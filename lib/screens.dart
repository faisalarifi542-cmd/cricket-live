import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'components.dart';
import 'models.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen(
      {super.key,
      required this.onOpenStream,
      required this.onOpenMatch,
      required this.onOpenRanking});
  final VoidCallback onOpenStream;
  final VoidCallback onOpenMatch;
  final VoidCallback onOpenRanking;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      decoration: BoxDecoration(gradient: c.bgGradient),
      child: SafeArea(
        child: ListView(
            padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
                context.horizontalPadding, context.mainBottomPadding),
            children: [
              Row(children: [
                const CricLogo(size: 36),
                const Spacer(),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                        color: c.live.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle, color: c.live)),
                          const SizedBox(width: 6),
                          Text('LIVE',
                              style: TextStyle(
                                  color: c.live,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13))
                        ])),
                IconButton(
                    onPressed: () {},
                    icon: Icon(Icons.search_rounded, color: c.text, size: 30)),
                Stack(children: [
                  IconButton(
                      onPressed: () {},
                      icon: Icon(Icons.notifications_rounded,
                          color: c.text, size: 30)),
                  Positioned(
                      right: 5,
                      top: 5,
                      child: CircleAvatar(
                          radius: 11,
                          backgroundColor: c.live,
                          child: const Text('3',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900))))
                ])
              ]),
              const SizedBox(height: 22),
              SegmentedTabs(items: const [
                ('Live', Icons.podcasts_rounded),
                ('Upcoming', Icons.calendar_month_rounded),
                ('Finished', Icons.check_circle_outline_rounded)
              ], selected: 0, onChanged: (_) {}),
              const SizedBox(height: 24),
              MatchHeroCard(onWatch: onOpenStream),
              const SizedBox(height: 28),
              SectionHeader('Trending Rankings',
                  icon: Icons.trending_up_rounded,
                  action: 'See All',
                  onAction: onOpenRanking),
              const SizedBox(height: 14),
              _TrendingRankings(onTap: onOpenRanking),
              const SizedBox(height: 28),
              const SectionHeader('Quick Access', icon: Icons.flash_on_rounded),
              const SizedBox(height: 14),
              _QuickAccess(onOpenRanking: onOpenRanking),
            ]),
      ),
    );
  }
}

class _TrendingRankings extends StatelessWidget {
  const _TrendingRankings({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      height: context.w <= 390 ? 220 : 215,
      padding: const EdgeInsets.all(20),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ICC ODI Batsmen Rankings',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w800,
                fontSize: context.sp(18))),
        const SizedBox(height: 12),
        Expanded(
            child: Row(
                children: AppData.homeRankings.asMap().entries.map((entry) {
          final p = entry.value;
          final isFirst = entry.key == 0;
          return Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: isFirst
                              ? c.warning
                              : c.border.withValues(alpha: .6),
                          width: isFirst ? 2.5 : 1.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(p.asset,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                            child: Text(
                                p.name
                                    .split(' ')
                                    .map((e) => e[0])
                                    .take(2)
                                    .join(),
                                style: TextStyle(
                                    color: c.text,
                                    fontWeight: FontWeight.w900)))),
                  ),
                  Positioned(
                      left: -8,
                      top: -6,
                      child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isFirst ? c.warning : c.card2,
                              border: Border.all(
                                  color: isFirst ? c.warning : c.border,
                                  width: 1.5)),
                          child: Center(
                              child: Text('${p.rank}',
                                  style: TextStyle(
                                      color: isFirst ? Colors.white : c.text,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900)))))
                ]),
                const SizedBox(height: 8),
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
                Text(p.country,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, fontSize: 12)),
                const SizedBox(height: 2),
                Text('${p.rating} Pts',
                    style: TextStyle(
                        color: c.isDark ? c.cyan : c.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 22))
              ]));
        }).toList())),
      ]),
    );
  }
}

class _QuickAccess extends StatelessWidget {
  const _QuickAccess({required this.onOpenRanking});
  final VoidCallback onOpenRanking;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final items = [
      ('Series', 'All Series', Icons.emoji_events_rounded, c.cyan, () {}),
      (
        'Schedule',
        'Fixtures',
        Icons.calendar_month_rounded,
        const Color(0xff65cc18),
        () {}
      ),
      (
        'Rankings',
        'ICC Rankings',
        Icons.bar_chart_rounded,
        const Color(0xff8b4dff),
        onOpenRanking
      ),
      (
        'Highlights',
        'Top Moments',
        Icons.smart_display_rounded,
        const Color(0xffff6a00),
        () {}
      ),
    ];
    return Row(
      children: items
          .map(
            (e) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: PremiumCard(
                  height: 110,
                  padding: const EdgeInsets.all(10),
                  onTap: e.$5,
                  radius: 24,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: e.$4.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                                color: e.$4.withValues(alpha: .25),
                                blurRadius: 12,
                                offset: const Offset(0, 4))
                          ],
                        ),
                        child: Icon(e.$3, color: e.$4, size: 24),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        e.$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w800,
                            fontSize: context.sp(12.5)),
                      ),
                      Text(
                        e.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.muted, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key, required this.onOpenMatch});
  final VoidCallback onOpenMatch;
  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final list = selected == 1 ? AppData.upcomingMatches : AppData.liveMatches;
    final grouped = <String, List<CricketMatch>>{};
    for (final m in list) {
      grouped.putIfAbsent(m.series, () => []).add(m);
    }
    return Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
            child: ListView(
                padding: EdgeInsets.fromLTRB(context.horizontalPadding, 22,
                    context.horizontalPadding, context.mainBottomPadding),
                children: [
              Row(children: [
                Text('MATCHES',
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        fontSize: context.sp(34))),
                const Spacer(),
                Icon(Icons.search_rounded, color: c.text, size: 32),
                const SizedBox(width: 20),
                Icon(Icons.filter_alt_rounded, color: c.text, size: 30)
              ]),
              const SizedBox(height: 22),
              SegmentedTabs(
                  items: const [
                    ('Live', Icons.podcasts_rounded),
                    ('Upcoming', Icons.calendar_month_rounded),
                    ('Recent', Icons.check_circle_outline_rounded)
                  ],
                  selected: selected,
                  onChanged: (v) => setState(() => selected = v)),
              const SizedBox(height: 20),
              SizedBox(
                  height: 48,
                  child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(right: 20),
                      children: const [
                        PillChip('All', selected: true),
                        SizedBox(width: 12),
                        PillChip('International'),
                        SizedBox(width: 12),
                        PillChip('League'),
                        SizedBox(width: 12),
                        PillChip('Domestic'),
                        SizedBox(width: 20),
                      ])),
              ...grouped.entries.expand((e) => [
                    const SizedBox(height: 24),
                    SectionHeader(e.key, action: 'View All'),
                    const SizedBox(height: 14),
                    ...e.value.map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: MatchCard(
                            match: m,
                            upcoming: selected == 1,
                            onTap: widget.onOpenMatch)))
                  ])
            ])));
  }
}

class MatchCard extends StatelessWidget {
  const MatchCard(
      {super.key, required this.match, required this.upcoming, this.onTap});
  final CricketMatch match;
  final bool upcoming;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final cardHeight = context.w <= 390 ? (upcoming ? 205.0 : 210.0) : (upcoming ? 195.0 : 205.0);
    return PremiumCard(
        height: cardHeight,
        padding: const EdgeInsets.all(20),
        onTap: onTap,
        child: Column(children: [
          Row(children: [
            if (match.isLive)
              const LivePill(compact: true)
            else
              Text(match.matchNo,
                  style: TextStyle(
                      color: c.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            if (match.isLive) ...[
              const SizedBox(width: 12),
              Expanded(
                  child: Text(match.matchNo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)))
            ] else
              const Spacer(),
            Icon(Icons.notifications_rounded, color: c.muted, size: 26)
          ]),
          const Spacer(),
          Row(children: [
            TeamBadge(match.left, size: context.w <= 390 ? 62 : 68),
            SizedBox(width: context.w <= 390 ? 12 : 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(match.left.short,
                      style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontSize: context.w <= 390 ? 26 : 28)),
                  if (upcoming)
                    Text(match.left.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13))
                  else ...[
                    Text(match.leftScore,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        softWrap: false,
                        style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w900,
                            fontSize: context.w <= 390 ? 26 : 28)),
                    Text(match.leftOvers,
                        style: TextStyle(color: c.muted, fontSize: 14))
                  ]
                ])),
            _vsSmall(context),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                  Text(match.right.short,
                      style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontSize: context.w <= 390 ? 26 : 28)),
                  Text(upcoming ? match.right.name : match.rightScore,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w700,
                          fontSize: upcoming ? 13 : 15))
                ])),
            SizedBox(width: context.w <= 390 ? 12 : 14),
            TeamBadge(match.right, size: context.w <= 390 ? 62 : 68)
          ]),
          const Spacer(),
          Divider(color: c.border, height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.sports_cricket_rounded,
                color: upcoming ? c.warning : (c.isDark ? c.cyan : c.primary),
                size: 18),
            const SizedBox(width: 8),
            Flexible(
                child: Text(match.status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: c.isDark ? c.cyan : c.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)))
          ]),
          if (upcoming) ...[
            const SizedBox(height: 8),
            Container(
                width: 180,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: c.card2,
                    borderRadius: BorderRadius.circular(15)),
                child: Text('NOT STARTED',
                    style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)))
          ]
        ]));
  }

  Widget _vsSmall(BuildContext context) => Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.cric.card2,
          border: Border.all(color: context.cric.border, width: 1.2)),
      child: Text('VS',
          style: TextStyle(
              color: context.cric.text,
              fontWeight: FontWeight.w900,
              fontSize: 13)));
}

class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});
  @override
  Widget build(BuildContext context) => SimpleTabPage(
      title: 'Schedule',
      icon: Icons.calendar_month_rounded,
      heading: 'Today Fixtures',
      children: AppData.upcomingMatches
          .map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: MatchCard(match: m, upcoming: true)))
          .toList());
}

class NewsScreen extends StatelessWidget {
  const NewsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final items = [
      'New Zealand build strong first innings before rain break',
      'Bangladesh prepare for final T20I against Ireland',
      'International League T20 season opener confirmed'
    ];
    return SimpleTabPage(
      title: 'News',
      icon: Icons.article_rounded,
      heading: 'Top Stories',
      children: items
          .map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: PremiumCard(
                height: 112,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: c.primaryGradient,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.article_rounded,
                          color: Colors.white),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            t,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.text,
                                fontWeight: FontWeight.w900,
                                fontSize: 16),
                          ),
                          const SizedBox(height: 6),
                          Text('2 hours ago • CricPro News',
                              style: TextStyle(color: c.muted, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class SimpleTabPage extends StatelessWidget {
  const SimpleTabPage(
      {super.key,
      required this.title,
      required this.icon,
      required this.heading,
      required this.children});
  final String title;
  final IconData icon;
  final String heading;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
            child: ListView(
                padding: EdgeInsets.fromLTRB(context.horizontalPadding, 24,
                    context.horizontalPadding, context.mainBottomPadding),
                children: [
              Row(children: [
                Text(title,
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: context.sp(36))),
                const Spacer(),
                Icon(Icons.search_rounded, color: c.text, size: 32),
                const SizedBox(width: 20),
                Icon(Icons.filter_alt_rounded, color: c.text, size: 31)
              ]),
              const SizedBox(height: 28),
              SectionHeader(heading, icon: icon),
              const SizedBox(height: 16),
              ...children,
            ])));
  }
}

class MoreScreen extends StatelessWidget {
  const MoreScreen(
      {super.key,
      required this.isDark,
      required this.onThemeChanged,
      required this.onOpenRanking,
      required this.onOpenTeams});
  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback onOpenRanking;
  final VoidCallback onOpenTeams;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
            child: ListView(
                padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
                    context.horizontalPadding, context.mainBottomPadding),
                children: [
              Row(children: [
                const CricLogo(size: 34),
                const Spacer(),
                Icon(Icons.search_rounded, color: c.text, size: 30),
                const SizedBox(width: 20),
                Stack(children: [
                  Icon(Icons.notifications_rounded, color: c.text, size: 30),
                  Positioned(
                      right: 0,
                      child: CircleAvatar(
                          radius: 10,
                          backgroundColor: c.live,
                          child: const Text('3',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900))))
                ])
              ]),
              const SizedBox(height: 24),
              Container(
                  height: 150,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: c.border, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                            color: c.isDark
                                ? Colors.black.withValues(alpha: .22)
                                : const Color(0xff9bb7d6).withValues(alpha: .16),
                            blurRadius: 24,
                            offset: const Offset(0, 10)),
                      ]),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(fit: StackFit.expand, children: [
                    Image.asset('assets/images/stadium_live.png',
                        fit: BoxFit.cover),
                    Container(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                          c.card.withValues(alpha: .92),
                          c.card.withValues(alpha: .88)
                        ]))),
                    Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(children: [
                          Stack(clipBehavior: Clip.none, children: [
                            CircleAvatar(
                                radius: 48,
                                backgroundColor: c.card2,
                                child: Text('RS',
                                    style: TextStyle(
                                        color: c.text,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 32))),
                            Positioned(
                                right: -2,
                                bottom: -2,
                                child: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: c.cyan,
                                    child: const Icon(Icons.edit_rounded,
                                        color: Colors.white, size: 18)))
                          ]),
                          const SizedBox(width: 20),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                Text('Rohit Sharma',
                                    style: TextStyle(
                                        color: c.text,
                                        fontSize: 26,
                                        fontWeight: FontWeight.w900)),
                                const SizedBox(height: 4),
                                Text('♛  Pro Member',
                                    style: TextStyle(
                                        color: c.cyan,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16)),
                                const SizedBox(height: 10),
                                Text('⭐ 1240   |   🛡 Level 7',
                                    style: TextStyle(
                                        color: c.text,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15))
                              ])),
                          Icon(Icons.chevron_right_rounded,
                              color: c.muted, size: 36)
                        ]))
                  ])),
              const SizedBox(height: 26),
              _MenuGroup(title: 'RANKINGS & TEAMS', items: [
                (
                  'ICC Men Ranking',
                  Icons.bar_chart_rounded,
                  c.cyan,
                  onOpenRanking
                ),
                (
                  'ICC Women Ranking',
                  Icons.bar_chart_rounded,
                  const Color(0xff8b4dff),
                  () {}
                ),
                (
                  'Teams',
                  Icons.groups_rounded,
                  const Color(0xff20d0a6),
                  onOpenTeams
                )
              ]),
              const SizedBox(height: 24),
              _MenuGroup(
                  title: 'SUPPORT & MORE',
                  items: [
                    ('Invite Friends', Icons.share_rounded, c.cyan, () {}),
                    ('Contact Us', Icons.email_rounded, c.warning, () {}),
                    (
                      'Terms & Conditions',
                      Icons.description_rounded,
                      const Color(0xff8b4dff),
                      () {}
                    ),
                    (
                      'Privacy Policy',
                      Icons.security_rounded,
                      const Color(0xff20d0a6),
                      () {}
                    )
                  ],
                  footer: _AppearanceRow(
                      isDark: isDark, onChanged: onThemeChanged)),
            ])));
  }
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.title, required this.items, this.footer});
  final String title;
  final List<(String, IconData, Color, VoidCallback)> items;
  final Widget? footer;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: TextStyle(
              color: c.muted,
              fontSize: 12,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w900)),
      const SizedBox(height: 14),
      PremiumCard(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            for (final item in items) _menuRow(context, item),
            if (footer != null) footer!,
          ])),
    ]);
  }

  Widget _menuRow(
      BuildContext context, (String, IconData, Color, VoidCallback) item) {
    final c = context.cric;
    return InkWell(
        onTap: item.$4,
        child: SizedBox(
            height: 76,
            child: Row(children: [
              const SizedBox(width: 18),
              Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: item.$3.withValues(alpha: .15)),
                  child: Icon(item.$2, color: item.$3, size: 26)),
              const SizedBox(width: 20),
              Expanded(
                  child: Text(item.$1,
                      style: TextStyle(
                          color: c.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800))),
              Icon(Icons.chevron_right_rounded, color: c.muted, size: 28),
              const SizedBox(width: 18)
            ])));
  }
}

class _AppearanceRow extends StatelessWidget {
  const _AppearanceRow({required this.isDark, required this.onChanged});
  final bool isDark;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
        height: 80,
        child: Row(children: [
          const SizedBox(width: 18),
          Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.primary.withValues(alpha: .15)),
              child: Icon(
                  isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  color: c.primary,
                  size: 26)),
          const SizedBox(width: 20),
          Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Appearance',
                    style: TextStyle(
                        color: c.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                Text(isDark ? 'Dark Mode' : 'Light Mode',
                    style: TextStyle(color: c.muted, fontSize: 13))
              ])),
          Switch(value: isDark, onChanged: onChanged),
          const SizedBox(width: 18)
        ]));
  }
}

class LiveStreamScreen extends StatelessWidget {
  const LiveStreamScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
      body: Container(
          decoration: BoxDecoration(gradient: c.bgGradient),
          child: SafeArea(
              child: ListView(
                  padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
                      context.horizontalPadding, context.detailBottomPadding),
                  children: [
                Row(children: [
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_rounded,
                          color: c.text, size: 32)),
                  Expanded(
                      child: Text('LIVE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: c.text,
                              fontSize: 28,
                              fontWeight: FontWeight.w900))),
                  Icon(Icons.share_rounded, color: c.text, size: 30)
                ]),
                const SizedBox(height: 14),
                PremiumCard(
                    height: context.w <= 390 ? 148 : 132,
                    padding: const EdgeInsets.all(18),
                    child: Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                            Row(children: [
                              Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                      color: c.live.withValues(alpha: .12),
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Text('● LIVE',
                                      style: TextStyle(
                                          color: c.live,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12))),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text('1st Test • Day 1',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: c.text,
                                          fontSize: context.sp(15),
                                          fontWeight: FontWeight.w800)))
                            ]),
                            const SizedBox(height: 10),
                            Text('New Zealand vs West Indies',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: c.text,
                                    fontSize: context.sp(20),
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 10),
                            Text(
                                'NZ 158/3 (38.4 ov) • NZ won the toss & chose to bat',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: c.isDark ? c.cyan : c.primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13))
                          ])),
                      const SizedBox(width: 12),
                      _smallPill(context, Icons.visibility_rounded, '128K')
                    ])),
                const SizedBox(height: 22),
                Container(
                    height: 300,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: c.border, width: 1.2)),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(fit: StackFit.expand, children: [
                      Image.asset('assets/images/stadium_live.png',
                          fit: BoxFit.cover),
                      Container(color: Colors.black.withValues(alpha: .18)),
                      const Positioned(left: 18, top: 18, child: LivePill()),
                      Positioned(
                          right: 18,
                          top: 18,
                          child: Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .92),
                                  borderRadius: BorderRadius.circular(18)),
                              child: const Icon(Icons.fullscreen_rounded,
                                  color: Color(0xff061a35), size: 28))),
                      Center(
                          child: CircleAvatar(
                              radius: 54,
                              backgroundColor:
                                  Colors.white.withValues(alpha: .88),
                              child: Icon(Icons.play_arrow_rounded,
                                  color: c.primary, size: 68)))
                    ])),
                const SizedBox(height: 22),
                PremiumCard(
                    height: 96,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    radius: 26,
                    child: Row(children: [
                      Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                              color: c.cyan.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(16)),
                          child: Icon(Icons.shield_rounded,
                              color: c.cyan, size: 30)),
                      const SizedBox(width: 20),
                      Expanded(
                          child: Text(
                              'If you are facing any buffering issue,\nplease switch to another stable link/server.',
                              style: TextStyle(
                                  color: c.text, fontSize: 15, height: 1.5)))
                    ])),
                const SizedBox(height: 18),
                const _QualityCard(
                    title: 'FULL HD', sub: 'Best Quality • 1080p'),
                const SizedBox(height: 14),
                const _QualityCard(title: 'HD', sub: 'High Quality • 720p'),
                const SizedBox(height: 14),
                const _QualityCard(
                    title: 'SD', sub: 'Currently Playing', selected: true),
                const SizedBox(height: 22),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.lock_outline_rounded, color: c.muted, size: 18),
                  const SizedBox(width: 8),
                  Text('All streams are secure and encrypted',
                      style: TextStyle(color: c.muted))
                ]),
              ]))),
    );
  }

  Widget _smallPill(BuildContext context, IconData icon, String txt) =>
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: context.cric.card2,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.cric.border, width: 1.2)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: context.cric.text),
            const SizedBox(width: 6),
            Text(txt,
                style: TextStyle(
                    color: context.cric.text, fontWeight: FontWeight.w900))
          ]));
}

class _QualityCard extends StatelessWidget {
  const _QualityCard(
      {required this.title, required this.sub, this.selected = false});
  final String title;
  final String sub;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
        decoration: selected
            ? BoxDecoration(
                border: Border.all(color: c.cyan, width: 3),
                borderRadius: BorderRadius.circular(26))
            : null,
        child: PremiumCard(
            height: 96,
            padding: const EdgeInsets.all(18),
            radius: 22,
            child: Row(children: [
              Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                      gradient: selected ? c.primaryGradient : null,
                      color: selected ? null : c.card2,
                      borderRadius: BorderRadius.circular(18)),
                  child: Icon(
                      selected
                          ? Icons.play_arrow_rounded
                          : Icons.desktop_windows_rounded,
                      color: selected
                          ? Colors.white
                          : (c.isDark ? c.cyan : c.primary),
                      size: 34)),
              const SizedBox(width: 20),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Text(title,
                        style: TextStyle(
                            color: c.text,
                            fontSize: 24,
                            fontWeight: FontWeight.w900)),
                    Text(sub,
                        style: TextStyle(
                            color: selected ? c.success : c.muted,
                            fontSize: 15,
                            fontWeight: FontWeight.w700))
                  ])),
              selected
                  ? CircleAvatar(
                      radius: 28,
                      backgroundColor: c.cyan,
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 36))
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                      decoration: BoxDecoration(
                          color: c.primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(16)),
                      child: Text('LIVE',
                          style: TextStyle(
                              color: c.primary, fontWeight: FontWeight.w900)))
            ])));
  }
}

class RankingScreen extends StatelessWidget {
  const RankingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
        body: Container(
            decoration: BoxDecoration(gradient: c.bgGradient),
            child: SafeArea(
                child: ListView(
                    padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
                        context.horizontalPadding, context.detailBottomPadding),
                    children: [
                  Row(children: [
                    IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.arrow_back_rounded,
                            color: c.text, size: 32)),
                    Expanded(
                        child: Text("ICC Men's Ranking",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.text,
                                fontSize: context.sp(26),
                                fontWeight: FontWeight.w900))),
                    Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.card,
                            border: Border.all(color: c.border, width: 1.2)),
                        child: Icon(Icons.tune_rounded, color: c.text, size: 26))
                  ]),
                  const SizedBox(height: 18),
                  const Row(children: [
                    Expanded(
                        child:
                            _DropPill('BATSMEN', Icons.sports_cricket_rounded)),
                    SizedBox(width: 14),
                    Expanded(
                        child: _DropPill('TEST', Icons.sports_cricket_rounded))
                  ]),
                  const SizedBox(height: 20),
                  ...AppData.rankings.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _RankingCard(player: p))),
                ]))));
  }
}

class _DropPill extends StatelessWidget {
  const _DropPill(this.title, this.icon);
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => PremiumCard(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      radius: 24,
      child: Row(children: [
        Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: (context.cric.isDark
                        ? context.cric.cyan
                        : context.cric.primary)
                    .withValues(alpha: .15),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(icon,
                color: context.cric.isDark
                    ? context.cric.cyan
                    : context.cric.primary,
                size: 22)),
        const SizedBox(width: 12),
        Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: context.cric.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 17))),
        Icon(Icons.keyboard_arrow_down_rounded,
            color: context.cric.text, size: 28)
      ]));
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({required this.player});
  final RankingPlayer player;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final isFirst = player.rank == 1;
    return Container(
        decoration: isFirst
            ? BoxDecoration(
                border: Border.all(color: c.cyan, width: 2.5),
                borderRadius: BorderRadius.circular(30))
            : null,
        child: PremiumCard(
            height: isFirst ? 132 : 118,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              SizedBox(
                  width: 68,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isFirst)
                          Text('♛',
                              style: TextStyle(color: c.warning, fontSize: 28)),
                        Text('${player.rank}',
                            style: TextStyle(
                                color: isFirst ? c.warning : c.text,
                                fontSize: 28,
                                fontWeight: FontWeight.w900)),
                        if (player.move != 0)
                          Text(
                              '${player.move > 0 ? '▲' : '▼'} ${player.move.abs()}',
                              style: TextStyle(
                                  color: player.move > 0 ? c.success : c.live,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13))
                      ])),
              VerticalDivider(color: c.border, width: 24, thickness: 1.2),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Text(player.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.text,
                            fontSize: context.sp(21),
                            fontWeight: FontWeight.w900,
                            height: 1)),
                    const SizedBox(height: 6),
                    Text('${player.flag}  ${player.country}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.muted,
                            fontSize: context.sp(14),
                            height: 1)),
                    const SizedBox(height: 6),
                    Text('${player.rating} RATING',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.isDark ? c.cyan : c.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: context.sp(19),
                            height: 1))
                  ])),
              const SizedBox(width: 12),
              ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                      width: 80,
                      height: 80,
                      color: c.card2,
                      child: Image.asset(player.asset,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                  player.name
                                      .split(' ')
                                      .map((e) => e[0])
                                      .take(2)
                                      .join(),
                                  style: TextStyle(
                                      color: c.text,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 20)))))),
            ])));
  }
}

class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final teams = [
      AppData.nz,
      AppData.wi,
      AppData.ban,
      AppData.ire,
      AppData.vic,
      AppData.wa,
      AppData.qld,
      AppData.sa,
      AppData.dcp,
      AppData.dv
    ];
    return Scaffold(
        body: Container(
            decoration: BoxDecoration(gradient: context.cric.bgGradient),
            child: SafeArea(
                child: GridView.builder(
                    padding: const EdgeInsets.all(22),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: 1.25),
                    itemCount: teams.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Center(
                            child: Text('Teams',
                                style: TextStyle(
                                    color: context.cric.text,
                                    fontSize: 34,
                                    fontWeight: FontWeight.w900)));
                      }
                      final team = teams[i - 1];
                      return PremiumCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TeamBadge(team, size: 72),
                                const SizedBox(height: 10),
                                Text(team.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: context.cric.text,
                                        fontWeight: FontWeight.w900))
                              ]));
                    }))));
  }
}

class MatchDetailsScreen extends StatefulWidget {
  const MatchDetailsScreen({super.key});
  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends State<MatchDetailsScreen> {
  MatchDetailTab tab = MatchDetailTab.scorecard;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
      body: Container(
          decoration: BoxDecoration(gradient: c.bgGradient),
          child: SafeArea(
              child: ListView(
                  padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
                      context.horizontalPadding, context.detailBottomPadding),
                  children: [
                Row(children: [
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_rounded,
                          color: c.text, size: 32)),
                  Expanded(
                      child: Text('Match Details',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: c.text,
                              fontSize: context.sp(28),
                              fontWeight: FontWeight.w900))),
                  Icon(Icons.search_rounded, color: c.text, size: 31),
                  const SizedBox(width: 16),
                  Icon(Icons.filter_alt_rounded,
                      color: c.isDark ? c.cyan : c.text, size: 30)
                ]),
                const SizedBox(height: 14),
        MatchHeroCard(
            compact: true,
            onWatch: () => Navigator.of(context).push(PageRouteBuilder<void>(
                transitionDuration: const Duration(milliseconds: 260),
                pageBuilder: (_, animation, __) => FadeTransition(
                    opacity: animation, child: const LiveStreamScreen())))),
                const SizedBox(height: 16),
                _DetailTabs(
                    selected: tab, onSelected: (v) => setState(() => tab = v)),
                const SizedBox(height: 16),
                switch (tab) {
                  MatchDetailTab.scorecard => const ScorecardContent(),
                  MatchDetailTab.commentary => const CommentaryContent(),
                  MatchDetailTab.overs => const OversContent(),
                  MatchDetailTab.info => const InfoContent(),
                  MatchDetailTab.squads => const SquadsContent()
                },
              ]))),
    );
  }
}

class _DetailTabs extends StatelessWidget {
  const _DetailTabs({required this.selected, required this.onSelected});
  final MatchDetailTab selected;
  final ValueChanged<MatchDetailTab> onSelected;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final items = [
      (MatchDetailTab.scorecard, 'Scorecard', Icons.list_alt_rounded),
      (
        MatchDetailTab.commentary,
        'Commentary',
        Icons.chat_bubble_outline_rounded
      ),
      (MatchDetailTab.overs, 'Overs', Icons.speed_rounded),
      (MatchDetailTab.info, 'Info', Icons.info_outline_rounded),
      (MatchDetailTab.squads, 'Squads', Icons.groups_rounded),
    ];
    return PremiumCard(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      radius: 24,
      child: Row(
        children: [
          for (final e in items)
            Expanded(
              child: InkWell(
                onTap: () => onSelected(e.$1),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      e.$3,
                      color: selected == e.$1
                          ? (c.isDark ? c.cyan : c.primary)
                          : c.muted,
                      size: context.w <= 390 ? 22 : 25,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      e.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected == e.$1
                            ? (c.isDark ? c.cyan : c.primary)
                            : c.text,
                        fontWeight: FontWeight.w800,
                        fontSize: context.w <= 390 ? 10 : 11.5,
                      ),
                    ),
                    const SizedBox(height: 7),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 46,
                      height: 3.5,
                      decoration: BoxDecoration(
                        color: selected == e.$1
                            ? (c.isDark ? c.cyan : c.primary)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ScorecardContent extends StatelessWidget {
  const ScorecardContent({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(children: [
      PremiumCard(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('NZ 158/3  (38.4 OV)',
                      style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontSize: context.sp(24))),
                  _tinyBluePill(context, '1st Innings')
                ]),
            const SizedBox(height: 12),
            const _TableHeader(cols: ['Batting', 'R', 'B', '4s', '6s', 'SR']),
            const _BatRow('K Williamson', '64*', '78', '6', '1', '82.05'),
            const _BatRow('R Ravindra', '22*', '29', '3', '0', '75.86'),
            const _BatRow('D Conway', '28', '42', '4', '0', '66.67',
                note: 'c Chase b Holder'),
            const _BatRow('T Latham (wk)', '16', '24', '1', '0', '66.67',
                note: 'lbw b Alzarri'),
            const _BatRow('G Phillips', '8', '10', '0', '1', '80.00',
                note: 'c Hope b Chase'),
            Divider(color: c.border),
            Row(children: [
              Expanded(
                  child: Text('Extras',
                      style: TextStyle(
                          color: c.text, fontWeight: FontWeight.w800))),
              Text('(b 1, lb 2, w 3, nb 0)', style: TextStyle(color: c.muted)),
              const Spacer(),
              Text('6',
                  style: TextStyle(color: c.text, fontWeight: FontWeight.w900))
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Text('Total',
                  style: TextStyle(
                      color: c.isDark ? c.cyan : c.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 18)),
              const Spacer(),
              Text('158/3 (38.4 OV)',
                  style: TextStyle(
                      color: c.isDark ? c.cyan : c.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 18))
            ]),
          ])),
      const SizedBox(height: 14),
      if (context.w < 600) ...[
        _BowlingCard(),
        const SizedBox(height: 14),
        const _PartnershipCard(),
        const SizedBox(height: 12),
        const _FallOfWicketsCard(),
      ] else
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _BowlingCard()),
          const SizedBox(width: 12),
          const Expanded(
              child: Column(children: [
            _PartnershipCard(),
            SizedBox(height: 12),
            _FallOfWicketsCard()
          ]))
        ]),
      const SizedBox(height: 14),
      _RecentOvers(),
    ]);
  }

  Widget _tinyBluePill(BuildContext context, String t) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
          color: context.cric.primary.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(12)),
      child: Text(t,
          style: TextStyle(
              color: context.cric.primary,
              fontWeight: FontWeight.w900,
              fontSize: 12)));
}

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.cols});
  final List<String> cols;
  @override
  Widget build(BuildContext context) => Container(
      height: 34,
      decoration: BoxDecoration(
          color: context.cric.card2, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Expanded(
            flex: 4,
            child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(cols[0],
                    style: TextStyle(
                        color: context.cric.text,
                        fontWeight: FontWeight.w900)))),
        for (final c in cols.skip(1))
          Expanded(
              child: Center(
                  child: Text(c,
                      style: TextStyle(
                          color: context.cric.text,
                          fontWeight: FontWeight.w900))))
      ]));
}

class _BatRow extends StatelessWidget {
  const _BatRow(this.name, this.r, this.b, this.fours, this.sixes, this.sr,
      {this.note});
  final String name, r, b, fours, sixes, sr;
  final String? note;
  @override
  Widget build(BuildContext context) => SizedBox(
      height: 44,
      child: Row(children: [
        Expanded(
            flex: 4,
            child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: context.cric.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.2)),
                      if (note != null)
                        Text(note!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: context.cric.muted, fontSize: 11))
                    ]))),
        for (final t in [r, b, fours, sixes, sr])
          Expanded(
              child: Center(
                  child: Text(t,
                      style: TextStyle(
                          color: context.cric.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.8))))
      ]));
}

class _BowlingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final rows = [
      ('A Joseph', '8.0', '0', '32', '0', '4.00'),
      ('A Alzarri', '8.0', '2', '29', '1', '3.63'),
      ('J Holder', '9.0', '1', '33', '1', '3.67'),
      ('R Chase', '7.4', '0', '32', '1', '4.17'),
      ('G Motie', '6.0', '0', '25', '0', '4.17')
    ];
    return PremiumCard(
        height: 256,
        padding: const EdgeInsets.all(14),
        radius: 20,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bowling',
              style: TextStyle(color: c.text, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const _TableHeader(cols: ['Bowler', 'O', 'M', 'R', 'W', 'E']),
          for (final r in rows)
            SizedBox(
                height: 32,
                child: Row(children: [
                  Expanded(
                      flex: 4,
                      child: Text(r.$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.text, fontSize: 12.4))),
                  for (final v in [r.$2, r.$3, r.$4, r.$5, r.$6])
                    Expanded(
                        child: Center(
                            child: Text(v,
                                style: TextStyle(color: c.text, fontSize: 12))))
                ]))
        ]));
  }
}

class _PartnershipCard extends StatelessWidget {
  const _PartnershipCard();
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      radius: 20,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Partnership',
            style: TextStyle(color: c.text, fontWeight: FontWeight.w900)),
        const SizedBox(height: 7),
        Text('K Williamson & R Ravindra',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text('46 (57)',
            style: TextStyle(
                color: c.text, fontWeight: FontWeight.w900, fontSize: 22)),
      ]),
    );
  }
}

class _FallOfWicketsCard extends StatelessWidget {
  const _FallOfWicketsCard();
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      radius: 20,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Fall of Wickets',
            style: TextStyle(color: c.text, fontWeight: FontWeight.w900)),
        const SizedBox(height: 7),
        Text(
            '1-41  (D Conway, 11.3 OV)\n2-62  (T Latham, 17.6 OV)\n3-112 (G Phillips, 28.2 OV)',
            style: TextStyle(color: c.text, height: 1.45, fontSize: 12.5)),
      ]),
    );
  }
}

class _RecentOvers extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final balls = [
      ('38.4', '1'),
      ('38.3', '•'),
      ('38.2', '4'),
      ('38.1', '1'),
      ('38.0', '2'),
      ('37.6', '1')
    ];
    return PremiumCard(
        height: 108,
        padding: const EdgeInsets.all(14),
        radius: 20,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Recent Overs',
                style: TextStyle(color: c.text, fontWeight: FontWeight.w900)),
            const Spacer(),
            Text('38.4 OV',
                style: TextStyle(color: c.text, fontWeight: FontWeight.w900))
          ]),
          const SizedBox(height: 12),
          Expanded(
              child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: balls
                      .map((b) => Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                  color: c.card2,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: c.border)),
                              child: Row(children: [
                                Text(b.$1,
                                    style: TextStyle(
                                        color: c.muted, fontSize: 12)),
                                const SizedBox(width: 8),
                                CircleAvatar(
                                    radius: 15,
                                    backgroundColor: b.$2 == '4'
                                        ? c.primary
                                        : Colors.transparent,
                                    child: Text(b.$2,
                                        style: TextStyle(
                                            color: b.$2 == '4'
                                                ? Colors.white
                                                : c.text,
                                            fontWeight: FontWeight.w900)))
                              ]))))
                      .toList()))
        ]));
  }
}

class CommentaryContent extends StatelessWidget {
  const CommentaryContent({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(children: [
      const _CommentarySummary(),
      const SizedBox(height: 16),
      const SectionHeader('KEY MOMENTS', action: 'VIEW ALL'),
      const SizedBox(height: 10),
      SizedBox(
          height: 82,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            _Moment('38.4', 'Play stopped\ndue to rain', Icons.cloud_rounded,
                c.primary),
            const _Moment('38.2', 'FOUR\nthrough covers', Icons.looks_4_rounded,
                Color(0xff9333ea)),
            _Moment('33.1', 'WICKET!\nHolder to Conway',
                Icons.sports_cricket_rounded, c.success),
            _Moment(
                '30.6', 'DRS saved\nNot Out', Icons.wb_sunny_rounded, c.warning)
          ])),
      const SizedBox(height: 16),
      SizedBox(
          height: 42,
          child: ListView(scrollDirection: Axis.horizontal, children: const [
            PillChip('All', selected: true),
            SizedBox(width: 10),
            PillChip('Wickets'),
            SizedBox(width: 10),
            PillChip('Boundaries'),
            SizedBox(width: 10),
            PillChip('Key Events')
          ])),
      const SizedBox(height: 16),
      const _CommentaryItem('38.4', 'Play stopped due to rain',
          'The players are off the field. Heavy rain at the stadium.', '158/3',
          active: true, icon: Icons.cloud_rounded),
      const _CommentaryItem(
          '38.3', '1 run', 'Pushed to deep square leg for a single.', '158/3'),
      const _CommentaryItem('38.2', 'FOUR!',
          'Beautifully timed through covers for a boundary!', '157/3',
          boundary: true),
      const _CommentaryItem(
          '38.1', 'Good length outside off, left alone.', 'No run.', '153/3'),
      const _CommentaryItem('38.0', 'Dot ball',
          'Full and straight, defended back to the bowler.', '153/3'),
    ]);
  }
}

class _BallChip extends StatelessWidget {
  const _BallChip(this.text, {this.highlight = false, this.wicket = false});
  final String text;
  final bool highlight, wicket;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final color = wicket ? c.live : (highlight ? c.primary : c.card2);
    return CircleAvatar(
        radius: 18,
        backgroundColor: color,
        child: Text(text,
            style: TextStyle(
                color: (highlight || wicket) ? Colors.white : c.text,
                fontWeight: FontWeight.w900)));
  }
}

class _CommentarySummary extends StatelessWidget {
  const _CommentarySummary();
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          CircleAvatar(
              radius: 34,
              backgroundColor: c.primary.withValues(alpha: .12),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('38',
                        style: TextStyle(
                            color: c.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 25)),
                    Text('OVER',
                        style: TextStyle(
                            color: c.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 10))
                  ])),
          const SizedBox(width: 14),
          Expanded(
              child: Text('38th Over - Alzarri Joseph',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: context.sp(18)))),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('5 RUNS',
                style:
                    TextStyle(color: c.primary, fontWeight: FontWeight.w900)),
            Text('NZ: 158/3',
                style: TextStyle(color: c.text, fontWeight: FontWeight.w900)),
            Text('RR: 4.09', style: TextStyle(color: c.muted))
          ]),
        ]),
        const SizedBox(height: 12),
        const Wrap(spacing: 9, runSpacing: 8, children: [
          _BallChip('.'),
          _BallChip('1'),
          _BallChip('4', highlight: true),
          _BallChip('.'),
          _BallChip('.')
        ]),
      ]),
    );
  }
}

class _Moment extends StatelessWidget {
  const _Moment(this.over, this.text, this.icon, this.color);
  final String over, text;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      width: 155,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: .35))),
      child: Row(children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(width: 8),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text(over,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900)),
              Text(text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.cric.text, fontSize: 11.5, height: 1.1))
            ]))
      ]));
}

class _CommentaryItem extends StatelessWidget {
  const _CommentaryItem(this.ball, this.title, this.body, this.score,
      {this.active = false, this.boundary = false, this.icon});
  final String ball, title, body, score;
  final bool active, boundary;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final color =
        boundary ? const Color(0xff9333ea) : (active ? c.primary : c.muted);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
          width: 54,
          child: Column(children: [
            CircleAvatar(
                radius: 22,
                backgroundColor:
                    color.withValues(alpha: active || boundary ? 1 : .12),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(ball,
                          style: TextStyle(
                              color: active || boundary ? Colors.white : color,
                              fontSize: 11,
                              fontWeight: FontWeight.w900)),
                      if (icon != null)
                        Icon(icon, size: 12, color: Colors.white)
                    ])),
            Container(width: 2, height: 66, color: c.border)
          ])),
      Expanded(
          child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PremiumCard(
                  height: 92,
                  padding: const EdgeInsets.all(12),
                  radius: 18,
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: boundary ? color : c.text,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15)),
                          const SizedBox(height: 5),
                          Text(body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: c.muted, fontSize: 13))
                        ])),
                    Text(score,
                        style: TextStyle(
                            color: c.primary, fontWeight: FontWeight.w900))
                  ]))))
    ]);
  }
}

class OversContent extends StatelessWidget {
  const OversContent({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(children: [
      PremiumCard(
          height: 275,
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Run Progression',
                      style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 18)),
                  _legend(context, c.cyan, 'New Zealand'),
                  _legend(context, c.live, 'West Indies')
                ]),
            Expanded(
                child: SizedBox(
                    width: double.infinity,
                    child: CustomPaint(painter: _RunChartPainter(c)))),
            Row(children: [
              Expanded(
                  child: Text('Recent Overs',
                      maxLines: 1,
                      style: TextStyle(
                          color: c.text, fontWeight: FontWeight.w800))),
              for (final o in ['6', '11', '8', '9', '8*'])
                Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: _BallChip(o,
                        highlight: o == '11' || o == '8*', wicket: o == '9'))
            ])
          ])),
      const SizedBox(height: 14),
      const _OverRow(
          '38',
          '8',
          'Alzarri Joseph',
          'Fast',
          ['1', '0', '4', '0', '1', '2'],
          'Daryl Mitchell 64 (83)',
          'Tom Latham 27 (38)'),
      const _OverRow(
          '37',
          '9',
          'Jason Holder',
          'Medium Fast',
          ['0', '4', '1', 'W', '2', '2'],
          'Daryl Mitchell 60 (79)',
          'Tom Latham 26 (36)'),
      const _OverRow(
          '36',
          '8',
          'Alzarri Joseph',
          'Fast',
          ['1', '1', '0', '4', '1', '1'],
          'Daryl Mitchell 55 (74)',
          'Tom Latham 25 (34)'),
      const _OverRow(
          '35',
          '11',
          'Jason Holder',
          'Medium Fast',
          ['4', '0', '4', '1', '1', '1'],
          'Daryl Mitchell 54 (71)',
          'Tom Latham 24 (33)'),
    ]);
  }

  Widget _legend(BuildContext context, Color color, String t) => Row(children: [
        CircleAvatar(radius: 5, backgroundColor: color),
        const SizedBox(width: 5),
        Text(t, style: TextStyle(color: context.cric.muted, fontSize: 12))
      ]);
}

class _RunChartPainter extends CustomPainter {
  _RunChartPainter(this.c);
  final CricColors c;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = c.border.withValues(alpha: .55)
      ..strokeWidth = 1;
    for (var i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final p1 = Paint()
      ..color = c.cyan
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final p2 = Paint()
      ..color = c.live
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    Path path1 = Path(), path2 = Path();
    final pts = [
      0,
      12,
      25,
      38,
      44,
      56,
      68,
      80,
      94,
      105,
      118,
      127,
      139,
      145,
      158
    ];
    final pts2 = [0, 6, 11, 20, 25, 31, 38, 45, 52, 60, 66, 72, 78];
    for (int i = 0; i < pts.length; i++) {
      final x = size.width * i / (pts.length - 1);
      final y = size.height - (pts[i] / 200) * size.height;
      if (i == 0) {
        path1.moveTo(x, y);
      } else {
        path1.lineTo(x, y);
      }
    }
    for (int i = 0; i < pts2.length; i++) {
      final x = size.width * i / (pts.length - 1);
      final y = size.height - (pts2[i] / 200) * size.height;
      if (i == 0) {
        path2.moveTo(x, y);
      } else {
        path2.lineTo(x, y);
      }
    }
    canvas.drawPath(path1, p1);
    canvas.drawPath(path2, p2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OverRow extends StatelessWidget {
  const _OverRow(this.over, this.runs, this.bowler, this.type, this.balls,
      this.bat1, this.bat2);
  final String over, runs, bowler, type, bat1, bat2;
  final List<String> balls;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: PremiumCard(
            padding: const EdgeInsets.all(14),
            radius: 20,
            child: IntrinsicHeight(
                child: Row(children: [
              SizedBox(
                  width: 54,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('OVER',
                            style: TextStyle(color: c.muted, fontSize: 10)),
                        const SizedBox(height: 2),
                        Text(over,
                            style: TextStyle(
                                color: c.cyan,
                                fontWeight: FontWeight.w900,
                                fontSize: 26)),
                        const SizedBox(height: 2),
                        Text('$runs RUNS',
                            style: TextStyle(
                                color: c.cyan,
                                fontSize: 10,
                                fontWeight: FontWeight.w800))
                      ])),
              VerticalDivider(color: c.border, width: 20),
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text(bowler,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.text,
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
                        Text(type,
                            style: TextStyle(color: c.muted, fontSize: 11)),
                        const SizedBox(height: 8),
                        Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: balls
                                .map((b) => _BallChip(b,
                                    highlight: b == '4' || b == '6',
                                    wicket: b == 'W'))
                                .toList())
                      ]))),
              VerticalDivider(color: c.border, width: 20),
              SizedBox(
                  width: context.w <= 430 ? 85 : 120,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(bat1,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.text,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(bat2,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.text, fontSize: 11))
                      ]))
            ]))));
  }
}

class InfoContent extends StatelessWidget {
  const InfoContent({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final cards = [
      (
        'Match',
        '1st Test • Day 1\nWest Indies Tour of New Zealand, 2025\nStatus: Live',
        Icons.sports_cricket_rounded
      ),
      (
        'Venue',
        'Hagley Oval, Christchurch\nCapacity: 18,000\nPitch: Balanced',
        Icons.location_on_rounded
      ),
      (
        'Toss',
        'New Zealand won the toss\nand chose to bat',
        Icons.toll_rounded
      ),
      (
        'Officials',
        'Richard Kettleborough\nMichael Gough\nThird Umpire: Joel Wilson',
        Icons.groups_rounded
      ),
      (
        'Weather',
        'Rain interruption\nCloudy • 18°C\nHumidity 72%',
        Icons.cloud_rounded
      ),
      (
        'Streaming',
        'Available Streams\nSD • HD • Full HD',
        Icons.live_tv_rounded
      )
    ];
    return Column(
        children: cards
            .map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PremiumCard(
                    height: 122,
                    padding: const EdgeInsets.all(16),
                    radius: 22,
                    child: Row(children: [
                      CircleAvatar(
                          radius: 25,
                          backgroundColor: c.primary.withValues(alpha: .13),
                          child:
                              Icon(e.$3, color: c.isDark ? c.cyan : c.primary)),
                      const SizedBox(width: 16),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                            Text(e.$1,
                                style: TextStyle(
                                    color: c.text,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18)),
                            const SizedBox(height: 6),
                            Text(e.$2,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.muted, height: 1.25))
                          ]))
                    ]))))
            .toList());
  }
}

class SquadsContent extends StatelessWidget {
  const SquadsContent({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final players = [
      ('1', 'Devon Conway', 'BAT', 'Playing XI'),
      ('2', 'Rachin Ravindra', 'BAT', 'Playing XI'),
      ('3', 'Kane Williamson', 'BAT', 'Playing XI'),
      ('4', 'Daryl Mitchell', 'AR', 'Playing XI'),
      ('5', 'Tom Latham', 'WK', 'Playing XI'),
      ('6', 'Glenn Phillips', 'AR', 'Playing XI'),
      ('7', 'Mitchell Santner', 'C AR', 'Playing XI'),
      ('8', 'Michael Bracewell', 'AR', 'Playing XI'),
      ('9', 'Matt Henry', 'BOWL', 'Playing XI'),
      ('10', 'Kyle Jamieson', 'BOWL', 'Playing XI'),
      ('11', 'Lockie Ferguson', 'BOWL', 'Playing XI')
    ];
    final bench = [
      ('12', 'Adam Milne', 'BOWL', 'Bench'),
      ('13', 'Ish Sodhi', 'BOWL', 'Bench'),
      ('14', 'Mark Chapman', 'BAT', 'Bench'),
      ('15', 'Ben Sears', 'BOWL', 'Bench'),
      ('16', 'Tim Seifert', 'WK', 'Bench')
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PremiumCard(
          height: 108,
          padding: const EdgeInsets.all(12),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _infoMini(context, 'TOSS', 'NZ elected\nto bat', Icons.toll),
            _infoMini(context, 'VENUE', 'Hagley Oval\nChristchurch',
                Icons.location_on),
            _infoMini(context, 'UMPIRES', 'Kettleborough\nGough', Icons.person),
            _infoMini(context, 'SERIES', '3rd ODI\nof 3', Icons.emoji_events)
          ])),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
            child: Container(
                height: 58,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: c.cyan),
                    color: c.cyan.withValues(alpha: .08)),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const TeamBadge(AppData.nz, size: 34),
                  const SizedBox(width: 8),
                  Text('NEW ZEALAND',
                      style:
                          TextStyle(color: c.cyan, fontWeight: FontWeight.w900))
                ]))),
        const SizedBox(width: 12),
        Expanded(
            child: Container(
                height: 58,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: c.border),
                    color: c.card),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const TeamBadge(AppData.wi, size: 34),
                  const SizedBox(width: 8),
                  Flexible(
                      child: Text('WEST INDIES',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.muted, fontWeight: FontWeight.w900)))
                ])))
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Text('PLAYING XI',
            style: TextStyle(
                color: c.cyan, fontWeight: FontWeight.w900, fontSize: 18)),
        const Spacer(),
        Text('CAPTAIN: Mitchell Santner',
            style: TextStyle(color: c.muted, fontWeight: FontWeight.w700))
      ]),
      const SizedBox(height: 10),
      ...players.map((p) => _SquadRow(p)),
      const SizedBox(height: 16),
      Text('BENCH',
          style: TextStyle(
              color: c.cyan, fontWeight: FontWeight.w900, fontSize: 18)),
      const SizedBox(height: 10),
      ...bench.map((p) => _SquadRow(p, bench: true))
    ]);
  }

  Widget _infoMini(BuildContext context, String t, String b, IconData i) =>
      Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(i, color: context.cric.cyan, size: 20),
        const SizedBox(height: 5),
        Text(t,
            style: TextStyle(
                color: context.cric.cyan,
                fontWeight: FontWeight.w900,
                fontSize: 11)),
        Text(b,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.cric.text, fontSize: 11))
      ]));
}

class _SquadRow extends StatelessWidget {
  const _SquadRow(this.p, {this.bench = false});
  final (String, String, String, String) p;
  final bool bench;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: PremiumCard(
            height: 62,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            radius: 16,
            child: Row(children: [
              Text(p.$1,
                  style: TextStyle(
                      color: c.muted,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
              const SizedBox(width: 10),
              CircleAvatar(
                  radius: 18,
                  backgroundColor: c.card2,
                  child: Text(p.$2.split(' ').map((e) => e[0]).take(2).join(),
                      style: TextStyle(
                          color: c.text,
                          fontSize: 11,
                          fontWeight: FontWeight.w900))),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(p.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 14))),
              _role(context, p.$3),
              const SizedBox(width: 8),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color:
                          (bench ? c.muted : c.success).withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(p.$4,
                      style: TextStyle(
                          color: bench ? c.muted : c.success,
                          fontWeight: FontWeight.w800,
                          fontSize: 10)))
            ])));
  }

  Widget _role(BuildContext context, String r) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
          color: context.cric.card2,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: context.cric.border)),
      child: Text(r,
          style: TextStyle(
              color: context.cric.text,
              fontWeight: FontWeight.w800,
              fontSize: 10)));
}
          style: TextStyle(
              color: context.cric.text,
              fontSize: 10,
              fontWeight: FontWeight.w800)));
}
