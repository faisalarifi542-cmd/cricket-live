import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../components.dart';
import '../../core/api/api_config.dart';
import '../../models/api_response.dart';
import '../../models/cricket_match.dart';
import '../../repositories/cricket_repository.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, required this.onOpenSeries});

  final VoidCallback onOpenSeries;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  int selectedDay = 3; // Wed 26 is selected by default
  int filterIndex = 0;
  final CricketRepository _repository = CricketRepository();
  late Future<ApiEnvelope<List<CricketMatch>>> _schedule;

  final days = [
    ('Mon', '24'),
    ('Tue', '25'),
    ('Wed', '26'),
    ('Thu', '27'),
    ('Fri', '28'),
    ('Sat', '29'),
    ('Sun', '30'),
  ];

  final filters = ['All', 'International', 'League', 'Domestic', 'Women'];

  @override
  void initState() {
    super.initState();
    _schedule = _repository.scheduleMatches(type: _filterType);
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
      _schedule = _repository.scheduleMatches(type: _filterType);
    });
  }

  Future<void> _refresh() async {
    setState(() => _schedule = _repository.scheduleMatches(type: _filterType, forceRefresh: true));
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
          child: ListView(
          padding: EdgeInsets.fromLTRB(
            context.horizontalPadding,
            18,
            context.horizontalPadding,
            context.mainBottomPadding,
          ),
          children: [
            // Header
            AppHeader(title: 'SCHEDULE'),
            const SizedBox(height: 24),

            // Date Selector
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: days.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _DateChip(
                  day: days[i].$1,
                  date: days[i].$2,
                  selected: selectedDay == i,
                  onTap: () => setState(() => selectedDay = i),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Filter Chips
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

            _ApiScheduleList(
              future: _schedule,
              allowDemoFallback: ApiConfig.allowDemoFallback,
              onRetry: () => setState(() => _schedule = _repository.scheduleMatches(type: _filterType, forceRefresh: true)),
              onOpenSeries: widget.onOpenSeries,
            ),
            const SizedBox(height: 28),

            // Today Section
            if (filterIndex == -100) ...[
            _SectionTitle('Today — Wed, 26 Nov'),
            const SizedBox(height: 14),
            _ScheduleFixtureCard(
              series: 'ICC MEN\'S ODI SERIES',
              matchNumber: '3rd ODI',
              team1: _TeamData('IND', 'India', '🇮🇳'),
              team2: _TeamData('AUS', 'Australia', '🇦🇺'),
              time: '3:30 PM IST',
              venue: 'Narendra Modi Stadium, Ahmedabad',
              status: 'UPCOMING',
              onTap: widget.onOpenSeries,
            ),
            const SizedBox(height: 12),
            _ScheduleFixtureCard(
              series: 'ENGLAND TOUR OF WEST INDIES',
              matchNumber: 'T20I • 2nd Match',
              team1: _TeamData('ENG', 'England', '🏴'),
              team2: _TeamData('WI', 'West Indies', '🇼🇸'),
              time: '7:00 PM GMT',
              venue: 'Kensington Oval, Bridgetown',
              status: 'UPCOMING',
              onTap: widget.onOpenSeries,
            ),
            const SizedBox(height: 28),

            // Tomorrow Section
            _SectionTitle('Tomorrow — Thu, 27 Nov'),
            const SizedBox(height: 14),
            _ScheduleFixtureCard(
              series: 'PAKISTAN TOUR OF BANGLADESH',
              matchNumber: 'T20I • 1st Match',
              team1: _TeamData('PAK', 'Pakistan', '🇵🇰'),
              team2: _TeamData('BAN', 'Bangladesh', '🇧🇩'),
              time: '6:00 PM BST',
              venue: 'Sher-e-Bangla Stadium, Dhaka',
              status: 'UPCOMING',
              onTap: widget.onOpenSeries,
            ),
            const SizedBox(height: 12),
            _ScheduleFixtureCard(
              series: 'SOUTH AFRICA T20 LEAGUE',
              matchNumber: 'Match 12',
              team1: _TeamData('SUN', 'Sunrisers', '☀️'),
              team2: _TeamData('DSG', 'Durban', '⚡'),
              time: '8:30 PM SAST',
              venue: 'Kingsmead, Durban',
              status: 'UPCOMING',
              onTap: widget.onOpenSeries,
            ),
            const SizedBox(height: 28),

            // Upcoming Section
            _SectionTitle('Upcoming'),
            const SizedBox(height: 14),
            _ScheduleFixtureCard(
              series: 'NEW ZEALAND VS SRI LANKA',
              matchNumber: 'Test • 1st Test',
              team1: _TeamData('NZ', 'New Zealand', '🇳🇿'),
              team2: _TeamData('SL', 'Sri Lanka', '🇱🇰'),
              time: 'Fri, 28 Nov • 10:00 AM NZDT',
              venue: 'Basin Reserve, Wellington',
              status: 'UPCOMING',
              onTap: widget.onOpenSeries,
            ),
            const SizedBox(height: 12),
            _ScheduleFixtureCard(
              series: 'AUSTRALIA DOMESTIC ONE-DAY',
              matchNumber: 'Match 8',
              team1: _TeamData('VIC', 'Victoria', '🏏'),
              team2: _TeamData('WA', 'Western Australia', '🦘'),
              time: 'Sat, 29 Nov • 2:00 PM AEDT',
              venue: 'MCG, Melbourne',
              status: 'UPCOMING',
              onTap: widget.onOpenSeries,
            ),
            const SizedBox(height: 28),

            ],

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: GradientButton(
                    label: 'Sync Schedule',
                    icon: Icons.sync_rounded,
                    onTap: () {},
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
        ),
      ),
    ),
    );
  }
}

class _ApiScheduleList extends StatelessWidget {
  const _ApiScheduleList({
    required this.future,
    required this.allowDemoFallback,
    required this.onRetry,
    required this.onOpenSeries,
  });

  final Future<ApiEnvelope<List<CricketMatch>>> future;
  final bool allowDemoFallback;
  final VoidCallback onRetry;
  final VoidCallback onOpenSeries;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ApiEnvelope<List<CricketMatch>>>(
      future: future,
      builder: (context, snapshot) {
        final matches = snapshot.data?.data ?? const <CricketMatch>[];
        if (snapshot.connectionState == ConnectionState.waiting && matches.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError && !allowDemoFallback) {
          return _ScheduleStateCard(onRetry: onRetry);
        }
        if (matches.isEmpty) {
          return _ScheduleStateCard(
            title: 'No fixtures found',
            message: 'Try another schedule filter or refresh shortly.',
            onRetry: onRetry,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionTitle('Upcoming'),
            const SizedBox(height: 14),
            for (final match in matches)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ScheduleFixtureCard(
                  series: match.series,
                  matchNumber: match.title,
                  team1: _TeamData(_code(match.teamA), match.teamA, ''),
                  team2: _TeamData(_code(match.teamB), match.teamB, ''),
                  time: match.startTime.isEmpty ? match.status : match.startTime,
                  venue: match.venue,
                  status: match.status,
                  onTap: onOpenSeries,
                ),
              ),
          ],
        );
      },
    );
  }

  String _code(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return 'TBD';
    final parts = cleaned.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.substring(0, parts.first.length.clamp(1, 3).toInt()).toUpperCase();
    return parts.take(2).map((part) => part[0]).join().toUpperCase();
  }
}

class _ScheduleStateCard extends StatelessWidget {
  const _ScheduleStateCard({
    this.title = 'Unable to load schedule',
    this.message = 'Please check your connection and try again.',
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Icon(Icons.calendar_month_rounded, color: c.cyan, size: 38),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(color: c.text, fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: c.muted, height: 1.4)),
          const SizedBox(height: 16),
          GradientButton(label: 'Retry', icon: Icons.refresh_rounded, onTap: onRetry),
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 68,
        padding: const EdgeInsets.symmetric(vertical: 10),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              day,
              style: TextStyle(
                color: selected ? Colors.white : c.muted,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              date,
              style: TextStyle(
                color: selected ? Colors.white : c.text,
                fontWeight: FontWeight.w900,
                fontSize: 20,
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
    required this.series,
    required this.matchNumber,
    required this.team1,
    required this.team2,
    required this.time,
    required this.venue,
    required this.status,
    required this.onTap,
  });

  final String series;
  final String matchNumber;
  final _TeamData team1;
  final _TeamData team2;
  final String time;
  final String venue;
  final String status;
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
          // Series and Status
          Row(
            children: [
              Expanded(
                child: Text(
                  series,
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(label: status, color: c.muted, filled: true),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            matchNumber,
            style: TextStyle(
              color: c.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),

          // Teams
          Row(
            children: [
              // Team 1
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.card2,
                        border: Border.all(color: c.border),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        team1.emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            team1.code,
                            style: TextStyle(
                              color: c.text,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            team1.name,
                            style: TextStyle(
                              color: c.muted,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // VS Circle
              Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: c.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: c.cyan.withValues(alpha: .3),
                      blurRadius: 12,
                    )
                  ],
                ),
                alignment: Alignment.center,
                child: const Text(
                  'VS',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),

              // Team 2
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            team2.code,
                            style: TextStyle(
                              color: c.text,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            team2.name,
                            style: TextStyle(
                              color: c.muted,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.card2,
                        border: Border.all(color: c.border),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        team2.emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Time and Venue
          Row(
            children: [
              Icon(Icons.access_time_rounded, color: c.cyan, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  time,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              InkWell(
                onTap: () {},
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.cyan.withValues(alpha: .15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.notifications_none_rounded,
                      color: c.cyan, size: 20),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: c.muted, size: 24),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.location_on_outlined, color: c.muted, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  venue,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TeamData {
  final String code;
  final String name;
  final String emoji;

  _TeamData(this.code, this.name, this.emoji);
}
