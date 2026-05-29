import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../components.dart';
import '../../models/api_response.dart';
import '../../models/cricket_match.dart';
import '../../repositories/cricket_repository.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.onOpenSeries,
    this.onOpenMatch,
  });

  final VoidCallback onOpenSeries;

  /// Invoked with the resolved match id when the user taps a fixture card.
  final ValueChanged<String>? onOpenMatch;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  int selectedDay = 0;
  int filterIndex = 0;
  final CricketRepository _repository = CricketRepository();
  late Future<ApiEnvelope<List<ScheduleDay>>> _schedule;

  final filters = const ['All', 'International', 'League', 'Domestic', 'Women'];

  @override
  void initState() {
    super.initState();
    _schedule = _repository.scheduleByDay(type: _filterType);
  }

  String get _filterType => switch (filterIndex) {
        1 => 'international',
        2 => 'league',
        3 => 'domestic',
        4 => 'women',
        _ => 'all',
      };

  void _setFilter(int index) {
    setState(() {
      filterIndex = index;
      selectedDay = 0;
      _schedule = _repository.scheduleByDay(type: _filterType);
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _schedule =
          _repository.scheduleByDay(type: _filterType, forceRefresh: true);
    });
    await _schedule;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      decoration: BoxDecoration(gradient: c.bgGradient),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<ApiEnvelope<List<ScheduleDay>>>(
            future: _schedule,
            builder: (context, snapshot) {
              final days = snapshot.data?.data ?? const <ScheduleDay>[];
              final waiting =
                  snapshot.connectionState == ConnectionState.waiting &&
                      days.isEmpty;
              final safeSelected =
                  days.isEmpty ? 0 : selectedDay.clamp(0, days.length - 1);
              final selectedMatches =
                  days.isEmpty ? <CricketMatch>[] : days[safeSelected].matches;
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  context.horizontalPadding,
                  18,
                  context.horizontalPadding,
                  context.mainBottomPadding,
                ),
                children: [
                  const AppHeader(title: 'SCHEDULE'),
                  const SizedBox(height: 24),
                  // Date selector — uses real API days. The chips are inside
                  // a horizontally scrollable list and a flexible height so
                  // they never trigger RenderFlex overflow at 360px.
                  _DateChipRow(
                    days: days,
                    selected: safeSelected,
                    onSelect: (i) => setState(() => selectedDay = i),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 46,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: filters.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => PillChip(
                        filters[i],
                        selected: filterIndex == i,
                        onTap: () => _setFilter(i),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (waiting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (snapshot.hasError && days.isEmpty)
                    _ScheduleStateCard(
                      title: 'Unable to load schedule',
                      message:
                          'Please check your connection and try again.',
                      onRetry: _refresh,
                    )
                  else if (days.isEmpty)
                    _ScheduleStateCard(
                      title: 'No fixtures found',
                      message:
                          'Try another schedule filter or refresh shortly.',
                      onRetry: _refresh,
                    )
                  else ...[
                    _SectionTitle(
                        _selectedTitle(days, safeSelected)),
                    const SizedBox(height: 14),
                    if (selectedMatches.isEmpty)
                      _ScheduleStateCard(
                        title: 'No fixtures on this day',
                        message:
                            'Pick another date above or check back later.',
                        onRetry: _refresh,
                      )
                    else
                      for (final match in selectedMatches)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ScheduleFixtureCard(
                            match: match,
                            onTap: () {
                              if (match.id.isNotEmpty &&
                                  widget.onOpenMatch != null) {
                                widget.onOpenMatch!(match.id);
                              } else {
                                widget.onOpenSeries();
                              }
                            },
                          ),
                        ),
                  ],
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: GradientButton(
                          label: 'Sync Schedule',
                          icon: Icons.sync_rounded,
                          onTap: _refresh,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GradientButton(
                          label: 'Add to Calendar',
                          icon: Icons.calendar_month_rounded,
                          outlined: true,
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _selectedTitle(List<ScheduleDay> days, int index) {
    if (days.isEmpty) return 'Upcoming';
    final day = days[index];
    final descriptive = day.dayDescriptive;
    if (descriptive.isEmpty) return 'Upcoming';
    return '$descriptive — ${day.matches.length} match${day.matches.length == 1 ? '' : 'es'}';
  }
}

class _DateChipRow extends StatelessWidget {
  const _DateChipRow({
    required this.days,
    required this.selected,
    required this.onSelect,
  });

  final List<ScheduleDay> days;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final placeholders = days.isEmpty
        ? List.generate(7, (i) {
            final date = DateTime.now().add(Duration(days: i));
            return _DateChipData(
              short: _dayShort(date),
              number: date.day.toString(),
            );
          })
        : [
            for (final d in days)
              _DateChipData(short: d.dayShort, number: d.dayNumber),
          ];
    // Bounded width but unbounded height — SingleChildScrollView keeps
    // overflow horizontal only, and the chip column sizes to its content.
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: placeholders.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _DateChip(
          day: placeholders[i].short,
          date: placeholders[i].number,
          selected: i == selected,
          onTap: days.isEmpty ? null : () => onSelect(i),
        ),
      ),
    );
  }

  static String _dayShort(DateTime date) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[date.weekday - 1];
  }
}

class _DateChipData {
  const _DateChipData({required this.short, required this.number});
  final String short;
  final String number;
}

class _ScheduleStateCard extends StatelessWidget {
  const _ScheduleStateCard({
    this.title = 'Unable to load schedule',
    this.message = 'Please check your connection and try again.',
    required this.onRetry,
  });

  final String title;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Icon(Icons.calendar_month_rounded, color: c.cyan, size: 38),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 18)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, height: 1.4)),
          const SizedBox(height: 16),
          GradientButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onTap: () => onRetry()),
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.day,
    required this.date,
    required this.selected,
    required this.onTap,
  });

  final String day;
  final String date;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 68,
        // Symmetric padding plus FittedBox-protected text lets the chip
        // grow to whatever height its content needs while keeping it
        // visually consistent on narrow screens.
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected ? c.primaryGradient : null,
          color: selected ? null : c.card.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? c.cyan.withValues(alpha: .7) : c.border,
            width: selected ? 1.5 : 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .3),
                    blurRadius: 16,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                day,
                style: TextStyle(
                  color: selected ? Colors.white : c.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                date,
                style: TextStyle(
                  color: selected ? Colors.white : c.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Text(
      title,
      style: TextStyle(
        color: c.text,
        fontWeight: FontWeight.w900,
        fontSize: 20,
      ),
    );
  }
}

class _ScheduleFixtureCard extends StatelessWidget {
  const _ScheduleFixtureCard({
    required this.match,
    required this.onTap,
  });

  final CricketMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  match.series.toUpperCase(),
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(
                  label: match.statusLabel, color: c.muted, filled: true),
            ],
          ),
          const SizedBox(height: 4),
          if (match.matchDesc.isNotEmpty)
            Text(
              match.matchDesc,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _CardTeamRow(
                  shortName: match.teamAShort,
                  fullName: match.teamA,
                ),
              ),
              const SizedBox(width: 8),
              Text('VS',
                  style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  )),
              const SizedBox(width: 8),
              Expanded(
                child: _CardTeamRow(
                  shortName: match.teamBShort,
                  fullName: match.teamB,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.access_time_rounded, color: c.muted, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  match.statusText.isNotEmpty
                      ? match.statusText
                      : _formattedStart(match),
                  style: TextStyle(
                      color: c.muted, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.location_on_outlined,
                  color: c.muted, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  match.venue,
                  style: TextStyle(
                      color: c.muted, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formattedStart(CricketMatch match) {
    final dt = match.startDateTime;
    if (dt == null) return match.startTime;
    final local = dt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${months[local.month - 1]} ${local.day} • $hh:$mm';
  }
}

class _CardTeamRow extends StatelessWidget {
  const _CardTeamRow({
    required this.shortName,
    required this.fullName,
    this.alignEnd = false,
  });

  final String shortName;
  final String fullName;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          shortName.isEmpty ? fullName : shortName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        if (fullName.isNotEmpty && fullName != shortName)
          Text(
            fullName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
      ],
    );
  }
}
