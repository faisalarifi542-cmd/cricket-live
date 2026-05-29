import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../components.dart';
import '../../models.dart';
import '../../screens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenMatchDetails,
    required this.onOpenSeries,
    required this.onOpenSearch,
    required this.onOpenNotifications,
    required this.onOpenFilters,
    required this.onOpenReminders,
    required this.onOpenRanking,
    required this.onWatchLive,
  });

  final VoidCallback onOpenMatchDetails;
  final VoidCallback onOpenSeries;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenFilters;
  final VoidCallback onOpenReminders;
  final VoidCallback onOpenRanking;
  final VoidCallback onWatchLive;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int topTab = 0;
  int category = 0;

  static const _liveHero = HeroFixture(
    badge: 'LIVE',
    series: '1st Test • Day 1',
    date: 'West Indies tour of New Zealand, 2025',
    time: '158/3 (38.4 OV)',
    left: AppData.newZealand,
    right: AppData.westIndies,
    centerTitle: 'VS',
    venue: 'NZ won the toss & chose to bat',
    button: 'Watch Live',
  );

  HeroFixture _heroForTab() {
    switch (topTab) {
      case 0:
        return _liveHero;
      case 2:
        return AppData.finishedHero;
      default:
        return AppData.upcomingHero;
    }
  }

  VoidCallback _heroAction() {
    switch (topTab) {
      case 0:
        return widget.onWatchLive;
      case 2:
        return widget.onOpenMatchDetails;
      default:
        return widget.onOpenReminders;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final categories = ['All', 'International', 'League', 'Domestic'];
    final narrow = context.w <= 420;
    return Container(
      decoration: BoxDecoration(gradient: c.bgGradient),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
              context.horizontalPadding, context.mainBottomPadding),
          children: [
            AppHeader(
              showLogo: true,
              trailing: [
                GlowIconButton(
                    icon: Icons.search_rounded, onTap: widget.onOpenSearch),
                const SizedBox(width: 8),
                GlowIconButton(
                  icon: topTab == 2
                      ? Icons.notifications_none_rounded
                      : Icons.notifications_rounded,
                  badge: '3',
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
              onChanged: (v) => setState(() => topTab = v),
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
            HomeHeroCard(
              fixture: _heroForTab(),
              finished: topTab == 2,
              live: topTab == 0,
              onButtonTap: _heroAction(),
            ),
            const SizedBox(height: 28),
            if (topTab == 1) ...[
              SectionHeader('Upcoming Series',
                  icon: Icons.calendar_view_week_rounded,
                  action: 'See All',
                  onAction: widget.onOpenSeries),
              const SizedBox(height: 14),
              _ResponsiveTwoUp(
                stacked: narrow,
                children: AppData.upcomingSeries
                    .map((series) => UpcomingSeriesMiniCard(
                        series: series, onTap: widget.onOpenSeries))
                    .toList(),
              ),
              const SizedBox(height: 28),
              SectionHeader('Featured Fixtures',
                  icon: Icons.star_border_rounded,
                  action: 'See All',
                  onAction: widget.onOpenSeries),
              const SizedBox(height: 14),
              SizedBox(
                height: 248,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (_, i) => FeaturedFixtureCard(
                    fixture: AppData.featuredFixtures[i],
                    onTap: widget.onOpenReminders,
                  ),
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemCount: AppData.featuredFixtures.length,
                ),
              ),
            ] else if (topTab == 2) ...[
              SectionHeader('Recent Results',
                  icon: Icons.emoji_events_outlined,
                  action: 'See All',
                  onAction: widget.onOpenSeries),
              const SizedBox(height: 14),
              _ResponsiveTwoUp(
                stacked: narrow,
                children: AppData.recentResults
                    .map((result) => RecentResultMiniCard(
                        result: result, onTap: widget.onOpenMatchDetails))
                    .toList(),
              ),
              const SizedBox(height: 28),
              SectionHeader('Top Performers',
                  icon: Icons.auto_graph_rounded,
                  action: 'See All',
                  onAction: widget.onOpenSeries),
              const SizedBox(height: 14),
              const PlayerOfMatchCard(),
            ] else ...[
              SectionHeader('Live Centre',
                  icon: Icons.live_tv_rounded,
                  action: 'Open Match',
                  onAction: widget.onOpenMatchDetails),
              const SizedBox(height: 14),
              LiveMatchMiniCard(
                onWatch: widget.onWatchLive,
                onOpen: widget.onOpenMatchDetails,
              ),
              const SizedBox(height: 14),
              LiveMatchMiniCard(
                onWatch: widget.onWatchLive,
                onOpen: widget.onOpenMatchDetails,
                series: 'ENGLAND TOUR OF WEST INDIES',
                title: 'ENG vs WI',
                meta: '2nd ODI • 142/2 (28.5 OV)',
                accent: AppData.england,
                accent2: AppData.westIndies,
              ),
            ],
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
    );
  }
}

class _ResponsiveTwoUp extends StatelessWidget {
  const _ResponsiveTwoUp({required this.children, required this.stacked});

  final List<Widget> children;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    if (stacked) {
      return Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const SizedBox(height: 12),
          ]
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i != children.length - 1) const SizedBox(width: 12),
        ]
      ],
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

class LiveMatchMiniCard extends StatelessWidget {
  const LiveMatchMiniCard({
    super.key,
    required this.onWatch,
    required this.onOpen,
    this.series = 'WEST INDIES TOUR OF NEW ZEALAND',
    this.title = 'NZ vs WI',
    this.meta = '1st Test • Day 1 • 158/3 (38.4 OV)',
    this.accent = AppData.newZealand,
    this.accent2 = AppData.westIndies,
  });

  final VoidCallback onWatch;
  final VoidCallback onOpen;
  final String series;
  final String title;
  final String meta;
  final TeamInfo accent;
  final TeamInfo accent2;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(label: 'LIVE', color: c.live, filled: true),
              const SizedBox(width: 10),
              Expanded(
                child: Text(series,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TeamBadge(accent, size: 40),
              const SizedBox(width: 6),
              TeamBadge(accent2, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w900,
                            fontSize: context.sp(20))),
                    const SizedBox(height: 4),
                    Text(meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.muted, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: 'Watch Live',
              icon: Icons.play_circle_fill_rounded,
              height: 46,
              onTap: onWatch,
            ),
          ),
        ],
      ),
    );
  }
}
