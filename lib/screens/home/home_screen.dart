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
import '../../screens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenMatchDetails,
    required this.onOpenSeries,
    required this.onOpenNotifications,
    required this.onOpenFilters,
    required this.onOpenReminders,
    required this.onOpenRanking,
    required this.onWatchLive,
  });

  /// Invoked with the resolved match id. Pass empty string when the user
  /// taps a section header that doesn't reference a specific match.
  final ValueChanged<String> onOpenMatchDetails;
  final VoidCallback onOpenSeries;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenFilters;
  final VoidCallback onOpenReminders;
  final VoidCallback onOpenRanking;
  final ValueChanged<String> onWatchLive;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int topTab = 0;
  int category = 0;
  final CricketRepository _repository = CricketRepository();
  final ScrollController _scrollController = ScrollController();
  late Future<ApiEnvelope<List<CricketMatch>>> _tabMatches;
  ApiEnvelope<List<CricketMatch>>? _tabMatchesData;
  Timer? _pollTimer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabMatches = _loadMatches();
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

  Future<ApiEnvelope<List<CricketMatch>>> _loadMatches({
    bool forceRefresh = false,
  }) async {
    final response =
        await _repository.matchesForTab(topTab, forceRefresh: forceRefresh);
    _tabMatchesData = response;
    return response;
  }

  void _setTopTab(int value) {
    setState(() {
      topTab = value;
      _tabMatchesData = null;
      _tabMatches = _loadMatches();
    });
    _configurePolling();
  }

  Future<void> _refresh() async {
    final oldOffset =
        _scrollController.hasClients ? _scrollController.offset : null;
    final matches = _loadMatches(forceRefresh: true);
    final response = await matches;
    if (!mounted) return;
    setState(() {
      _tabMatches = Future.value(response);
    });
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
      debugPrint('[Polling] Home tab=$topTab interval=${interval?.inSeconds}s');
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
      debugPrint('[Polling] Home silent refresh start offset=$oldOffset');
    }
    try {
      final previous = _tabMatchesData;
      final response =
          await _repository.matchesForTab(topTab, forceRefresh: true);
      if (!mounted) return;
      final changed = previous == null ||
          jsonEncode(previous.data.map((match) => match.id + match.statusText + match.teamAScoreText + match.teamBScoreText).toList()) !=
              jsonEncode(response.data.map((match) => match.id + match.statusText + match.teamAScoreText + match.teamBScoreText).toList());
      _tabMatchesData = response;
      if (changed) {
        setState(() {});
        _restoreScroll(oldOffset);
      }
      if (kDebugMode) {
        debugPrint('[Polling] Home silent refresh changed=$changed');
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
          debugPrint('[Polling] Home restored offset=$restoredOffset');
        }
      }
    });
  }

  HeroFixture _heroFromMatches(List<CricketMatch> matches) {
    if (matches.isEmpty) {
      // Return empty hero for empty state - no hardcoded data
      return HeroFixture(
        badge: topTab == 0 ? 'LIVE' : (topTab == 2 ? 'RESULT' : 'UPCOMING'),
        series: '',
        date: '',
        time: topTab == 0
            ? 'No live matches'
            : (topTab == 2 ? 'No recent matches' : 'No upcoming matches'),
        left: const TeamInfo(
            code: 'TBD',
            name: 'TBD',
            shortName: 'TBD',
            color: Color(0xff22d3ee)),
        right: const TeamInfo(
            code: 'TBD',
            name: 'TBD',
            shortName: 'TBD',
            color: Color(0xfff59e0b)),
        centerTitle: 'VS',
        venue: '',
        button: '',
      );
    }
    return matches.first
        .toHeroFixture(live: topTab == 0, finished: topTab == 2);
  }

  HeroFixture _heroFromMatch(CricketMatch match) =>
      match.toHeroFixture(live: topTab == 0, finished: topTab == 2);

  Future<bool> _hasPlayableStreams(String matchId) =>
      _repository.hasPlayableStreams(matchId);

  Future<bool> _shouldShowWatchLive(CricketMatch match) =>
      _repository.shouldShowWatchLiveForMatch(match);

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final categories = ['All', 'International', 'League', 'Domestic'];
    final narrow = context.w <= 420;
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
                    icon: topTab == 2
                        ? Icons.notifications_none_rounded
                        : Icons.notifications_rounded,
                    onTap: widget.onOpenNotifications,
                  ),
                ],
              ),
              const SizedBox(height: 20),
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
                  itemBuilder: (_, i) => PillChip(
                    categories[i],
                    selected: category == i,
                    onTap: () => setState(() => category = i),
                  ),
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemCount: categories.length,
                ),
              ),
              const SizedBox(height: 22),
              _tabMatchesData != null
                  ? _HomeHeroSection(
                      matches: _tabMatchesData!.data,
                      lastUpdated: _tabMatchesData!.meta.lastUpdated,
                      topTab: topTab,
                      fixtureFor: _heroFromMatch,
                      emptyFixture: _heroFromMatches(_tabMatchesData!.data),
                      hasPlayableStreams: _hasPlayableStreams,
                      shouldShowWatchLive: _shouldShowWatchLive,
                      onOpenMatch: widget.onOpenMatchDetails,
                      onWatchLive: widget.onWatchLive,
                      onReminder: widget.onOpenReminders,
                    )
                  : FutureBuilder<ApiEnvelope<List<CricketMatch>>>(
                      future: _tabMatches,
                      builder: (context, snapshot) {
                        final matches =
                            snapshot.data?.data ?? const <CricketMatch>[];
                  // Don't show hero card if no matches and it's live tab
                  if (topTab == 0 && matches.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (matches.isNotEmpty)
                        _FeaturedMatchCarousel(
                          matches: matches.take(5).toList(growable: false),
                          topTab: topTab,
                          fixtureFor: _heroFromMatch,
                          hasPlayableStreams: _hasPlayableStreams,
                          shouldShowWatchLive: _shouldShowWatchLive,
                          onOpenMatch: widget.onOpenMatchDetails,
                          onWatchLive: widget.onWatchLive,
                          onReminder: widget.onOpenReminders,
                        ),
                      if (matches.isEmpty && topTab != 0)
                        HomeHeroCard(
                          fixture: _heroFromMatches(matches),
                          finished: topTab == 2,
                          live: false,
                          showButton: false,
                        ),
                      if (snapshot.data?.meta.lastUpdated != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Last updated ${snapshot.data!.meta.lastUpdated!.toLocal()}',
                          style: TextStyle(
                              color: c.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ],
                  );
                      },
                    ),
              const SizedBox(height: 28),
              _HomeTabContent(
                future: _tabMatches,
                data: _tabMatchesData,
                topTab: topTab,
                onRetry: () => setState(() => _tabMatches =
                    _repository.matchesForTab(topTab, forceRefresh: true)),
                onSwitchUpcoming: () => _setTopTab(1),
                onOpenMatch: widget.onOpenMatchDetails,
                onWatchLive: widget.onWatchLive,
                onReminder: () => widget.onOpenReminders(),
              ),
              const SizedBox(height: 28),
              SectionHeader('Quick Access',
                  icon: Icons.flash_on_rounded,
                  action: 'See All',
                  onAction: widget.onOpenSeries),
              const SizedBox(height: 14),
              _QuickAccessGrid(
                narrow: narrow,
                cards: [
                  QuickAccessCard(
                      icon: Icons.emoji_events_outlined,
                      title: 'Series',
                      subtitle: 'All Series',
                      onTap: widget.onOpenSeries,
                      accent: const Color(0xff22d3ee)),
                  QuickAccessCard(
                      icon: Icons.calendar_month_rounded,
                      title: 'Schedule',
                      subtitle: 'All Fixtures',
                      onTap: widget.onOpenSeries,
                      accent: const Color(0xff84cc16)),
                  QuickAccessCard(
                      icon: Icons.bar_chart_rounded,
                      title: 'Rankings',
                      subtitle: 'ICC Rankings',
                      onTap: widget.onOpenRanking,
                      accent: const Color(0xffa855f7)),
                  QuickAccessCard(
                      icon: Icons.confirmation_num_outlined,
                      title: 'Tickets',
                      subtitle: 'Book Now',
                      onTap: widget.onOpenFilters,
                      accent: const Color(0xfff59e0b)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedMatchCarousel extends StatefulWidget {
  const _FeaturedMatchCarousel({
    required this.matches,
    required this.topTab,
    required this.fixtureFor,
    required this.hasPlayableStreams,
    required this.shouldShowWatchLive,
    required this.onOpenMatch,
    required this.onWatchLive,
    required this.onReminder,
  });

  final List<CricketMatch> matches;
  final int topTab;
  final HeroFixture Function(CricketMatch match) fixtureFor;
  final Future<bool> Function(String matchId) hasPlayableStreams;
  final Future<bool> Function(CricketMatch match) shouldShowWatchLive;
  final ValueChanged<String> onOpenMatch;
  final ValueChanged<String> onWatchLive;
  final VoidCallback onReminder;

  @override
  State<_FeaturedMatchCarousel> createState() => _FeaturedMatchCarouselState();
}

class _HomeHeroSection extends StatelessWidget {
  const _HomeHeroSection({
    required this.matches,
    required this.lastUpdated,
    required this.topTab,
    required this.fixtureFor,
    required this.emptyFixture,
    required this.hasPlayableStreams,
    required this.shouldShowWatchLive,
    required this.onOpenMatch,
    required this.onWatchLive,
    required this.onReminder,
  });

  final List<CricketMatch> matches;
  final DateTime? lastUpdated;
  final int topTab;
  final HeroFixture Function(CricketMatch match) fixtureFor;
  final HeroFixture emptyFixture;
  final Future<bool> Function(String matchId) hasPlayableStreams;
  final Future<bool> Function(CricketMatch match) shouldShowWatchLive;
  final ValueChanged<String> onOpenMatch;
  final ValueChanged<String> onWatchLive;
  final VoidCallback onReminder;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    if (topTab == 0 && matches.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (matches.isNotEmpty)
          _FeaturedMatchCarousel(
            matches: matches.take(5).toList(growable: false),
            topTab: topTab,
            fixtureFor: fixtureFor,
            hasPlayableStreams: hasPlayableStreams,
            shouldShowWatchLive: shouldShowWatchLive,
            onOpenMatch: onOpenMatch,
            onWatchLive: onWatchLive,
            onReminder: onReminder,
          ),
        if (matches.isEmpty && topTab != 0)
          HomeHeroCard(
            fixture: emptyFixture,
            finished: topTab == 2,
            live: false,
            showButton: false,
          ),
        if (lastUpdated != null) ...[
          const SizedBox(height: 10),
          Text(
            'Last updated ${lastUpdated!.toLocal()}',
            style: TextStyle(
              color: c.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _FeaturedMatchCarouselState extends State<_FeaturedMatchCarousel> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final height = context.w <= 400 ? 382.0 : 420.0;
    return Column(
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.matches.length,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (context, index) {
              final match = widget.matches[index];
              final fixture = widget.fixtureFor(match);
              final live = widget.topTab == 0;
              final finished = widget.topTab == 2;
              if (live) {
                final future = match.hasStreamInfo
                    ? widget.shouldShowWatchLive(match)
                    : widget.hasPlayableStreams(match.id);
                return FutureBuilder<bool>(
                  future: future,
                  builder: (context, streamSnapshot) => HomeHeroCard(
                    fixture: fixture,
                    finished: false,
                    live: true,
                    onTap: () => widget.onOpenMatch(match.id),
                    showButton: streamSnapshot.data == true,
                    onButtonTap: () => widget.onWatchLive(match.id),
                  ),
                );
              }
              return HomeHeroCard(
                fixture: fixture,
                finished: finished,
                live: false,
                onTap: () => widget.onOpenMatch(match.id),
                showButton: true,
                onButtonTap:
                    finished ? () => widget.onOpenMatch(match.id) : widget.onReminder,
              );
            },
          ),
        ),
        if (widget.matches.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.matches.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 26 : 10,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? c.cyan
                        : Colors.white.withValues(alpha: .26),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _HomeTabContent extends StatelessWidget {
  const _HomeTabContent({
    required this.future,
    required this.data,
    required this.topTab,
    required this.onRetry,
    required this.onSwitchUpcoming,
    required this.onOpenMatch,
    required this.onWatchLive,
    required this.onReminder,
  });

  final Future<ApiEnvelope<List<CricketMatch>>> future;
  final ApiEnvelope<List<CricketMatch>>? data;
  final int topTab;
  final VoidCallback onRetry;
  final VoidCallback onSwitchUpcoming;
  final ValueChanged<String> onOpenMatch;
  final ValueChanged<String> onWatchLive;
  final VoidCallback onReminder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ApiEnvelope<List<CricketMatch>>>(
      future: future,
      builder: (context, snapshot) {
        final allMatches =
            data?.data ?? snapshot.data?.data ?? const <CricketMatch>[];
        // Drop the hero match from the list so the same fixture is never
        // shown twice on the Home screen. The first match in `allMatches` is
        // promoted to the hero card right above, so we skip(1) here for the
        // "Live Centre" / "Upcoming Fixtures" / "Recent Results" list.
        final matches = allMatches.isEmpty
            ? const <CricketMatch>[]
            : allMatches.skip(1).toList();
        final items = matches
            .map((match) => match.toCompactFixture(finished: topTab == 2))
            .toList();

        if (data == null &&
            snapshot.connectionState == ConnectionState.waiting &&
            allMatches.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (data == null && snapshot.hasError && allMatches.isEmpty) {
          return _HomeStateCard(
            icon: Icons.cloud_off_rounded,
            title: 'Unable to refresh cricket data',
            message:
                'Your saved data will be shown when available. Please try again.',
            action: 'Retry',
            onAction: onRetry,
          );
        }

        if (allMatches.isEmpty) {
          return _HomeStateCard(
            icon: Icons.sports_cricket_rounded,
            title:
                topTab == 0 ? 'No live matches right now' : 'No matches found',
            message: topTab == 0
                ? 'There are no live games at this moment. Upcoming fixtures are ready to browse.'
                : 'Pull to refresh or try again shortly.',
            action: topTab == 0 ? 'View Upcoming' : 'Refresh',
            onAction: topTab == 0 ? onSwitchUpcoming : onRetry,
          );
        }

        if (items.isEmpty) {
          // We have a single match — that match is the hero above, so the
          // list below has no additional fixtures to show. Return an empty
          // sized box so the home screen stays compact.
          return const SizedBox.shrink();
        }

        final title = topTab == 0
            ? 'Live Centre'
            : topTab == 2
                ? 'Recent Results'
                : 'Upcoming Fixtures';
        final icon = topTab == 0
            ? Icons.live_tv_rounded
            : topTab == 2
                ? Icons.emoji_events_outlined
                : Icons.calendar_month_rounded;

        // Real matches paired with their matchId.
        final pairs = <(CompactFixture, String, CricketMatch)>[
          for (var i = 0; i < items.length && i < matches.length; i++)
            (items[i], matches[i].id, matches[i]),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title,
                icon: icon,
                action: topTab == 0 && pairs.isNotEmpty ? 'Open Match' : null,
                onAction: topTab == 0 && pairs.isNotEmpty
                    ? () => onOpenMatch(pairs.first.$2)
                    : null),
            const SizedBox(height: 14),
            for (final pair in pairs.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: topTab == 2
                    ? FinishedMatchCard(
                        match: pair.$1, onTap: () => onOpenMatch(pair.$2))
                    : topTab == 0
                        ? _StreamAwareLiveMatchCard(
                            match: pair.$1,
                            matchId: pair.$2,
                            apiMatch: pair.$3,
                            onOpenMatch: onOpenMatch,
                            onWatchLive: onWatchLive,
                          )
                        : UpcomingMatchCard(
                            match: pair.$1,
                            onTap: () => onOpenMatch(pair.$2),
                            onReminder: onReminder,
                          ),
              ),
            const BannerAdWidget(placement: AdPlacement.home),
          ],
        );
      },
    );
  }
}

class _StreamAwareLiveMatchCard extends StatelessWidget {
  const _StreamAwareLiveMatchCard({
    required this.match,
    required this.matchId,
    required this.apiMatch,
    required this.onOpenMatch,
    required this.onWatchLive,
  });

  final CompactFixture match;
  final String matchId;
  final CricketMatch apiMatch;
  final ValueChanged<String> onOpenMatch;
  final ValueChanged<String> onWatchLive;

  @override
  Widget build(BuildContext context) {
    if (matchId.isEmpty) {
      return UpcomingMatchCard(match: match, onTap: () => onOpenMatch(matchId));
    }
    if (apiMatch.hasStreamInfo) {
      return FutureBuilder<bool>(
        future: CricketRepository().shouldShowWatchLiveForMatch(apiMatch),
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

class _HomeStateCard extends StatelessWidget {
  const _HomeStateCard({
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
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w900, fontSize: 18)),
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

class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid({required this.cards, required this.narrow});

  final List<Widget> cards;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    if (!narrow) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            Expanded(child: cards[i]),
            if (i != cards.length - 1) const SizedBox(width: 12),
          ]
        ],
      );
    }
    return Column(
      children: [
        Row(children: [
          Expanded(child: cards[0]),
          const SizedBox(width: 12),
          Expanded(child: cards[1])
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: cards[2]),
          const SizedBox(width: 12),
          Expanded(child: cards[3])
        ]),
      ],
    );
  }
}
