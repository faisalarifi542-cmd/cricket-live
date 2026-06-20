// Centralized cricket score presentation — the single source of truth for
// turning a team's structured [InningsScore] list into UI-friendly strings.
//
// Every score block in the app (Home hero, Home/Matches cards, Match Details
// header, minimized score bar) renders through this + the shared `TeamScoreView`
// widget, so a limited-overs match reads `218/10` / `44.2 ov` and a Test/first-
// class match reads `362/10 & 391/10` / `87.1 ov • 96.2 ov` — consistently,
// never truncated, never with one innings tiny and another huge.
import '../models/cricket_match.dart';

/// Context in which a team score is rendered. Each mode owns its own font
/// sizing, layout type and current-innings highlight behaviour — so we never
/// force one generic FittedBox layout onto every screen. The `…MultiInnings`
/// variants are hints from the call site; the actual single-vs-multi layout is
/// ultimately decided by the data (a Test that has only batted once still reads
/// as a single innings).
enum ScoreDisplayMode {
  heroLimitedOvers,
  heroMultiInnings,
  cardLimitedOvers,
  cardMultiInnings,
  matchDetailsLimitedOvers,
  matchDetailsMultiInnings,
  compactBar,
}

/// The layout family a mode belongs to (roomy hero/details stacked rows, tight
/// card stacked rows, or the single-line compact bar).
enum ScoreLayoutFamily { hero, card, details, bar }

extension ScoreDisplayModeX on ScoreDisplayMode {
  ScoreLayoutFamily get family => switch (this) {
        ScoreDisplayMode.heroLimitedOvers ||
        ScoreDisplayMode.heroMultiInnings =>
          ScoreLayoutFamily.hero,
        ScoreDisplayMode.cardLimitedOvers ||
        ScoreDisplayMode.cardMultiInnings =>
          ScoreLayoutFamily.card,
        ScoreDisplayMode.matchDetailsLimitedOvers ||
        ScoreDisplayMode.matchDetailsMultiInnings =>
          ScoreLayoutFamily.details,
        ScoreDisplayMode.compactBar => ScoreLayoutFamily.bar,
      };
}

class TeamScorePresentation {
  const TeamScorePresentation(this.innings);

  final List<InningsScore> innings;

  /// Only innings that have actually been batted (have a runs figure).
  List<InningsScore> get scored =>
      innings.where((i) => i.hasRuns).toList(growable: false);

  /// True when this team has any score to show.
  bool get hasScore => scored.isNotEmpty;

  /// True for Test / first-class style scores with two or more innings.
  bool get isMultiInnings => scored.length > 1;

  /// Combined score line, oldest innings first: `362/10 & 391/10`.
  /// For a single innings this is just `218/10`.
  String get combinedScore => scored.map((i) => i.scoreText).join(' & ');

  /// Per-innings overs text (no unit), only for innings that carry overs.
  List<String> get oversList =>
      scored.map((i) => i.oversText).where((o) => o.isNotEmpty).toList();

  /// Overs line. `unitEach` true → `87.1 ov • 96.2 ov` (roomy layouts);
  /// false → `87.1 • 96.2 ov` (tight list cards). Single innings → `44.2 ov`.
  /// Empty when no innings carries overs.
  String oversLine({bool unitEach = true}) {
    final o = oversList;
    if (o.isEmpty) return '';
    if (o.length == 1) return '${o.first} ov';
    return unitEach ? o.map((e) => '$e ov').join(' • ') : '${o.join(' • ')} ov';
  }

  /// Clamps a caller-supplied current-innings index to the valid range of
  /// [scored]. The current innings is decided by the MATCH (which side is
  /// actually batting — see `CricketMatch.currentScoredIndexForTeam`), NOT by
  /// "is the match live", so the `*` lands only on the batting team's active
  /// innings and never on both teams. Returns `-1` (no highlight) when the
  /// supplied index is out of range.
  int resolveCurrentIndex(int index) =>
      (index >= 0 && index < scored.length) ? index : -1;

  /// `1st`, `2nd`, `3rd`, `4th`… ordinal label for an innings row.
  static String ordinal(int oneBased) {
    if (oneBased >= 11 && oneBased <= 13) return '${oneBased}th';
    return switch (oneBased % 10) {
      1 => '${oneBased}st',
      2 => '${oneBased}nd',
      3 => '${oneBased}rd',
      _ => '${oneBased}th',
    };
  }
}
