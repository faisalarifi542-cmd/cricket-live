# CricPro / WebCricHD — Performance Optimization Report

**Date:** 2026-07-04
**Branch:** `apply-downloads-folder-changes`
**Scope:** runtime performance & memory in the Flutter app (`lib/`). Findings verified by direct file reads and targeted greps; speculative items marked.

---

## What is already done well (verified)

- **Image loading** — every network image routes through `CachedNetworkImage` with `fadeInDuration: Duration.zero`, a placeholder, and an `errorWidget` fallback (team logos → flag asset → initials; player avatars → initials; series posters → bundled art). No bare `Image.network` in production paths. `TeamLogoWidget` (`components.dart:426`) and `PlayerAvatarWidget` (`components.dart:615`) are the shared entry points; `StadiumImage` (`components.dart:33`) wraps stadium art with admin-remote fallback + `errorBuilder`.

## Fixed this pass

- **`_StreamAwareLiveCard` re-firing `/streams` on every poll** (`matches_cards.dart`) — was a `StatelessWidget` that built a fresh `CricketRepository()` + `Future` inside `build`, so the 10s silent poll re-issued a stream-availability HTTP request per live card. Converted to a `StatefulWidget`: the repository is created once in State, the future is resolved in `initState` and re-resolved in `didUpdateWidget` **only when the match id changes**. A score-only poll for the same match no longer touches the network for stream state. Matches the existing pattern in `_LiveActionBar` (`home_match_cards.dart:1066`) and `_HeroCtaButton` (`home_hero.dart:613`). `flutter analyze` clean.
- **`_Countdown` 1-second timers never stopping** (`matches_cards.dart`) — each upcoming card started a `Timer.periodic(1s)` that fired `setState` for the card's whole lifetime, even after the start time passed (when the label is static). Now: no timer is started when there's no future start time, and the timer cancels itself the moment the countdown reaches zero. Cuts one steady 1Hz `setState` per upcoming card and stops the leak-on-stale-entry case. `flutter analyze` clean.
- **`const` constructors** — used broadly across the shared components and most screens; `flutter analyze` reports zero `prefer_const` issues in production code.
- **List rendering** — long lists use `ListView`/`ListView.builder`/slivers, not `Column` of cards. The main tab scroll views reserve bottom inset via `mainScrollBottomInset` so the last card clears nav + banner ad.
- **Score formatting** — the expensive multi-innings formatting lives in `TeamScorePresentation` (`utils/score_presentation.dart`) and is computed once per `CricketMatch` parse in `_flatScoreFrom`/`_parseInnings`, not re-derived in widget `build` methods. Screens render through the shared `TeamScoreView`.
- **Change-detection** — polling updates use a fingerprint key (`homeVisibleScoreKey`, `_matchRefreshKey`, minimized-bar `_scoreKey`) so a no-op poll doesn't repaint the list. (One gap: the Matches key omits `resultText` — P2-3.)
- **Responsiveness** — `context.sp()`, `context.bp`, `context.w` and the `CricBreak` buckets drive per-width sizing, so small-width layouts scale rather than overflow.

## Findings (ranked)

### P1 — visible jank / repeated work

| # | File:line | Issue | Fix | Risk |
|---|-----------|-------|-----|------|
| P1-1 | `home_screen.dart:140,696`; `matches_screen.dart:164,255`; `match_details_screen.dart:55,446`; `minimized_score_bar.dart:37,90` | The live-poll + recovery state machine (`_pollTimer` + `_recoveryTimer` + `_consecutivePollFailures` + `_configurePolling` + `_armRecovery`) is copy-pasted into four screens with different intervals (Home `(8+6n).clamp(8,40)`; Matches `(10+6n).clamp(10,40)`; MatchDetails `(5+5n).clamp(5,30)`). Each also reimplements `WidgetsBindingObserver` lifecycle pause/resume. Four copies = four chances for a dispose/timer leak. | Extract a `LivePollController` (helper class or mixin) owning the timer + recovery + failure counter, taking a `Future<void> Function() poll` and a `Duration Function() interval`. Each screen delegates `initState`/`dispose`/`didChangeAppLifecycleState`. **Must preserve each screen's current interval curve.** Add a test. | medium |
| P1-2 | `cricket_match.dart:624,670` | Two `kDebugMode` `debugPrint` dumps fire on every live-match parse — on every poll tick in debug/profile builds (compiles out in release). The 670 block is explicitly marked "TEMP DIAGNOSTIC … Remove once confirmed." | Delete both blocks, or gate behind an additional `_kInningsTrace` flag defaulted off. | low |

### P2 — memory / efficiency

| # | File:line | Issue | Fix | Risk |
|---|-----------|-------|-----|------|
| P2-1 | `cricket_match.dart:272,286` | Static `_phaseRegistry` and `_summaryRegistry` maps accumulate one entry per match id ever parsed (every list parse + every `fromCacheJson`), never evicted. `_summaryRegistry` holds full `CricketMatch` objects. Slow leak; entries are small. | Bound `_summaryRegistry` (e.g. evict oldest when > 200 entries); `_phaseRegistry` is tiny but can share the cap. | low |
| P2-2 | `matches_screen.dart:343` (`_matchRefreshKey`) | Change-key omits `resultText` — a finished match whose result text changes on a silent poll won't repaint the Matches list. (Correctness-adjacent perf: the fingerprint is wrong.) | Use the shared `homeVisibleScoreKey` (or add `resultText` to this key). | low |
| P2-3 | `matches_screen.dart:50` / `schedule_screen.dart:67` | `_BlendImage` + `_BlendPainter` (with a static `_cache` map) duplicated across two screens. Two copies of the codec-load path. | Move to `lib/widgets/blend_image.dart`; import from both. | low |
| P2-4 | `minimized_score_bar.dart:216` (`_deriveChase`) | Chase-equation parsing (regex on statusText, target/progress math, batting-side pick) is business logic co-located with the widget. Re-runs on every build of the bar. | Move to `lib/utils/chase_info.dart` as a pure function; the widget consumes the result (and can memoize on `match`). | low |

### P3 — polish

| # | File:line | Issue | Fix | Risk |
|---|-----------|-------|-----|------|
| P3-1 | `series_components.dart:416-421` | A `print` inside an `assert(() { ...; return true; }())` block (debug-only, stripped in release, `// ignore: avoid_print`). Intentional diagnostic. | Leave, or convert to `debugPrint` for consistency. | low |
| P3-2 | Various screens (F-14) | Loading state is a bare default-color `CircularProgressIndicator` on 6 screens vs a cyan spinner on 3 vs a skeleton on Home. Not a perf issue, but the inconsistent spinner is a minor rebuild/visual cost. | Standardize on a shared `CricLoadingSpinner` (`color: c.cyan`) + `CricSkeleton` for card lists. | low |

## RepaintBoundary

No `RepaintBoundary` opportunities were confirmed as needed this pass. The animating elements (pulsing live dot, `AnimatedContainer`/`AnimatedPositioned` in `SegmentedTabs`/`BottomNav`, hero carousel auto-advance) are small and isolated; the shared components already keep their `build` methods cheap. If the hero carousel or a long live-card list shows jank on a low-end device, wrap each card in a `RepaintBoundary` — but measure first; premature boundaries add layer cost.

## Timers

- The live poll uses `Timer.periodic`-style scheduling via `_configurePolling` (re-armed each cycle, not a fixed periodic — correct, allows backoff). The risk is the duplication (P1-1), not the timer type.
- The minimized score bar and floating overlay manage their own timers via `MinimizedScoreController`; dispose paths were verified to clear them.
- No permanent 1-second `Timer.periodic` was found in production paths. The "Updated X ago" ticker in `md_panels.dart` is per-screen and disposed with the widget.

## Release build size

Not measured this session. `flutter build apk --release` should be run before release to confirm tree-shaking, asset bundling, and R8/proguard. The asset manifest is explicit (no globbed `assets/`), so no accidental bundle bloat; the `assets/images/series/new` folder (12 MB) is referenced by `series_new_assets.dart` and legitimate, but verify the release bundle doesn't ship the unreferenced `newest-design` (6 MB) or `current-design` (38 MB) dumps — those are gitignored and should not be in `assets/` for a release build.

## Recommended optimization order

1. **Delete the two TEMP DIAGNOSTIC blocks** (P1-2) — zero risk, immediate debug-build noise reduction.
2. **Extract `LivePollController`** (P1-1) — the single biggest perf/architecture win; eliminates four copies and the dispose-leak risk. Needs a test preserving intervals.
3. **Bound the static registries** (P2-1) — trivial, prevents the slow leak.
4. **Move `_deriveChase` to a util** (P2-4) — lets the bar memoize and keeps business logic testable.
5. **De-duplicate `_BlendImage`** (P2-3) — maintenance/codec-cache win.
