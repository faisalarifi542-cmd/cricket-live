import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/screens/series/series_components.dart';
import 'package:cricpro_flutter/utils/team_format.dart';

void main() {
  group('classifySeriesStatus', () {
    final now = DateTime(2026, 6, 21, 12);
    DateTime d(int day) => DateTime(2026, 6, day, 12);

    test('upcoming when start is in the future', () {
      expect(
        classifySeriesStatus(null, d(25), d(30), now: now),
        SeriesStatus.upcoming,
      );
    });

    test('completed when end is in the past', () {
      expect(
        classifySeriesStatus(null, d(10), d(18), now: now),
        SeriesStatus.completed,
      );
    });

    test('ongoing when today is within the date window', () {
      expect(
        classifySeriesStatus(null, d(20), d(24), now: now),
        SeriesStatus.ongoing,
      );
    });

    test('ongoing when a match is live, even with stale dates', () {
      expect(
        classifySeriesStatus(null, d(10), d(18), liveCount: 1, now: now),
        SeriesStatus.ongoing,
      );
    });

    test('a completed series is NEVER classified upcoming', () {
      final s = classifySeriesStatus('Completed', d(10), d(18), now: now);
      expect(s, isNot(SeriesStatus.upcoming));
      expect(s, SeriesStatus.completed);
    });

    test('an upcoming series is NEVER classified completed', () {
      final s = classifySeriesStatus('Upcoming', d(25), d(30), now: now);
      expect(s, isNot(SeriesStatus.completed));
      expect(s, SeriesStatus.upcoming);
    });

    test('liveCount>0 wins over a past end date (genuine live match)', () {
      expect(
        classifySeriesStatus(null, d(10), d(18), liveCount: 1, now: now),
        SeriesStatus.ongoing,
      );
    });

    test('end-date-in-past wins over stale "ongoing" text (Afghanistan fix)', () {
      // Series string says "ongoing" but end date is in the past → Completed.
      expect(
        classifySeriesStatus('ongoing', d(10), d(18), now: now),
        SeriesStatus.completed,
      );
    });

    test('Afghanistan Tour of India: endDate before today → Completed', () {
      final endPast = DateTime(2026, 6, 20, 12);
      final start = DateTime(2026, 6, 6, 12);
      final today = DateTime(2026, 6, 22, 12);
      final s = classifySeriesStatus('Upcoming', start, endPast, now: today);
      expect(s, SeriesStatus.completed);
      expect(s, isNot(SeriesStatus.upcoming));
    });

    // --- Local-DATE granularity (time-of-day must not flip the status) -------

    test('starts later TODAY → Ongoing, not Upcoming (date, not time)', () {
      // now is 08:00; series starts 20:00 the SAME local day and ends in 3 days.
      final nowMorning = DateTime(2026, 6, 23, 8);
      final startTonight = DateTime(2026, 6, 23, 20);
      final end = DateTime(2026, 6, 26, 23, 59);
      expect(
        classifySeriesStatus('upcoming', startTonight, end, now: nowMorning),
        SeriesStatus.ongoing,
      );
    });

    test('ends later TODAY → Ongoing, not Completed (date, not time)', () {
      // now is 22:00; series end instant is 23:59 same day → still ongoing.
      final nowLate = DateTime(2026, 6, 23, 22);
      final start = DateTime(2026, 6, 20, 10);
      final endTonight = DateTime(2026, 6, 23, 23, 59);
      expect(
        classifySeriesStatus(null, start, endTonight, now: nowLate),
        SeriesStatus.ongoing,
      );
    });

    test('ended YESTERDAY → Completed even if end instant was late', () {
      final today = DateTime(2026, 6, 23, 1);
      final start = DateTime(2026, 6, 18, 10);
      final endYesterday = DateTime(2026, 6, 22, 23, 59);
      expect(
        classifySeriesStatus('ongoing', start, endYesterday, now: today),
        SeriesStatus.completed,
      );
    });

    // --- Missing-date fallbacks --------------------------------------------

    test('no dates + bare "upcoming" string → Unknown, NOT Upcoming', () {
      // A bare provider "upcoming" with no real start date is not definitive,
      // so it must NOT land in the Upcoming filter (the reported pollution).
      final s = classifySeriesStatus('upcoming', null, null, now: now);
      expect(s, SeriesStatus.unknown);
      expect(s, isNot(SeriesStatus.upcoming));
    });

    test('no dates + provider says completed → Completed (definitive)', () {
      expect(
        classifySeriesStatus('Result', null, null, now: now),
        SeriesStatus.completed,
      );
    });

    test('no dates + provider says live → Ongoing (definitive)', () {
      expect(
        classifySeriesStatus('Live', null, null, now: now),
        SeriesStatus.ongoing,
      );
    });

    test(
        'no dates AND no status (undated edition, e.g. Afghanistan/IPL) → '
        'Unknown, never Upcoming', () {
      final s = classifySeriesStatus('', null, null, now: now);
      expect(s, SeriesStatus.unknown);
      expect(s, isNot(SeriesStatus.upcoming));
    });
  });

  // Verifies the WWC fix end-to-end: the card must surface the AUTHORITATIVE
  // full-series format/date range the backend now sends — not a match-window
  // slice. SeriesView.fromApi is the single path the Series cards/hero use.
  group('SeriesView.fromApi authoritative format + date range', () {
    final now = DateTime(2026, 6, 23, 12);

    test('WWC: full "33 T20s" label and Jun 12 – Jul 05 range; Ongoing', () {
      final view = SeriesView.fromApi(ApiSeries.fromJson({
        'series_id': '10119',
        'name': "ICC Women's T20 World Cup 2026",
        'status': 'ongoing',
        'start_date': '2026-06-12T00:00:00.000Z',
        'end_date': '2026-07-05T00:00:00.000Z',
        'format': '33 T20s',
        'matchCount': 33,
      }));
      // Count-aware backend label wins (NOT the "8 T20s" match-window slice).
      expect(view.formatSummary, '33 T20s');
      expect(view.matchCount, 33);
      // Full series span, not the next upcoming match window.
      expect(view.startDate, isNotNull);
      expect(view.endDate, isNotNull);
      expect(view.shortDateRange, contains('Jul'));
      expect(classifySeriesStatus(view.status.name, view.startDate, view.endDate,
          now: now), SeriesStatus.ongoing);
    });

    test('WWC is Ongoing on Jun 23 and excluded from Upcoming', () {
      // Classify with the group's fixed `now` (Jun 23) so the status — and
      // therefore the filter result — never depends on the real wall clock.
      // WWC ends Jul 05; after that date the real clock flips it to Completed
      // and this assertion would break. fromApi's format/range parsing is
      // already covered by the test directly above; this one targets the
      // Ongoing/Upcoming filter behaviour on a deterministic status.
      final start = DateTime(2026, 6, 12);
      final end = DateTime(2026, 7, 5);
      final view = SeriesView(
        id: '10119',
        name: "ICC Women's T20 World Cup 2026",
        status: classifySeriesStatus('ongoing', start, end, now: now),
        category: SeriesCategory.women,
        startDate: start,
        endDate: end,
      );
      final all = [view];
      expect(filterSeries(all, null, SeriesStatus.ongoing), isNotEmpty);
      expect(filterSeries(all, null, SeriesStatus.upcoming), isEmpty);
    });

    test('Afghanistan tour of India (ended Jun 20) classifies Completed', () {
      final view = SeriesView.fromApi(ApiSeries.fromJson({
        'series_id': '11641',
        'name': 'Afghanistan tour of India 2026',
        'status': 'completed',
        'start_date': '2026-06-06T00:00:00.000Z',
        'end_date': '2026-06-20T00:00:00.000Z',
      }));
      expect(classifySeriesStatus(view.status.name, view.startDate,
          view.endDate, now: now), SeriesStatus.completed);
    });
  });

  group('seriesTeamsFromTitle', () {
    test('"Afghanistan Tour Of India 2026" -> AFG, IND', () {
      final t = seriesTeamsFromTitle('Afghanistan Tour Of India 2026');
      expect(t.map((e) => e.code).toList(), ['AFG', 'IND']);
      expect(t.first.name, 'Afghanistan');
    });

    test('"Australia tour of Bangladesh 2026" -> AUS, BAN', () {
      final t = seriesTeamsFromTitle('Australia tour of Bangladesh 2026');
      expect(t.map((e) => e.code).toList(), ['AUS', 'BAN']);
    });

    test('women + u19 suffix applied to both teams', () {
      final t = seriesTeamsFromTitle('Sri Lanka Women U19 tour of India 2026');
      expect(t.map((e) => e.code).toList(), ['SL W U19', 'IND W U19']);
    });

    test('no known nation -> empty (never invents teams)', () {
      expect(seriesTeamsFromTitle('Major League Cricket 2026'), isEmpty);
    });
  });

  group('seriesCategoryOf', () {
    test('Major League Cricket -> league', () {
      expect(seriesCategoryOf('Major League Cricket 2026', null),
          SeriesCategory.league);
    });

    test("ICC Women's T20 World Cup -> women", () {
      expect(seriesCategoryOf("ICC Women's T20 World Cup 2026", null),
          SeriesCategory.women);
    });

    test('Afghanistan tour of India -> international', () {
      expect(seriesCategoryOf('Afghanistan tour of India 2026', null),
          SeriesCategory.international);
    });

    test('Australia tour of Bangladesh -> international', () {
      expect(seriesCategoryOf('Australia tour of Bangladesh 2026', null),
          SeriesCategory.international);
    });

    test('Asia Pacific Champions Trophy -> international (NOT domestic)', () {
      expect(
        seriesCategoryOf('Asia Pacific Cricket Champions Trophy 2026', null),
        SeriesCategory.international,
      );
    });

    test('Ranji Trophy -> domestic', () {
      expect(seriesCategoryOf('Ranji Trophy 2026', null),
          SeriesCategory.domestic);
    });

    test('authoritative backend category is honoured', () {
      expect(
        seriesCategoryOf('Some Cup 2026', null, backendCategory: 'domestic'),
        SeriesCategory.domestic,
      );
      expect(
        seriesCategoryOf('Some Cup 2026', null, backendCategory: 'league'),
        SeriesCategory.league,
      );
    });

    test('women override wins over a backend league bucket', () {
      expect(
        seriesCategoryOf("Women's Premier League 2026", null,
            backendCategory: 'league'),
        SeriesCategory.women,
      );
    });
  });

  group('filterSeries (category x status)', () {
    final now = DateTime(2026, 6, 22, 12);
    DateTime d(int day) => DateTime(2026, 6, day, 12);

    // Build views with an explicit `now` so the test is deterministic.
    final afg = SeriesView(
      id: 'afg',
      name: 'Afghanistan tour of India 2026',
      status: classifySeriesStatus(null, d(6), d(20), now: now),
      category: SeriesCategory.international,
      startDate: d(6),
      endDate: d(20),
    );
    final mlc = SeriesView(
      id: 'mlc',
      name: 'Major League Cricket 2026',
      status: classifySeriesStatus(null, d(18), DateTime(2026, 7, 18), now: now),
      category: SeriesCategory.league,
      startDate: d(18),
      endDate: DateTime(2026, 7, 18),
    );
    final wwc = SeriesView(
      id: 'wwc',
      name: "ICC Women's T20 World Cup 2026",
      status: classifySeriesStatus(null, d(12), DateTime(2026, 7, 5), now: now),
      category: SeriesCategory.women,
      startDate: d(12),
      endDate: DateTime(2026, 7, 5),
    );
    final asia = SeriesView(
      id: 'asia',
      name: 'Asia Pacific Champions Trophy 2026',
      status: classifySeriesStatus(null, d(25), d(30), now: now),
      category: SeriesCategory.international,
      startDate: d(25),
      endDate: d(30),
    );
    final all = [afg, mlc, wwc, asia];

    test('All x All returns everything', () {
      expect(filterSeries(all, null, null).length, all.length);
    });

    test('Completed includes the ended series, excludes upcoming', () {
      final out = filterSeries(all, null, SeriesStatus.completed);
      expect(out.contains(afg), isTrue);
      expect(out.contains(asia), isFalse);
    });

    test('Upcoming excludes completed series', () {
      final out = filterSeries(all, null, SeriesStatus.upcoming);
      expect(out.contains(afg), isFalse);
      expect(out.contains(asia), isTrue);
    });

    test('Ongoing includes in-range series', () {
      final out = filterSeries(all, null, SeriesStatus.ongoing);
      expect(out.contains(mlc), isTrue);
      expect(out.contains(wwc), isTrue);
    });

    test('League + Ongoing => Major League Cricket', () {
      final out =
          filterSeries(all, SeriesCategory.league, SeriesStatus.ongoing);
      expect(out, [mlc]);
    });

    test('Women + Ongoing => ICC Women T20 World Cup', () {
      final out =
          filterSeries(all, SeriesCategory.women, SeriesStatus.ongoing);
      expect(out, [wwc]);
    });

    test('International + Completed => Afghanistan tour of India', () {
      final out = filterSeries(
          all, SeriesCategory.international, SeriesStatus.completed);
      expect(out, [afg]);
    });

    // End-to-end against the reported bug: the backend now sends the REAL
    // Cricbuzz series date range, but historically also a stale status string.
    // Parsing through ApiSeries + classifying on Jun 23 must use the dates, so
    // a "upcoming" status can never keep the World Cup out of Ongoing.
    group('named series on Jun 23, parsed via ApiSeries (stale status ignored)',
        () {
      final jun23 = DateTime(2026, 6, 23, 12);

      SeriesStatus statusOf(ApiSeries api) {
        final v = SeriesView.fromApi(api);
        return classifySeriesStatus(api.status, v.startDate, v.endDate,
            now: jun23);
      }

      test('WWC Jun 12 - Jul 05 with stale "upcoming" status => Ongoing', () {
        const api = ApiSeries(
          id: '10119',
          name: "ICC Women's T20 World Cup 2026",
          status: 'upcoming', // stale provider text
          startDate: '2026-06-12T00:00:00.000Z',
          endDate: '2026-07-05T00:00:00.000Z',
        );
        final v = SeriesView.fromApi(api);
        // ApiSeries dates parsed onto the view.
        expect(v.startDate, isNotNull);
        expect(v.endDate, isNotNull);
        expect(v.startDate!.toUtc().month, 6);
        expect(v.startDate!.toUtc().day, 12);
        expect(statusOf(api), SeriesStatus.ongoing);
      });

      test('Afghanistan Jun 06 - Jun 20 => Completed', () {
        expect(
          statusOf(const ApiSeries(
            id: '11641',
            name: 'Afghanistan tour of India 2026',
            status: 'upcoming',
            startDate: '2026-06-06T00:00:00.000Z',
            endDate: '2026-06-20T00:00:00.000Z',
          )),
          SeriesStatus.completed,
        );
      });

      test('Major League Cricket Jun 18 - Jul 18 => Ongoing', () {
        expect(
          statusOf(const ApiSeries(
            id: '11793',
            name: 'Major League Cricket 2026',
            status: '',
            startDate: '2026-06-18T00:00:00.000Z',
            endDate: '2026-07-18T00:00:00.000Z',
          )),
          SeriesStatus.ongoing,
        );
      });

      test('India A tour of Sri Lanka Jun 25 - Jul 05 => Upcoming', () {
        expect(
          statusOf(const ApiSeries(
            id: '12283',
            name: 'India A tour of Sri Lanka 2026',
            status: '',
            startDate: '2026-06-25T00:00:00.000Z',
            endDate: '2026-07-05T00:00:00.000Z',
          )),
          SeriesStatus.upcoming,
        );
      });
    });

    test('an undated edition is Unknown: shown only under All, no status filter',
        () {
      // Backend dropped its dates/status (the real Afghanistan/IPL symptom).
      final undated = SeriesView(
        id: 'undated',
        name: 'Indian Premier League 2026',
        status: classifySeriesStatus('', null, null, now: now),
        category: SeriesCategory.league,
      );
      expect(undated.status, SeriesStatus.unknown);
      final list = [...all, undated];
      // Excluded from EVERY status filter...
      expect(filterSeries(list, null, SeriesStatus.upcoming).contains(undated),
          isFalse);
      expect(filterSeries(list, null, SeriesStatus.ongoing).contains(undated),
          isFalse);
      expect(filterSeries(list, null, SeriesStatus.completed).contains(undated),
          isFalse);
      // ...but "All" still surfaces it.
      expect(filterSeries(list, null, null).contains(undated), isTrue);
    });
  });

  group('SeriesView.fromApi team derivation (no TBD vs TBD)', () {
    test('derives teams from title when the provider omits a teams array', () {
      final view = SeriesView.fromApi(const ApiSeries(
        id: 's1',
        name: 'Afghanistan Tour Of India 2026',
        status: 'Upcoming',
        teams: <dynamic>[],
      ));
      expect(view.teams.length, 2);
      expect(view.teams.map((t) => t.shortName).toList(), ['AFG', 'IND']);
      expect(view.teams.every((t) => t.shortName != 'TBD'), isTrue);
    });

    test('parses start_date/end_date and classifies by the SERIES dates', () {
      // Series ran 6–20 Jun; "today" is 23 Jun → must be Completed from the
      // SERIES end date (not from any single match date).
      final view = SeriesView.fromApi(const ApiSeries(
        id: 's-dates',
        name: 'Afghanistan Tour Of India 2026',
        status: 'Upcoming', // stale provider text must not win
        startDate: '2026-06-06T09:30:00.000Z',
        endDate: '2026-06-20T23:59:59.000Z',
      ));
      expect(view.startDate, isNotNull);
      expect(view.endDate, isNotNull);
      expect(view.startDate!.toUtc().year, 2026);
      expect(view.startDate!.toUtc().month, 6);
      expect(view.startDate!.toUtc().day, 6);
      final status = classifySeriesStatus(
        'Upcoming',
        view.startDate,
        view.endDate,
        now: DateTime(2026, 6, 23, 12),
      );
      expect(status, SeriesStatus.completed);
    });

    test('keeps provider teams and does not duplicate a side', () {
      final view = SeriesView.fromApi(const ApiSeries(
        id: 's2',
        name: 'Australia tour of Bangladesh 2026',
        status: 'Upcoming',
        teams: <dynamic>[
          {'name': 'Australia', 'shortName': 'AUS'},
        ],
      ));
      expect(view.teams.length, 2);
      final codes = view.teams.map((t) => t.shortName.toUpperCase()).toSet();
      expect(codes.contains('AUS'), isTrue);
      expect(codes.length, 2); // no duplicate AUS
    });
  });
}
