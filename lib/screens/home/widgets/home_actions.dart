part of '../home_screen.dart';

// ---------------------------------------------------------------------------
// Action bar (Watch Live / View Match) shared by the list match cards.
// Quick-action cards (Live Scores / Commentary / Schedule / Rankings / Stats)
// were removed — the bottom nav already covers Matches/Schedule/Series/More.
// ---------------------------------------------------------------------------

class _HomeActionBar extends StatelessWidget {
  const _HomeActionBar({
    required this.onViewMatch,
    this.onWatchLive,
    this.watchEnabled = false,
    this.showWatch = false,
    this.showView = true,
  });

  final VoidCallback onViewMatch;

  /// Whether to render the Watch Live button at all. Live cards always set
  /// this true (kept visible even when disabled); Upcoming/Finished leave it
  /// false so only the full-width View Match button shows.
  final bool showWatch;
  final VoidCallback? onWatchLive;
  final bool watchEnabled;
  final bool showView;

  @override
  Widget build(BuildContext context) {
    // Nothing to show — collapse the bar entirely.
    if (!showWatch && !showView) return const SizedBox.shrink();
    final watchBtn = showWatch
        ? Opacity(
            opacity: watchEnabled ? 1 : 0.55,
            child: _FilledActionButton(
              icon: Icons.podcasts_rounded,
              label: 'Watch Live',
              onTap: watchEnabled ? onWatchLive : null,
            ),
          )
        : null;
    final viewBtn = showView
        ? _OutlinedActionButton(
            icon: Icons.bar_chart_rounded,
            label: 'Match Center',
            trailingChevron: true,
            onTap: onViewMatch,
          )
        : null;

    if (watchBtn != null && viewBtn != null) {
      return Row(
        children: [
          Expanded(child: watchBtn),
          const SizedBox(width: 10),
          Expanded(child: viewBtn),
        ],
      );
    }
    return watchBtn ?? viewBtn ?? const SizedBox.shrink();
  }
}

/// Large filled gradient action button (Watch Live).
class _FilledActionButton extends StatelessWidget {
  const _FilledActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff35e2ff), Color(0xff0a86ff)],
          ),
          borderRadius: BorderRadius.circular(13),
          boxShadow: c.isDark
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .45),
                    blurRadius: 16,
                    spreadRadius: -3,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Large outlined action button (View Match).
class _OutlinedActionButton extends StatelessWidget {
  const _OutlinedActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingChevron = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool trailingChevron;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: c.isDark ? c.card.withValues(alpha: .35) : c.card,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: c.cyan.withValues(alpha: .6), width: 1.2),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.cyan.withValues(alpha: .16),
                border: Border.all(color: c.cyan.withValues(alpha: .55)),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 13, color: c.cyan),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            if (trailingChevron) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 19, color: c.cyan),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact trailing action button for normal Home list cards (target): a small
/// outlined "View Match" (or filled "Watch Live" when a stream exists), sized to
/// sit at the right of the bottom metadata row instead of a full-width CTA.
class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.trailingChevron = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final bool trailingChevron;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: filled
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xff35e2ff), Color(0xff0a86ff)],
                )
              : null,
          color: filled
              ? null
              : (c.isDark ? c.card.withValues(alpha: .35) : c.card),
          borderRadius: BorderRadius.circular(11),
          border: filled
              ? null
              : Border.all(color: c.cyan.withValues(alpha: .6), width: 1.2),
          boxShadow: filled && c.isDark
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .4),
                    blurRadius: 12,
                    spreadRadius: -3,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: filled ? Colors.white : c.cyan),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: filled ? Colors.white : c.text,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
            if (trailingChevron) ...[
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded,
                  size: 17, color: filled ? Colors.white : c.cyan),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bottom row for normal Home list cards (target): venue + date/time stacked at
/// the left (two controlled rows, so nothing is hidden on small screens) and a
/// compact action button parked at the right.
class _CardBottomRow extends StatelessWidget {
  const _CardBottomRow({
    required this.venue,
    required this.dateTime,
    required this.trailing,
  });

  final String venue;
  final String dateTime;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Venue gets up to 2 lines on narrow devices (Part 17) so a long venue
    // like "The Kent County Cricket…" is not truncated behind the CTA; the
    // date/time stays on its own single-line row beneath it.
    Widget metaLine(IconData icon, String text, {int maxLines = 1}) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, color: c.cyan, size: 13),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.onImageText,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                  height: 1.2,
                ),
              ),
            ),
          ],
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 30,
          child: venue.isEmpty
              ? const SizedBox.shrink()
              : metaLine(Icons.location_on_outlined, venue, maxLines: 2),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 34,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: dateTime.isEmpty
                    ? const SizedBox.shrink()
                    : metaLine(Icons.calendar_month_rounded, dateTime),
              ),
              const SizedBox(width: 10),
              trailing,
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status badge
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.live,
    this.dense = false,
  });

  final String label;
  final Color color;
  final bool live;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .85)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: dense ? 9.5 : 10,
              letterSpacing: .4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state + skeleton
// ---------------------------------------------------------------------------

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState({required this.topTab, required this.onSwitchUpcoming});

  final int topTab;
  final VoidCallback onSwitchUpcoming;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final message = switch (topTab) {
      0 => 'No live matches right now',
      1 => 'No upcoming matches',
      _ => 'No finished matches',
    };
    final support = switch (topTab) {
      0 => 'Check Upcoming matches for scheduled games.',
      1 => 'New fixtures will appear here once scheduled.',
      _ => 'Completed matches will appear here.',
    };
    return Container(
      key: const ValueKey('home-empty-state'),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: c.isDark ? c.card.withValues(alpha: .4) : c.card,
        border: Border.all(color: c.cyan.withValues(alpha: .28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.cyan.withValues(alpha: .12),
              border: Border.all(color: c.cyan.withValues(alpha: .35)),
            ),
            alignment: Alignment.center,
            child: Icon(
              topTab == 0
                  ? Icons.podcasts_rounded
                  : Icons.sports_cricket_rounded,
              color: c.cyan,
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.text, fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            support,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
          if (topTab == 0) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onSwitchUpcoming,
              behavior: HitTestBehavior.opaque,
              child: Container(
                key: const ValueKey('home-empty-live-cta'),
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xff35e2ff), Color(0xff0a86ff)],
                  ),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: c.isDark
                      ? [
                          BoxShadow(
                            color: c.cyan.withValues(alpha: .30),
                            blurRadius: 12,
                            spreadRadius: -4,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                // Scale-down inside the pill rather than clipping: keeps the
                // full label readable on very narrow phones / wide font
                // metrics without ever overflowing.
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_month_rounded,
                          color: Colors.white, size: 17),
                      SizedBox(width: 7),
                      Text(
                        'View Upcoming Matches',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// High-fidelity match-card skeleton that reserves the EXACT final card
/// geometry (status pill + title, two team emblems + codes + score slots, VS,
/// venue/date footer, View Match placeholder). Wraps [_HomeCardShell] and
/// uses [homeLiveCardResolvedHeight] so its outer rectangle matches the loaded
/// live card within ±2 px — the tree never jumps when data arrives. Emblem /
/// VS metrics come from [homeCardEmblemSize] / [homeCardVsWidth] with the same
/// `contentWidth` inputs the loaded card uses. No `Spacer()` — every internal
/// region is a `Flexible` share of the reserved height, so if the resolved
/// height ever shrinks the row simply compresses rather than overflowing.
class _CardSkeleton extends StatefulWidget {
  const _CardSkeleton({
    required this.index,
    required this.outerCardWidth,
  });

  /// Index within the loading list (0 = topmost). Feeds the stable key
  /// factory so multiple sibling skeletons stay unique.
  final int index;

  /// Outer rendered card width from the parent LayoutBuilder — passed down
  /// explicitly, never rediscovered internally.
  final double outerCardWidth;

  @override
  State<_CardSkeleton> createState() => _CardSkeletonState();
}

class _CardSkeletonState extends State<_CardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final reduce = MediaQuery.accessibleNavigationOf(context);
    final t = reduce ? 0.5 : _shimmer.value;
    const blockBase = Color(0xff0c2640);
    final block = blockBase.withValues(alpha: c.isDark ? .55 : .30);
    final shimmerColor = c.cyan
        .withValues(alpha: (c.isDark ? 0.10 : 0.12) + 0.06 * (0.5 + 0.5 * t));

    Widget pill({double w = 46, double h = 16}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: block,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: shimmerColor, width: 1),
          ),
        );
    Widget line({double w = double.infinity, double h = 11}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: block,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    Widget circle(double d) => Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: block,
            border: Border.all(color: shimmerColor, width: 2),
          ),
        );

    final outerCardWidth = widget.outerCardWidth;
    final contentWidth = (outerCardWidth - kHomeCardPadding.horizontal)
        .clamp(0.0, double.infinity);
    final emblem = homeCardEmblemSize(contentWidth: contentWidth);
    final vsWidth = homeCardVsWidth(contentWidth: contentWidth);
    final vsHeight = vsWidth * .69;
    final resolvedHeight = homeLiveCardResolvedHeight(
      outerCardWidth: outerCardWidth,
      textScaler: MediaQuery.textScalerOf(context),
    );

    // Absorb tap so a skeleton is not treated as a button (no accidental
    // navigation while loading). Semantic label instead.
    return Semantics(
      container: true,
      label: 'Loading match card',
      excludeSemantics: true,
      child: KeyedSubtree(
        key: homeSkeletonCardKey(widget.index),
        child: SizedBox(
          height: resolvedHeight,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kHomeCardRadius),
              color: c.isDark ? c.card.withValues(alpha: .5) : c.card,
              border: Border.all(color: c.cyan.withValues(alpha: .22)),
            ),
            child: Padding(
              padding: kHomeCardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header: status pill + title lines + star.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      pill(w: 50, h: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            line(h: 11, w: double.infinity),
                            const SizedBox(height: 4),
                            line(h: 11, w: 110),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      circle(22),
                    ],
                  ),
                  const SizedBox(height: kHomeCardHeaderToBody),
                  // Team row: two emblem columns + centred VS. Uses the SAME
                  // width-derived emblem/VS sizes the loaded card uses.
                  Flexible(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              circle(emblem),
                              const SizedBox(height: 6),
                              line(h: 13, w: 44),
                              const SizedBox(height: 6),
                              line(h: 15, w: 64),
                              const SizedBox(height: 4),
                              line(h: 10, w: 40),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: pill(w: vsWidth, h: vsHeight),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              circle(emblem),
                              const SizedBox(height: 6),
                              line(h: 13, w: 44),
                              const SizedBox(height: 6),
                              line(h: 15, w: 64),
                              const SizedBox(height: 4),
                              line(h: 10, w: 40),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: kHomeCardBodyToDivider),
                  // Hairline divider placeholder — matches the loaded divider
                  // position so the footer band lines up when data arrives.
                  Container(
                    height: 1,
                    color: c.cyan.withValues(alpha: .12),
                  ),
                  const SizedBox(height: kHomeCardDividerToFooter),
                  // Footer: venue line + date/time + View Match placeholder.
                  // Sized to match `_CardBottomRow` (venue 30 + gap 5 + row 34
                  // = 69) so the reserved footer region is identical.
                  SizedBox(
                    height: 30,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: line(h: 11, w: 130),
                    ),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    height: 34,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: line(h: 11, w: 90),
                          ),
                        ),
                        const SizedBox(width: 10),
                        pill(w: 96, h: 30),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category filter row (All / International / League / Domestic + filter icon)
// ---------------------------------------------------------------------------
