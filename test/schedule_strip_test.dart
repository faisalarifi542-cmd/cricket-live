import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/screens/schedule/schedule_strip.dart';

CricketMatch _match({
  required String id,
  required String status,
  DateTime? start,
  String series = 'Series',
}) {
  return CricketMatch.fromJson(<String, dynamic>{
    'id': id,
    'status': status,
    'series_name': series,
    'team1': <String, dynamic>{'name': 'A', 'shortName': 'A'},
    'team2': <String, dynamic>{'name': 'B', 'shortName': 'B'},
    if (start != null) 'start_time': start.toUtc().toIso8601String(),
  });
}

void main() {
  // Pretend "now" is Sun Jun 28 2026, 09:00 local.
  final now = DateTime(2026, 6, 28, 9);
  final today = DateTime(2026, 6, 28);

  group('Schedule strip opens on today', () {
    test('first chip is today and the strip starts at today', () {
      final days = buildScheduleStrip(matches: const [], now: now);
      expect(days.length, 14);
      expect(days.first.date, today);
      expect(days.first.dayDescriptive, 'Jun 28');
      // No past dates appear.
      expect(days.every((d) => !d.date!.isBefore(today)), isTrue);
    });

    test('upcoming match buckets under its local start date', () {
      final m = _match(
        id: 'u1',
        status: 'upcoming',
        start: DateTime(2026, 6, 29, 12, 0), // local noon Jun 29
      );
      final days = buildScheduleStrip(matches: [m], now: now);
      final jun29 = days.firstWhere((d) => d.date == DateTime(2026, 6, 29));
      expect(jun29.matches.map((e) => e.id), contains('u1'));
      // Today has no matches in this case.
      expect(days.first.matches, isEmpty);
    });
  });

  group('Live multi-day Test appears under today (Test 2)', () {
    test('a live match that started Jun 25 shows under Jun 28, not Jun 25', () {
      final live = _match(
        id: 'nzeng',
        status: 'live',
        start: DateTime.utc(2026, 6, 25, 10, 0), // started 3 days ago
        series: 'New Zealand tour of England, 2026',
      );
      final days = buildScheduleStrip(matches: [live], now: now);
      // Under today.
      expect(days.first.date, today);
      expect(days.first.matches.map((e) => e.id), contains('nzeng'));
      // NOT forced to a Jun 25 chip (Jun 25 isn't even in the forward strip).
      expect(days.any((d) => d.date == DateTime(2026, 6, 25)), isFalse);
    });

    test('IRE vs IND live today and MLC upcoming both land on Jun 28', () {
      final ire = _match(
        id: 'ireind',
        status: 'live',
        start: DateTime.utc(2026, 6, 28, 12, 30),
        series: 'India tour of Ireland, 2026',
      );
      final mlc = _match(
        id: 'lakrsor',
        status: 'upcoming',
        start: DateTime(2026, 6, 28, 23, 30), // local late-night Jun 28
        series: 'Major League Cricket 2026',
      );
      final ids = buildScheduleStrip(matches: [ire, mlc], now: now)
          .first
          .matches
          .map((e) => e.id)
          .toList();
      expect(ids, containsAll(<String>['ireind', 'lakrsor']));
    });
  });
}
