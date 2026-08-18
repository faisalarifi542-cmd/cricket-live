import '../../models/cricket_match.dart';

/// Home score-rendering rules (pure + testable).
///
/// A MISSING score must never render as a real `0/0` / `0.0 OVERS`. The upstream
/// providers can emit a fabricated all-zero innings (`{runs:0, wickets:0,
/// overs:0}`) for a side that has no data — indistinguishable, from the numbers
/// alone, from a genuine `0/0` duck-start. Home therefore treats an innings as a
/// REAL batted innings only once it carries runs, a wicket, or overs bowled;
/// a `0/0` with no wickets and empty/zero overs is treated as MISSING.
///
/// This lives Home-local (NOT in the shared `TeamScoreView` / score presentation)
/// so the shared renderer and its tests are untouched.
bool isRealHomeInnings(InningsScore i) {
  if (i.runs == null) return false;
  if (i.runs! > 0) return true;
  if ((i.wickets ?? 0) > 0) return true;
  return homeOversPlayed(i.oversText);
}

/// The real batted innings for a team, oldest-first (the model already
/// normalizes order). Filters out fabricated all-zero placeholders.
List<InningsScore> homeRealInnings(List<InningsScore> innings) =>
    innings.where(isRealHomeInnings).toList(growable: false);

/// True when an overs string represents overs actually bowled (> 0). Empty or
/// `0` / `0.0` → false, so we never render `0.0 OVERS`. A non-numeric but
/// non-empty overs token is treated as present (defensive; providers vary).
bool homeOversPlayed(String overs) {
  final ov = overs.trim();
  if (ov.isEmpty) return false;
  final asNum = double.tryParse(ov);
  return asNum == null ? true : asNum > 0;
}
