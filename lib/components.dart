import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'models.dart';

enum AppTab { home, matches, schedule, news, more }

enum MatchDetailTab { scorecard, commentary, overs, info, squads }

String tabLabel(AppTab tab) => switch (tab) {
      AppTab.home => 'Home',
      AppTab.matches => 'Matches',
      AppTab.schedule => 'Schedule',
      AppTab.news => 'News',
      AppTab.more => 'More'
    };
IconData tabIcon(AppTab tab) => switch (tab) {
      AppTab.home => Icons.home_rounded,
      AppTab.matches => Icons.sports_cricket_rounded,
      AppTab.schedule => Icons.calendar_month_rounded,
      AppTab.news => Icons.article_rounded,
      AppTab.more => Icons.more_horiz_rounded
    };

class PremiumCard extends StatelessWidget {
  const PremiumCard(
      {super.key,
      required this.child,
      this.padding,
      this.radius = 28,
      this.height,
      this.onTap});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double? height;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.border, width: 1.2),
        boxShadow: [
          BoxShadow(
              color: c.isDark
                  ? Colors.black.withValues(alpha: .22)
                  : const Color(0xff9bb7d6).withValues(alpha: .16),
              blurRadius: 24,
              offset: const Offset(0, 10)),
        ],
      ),
      child: child,
    );
    return onTap == null
        ? card
        : InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            child: card);
  }
}

class CricLogo extends StatelessWidget {
  const CricLogo({super.key, this.size = 34});
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return RichText(
      text: TextSpan(
          style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w800,
              fontStyle: FontStyle.italic,
              letterSpacing: -1.2),
          children: [
            TextSpan(text: 'CRIC', style: TextStyle(color: c.text)),
            TextSpan(text: 'PRO', style: TextStyle(color: c.primary)),
          ]),
    );
  }
}

class LivePill extends StatelessWidget {
  const LivePill({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1200),
      builder: (context, value, child) {
        return Container(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14, vertical: compact ? 7 : 10),
          decoration: BoxDecoration(
              color: c.live,
              borderRadius: BorderRadius.circular(compact ? 12 : 16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedOpacity(
              opacity: value > 0.5 ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 600),
              child: const CircleAvatar(radius: 4, backgroundColor: Colors.white),
            ),
            const SizedBox(width: 7),
            Text('LIVE',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 13 : 16,
                    fontWeight: FontWeight.w900)),
          ]),
        );
      },
    );
  }
}

class TeamBadge extends StatelessWidget {
  const TeamBadge(this.team, {super.key, this.size = 68});
  final Team team;
  final double size;
  @override
  Widget build(BuildContext context) {
    return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: team.color.withValues(alpha: .2),
            border: Border.all(
                color: Colors.white.withValues(alpha: .88), width: 2.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: .18),
                  blurRadius: 12,
                  offset: const Offset(0, 6))
            ]),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(team.asset,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Center(
                child: Text(team.short,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900)))));
  }
}

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar(this.player, {super.key, this.size = 64});
  final RankingPlayer player;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.card2,
            border: Border.all(color: c.border, width: 1.2)),
        child: Image.asset(player.asset,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Center(
                child: Text(
                    player.name.split(' ').map((e) => e[0]).take(2).join(),
                    style: TextStyle(
                        color: c.text, fontWeight: FontWeight.w900)))));
  }
}

class BottomNav extends StatelessWidget {
  const BottomNav({super.key, required this.active, required this.onTab});
  final AppTab active;
  final ValueChanged<AppTab> onTab;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SafeArea(
      top: false,
      bottom: false,
      child: Container(
        height: 88 + MediaQuery.paddingOf(context).bottom,
        padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom, top: 8),
        decoration: BoxDecoration(
          color: c.nav,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: c.border, width: 1.2),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: c.isDark ? .35 : .08),
                blurRadius: 24,
                offset: const Offset(0, -8))
          ],
        ),
        child: Row(
          children: AppTab.values.map((tab) {
            final selected = tab == active;
            final color = selected ? (c.isDark ? c.cyan : c.primary) : c.muted;
            return Expanded(
              child: InkWell(
                onTap: () => onTab(tab),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: selected ? color : Colors.transparent,
                              borderRadius: BorderRadius.circular(4))),
                      const SizedBox(height: 10),
                      AnimatedScale(
                        duration: const Duration(milliseconds: 200),
                        scale: selected ? 1.1 : 1,
                        child: Icon(tabIcon(tab), color: color, size: 28),
                      ),
                      const SizedBox(height: 4),
                      Text(tabLabel(tab),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: color,
                              fontWeight:
                                  selected ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 12)),
                    ]),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs(
      {super.key,
      required this.items,
      required this.selected,
      required this.onChanged});
  final List<(String, IconData)> items;
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final labelSize = context.sp(15);
    return Container(
      height: 64,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: c.border, width: 1.2)),
      child: Row(children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                    gradient: i == selected ? c.primaryGradient : null,
                    borderRadius: BorderRadius.circular(28)),
                child: Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(items[i].$2,
                      color: i == selected ? Colors.white : c.muted, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                      child: Text(items[i].$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: i == selected ? Colors.white : c.text,
                              fontWeight: FontWeight.w700,
                              fontSize: labelSize))),
                ])),
              ),
            ),
          ),
      ]),
    );
  }
}

class PillChip extends StatelessWidget {
  const PillChip(this.label, {super.key, this.selected = false});
  final String label;
  final bool selected;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
          gradient: selected ? c.primaryGradient : null,
          color: selected ? null : c.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: selected ? Colors.transparent : c.border, width: 1.2)),
      alignment: Alignment.center,
      child: Text(label,
          maxLines: 1,
          style: TextStyle(
              color: selected ? Colors.white : c.text,
              fontWeight: FontWeight.w700,
              fontSize: 15)),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title,
      {super.key, this.action, this.icon, this.onAction});
  final String title;
  final String? action;
  final IconData? icon;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(children: [
      if (icon != null) ...[
        Icon(icon, color: c.cyan, size: 26),
        const SizedBox(width: 10)
      ],
      Expanded(
          child: Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w800,
                  fontSize: context.sp(22)))),
      if (action != null)
        InkWell(
            onTap: onAction,
            child: Row(children: [
              Text(action!,
                  style: TextStyle(
                      color: c.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              Icon(Icons.chevron_right_rounded, color: c.muted, size: 24)
            ])),
    ]);
  }
}

class MatchHeroCard extends StatelessWidget {
  const MatchHeroCard({super.key, this.compact = false, this.onWatch});
  final bool compact;
  final VoidCallback? onWatch;
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final h = compact
        ? (context.w <= 360 ? 360.0 : 380.0)
        : (context.w <= 360
            ? 340.0
            : context.w <= 390
                ? 350.0
                : 360.0);
    return Container(
      height: h,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
              color: c.isDark ? c.border : Colors.white.withValues(alpha: .7),
              width: 1.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: c.isDark ? .28 : .16),
                blurRadius: 22,
                offset: const Offset(0, 10))
          ]),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        Image.asset('assets/images/stadium_live.png', fit: BoxFit.cover),
        Container(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
              Colors.black.withValues(alpha: .22),
              Colors.black.withValues(alpha: .48),
              Colors.black.withValues(alpha: .75)
            ]))),
        Padding(
          padding: EdgeInsets.all(context.w <= 360 ? 18 : 22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const LivePill(compact: true),
              const SizedBox(width: 12),
              Expanded(
                  child: Text('1st Test • Day 1',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: .96),
                          fontWeight: FontWeight.w700,
                          fontSize: 16))),
              _viewerPill('128K')
            ]),
            const SizedBox(height: 12),
            Text('West Indies Tour of New Zealand, 2025',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: .96),
                    fontWeight: FontWeight.w700,
                    fontSize: context.sp(16))),
            const Spacer(),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _heroTeam(context, AppData.nz),
                  Column(children: [
                    _vsCircle(context),
                    const SizedBox(height: 12),
                    Text('158/3',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: context.w <= 390 ? 38 : 42,
                            fontWeight: FontWeight.w900,
                            height: 1)),
                    Text('(38.4 OV)',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: .95),
                            fontSize: context.sp(17),
                            fontWeight: FontWeight.w700)),
                  ]),
                  _heroTeam(context, AppData.wi),
                ]),
            const Spacer(),
            Center(
                child: Text('NZ won the toss & chose to bat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w800,
                        fontSize: context.sp(15)))),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: onWatch,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 54,
                  width: 250,
                  decoration: BoxDecoration(
                    gradient: c.primaryGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                          color: c.primary.withValues(alpha: .35),
                          blurRadius: 16,
                          offset: const Offset(0, 6))
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_circle_fill_rounded,
                          color: Colors.white, size: 26),
                      SizedBox(width: 10),
                      Text(
                        'Watch Live',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!compact) const SizedBox(height: 10),
            if (!compact)
              Center(
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    for (int i = 0; i < 3; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == 0 ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: i == 0
                                ? c.cyan
                                : Colors.white.withValues(alpha: .4),
                            borderRadius: BorderRadius.circular(4)),
                      )
                  ])),
          ]),
        ),
      ]),
    );
  }

  Widget _viewerPill(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .95),
          borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        const Icon(Icons.visibility_rounded,
            size: 18, color: Color(0xff061a35)),
        const SizedBox(width: 5),
        Text(text,
            style: const TextStyle(
                color: Color(0xff061a35),
                fontWeight: FontWeight.w900,
                fontSize: 13))
      ]));
  Widget _heroTeam(BuildContext context, Team team) => SizedBox(
      width: context.w <= 390 ? 94 : 114,
      child: Column(children: [
        TeamBadge(team, size: context.w <= 390 ? 70 : 84),
        const SizedBox(height: 10),
        Text(team.name.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: context.w <= 390 ? 11 : context.sp(13)))
      ]));
  Widget _vsCircle(BuildContext context) => Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.cric.card.withValues(alpha: .88),
          border: Border.all(
              color: Colors.white.withValues(alpha: .3), width: 1.5)),
      child: Text('VS',
          style: TextStyle(
              color: context.cric.text,
              fontWeight: FontWeight.w900,
              fontSize: 14)));
}

class EmptyOrErrorImage extends StatelessWidget {
  const EmptyOrErrorImage(
      {super.key, required this.asset, required this.fallback});
  final String asset;
  final String fallback;
  @override
  Widget build(BuildContext context) => Image.asset(asset,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Center(
          child: Text(fallback,
              style: TextStyle(
                  color: context.cric.text, fontWeight: FontWeight.w900))));
}
