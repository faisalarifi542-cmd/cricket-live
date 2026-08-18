import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/services/cricket_api_service.dart';
import 'package:cricpro_flutter/utils/match_classification.dart';

Map<String, dynamic> _raw(
  String id,
  String status, {
  String series = 'Series',
  String desc = '',
  String? start,
  List<Map<String, dynamic>> team1 = const [],
}) =>
    <String, dynamic>{
      'match_id': id,
      'status': status,
      'series_name': series,
      if (desc.isNotEmpty) 'match_desc': desc,
      'team1': <String, dynamic>{'name': 'ZIM', 'shortName': 'ZIM', 'id': '1'},
      'team2': <String, dynamic>{'name': 'BAN', 'shortName': 'BAN', 'id': '2'},
      if (start != null) 'start_time': start,
      if (team1.isNotEmpty) 'score': <String, dynamic>{'team1': team1},
    };

class _FakeService extends CricketApiService {
  _FakeService({
    this.live = const [],
    this.sched = const [],
  });

  final List<Map<String, dynamic>> live;
  final List<Map<String, dynamic>> sched;

  ApiEnvelope<List<CricketMatch>> _env(List<Map<String, dynamic>> l) =>
      ApiEnvelope(
        data: l.map(CricketMatch.fromJson).toList(),
        meta: ApiMeta.fromJson(null),
      );

  @override
  Future<ApiEnvelope<List<CricketMatch>>> liveMatches() async => _env(live);
  @override
  Future<ApiEnvelope<List<CricketMatch>>> recentMatches() async =>
      _env(const []);
  @override
  Future<ApiEnvelope<List<CricketMatch>>> upcomingMatches() async =>
      _env(const []);
  @override
  Future<ApiEnvelope<List<dynamic>>> schedule(
          {String type = 'upcoming', bool forceRefresh = false}) async =>
      ApiEnvelope<List<dynamic>>(data: sched, meta: ApiMeta.fromJson(null));
}

void main() {
  final future = DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String();
  final past = DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String();

  test('a LIVE multi-day Test is excluded from merged Upcoming (Test 1 & 5)',
      () async {
    // ZIM vs BAN id 158016 is LIVE (started, has a score). The schedule feed
    // lists the SAME id as a future "Day 2" upcoming entry. The live copy must
    // win → 158016 must NOT appear in Upcoming; a genuine future fixture (999)
    // still does.
    final repo = CricketRepository(
      service: _FakeService(
        live: [
          _raw('158016', 'live',
              series: 'Bangladesh tour of Zimbabwe, 2026',
              start: past,
              team1: [
                {'runs': 120, 'wickets': 3, 'overs': 40.0, 'innings_number': 1},
              ]),
        ],
        sched: [
          _raw('158016', 'upcoming',
              series: 'Bangladesh tour of Zimbabwe, 2026', start: future),
          _raw('999', 'upcoming',
              series: 'India tour of Ireland, 2026', start: future),
        ],
      ),
    );

    final merged = await repo.upcomingMatchesMerged(forceRefresh: true);
    final ids = merged.data.map((m) => m.id).toList();
    expect(ids, contains('999'));
    expect(ids, isNot(contains('158016'))); // live copy wins, excluded
  });

  test(
      'a multi-day "Day N" schedule entry with NO live copy is still excluded '
      '(the proven ZIM vs BAN bug)', () async {
    // The exact production shape: ZIM vs BAN id 158016 is on Day 5 of a running
    // One-off Test but is NOT in the live/upcoming/recent feeds — it appears
    // ONLY in the schedule feed as a future-dated "One-off Test, Day 5" entry
    // with no score. The id-exclusion cannot catch it (no live/recent copy), so
    // the continuation-day marker must keep it out of Upcoming. A genuine
    // Day-1 fixture and a plain fixture both remain.
    final repo = CricketRepository(
      service: _FakeService(
        sched: [
          _raw('158016', 'upcoming',
              series: 'Bangladesh tour of Zimbabwe, 2026',
              desc: 'One-off Test, Day 5',
              start: future),
          _raw('700', 'upcoming',
              series: 'India A tour of Sri Lanka 2026',
              desc: '2nd Unofficial Test, Day 1', // genuine first day
              start: future),
          _raw('999', 'upcoming',
              series: 'India tour of Ireland, 2026',
              desc: '3rd T20I',
              start: future),
        ],
      ),
    );

    final merged = await repo.upcomingMatchesMerged(forceRefresh: true);
    final ids = merged.data.map((m) => m.id).toList();
    expect(ids, isNot(contains('158016'))); // Day 5 of a running Test
    expect(ids, contains('700')); // Day 1 is a real fixture
    expect(ids, contains('999')); // plain T20I fixture
  });

  group('continuation-day classification', () {
    CricketMatch m(String desc) => CricketMatch.fromJson(
        _raw('x', 'upcoming', desc: desc, start: future));

    test('"Day N" (N>=2) is a multi-day continuation, never upcoming', () {
      expect(isMultiDayContinuationEntry(m('One-off Test, Day 5')), isTrue);
      expect(isMultiDayContinuationEntry(m('1st Test, Day 2')), isTrue);
      expect(isMultiDayContinuationEntry(m('Test, Day 10')), isTrue);
      expect(isUpcomingMatch(m('One-off Test, Day 5')), isFalse);
    });

    test('Day 1 / Day-Night / no day number stay genuine upcoming', () {
      expect(isMultiDayContinuationEntry(m('2nd Unofficial Test, Day 1')),
          isFalse);
      expect(isMultiDayContinuationEntry(m('1st Test, Day/Night')), isFalse);
      expect(isMultiDayContinuationEntry(m('3rd T20I')), isFalse);
      expect(isUpcomingMatch(m('2nd Unofficial Test, Day 1')), isTrue);
    });
  });

  group('classification reconciliation primitives', () {
    test('a match WITH a score is live, never upcoming', () {
      final m = CricketMatch.fromJson(_raw('m', 'upcoming', team1: [
        {'runs': 80, 'wickets': 2, 'overs': 12.0, 'innings_number': 1},
      ]));
      expect(isUpcomingMatch(m), isFalse);
      expect(isLiveMatch(m), isTrue);
    });

    test('dedupe keeps the LIVE copy over an upcoming duplicate', () {
      final liveCopy = CricketMatch.fromJson(_raw('dup', 'live', team1: [
        {'runs': 80, 'wickets': 2, 'overs': 12.0, 'innings_number': 1},
      ]));
      final upcomingCopy = CricketMatch.fromJson(_raw('dup', 'upcoming'));
      final out = dedupeMatchesById([upcomingCopy, liveCopy]);
      expect(out.length, 1);
      expect(out.first.isLive, isTrue);
    });
  });
}
