part of '../schedule_screen.dart';

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: c.isDark
                ? [
                    const Color(0xff0a1929).withValues(alpha: .99),
                    const Color(0xff0f2744).withValues(alpha: .99),
                  ]
                : [
                    c.card,
                    c.card2,
                  ],
          ),
          border: Border.all(color: c.cyan.withValues(alpha: .32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, color: c.muted, size: 22),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.initial, required this.onChanged});

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: _SheetShell(
        title: 'Search Schedule',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
              cursorColor: c.cyan,
              onChanged: widget.onChanged,
              decoration: InputDecoration(
                hintText: 'Search team, series or venue',
                hintStyle: TextStyle(color: c.muted),
                prefixIcon: Icon(Icons.search_rounded, color: c.cyan),
                filled: true,
                fillColor: c.card2.withValues(alpha: .5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: c.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: c.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: c.cyan),
                ),
              ),
            ),
            const SizedBox(height: 14),
            GradientButton(
              label: 'Done',
              icon: Icons.check_rounded,
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSheet extends StatelessWidget {
  const _FilterSheet({
    required this.filters,
    required this.selected,
    required this.onSelect,
  });

  final List<_CategoryFilter> filters;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Filter by Category',
      child: Column(
        children: [
          for (var i = 0; i < filters.length; i++)
            _SheetOption(
              icon: filters[i].icon,
              label: filters[i].label,
              selected: i == selected,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _SortSheet extends StatelessWidget {
  const _SortSheet({required this.selected, required this.onSelect});

  final _Sort selected;
  final ValueChanged<_Sort> onSelect;

  @override
  Widget build(BuildContext context) {
    const options = [
      (_Sort.time, 'Time', Icons.access_time_rounded),
      (_Sort.series, 'Series', Icons.emoji_events_rounded),
      (_Sort.type, 'Match Type', Icons.sports_cricket_rounded),
    ];
    return _SheetShell(
      title: 'Sort Matches',
      child: Column(
        children: [
          for (final o in options)
            _SheetOption(
              icon: o.$3,
              label: o.$2,
              selected: o.$1 == selected,
              onTap: () => onSelect(o.$1),
            ),
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? c.cyan.withValues(alpha: .1) : Colors.transparent,
          border: Border.all(
            color: selected ? c.cyan.withValues(alpha: .7) : c.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? c.cyan : c.muted, size: 19),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: c.cyan, size: 20),
          ],
        ),
      ),
    );
  }
}
