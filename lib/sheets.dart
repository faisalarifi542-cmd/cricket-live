import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'components.dart';

Future<void> showFilterSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _SheetWrapper(child: _FilterSheet()),
  );
}

Future<void> showReminderSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _SheetWrapper(child: _ReminderSheet()),
  );
}

Future<void> showCalendarSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _SheetWrapper(child: _CalendarSheet()),
  );
}

class _SheetWrapper extends StatelessWidget {
  const _SheetWrapper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      decoration: BoxDecoration(
        color: c.bg2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: c.border),
      ),
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 14,
        bottom: 18 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 44, height: 4, decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet();

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  final Set<String> types = {'T20I'};
  final Set<String> statuses = {'Live'};

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Filter Matches', style: TextStyle(color: c.text, fontSize: 22, fontWeight: FontWeight.w900)),
              const Spacer(),
              TextButton(onPressed: () => setState(() {
                types.clear();
                statuses.clear();
              }), child: const Text('Reset')),
            ],
          ),
          const SizedBox(height: 18),
          _section('Match Type', [for (final t in ['T20I', 'ODI', 'Test', 'League']) PillChip(t, selected: types.contains(t), onTap: () => setState(() => types.contains(t) ? types.remove(t) : types.add(t)))]),
          const SizedBox(height: 16),
          _section('Status', [for (final s in ['Live', 'Upcoming', 'Finished']) PillChip(s, selected: statuses.contains(s), onTap: () => setState(() => statuses.contains(s) ? statuses.remove(s) : statuses.add(s)))]),
          const SizedBox(height: 16),
          _section('Date Range', [
            const PillChip('Today', selected: true),
            const PillChip('This Week'),
            const PillChip('Custom'),
          ]),
          const SizedBox(height: 16),
          _section('Series / Tournament', [
            const PillChip('All Series'),
            const PillChip('ICC Events'),
            const PillChip('Domestic'),
          ]),
          const SizedBox(height: 16),
          _section('Team', [
            const PillChip('India'),
            const PillChip('Australia'),
            const PillChip('England'),
            const PillChip('Pakistan'),
            const PillChip('New Zealand'),
          ]),
          const SizedBox(height: 16),
          _section('Venue', [
            const PillChip('All Venues'),
            const PillChip('Asia'),
            const PillChip('Australia'),
            const PillChip('UK'),
          ]),
          const SizedBox(height: 22),
          GradientButton(label: 'Apply Filters', icon: Icons.tune_rounded, onTap: () => Navigator.pop(context)),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> chips) {
    final c = context.cric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: TextStyle(color: c.muted, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: chips),
      ],
    );
  }
}

class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet();

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  int selected = 1;
  bool saved = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final options = ['15 minutes before', '30 minutes before', '1 hour before', '2 hours before', '1 day before'];
    if (saved) {
      return Column(
        children: [
          Icon(Icons.check_circle_rounded, color: c.success, size: 64),
          const SizedBox(height: 14),
          Text('Reminder set!', style: TextStyle(color: c.text, fontWeight: FontWeight.w900, fontSize: 22)),
          const SizedBox(height: 6),
          Text(options[selected], style: TextStyle(color: c.muted, fontSize: 16)),
          const SizedBox(height: 18),
          SizedBox(width: 220, child: GradientButton(label: 'Done', onTap: () => Navigator.pop(context))),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Set Reminder', style: TextStyle(color: c.text, fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text('Get notified before the match starts.', style: TextStyle(color: c.muted)),
        const SizedBox(height: 16),
        for (var i = 0; i < options.length; i++)
          GestureDetector(
            onTap: () => setState(() => selected = i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: selected == i ? c.cyan : c.border, width: 2),
                      color: selected == i ? c.cyan.withValues(alpha: .22) : Colors.transparent,
                    ),
                    alignment: Alignment.center,
                    child: selected == i ? Icon(Icons.check_rounded, color: c.cyan, size: 16) : null,
                  ),
                  const SizedBox(width: 14),
                  Text(options[i], style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 16)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        GradientButton(
          label: 'Confirm Reminder',
          icon: Icons.notifications_active_outlined,
          onTap: () => setState(() => saved = true),
        ),
      ],
    );
  }
}

class _CalendarSheet extends StatelessWidget {
  const _CalendarSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final options = [
      ('Add full series', Icons.event_available_rounded),
      ('Add only India matches', Icons.shield_outlined),
      ('Add only upcoming matches', Icons.schedule_rounded),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Add to Calendar', style: TextStyle(color: c.text, fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text('Pick which matches you want synced to your calendar.', style: TextStyle(color: c.muted)),
        const SizedBox(height: 16),
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PremiumCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(radius: 22, backgroundColor: c.card2, child: Icon(option.$2, color: c.cyan)),
                  const SizedBox(width: 14),
                  Expanded(child: Text(option.$1, style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 16))),
                  Icon(Icons.chevron_right_rounded, color: c.muted),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        GradientButton(label: 'Close', icon: Icons.close_rounded, outlined: true, onTap: () => Navigator.pop(context)),
      ],
    );
  }
}
