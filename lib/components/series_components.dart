import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../components.dart';
import '../models.dart';

// =============================================================================
// SERIES HERO CARD
// =============================================================================

/// Premium series hero card.
///
/// On compact / mobile widths it stacks the title above the two team
/// badges (still feels balanced) and uses [FittedBox] to shrink large titles
/// so the card never overflows on 360 px screens.
class SeriesHeroCard extends StatelessWidget {
  const SeriesHeroCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final w = context.w;
    final compact = w < 380;
    final badge = compact ? 78.0 : (w < 480 ? 92.0 : 110.0);
    final pad = compact ? 14.0 : 18.0;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: c.cyan.withValues(alpha: .08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        // Hero keeps a consistent 16:11 ratio so its height adapts naturally
        // to whatever width is available. This is the root fix for the
        // overflow bars seen at 360px width.
        aspectRatio: compact ? 16 / 13 : (w < 480 ? 16 / 11 : 16 / 9),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/stadium_live.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const EmptyOrErrorImage(label: 'Series hero'),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: .15),
                    Colors.black.withValues(alpha: .72),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(pad),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      'INTERNATIONAL TOUR',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w800,
                        fontSize: context.sp(13),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      TeamBadge(AppData.india, size: badge),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: compact ? 8 : 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'India Tour of Australia',
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: context.sp(22),
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '2024-25',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: context.sp(28),
                                    height: 1.0,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.calendar_month_rounded,
                                        color:
                                            Colors.white.withValues(alpha: .85),
                                        size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      '22 Nov 2024 – 7 Jan 2025',
                                      style: TextStyle(
                                        color: c.cyan,
                                        fontWeight: FontWeight.w700,
                                        fontSize: context.sp(13.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      TeamBadge(AppData.australia, size: badge),
                    ],
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '3 Test  •  3 ODI  •  5 T20I',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .9),
                        fontSize: context.sp(14),
                        fontWeight: FontWeight.w700,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// OVERVIEW TAB
// =============================================================================

class SeriesOverviewTab extends StatelessWidget {
  const SeriesOverviewTab({super.key, required this.onOpenReminder});

  final VoidCallback onOpenReminder;

  @override
  Widget build(BuildContext context) {
    return StaggeredColumn(
      spacing: 16,
      children: [
        const _SeriesInfoCard(),
        _NextMatchCard(onOpenReminder: onOpenReminder),
        const _VenuesCard(),
        _FormAndInsightSection(context: context),
      ],
    );
  }
}

class _SeriesInfoCard extends StatelessWidget {
  const _SeriesInfoCard();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SERIES INFO',
              style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: context.sp(15),
                  letterSpacing: 1.2)),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (ctx, constraints) {
              final cols = constraints.maxWidth >= 540 ? 3 : 1;
              if (cols == 1) {
                return Column(
                  children: [
                    for (final e in AppData.seriesOverviewStats)
                      InfoListTile(
                        icon: e.icon,
                        label: e.label,
                        value: e.value,
                        valueColor:
                            e.label == 'Series Status' ? c.success : null,
                      ),
                  ],
                );
              }
              const spacing = 14.0;
              final tileW = computeGridChildWidth(
                maxWidth: constraints.maxWidth,
                columns: cols,
                spacing: spacing,
              );
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final e in AppData.seriesOverviewStats)
                    SizedBox(
                      width: tileW,
                      child: InfoListTile(
                        icon: e.icon,
                        label: e.label,
                        value: e.value,
                        valueColor:
                            e.label == 'Series Status' ? c.success : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NextMatchCard extends StatelessWidget {
  const _NextMatchCard({required this.onOpenReminder});

  final VoidCallback onOpenReminder;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final stacked = constraints.maxWidth < 520;
          final title = Text(
            'NEXT MATCH',
            style: TextStyle(
              color: c.cyan,
              fontWeight: FontWeight.w800,
              fontSize: context.sp(15),
              letterSpacing: 1.2,
            ),
          );
          final teams = _NextMatchTeams();
          final info = _NextMatchInfo(onOpenReminder: onOpenReminder);
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 14),
                Center(child: teams),
                const SizedBox(height: 18),
                info,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Center(child: teams)),
              Container(width: 1, height: 120, color: c.border),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 12), info],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NextMatchTeams extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final compact = context.isCompact;
    final size = compact ? 52.0 : 60.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamBadge(AppData.india, size: size),
        const SizedBox(width: 10),
        Text('VS',
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w900,
              fontSize: context.sp(16),
            )),
        const SizedBox(width: 10),
        TeamBadge(AppData.australia, size: size),
      ],
    );
  }
}

class _NextMatchInfo extends StatelessWidget {
  const _NextMatchInfo({required this.onOpenReminder});

  final VoidCallback onOpenReminder;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('22 – 26 Nov 2024',
            style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w800,
                fontSize: context.sp(15.5))),
        const SizedBox(height: 6),
        Text('Optus Stadium, Perth',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: c.muted, fontSize: context.sp(13.5), height: 1.4)),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PulseDot(color: c.cyan, size: 7),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Starts 9:30 AM (Local)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.text,
                    fontSize: context.sp(13.5),
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GradientButton(
          label: 'Set Reminder',
          icon: Icons.notifications_none_rounded,
          onTap: onOpenReminder,
          height: 46,
        ),
      ],
    );
  }
}

class _VenuesCard extends StatelessWidget {
  const _VenuesCard();

  static const _venues = [
    ('Perth Stadium', 'Perth'),
    ('Adelaide Oval', 'Adelaide'),
    ('The Gabba', 'Brisbane'),
    ('MCG', 'Melbourne'),
    ('SCG', 'Sydney'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VENUES',
              style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: context.sp(15),
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          SizedBox(
            height: 156,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              itemBuilder: (_, i) {
                final v = _venues[i];
                return _VenueChip(name: v.$1, city: v.$2);
              },
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemCount: _venues.length,
            ),
          ),
        ],
      ),
    );
  }
}

class _VenueChip extends StatelessWidget {
  const _VenueChip({required this.name, required this.city});

  final String name;
  final String city;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(8),
      radius: 18,
      child: SizedBox(
        width: 142,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 84,
                width: double.infinity,
                child: Image.asset(
                  'assets/images/stadium_live.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const EmptyOrErrorImage(label: 'Venue'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w800,
                  fontSize: context.sp(13.5)),
            ),
            Text(
              city,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: context.sp(12.5)),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormAndInsightSection extends StatelessWidget {
  const _FormAndInsightSection({required this.context});

  // ignore: unused_field
  final BuildContext context;

  @override
  Widget build(BuildContext ctx) {
    final c = ctx.cric;
    return LayoutBuilder(
      builder: (lb, constraints) {
        final side = constraints.maxWidth >= 760;
        final form = _FormCard();
        final insight = _InsightCard();
        if (side) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: form),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: insight),
            ],
          );
        }
        return Column(
          children: [
            form,
            const SizedBox(height: 16),
            insight,
            const SizedBox(height: 4),
            // ensure no accidental cut
            const SizedBox.shrink(),
            // Bottom subtle decoration line aligning with theme.
            Divider(color: c.border.withValues(alpha: 0)),
          ],
        );
      },
    );
  }
}

class _FormCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SERIES FORM / MOMENTUM',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: context.sp(15),
                  letterSpacing: 1.2)),
          const SizedBox(height: 14),
          _formRow(
              context, AppData.india, ['W', 'W', 'W', '-', '-'], 'Won Last 3'),
          const SizedBox(height: 12),
          _formRow(context, AppData.australia, ['L', 'W', 'L', '-', '-'],
              'Mixed Form'),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (ctx, cs) {
              const spacing = 10.0;
              final tileW = computeGridChildWidth(
                maxWidth: cs.maxWidth,
                columns: 2,
                spacing: spacing,
              );
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                    width: tileW,
                    child: _radialStat(context, 'Completed', 2, 'Matches'),
                  ),
                  SizedBox(
                    width: tileW,
                    child: _radialStat(context, 'Upcoming', 9, 'Matches',
                        accent: const Color(0xff5b8cff)),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _formRow(
      BuildContext context, TeamInfo team, List<String> form, String label) {
    final c = context.cric;
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final stacked = constraints.maxWidth < 320;
        final teamBlock = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TeamBadge(team, size: 26),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                team.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w700,
                    fontSize: context.sp(13.5)),
              ),
            ),
          ],
        );
        final formBubbles = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in form)
              Container(
                margin: const EdgeInsets.only(right: 6),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: item == 'W'
                      ? c.success.withValues(alpha: .22)
                      : item == 'L'
                          ? c.live.withValues(alpha: .22)
                          : c.card2,
                ),
                alignment: Alignment.center,
                child: Text(item,
                    style: TextStyle(
                        color: item == 'W'
                            ? c.success
                            : item == 'L'
                                ? c.live
                                : c.muted,
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5)),
              ),
          ],
        );
        final labelText = Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: label == 'Won Last 3' ? c.success : c.warning,
                fontWeight: FontWeight.w700,
                fontSize: context.sp(12)));

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              teamBlock,
              const SizedBox(height: 8),
              Row(
                children: [Expanded(child: formBubbles), labelText],
              ),
            ],
          );
        }
        return Row(
          children: [
            teamBlock,
            const SizedBox(width: 8),
            Expanded(child: formBubbles),
            labelText,
          ],
        );
      },
    );
  }

  Widget _radialStat(
      BuildContext context, String title, int value, String subtitle,
      {Color? accent}) {
    final c = context.cric;
    final a = accent ?? c.cyan;
    return PremiumCard(
      padding: const EdgeInsets.all(12),
      radius: 16,
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                    value: value == 2 ? .22 : .72,
                    strokeWidth: 6,
                    valueColor: AlwaysStoppedAnimation<Color>(a),
                    backgroundColor: c.card2),
                CountUpText(
                  value: value,
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: context.sp(17)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, fontSize: 12)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w800,
                        fontSize: context.sp(14))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SERIES INSIGHT',
              style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: context.sp(15),
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          const Center(
              child: Icon(Icons.emoji_events_rounded,
                  color: Color(0xffffc83d), size: 76)),
          const SizedBox(height: 12),
          Text('Trophy at Stake',
              style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w800,
                  fontSize: context.sp(16.5))),
          const SizedBox(height: 6),
          Text('Border-Gavaskar Trophy',
              style: TextStyle(
                  color: c.muted, height: 1.4, fontSize: context.sp(13.5))),
        ],
      ),
    );
  }
}

// =============================================================================
// MATCHES TAB
// =============================================================================

class SeriesMatchesTab extends StatelessWidget {
  const SeriesMatchesTab({super.key, required this.onOpenCalendar});

  final VoidCallback onOpenCalendar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('UPCOMING MATCHES'),
        const SizedBox(height: 10),
        StaggeredColumn(
          spacing: 12,
          children: [
            for (final row in AppData.seriesUpcomingRows)
              SeriesMatchRowCard(row: row),
          ],
        ),
        const SizedBox(height: 16),
        const _SectionLabel('COMPLETED MATCHES'),
        const SizedBox(height: 10),
        StaggeredColumn(
          spacing: 12,
          children: [
            for (final row in AppData.seriesCompletedRows)
              SeriesMatchRowCard(row: row, completed: true),
          ],
        ),
        const SizedBox(height: 16),
        GradientButton(
          label: 'Add Series to Calendar',
          icon: Icons.event_available_rounded,
          outlined: true,
          onTap: onOpenCalendar,
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
          color: context.cric.cyan,
          fontWeight: FontWeight.w800,
          fontSize: context.sp(15),
          letterSpacing: 1.2,
        ));
  }
}

// =============================================================================
// MATCH ROW CARD
// =============================================================================

class SeriesMatchRowCard extends StatelessWidget {
  const SeriesMatchRowCard(
      {super.key, required this.row, this.completed = false});

  final SeriesMatchRow row;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final statusColor = completed
        ? (row.status.contains('IND') ? c.success : const Color(0xff5ce1ff))
        : c.cyan;
    return PremiumCard(
      onTap: () {}, // tap-scale + ripple
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: match label + status pill
          Row(
            children: [
              Expanded(
                child: Text(
                  row.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.cyan,
                      fontWeight: FontWeight.w800,
                      fontSize: context.sp(15)),
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(label: row.status, color: statusColor, filled: true),
            ],
          ),
          const SizedBox(height: 12),
          // Middle row: teams + VS + date range. Stacks on very narrow.
          LayoutBuilder(
            builder: (ctx, cs) {
              final stacked = cs.maxWidth < 320;
              final teams = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TeamBadge(row.left, size: 32),
                  const SizedBox(width: 8),
                  Text('VS',
                      style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontSize: context.sp(13))),
                  const SizedBox(width: 8),
                  TeamBadge(row.right, size: 32),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      '${row.left.code} vs ${row.right.code}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w700,
                          fontSize: context.sp(13)),
                    ),
                  ),
                ],
              );
              final date = Text(
                row.date,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w800,
                    fontSize: context.sp(14)),
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    teams,
                    const SizedBox(height: 8),
                    date,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: teams),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: date,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Divider(color: c.border, height: 12),
          const SizedBox(height: 6),
          // Bottom row: venue + countdown/result + chevron
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.location_on_outlined, color: c.muted, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  row.venue.replaceAll('\n', ', '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.muted, height: 1.35, fontSize: context.sp(12.5)),
                ),
              ),
              const SizedBox(width: 8),
              _Countdown(text: row.trailing, completed: completed),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: c.muted, size: 22),
            ],
          ),
        ],
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.text, required this.completed});
  final String text;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final lines = text.split('\n');
    final color = completed ? c.success : c.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lines.isNotEmpty)
          Text(
            lines.first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.muted,
              fontSize: context.sp(11),
              fontWeight: FontWeight.w700,
            ),
          ),
        if (lines.length > 1)
          Text(
            lines.sublist(1).join(' '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: context.sp(13),
              fontWeight: FontWeight.w900,
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// SQUADS TAB
// =============================================================================

class SeriesSquadsTab extends StatelessWidget {
  const SeriesSquadsTab({
    super.key,
    required this.squadTeam,
    required this.onTeamChanged,
    required this.onOpenPlayer,
  });

  final int squadTeam;
  final ValueChanged<int> onTeamChanged;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    const top = AppData.indiaSquadTop;
    const middle = AppData.indiaSquadMiddle;
    const allRounders = AppData.indiaAllRounders;
    const bowlers = AppData.indiaBowlers;
    const reserves = AppData.indiaReserves;
    return Column(
      children: [
        SegmentedTabs(
          items: const [('India', null), ('Australia', null)],
          selected: squadTeam,
          onChanged: onTeamChanged,
          height: 52,
        ),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(.04, 0),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: Column(
            key: ValueKey(squadTeam),
            children: [
              _SquadSection(
                  title: 'TOP ORDER', players: top, onTap: onOpenPlayer),
              const SizedBox(height: 16),
              _SquadSection(
                  title: 'MIDDLE ORDER', players: middle, onTap: onOpenPlayer),
              const SizedBox(height: 16),
              _SquadSection(
                  title: 'ALL-ROUNDERS',
                  players: allRounders,
                  onTap: onOpenPlayer),
              const SizedBox(height: 16),
              _BowlersCard(bowlers: bowlers, onTap: onOpenPlayer),
              const SizedBox(height: 16),
              const _ReservePlayersCard(reserves: reserves),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (ctx, cs) {
                  final stacked = cs.maxWidth < 380;
                  const compare = GradientButton(
                      label: 'Compare Teams',
                      icon: Icons.groups_rounded,
                      outlined: true);
                  const view = GradientButton(
                      label: 'View Full Squad',
                      icon: Icons.arrow_forward_rounded);
                  if (stacked) {
                    return const Column(
                      children: [
                        compare,
                        SizedBox(height: 10),
                        view,
                      ],
                    );
                  }
                  return const Row(
                    children: [
                      Expanded(child: compare),
                      SizedBox(width: 12),
                      Expanded(child: view),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Responsive squad section: uses LayoutBuilder to pick 2-column on mobile,
/// 3 on tablet, 4 on desktop — never the broken 4 or 5 columns at 360px.
class _SquadSection extends StatelessWidget {
  const _SquadSection({
    required this.title,
    required this.players,
    required this.onTap,
  });

  final String title;
  final List<PlayerInfo> players;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: context.sp(15),
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (ctx, cs) {
              // Minimum 140 px card so names like "Suryakumar" fit. Never
              // exceed 4 columns even on huge widths.
              const minW = 140.0;
              const spacing = 10.0;
              var cols = ((cs.maxWidth + spacing) / (minW + spacing)).floor();
              if (cols < 2) cols = 2;
              if (cols > 4) cols = 4;
              final tileW = computeGridChildWidth(
                maxWidth: cs.maxWidth,
                columns: cols,
                spacing: spacing,
              );
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final p in players)
                    SizedBox(
                      width: tileW,
                      child: SquadPlayerCard(player: p, onTap: onTap),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BowlersCard extends StatelessWidget {
  const _BowlersCard({required this.bowlers, required this.onTap});
  final List<PlayerInfo> bowlers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BOWLERS',
              style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: context.sp(15),
                  letterSpacing: 1.2)),
          const SizedBox(height: 10),
          for (var i = 0; i < bowlers.length; i++)
            Padding(
              padding:
                  EdgeInsets.only(bottom: i == bowlers.length - 1 ? 0 : 10),
              child: PremiumCard(
                onTap: onTap,
                radius: 16,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    PlayerAvatar(player: bowlers[i], size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        bowlers[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w700,
                            fontSize: context.sp(14)),
                      ),
                    ),
                    const StatusBadge(
                        label: 'BOWL',
                        color: Color(0xff8b5cff),
                        filled: true),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReservePlayersCard extends StatelessWidget {
  const _ReservePlayersCard({required this.reserves});
  final List<PlayerInfo> reserves;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RESERVE PLAYERS',
              style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: context.sp(15),
                  letterSpacing: 1.2)),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (ctx, cs) {
              const minW = 140.0;
              const spacing = 10.0;
              var cols = ((cs.maxWidth + spacing) / (minW + spacing)).floor();
              if (cols < 2) cols = 2;
              if (cols > 4) cols = 4;
              final tileW = computeGridChildWidth(
                maxWidth: cs.maxWidth,
                columns: cols,
                spacing: spacing,
              );
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final p in reserves)
                    SizedBox(
                      width: tileW,
                      child: ReservePlayerChip(player: p),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// STATS TAB
// =============================================================================

class SeriesStatsTab extends StatelessWidget {
  const SeriesStatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const StaggeredColumn(
      spacing: 16,
      children: [
        _PointsTableCard(),
        _LeadersSection(),
        _SeriesStatsCard(),
      ],
    );
  }
}

class _PointsTableCard extends StatelessWidget {
  const _PointsTableCard();

  // Fixed pixel widths keep the table readable when it scrolls horizontally
  // on narrow phones. Using Expanded inside a horizontal SingleChildScrollView
  // collapses every column to 0 because the parent gives unbounded width.
  static const double _rankW = 36;
  static const double _teamW = 168;
  static const double _statW = 44;
  static const double _statWideW = 60;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('POINTS TABLE (TEST SERIES)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: context.sp(15),
                  letterSpacing: 1.2)),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  decoration: BoxDecoration(
                      color: c.card2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.border)),
                  child: const Row(
                    children: [
                      _Cell('#', width: _rankW, header: true),
                      _Cell('TEAM',
                          width: _teamW, header: true, align: TextAlign.left),
                      _Cell('P', width: _statW, header: true),
                      _Cell('W', width: _statW, header: true),
                      _Cell('L', width: _statW, header: true),
                      _Cell('D', width: _statW, header: true),
                      _Cell('PTS', width: _statWideW, header: true),
                      _Cell('PCT', width: _statWideW, header: true),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                _pointsRow(context, '1', AppData.india,
                    ['3', '2', '1', '0', '16', '66.67']),
                Divider(color: c.border),
                _pointsRow(context, '2', AppData.australia,
                    ['3', '1', '2', '0', '8', '33.33']),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: c.muted, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text('India won the Test series 2-1',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w700,
                        fontSize: context.sp(13))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pointsRow(
      BuildContext context, String rank, TeamInfo team, List<String> stats) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          _Cell(rank, width: _rankW),
          SizedBox(
            width: _teamW,
            child: Row(
              children: [
                TeamBadge(team, size: 26),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    team.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w800,
                        fontSize: context.sp(13.5)),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < stats.length; i++)
            _Cell(stats[i], width: i >= 4 ? _statWideW : _statW),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(
    this.text, {
    required this.width,
    this.header = false,
    this.align = TextAlign.center,
  });

  final String text;
  final double width;
  final bool header;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: TextStyle(
          color: header ? c.muted : c.text,
          fontWeight: header ? FontWeight.w800 : FontWeight.w700,
          fontSize: context.sp(13),
        ),
      ),
    );
  }
}

class _LeadersSection extends StatelessWidget {
  const _LeadersSection();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, cs) {
        final wide = cs.maxWidth >= 760;
        const runs = _LeaderCard(
            title: 'TOP RUN SCORERS', players: AppData.topRunScorers);
        const wickets = _LeaderCard(
            title: 'TOP WICKET TAKERS', players: AppData.topWickets);
        if (wide) {
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: runs),
              SizedBox(width: 16),
              Expanded(child: wickets),
            ],
          );
        }
        return const Column(
          children: [
            runs,
            SizedBox(height: 16),
            wickets,
          ],
        );
      },
    );
  }
}

class _LeaderCard extends StatelessWidget {
  const _LeaderCard({required this.title, required this.players});

  final String title;
  final List<PlayerInfo> players;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: context.sp(15),
                  letterSpacing: 1.2)),
          const SizedBox(height: 12),
          for (var i = 0; i < players.length; i++) ...[
            _LeaderRow(player: players[i]),
            if (i != players.length - 1) Divider(color: c.border, height: 16),
          ],
          const SizedBox(height: 12),
          const GradientButton(
            label: 'View Full List',
            icon: Icons.arrow_forward_rounded,
            outlined: true,
            height: 44,
          ),
        ],
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.player});
  final PlayerInfo player;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        PlayerAvatar(player: player, size: 40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                player.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w800,
                    fontSize: context.sp(14)),
              ),
              Text(
                player.team.code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.muted, fontSize: context.sp(12)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CountUpText(
              value: int.tryParse(
                      player.stat?.replaceAll(RegExp(r'[^0-9]'), '') ?? '') ??
                  0,
              style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w900,
                  fontSize: context.sp(20)),
            ),
            Text(
              player.secondaryStat ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.muted, fontSize: context.sp(11.5)),
            ),
          ],
        ),
      ],
    );
  }
}

class _SeriesStatsCard extends StatelessWidget {
  const _SeriesStatsCard();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    const items = [
      (Icons.sports_cricket_rounded, 'Most Runs', '766', 'Total Runs'),
      (Icons.sports_baseball_rounded, 'Most Wickets', '58', 'Total Wickets'),
      (
        Icons.calendar_month_rounded,
        'Matches Played',
        '11',
        '3 Tests • 3 ODIs • 5 T20Is'
      ),
      (Icons.stadium_outlined, 'Venues', '5', 'Perth, Adelaide, MCG +2'),
      (Icons.emoji_events_outlined, 'Player of Series', 'J. Bumrah', '(IND)'),
      (
        Icons.star_outline_rounded,
        'Series Result',
        'India won',
        '2-1 (Test) | 2-1 (ODI)'
      ),
    ];
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SERIES STATS',
              style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: context.sp(15),
                  letterSpacing: 1.2)),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (ctx, cs) {
              final cols = cs.maxWidth >= 760
                  ? 3
                  : cs.maxWidth >= 460
                      ? 2
                      : 1;
              const spacing = 14.0;
              final tileW = computeGridChildWidth(
                maxWidth: cs.maxWidth,
                columns: cols,
                spacing: spacing,
              );
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final it in items)
                    ResponsiveStatTile(
                      icon: it.$1,
                      title: it.$2,
                      value: it.$3,
                      subtitle: it.$4,
                      tileWidth: tileW,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SQUAD PLAYER CARD / RESERVE / STAT TILE
// =============================================================================

class SquadPlayerCard extends StatelessWidget {
  const SquadPlayerCard({super.key, required this.player, this.onTap});

  final PlayerInfo player;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final badgeColor = switch (player.role) {
      'BAT' => c.cyan,
      'WK' => const Color(0xff3b82f6),
      'AR' => const Color(0xff14b8a6),
      _ => const Color(0xff8b5cff),
    };
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      radius: 18,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (player.order != null)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.card2,
                      border: Border.all(color: c.cyan.withValues(alpha: .6))),
                  alignment: Alignment.center,
                  child: Text(
                    '${player.order}',
                    style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w900,
                        fontSize: 11),
                  ),
                ),
              const Spacer(),
              StatusBadge(label: player.role, color: badgeColor, filled: true),
            ],
          ),
          const SizedBox(height: 6),
          PlayerAvatar(
              player: player,
              size: 68,
              borderColor: Colors.white.withValues(alpha: .26)),
          const SizedBox(height: 10),
          Text(
            player.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w800,
                fontSize: context.sp(13.5),
                height: 1.15),
          ),
          if (player.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              player.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w700,
                  fontSize: context.sp(11),
                  height: 1.2),
            ),
          ],
        ],
      ),
    );
  }
}

class ReservePlayerChip extends StatelessWidget {
  const ReservePlayerChip({super.key, required this.player});

  final PlayerInfo player;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final badgeColor = switch (player.role) {
      'BOWL' => const Color(0xff8b5cff),
      'AR' => const Color(0xff14b8a6),
      'WK' => const Color(0xff3b82f6),
      _ => c.cyan,
    };
    return PremiumCard(
      padding: const EdgeInsets.all(10),
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              PlayerAvatar(player: player, size: 36),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  player.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                      fontSize: context.sp(12.5),
                      height: 1.2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
                label: player.role, color: badgeColor, filled: true),
          ),
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // Backwards-compatible wrapper. Previously this widget computed its width
    // from `context.w` which assumed the screen padding but ignored card
    // padding — causing right-overflow inside info cards. It now lays itself
    // out flexibly using the available constraints from its parent.
    return LayoutBuilder(
      builder: (ctx, cs) {
        final w =
            cs.hasBoundedWidth ? cs.maxWidth : MediaQuery.sizeOf(ctx).width;
        final cols = w >= 460 ? 2 : 1;
        const spacing = 14.0;
        final tileW = computeGridChildWidth(
          maxWidth: w,
          columns: cols,
          spacing: spacing,
        );
        return ResponsiveStatTile(
          icon: icon,
          title: title,
          value: value,
          subtitle: subtitle,
          tileWidth: tileW,
        );
      },
    );
  }
}
