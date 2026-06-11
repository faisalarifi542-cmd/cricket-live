import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/screens/player/player_detail_screen.dart';
import 'package:cricpro_flutter/screens/match_details/widgets/live_match_tab.dart';
import 'package:cricpro_flutter/screens/match_details/widgets/match_details_ui.dart';
import 'package:cricpro_flutter/widgets/squad.dart';

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
  int tab = 0;
  final CricketRepository _repository = CricketRepository();
  final ScrollController _scrollController = ScrollController();
  final Map<int, Future<ApiEnvelope<Map<String, dynamic>>>> _tabFutures = {};
  final Map<int, Map<String, dynamic>> _tabData = {};
  Future<ApiEnvelope<Map<String, dynamic>>>? _summaryFuture;
  Map<String, dynamic>? _summaryData;
  Timer? _pollTimer;
  DateTime? _lastUpdatedAt;
  String? _initializedMatchId;
  bool _polling = false;

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
      _initializedMatchId = _matchId;
      _tabFutures.clear();
      _tabData.clear();
      _summaryData = null;
      _initialTabApplied = false;
      _userPickedTab = false;
      _pollTimer?.cancel();
      _tabFutures[tab] = _loadTab(tab);
      _summaryFuture = _loadSummary();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _configurePolling(_summaryData);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
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

  /// Opens the Live tab by default for Live and Finished matches (the Live tab
  /// becomes the live center / result summary). Upcoming matches keep the
  /// default Scorecard tab. Runs once per match and never overrides a tab the
  /// user has already chosen. Does NOT scroll the page.
  void _maybeApplyInitialTab(Map<String, dynamic>? data) {
    if (_initialTabApplied || _userPickedTab || data == null) return;
    final status = apiString(data['status'] ?? data['state']).toLowerCase();
    final isUpcoming = status == 'upcoming' ||
        status == 'scheduled' ||
        status == 'not_started' ||
        status == 'preview' ||
        status.isEmpty && !_isLiveMatchData(data);
    if (isUpcoming) {
      _initialTabApplied = true;
      return;
    }
    _initialTabApplied = true;
    const liveTab = 1;
    if (tab == liveTab) return;
    // Defer to after the current build to safely switch tabs + preload data.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userPickedTab) return;
      setState(() {
        tab = liveTab;
        if (_matchId.isNotEmpty) {
          _tabFutures.putIfAbsent(liveTab, () => _loadTab(liveTab));
        }
      });
      // The Live tab also uses the scorecard for finished-match performers.
      if (_matchId.isNotEmpty && !_tabData.containsKey(2)) {
        _loadTab(2).then((_) {
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
      4 => _repository.matchFullCommentary(id, forceRefresh: forceRefresh),
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
    final oldTab = tab;
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
        : _repository.matchFullCommentary(_matchId, forceRefresh: true);
    final overs = tab == 5
        ? current
        : _repository.matchOvers(_matchId, forceRefresh: true);
    final results = await Future.wait<dynamic>(
        [summary, current, scorecard, liveCenter, commentary, overs]);
    if (!mounted) return;
    setState(() {
      _summaryFuture =
          Future.value(results[0] as ApiEnvelope<Map<String, dynamic>>);
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
    });
    _restoreScrollAndTab(oldOffset, oldTab);
  }

  void _configurePolling(Map<String, dynamic>? matchData) {
    final shouldPoll = _isLiveMatchData(matchData);
    if (!mounted) return;
    if (!shouldPoll) {
      _pollTimer?.cancel();
      _pollTimer = null;
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

  Future<void> _silentPollLiveMatch() async {
    if (_polling || !mounted || _matchId.isEmpty) return;
    if (!_isLiveMatchData(_summaryData)) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    _polling = true;
    final oldOffset =
        _scrollController.hasClients ? _scrollController.offset : null;
    final oldTab = tab;
    if (kDebugMode) {
      debugPrint(
          '[Polling] silent refresh start offset=$oldOffset tab=$oldTab');
    }
    try {
      final summary =
          await _repository.matchDetail(_matchId, forceRefresh: true);
      if (!mounted) return;
      final stillLive = _isLiveMatchData(summary.data);
      final currentTab = tab;
      final previousTabData = _tabData[currentTab];
      ApiEnvelope<Map<String, dynamic>>? tabResponse;
      if (currentTab <= 3) {
        tabResponse = await _loadTab(currentTab, forceRefresh: true);
      }
      if (!mounted) return;
      final summaryChanged = _jsonChanged(_summaryData, summary.data);
      final tabChanged = tabResponse != null &&
          _jsonChanged(previousTabData, tabResponse.data);
      _summaryData = summary.data;
      if (!stillLive) {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
      if (summaryChanged || tabChanged) {
        setState(() {
          _lastUpdatedAt = DateTime.now();
        });
        _restoreScrollAndTab(oldOffset, oldTab);
      }
      if (kDebugMode) {
        debugPrint(
            '[Polling] silent refresh changed=${summaryChanged || tabChanged}');
      }
    } finally {
      _polling = false;
    }
  }

  void _restoreScrollAndTab(double? oldOffset, int oldTab) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (tab != oldTab) {
        setState(() => tab = oldTab);
      }
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
                  onFilter: () {},
                ),
                const SizedBox(height: 12),
                if (_matchId.isNotEmpty)
                  _summaryData != null
                      ? MatchHeroScoreCard(
                          match: CricketMatch.fromJson(_summaryData!))
                      : FutureBuilder<ApiEnvelope<Map<String, dynamic>>>(
                          future: _summaryFuture,
                          builder: (context, snapshot) {
                            final data = snapshot.data?.data;
                            if (data == null) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 32),
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                );
                              }
                              return PremiumCard(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  snapshot.hasError
                                      ? 'Unable to load this match right now. Pull to refresh.'
                                      : 'Match details are not available yet.',
                                  style: TextStyle(color: c.muted, height: 1.5),
                                ),
                              );
                            }
                            return MatchHeroScoreCard(
                                match: CricketMatch.fromJson(data));
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
                              )
                            : _ApiMatchTabFutureContent(
                                tab: tab,
                                future: _tabFutures[tab]!,
                                summaryData: _summaryData,
                                scorecardData: _tabData[2],
                                matchStatus:
                                    _summaryData?['status']?.toString(),
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

class _ApiMatchTabFutureContent extends StatelessWidget {
  const _ApiMatchTabFutureContent(
      {required this.tab,
      required this.future,
      this.summaryData,
      this.scorecardData,
      this.matchStatus});

  final int tab;
  final Future<ApiEnvelope<Map<String, dynamic>>> future;
  final Map<String, dynamic>? summaryData;
  final Map<String, dynamic>? scorecardData;
  final String? matchStatus;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ApiEnvelope<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const _MatchDataStateCard(
            icon: Icons.cloud_off_rounded,
            text:
                'This match data is temporarily unavailable. Pull to refresh.',
          );
        }
        final data = snapshot.data?.data ?? const <String, dynamic>{};
        return _ApiMatchTabDataContent(
          tab: tab,
          data: data,
          summaryData: summaryData,
          scorecardData: scorecardData,
          matchStatus: matchStatus,
        );
      },
    );
  }
}

class _ApiMatchTabDataContent extends StatelessWidget {
  const _ApiMatchTabDataContent(
      {required this.tab,
      required this.data,
      this.summaryData,
      this.scorecardData,
      this.matchStatus});

  final int tab;
  final Map<String, dynamic> data;
  final Map<String, dynamic>? summaryData;
  final Map<String, dynamic>? scorecardData;
  final String? matchStatus;

  @override
  Widget build(BuildContext context) {
    // The Live tab manages its own empty state and also draws from
    // summaryData, so it must build even when the live-center payload is empty.
    if (tab == 1) {
      return LiveMatchTab(
        summary: summaryData,
        liveCenter: data,
        scorecardData: scorecardData,
      );
    }
    if (data.isEmpty) {
      return _MatchDataStateCard(
        icon: tab == 3 ? Icons.groups_rounded : Icons.info_outline_rounded,
        text: _emptyText(tab, matchStatus),
      );
    }
    return switch (tab) {
      0 => _InfoPanel(data: data),
      2 => _ScorecardPanel(data: data, matchStatus: matchStatus),
      3 => _SquadsPanel(data: data),
      4 => _CommentaryPanel(data: data, matchStatus: matchStatus),
      _ => _OversPanel(data: data),
    };
  }

  static String _emptyText(int tab, String? status) {
    final isUpcoming = status == null ||
        status.toLowerCase() == 'upcoming' ||
        status.toLowerCase() == 'scheduled' ||
        status.toLowerCase() == 'not_started';

    return switch (tab) {
      0 => 'Match information is not available yet.',
      2 => isUpcoming
          ? 'Scorecard will be available once the match starts.'
          : 'Scorecard is not available from the provider yet.',
      3 => 'Squad has not been announced yet.',
      4 => isUpcoming
          ? 'Commentary will appear when the match starts.'
          : 'Commentary is not available from the provider yet.',
      _ => 'Over summaries are not available yet.',
    };
  }
}

class _RefreshStatusRow extends StatelessWidget {
  const _RefreshStatusRow({
    required this.lastUpdatedAt,
    required this.onRefresh,
  });

  final DateTime? lastUpdatedAt;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final label = lastUpdatedAt == null
        ? 'Pull to refresh'
        : DateTime.now().difference(lastUpdatedAt!).inSeconds < 10
            ? 'Updated just now'
            : 'Updated ${DateTime.now().difference(lastUpdatedAt!).inSeconds}s ago';
    return MDUpdatedRow(label: label, onRefresh: () => onRefresh());
  }
}

class _ScorecardPanel extends StatefulWidget {
  const _ScorecardPanel({required this.data, this.matchStatus});

  final Map<String, dynamic> data;
  final String? matchStatus;

  @override
  State<_ScorecardPanel> createState() => _ScorecardPanelState();
}

class _ScorecardPanelState extends State<_ScorecardPanel> {
  int selected = 0;
  bool _battingExpanded = false;
  bool _bowlingExpanded = false;

  @override
  void initState() {
    super.initState();
    selected = _preferredInningsIndex(widget.data);
  }

  @override
  void didUpdateWidget(covariant _ScorecardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      selected = _preferredInningsIndex(widget.data);
    }
  }

  int _preferredInningsIndex(Map<String, dynamic> data) {
    final innings = apiList(data['innings']);
    if (innings.isEmpty) return 0;
    final currentBatTeamId =
        str(data['curr_bat_team_id'] ?? data['currentBatTeamId']);
    if (currentBatTeamId.isEmpty) return 0;
    for (var i = 0; i < innings.length; i++) {
      final inn = apiMap(innings[i]);
      final batTeamId =
          str(inn['batting_team_id'] ?? inn['batTeamId'] ?? inn['teamId']);
      if (batTeamId.isNotEmpty && batTeamId == currentBatTeamId) {
        return i;
      }
    }
    return 0;
  }

  /// Builds the innings selector labels, de-duplicating teams that bat more
  /// than once (e.g. a Test) into "IND Inn 1 / AFG Inn 1 / AFG Inn 2".
  List<MDTeamSelectorItem> _inningsSelectorItems(List<dynamic> innings) {
    final shorts = <String>[];
    final counts = <String, int>{};
    for (final raw in innings) {
      final m = apiMap(raw);
      final name = str(m['teamName'] ?? m['batting_team'], fallback: 'Team');
      var short = str(m['teamShort'] ?? m['team_short'] ?? m['teamShortName']);
      if (short.isEmpty) {
        short = name.length >= 3
            ? name.substring(0, 3).toUpperCase()
            : name.toUpperCase();
      }
      shorts.add(short);
      counts[short] = (counts[short] ?? 0) + 1;
    }
    final multi = counts.values.any((v) => v > 1);
    final seen = <String, int>{};
    final items = <MDTeamSelectorItem>[];
    for (var i = 0; i < innings.length; i++) {
      final m = apiMap(innings[i]);
      final short = shorts[i];
      final name = str(m['teamName'] ?? m['batting_team'], fallback: short);
      final logo = str(m['logoUrl'] ?? m['logo_url']);
      final n = (seen[short] ?? 0) + 1;
      seen[short] = n;
      final ord = n == 1
          ? '1st'
          : n == 2
              ? '2nd'
              : n == 3
                  ? '3rd'
                  : '${n}th';
      items.add(MDTeamSelectorItem(
        // Single-innings teams show the full name when it fits; multi-innings
        // (Tests) use the short code + ordinal so both fit cleanly.
        label: multi
            ? '$short $ord Inn'
            : (name.length <= 14 ? name : short),
        name: name,
        logo: logo.isEmpty ? null : logo,
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final innings = apiList(widget.data['innings']);

    // Check if innings data is actually empty (no batting/bowling data)
    final hasData = innings.isNotEmpty &&
        innings.any((inn) {
          final inningsMap = apiMap(inn);
          final batting = apiList(inningsMap['batting'] ??
              inningsMap['batters'] ??
              inningsMap['batsmen']);
          final bowling =
              apiList(inningsMap['bowling'] ?? inningsMap['bowlers']);
          return batting.isNotEmpty || bowling.isNotEmpty;
        });

    if (!hasData) {
      final isUpcoming = widget.matchStatus == null ||
          widget.matchStatus!.toLowerCase() == 'upcoming' ||
          widget.matchStatus!.toLowerCase() == 'scheduled' ||
          widget.matchStatus!.toLowerCase() == 'not_started';

      return _MatchDataStateCard(
        icon: Icons.scoreboard_rounded,
        text: isUpcoming
            ? 'Scorecard will be available once the match starts.'
            : 'Scorecard data is not available yet.',
      );
    }
    final safeSelected = selected.clamp(0, innings.length - 1);
    final current = apiMap(innings[safeSelected]);
    final batting =
        apiList(current['batting'] ?? current['batters'] ?? current['batsmen']);
    final bowling = apiList(current['bowling'] ?? current['bowlers']);
    final battingRows =
        batting.map(apiMap).where(_shouldShowBatter).toList(growable: false);
    final yetToBatRows = _yetToBatRows(
      batting.map(apiMap).toList(growable: false),
      apiList(current['did_not_bat'] ??
          current['didNotBat'] ??
          current['yet_to_bat'] ??
          current['yetToBat']),
    );
    final bowlingRows =
        bowling.map(apiMap).where(_shouldShowBowler).toList(growable: false);
    final c = context.cric;

    const previewCount = 5;
    final battingVisible = _battingExpanded
        ? battingRows
        : battingRows.take(previewCount).toList(growable: false);
    final bowlingVisible = _bowlingExpanded
        ? bowlingRows
        : bowlingRows.take(previewCount).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (innings.length > 1)
          MDTeamSelector(
            items: _inningsSelectorItems(innings),
            selected: safeSelected,
            onChanged: (value) => setState(() {
              selected = value;
              _battingExpanded = false;
              _bowlingExpanded = false;
            }),
          ),
        if (innings.length > 1) const SizedBox(height: 10),
        _SectionCard(
          title:
              str(current['teamName'] ?? current['batting_team'] ?? 'Batting'),
          asset: MDAsset.icBatting,
          icon: Icons.sports_cricket_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatTable(
                headers: const ['Batter', 'R', 'B', '4s', '6s', 'SR'],
                rows: [
                  for (final row in battingVisible)
                    [
                      _batterCell(context, row),
                      Text(str(row['runs'], fallback: '0')),
                      Text(str(row['balls'], fallback: '0')),
                      Text(str(row['fours'], fallback: '0')),
                      Text(str(row['sixes'], fallback: '0')),
                      Text(_fmtStat(str(row['strike_rate'] ??
                          row['strikeRate']))),
                    ],
                ],
                empty: 'Batting card is not available yet.',
              ),
              if (battingRows.length > previewCount)
                _ViewAllButton(
                  label: _battingExpanded
                      ? 'Show Less'
                      : 'View All Batting (${battingRows.length})',
                  expanded: _battingExpanded,
                  onTap: () =>
                      setState(() => _battingExpanded = !_battingExpanded),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _YetToBatCard(players: yetToBatRows),
        if (yetToBatRows.isNotEmpty) const SizedBox(height: 10),
        _ScorecardSummaryCard(innings: current),
        const SizedBox(height: 10),
        _SectionCard(
          title: 'Bowling',
          asset: MDAsset.icBowling,
          icon: Icons.sports_baseball_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatTable(
                headers: const ['Bowler', 'O', 'M', 'R', 'W', 'Econ'],
                rows: [
                  for (final row in bowlingVisible)
                    [
                      _playerCell(
                          context,
                          row,
                          formatCompactPlayerName(str(row['name'] ??
                              row['player_name'] ??
                              row['bowler']))),
                      Text(str(row['overs'], fallback: '0')),
                      Text(str(row['maidens'], fallback: '0')),
                      Text(str(row['runs'] ?? row['runs_conceded'],
                          fallback: '0')),
                      Text(str(row['wickets'], fallback: '0')),
                      Text(_fmtStat(str(row['economy']))),
                    ],
                ],
                empty: 'Bowling figures are not available yet.',
              ),
              if (bowlingRows.length > previewCount)
                _ViewAllButton(
                  label: _bowlingExpanded
                      ? 'Show Less'
                      : 'View All Bowling (${bowlingRows.length})',
                  expanded: _bowlingExpanded,
                  onTap: () =>
                      setState(() => _bowlingExpanded = !_bowlingExpanded),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _FallOfWicketsCard(
            fows: apiList(current['fall_of_wickets'] ?? current['fow'])),
        const SizedBox(height: 10),
        _PartnershipsCard(partnerships: apiList(current['partnerships'])),
        if (batting.isEmpty && bowling.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
                'Raw scorecard loaded, but no innings table was provided by the API.',
                style: TextStyle(color: c.muted)),
          ),
      ],
    );
  }
}

String _formatExtrasLine(Map<String, dynamic> extras) {
  if (extras.isEmpty) return '';
  final total = str(extras['total'] ?? extras['t'], fallback: '0');
  final byes = str(extras['byes'] ?? extras['b'], fallback: '0');
  final legByes = str(extras['leg_byes'] ?? extras['legByes'] ?? extras['lb'],
      fallback: '0');
  final wides = str(extras['wides'] ?? extras['w'], fallback: '0');
  final noBalls = str(extras['no_balls'] ?? extras['noBalls'] ?? extras['nb'],
      fallback: '0');
  final penalty = str(extras['penalty'] ?? extras['p'], fallback: '0');
  return '$total (b $byes, lb $legByes, w $wides, nb $noBalls, p $penalty)';
}

String _formatTotalLine(
    Map<String, dynamic> total, Map<String, dynamic> innings) {
  // Prefer structured backend shape: { runs, wickets, overs }.
  if (total.isNotEmpty) {
    final runs = str(total['runs'] ?? total['r'], fallback: '0');
    final wickets = str(total['wickets'] ?? total['w'], fallback: '0');
    final oversRaw = str(total['overs'] ?? total['o']);
    final overs = oversRaw.isEmpty ? '' : normalizeOversText(oversRaw);
    if (runs == '0' && wickets == '0' && overs.isEmpty) return '';
    return overs.isEmpty ? '$runs/$wickets' : '$runs/$wickets ($overs ov)';
  }
  return _scoreText(innings);
}

class _ScorecardSummaryCard extends StatelessWidget {
  const _ScorecardSummaryCard({required this.innings});

  final Map<String, dynamic> innings;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final extrasRaw = innings['extras'];
    final extrasMap =
        extrasRaw is Map<String, dynamic> ? extrasRaw : <String, dynamic>{};
    final extrasText = extrasRaw is String && extrasRaw.trim().isNotEmpty
        ? extrasRaw.trim()
        : _formatExtrasLine(extrasMap);
    final totalRaw = innings['total'];
    final totalMap =
        totalRaw is Map<String, dynamic> ? totalRaw : <String, dynamic>{};
    final totalText = totalRaw is String && totalRaw.trim().isNotEmpty
        ? totalRaw.trim()
        : _formatTotalLine(totalMap, innings);
    final rrRaw = str(innings['run_rate'] ?? innings['runRate']);
    final rrText = rrRaw.isEmpty ? '' : 'Run rate: $rrRaw';
    final visible = <MapEntry<String, String>>[];
    if (extrasText.isNotEmpty) visible.add(MapEntry('Extras', extrasText));
    if (totalText.isNotEmpty) visible.add(MapEntry('Total', totalText));
    if (rrText.isNotEmpty) visible.add(MapEntry('Run rate', rrRaw));
    if (visible.isEmpty) return const SizedBox.shrink();
    return PremiumCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 78,
                    child: Text(entry.key,
                        style: TextStyle(
                            color: c.muted,
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                            letterSpacing: 0.4)),
                  ),
                  Expanded(
                    child: Text(entry.value,
                        style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 12.5,
                            height: 1.25)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FallOfWicketsCard extends StatelessWidget {
  const _FallOfWicketsCard({required this.fows});

  final List<dynamic> fows;

  @override
  Widget build(BuildContext context) {
    if (fows.isEmpty) return const SizedBox.shrink();
    final entries = <String>[];
    for (final raw in fows) {
      final row = apiMap(raw);
      // Backend shape may vary: {wicket_number, score, batsman, overs}
      // or {wktNbr, score, batsmanName, overNbr}.
      final wkt = str(
          row['wicket_number'] ?? row['wktNbr'] ?? row['wicket'] ?? row['wkt']);
      final score = str(row['score'] ??
          row['runs'] ??
          row['wicketScore'] ??
          row['scoreAtFall']);
      final batsman = str(row['batsman'] ??
          row['batsmanName'] ??
          row['player_name'] ??
          row['name']);
      final oversRaw = str(row['overs'] ?? row['overNbr'] ?? row['over']);
      final overs = oversRaw.isEmpty ? '' : normalizeOversText(oversRaw);
      if (wkt.isEmpty && score.isEmpty && batsman.isEmpty) continue;
      final left = wkt.isEmpty ? score : (score.isEmpty ? wkt : '$wkt-$score');
      final tail = <String>[
        if (batsman.isNotEmpty) batsman,
        if (overs.isNotEmpty) '$overs ov',
      ].join(', ');
      entries.add(tail.isEmpty ? left : '$left ($tail)');
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: 'Fall of Wickets',
      asset: MDAsset.icFallWickets,
      icon: Icons.trending_down_rounded,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 8.0;
          final chipWidth = (constraints.maxWidth - spacing) / 2;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final text in entries)
                SizedBox(
                  width: chipWidth,
                  child: MDPillChip(text: text, center: true),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PartnershipsCard extends StatelessWidget {
  const _PartnershipsCard({required this.partnerships});

  final List<dynamic> partnerships;

  @override
  Widget build(BuildContext context) {
    if (partnerships.isEmpty) return const SizedBox.shrink();
    final entries = <String>[];
    for (final raw in partnerships) {
      final row = apiMap(raw);
      final runs = str(row['runs'] ?? row['totalRuns'] ?? row['r']);
      final balls = str(row['balls'] ?? row['totalBalls'] ?? row['b']);
      if (runs.isEmpty && balls.isEmpty) continue;
      // Compact figure-only chip like the target: "75 (127)".
      final figure = balls.isEmpty ? runs : '$runs ($balls)';
      if (figure.isEmpty) continue;
      entries.add(figure);
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: 'Partnerships',
      asset: MDAsset.icPartnership,
      icon: Icons.people_alt_outlined,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final entry in entries) MDPillChip(text: entry)],
      ),
    );
  }
}

class _YetToBatCard extends StatelessWidget {
  const _YetToBatCard({required this.players});

  final List<Map<String, dynamic>> players;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) return const SizedBox.shrink();
    final c = context.cric;
    final names = players
        .map((row) => _playerName(row))
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isEmpty) return const SizedBox.shrink();
    return PremiumCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Yet to bat',
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w900,
              fontSize: 11.5,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            names.join(', '),
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentaryPanel extends StatefulWidget {
  const _CommentaryPanel({required this.data, this.matchStatus});

  final Map<String, dynamic> data;
  final String? matchStatus;

  @override
  State<_CommentaryPanel> createState() => _CommentaryPanelState();
}

class _CommentaryPanelState extends State<_CommentaryPanel> {
  int filter = 0;
  int _shown = 80;

  static const _pageSize = 80;

  @override
  Widget build(BuildContext context) {
    // New normalized feed: { matchId, innings, items: [...] }. Falls back to
    // legacy shapes so an older payload still renders.
    final source = apiList(widget.data['items'] ??
        widget.data['data'] ??
        widget.data['commentary'] ??
        widget.data['commentaryList']);

    if (kDebugMode) {
      debugPrint('Commentary feed items: ${source.length}');
    }

    final filtered = source.where((item) {
      final row = apiMap(item);
      final type = str(row['type']).toLowerCase();
      final isBall = truthy(row['isBall']) || truthy(row['is_ball']);
      final isWicket = truthy(row['isWicket']) || type == 'wicket';
      final isBoundary =
          truthy(row['isBoundary']) || type == 'four' || type == 'six';
      switch (filter) {
        case 1: // Wickets — only real wicket deliveries.
          return isBall && isWicket;
        case 2: // Boundaries — only real fours/sixes.
          return isBall && isBoundary;
        case 3: // Key Events — trust the server's isKeyEvent flag.
          return truthy(row['isKeyEvent']) || truthy(row['is_key_event']);
        default:
          return true;
      }
    }).toList();

    if (source.isEmpty) {
      final isUpcoming = widget.matchStatus == null ||
          widget.matchStatus!.toLowerCase() == 'upcoming' ||
          widget.matchStatus!.toLowerCase() == 'scheduled' ||
          widget.matchStatus!.toLowerCase() == 'not_started';

      return _MatchDataStateCard(
        icon: Icons.chat_bubble_outline_rounded,
        text: isUpcoming
            ? 'Commentary will appear when the match starts.'
            : 'Commentary is not available from the provider yet.',
      );
    }

    final emptyText = switch (filter) {
      1 => 'No wicket commentary available.',
      2 => 'No boundary commentary available.',
      3 => 'No key events available yet.',
      _ => 'No commentary items match this filter.',
    };

    final visible = filtered.length > _shown ? _shown : filtered.length;
    final hasMore = filtered.length > visible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScrollableSegmentedTabs(
          items: const ['All', 'Wickets', 'Boundaries', 'Key Events'],
          selected: filter,
          onChanged: (value) => setState(() {
            filter = value;
            _shown = _pageSize; // reset paging when switching filters
          }),
          height: 44,
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          _MatchDataStateCard(
              icon: Icons.filter_alt_off_rounded, text: emptyText),
        for (var i = 0; i < visible; i++)
          _CommentaryTimelineItem(
            row: apiMap(filtered[i]),
            isFirst: i == 0,
            isLast: i == visible - 1,
          ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: MDViewMore(
              label: 'View More Commentary',
              icon: Icons.keyboard_arrow_down_rounded,
              onTap: () => setState(() => _shown += _pageSize),
            ),
          ),
      ],
    );
  }
}

class _OversPanel extends StatelessWidget {
  const _OversPanel({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final overs = apiList(data['overs'] ?? data['over_summary_list']);
    final performance = apiList(data['latest_performance']);
    final recent = apiList(data['recent_overs']);
    if (overs.isEmpty && recent.isEmpty && performance.isEmpty) {
      return const _MatchDataStateCard(
          icon: Icons.sports_cricket_rounded,
          text: 'Over summaries are not available yet.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (overs.isNotEmpty) ...[
          _LastTenOversCard(overs: overs),
          const SizedBox(height: 12),
        ],
        if (recent.isNotEmpty)
          _SectionCard(
            title: 'Recent Balls',
            icon: Icons.timelapse_rounded,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ball in recent) _BallBubble(label: str(ball))
              ],
            ),
          ),
        if (recent.isNotEmpty) const SizedBox(height: 12),
        for (final item in overs)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _OverCard(row: apiMap(item)),
          ),
      ],
    );
  }
}

/// "Last 10 Overs Summary" header card with Runs / Wickets / Avg + over grid.
class _LastTenOversCard extends StatelessWidget {
  const _LastTenOversCard({required this.overs});

  final List<dynamic> overs;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Take the most recent 10 overs (the list is newest-first from the API).
    final recent = overs.take(10).toList();
    var runs = 0;
    var wkts = 0;
    for (final raw in recent) {
      final o = apiMap(raw);
      runs += _num(o['runs']).toInt();
      wkts += apiList(o['balls'])
          .where((b) => truthy(apiMap(b)['isWicket']))
          .length;
    }
    final avg = recent.isEmpty ? 0.0 : runs / recent.length;
    return MDGlassPanel(
      topGlow: true,
      borderAlpha: .35,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: c.cyan, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'LAST 10 OVERS SUMMARY',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    fontSize: 12.5,
                    letterSpacing: .3,
                  ),
                ),
              ),
              _miniStat(context, 'Runs', '$runs'),
              const SizedBox(width: 10),
              _miniStat(context, 'Wkts', '$wkts'),
              const SizedBox(width: 10),
              _miniStat(context, 'Avg', avg.toStringAsFixed(2)),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final display = recent.reversed.toList();
              const gap = 6.0;
              final n = display.length.clamp(1, 10);
              final w = (constraints.maxWidth - gap * (n - 1)) / n;
              return Row(
                children: [
                  for (var i = 0; i < display.length; i++) ...[
                    if (i != 0) const SizedBox(width: gap),
                    SizedBox(
                      width: w,
                      child: _overChip(context, apiMap(display[i]),
                          highlight: i == display.length - 1),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _miniStat(BuildContext context, String label, String value) {
    final c = context.cric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label,
            style: TextStyle(
                color: c.muted, fontWeight: FontWeight.w700, fontSize: 9)),
        Text(value,
            style: TextStyle(
                color: c.cyan, fontWeight: FontWeight.w900, fontSize: 13)),
      ],
    );
  }

  Widget _overChip(BuildContext context, Map<String, dynamic> over,
      {required bool highlight}) {
    final c = context.cric;
    final num = normalizeOversText(str(over['overNumber'] ?? over['over']));
    final overLabel = num.split('.').first;
    final runs = str(over['runs'], fallback: '0');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: highlight ? c.cyan.withValues(alpha: .14) : Colors.transparent,
        border: Border.all(
          color: highlight
              ? c.cyan.withValues(alpha: .7)
              : c.cyan.withValues(alpha: .15),
        ),
      ),
      child: Column(
        children: [
          Text(overLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.muted, fontWeight: FontWeight.w700, fontSize: 10)),
          const SizedBox(height: 2),
          Text(runs,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w900, fontSize: 13)),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final team1 = apiMap(data['team1']);
    final team2 = apiMap(data['team2']);
    final venue = apiMap(data['venue']);
    final toss = apiMap(data['toss']);
    final officials = apiMap(data['officials'] ?? data['match_officials']);

    final statusText =
        str(data['status_text'] ?? data['statusText'] ?? data['status']);
    final series = str(data['series_name'] ?? data['seriesName']);
    final format =
        str(data['match_format'] ?? data['match_type'] ?? data['matchFormat']);
    final teamsLine = team1.isNotEmpty && team2.isNotEmpty
        ? '${str(team1['name'], fallback: 'Team 1')} vs ${str(team2['name'], fallback: 'Team 2')}'
        : '';
    final venueLine = [venue['name'], venue['city'], venue['country']]
        .where((v) => str(v).isNotEmpty)
        .join(', ');
    final tossLine = toss.isEmpty
        ? ''
        : '${str(toss['winner'])} won the toss and chose to ${str(toss['decision']).toLowerCase()}';

    final left = <_InfoItem>[
      if (statusText.isNotEmpty)
        _InfoItem(Icons.emoji_events_outlined, 'Match Status', statusText,
            valueColor: c.success),
      if (series.isNotEmpty) _InfoItem(Icons.layers_outlined, 'Series', series),
      if (format.isNotEmpty)
        _InfoItem(Icons.sports_cricket_rounded, 'Format', format),
    ];
    final right = <_InfoItem>[
      if (tossLine.isNotEmpty)
        _InfoItem(Icons.casino_outlined, 'Toss', tossLine),
      if (venueLine.isNotEmpty)
        _InfoItem(Icons.location_on_outlined, 'Venue', venueLine),
      if (teamsLine.isNotEmpty)
        _InfoItem(Icons.groups_2_outlined, 'Teams', teamsLine),
    ];

    final runRate = str(data['current_run_rate'] ?? data['currentRunRate']);
    final reqRate = str(data['required_run_rate'] ?? data['requiredRunRate']);
    final lastWicket = str(data['last_wicket'] ?? data['lastWicket']);
    final recentOvers = str(data['recent_overs'] ?? data['recentOvers']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (left.isNotEmpty || right.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 340;
              final a = _InfoGridCard(items: left);
              final b = _InfoGridCard(items: right);
              if (stack) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (left.isNotEmpty) a,
                    if (left.isNotEmpty && right.isNotEmpty)
                      const SizedBox(height: 12),
                    if (right.isNotEmpty) b,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: left.isEmpty ? const SizedBox() : a),
                  if (left.isNotEmpty && right.isNotEmpty)
                    const SizedBox(width: 12),
                  Expanded(child: right.isEmpty ? const SizedBox() : b),
                ],
              );
            },
          ),
        if (_hasOfficials(officials)) ...[
          const SizedBox(height: 12),
          _OfficialsCard(officials: officials),
        ],
        if (runRate.isNotEmpty || reqRate.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Run Rate',
            icon: Icons.show_chart_rounded,
            child: Column(
              children: [
                if (runRate.isNotEmpty)
                  _kvRow(context, 'Current Run Rate', runRate),
                if (reqRate.isNotEmpty)
                  _kvRow(context, 'Required Run Rate', reqRate),
              ],
            ),
          ),
        ],
        if (recentOvers.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Recent Overs',
            icon: Icons.timelapse_rounded,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                recentOvers,
                style: TextStyle(
                    color: c.text, fontWeight: FontWeight.w700, height: 1.4),
              ),
            ),
          ),
        ],
        if (lastWicket.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Last Wicket',
            icon: Icons.sports_cricket_outlined,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                lastWicket,
                style: TextStyle(
                    color: c.text, fontWeight: FontWeight.w700, height: 1.4),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: c.card.withValues(alpha: .4),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.cyan.withValues(alpha: .25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline_rounded, color: c.cyan, size: 13),
                const SizedBox(width: 6),
                Text(
                  'All times are local (IST)',
                  style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static bool _hasOfficials(Map<String, dynamic> o) {
    if (o.isEmpty) return false;
    return [
      o['umpires'],
      o['field_umpires'],
      o['tv_umpire'],
      o['tvUmpire'],
      o['referee'],
      o['match_referee'],
      o['reserve_umpire'],
    ].any((v) => str(v).isNotEmpty);
  }

  static Widget _kvRow(BuildContext context, String k, String v) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(k,
                style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5)),
          ),
          Text(v,
              style: TextStyle(
                  color: c.cyan, fontWeight: FontWeight.w900, fontSize: 14)),
        ],
      ),
    );
  }
}

class _InfoItem {
  const _InfoItem(this.icon, this.label, this.value, {this.valueColor});
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
}

class _InfoGridCard extends StatelessWidget {
  const _InfoGridCard({required this.items});

  final List<_InfoItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return MDGlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i != 0) ...[
              const SizedBox(height: 10),
              Divider(color: c.cyan.withValues(alpha: .12), height: 1),
              const SizedBox(height: 10),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.cyan.withValues(alpha: .12),
                    border: Border.all(color: c.cyan.withValues(alpha: .35)),
                  ),
                  child: Icon(items[i].icon, color: c.cyan, size: 15),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.cyan.withValues(alpha: .9),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        items[i].value,
                        style: TextStyle(
                          color: items[i].valueColor ?? c.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OfficialsCard extends StatelessWidget {
  const _OfficialsCard({required this.officials});

  final Map<String, dynamic> officials;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final items = <(String, String)>[
      ('Umpires', str(officials['umpires'] ?? officials['field_umpires'])),
      ('TV Umpire', str(officials['tv_umpire'] ?? officials['tvUmpire'])),
      (
        'Match Referee',
        str(officials['referee'] ?? officials['match_referee'])
      ),
      (
        'Reserve Umpire',
        str(officials['reserve_umpire'] ?? officials['reserveUmpire'])
      ),
    ].where((e) => e.$2.isNotEmpty).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: 'Match Officials',
      icon: Icons.person_outline_rounded,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final e in items)
            SizedBox(
              width: (context.w - context.horizontalPadding * 2 - 32 - 12) / 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.$1,
                    style: TextStyle(
                      color: c.cyan,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    e.$2,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SquadsPanel extends StatefulWidget {
  const _SquadsPanel({required this.data});

  final Map<String, dynamic> data;

  @override
  State<_SquadsPanel> createState() => _SquadsPanelState();
}

class _SquadsPanelState extends State<_SquadsPanel> {
  int team = 0;

  @override
  Widget build(BuildContext context) {
    final teams = apiList(widget.data['teams']);
    if (teams.isEmpty) {
      return const _MatchDataStateCard(
          icon: Icons.groups_rounded,
          text: 'Squad has not been announced yet.');
    }
    final safeTeam = team.clamp(0, teams.length - 1);
    final current = apiMap(teams[safeTeam]);
    final xi = apiList(current['playingXI'] ?? current['playing_xi']);
    final bench = apiList(current['bench'] ?? current['substitutes']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MDTeamSelector(
          items: [
            for (final item in teams)
              MDTeamSelectorItem(
                label: str(
                    apiMap(item)['teamName'] ??
                        apiMap(item)['team_name'] ??
                        apiMap(item)['teamShort'] ??
                        apiMap(item)['team_short'],
                    fallback: 'Team'),
                name: str(apiMap(item)['teamName'] ??
                    apiMap(item)['team_name'] ??
                    apiMap(item)['teamShort']),
                logo: str(apiMap(item)['logoUrl'] ??
                            apiMap(item)['logo_url'] ??
                            apiMap(item)['flag'])
                        .isEmpty
                    ? null
                    : str(apiMap(item)['logoUrl'] ??
                        apiMap(item)['logo_url'] ??
                        apiMap(item)['flag']),
              ),
          ],
          selected: safeTeam,
          onChanged: (value) => setState(() => team = value),
        ),
        const SizedBox(height: 14),
        PremiumSquad(playingXi: xi, bench: bench, title: 'Playing XI'),
      ],
    );
  }
}

/// Formats a strike-rate / economy value to a single decimal so it never
/// wraps in the compact scorecard table. Empty values show a clean dash.
String _fmtStat(String raw) {
  final v = formatStatNumber(raw, decimals: 1);
  return v.isEmpty ? '—' : v;
}

/// Compact "View All / Show Less" toggle shown under a collapsed table.
class _ViewAllButton extends StatelessWidget {
  const _ViewAllButton({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        children: [
          const SizedBox(height: 6),
          Divider(color: c.cyan.withValues(alpha: .14), height: 1),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: c.cyan,
                  size: 19,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(
      {required this.title, required this.child, this.icon, this.asset});

  final String title;
  final Widget child;
  final IconData? icon;
  final String? asset;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return MDGlassPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          asset != null
              ? Row(
                  children: [
                    MDIcon(asset!,
                        fallback: icon ?? Icons.sports_cricket_rounded,
                        size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          fontSize: 13.5,
                          letterSpacing: .4,
                        ),
                      ),
                    ),
                  ],
                )
              : MDSectionHeader(title: title, icon: icon),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _StatTable extends StatelessWidget {
  const _StatTable(
      {required this.headers, required this.rows, required this.empty});

  final List<String> headers;
  final List<List<Widget>> rows;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    if (rows.isEmpty) return _InlineEmpty(text: empty);
    return LayoutBuilder(
      builder: (context, constraints) {
        final hideLast = headers.length >= 7 && constraints.maxWidth < 270;
        final visibleHeaders =
            hideLast ? headers.take(headers.length - 1).toList() : headers;
        final numericCount = visibleHeaders.length - 1;
        final narrow = constraints.maxWidth < 360;

        // Fixed column widths; the last numeric column (SR / Econ) is widest so
        // values like "105.9" / "54.4" stay on one line and never wrap.
        double widthFor(int numericIndex) {
          final isLast = numericIndex == numericCount - 1;
          if (isLast) return narrow ? 42.0 : 48.0;
          return narrow ? 28.0 : 32.0;
        }

        Widget numericHeader(int i, String h) => SizedBox(
              width: widthFor(i),
              child: Text(
                h,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.muted,
                  fontWeight: FontWeight.w900,
                  fontSize: 11.5,
                ),
              ),
            );

        Widget numericCell(int i, Widget child) => SizedBox(
              width: widthFor(i),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: DefaultTextStyle.merge(
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                  child: child,
                ),
              ),
            );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      visibleHeaders.first,
                      style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  for (var i = 1; i < visibleHeaders.length; i++)
                    numericHeader(i - 1, visibleHeaders[i]),
                ],
              ),
            ),
            Divider(color: c.border.withValues(alpha: .55), height: 1),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: row.first),
                    for (var i = 0; i < numericCount; i++)
                      numericCell(
                          i,
                          i + 1 < row.length
                              ? row[i + 1]
                              : const Text('—')),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CommentaryTimelineItem extends StatefulWidget {
  const _CommentaryTimelineItem({
    required this.row,
    required this.isFirst,
    required this.isLast,
  });

  final Map<String, dynamic> row;
  final bool isFirst;
  final bool isLast;

  @override
  State<_CommentaryTimelineItem> createState() =>
      _CommentaryTimelineItemState();
}

class _CommentaryTimelineItemState extends State<_CommentaryTimelineItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final row = widget.row;

    // Trust the server-normalized feed. Never re-guess event types here.
    final isBall = truthy(row['isBall']) || truthy(row['is_ball']);
    final type = str(row['type']).toLowerCase();
    final label = str(row['label'],
        fallback: isBall ? 'BALL' : 'COMMENTARY');
    final text = str(row['text'] ?? row['commentary']);
    final scoreLine = str(row['score']);
    final over = str(row['over']);
    final team = str(row['teamShort'] ?? row['team']);
    final isWicket = truthy(row['isWicket']) || type == 'wicket';

    return isBall
        ? _buildBall(context, c, type, label, text, scoreLine, over, team,
            isWicket)
        : _buildNote(context, c, label, text);
  }

  // ---- Real delivery -------------------------------------------------------
  Widget _buildBall(
    BuildContext context,
    dynamic c,
    String type,
    String label,
    String text,
    String scoreLine,
    String over,
    String team,
    bool isWicket,
  ) {
    final runs = str(widget.row['runs'], fallback: '0');
    final Color tone = switch (type) {
      'wicket' => const Color(0xffb05cff),
      'six' => const Color(0xff38f28b),
      'four' => c.cyan,
      'extra' => c.warning,
      'dot' => c.muted,
      _ => c.cyan,
    };
    final ballLabel = switch (type) {
      'wicket' => 'W',
      'six' => '6',
      'four' => '4',
      'dot' => '0',
      'extra' => (label.isNotEmpty ? label[0] : '+'),
      _ => runs,
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                children: [
                  Text(over.isEmpty ? '--' : over,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                      style: TextStyle(
                          color: c.cyan,
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5)),
                  if (team.isNotEmpty)
                    Text(team.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 9)),
                ],
              ),
            ),
          ),
          _TimelineRail(
            isFirst: widget.isFirst,
            isLast: widget.isLast,
            child: MDBallChip(
              label: ballLabel,
              wicket: type == 'wicket',
              boundary: type == 'four' || type == 'six',
              size: switch (type) {
                'wicket' => 44,
                'six' || 'four' => 42,
                'dot' => 38,
                _ => 40,
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MDGlassPanel(
                padding: const EdgeInsets.all(11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _EventBadge(label: label, color: tone),
                        const Spacer(),
                        if (text.isNotEmpty)
                          _ExpandChevron(
                            expanded: _expanded,
                            onTap: () =>
                                setState(() => _expanded = !_expanded),
                          ),
                      ],
                    ),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(text,
                          maxLines: _expanded ? null : 3,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: .9),
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ],
                    if (scoreLine.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(scoreLine,
                          style: TextStyle(
                              color: c.cyan,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Non-ball note (presentation / update / pre-match) -------------------
  Widget _buildNote(
      BuildContext context, dynamic c, String label, String text) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No fake over/team for notes — just a clean spacer.
          const SizedBox(width: 40),
          _TimelineRail(
            isFirst: widget.isFirst,
            isLast: widget.isLast,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.isDark ? const Color(0xff0a1f33) : c.card,
                border: Border.all(
                    color: c.muted.withValues(alpha: .75), width: 2),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: c.card2.withValues(alpha: .4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.border.withValues(alpha: .6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _EventBadge(label: label, color: c.muted, subtle: true),
                        const Spacer(),
                        if (text.isNotEmpty)
                          _ExpandChevron(
                            expanded: _expanded,
                            onTap: () =>
                                setState(() => _expanded = !_expanded),
                          ),
                      ],
                    ),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(text,
                          maxLines: _expanded ? null : 3,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.onImageText,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              fontSize: 12.5)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical cyan rail with a centered marker, shared by ball + note rows.
class _TimelineRail extends StatelessWidget {
  const _TimelineRail({
    required this.child,
    required this.isFirst,
    required this.isLast,
  });

  final Widget child;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      width: 46,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(
                  top: isFirst ? 18 : 0,
                  bottom: isLast ? 18 : 0,
                ),
                child:
                    Container(width: 2, color: c.cyan.withValues(alpha: .28)),
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.only(top: 2), child: child),
        ],
      ),
    );
  }
}

class _ExpandChevron extends StatelessWidget {
  const _ExpandChevron({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Icon(
        expanded
            ? Icons.keyboard_arrow_up_rounded
            : Icons.keyboard_arrow_down_rounded,
        color: c.muted,
        size: 18,
      ),
    );
  }
}



class _OverCard extends StatelessWidget {
  const _OverCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final balls = apiList(row['balls']);
    final overNumber = str(row['overNumber'] ?? row['over']);
    final normalizedOver = normalizeOversText(overNumber);

    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                  'Over ${normalizedOver.isEmpty ? overNumber : normalizedOver}',
                  style: TextStyle(color: c.text, fontWeight: FontWeight.w900)),
              const Spacer(),
              Text('${str(row['runs'], fallback: '0')} runs',
                  style: TextStyle(color: c.cyan, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              '${str(row['bowlerName'] ?? row['bowler'])} | ${str(row['scoreAfter'])}',
              style: TextStyle(color: c.muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ball in balls)
                _BallBubble(
                    label: str(apiMap(ball)['result']),
                    wicket: truthy(apiMap(ball)['isWicket']),
                    boundary: truthy(apiMap(ball)['isBoundary']))
            ],
          ),
        ],
      ),
    );
  }
}

class _BallBubble extends StatelessWidget {
  const _BallBubble(
      {required this.label, this.wicket = false, this.boundary = false});

  final String label;
  final bool wicket;
  final bool boundary;

  @override
  Widget build(BuildContext context) {
    return MDBallChip(label: label, wicket: wicket, boundary: boundary);
  }
}

class _EventBadge extends StatelessWidget {
  const _EventBadge(
      {required this.label, required this.color, this.subtle = false});

  final String label;
  final Color color;
  final bool subtle;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: color.withValues(alpha: subtle ? 0.10 : 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: color.withValues(alpha: subtle ? 0.3 : 0.35))),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 10.5,
                letterSpacing: .3)),
      );
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(color: context.cric.muted, fontWeight: FontWeight.w700));
}

Widget _playerCell(
    BuildContext context, Map<String, dynamic> row, String label) {
  final id = str(row['playerId'] ?? row['player_id']);
  final safeLabel = label.isEmpty ? 'Player' : label;
  final style = TextStyle(
    color: context.cric.cyan,
    fontWeight: FontWeight.w800,
    fontSize: 13.5,
  );
  if (id.isEmpty) {
    return Text(
      safeLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
  return InkWell(
    onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: id))),
    child: Text(
      safeLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    ),
  );
}

Widget _batterCell(BuildContext context, Map<String, dynamic> row) {
  final dismissal = _dismissalText(row);
  final isCurrent = _isCurrentBatter(row);
  final subtitle = dismissal.isNotEmpty
      ? dismissal
      : (isCurrent ? 'not out' : str(row['status']));
  return Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _playerCell(context, row,
            formatCompactPlayerName(_playerName(row), maxLen: 18)),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isCurrent ? context.cric.success : context.cric.muted,
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
              ),
            ),
          ),
      ],
    ),
  );
}

String _playerName(Map<String, dynamic> row) {
  return str(row['name'] ??
      row['player_name'] ??
      row['batsman'] ??
      row['bowler'] ??
      row['fullName']);
}

String _dismissalText(Map<String, dynamic> row) {
  return str(row['dismissal'] ??
      row['dismissal_text'] ??
      row['dismissalText'] ??
      row['outDesc'] ??
      row['out_desc'] ??
      row['how_out']);
}

bool _isCurrentBatter(Map<String, dynamic> row) {
  final status = str(row['status']).toLowerCase();
  return truthy(row['is_current']) ||
      truthy(row['isCurrent']) ||
      truthy(row['is_striker']) ||
      truthy(row['isStriker']) ||
      truthy(row['is_non_striker']) ||
      truthy(row['isNonStriker']) ||
      status == 'not out' ||
      status == 'batting';
}

bool _shouldShowBatter(Map<String, dynamic> row) {
  final runs = _num(row['runs']);
  final balls = _num(row['balls']);
  return runs > 0 ||
      balls > 0 ||
      _dismissalText(row).isNotEmpty ||
      _isCurrentBatter(row);
}

List<Map<String, dynamic>> _yetToBatRows(
  List<Map<String, dynamic>> batting,
  List<dynamic> explicit,
) {
  final rows = <Map<String, dynamic>>[];
  for (final row in batting) {
    if (!_shouldShowBatter(row) && _playerName(row).isNotEmpty) {
      rows.add(row);
    }
  }
  for (final raw in explicit) {
    final row = raw is String ? {'name': raw} : apiMap(raw);
    final name = _playerName(row);
    if (name.isEmpty) continue;
    if (rows.any((existing) => _playerName(existing) == name)) continue;
    rows.add(row);
  }
  return rows;
}

bool _shouldShowBowler(Map<String, dynamic> row) {
  return str(row['overs']).isNotEmpty ||
      _num(row['balls']) > 0 ||
      _num(row['runs'] ?? row['runs_conceded']) > 0 ||
      _num(row['wickets']) > 0 ||
      _num(row['maidens']) > 0;
}

num _num(dynamic value) {
  if (value is num) return value;
  return num.tryParse(str(value)) ?? 0;
}

String _scoreText(Map<String, dynamic> row) {
  final runs = str(row['runs'] ?? row['total_runs']);
  final wickets = str(row['wickets'] ?? row['total_wickets']);
  final overs = str(row['overs'] ?? row['total_overs']);
  if (runs.isEmpty) return '';
  final normalizedOvers = overs.isEmpty ? '' : normalizeOversText(overs);
  return '$runs/$wickets${normalizedOvers.isEmpty ? '' : ' ($normalizedOvers OV)'}';
}

Map<String, dynamic> apiMap(dynamic value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

String str(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is List) {
    return value
        .map((item) => str(item))
        .where((item) => item.isNotEmpty)
        .join(', ');
  }
  final text = value.toString().trim();
  return text.isEmpty || text == 'null' ? fallback : text;
}

bool truthy(dynamic value) =>
    value == true ||
    value == 1 ||
    value == '1' ||
    value.toString().toLowerCase() == 'true';

class _MatchDataStateCard extends StatelessWidget {
  const _MatchDataStateCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(icon, color: c.cyan),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style:
                      TextStyle(color: c.muted, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
