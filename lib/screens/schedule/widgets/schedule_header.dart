part of '../schedule_screen.dart';

class _ScheduleHeader extends StatelessWidget {
  const _ScheduleHeader({required this.onSearch, required this.onFilter});

  final VoidCallback onSearch;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        Expanded(
          child: Text(
            'SCHEDULE',
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w900,
              fontSize: context.sp(33),
              letterSpacing: .5,
              height: .95,
            ),
          ),
        ),
        _GlassIconButton(
          icon: Icons.search_rounded,
          onTap: onSearch,
          tooltip: 'Search matches',
        ),
        const SizedBox(width: 10),
        _GlassIconButton(
          icon: Icons.tune_rounded,
          onTap: onFilter,
          tooltip: 'Filter matches',
        ),
      ],
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// Accessible name for this icon-only control (no visible text label).
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
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
                        color: c.cyan.withValues(alpha: .07),
                        blurRadius: 12,
                        spreadRadius: -4,
                      ),
                    ]
                  : c.cardShadow,
            ),
            child: Icon(icon, color: c.text, size: 21),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date selector
// ---------------------------------------------------------------------------

class _DateSelector extends StatelessWidget {
  const _DateSelector({
    required this.days,
    required this.selected,
    required this.loading,
    required this.onSelect,
  });

  final List<ScheduleDay> days;
  final int selected;
  final bool loading;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (loading || days.isEmpty) {
      // Placeholder date cards (today onwards) while loading.
      final placeholders = List.generate(7, (i) {
        final d = DateTime.now().add(Duration(days: i));
        return _DateParts.fromDate(d);
      });
      return SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 20),
          itemCount: placeholders.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => _DateCard(
            parts: placeholders[i],
            selected: i == 0,
            onTap: null,
          ),
        ),
      );
    }
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 20),
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _DateCard(
          parts: _DateParts.fromDay(days[i]),
          selected: i == selected,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}

class _DateParts {
  const _DateParts({
    required this.weekday,
    required this.day,
    required this.month,
  });

  final String weekday;
  final String day;
  final String month;

  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC'
  ];
  static const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  factory _DateParts.fromDate(DateTime d) => _DateParts(
        weekday: _weekdays[d.weekday - 1],
        day: d.day.toString(),
        month: _months[d.month - 1],
      );

  factory _DateParts.fromDay(ScheduleDay day) {
    final date = day.date;
    if (date != null) return _DateParts.fromDate(date);
    return _DateParts(
      weekday: day.dayShort.toUpperCase(),
      day: day.dayNumber,
      month: '',
    );
  }
}

class _DateCard extends StatelessWidget {
  const _DateCard({
    required this.parts,
    required this.selected,
    required this.onTap,
  });

  final _DateParts parts;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          gradient: selected ? c.primaryGradient : null,
          color: selected ? null : (c.isDark ? c.card.withValues(alpha: .5) : c.card),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? c.cyan.withValues(alpha: .8) : c.border,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected && c.isDark
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .22),
                    blurRadius: 16,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              parts.weekday,
              maxLines: 1,
              style: TextStyle(
                color: selected ? Colors.white.withValues(alpha: .9) : c.muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              parts.day,
              maxLines: 1,
              style: TextStyle(
                color: selected ? Colors.white : c.text,
                fontWeight: FontWeight.w900,
                fontSize: 22,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              parts.month,
              maxLines: 1,
              style: TextStyle(
                color: selected
                    ? Colors.white.withValues(alpha: .85)
                    : c.muted.withValues(alpha: .8),
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 5),
            // Selected accent underline.
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: selected ? 18 : 0,
              height: 2.5,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(99),
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

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.filters,
    required this.selected,
    required this.onSelect,
  });

  final List<_CategoryFilter> filters;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // Trailing padding so the last category chip (e.g. "Women") scrolls
        // fully into view instead of being cut flush at the right edge.
        padding: const EdgeInsets.only(right: 20),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _CategoryChip(
          filter: filters[i],
          selected: i == selected,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  final _CategoryFilter filter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // GestureDetector (no InkWell) so there is never a splash/highlight that
    // could paint a rectangular patch behind the rounded pill.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: selected ? c.primaryGradient : null,
          color: selected ? null : (c.isDark ? c.card.withValues(alpha: .5) : c.card),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? c.cyan.withValues(alpha: .8) : c.border,
          ),
          boxShadow: selected && c.isDark
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .18),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            filter.asset != null
                ? Image.asset(
                    filter.asset!,
                    width: 16,
                    height: 16,
                    color: selected ? Colors.white : c.cyan,
                    excludeFromSemantics: true,
                    errorBuilder: (_, __, ___) => Icon(
                      filter.icon,
                      size: 15,
                      color: selected ? Colors.white : c.cyan,
                    ),
                  )
                : Icon(
                    filter.icon,
                    size: 15,
                    color: selected ? Colors.white : c.cyan,
                  ),
            const SizedBox(width: 7),
            Text(
              filter.label,
              style: TextStyle(
                color: selected ? Colors.white : c.muted,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary / sort row
// ---------------------------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.sortLabel,
    required this.onSort,
  });

  final String label;
  final String sortLabel;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.cyan.withValues(alpha: .12),
            border: Border.all(color: c.cyan.withValues(alpha: .3)),
          ),
          child: Image.asset(
            _Asset.iconCalendar,
            width: 15,
            height: 15,
            color: c.cyan,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) =>
                Icon(Icons.calendar_today_rounded, color: c.cyan, size: 15),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: onSort,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: c.isDark ? c.card.withValues(alpha: .55) : c.card,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sortLabel,
                  style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.sort_rounded, color: c.cyan, size: 15),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Premium match card
// ---------------------------------------------------------------------------

