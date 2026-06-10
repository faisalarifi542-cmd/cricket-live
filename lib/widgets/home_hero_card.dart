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
        boxShadow: c.heroShadow,
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
                                color: Colors.white.withValues(alpha: .85),
                                fontWeight: FontWeight.w700,
                                fontSize: 13))),
                ],
              ),
              if (!finished) ...[
                const SizedBox(height: 8),
                Text(fixture.series,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .92),
                        fontWeight: FontWeight.w800,
                        fontSize: context.sp(14))),
                const SizedBox(height: 4),
                Text(fixture.date,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .75),
                        fontSize: 13)),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  TeamBadge(fixture.left,
                      size: badgeSize,
                      borderColor: Colors.white.withValues(alpha: .85)),
                  const Spacer(),
                  Text(fixture.centerTitle,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: .95),
                          fontWeight: FontWeight.w900,
                          fontSize: context.sp(18))),
                  const Spacer(),
                  TeamBadge(fixture.right,
                      size: badgeSize,
                      borderColor: Colors.white.withValues(alpha: .85)),
                ],
              ),
              if (fixture.leftMeta != null || fixture.rightMeta != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: Text(fixture.leftMeta ?? '',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: context.sp(finished ? 20 : 17)))),
                    const Spacer(),
                    Expanded(
                        child: Text(fixture.rightMeta ?? '',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: .85),
                                fontWeight: FontWeight.w900,
                                fontSize: context.sp(finished ? 20 : 17)))),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              if (finished && fixture.result != null)
                Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                        color: c.success.withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(18),
                        border:
                            Border.all(color: c.success.withValues(alpha: .6))),
                    child: Text(fixture.result!,
                        style: TextStyle(
                            color: c.success,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                  ),
                )
              else
                Text(fixture.time,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .92),
                        fontWeight: FontWeight.w700,
                        fontSize: context.sp(16))),
              const SizedBox(height: 12),
              Text(fixture.venue,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .75),
                      fontSize: 13,
                      height: 1.4)),
              const SizedBox(height: 16),
              SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                      label: fixture.button,
                      icon: finished
                          ? Icons.bar_chart_rounded
                          : (live
                              ? Icons.play_circle_fill_rounded
                              : Icons.notifications_active_outlined),
                      onTap: onButtonTap)),
            ],
          ),
        ],
      ),
    );
  }
}
