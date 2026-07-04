import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/core/api/api_client.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/services/commentary_cache.dart';
import 'package:cricpro_flutter/utils/team_format.dart';
import 'package:cricpro_flutter/widgets/minimized_score_bar.dart';
import 'package:cricpro_flutter/services/floating_score_overlay_service.dart';
import 'package:cricpro_flutter/services/analytics_service.dart';
import 'package:cricpro_flutter/screens/player/player_detail_screen.dart';
import 'package:cricpro_flutter/screens/match_details/widgets/live_match_tab.dart';
import 'package:cricpro_flutter/screens/match_details/widgets/match_details_ui.dart';
import 'package:cricpro_flutter/widgets/squad.dart';

part 'widgets/md_panels.dart';
part 'widgets/md_info.dart';
part 'widgets/md_timeline.dart';

class MatchDetailsScreen extends StatefulWidget {
  const MatchDetailsScreen({super.key, this.onWatchLive, this.matchId = ''});

  /// Invoked when the user taps Watch Live. Receives the resolved matchId
  /// so the host can navigate to the Live Player for the specific match.
  final ValueChanged<String>? onWatchLive;
  final String matchId;

  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends State<MatchDetailsScreen>
    with WidgetsBindingObserver {
  // Tab indices for the fixed tab order: Info, Live, Scorecard, Squad,
  // Commentary, Overs.
  static const int _infoTab = 0;
  static const int _liveTab = 1;
  static const int _scoreTab = 2;

  int tab = _infoTab;
  final CricketRepository _repository = CricketRepository();
  final ScrollController _scrollController = ScrollController();
  final Map<int, Future<ApiEnvelope<Map<String, dynamic>>>> _tabFutures = {};
  final Map<int, Map<String, dynamic>> _tabData = {};
  Future<ApiEnvelope<Map<String, dynamic>>>? _summaryFuture;
  Map<String, dynamic>? _summaryData;
  Timer? _pollTimer;
  // Self-healing watchdog: when polling is paused by a transient network error
  // it is re-armed after a short delay instead of being cancelled forever (the
  // old behaviour, which froze the score until a manual pull-to-refresh).
  Timer? _recoveryTimer;
  int _consecutivePollFailures = 0;
  DateTime? _lastUpdatedAt;
  String? _initializedMatchId;
  bool _polling = false;

  /// Whether the last summary/tab response was served from STALE cache (a
  /// refresh is retrying) — surfaced in the "Updated X ago" row as
  /// "Stale data, retrying". Reset to false on a fresh successful response.
  bool _isStale = false;

  /// True while the network is unreachable and data is coming from offline
  /// cache — surfaced as "Offline cache". Set on a network failure, cleared on
  /// a successful response.
  bool _isOffline = false;

  /// True once the user has manually tapped a tab. Until then we are allowed
  /// to auto-select the Live tab for live/finished matches.
  bool _userPickedTab = false;

  /// Guards the one-time initial tab selection per match.
  bool _initialTabApplied = false;

  String get _matchId {
    final routeArg = ModalRoute.of(context)?.settings.arguments;
    if (routeArg is String && routeArg.isNotEmpty) return routeArg;
    return widget.matchId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_matchId.isNotEmpty && _initializedMatchId != _matchId) {
      WidgetsBinding.instance.addObserver(this);
      // Opening a different match: drop the previous match's accumulated
      // commentary so its items never leak into this one.
      if (_initializedMatchId != null && _initializedMatchId!.isNotEmpty) {
        CommentaryCache.instance.clearMatch(_initializedMatchId!);
      }
      _initializedMatchId = _matchId;
      // Fire once per match open (guarded by the _initializedMatchId check).
      AnalyticsService.instance.track('match_open', {'match_id': _matchId});
      AnalyticsService.instance.screenView('match_details');
      _tabFutures.clear();
      _tabData.clear();
      _summaryData = null;
      _initialTabApplied = false;
      _userPickedTab = false;
      _pollTimer?.cancel();
      // Resolve the initial tab synchronously from the last-known phase (captured
      // when the match was parsed for the list/feed the user tapped) so there is
      // no first-frame flash on Info before the detail summary loads:
      //   live → Live, finished → Scorecard, upcoming/unknown → Info.
      tab = _initialTabFor(CricketMatch.knownPhase(_matchId));
      _tabFutures[tab] = _loadTab(tab);
      // The Live tab also surfaces scorecard-derived performers, so preload it.
      if (tab == _liveTab) {
        _tabFutures.putIfAbsent(_scoreTab, () => _loadTab(_scoreTab));
      }
      _summaryFuture = _loadSummary();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _recoveryTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _configurePolling(_summaryData);
      // Resume with an immediate refresh so a match watched from the Live/Comm
      // tab catches up instantly instead of waiting for the next 5s tick.
      if (_pollTimer != null) _silentPollLiveMatch();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _pollTimer?.cancel();
      _pollTimer = null;
      _recoveryTimer?.cancel();
      _recoveryTimer = null;
    }
  }

  /// A match in a TERMINAL state will never produce more live updates, so
  /// polling should stop permanently. Transient non-live reads (innings break,
  /// rain, a one-off empty payload) must NOT stop polling.
  bool _isTerminalMatchData(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return false;
    final status = apiString(data['status'] ?? data['state']).toLowerCase();
    return status == 'completed' ||
        status == 'complete' ||
        status == 'finished' ||
        status == 'result' ||
        status == 'abandoned' ||
        status == 'no_result' ||
        status == 'cancelled' ||
        status == 'canceled';
  }

  Future<ApiEnvelope<Map<String, dynamic>>> _loadSummary({
    bool forceRefresh = false,
  }) async {
    final response =
        await _repository.matchDetail(_matchId, forceRefresh: forceRefresh);
    _summaryData = response.data;
    _maybeApplyInitialTab(response.data);
    _configurePolling(response.data);
    return response;
  }

  /// Builds the hero match from the loaded detail [data], backfilled from the
  /// last-known good summary captured when the user tapped the card. This keeps
  /// real teams/venue/series even when the `/match/:id` payload is thin, and a
  /// refresh updates the score without ever regressing to "TBD vs TBD".
  CricketMatch _matchFromDetail(Map<String, dynamic> data) {
    final detail = CricketMatch.fromJson(data);
    return detail.fillFrom(CricketMatch.knownSummary(_matchId));
  }

  /// Parses a sortable over.ball value from a normalized commentary item.
  /// Handles both the fast `/comm` shape (`over` int + `ball`) and the
  /// full-commentary shape (`over` = "8.4"). Returns null for notes.
  double? _commItemOver(Map<String, dynamic> m) {
    final overRaw = m['over'] ?? m['overNumber'] ?? m['over_number'];
    final ballRaw = m['ball'] ?? m['ballNumber'] ?? m['ball_number'];
    final overStr = '${overRaw ?? ''}'.trim();
    if (overStr.isEmpty) return null;
    final overNum = double.tryParse(overStr);
    if (overNum == null) return null;
    if (overStr.contains('.')) return overNum;
    final ball = int.tryParse('${ballRaw ?? ''}'.trim()) ?? 0;
    return overNum + ball / 10.0;
  }

  /// Latest (highest) over present in a commentary list.
  double? _latestCommentaryOver(List<dynamic> items) {
    double? best;
    for (final raw in items) {
      if (raw is! Map) continue;
      final o = _commItemOver(Map<String, dynamic>.from(raw));
      if (o == null) continue;
      if (best == null || o > best) best = o;
    }
    return best;
  }

  /// Current live over taken from the fresh score summary (max overs across
  /// both teams' innings). Used only for the freshness-compare debug log.
  double? _scoreOver(Map<String, dynamic> summary) {
    double? best;
    void scan(dynamic team) {
      if (team is! Map) return;
      final inns = team['innings'] ?? team['inns'];
      final list = inns is List ? inns : (inns == null ? const [] : [inns]);
      for (final i in list) {
        if (i is! Map) continue;
        final o = double.tryParse('${i['overs'] ?? i['o'] ?? ''}'.trim());
        if (o != null && (best == null || o > best!)) best = o;
      }
    }

    scan(summary['team1'] ?? summary['teamA']);
    scan(summary['team2'] ?? summary['teamB']);
    return best;
  }

  /// Debug-only freshness probe (Task 3/7): logs the live score over vs the
  /// latest commentary over and whether commentary is lagging beyond a
  /// format-aware threshold. No secrets. The fast `/app/live-commentary` source
  /// is already the freshest provider feed, so this proves whether any residual
  /// lag is provider-side rather than app/cache-side.
  void _logCommentaryFreshness(
      int currentTab, Map<String, dynamic> summary, Map<String, dynamic> commData) {
    if (!kDebugMode) return;
    final items = apiList(commData['items'] ??
        commData['data'] ??
        commData['commentary'] ??
        commData['commentaryList']);
    final scoreOver = _scoreOver(summary);
    final commOver = _latestCommentaryOver(items);
    final source = apiString(commData['source'], 'comm');
    // Backend already arbitrated sources and computed provider lag against the
    // live score (ball-index, not decimal). Prefer its verdict; fall back to a
    // local compare if the field is absent (older backend).
    final backendLag = commData['providerLag'] == true;
    final tabName = currentTab == _liveTab ? 'Live' : 'Comm';
    var localLag = false;
    if (scoreOver != null && commOver != null) {
      // T20 (<=20 ov innings) tolerates 1 over; ODI/Test 2 overs.
      final threshold = scoreOver <= 20.0 ? 1.0 : 2.0;
      localLag = (scoreOver - commOver) > threshold;
    }
    final providerLag = backendLag || localLag;
    final completeHistory = commData['completeHistory'] == true;
    // Filter tallies on the COMPLETE merged list, so QA can confirm Wickets /
    // Boundaries / Key Events are populated (and not falsely empty).
    var wickets = 0, boundaries = 0, keyEvents = 0;
    for (final raw in items) {
      final row = apiMap(raw);
      final type = str(row['type']).toLowerCase();
      final isBall = truthy(row['isBall']) || truthy(row['is_ball']);
      final isWicket = truthy(row['isWicket']) || type == 'wicket';
      final isBoundary =
          truthy(row['isBoundary']) || type == 'four' || type == 'six';
      if (isBall && isWicket) wickets++;
      if (isBall && isBoundary) boundaries++;
      if (truthy(row['isKeyEvent']) || truthy(row['is_key_event'])) keyEvents++;
    }
    debugPrint(
        'CricProCommentaryPoll: match=$_matchId tab=$tabName items=${items.length} all=${items.length} wickets=$wickets boundaries=$boundaries keyEvents=$keyEvents scoreOver=${commData['scoreOver'] ?? scoreOver ?? '-'} latestCommentaryOver=${commOver ?? '-'} source=$source completeHistory=$completeHistory providerLag=$providerLag applied=true');
  }

  /// Initial tab for a coarse [phase] hint resolved before the detail summary
  /// loads: live → Live, finished → Scorecard, upcoming/unknown → Info.
  int _initialTabFor(MatchPhase? phase) {
    switch (phase) {
      case MatchPhase.live:
        return _liveTab;
      case MatchPhase.finished:
        return _scoreTab;
      case MatchPhase.upcoming:
      case null:
        return _infoTab;
    }
  }

  /// Authoritative initial tab from the loaded detail summary [data].
  int _tabForSummary(Map<String, dynamic> data) {
    final status = apiString(data['status'] ?? data['state']).toLowerCase();
    final isUpcoming = status == 'upcoming' ||
        status == 'scheduled' ||
        status == 'not_started' ||
        status == 'preview' ||
        status.isEmpty && !_isLiveMatchData(data);
    if (isUpcoming) return _infoTab;
    if (_isTerminalMatchData(data)) return _scoreTab;
    return _liveTab;
  }

  /// Confirms / corrects the initial tab once the real summary arrives. The tab
  /// was already seeded synchronously from the cached phase, so in the common
  /// case this is a no-op (no flash). Only corrects a stale seed, and never
  /// overrides a tab the user already picked. Does NOT scroll the page.
  void _maybeApplyInitialTab(Map<String, dynamic>? data) {
    if (_initialTabApplied || _userPickedTab || data == null) return;
    _initialTabApplied = true;
    final target = _tabForSummary(data);
    if (tab == target) {
      // Seed was correct; just make sure Live's scorecard dependency is loaded.
      if (target == _liveTab &&
          _matchId.isNotEmpty &&
          !_tabData.containsKey(_scoreTab)) {
        _loadTab(_scoreTab).then((_) {
          if (mounted) setState(() {});
        });
      }
      return;
    }
    // Defer to after the current build to safely switch tabs + preload data.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userPickedTab) return;
      setState(() {
        tab = target;
        if (_matchId.isNotEmpty) {
          _tabFutures.putIfAbsent(target, () => _loadTab(target));
        }
      });
      // The Live tab also uses the scorecard for finished-match performers.
      if (target == _liveTab &&
          _matchId.isNotEmpty &&
          !_tabData.containsKey(_scoreTab)) {
        _loadTab(_scoreTab).then((_) {
          if (mounted) setState(() {});
        });
      }
    });
  }

  Future<ApiEnvelope<Map<String, dynamic>>> _loadTab(int index,
      {bool forceRefresh = false}) async {
    final id = _matchId;
    if (kDebugMode && index == 1) {
      debugPrint('[MatchDetails] Loading live-center for $id');
    }
    final response = await switch (index) {
      // New tab order: Info, Live, Scorecard, Squad, Commentary, Overs.
      0 => _repository.matchDetail(id, forceRefresh: forceRefresh),
      // Live tab (1) uses the merged Live Center object from the backend,
      // which already contains current batters, bowler, partnership, last
      // wicket, recent balls and latest commentary (with scorecard/commentary
      // fallbacks merged server-side).
      1 => _repository.matchLiveCenter(id, forceRefresh: forceRefresh),
      2 => _repository.matchScorecard(id, forceRefresh: forceRefresh),
      3 => _repository.matchSquads(id, forceRefresh: forceRefresh),
      // Commentary tab uses the FAST live-commentary source (freshest provider
      // feed, short TTL + single-flight) merged through the no-removal cache.
      4 => _repository.matchLiveCommentary(id, forceRefresh: forceRefresh),
      _ => _repository.matchOvers(id, forceRefresh: forceRefresh),
    };
    _tabData[index] = response.data;
    if (kDebugMode && index == 1) {
      final keys = response.data.keys.toList();
      final live = apiMap(response.data['data'] ??
          response.data['liveCenter'] ??
          response.data['live_center'] ??
          response.data);
      debugPrint('[MatchDetails] live-center loaded: $keys');
      debugPrint(
          '[MatchDetails] live-center counts: currentBatters=${apiList(live['current_batters'] ?? live['currentBatters']).length}, '
          'currentBowler=${apiMap(live['current_bowler'] ?? live['currentBowler']).isNotEmpty}, '
          'recentBalls=${apiList(live['recent_balls'] ?? live['recentBalls']).length}, '
          'commentary=${apiList(live['commentary'] ?? live['commentaryList']).length}');
    }
    return response;
  }

  void _setTab(int value) {
    setState(() {
      _userPickedTab = true;
      tab = value;
      if (_matchId.isNotEmpty) {
        _tabFutures.putIfAbsent(value, () => _loadTab(value));
      }
    });
    // The Live tab (1) also draws top performers / final scores from the
    // scorecard when a match is completed. Make sure the scorecard (now tab 2)
    // is loaded even if the user jumps straight to Live.
    if (value == 1 && _matchId.isNotEmpty && !_tabData.containsKey(2)) {
      _loadTab(2).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _refreshCurrentTab() async {
    if (_matchId.isEmpty) return;
    final oldOffset =
        _scrollController.hasClients ? _scrollController.offset : null;
    final summary = _loadSummary(forceRefresh: true);
    final current = _loadTab(tab, forceRefresh: true);
    final scorecard = tab == 2
        ? current
        : _repository.matchScorecard(_matchId, forceRefresh: true);
    final liveCenter = tab == 1
        ? current
        : _repository.matchLiveCenter(_matchId, forceRefresh: true);
    final commentary = tab == 4
        ? current
        : _repository.matchLiveCommentary(_matchId, forceRefresh: true);
    final overs = tab == 5
        ? current
        : _repository.matchOvers(_matchId, forceRefresh: true);
    final results = await Future.wait<dynamic>(
        [summary, current, scorecard, liveCenter, commentary, overs]);
    if (!mounted) return;
    final summaryEnvelope =
        results[0] as ApiEnvelope<Map<String, dynamic>>;
    setState(() {
      _summaryFuture = Future.value(summaryEnvelope);
      _tabFutures[tab] =
          Future.value(results[1] as ApiEnvelope<Map<String, dynamic>>);
      _tabFutures[2] = Future.value(
          results[2] as ApiEnvelope<Map<String, dynamic>>); // Scorecard
      _tabFutures[1] = Future.value(
          results[3] as ApiEnvelope<Map<String, dynamic>>); // Live center
      _tabFutures[4] = Future.value(
          results[4] as ApiEnvelope<Map<String, dynamic>>); // Commentary
      _tabFutures[5] = Future.value(
          results[5] as ApiEnvelope<Map<String, dynamic>>); // Overs
      _lastUpdatedAt = DateTime.now();
      // A successful manual refresh clears the offline flag; reflect staleness
      // from the envelope meta so the "Updated X ago" row stays accurate.
      _isOffline = false;
      _isStale = summaryEnvelope.meta.isStale;
    });
    _restoreScroll(oldOffset);
    // If polling was paused by an offline back-off, resume it now that the
    // network is reachable again and the match is still live.
    if (mounted && _pollTimer == null) _configurePolling(_summaryData);
  }

  void _configurePolling(Map<String, dynamic>? matchData) {
    if (!mounted) return;
    // Terminal match: stop everything, for good.
    if (_isTerminalMatchData(matchData)) {
      _pollTimer?.cancel();
      _pollTimer = null;
      _recoveryTimer?.cancel();
      _recoveryTimer = null;
      if (kDebugMode) {
        debugPrint('[Polling] MatchDetails terminal — polling stopped');
      }
      return;
    }
    final shouldPoll = _isLiveMatchData(matchData);
    if (!shouldPoll) {
      // Not live yet (upcoming) and not terminal. Don't run the fast loop, but
      // if we have no data at all keep a slow watchdog so a match starting while
      // the user watches is picked up without a manual refresh.
      _pollTimer?.cancel();
      _pollTimer = null;
      if (matchData == null || matchData.isEmpty) {
        _armRecovery();
      }
      if (kDebugMode) {
        debugPrint('[Polling] MatchDetails live=false interval=none');
      }
      return;
    }
    if (_pollTimer != null) return;
    if (kDebugMode) {
      debugPrint('[Polling] MatchDetails live=true interval=5s');
    }
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _silentPollLiveMatch(),
    );
  }

  /// Re-arm polling after a transient failure / non-live blip instead of giving
  /// up forever. Single-shot; cleared once it fires or polling resumes.
  void _armRecovery() {
    if (!mounted || _recoveryTimer != null || _pollTimer != null) return;
    final delay = Duration(
      seconds: (5 + 5 * _consecutivePollFailures).clamp(5, 30),
    );
    _recoveryTimer = Timer(delay, () async {
      _recoveryTimer = null;
      if (!mounted || _matchId.isEmpty) return;
      try {
        final summary =
            await _repository.matchDetail(_matchId, forceRefresh: true);
        if (!mounted) return;
        _summaryData = summary.data;
        _consecutivePollFailures = 0;
        _configurePolling(summary.data);
      } catch (_) {
        _consecutivePollFailures++;
        _armRecovery();
      }
    });
  }

  Future<void> _silentPollLiveMatch() async {
    if (_polling || !mounted || _matchId.isEmpty) return;
    _polling = true;
    final oldOffset =
        _scrollController.hasClients ? _scrollController.offset : null;
    if (kDebugMode) {
      debugPrint('[Polling] silent refresh start offset=$oldOffset tab=$tab');
    }
    try {
      final summary =
          await _repository.matchDetail(_matchId, forceRefresh: true);
      if (!mounted) return;
      _consecutivePollFailures = 0;
      // A successful response clears the offline flag; track staleness from the
      // envelope meta so the "Updated X ago" row can say "Stale data, retrying".
      _isOffline = false;
      _isStale = summary.meta.isStale;
      final currentTab = tab;
      final previousTabData = _tabData[currentTab];
      // Refresh the visible tab's own payload. Live(1)/Scorecard(2) and
      // Info(0)/Squad(3) via _loadTab; Commentary(4)/Overs(5) refresh their
      // dedicated repo calls so those tabs do not freeze during live play.
      ApiEnvelope<Map<String, dynamic>>? tabResponse;
      if (currentTab <= 3) {
        tabResponse = await _loadTab(currentTab, forceRefresh: true);
        // The Live tab's commentary preview reads from the accumulated
        // commentary feed (fresher than the merged live-center, which lags
        // 1–2 balls). Refresh it from the FAST live-commentary source so the
        // preview stays current without switching tabs.
        if (currentTab == _liveTab) {
          try {
            final fc = await _repository.matchLiveCommentary(_matchId,
                forceRefresh: true);
            _tabData[4] = fc.data;
            _logCommentaryFreshness(currentTab, summary.data, fc.data);
          } catch (_) {
            // Non-fatal — the preview falls back to live-center commentary.
          }
        }
      } else if (currentTab == 4) {
        tabResponse =
            await _repository.matchLiveCommentary(_matchId, forceRefresh: true);
        _tabData[4] = tabResponse.data;
        _logCommentaryFreshness(currentTab, summary.data, tabResponse.data);
      } else if (currentTab == 5) {
        tabResponse =
            await _repository.matchOvers(_matchId, forceRefresh: true);
        _tabData[5] = tabResponse.data;
      }
      if (!mounted) return;
      final summaryChanged = _jsonChanged(_summaryData, summary.data);
      final tabChanged = tabResponse != null &&
          _jsonChanged(previousTabData, tabResponse.data);
      _summaryData = summary.data;
      // Keep a minimized floating bar (if this match is the one minimized) in
      // sync with the live poll, so it updates without pull-to-refresh.
      MinimizedScoreController.instance
          .update(CricketMatch.fromJson(summary.data));
      // Stop only on a TERMINAL state. Innings breaks / stoppages keep polling.
      if (_isTerminalMatchData(summary.data)) {
        _pollTimer?.cancel();
        _pollTimer = null;
        _recoveryTimer?.cancel();
        _recoveryTimer = null;
      }
      if (summaryChanged || tabChanged) {
        setState(() {
          if (tabResponse != null) {
            _tabFutures[currentTab] = Future.value(tabResponse);
          }
          _lastUpdatedAt = DateTime.now();
        });
        _restoreScroll(oldOffset);
      }
      if (kDebugMode) {
        debugPrint(
            '[Polling] silent refresh changed=${summaryChanged || tabChanged}');
      }
    } catch (_) {
      // Network failure while polling — pause the fast loop but DO NOT give up.
      // Arm a self-healing recovery timer so live updates resume automatically
      // once the network is reachable again, without a manual pull-to-refresh.
      _consecutivePollFailures++;
      _pollTimer?.cancel();
      _pollTimer = null;
      // Surface the offline state in the "Updated X ago" row so the user knows
      // the shown data is from cache, not a fresh fetch.
      if (mounted) {
        setState(() {
          _isOffline = true;
          _isStale = true;
        });
      }
      _armRecovery();
    } finally {
      _polling = false;
    }
  }

  void _restoreScroll(double? oldOffset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Only restore scroll offset. The selected tab is plain state that survives
      // rebuilds on its own, so forcing it back here would clobber a tab the user
      // tapped while a poll/refresh was mid-flight.
      if (oldOffset != null && _scrollController.hasClients) {
        final restoredOffset = oldOffset.clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(restoredOffset);
        if (kDebugMode) {
          debugPrint('[Polling] restored offset=$restoredOffset');
        }
      }
    });
  }

  bool _jsonChanged(Map<String, dynamic>? oldData, Map<String, dynamic> next) {
    if (oldData == null) return true;
    return jsonEncode(oldData) != jsonEncode(next);
  }

  bool _isLiveMatchData(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return false;
    final match = CricketMatch.fromJson(data);
    if (match.isLive) return true;
    final status = apiString(data['status'] ?? data['state']).toLowerCase();
    return status == 'live' ||
        status == 'inprogress' ||
        status == 'in_progress' ||
        status == 'progress';
  }

  /// Minimize chooser: in-app bar (default) or the optional Android floating
  /// overlay. The overlay path is offered only on Android; if its permission is
  /// missing we explain and open the system settings, falling back to the
  /// in-app bar when denied.
  Future<void> _showMinimizeOptions() async {
    final data = _summaryData;
    if (data == null) return;
    final match = CricketMatch.fromJson(data);
    final overlay = FloatingScoreOverlay.instance;
    final overlaySupported = await overlay.isSupported();
    if (!mounted) return;

    void minimizeInApp() {
      MinimizedScoreController.instance.show(match);
      Navigator.pop(context); // close detail screen
    }

    if (!overlaySupported) {
      // No overlay on this platform/device — keep the original behavior.
      minimizeInApp();
      return;
    }

    final c = context.cric;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              gradient: c.cardGradient,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.minimize_rounded, color: c.cyan),
                  title: Text('Minimize in app',
                      style: TextStyle(
                          color: c.text, fontWeight: FontWeight.w700)),
                  subtitle: Text('Keep a score bar inside CricPro',
                      style: TextStyle(color: c.muted, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    minimizeInApp();
                  },
                ),
                Divider(color: c.border, height: 1),
                ListTile(
                  leading: Icon(Icons.picture_in_picture_alt_rounded,
                      color: c.cyan),
                  title: Text('Floating score over other apps',
                      style: TextStyle(
                          color: c.text, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      'Shows a small live cricket score bubble while you use other apps.',
                      style: TextStyle(color: c.muted, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _enableFloatingScore(match);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Enables the floating overlay for [match]. Requests permission on first use,
  /// then starts the bubble. Falls back to the in-app bar if permission is
  /// denied or the service refuses to start.
  Future<void> _enableFloatingScore(CricketMatch match) async {
    final overlay = FloatingScoreOverlay.instance;
    var granted = await overlay.hasPermission();
    if (!granted) {
      granted = await overlay.requestPermission();
      // The user may still be choosing on the system screen; re-check once.
      if (!granted) granted = await overlay.hasPermission();
    }
    if (!mounted) return;
    if (!granted) {
      // Denied — graceful fallback to the in-app minimizer.
      MinimizedScoreController.instance.show(match);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permission needed — using in-app score bar instead.'),
        ),
      );
      Navigator.pop(context);
      return;
    }
    final started = await overlay.start(match);
    if (!mounted) return;
    if (started) {
      // Avoid duplicate UI: don't also show the in-app bar.
      MinimizedScoreController.instance.clear();
      Navigator.pop(context);
    } else {
      MinimizedScoreController.instance.show(match);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refreshCurrentTab,
            child: ListView(
              controller: _scrollController,
              padding: EdgeInsets.fromLTRB(context.horizontalPadding, 10,
                  context.horizontalPadding, context.detailBottomPadding),
              children: [
                MatchDetailsTopBar(
                  onBack: () => Navigator.pop(context),
                  onMinimize:
                      _summaryData != null ? _showMinimizeOptions : null,
                ),
                const SizedBox(height: 12),
                if (_matchId.isNotEmpty)
                  _summaryData != null
                      ? MatchHeroScoreCard(match: _matchFromDetail(_summaryData!))
                      : FutureBuilder<ApiEnvelope<Map<String, dynamic>>>(
                          future: _summaryFuture,
                          builder: (context, snapshot) {
                            final data = snapshot.data?.data;
                            if (data == null) {
                              // Render the known summary (teams/venue/series the
                              // user just saw) immediately while the detail loads
                              // or if it fails — never a bare spinner or "TBD".
                              final known =
                                  CricketMatch.knownSummary(_matchId);
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                if (known != null) {
                                  return MatchHeroScoreCard(match: known);
                                }
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 32),
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                );
                              }
                              if (snapshot.hasError) {
                                if (known != null) {
                                  return MatchHeroScoreCard(match: known);
                                }
                                final isOffline = snapshot.error
                                        is ApiClientException &&
                                    (snapshot.error as ApiClientException)
                                        .isNetwork;
                                if (isOffline) {
                                  return CricOfflineCard(
                                    onRetry: _refreshCurrentTab,
                                  );
                                }
                                return PremiumCard(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    'Something went wrong. Pull to refresh.',
                                    style:
                                        TextStyle(color: c.muted, height: 1.5),
                                  ),
                                );
                              }
                              if (known != null) {
                                return MatchHeroScoreCard(match: known);
                              }
                              return PremiumCard(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'Match details are not available yet.',
                                  style: TextStyle(color: c.muted, height: 1.5),
                                ),
                              );
                            }
                            return MatchHeroScoreCard(
                                match: _matchFromDetail(data));
                          },
                        )
                else
                  PremiumCard(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No match selected. Open a live or upcoming match from the Home or Matches screen.',
                      style: TextStyle(color: c.muted, height: 1.5),
                    ),
                  ),
                const SizedBox(height: 10),
                _RefreshStatusRow(
                  lastUpdatedAt: _lastUpdatedAt,
                  onRefresh: _refreshCurrentTab,
                  isStale: _isStale,
                  isOffline: _isOffline,
                ),
                const SizedBox(height: 10),
                MatchDetailsTabBar(
                  items: const [
                    ('Info', Icons.info_outline_rounded, MDAsset.tabInfo),
                    ('Live', Icons.podcasts_rounded, MDAsset.tabLive),
                    ('Score', Icons.scoreboard_outlined, MDAsset.tabScorecard),
                    ('Squad', Icons.groups_rounded, MDAsset.tabSquad),
                    (
                      'Comm',
                      Icons.chat_bubble_outline_rounded,
                      MDAsset.tabCommentary
                    ),
                    ('Overs', Icons.sports_cricket_rounded, MDAsset.tabOvers),
                  ],
                  selected: tab,
                  onChanged: _setTab,
                ),
                const SizedBox(height: 12),
                if (_matchId.isNotEmpty && _tabFutures[tab] != null) ...[
                  // Debug info - hidden in production
                  // _ApiTabStatus(future: _tabFutures[tab]!),
                  // const SizedBox(height: 16),
                ],
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: child,
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(tab),
                    child: _matchId.isNotEmpty && _tabFutures[tab] != null
                        ? _tabData.containsKey(tab)
                            ? _ApiMatchTabDataContent(
                                tab: tab,
                                data: _tabData[tab]!,
                                summaryData: _summaryData,
                                scorecardData: _tabData[2],
                                matchStatus:
                                    _summaryData?['status']?.toString(),
                                fullCommentaryData: _tabData[4],
                                fallbackSummary:
                                    CricketMatch.knownSummary(_matchId),
                                onViewMoreCommentary: () => _setTab(4),
                              )
                            : _ApiMatchTabFutureContent(
                                tab: tab,
                                future: _tabFutures[tab]!,
                                summaryData: _summaryData,
                                scorecardData: _tabData[2],
                                matchStatus:
                                    _summaryData?['status']?.toString(),
                                fullCommentaryData: _tabData[4],
                                fallbackSummary:
                                    CricketMatch.knownSummary(_matchId),
                                onViewMoreCommentary: () => _setTab(4),
                              )
                        : PremiumCard(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No match selected.',
                              style: TextStyle(color: c.muted, height: 1.5),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

