# CricPro / WebCricHD — Performance Optimization Report

**Date:** 2026-07-04 (reconciled)
**Branch:** `apply-downloads-folder-changes`
**Scope:** runtime performance & memory in the Flutter app (`lib/`). Findings verified by direct file reads and targeted greps; speculative items marked.

---

## What is already done well (verified)

- **Image loading** — every network image routes through `CachedNetworkImage` with `fadeInDuration: Duration.zero`, a placeholder, and an `errorWidget` fallback (team logos → flag asset → initials; player avatars → initials; series posters → bundled art). No bare `Image.network` in production paths. `TeamLogoWidget` and `PlayerAvatarWidget` are the shared entry points; `StadiumImage` wraps stadium art with admin-remote fallback + `errorBuilder`.
- **`const` constructors** — used broadly across the shared components and most screens; `flutter analyze` reports zero `prefer_const` issues in production code.
- **List rendering** — long lists use `ListView`/`ListView.builder`/slivers, not `Column` of cards. The main tab scroll views reserve bottom inset via `mainScrollBottomInset` so the last card clears nav + banner ad.
- **Score formatting** — the expensive multi-innings formatting lives in `TeamScorePresentation` (`utils/score_presentation.dart`) and is computed once per `CricketMatch` parse, not re-derived in widget `build` methods. Screens render through the shared `TeamScoreView`.
- **Change-detection** — polling updates use a fingerprint key (`homeVisibleScoreKey`, `_matchRefreshKey`, minimized-bar `_scoreKey`) so a no-op poll doesn't repaint the list.
- **Responsiveness** — `context.sp()`, `context.bp`, `context.w` and the `CricBreak` buckets drive per-width sizing, so small-width layouts scale rather than overflow.

## Fixed (review + reconciliation passes)

- **`_StreamAwareLiveCard` re-firing `/streams` on every poll** (`matches_cards.dart`) — was a `StatelessWidget` that built a fresh `CricketRepository()` + `Future` inside `build`, so the 10s silent poll re-issued a stream-availability HTTP request per live card. Converted to a `StatefulWidget`: the repository is created once in State, the future is resolved in `initState` and re-resolved in `didUpdateWidget` **only when the match id changes**. A score-only poll for the same match no longer touches the network for stream state. Matches the existing pattern in `_LiveActionBar` and `_HeroCtaButton`.
- **`_Countdown` 1-second timers never stopping** (`matches_cards.dart`) — each upcoming card started a `Timer.periodic(1s)` that fired `setState` for the card's whole lifetime, even after the start time passed. Now: no timer is started when there's no future start time, and the timer cancels itself the moment the countdown reaches zero.
- **Parse-path TEMP DIAGNOSTIC debug prints** (`cricket_match.dart`) — deleted two `kDebugMode` `debugPrint` blocks that fired on every live-match parse (every poll tick in debug/profile builds) plus the now-unused `package:flutter/foundation.dart` import.
- **Unbounded static registries** (`cricket_match.dart`) — `_phaseRegistry` and `_summaryRegistry` accumulated one entry per match id ever parsed, never evicted. Bounded to 200 entries (oldest evicted) via shared `_rememberPhase`/`_rememberSummary` helpers; both write sites routed through them.
- **Matches change-key** (`matches_screen.dart`) — `_matchRefreshKey` now includes `phase` + `resultText` so a result-text or phase change on a silent poll repaints the list (previously a finished match whose result text changed wouldn't repaint).

## Findings still open (ranked)

### P1 — visible jank / repeated work

| # | File | Issue | Fix | Risk |
|---|------|-------|-----|------|
| P1-1 | `home_screen.dart`, `matches_screen.dart`, `match_details_screen.dart`, `minimized_score_bar.dart` | The live-poll + recovery state machine (`_pollTimer` + `_recoveryTimer` + `_consecutivePollFailures` + `_configurePolling` + `_armRecovery`) is copy-pasted into four screens with different intervals (Home `(8+6n).clamp(8,40)`; Matches `(10+6n).clamp(10,40)`; MatchDetails `(5+5n).clamp(5,30)`). Each reimplements `WidgetsBindingObserver` lifecycle pause/resume. Four copies = four chances for a dispose/timer leak. | Extract a `LivePollController` owning the timer + recovery + failure counter, taking a `Future<void> Function() poll` and a `Duration Function() interval`. Each screen delegates `initState`/`dispose`/`didChangeAppLifecycleState`. **Must preserve each screen's current interval curve.** Add a test. | medium |
| P1-2 | `match_details_screen.dart:626-629` (`_jsonChanged`) | `jsonEncode(oldData) != jsonEncode(next)` runs two full JSON serializations on every 5s silent poll while a match is live. | Compare a cheap content fingerprint (score/status/over fields) instead of full `jsonEncode` of both maps. | low |

### P2 — memory / efficiency

| # | File | Issue | Fix | Risk |
|---|------|-------|-----|------|
| P2-1 | `matches_screen.dart` / `schedule_screen.dart` | `_BlendImage` + `_BlendPainter` (with a static `_cache` map) duplicated across two screens. | Move to `lib/widgets/blend_image.dart`; import from both. | low |
| P2-2 | `minimized_score_bar.dart` (`_deriveChase`) | Chase-equation parsing (regex on statusText, target/progress math, batting-side pick) is business logic co-located with the widget; re-runs on every build. | Move to `lib/utils/chase_info.dart` as a pure function; the widget memoizes on `match`. | low |

### P3 — polish

| # | File | Issue | Fix | Risk |
|---|------|-------|-----|------|
| P3-1 | Various screens | Loading state is a bare default-color `CircularProgressIndicator` on 6 screens vs a cyan spinner on 3 vs a skeleton on Home. | Standardize on a shared `CricLoadingSpinner` + `CricSkeleton`. | low |

## RepaintBoundary

No `RepaintBoundary` opportunities were confirmed as needed. The animating elements (pulsing live dot, `AnimatedContainer`/`AnimatedPositioned` in `SegmentedTabs`/`BottomNav`, hero carousel auto-advance) are small and isolated; the shared components keep their `build` methods cheap. If the hero carousel or a long live-card list shows jank on a low-end device, wrap each card in a `RepaintBoundary` — but measure first; premature boundaries add layer cost.

## Timers

- The live poll uses re-armed scheduling (not a fixed periodic — correct, allows backoff). The risk is the duplication (P1-1), not the timer type.
- The minimized score bar and floating overlay manage their own timers via `MinimizedScoreController`; dispose paths were verified to clear them.
- The Live-tab `_LiveFooter` ticker (added in the reconciliation pass) only runs while a real `lastUpdatedAt` is present and the match is live, and is disposed with the widget.
- The "Updated X ago" ticker in `md_panels.dart` is per-screen and disposed with the widget.

## Release build

**Measured.** `flutter build apk --release` after `flutter clean`:

- **Command:** `flutter build apk --release`
- **Exit code:** 0
- **APK path:** `build/app/outputs/flutter-apk/app-release.apk`
- **APK size:** 79.8 MB (83,632,445 bytes)
- **Warnings:** font tree-shaking cut MaterialIcons-Regular.otf 98.7% (1.6 MB → 22 KB); one non-fatal Kotlin incremental-compiler cache warning in the build log (the build recovered and produced the APK). Java source/target 8 obsolete warnings (harmless).

The asset manifest is explicit (no globbed `assets/`), so no accidental bundle bloat. The `assets/images/series/new` folder (12 MB) is referenced by `series_new_assets.dart` and legitimate; the unreferenced `newest-design` / `current-design` dumps are gitignored and not in `assets/` for a release build.

## Recommended optimization order

1. **Extract `LivePollController`** (P1-1) — the single biggest perf/architecture win; eliminates four copies and the dispose-leak risk. Needs a test preserving intervals.
2. **Replace `jsonEncode` change-detection with a fingerprint** (P1-2) — removes a per-poll CPU spike on Match Details.
3. **Move `_deriveChase` to a util** (P2-2) — lets the bar memoize and keeps business logic testable.
4. **De-duplicate `_BlendImage`** (P2-1) — maintenance/codec-cache win.
5. **Standardize loading spinners** (P3-1) — minor rebuild/visual cost across screens.
