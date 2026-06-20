part of '../matches_screen.dart';

class _MatchesHeader extends StatelessWidget {
  const _MatchesHeader({required this.onBell});

  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // CRICPRO wordmark — rendered as a tight italic RichText so the two
        // halves read as one word (the PNG wordmark has an uneven gap).
        _wordmark(c),
        const Spacer(),
        _BellButton(onTap: onBell),
      ],
    );
  }

  Widget _wordmark(CricColors c) {
    return Transform.rotate(
      angle: -0.04,
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            letterSpacing: -0.5,
            height: 1,
          ),
          children: [
            TextSpan(text: 'CRIC', style: TextStyle(color: c.text)),
            TextSpan(text: 'PRO', style: TextStyle(color: c.cyan)),
          ],
        ),
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.isDark ? c.card.withValues(alpha: .55) : c.card,
          border: Border.all(color: c.cyan.withValues(alpha: .35)),
          boxShadow: c.isDark
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .10),
                    blurRadius: 14,
                    spreadRadius: -4,
                  ),
                ]
              : c.cardShadow,
        ),
        alignment: Alignment.center,
        child: Image.asset(
          _MAsset.iconBell,
          width: 21,
          height: 21,
          color: c.text,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.notifications_none_rounded, color: c.text, size: 22),
        ),
      ),
    );
  }
}

class _SectionTitleRow extends StatelessWidget {
  const _SectionTitleRow({required this.onSeeAll});

  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        Image.asset(
          _MAsset.iconBatBall,
          width: 24,
          height: 24,
          color: c.cyan,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.sports_cricket_rounded, color: c.cyan, size: 22),
        ),
        const SizedBox(width: 10),
        Text(
          'Matches',
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: context.sp(22),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onSeeAll,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See All',
                style: TextStyle(
                  color: c.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.chevron_right_rounded, color: c.cyan, size: 20),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status tabs
// ---------------------------------------------------------------------------

class _StatusTabs extends StatelessWidget {
  const _StatusTabs({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  static const _tabs = <(String, IconData)>[
    ('Live', Icons.podcasts_rounded),
    ('Upcoming', Icons.calendar_month_rounded),
    ('Finished', Icons.verified_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: c.isDark ? c.card.withValues(alpha: .42) : c.card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: c.cyan.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: _StatusTab(
                label: _tabs[i].$1,
                icon: _tabs[i].$2,
                selected: i == selected,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusTab extends StatelessWidget {
  const _StatusTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: 40,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    c.cyan.withValues(alpha: .55),
                    c.primary.withValues(alpha: .42),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(color: c.cyan.withValues(alpha: .95), width: 1.5)
              : null,
          boxShadow: selected && c.isDark
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .30),
                    blurRadius: 16,
                    spreadRadius: -2,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : c.muted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : c.muted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category chips
// ---------------------------------------------------------------------------

class _CategoryChipsRow extends StatelessWidget {
  const _CategoryChipsRow({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<_Category> categories;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (_, i) => _CategoryChip(
          category: categories[i],
          selected: i == selected,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final _Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    c.cyan.withValues(alpha: .55),
                    c.primary.withValues(alpha: .42),
                  ],
                )
              : null,
          color: selected ? null : (c.isDark ? c.card.withValues(alpha: .42) : c.card),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? c.cyan.withValues(alpha: .95)
                : c.cyan.withValues(alpha: .35),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected && c.isDark
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .28),
                    blurRadius: 14,
                    spreadRadius: -2,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              category.asset,
              width: 16,
              height: 16,
              color: selected ? Colors.white : c.cyan,
              errorBuilder: (_, __, ___) => Icon(
                category.icon,
                size: 15,
                color: selected ? Colors.white : c.cyan,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              category.label,
              style: TextStyle(
                color: selected ? Colors.white : c.text,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Match cards
// ---------------------------------------------------------------------------

/// Shared premium card shell: stadium background, dark overlay, cyan border,
/// edge glow and the standard content padding.
