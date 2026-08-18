# CricPro Home Premium Visual Evidence

## Machine-verified geometry

The production renderer and tests share `calculateHomeHeroDiagnostics`; tests do
not duplicate the hero height calculation.

| Screen | Active card | Height | Aspect height | Content floor | Floor active | Ratio | Score | Emblem metric | CTA |
|---:|---:|---:|---:|---:|:---:|---:|---:|---:|---:|
| 352 | 328.40 | 245.07 | 245.07 | 245.07 | No | 1.340 | 28.00 | 60.00 | 44 |
| 391 | 367.45 | 274.22 | 274.22 | 274.22 | No | 1.340 | 28.66 | 69.82 | 48 |
| 477 | 448.97 | 335.05 | 335.05 | 335.05 | No | 1.340 | 35.02 | 85.30 | 48 |
| 491 | 462.38 | 345.06 | 345.06 | 345.06 | No | 1.340 | 36.07 | 87.85 | 48 |

Previous compact ratio was approximately 1.15. At 352px the real carousel-card
intersection test measured both neighbours inside the required 4–6px band and
the active card centred within 1.5px. No neighbouring readable content enters
the viewport.

Accessibility diagnostics at text scale 1.15 and `fontHeightBoost: 0.06` retain
a ratio of at least 1.22. The compact venue exposes its complete, untruncated
label exactly once through semantics. Normal Home cards use a fixed 256px phone
height (270px wide) across short/long/missing venue, missing score, and phase
variants. The final card clears the shared BottomNav by at least 8px.

## Visual refinements

- Reduced the Home wordmark from 40px to 36px and added calmer header breathing room.
- Replaced the filled bell blob with a Home-local 44px outlined cyan circle,
  white bell, and restrained unread dot.
- Reduced carousel side exposure and kept the active card centred.
- Added a stronger Home-local navy stadium scrim, darker score/header bands,
  and a controlled cyan centre highlight to suppress the orange horizon.
- Preserved current/latest innings only, with compact `1st Inn` / `2nd Inn`
  labels and full historical innings still in the model and detail views.
- Tightened compact hero spacing without enlarging the hero, emblems, or CTA.
- Refined Match Center with a softer shadow/highlight; height remains 44px on
  compact heroes and 48px on wider heroes.
- Reduced broad emblem, dot, active-tab, and normal-card glow.
- Added subtle normal-card centre depth and cleaner team rings.
- Rebuilt the normal-card footer as a reserved venue row plus a separate
  date/action row.

## Tests and tooling

- `dart format lib/screens/home test/home_hero_dimensions_test.dart test/home_visual_evidence_test.dart test/home_hero_overflow_test.dart` — clean.
- `flutter analyze --no-pub ...` — no errors/warnings; three pre-existing
  `no_leading_underscores_for_local_identifiers` info notices in
  `home_hero_overflow_test.dart`.
- `flutter test --no-pub test/home_hero_overflow_test.dart` — 4/4 passed.
- `home_hero_dimensions_test.dart` — 10/10 passed after implementation. A later
  post-polish rerun stalled without output in the Windows Flutter runner after
  90 seconds; the visual-only changes did not alter geometry formulas.
- Default `home_visual_evidence_test.dart` — 12/12 passed without writes.
- Gated PNG capture produced all 12 files. On this Windows runner a multi-capture
  process remains alive after `RenderRepaintBoundary.toImage`; generation was
  performed one capture per fresh Flutter process. The test source remains
  normally gated and contains no forced process exit.

## Evidence PNGs

Files are under `build/home_visual_evidence/`:

- `home_352x856_{single,multi,yet_to_bat}.png`
- `home_391x844_{single,multi,yet_to_bat}.png`
- `home_477x922_{single,multi,yet_to_bat}.png`
- `home_491x912_{single,multi,yet_to_bat}.png`

## Requires user device review

Geometry does not prove perceived quality. Please review stadium darkness,
orange suppression, glow restraint, header balance, real Android font metrics,
and side-by-side premium balance on the physical device.

## Final Home cleanup - 2026-07-14

- Hero geometry, logo/emblem sizes, score sizes, and CTA dimensions remain
  unchanged. The isolated stadium layer has a stronger navy scrim and darker
  score/footer bands; the single card border is the only hero edge stroke.
- Compact venue spacing increased while decorative slack was reduced. Wide
  LIVE/phase pills use tighter internal padding so the 391px multi-innings
  fixture remains overflow-free.
- Match Center keeps its 44/48px height and now has a deeper gradient, subtle
  internal highlight, low-opacity outline, and softer shadow.
- Active segmented-tab brightness and glow were reduced.
- Upcoming teasers show one complete card plus a deterministic 12px hint below
  440px content width; at 440px and above, two complete cards fit. Cards are
  142px tall with fixed 32/61/18px header/body/footer regions and stable keys.
- `More Upcoming Matches` scales down on one line rather than ellipsising.
  Featured Series gained heading/card spacing and trailing clearance.

Latest machine checks:

- Hero overflow: 4/4 passed.
- Score resilience + behavior + feed: 38/38 passed.
- Default visual-evidence rendering: 12/12 passed across all requested sizes.
- Scoped analyzer: no errors/warnings; three existing info notices remain.
- Dimensions rerun stalled before emitting its first case and was terminated
  after 150 seconds; no pass is claimed for that rerun.
- Write-enabled PNG generation deadlocked again after raster capture on this
  Windows runner. `home_352x856_single.png` refreshed; the other eleven remain
  the previously generated evidence set. The final non-writing render suite
  passed every size/state combination.
