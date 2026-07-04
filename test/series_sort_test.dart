// Tests for the canonical series-list ordering introduced by
// `sortSeriesByStatus`: Ongoing first, then Upcoming, then Completed, with
// within-section date ordering and live-match series prioritised among
// ongoing. Guards the regression where the Series list rendered in arbitrary
// backend-payload order.
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/screens/series/series_components.dart';

SeriesView _s(
  String id,
  SeriesStatus status, {
  DateTime? start,
  DateTime? end,
  int liveCount = 0,
}) =>
    SeriesView(
      id: id,
      name: id,
      status: status,
      category: SeriesCategory.international,
      startDate: start,
      endDate: end,
      liveCount: liveCount,
    );

void main() {
  group('sortSeriesByStatus — section order', () {
    test('Ongoing → Upcoming → Completed regardless of input order', () {
      final input = [
        _s('completed-1', SeriesStatus.completed,
            start: DateTime(2026, 5, 1), end: DateTime(2026, 5, 10)),
        _s('upcoming-1', SeriesStatus.upcoming, start: DateTime(2026, 7, 1)),
        _s('ongoing-1', SeriesStatus.ongoing,
            start: DateTime(2026, 6, 15), end: DateTime(2026, 6, 25)),
      ];
      final out = sortSeriesByStatus(input);
      expect(out.map((s) => s.id).toList(),
          ['ongoing-1', 'upcoming-1', 'completed-1']);
    });

    test('Unknown/TBD tails after every real status', () {
      final input = [
        _s('tbd', SeriesStatus.unknown),
        _s('completed-1', SeriesStatus.completed, end: DateTime(2026, 5, 10)),
      ];
      final out = sortSeriesByStatus(input);
      expect(out.last.id, 'tbd');
    });
  });

  group('sortSeriesByStatus — within-section ordering', () {
    test('Ongoing: live-match series first, then start-date desc', () {
      final input = [
        _s('ongo-no-live-old', SeriesStatus.ongoing,
            start: DateTime(2026, 6, 1), liveCount: 0),
        _s('ongo-live', SeriesStatus.ongoing,
            start: DateTime(2026, 6, 10), liveCount: 2),
        _s('ongo-no-live-new', SeriesStatus.ongoing,
            start: DateTime(2026, 6, 20), liveCount: 0),
      ];
      final out = sortSeriesByStatus(input);
      // Live series wins regardless of start date; then the newer ongoing series.
      expect(out.map((s) => s.id).toList(),
          ['ongo-live', 'ongo-no-live-new', 'ongo-no-live-old']);
    });

    test('Upcoming: soonest start date first; undated last', () {
      final input = [
        _s('up-far', SeriesStatus.upcoming, start: DateTime(2026, 8, 1)),
        _s('up-nodate', SeriesStatus.upcoming),
        _s('up-soon', SeriesStatus.upcoming, start: DateTime(2026, 7, 2)),
      ];
      final out = sortSeriesByStatus(input);
      expect(out.map((s) => s.id).toList(), ['up-soon', 'up-far', 'up-nodate']);
    });

    test('Completed: most-recent end date first', () {
      final input = [
        _s('done-old', SeriesStatus.completed, end: DateTime(2026, 4, 1)),
        _s('done-recent', SeriesStatus.completed, end: DateTime(2026, 6, 1)),
        _s('done-mid', SeriesStatus.completed, end: DateTime(2026, 5, 1)),
      ];
      final out = sortSeriesByStatus(input);
      expect(out.map((s) => s.id).toList(),
          ['done-recent', 'done-mid', 'done-old']);
    });
  });

  test('does not mutate the input list', () {
    final input = [
      _s('a', SeriesStatus.completed, end: DateTime(2026, 5, 1)),
      _s('b', SeriesStatus.ongoing, start: DateTime(2026, 6, 1)),
    ];
    final original = [...input];
    sortSeriesByStatus(input);
    expect(input.map((s) => s.id).toList(), original.map((s) => s.id).toList());
  });
}
