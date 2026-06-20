import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../components.dart';
import '../models.dart';

class HomeHeroCard extends StatelessWidget {
  const HomeHeroCard({
    super.key,
    required this.fixture,
    this.onTap,
    this.onButtonTap,
    this.finished = false,
    this.live = false,
    this.showButton = true,
  });

  final HeroFixture fixture;
  final VoidCallback? onTap;
  final VoidCallback? onButtonTap;
  final bool finished;
  final bool live;
  final bool showButton;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final card = LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final compact = w <= 390 || h < 430;
        final badgeSize = compact ? 70.0 : (w <= 480 ? 82.0 : 96.0);
        final cardPad = compact ? 12.0 : 16.0;
        final gap = compact ? 7.0 : 10.0;
        final showVenue = h >= 365;
        final showStatusLine = h >= 385;
        final buttonHeight = compact ? 42.0 : 48.0;
        final buttonWidth = compact ? 210.0 : 250.0;
        return Container(
      padding: EdgeInsets.all(cardPad),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: c.border),
        boxShadow: c.heroShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/stadium_live.webp',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const EmptyOrErrorImage(label: 'Stadium'),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: c.matchCardOverlayColors,
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusBadge(
                      label: fixture.badge,
                      color: finished ? c.success : (live ? c.live : c.cyan),
                      filled: true),
                  const Spacer(),
                  if (finished)
                    Flexible(
                        child: Text(fixture.date,
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.onImageText,
                                fontWeight: FontWeight.w700))),
                ],
              ),
              SizedBox(height: gap),
              Center(
                child: Text(fixture.series,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w800,
                        fontSize: context.sp(compact ? 13 : 15))),
              ),
              SizedBox(height: gap),
              Center(
                child: Text(
                  fixture.date,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: context.sp(compact ? 18 : 22)),
                ),
              ),
              if (showStatusLine) ...[
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    fixture.time,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w700,
                        fontSize: context.sp(compact ? 14 : 16)),
                  ),
                ),
              ],
              SizedBox(height: gap),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                      child: _heroTeamBlock(context, fixture.left,
                          fixture.leftMeta ?? fixture.left.code, badgeSize)),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: compact ? 46 : 58,
                        height: compact ? 46 : 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.isDark ? Colors.black.withValues(alpha: .22) : c.card.withValues(alpha: .55),
                          border: Border.all(color: c.border),
                        ),
                        alignment: Alignment.center,
                        child: Text(fixture.centerTitle,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 16 : 20,
                                fontWeight: FontWeight.w900)),
                      ),
                      if (fixture.result != null) ...[
                        const SizedBox(height: 10),
                        Text(fixture.result!,
                            style: TextStyle(
                                color: c.success,
                                fontWeight: FontWeight.w800,
                                fontSize: context.sp(17))),
                      ]
                    ],
                  ),
                  Expanded(
                      child: _heroTeamBlock(context, fixture.right,
                          fixture.rightMeta ?? fixture.right.code, badgeSize)),
                ],
              ),
              SizedBox(height: gap),
              if (finished && showVenue)
                Center(
                  child: Text(fixture.venue,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.onImageText,
                          fontWeight: FontWeight.w600)),
                )
              else if (!finished && showVenue)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_on_outlined,
                        color: c.onImageText, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                        child: Text(fixture.venue.split('\n').first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.onImageText,
                                fontWeight: FontWeight.w600))),
                  ],
                ),
              const Spacer(),
              if (showButton) ...[
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: buttonWidth),
                    child: GradientButton(
                      label: fixture.button,
                      icon: finished
                          ? Icons.list_alt_rounded
                          : live
                              ? Icons.play_circle_fill_rounded
                              : Icons.notifications_none_rounded,
                      outlined: finished,
                      height: buttonHeight,
                      onTap: onButtonTap,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
      },
    );

    if (onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      ),
    );
  }

  Widget _heroTeamBlock(
      BuildContext context, TeamInfo team, String stat, double badgeSize) {
    final c = context.cric;
    // Don't show stat if it's the same as the team code (avoids duplication)
    final showStat = stat != team.code && stat != team.shortName;

    return Column(
      children: [
        TeamBadge(team, size: badgeSize),
        const SizedBox(height: 10),
        Text(team.shortName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: context.sp(16))),
        if (showStat) ...[
          const SizedBox(height: 4),
          Text(stat,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.onImageText,
                  fontSize: context.sp(14),
                  fontWeight: FontWeight.w700)),
        ],
      ],
    );
  }
}

class UpcomingSeriesMiniCard extends StatelessWidget {
  const UpcomingSeriesMiniCard({super.key, required this.series, this.onTap});

  final CompactFixture series;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            TeamBadge(series.left, size: 46),
            const SizedBox(width: 8),
            TeamBadge(series.right, size: 46)
          ]),
          const SizedBox(height: 14),
          Text(series.series,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 6),
          Text(series.subtitle, style: TextStyle(color: c.muted)),
          const SizedBox(height: 14),
          Text(series.date,
              style: TextStyle(color: c.cyan, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class FeaturedFixtureCard extends StatelessWidget {
  const FeaturedFixtureCard({super.key, required this.fixture, this.onTap});

  final CompactFixture fixture;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: PremiumCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fixture.series,
                style: TextStyle(
                    color: context.cric.cyan, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              children: [
                TeamBadge(fixture.left, size: 54),
                const SizedBox(width: 12),
                Text('VS',
                    style: TextStyle(
                        color: context.cric.text, fontWeight: FontWeight.w900)),
                const SizedBox(width: 12),
                TeamBadge(fixture.right, size: 54),
              ],
            ),
            const SizedBox(height: 14),
            Text(fixture.subtitle,
                style: TextStyle(
                    color: context.cric.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 18)),
            const Spacer(),
            Text(fixture.date, style: TextStyle(color: context.cric.muted)),
            const SizedBox(height: 12),
            const GradientButton(
                label: 'Notify Me',
                icon: Icons.notifications_none_rounded,
                height: 46),
          ],
        ),
      ),
    );
  }
}

class RecentResultMiniCard extends StatelessWidget {
  const RecentResultMiniCard({super.key, required this.result, this.onTap});

  final CompactFixture result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(result.series,
              style: TextStyle(color: c.cyan, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(children: [
                TeamBadge(result.left, size: 50),
                const SizedBox(height: 8),
                Text(result.left.code,
                    style:
                        TextStyle(color: c.text, fontWeight: FontWeight.w800))
              ]),
              Text('VS',
                  style: TextStyle(color: c.text, fontWeight: FontWeight.w900)),
              Column(children: [
                TeamBadge(result.right, size: 50),
                const SizedBox(height: 8),
                Text(result.right.code,
                    style:
                        TextStyle(color: c.text, fontWeight: FontWeight.w800))
              ]),
            ],
          ),
          const SizedBox(height: 12),
          Text(result.date,
              style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          StatusBadge(label: result.status, color: c.cyan),
          const SizedBox(height: 10),
          Text(result.venue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w700, height: 1.5)),
        ],
      ),
    );
  }
}

class QuickAccessCard extends StatelessWidget {
  const QuickAccessCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                  colors: [accent.withValues(alpha: .88), accent]),
              boxShadow: [
                BoxShadow(
                    color: accent.withValues(alpha: .35),
                    blurRadius: 18,
                    offset: const Offset(0, 8))
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w800, fontSize: 16),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(color: c.muted), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
