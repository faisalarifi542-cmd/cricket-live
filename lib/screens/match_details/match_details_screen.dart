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
import 'package:cricpro_flutter/widgets/squad.dart';
import 'package:cricpro_flutter/screens.dart';

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
  Future<bool>? _streamAvailabilityFuture;
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
      _streamAvailabilityFuture = _repository.hasPlayableStreams(_matchId);
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
      if (_matchId.isNotEmpty && !_tabData.containsKey(0)) {
        _loadTab(0).then((_) {
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
      0 => _repository.matchScorecard(id, forceRefresh: forceRefresh),
      // Live tab (1) uses the merged Live Center object from the backend,
      // which already contains current batters, bowler, partnership, last
      // wicket, recent balls and latest commentary (with scorecard/commentary
      // fallbacks merged server-side).
      1 => _repository.matchLiveCenter(id, forceRefresh: forceRefresh),
      2 => _repository.matchCommentary(id, forceRefresh: forceRefresh),
      3 => _repository.matchOvers(id, forceRefresh: forceRefresh),
      4 => _repository.matchDetail(id, forceRefresh: forceRefresh),
      _ => _repository.matchSquads(id, forceRefresh: forceRefresh),
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
    // scorecard when a match is completed. Make sure the scorecard is loaded
    // even if the user jumps straight to Live, then rebuild once it arrives.
    if (value == 1 && _matchId.isNotEmpty && !_tabData.containsKey(0)) {
      _loadTab(0).then((_) {
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
    final scorecard = tab == 0
        ? current
        : _repository.matchScorecard(_matchId, forceRefresh: true);
    // Live tab (1) is its own merged live-center endpoint now.
    final liveCenter = tab == 1
        ? current
        : _repository.matchLiveCenter(_matchId, forceRefresh: true);
    final commentary = tab == 2
        ? current
        : _repository.matchCommentary(_matchId, forceRefresh: true);
    final overs = tab == 3
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
      _tabFutures[0] =
          Future.value(results[2] as ApiEnvelope<Map<String, dynamic>>);
      _tabFutures[1] =
          Future.value(results[3] as ApiEnvelope<Map<String, dynamic>>); // Live center
      _tabFutures[2] =
          Future.value(results[4] as ApiEnvelope<Map<String, dynamic>>); // Commentary
      _tabFutures[3] =
          Future.value(results[5] as ApiEnvelope<Map<String, dynamic>>); // Overs
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
              padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
                  context.horizontalPadding, context.detailBottomPadding),
              children: [
                AppHeader(
                  leading: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_rounded, color: c.text)),
                  title: 'Match Details',
                  trailing: const [
                    GlowIconButton(icon: Icons.filter_alt_outlined),
                  ],
                ),
                const SizedBox(height: 16),
                if (_matchId.isNotEmpty)
                  _summaryData != null
                      ? _MatchDetailHeroFromData(
                          matchId: _matchId,
                          data: _summaryData!,
                          streamAvailabilityFuture: _streamAvailabilityFuture,
                          repository: _repository,
                          onWatchLive: widget.onWatchLive,
                        )
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
                            return _MatchDetailHeroFromData(
                              matchId: _matchId,
                              data: data,
                              streamAvailabilityFuture:
                                  _streamAvailabilityFuture,
                              repository: _repository,
                              onWatchLive: widget.onWatchLive,
                            );
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
                const SizedBox(height: 16),
                _RefreshStatusRow(
                  lastUpdatedAt: _lastUpdatedAt,
                  onRefresh: _refreshCurrentTab,
                ),
                const SizedBox(height: 10),
                // Match Details has 5 tabs which squeeze "Commentary" into
                // "Comment…" on narrow widths. Use the scrollable variant so
                // every label stays fully visible.
                ScrollableSegmentedTabs(
                  items: const [
                    'Scorecard',
                    'Live',
                    'Commentary',
                    'Overs',
                    'Info',
                    'Squads'
                  ],
                  selected: tab,
                  onChanged: _setTab,
                  height: 52,
                ),
                const SizedBox(height: 16),
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
                                scorecardData: _tabData[0],
                                matchStatus:
                                    _summaryData?['status']?.toString(),
                              )
                            : _ApiMatchTabFutureContent(
                                tab: tab,
                                future: _tabFutures[tab]!,
                                summaryData: _summaryData,
                                scorecardData: _tabData[0],
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

class _MatchDetailHeroFromData extends StatelessWidget {
  const _MatchDetailHeroFromData({
    required this.matchId,
    required this.data,
    required this.streamAvailabilityFuture,
    required this.repository,
    required this.onWatchLive,
  });

  final String matchId;
  final Map<String, dynamic> data;
  final Future<bool>? streamAvailabilityFuture;
  final CricketRepository repository;
  final ValueChanged<String>? onWatchLive;

  @override
  Widget build(BuildContext context) {
    final match = CricketMatch.fromJson(data);
    if (match.hasStreamInfo) {
      return FutureBuilder<bool>(
        future: repository.shouldShowWatchLiveForMatch(match),
        builder: (context, streamSnapshot) => MatchDetailHeroCard(
          match: match,
          showWatchLive: streamSnapshot.data == true,
          onWatchLive:
              onWatchLive == null ? null : () => onWatchLive!(matchId),
        ),
      );
    }
    return FutureBuilder<bool>(
      future: streamAvailabilityFuture,
      builder: (context, streamSnapshot) => MatchDetailHeroCard(
        match: match,
        showWatchLive: streamSnapshot.data == true,
        onWatchLive:
            onWatchLive == null ? null : () => onWatchLive!(matchId),
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
        icon: tab == 5 ? Icons.groups_rounded : Icons.info_outline_rounded,
        text: _emptyText(tab, matchStatus),
      );
    }
    return switch (tab) {
      0 => _ScorecardPanel(data: data, matchStatus: matchStatus),
      2 => _CommentaryPanel(data: data, matchStatus: matchStatus),
      3 => _OversPanel(data: data),
      4 => _InfoPanel(data: data),
      _ => _SquadsPanel(data: data),
    };
  }

  static String _emptyText(int tab, String? status) {
    final isUpcoming = status == null ||
        status.toLowerCase() == 'upcoming' ||
        status.toLowerCase() == 'scheduled' ||
        status.toLowerCase() == 'not_started';

    return switch (tab) {
      0 => isUpcoming
          ? 'Scorecard will be available once the match starts.'
          : 'Scorecard is not available from the provider yet.',
      2 => isUpcoming
          ? 'Commentary will appear when the match starts.'
          : 'Commentary is not available from the provider yet.',
      3 => 'Over summaries are not available yet.',
      4 => 'Match information is not available yet.',
      _ => 'Squad has not been announced yet.',
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
    final c = context.cric;
    final label = lastUpdatedAt == null
        ? 'Pull to refresh'
        : DateTime.now().difference(lastUpdatedAt!).inSeconds < 10
            ? 'Updated just now'
            : 'Updated ${DateTime.now().difference(lastUpdatedAt!).inSeconds}s ago';
    return Row(
      children: [
        Icon(Icons.sync_rounded, color: c.cyan, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        InkWell(
          onTap: onRefresh,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Icon(Icons.refresh_rounded, color: c.cyan, size: 20),
          ),
        ),
      ],
    );
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
    final battingRows = batting
        .map(apiMap)
        .where(_shouldShowBatter)
        .toList(growable: false);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (innings.length > 1)
          ScrollableSegmentedTabs(
            items: [
              for (var i = 0; i < innings.length; i++)
                str(apiMap(innings[i])['teamName'] ??
                    apiMap(innings[i])['batting_team'] ??
                    'Inn ${i + 1}'),
            ],
            selected: safeSelected,
            onChanged: (value) => setState(() => selected = value),
            height: 44,
          ),
        if (innings.length > 1) const SizedBox(height: 12),
        _SectionCard(
          title:
              str(current['teamName'] ?? current['batting_team'] ?? 'Batting'),
          child: _StatTable(
            headers: const ['Batter', 'R', 'B', '4s', '6s', 'SR'],
            rows: [
              for (final row in battingRows)
                [
                  _batterCell(context, row),
                  Text(str(row['runs'], fallback: '0')),
                  Text(str(row['balls'], fallback: '0')),
                  Text(str(row['fours'], fallback: '0')),
                  Text(str(row['sixes'], fallback: '0')),
                  Text(str(row['strike_rate'] ?? row['strikeRate'])),
                ],
            ],
            empty: 'Batting card is not available yet.',
          ),
        ),
        const SizedBox(height: 12),
        _YetToBatCard(players: yetToBatRows),
        if (yetToBatRows.isNotEmpty) const SizedBox(height: 12),
        _ScorecardSummaryCard(innings: current),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Bowling',
          child: _StatTable(
            headers: const ['Bowler', 'O', 'M', 'R', 'W', 'Econ'],
            rows: [
              for (final row in bowlingRows)
                [
                  _playerCell(
                      context,
                      row,
                      str(row['name'] ??
                          row['player_name'] ??
                          row['bowler'])),
                  Text(str(row['overs'], fallback: '0')),
                  Text(str(row['maidens'], fallback: '0')),
                  Text(str(row['runs'] ?? row['runs_conceded'], fallback: '0')),
                  Text(str(row['wickets'], fallback: '0')),
                  Text(str(row['economy'])),
                ],
            ],
            empty: 'Bowling figures are not available yet.',
          ),
        ),
        const SizedBox(height: 12),
        _FallOfWicketsCard(fows: apiList(current['fall_of_wickets'] ?? current['fow'])),
        const SizedBox(height: 12),
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
  final legByes = str(extras['leg_byes'] ?? extras['legByes'] ?? extras['lb'], fallback: '0');
  final wides = str(extras['wides'] ?? extras['w'], fallback: '0');
  final noBalls = str(extras['no_balls'] ?? extras['noBalls'] ?? extras['nb'], fallback: '0');
  final penalty = str(extras['penalty'] ?? extras['p'], fallback: '0');
  return '$total (b $byes, lb $legByes, w $wides, nb $noBalls, p $penalty)';
}

String _formatTotalLine(Map<String, dynamic> total, Map<String, dynamic> innings) {
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
    final extrasMap = extrasRaw is Map<String, dynamic> ? extrasRaw : <String, dynamic>{};
    final extrasText = extrasRaw is String && extrasRaw.trim().isNotEmpty
        ? extrasRaw.trim()
        : _formatExtrasLine(extrasMap);
    final totalRaw = innings['total'];
    final totalMap = totalRaw is Map<String, dynamic> ? totalRaw : <String, dynamic>{};
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(entry.key,
                        style: TextStyle(
                            color: c.muted,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: 0.4)),
                  ),
                  Expanded(
                    child: Text(entry.value,
                        style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w900,
                            height: 1.3)),
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
    final c = context.cric;
    final entries = <String>[];
    for (final raw in fows) {
      final row = apiMap(raw);
      // Backend shape may vary: {wicket_number, score, batsman, overs}
      // or {wktNbr, score, batsmanName, overNbr}.
      final wkt = str(row['wicket_number'] ??
          row['wktNbr'] ??
          row['wicket'] ??
          row['wkt']);
      final score = str(row['score'] ??
          row['runs'] ??
          row['wicketScore'] ??
          row['scoreAtFall']);
      final batsman = str(row['batsman'] ??
          row['batsmanName'] ??
          row['player_name'] ??
          row['name']);
      final oversRaw = str(row['overs'] ??
          row['overNbr'] ??
          row['over']);
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
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Fall of wickets',
              style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 0.2)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final text in entries)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(text,
                      style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ),
            ],
          ),
        ],
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
    final c = context.cric;
    final entries = <String>[];
    for (final raw in partnerships) {
      final row = apiMap(raw);
      final runs = str(row['runs'] ?? row['totalRuns'] ?? row['r']);
      final balls = str(row['balls'] ?? row['totalBalls'] ?? row['b']);
      final p1 = str(row['bat1Name'] ?? row['player_1'] ?? row['batsman1']);
      final p2 = str(row['bat2Name'] ?? row['player_2'] ?? row['batsman2']);
      if (runs.isEmpty && p1.isEmpty && p2.isEmpty) continue;
      final names = [p1, p2].where((s) => s.isNotEmpty).join(' & ');
      final figure = balls.isEmpty ? runs : '$runs ($balls)';
      entries.add(
          names.isEmpty ? figure : '$names — $figure');
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Partnerships',
              style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 0.2)),
          const SizedBox(height: 10),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(entry,
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      height: 1.3)),
            ),
        ],
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Yet to bat',
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            names.join(', '),
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w700,
              height: 1.35,
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

  @override
  Widget build(BuildContext context) {
    final source = apiList(widget.data['data'] ??
        widget.data['items'] ??
        widget.data['commentary'] ??
        widget.data['commentaryList']);

    if (kDebugMode) {
      debugPrint('Commentary raw payload type: ${widget.data.runtimeType}');
      debugPrint('Commentary data type: ${widget.data['data']?.runtimeType}');
      debugPrint('Commentary count: ${source.length}');
    }

    final filtered = source.where((item) {
      final row = apiMap(item);
      if (filter == 1) {
        return truthy(row['is_wicket']) ||
            str(row['event']).toLowerCase().contains('wicket');
      }
      if (filter == 2) {
        return truthy(row['is_boundary']) ||
            truthy(row['is_four']) ||
            truthy(row['is_six']);
      }
      if (filter == 3) {
        return truthy(row['is_wicket']) ||
            truthy(row['is_boundary']) ||
            str(row['runs']) == '6';
      }
      return true;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScrollableSegmentedTabs(
          items: const ['All', 'Wickets', 'Boundaries', 'Key Events'],
          selected: filter,
          onChanged: (value) => setState(() => filter = value),
          height: 44,
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const _MatchDataStateCard(
              icon: Icons.filter_alt_off_rounded,
              text: 'No commentary items match this filter.'),
        for (final item in filtered.take(50))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CommentaryCard(row: apiMap(item)),
          ),
        if (_paginationHasMultiplePages(widget.data['pagination']))
          _PaginationHint(data: apiMap(widget.data['pagination'])),
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
        if (performance.isNotEmpty)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in performance)
                _PerformanceChip(row: apiMap(item)),
            ],
          ),
        if (performance.isNotEmpty) const SizedBox(height: 12),
        if (recent.isNotEmpty)
          _SectionCard(
            title: 'Recent balls',
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

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final team1 = apiMap(data['team1']);
    final team2 = apiMap(data['team2']);
    final venue = apiMap(data['venue']);
    final toss = apiMap(data['toss']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title:
              '${str(team1['name'], fallback: 'Team 1')} vs ${str(team2['name'], fallback: 'Team 2')}',
          child: _MiniRows(rows: {
            'Status': data['status_text'] ?? data['status'],
            'Series': data['series_name'],
            'Format': data['match_format'],
            'Type': data['match_type'],
            'Start time': data['start_time'],
            'Venue': [venue['name'], venue['city'], venue['country']]
                .where((v) => str(v).isNotEmpty)
                .join(', '),
            'Toss': toss.isEmpty
                ? null
                : '${str(toss['winner'])} chose ${str(toss['decision']).toLowerCase()}',
            'Result': data['result'],
            'Last wicket': data['last_wicket'],
            'Recent overs': data['recent_overs'],
            'Run rate': data['current_run_rate'],
            'Required rate': data['required_run_rate'],
          }),
        ),
        const SizedBox(height: 12),
        if (apiList(data['current_batsmen']).isNotEmpty)
          _SectionCard(
            title: 'At the crease',
            child: Column(
              children: [
                for (final item in apiList(data['current_batsmen']))
                  _PlayerLine(
                      row: apiMap(item),
                      subtitle:
                          '${str(apiMap(item)['runs'])} (${str(apiMap(item)['balls'])})'),
              ],
            ),
          ),
        if (apiMap(data['current_bowler']).isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Current bowler',
            child: _PlayerLine(
              row: apiMap(data['current_bowler']),
              subtitle:
                  '${str(apiMap(data['current_bowler'])['overs'])}-${str(apiMap(data['current_bowler'])['maidens'])}-${str(apiMap(data['current_bowler'])['runs'])}-${str(apiMap(data['current_bowler'])['wickets'])}',
            ),
          ),
        ],
      ],
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
        ScrollableSegmentedTabs(
          items: [
            for (final item in teams)
              str(apiMap(item)['teamShort'] ??
                  apiMap(item)['team_short'] ??
                  apiMap(item)['teamName'])
          ],
          selected: safeTeam,
          onChanged: (value) => setState(() => team = value),
          height: 44,
        ),
        const SizedBox(height: 12),
        PremiumSquad(playingXi: xi, bench: bench, title: 'Playing XI'),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 12),
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
        final hideLast = headers.length >= 6 && constraints.maxWidth < 370;
        final visibleHeaders =
            hideLast ? headers.take(headers.length - 1).toList() : headers;
        final numericCount = visibleHeaders.length - 1;
        final numericWidth = constraints.maxWidth < 360 ? 34.0 : 38.0;
        Widget numericCell(Widget child) => SizedBox(
              width: numericWidth,
              child: DefaultTextStyle.merge(
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
                child: Center(child: child),
              ),
            );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      visibleHeaders.first,
                      style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  for (final header in visibleHeaders.skip(1))
                    SizedBox(
                      width: numericWidth,
                      child: Text(
                        header,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.muted,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Divider(color: c.border.withValues(alpha: .55)),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: row.first),
                    for (final cell in row.skip(1).take(numericCount))
                      numericCell(cell),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MiniRows extends StatelessWidget {
  const _MiniRows({required this.rows});

  final Map<String, dynamic> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final visible =
        rows.entries.where((entry) => str(entry.value).isNotEmpty).toList();
    if (visible.isEmpty) {
      return const _InlineEmpty(text: 'Details are not available yet.');
    }
    return Column(
      children: [
        for (final entry in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                    width: 108,
                    child: Text(entry.key,
                        style: TextStyle(
                            color: c.muted, fontWeight: FontWeight.w800))),
                Expanded(
                    child: Text(str(entry.value),
                        style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w700,
                            height: 1.3))),
              ],
            ),
          ),
      ],
    );
  }
}

class _CommentaryCard extends StatelessWidget {
  const _CommentaryCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final isWicket = truthy(row['is_wicket']);
    final isSix =
        truthy(row['is_six']) || str(row['event']).toLowerCase() == 'six';
    final isFour =
        truthy(row['is_four']) || str(row['event']).toLowerCase() == 'four';
    final tone = isWicket
        ? Colors.redAccent
        : (isSix ? Colors.purpleAccent : (isFour ? c.cyan : c.muted));
    final label = isWicket
        ? 'Wicket'
        : (isSix
            ? 'Six'
            : (isFour
                ? 'Four'
                : (str(row['runs']) == '0'
                    ? 'Dot'
                    : '${str(row['runs'], fallback: '0')} runs')));
    final over = str(row['over']).isEmpty
        ? '--'
        : '${str(row['over'])}.${str(row['ball'], fallback: '0')}';
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      borderColor: tone.withValues(alpha: 0.28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EventBadge(label: over, color: tone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _EventBadge(label: label, color: tone),
                    if (str(row['batsman']).isNotEmpty)
                      _SoftChip(text: str(row['batsman'])),
                    if (str(row['bowler']).isNotEmpty)
                      _SoftChip(text: str(row['bowler'])),
                  ],
                ),
                const SizedBox(height: 10),
                Text(str(row['text'] ?? row['commentary']),
                    style: TextStyle(
                        color: c.text,
                        height: 1.4,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
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

class _PerformanceChip extends StatelessWidget {
  const _PerformanceChip({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.cyan.withValues(alpha: 0.25)),
      ),
      child: Text(
          '${str(row['label'])}: ${str(row['runs'])}/${str(row['wickets'])}',
          style: TextStyle(color: c.text, fontWeight: FontWeight.w900)),
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
    final c = context.cric;
    final color = wicket
        ? Colors.redAccent
        : (boundary || label == '4' || label == '6' ? c.cyan : c.muted);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}

class _PlayerLine extends StatelessWidget {
  const _PlayerLine({required this.row, required this.subtitle});

  final Map<String, dynamic> row;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final id = str(row['playerId'] ?? row['player_id']);
    final image = resolvePlayerImageUrl(row);
    return InkWell(
      onTap: id.isEmpty
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlayerDetailScreen(playerId: id))),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: c.card,
              backgroundImage: image == null
                  ? null
                  : NetworkImage(
                      image,
                      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                    ),
              child: image == null
                  ? Icon(Icons.person_rounded, color: c.muted)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      str(row['name'] ?? row['player_name'],
                          fallback: 'Player'),
                      style: TextStyle(
                          color: c.text, fontWeight: FontWeight.w900)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        style: TextStyle(
                            color: c.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (truthy(row['isCaptain']) || truthy(row['is_captain']))
              const _SoftChip(text: 'C'),
            if (truthy(row['isWicketKeeper']) || truthy(row['is_wicketkeeper']))
              const _SoftChip(text: 'WK'),
          ],
        ),
      ),
    );
  }
}

class _EventBadge extends StatelessWidget {
  const _EventBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.35))),
        child: Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w900, fontSize: 11)),
      );
}

class _SoftChip extends StatelessWidget {
  const _SoftChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: c.card, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: TextStyle(
              color: c.muted, fontWeight: FontWeight.w800, fontSize: 11)),
    );
  }
}

class _PaginationHint extends StatelessWidget {
  const _PaginationHint({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Text('Page ${str(data['page'])} of ${str(data['pages'])}',
        textAlign: TextAlign.center,
        style: TextStyle(color: c.muted, fontWeight: FontWeight.w800));
  }
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
  if (id.isEmpty) {
    return Text(
      safeLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
  return InkWell(
    onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: id))),
    child: Text(
      safeLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: context.cric.cyan, fontWeight: FontWeight.w900),
    ),
  );
}

Widget _batterCell(BuildContext context, Map<String, dynamic> row) {
  final dismissal = _dismissalText(row);
  final isCurrent = _isCurrentBatter(row);
  final subtitle = dismissal.isNotEmpty
      ? dismissal
      : (isCurrent ? 'not out' : str(row['status']));
  return ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 190),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _playerCell(context, row, _playerName(row)),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isCurrent ? context.cric.success : context.cric.muted,
              fontWeight: FontWeight.w700,
              fontSize: 10,
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

bool _paginationHasMultiplePages(dynamic value) {
  final map = apiMap(value);
  if (map.isEmpty) return false;
  final pages = int.tryParse(str(map['pages'])) ?? 0;
  return pages > 1;
}

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
