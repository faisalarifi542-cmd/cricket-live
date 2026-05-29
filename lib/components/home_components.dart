import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../components.dart';
import '../models.dart';

class HomeHeroCard extends StatelessWidget {
  const HomeHeroCard({
    super.key,
    required this.fixture,
    this.onButtonTap,
    this.finished = false,
    this.live = false,
  });

  final HeroFixture fixture;
  final VoidCallback? onButtonTap;
  final bool finished;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final w = context.w;
    final narrow = w <= 400;
    final badgeSize = narrow ? 78.0 : (w <= 480 ? 90.0 : 110.0);
    final cardPad = narrow ? 14.0 : 18.0;
    return Container(
      padding: EdgeInsets.all(cardPad),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: .32),
              blurRadius: 26,
              offset: const Offset(0, 12))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/stadium_live.png',
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
                  colors: [
                    Colors.black.withValues(alpha: .22),
                    Colors.black.withValues(alpha: .68)
                  ],
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
                                color: Colors.white.withValues(alpha: .88),
                                fontWeight: FontWeight.w700))),
                ],
              ),
              SizedBox(height: narrow ? 14 : 18),
              Center(
                child: Text(fixture.series,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w800,
                        fontSize: context.sp(15))),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  finished ? 'India vs Australia' : fixture.date,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: context.sp(narrow ? 20 : 24)),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  fixture.time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.cyan,
                      fontWeight: FontWeight.w700,
                      fontSize: context.sp(17)),
                ),
              ),
              SizedBox(height: narrow ? 12 : 16),
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
                        width: narrow ? 52 : 68,
                        height: narrow ? 52 : 68,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: .22),
                          border: Border.all(color: c.border),
                        ),
                        alignment: Alignment.center,
                        child: Text(fixture.centerTitle,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: narrow ? 18 : 22,
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
              SizedBox(height: narrow ? 12 : 16),
              if (finished)
                Center(
                  child: Text(fixture.venue,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: .82),
                          fontWeight: FontWeight.w600)),
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_on_outlined,
                        color: Colors.white.withValues(alpha: .72), size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                        child: Text(fixture.venue.split('\n').first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: .78),
                                fontWeight: FontWeight.w600))),
                  ],
                ),
              SizedBox(height: narrow ? 16 : 20),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: GradientButton(
                    label: fixture.button,
                    icon: finished
                        ? Icons.list_alt_rounded
                        : live
                            ? Icons.play_circle_fill_rounded
                            : Icons.notifications_none_rounded,
                    outlined: finished,
                    onTap: onButtonTap,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    4,
                    (i) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == 0 ? 26 : 10,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == 0
                            ? c.cyan
                            : Colors.white.withValues(alpha: .26),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroTeamBlock(
      BuildContext context, TeamInfo team, String stat, double badgeSize) {
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
        const SizedBox(height: 4),
        Text(stat,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Colors.white.withValues(alpha: .95),
                fontSize: context.sp(14),
                fontWeight: FontWeight.w700)),
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
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w700, height: 1.5)),
        ],
      ),
    );
  }
}

class PlayerOfMatchCard extends StatelessWidget {
  const PlayerOfMatchCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final narrow = context.w <= 400;
    final avatarSize = narrow ? 88.0 : 122.0;
    final headerSize = narrow ? 36.0 : 44.0;
    return PremiumCard(
      padding: EdgeInsets.all(narrow ? 14 : 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              PlayerAvatar(
                  player: AppData.indiaSquadTop.first,
                  size: avatarSize,
                  borderColor: Colors.white.withValues(alpha: .42)),
              const SizedBox(height: 8),
              SizedBox(
                width: avatarSize + 6,
                child: Text(
                  'Rohit Sharma',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w800,
                      fontSize: context.sp(15)),
                ),
              ),
              Text('India', style: TextStyle(color: c.muted, fontSize: 12)),
            ],
          ),
          SizedBox(width: narrow ? 12 : 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: StatusBadge(
                        label: 'PLAYER OF THE MATCH',
                        color: c.cyan,
                        filled: true)),
                const SizedBox(height: 14),
                Text('121*',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: headerSize,
                        fontWeight: FontWeight.w900,
                        height: .9)),
                const SizedBox(height: 6),
                Text('(107)',
                    style:
                        TextStyle(color: c.muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Divider(color: c.border),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Expanded(child: _StatValue(title: 'Runs', value: '121')),
                    Expanded(child: _StatValue(title: 'Balls', value: '107')),
                    Expanded(child: _StatValue(title: 'SR', value: '113.08')),
                  ],
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Expanded(child: _StatValue(title: 'Fours', value: '11')),
                    Expanded(child: _StatValue(title: 'Sixes', value: '6')),
                    Expanded(child: _StatValue(title: 'Wkts', value: '1')),
                  ],
                ),
              ],
            ),
          )
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

class _StatValue extends StatelessWidget {
  const _StatValue({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                color: c.text, fontWeight: FontWeight.w900, fontSize: 28)),
        const SizedBox(height: 4),
        Text(title, style: TextStyle(color: c.muted)),
      ],
    );
  }
}
