import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../components.dart';
import '../../models/api_response.dart';
import '../../models.dart';
import '../../models/cricket_match.dart';
import '../../repositories/cricket_repository.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  int topTab = 0;
  int category = 0;
  final CricketRepository _repository = CricketRepository();
  late Future<ApiEnvelope<List<CricketMatch>>> _tabMatches;
  late Future<ApiEnvelope<Map<String, dynamic>>> _homeData;

  @override
  void initState() {
    super.initState();
    _homeData = _repository.home();
    _tabMatches = _repository.matchesForTab(topTab);
  }

  void _setTopTab(int value) {
    setState(() {
      topTab = value;
      _tabMatches = _repository.matchesForTab(value);
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _homeData = _repository.home(forceRefresh: true);
      _tabMatches = _repository.matchesForTab(topTab, forceRefresh: true);
    });
    await Future.wait([_homeData, _tabMatches]);
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

  VoidCallback _heroAction({String matchId = ''}) {
    switch (topTab) {
      case 0:
        return () => widget.onWatchLive(matchId);
      case 2:
        return () => widget.onOpenMatchDetails(matchId);
      default:
        return widget.onOpenReminders;
    }
  }

  Future<bool> _hasPlayableStreams(String matchId) =>
      _repository.hasPlayableStreams(matchId);

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
              FutureBuilder<ApiEnvelope<List<CricketMatch>>>(
                future: _tabMatches,
                builder: (context, snapshot) {
                  final matches = snapshot.data?.data ?? const <CricketMatch>[];
                  final heroMatchId = matches.isEmpty ? '' : matches.first.id;
                  final heroFixture = _heroFromMatches(matches);

                  // Don't show hero card if no matches and it's live tab
                  if (topTab == 0 && matches.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (topTab == 0 && heroMatchId.isNotEmpty)
                        FutureBuilder<bool>(
                          future: _hasPlayableStreams(heroMatchId),
                          builder: (context, streamSnapshot) => HomeHeroCard(
                            fixture: heroFixture,
                            finished: false,
                            live: true,
                            onTap: () => widget.onOpenMatchDetails(heroMatchId),
                            showButton: streamSnapshot.data == true,
                            onButtonTap: _heroAction(matchId: heroMatchId),
                          ),
                        )
                      else if (matches.isNotEmpty)
                        HomeHeroCard(
                          fixture: heroFixture,
                          finished: topTab == 2,
                          live: topTab == 0,
                          onTap: heroMatchId.isEmpty
                              ? null
                              : () => widget.onOpenMatchDetails(heroMatchId),
                          showButton: topTab != 0,
                          onButtonTap: _heroAction(matchId: heroMatchId),
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

class _HomeTabContent extends StatelessWidget {
  const _HomeTabContent({
    required this.future,
    required this.topTab,
    required this.onRetry,
    required this.onSwitchUpcoming,
    required this.onOpenMatch,
    required this.onWatchLive,
    required this.onReminder,
  });

  final Future<ApiEnvelope<List<CricketMatch>>> future;
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
        final allMatches = snapshot.data?.data ?? const <CricketMatch>[];
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

        if (snapshot.connectionState == ConnectionState.waiting &&
            allMatches.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError && allMatches.isEmpty) {
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
        final pairs = <(CompactFixture, String)>[
          for (var i = 0; i < items.length && i < matches.length; i++)
            (items[i], matches[i].id),
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
                            onOpenMatch: onOpenMatch,
                            onWatchLive: onWatchLive,
                          )
                        : UpcomingMatchCard(
                            match: pair.$1,
                            onTap: () => onOpenMatch(pair.$2),
                            onReminder: onReminder,
                          ),
              ),
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
    required this.onOpenMatch,
    required this.onWatchLive,
  });

  final CompactFixture match;
  final String matchId;
  final ValueChanged<String> onOpenMatch;
  final ValueChanged<String> onWatchLive;

  @override
  Widget build(BuildContext context) {
    if (matchId.isEmpty) {
      return UpcomingMatchCard(match: match, onTap: () => onOpenMatch(matchId));
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


