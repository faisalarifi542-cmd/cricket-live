import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../app_theme.dart';
import '../../components.dart';
import '../../models/api_response.dart';
import '../../models.dart';
import '../../models/cricket_match.dart';
import '../../repositories/cricket_repository.dart';
import '../../models/ad_config.dart';
import '../../widgets/ads/banner_ad_widget.dart';
import '../../widgets/ads/native_ad_card.dart';
import '../../screens.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({
    super.key,
    required this.onOpenMatch,
    required this.onOpenFilters,
    required this.onOpenReminders,
    required this.onOpenSeries,
    required this.onWatchLive,
  });

  /// Invoked with the resolved match id (empty string allowed) when a card
  /// is tapped.
  final ValueChanged<String> onOpenMatch;
  final VoidCallback onOpenFilters;
  final VoidCallback onOpenReminders;
  final VoidCallback onOpenSeries;
  final ValueChanged<String> onWatchLive;

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen>
    with WidgetsBindingObserver {
  int topTab = 1;
  int category = 0;
  final CricketRepository _repository = CricketRepository();
  final ScrollController _scrollController = ScrollController();
  late Future<ApiEnvelope<List<CricketMatch>>> _apiMatches;
  ApiEnvelope<List<CricketMatch>>? _apiMatchesData;
  Timer? _pollTimer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiMatches = _loadMatches();
    _configurePolling();
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
      _configurePolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<ApiEnvelope<List<CricketMatch>>> _loadMatches(
      {bool forceRefresh = false}) async {
    final response =
        await _repository.matchesForTab(topTab, forceRefresh: forceRefresh);
    _apiMatchesData = response;
    return response;
  }

  void _setTopTab(int value) {
    setState(() {
      topTab = value;
      _apiMatchesData = null;
      _apiMatches = _loadMatches();
    });
    _configurePolling();
  }

  Future<void> _refresh() async {
    final oldOffset =
        _scrollController.hasClients ? _scrollController.offset : null;
    final response = await _loadMatches(forceRefresh: true);
    if (!mounted) return;
    setState(() => _apiMatches = Future.value(response));
    _restoreScroll(oldOffset);
  }

  void _configurePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    final interval = switch (topTab) {
      0 => const Duration(seconds: 10),
      1 => const Duration(seconds: 90),
      _ => null,
    };
    if (kDebugMode) {
      debugPrint(
          '[Polling] Matches tab=$topTab interval=${interval?.inSeconds}s');
    }
    if (interval == null) return;
    _pollTimer = Timer.periodic(interval, (_) => _silentPollVisibleTab());
  }

  Future<void> _silentPollVisibleTab() async {
    if (_polling || !mounted) return;
    _polling = true;
    final oldOffset =
        _scrollController.hasClients ? _scrollController.offset : null;
    if (kDebugMode) {
      debugPrint('[Polling] Matches silent refresh start offset=$oldOffset');
    }
    try {
      final previous = _apiMatchesData;
      final response =
          await _repository.matchesForTab(topTab, forceRefresh: true);
      if (!mounted) return;
      final changed = previous == null ||
          jsonEncode(previous.data.map(_matchRefreshKey).toList()) !=
              jsonEncode(response.data.map(_matchRefreshKey).toList());
      _apiMatchesData = response;
      if (changed) {
        setState(() {});
        _restoreScroll(oldOffset);
      }
      if (kDebugMode) {
        debugPrint('[Polling] Matches silent refresh changed=$changed');
      }
    } finally {
      _polling = false;
    }
  }

  void _restoreScroll(double? oldOffset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (oldOffset != null && _scrollController.hasClients) {
        final restoredOffset = oldOffset.clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(restoredOffset);
        if (kDebugMode) {
          debugPrint('[Polling] Matches restored offset=$restoredOffset');
        }
      }
    });
  }

  String _matchRefreshKey(CricketMatch match) {
    return [
      match.id,
      match.status,
      match.statusText,
      match.teamAScoreText,
      match.teamBScoreText,
    ].join('|');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final filters = ['All', 'International', 'League', 'Domestic'];
    return Container(
      decoration: BoxDecoration(gradient: c.bgGradient),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
                context.horizontalPadding, context.mainBottomPadding),
            children: [
              AppHeader(
                showLogo: true,
                trailing: [
                  GlowIconButton(
                      icon: Icons.filter_alt_outlined,
                      onTap: widget.onOpenFilters),
                ],
              ),
              const SizedBox(height: 22),
              SegmentedTabs(
                items: const [
                  ('Live', Icons.podcasts_rounded),
                  ('Upcoming', Icons.calendar_month_rounded),
                  ('Finished', Icons.check_circle_outline_rounded),
                ],
                selected: topTab,
                onChanged: _setTopTab,
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 46,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (_, i) => PillChip(filters[i],
                      selected: category == i,
                      onTap: () => setState(() => category = i)),
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemCount: filters.length,
                ),
              ),
              const SizedBox(height: 22),
              FutureBuilder<ApiEnvelope<List<CricketMatch>>>(
                future: _apiMatches,
                builder: (context, snapshot) {
                  final apiItems =
                      _apiMatchesData?.data ??
                          snapshot.data?.data ??
                          const <CricketMatch>[];
                  final items = apiItems
                      .map((match) =>
                          match.toCompactFixture(finished: topTab == 2))
                      .toList();

                  if (_apiMatchesData == null &&
                      snapshot.connectionState == ConnectionState.waiting &&
                      apiItems.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 26),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (_apiMatchesData == null && snapshot.hasError) {
                    return _StateCard(
                      icon: Icons.cloud_off_rounded,
                      title: 'Unable to load matches',
                      message: 'Please check your connection and try again.',
                      action: 'Retry',
                      onAction: () => setState(
                          () => _apiMatches = _loadMatches(forceRefresh: true)),
                    );
                  }

                  if (items.isEmpty) {
                    return _StateCard(
                      icon: topTab == 0
                          ? Icons.sports_cricket_rounded
                          : Icons.event_busy_rounded,
                      title: topTab == 0
                          ? 'No live matches right now'
                          : 'No matches found',
                      message: topTab == 0
                          ? 'Upcoming fixtures are ready when you want to look ahead.'
                          : 'Please refresh or try a different category.',
                      action: topTab == 0 ? 'View Upcoming' : 'Refresh',
                      onAction: topTab == 0
                          ? () => _setTopTab(1)
                          : () => setState(() =>
                              _apiMatches = _loadMatches(forceRefresh: true)),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if ((_apiMatchesData?.meta.lastUpdated ??
                              snapshot.data?.meta.lastUpdated) !=
                          null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Last updated ${(_apiMatchesData?.meta.lastUpdated ?? snapshot.data!.meta.lastUpdated)!.toLocal()}',
                            style: TextStyle(
                                color: c.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      for (var i = 0; i < items.length; i++) ...[
                        Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: Builder(builder: (_) {
                              final matchId =
                                  i >= apiItems.length ? '' : apiItems[i].id;
                              void onTap() => widget.onOpenMatch(matchId);
                              return topTab == 2
                                  ? FinishedMatchCard(
                                      match: items[i], onTap: onTap)
                                  : topTab == 0
                                      ? _StreamAwareLiveMatchCard(
                                          match: items[i],
                                          matchId: matchId,
                                          apiMatch: i >= apiItems.length
                                              ? null
                                              : apiItems[i],
                                          onOpenMatch: widget.onOpenMatch,
                                          onWatchLive: widget.onWatchLive,
                                        )
                                      : UpcomingMatchCard(
                                          match: items[i],
                                          onTap: onTap,
                                          onReminder: widget.onOpenReminders);
                            })),
                        if ((i + 1) % 5 == 0)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 18),
                            child: NativeAdCard(placement: AdPlacement.matches),
                          ),
                      ],
                      const BannerAdWidget(placement: AdPlacement.matches),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreamAwareLiveMatchCard extends StatelessWidget {
  const _StreamAwareLiveMatchCard({
    required this.match,
    required this.matchId,
    this.apiMatch,
    required this.onOpenMatch,
    required this.onWatchLive,
  });

  final CompactFixture match;
  final String matchId;
  final CricketMatch? apiMatch;
  final ValueChanged<String> onOpenMatch;
  final ValueChanged<String> onWatchLive;

  @override
  Widget build(BuildContext context) {
    if (matchId.isEmpty) {
      return UpcomingMatchCard(match: match, onTap: () => onOpenMatch(matchId));
    }
    if (apiMatch?.hasStreamInfo == true) {
      return FutureBuilder<bool>(
        future: CricketRepository().shouldShowWatchLiveForMatch(apiMatch!),
        builder: (context, snapshot) => UpcomingMatchCard(
          match: match,
          onTap: () => onOpenMatch(matchId),
          onReminder: snapshot.data == true ? () => onWatchLive(matchId) : null,
        ),
      );
    }
    return FutureBuilder<bool>(
      future: CricketRepository().hasPlayableStreams(matchId),
      builder: (context, snapshot) => UpcomingMatchCard(
        match: match,
        onTap: () => onOpenMatch(matchId),
        onReminder: snapshot.data == true ? () => onWatchLive(matchId) : null,
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Icon(icon, color: c.cyan, size: 38),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                  color: c.text, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, height: 1.4)),
          const SizedBox(height: 16),
          GradientButton(
              label: action, icon: Icons.refresh_rounded, onTap: onAction),
        ],
      ),
    );
  }
}
