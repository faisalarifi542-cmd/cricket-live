// Central match status classification + de-duplication, so every screen (Home
// sections + hero, Matches tabs, Schedule) groups a match into EXACTLY ONE of
// live / upcoming / finished using the same rules — never trusting only which
// feed a match arrived in.
//
// The backend's live and upcoming feeds can both contain the same match id (a
// fresh live entry + a stale "upcoming" entry), which is what made one match
// show in both the Live and Upcoming tabs. These helpers reconcile that by
// looking at status + score presence + start time, then de-duping by id.
import '../models/cricket_match.dart';

// Reuses the model's [MatchPhase] enum (live / finished / upcoming) so there is
// a single phase type across the app.

/// True when a team has actually batted (a real innings score exists), which
/// means the toss/play has happened — so the match cannot still be "upcoming".
bool matchHasScore(CricketMatch m) =>
    m.teamAInnings.any((i) => i.hasRuns) || m.teamBInnings.any((i) => i.hasRuns);

/// Classifies a match into its single canonical phase. Provider `status` leads,
/// but a match flagged "upcoming" that already has a score, or whose start time
/// is well in the past, is NOT treated as upcoming (it's a stale duplicate of a
/// live/finished entry). [now] is injectable for tests.
MatchPhase classifyMatch(CricketMatch m, {DateTime? now}) {
  if (m.isFinished) return MatchPhase.finished;
  if (m.isLive) return MatchPhase.live;
  // status == upcoming — validate against the data.
  if (matchHasScore(m)) return MatchPhase.live; // toss/play happened.
  final dt = m.startDateTime?.toUtc();
  if (dt != null) {
    final ref = (now ?? DateTime.now()).toUtc();
    // Started well in the past but still flagged upcoming with no score → a
    // stale entry; keep it out of Upcoming (a fresher live/finished copy exists
    // elsewhere and wins after de-dup).
    if (dt.isBefore(ref.subtract(const Duration(hours: 6)))) {
      return MatchPhase.finished;
    }
  }
  return MatchPhase.upcoming;
}

/// The Cricbuzz schedule feed lists every REMAINING DAY of an in-progress
/// multi-day match (Test / first-class) as a SEPARATE future-dated entry under
/// the same match id — `"One-off Test, Day 5"`, `"1st Test, Day 2"`, … — with no
/// score and an `"upcoming"` status. A `Day N` marker with N >= 2 proves play
/// already began on Day 1, so the entry is NOT a genuine upcoming fixture and
/// must be kept out of every Upcoming list (the ZIM vs BAN "Day 2/5" bug).
///
/// Crucially this is the ONLY signal available when the provider does NOT also
/// surface a live/recent copy of the same id (so the id-exclusion in
/// [CricketRepository.upcomingMatchesMerged] cannot catch it). `Day 1`,
/// `Day/Night`, and any description without a day number stay upcoming.
final RegExp _multiDayContinuationRe =
    RegExp(r'\bday\s*(?:[2-9]|1[0-9])\b', caseSensitive: false);

bool isMultiDayContinuationEntry(CricketMatch m) =>
    _multiDayContinuationRe.hasMatch(m.matchDesc);

bool isLiveMatch(CricketMatch m, {DateTime? now}) =>
    classifyMatch(m, now: now) == MatchPhase.live;

/// A genuine upcoming fixture: classified upcoming AND not a continuation day of
/// an already-started multi-day match. Use this everywhere an Upcoming list is
/// built so a running Test's "Day N" schedule entry never reads as a fresh
/// fixture, even when no live/recent copy exists to exclude it by id.
bool isUpcomingMatch(CricketMatch m, {DateTime? now}) =>
    classifyMatch(m, now: now) == MatchPhase.upcoming &&
    !isMultiDayContinuationEntry(m);

bool isFinishedMatch(CricketMatch m, {DateTime? now}) =>
    classifyMatch(m, now: now) == MatchPhase.finished;

/// True when a match starts today or tomorrow in the device's LOCAL date — used
/// to keep the Home Upcoming section short (the full fixture list lives in
/// Schedule). Matches with no parseable start time are excluded. [now] is
/// injectable for tests.
bool isTodayOrTomorrowLocal(CricketMatch m, {DateTime? now}) {
  final dt = m.startDateTime?.toLocal();
  if (dt == null) return false;
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final day = DateTime(dt.year, dt.month, dt.day);
  final diff = day.difference(today).inDays;
  return diff == 0 || diff == 1;
}

int _phaseRank(MatchPhase p) => switch (p) {
      MatchPhase.live => 0, // live is the most authoritative copy.
      MatchPhase.finished => 1,
      MatchPhase.upcoming => 2,
    };

/// Stable ordering by phase for the Home hero carousel: Live first, then
/// Upcoming, then Finished. Relative order WITHIN a phase is preserved (so the
/// admin/favourite order survives). [now] injectable for tests.
List<CricketMatch> orderByPhase(List<CricketMatch> list, {DateTime? now}) {
  if (list.length < 2) return list;
  int rank(CricketMatch m) => switch (classifyMatch(m, now: now)) {
        MatchPhase.live => 0,
        MatchPhase.upcoming => 1,
        MatchPhase.finished => 2,
      };
  final indexed = <(int, CricketMatch)>[
    for (var i = 0; i < list.length; i++) (i, list[i]),
  ];
  indexed.sort((a, b) {
    final r = rank(a.$2).compareTo(rank(b.$2));
    return r != 0 ? r : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// De-duplicates matches by stable id, keeping the single most-authoritative
/// copy when the same match appears more than once (live > finished > upcoming).
/// Order of first appearance is otherwise preserved. Entries with an empty id
/// are kept as-is (cannot be reconciled).
List<CricketMatch> dedupeMatchesById(List<CricketMatch> matches,
    {DateTime? now}) {
  final bestIndex = <String, int>{};
  final out = <CricketMatch>[];
  for (final m in matches) {
    final id = m.id.trim();
    if (id.isEmpty) {
      out.add(m);
      continue;
    }
    final existing = bestIndex[id];
    if (existing == null) {
      bestIndex[id] = out.length;
      out.add(m);
      continue;
    }
    // Replace the kept copy only if this one ranks higher (more authoritative).
    final keptRank = _phaseRank(classifyMatch(out[existing], now: now));
    final thisRank = _phaseRank(classifyMatch(m, now: now));
    if (thisRank < keptRank) out[existing] = m;
  }
  return out;
}
