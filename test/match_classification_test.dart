import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/utils/match_classification.dart';
import 'package:cricpro_flutter/utils/team_format.dart';

CricketMatch _m({
  required String id,
  required String status,
  List<Map<String, dynamic>>? t1Inn,
  List<Map<String, dynamic>>? t2Inn,
  String? start,
}) =>
    CricketMatch.fromJson(<String, dynamic>{
      'id': id,
      'status': status,
      if (start != null) 'start_time': start,
      'team1': <String, dynamic>{
        'name': 'India',
        'short': 'IND',
        if (t1Inn != null) 'innings': t1Inn,
      },
      'team2': <String, dynamic>{
        'name': 'South Africa',
        'short': 'RSA',
        if (t2Inn != null) 'innings': t2Inn,
      },
    });

void main() {
  // Fixed reference time so start-based staleness checks are deterministic.
  final now = DateTime.utc(2026, 6, 21, 18);

  group('classifyMatch — single canonical phase', () {
    test('A live match with a score is Live, never Upcoming', () {
      final m = _m(id: '1', status: 'live', t1Inn: [
        {'runs': 105, 'wickets': 3, 'overs': 12.1}
      ]);
      expect(classifyMatch(m, now: now), MatchPhase.live);
      expect(isUpcomingMatch(m, now: now), isFalse);
    });

    test('An upcoming match with a future start is Upcoming, never Live', () {
      final m = _m(
        id: '2',
        status: 'upcoming',
        start: DateTime.utc(2026, 6, 22, 2, 30).toIso8601String(),
      );
      expect(classifyMatch(m, now: now), MatchPhase.upcoming);
      expect(isLiveMatch(m, now: now), isFalse);
    });

    test('Status "upcoming" but a real score exists -> treated as Live', () {
      final m = _m(id: '3', status: 'upcoming', t1Inn: [
        {'runs': 110, 'wickets': 4, 'overs': 12.4}
      ]);
      expect(classifyMatch(m, now: now), MatchPhase.live);
      expect(isUpcomingMatch(m, now: now), isFalse);
    });

    test('A finished match with a result is not Live or Upcoming', () {
      final m = _m(
        id: '4',
        status: 'completed',
        t1Inn: [
          {'runs': 158, 'wickets': 7, 'overs': 20.0}
        ],
        t2Inn: [
          {'runs': 161, 'wickets': 4, 'overs': 19.1}
        ],
      );
      expect(classifyMatch(m, now: now), MatchPhase.finished);
      expect(isLiveMatch(m, now: now), isFalse);
      expect(isUpcomingMatch(m, now: now), isFalse);
    });

    test('Stale "upcoming" entry whose start is long past is not Upcoming', () {
      final m = _m(
        id: '5',
        status: 'upcoming',
        start: DateTime.utc(2026, 6, 21, 2, 0).toIso8601String(), // 16h before now
      );
      expect(isUpcomingMatch(m, now: now), isFalse);
    });
  });

  group('dedupeMatchesById — one match, one tab', () {
    test('Same id across Live + Upcoming keeps the Live copy only', () {
      final live = _m(id: 'X', status: 'live', t1Inn: [
        {'runs': 110, 'wickets': 4, 'overs': 12.4}
      ]);
      final upcoming = _m(
        id: 'X',
        status: 'upcoming',
        start: DateTime.utc(2026, 6, 22, 2, 30).toIso8601String(),
      );
      final out = dedupeMatchesById([upcoming, live], now: now);
      expect(out.length, 1);
      expect(classifyMatch(out.first, now: now), MatchPhase.live);
    });

    test('Different ids are all preserved', () {
      final a = _m(id: 'A', status: 'live', t1Inn: [
        {'runs': 1, 'overs': 0.1}
      ]);
      final b = _m(
        id: 'B',
        status: 'upcoming',
        start: DateTime.utc(2026, 6, 22).toIso8601String(),
      );
      expect(dedupeMatchesById([a, b], now: now).length, 2);
    });
  });

  group('Raw timestamp guard', () {
    test('A raw millis value reads as a timestamp and must be hidden', () {
      expect(looksLikeRawTimestamp('1782073800000'), isTrue);
    });
    test('Real cricket/time text is NOT a timestamp', () {
      expect(looksLikeRawTimestamp('12.4'), isFalse); // overs (has a dot)
      expect(looksLikeRawTimestamp('Jun 22 • 02:30 AM'), isFalse);
      expect(looksLikeRawTimestamp(''), isFalse);
    });
  });

  group('Home upcoming window (today + tomorrow, local)', () {
    // Local (no Z) start times so toLocal() is a no-op and the test is TZ-stable.
    final now = DateTime(2026, 6, 21, 12);
    CricketMatch up(String id, DateTime start) => _m(
          id: id,
          status: 'upcoming',
          start: start.toIso8601String(),
        );

    test('includes a match starting later today', () {
      expect(isTodayOrTomorrowLocal(up('t', DateTime(2026, 6, 21, 22, 30)),
          now: now), isTrue);
    });
    test('includes a match starting tomorrow', () {
      expect(isTodayOrTomorrowLocal(up('m', DateTime(2026, 6, 22, 7, 30)),
          now: now), isTrue);
    });
    test('excludes a match starting in two days', () {
      expect(isTodayOrTomorrowLocal(up('f', DateTime(2026, 6, 23, 9, 0)),
          now: now), isFalse);
    });
    test('excludes a match with no start time', () {
      expect(isTodayOrTomorrowLocal(_m(id: 'n', status: 'upcoming'), now: now),
          isFalse);
    });
  });

  group('Hero ordering — live before upcoming before finished', () {
    final now = DateTime.utc(2026, 6, 21, 18);
    test('orders by phase, preserving within-phase order', () {
      final finished = _m(id: 'f', status: 'completed', t1Inn: [
        {'runs': 158, 'wickets': 7, 'overs': 20.0}
      ]);
      final upcoming = _m(
        id: 'u',
        status: 'upcoming',
        start: DateTime.utc(2026, 6, 22, 2, 30).toIso8601String(),
      );
      final live = _m(id: 'l', status: 'live', t1Inn: [
        {'runs': 110, 'wickets': 4, 'overs': 12.4}
      ]);
      final ordered =
          orderByPhase([finished, upcoming, live], now: now).map((m) => m.id);
      expect(ordered.toList(), ['l', 'u', 'f']);
    });

    test('a scored "upcoming" hero is ordered as live (first)', () {
      final realUpcoming = _m(
        id: 'u',
        status: 'upcoming',
        start: DateTime.utc(2026, 6, 22).toIso8601String(),
      );
      final scoredUpcoming = _m(id: 's', status: 'upcoming', t1Inn: [
        {'runs': 50, 'wickets': 1, 'overs': 6.0}
      ]);
      final ordered =
          orderByPhase([realUpcoming, scoredUpcoming], now: now).map((m) => m.id);
      expect(ordered.first, 's'); // scored → live → leads
    });
  });

  group('shortenTeamName', () {
    test('Long franchise city prefix is abbreviated, not ellipsized', () {
      expect(shortenTeamName('Los Angeles Knight Riders'), 'LA Knight Riders');
    });
    test('Short names are returned unchanged', () {
      expect(shortenTeamName('India'), 'India');
      expect(shortenTeamName('Seattle Orcas'), 'Seattle Orcas');
    });
  });
}
