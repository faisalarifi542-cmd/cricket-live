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
            label: 'View Match',
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: c.isDark ? c.card.withValues(alpha: .4) : c.card,
        border: Border.all(color: c.cyan.withValues(alpha: .28)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.cyan.withValues(alpha: .12),
              border: Border.all(color: c.cyan.withValues(alpha: .35)),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.sports_cricket_rounded, color: c.cyan, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: TextStyle(
                      color: c.text, fontWeight: FontWeight.w800, fontSize: 14),
                ),
                if (topTab == 0) ...[
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: onSwitchUpcoming,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      'View upcoming fixtures',
                      style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      height: 210,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: c.isDark ? c.card.withValues(alpha: .5) : c.card,
        border: Border.all(color: c.cyan.withValues(alpha: .22)),
      ),
      alignment: Alignment.center,
      child: CircularProgressIndicator(color: c.cyan),
    );
  }
}

// ---------------------------------------------------------------------------
// Category filter row (All / International / League / Domestic + filter icon)
// ---------------------------------------------------------------------------

