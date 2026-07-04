import '../../models/cricket_match.dart';

/// Pure, testable schedule-strip builder.
///
/// The Schedule screen's date strip is a FIXED [span]-day window starting at
/// the device's LOCAL today — generated INDEPENDENTLY of the match payload so
/// Schedule always opens on today and never anchors to an old (still-live)
/// match's start date.
///
/// Each match is bucketed by its EFFECTIVE calendar date:
///   • a LIVE match (incl. a multi-day Test that started days ago, or a match
///     starting later today) belongs to TODAY — so an ongoing NZ vs ENG Test
///     that began Jun 25 appears under Jun 28;
///   • everything else uses its LOCAL start date.
/// Matches whose effective date falls outside the window are dropped (a match
/// finished days ago is not "scheduled" going forward).
List<ScheduleDay> buildScheduleStrip({
  required List<CricketMatch> matches,
  required DateTime now,
  int span = 14,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final strip = [for (var i = 0; i < span; i++) today.add(Duration(days: i))];
  final lastDay = strip.last;
  final buckets = {for (final d in strip) d: <CricketMatch>[]};
  final seen = {for (final d in strip) d: <String>{}};

  for (final m in matches) {
    final key = effectiveScheduleDate(m, today);
    if (key == null) continue;
    if (key.isBefore(today) || key.isAfter(lastDay)) continue;
    if (m.id.isNotEmpty && !seen[key]!.add(m.id)) continue; // de-dupe per day
    buckets[key]!.add(m);
  }

  return [
    for (final k in strip)
      ScheduleDay(label: scheduleDayLabel(k), date: k, matches: buckets[k]!),
  ];
}

/// The calendar day a match belongs to. Live matches → [today]; others → their
/// local start date. Returns null when there is no parseable start time and the
/// match is not live (so it can be skipped).
DateTime? effectiveScheduleDate(CricketMatch m, DateTime today) {
  if (m.isLive) return today;
  final local = m.startDateTime?.toLocal();
  if (local == null) return null;
  return DateTime(local.year, local.month, local.day);
}

const _wk = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _mo = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', //
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
];

/// `SUN, JUN 28 2026` style label for a date chip.
String scheduleDayLabel(DateTime d) =>
    '${_wk[d.weekday - 1]}, ${_mo[d.month - 1]} ${d.day} ${d.year}';
