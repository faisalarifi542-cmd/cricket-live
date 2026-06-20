# Score Minimizer & Home Hero — Final Verification Report

Date: 2026-06-15
Branch: `phase4-remote-assets-archiving`
Static analysis: `flutter analyze lib/` → **No issues found!** (ran in ~145s)

This report documents the minimized live-score bar plus the two Home-screen
stability fixes that shipped alongside it, and records the final code-level
verification against the required behaviors. No new features were added during
this pass — verification only.

---

## The 3 bugs fixed

### Bug 1 — Hero carousel "slides/jumps" when a live score updates
The featured hero carousel is a position-based `PageView`. A silent poll would
re-resolve and re-prioritise the hero list, and because prioritisation can
reorder by favourite-country / live-ness, the match sitting under the current
page index changed — so a mere score tick made the visible hero appear to slide
to a different match.

### Bug 2 — Hero match duplicated in the list on fresh app open (and risk of an infinite skeleton)
On first paint the hero ids were not yet known (`_heroIds` empty), so the
Live/Upcoming/Finished list rendered with an empty exclude set and briefly
showed the same match that was about to "move" into the carousel — a visible
duplicate flash. A naive fix (hold the list on a skeleton until hero ids are
known) introduced the opposite risk: if the hero request failed, the list could
be stuck on a skeleton forever.

### Bug 3 — Minimized score froze / polled the wrong (heavy) endpoint
The floating minimized bar needs to keep updating after the user leaves Match
Details, but it must not hammer the heavy `/app/home` aggregation and must not
keep an aggressive timer alive in the background or after the match completes.

---

## Root causes

| Bug | Root cause |
| --- | --- |
| 1 | Silent poll adopted the freshly **re-prioritised order** every tick. A position-keyed `PageView` then displayed whatever match landed on the old index. |
| 2 | List used `excludeIds: _heroIds`, but `_heroIds` was empty until the hero future settled — and there was no "settled" gate, so the first frame leaked the hero into the list. Adding the gate without an error path created the infinite-skeleton hazard. |
| 3 | Without a dedicated controller, the bar had no independent data source; the only refresh loop was the home/detail poll, which either stopped (freeze) or, if reused naively, would have polled the heavy home feed. |

---

## Fixes (how each root cause was addressed)

**Bug 1 — order-preserving overlay.**
`_preserveHeroOrder()` ([home_screen.dart:784](lib/screens/home/home_screen.dart#L784))
compares the **id set** of the freshly-resolved heroes with the currently
displayed set:
- Same membership → keep the existing visible order, overlay only fresh
  score/status by id (score updates in place, no slide).
- Membership actually changed (a match started/finished) → adopt the new
  prioritised order — reordering is allowed only here.

The carousel widget reinforces this: `_reseatForItems()`
([home_hero.dart:49](lib/screens/home/widgets/home_hero.dart#L49)) tracks the
centred match by **id** and, when the item list identity changes, silently
`jumpToPage()` (no animation) back to the same match. `_heroListKey()` gates
repaints so an unchanged poll causes no `setState` at all.

**Bug 2 — settled gate with an error fallback.**
`_heroSettled` ([home_screen.dart:121](lib/screens/home/home_screen.dart#L121))
becomes true once the hero future **resolves or fails**. The list is held on a
skeleton via `heroPending: cfg.topFeatured.enabled && !_heroSettled`
([home_screen.dart:420](lib/screens/home/home_screen.dart#L420)) only while the
carousel is enabled and ids are unknown. Crucially, `_captureHeroIds()`'s
`catchError` ([home_screen.dart:202](lib/screens/home/home_screen.dart#L202))
flips `_heroSettled = true` on failure, so the list always unblocks. The
underlying HTTP client has a hard **12s timeout**
([api_client.dart:37](lib/core/api/api_client.dart#L37)), so a hung request
still settles and the list renders — no infinite skeleton.

**Bug 3 — dedicated `MinimizedScoreController` on the fast endpoint.**
`MinimizedScoreController` ([minimized_score_bar.dart:21](lib/widgets/minimized_score_bar.dart#L21))
is a singleton `ChangeNotifier` with a `WidgetsBindingObserver`. It polls
`_repository.liveScores([match.id])` every 5s, merges only score/status fields
(`mergeLiveScore`, no blink), pauses on background, resumes on foreground, and
stops on completion. Match Details also pushes fresh data into it via
`.update()` ([match_details_screen.dart:370](lib/screens/match_details/match_details_screen.dart#L370)),
so the bar stays current even right after the detail screen closes.

---

## Files changed

| File | Role |
| --- | --- |
| [lib/widgets/minimized_score_bar.dart](lib/widgets/minimized_score_bar.dart) | `MinimizedScoreController` (poll/lifecycle/merge) + the floating bar UI. |
| [lib/screens/home/home_screen.dart](lib/screens/home/home_screen.dart) | Hero order preservation, `_heroSettled` gate + error fallback, fast live-score overlay, poll cadence. |
| [lib/screens/home/widgets/home_hero.dart](lib/screens/home/widgets/home_hero.dart) | Id-keyed carousel re-seat (silent `jumpToPage`, no slide). |
| [lib/main.dart](lib/main.dart) | Mounts the bar in `bottomNavigationBar` Column, above the banner + `BottomNav`. |
| [lib/screens/match_details/match_details_screen.dart](lib/screens/match_details/match_details_screen.dart) | `.show()` on minimize, `.update()` from the detail poll. |
| [lib/services/cricket_api_service.dart](lib/services/cricket_api_service.dart) | `liveScores()` → `GET /app/live-scores?ids=`. |
| [lib/repositories/cricket_repository.dart](lib/repositories/cricket_repository.dart) | `liveScores()` passthrough + `CricProHomePoll` debug logs. |

---

## Polling behavior

**Minimized bar** ([minimized_score_bar.dart](lib/widgets/minimized_score_bar.dart))
- Endpoint: `/app/live-scores?ids=<matchId>` via `_repository.liveScores([id])` — the fast live-score path. **Never** touches `/app/home`.
- Interval: **5s** (`_interval`). Acceptable because the backend single-flights provider load.
- Starts only when the minimized match `isLive && !isFinished` (`_syncPolling`).
- De-dupes against Match Details pushes: a tick within `_interval` of the last `update()` is skipped (`_lastUpdated`), avoiding duplicate requests.
- Stops when the match becomes finished/completed (`_syncPolling` after each tick), when closed (`clear()`), and the lifecycle observer is removed on stop (no timer leak).
- Background: `didChangeAppLifecycleState` cancels the timer on pause; resumes via `_syncPolling()` on `resumed` (only if still live). The observer stays registered across a pause so resume re-arms; it is fully removed on `_stopPolling`.

**Home hero / list** ([home_screen.dart](lib/screens/home/home_screen.dart))
- Fast score overlay uses `_repository.liveScores(liveIds)` for visible live matches ([home_screen.dart:865](lib/screens/home/home_screen.dart#L865)) — no per-tick `/app/home`.
- Cadence (`_configurePolling`, [home_screen.dart:629](lib/screens/home/home_screen.dart#L629)): Live tab 4s; Upcoming/Finished tabs 90s, or 4s if the featured hero is live (so a live hero never freezes off-tab); otherwise paused.
- Heavy membership/hero re-resolve runs only every 4th tick (`_kMembershipEveryNTicks`); a live-only poll skips the wasteful list refetch.
- App pause cancels both poll and recovery timers; resume calls `_configurePolling()` + one immediate `_kickImmediateRefresh('resume')`. Tab re-entry triggers one silent refresh.

---

## Final verification result

`flutter analyze lib/` → **No issues found!**

Required behaviors, verified by code inspection:

1. **Hero carousel**
   - ✅ Score update keeps the same visible hero — `_preserveHeroOrder` overlays by id; `_reseatForItems` keeps the centred id.
   - ✅ No slide/jump on live score change — re-seat uses silent `jumpToPage`, never `animateToPage`.
   - ✅ No animated jump during silent refresh — `_heroListKey` suppresses repaint when nothing visible changed.
   - ✅ Reordering allowed only when membership changes (match finishes / new live match) — the `prevIds == freshIds` branch.

2. **First-load duplication**
   - ✅ Hero match not shown in the list while hero is loading — `heroPending`/`_heroSettled` skeleton gate + `excludeIds: _heroIds`.
   - ✅ No infinite skeleton on hero failure — `catchError` sets `_heroSettled = true`; HTTP client has a 12s timeout fallback.
   - ✅ Once hero ids known, the list renders normally with exclusion.

3. **Minimized score**
   - ✅ Keeps updating after leaving Match Details — dedicated controller poll + detail-screen `.update()` pushes.
   - ✅ Polling stops when the bar is closed — `clear()` → `_stopPolling()`.
   - ✅ Polling stops when the match is completed — `_syncPolling()` gate on `isLive && !isFinished`.
   - ✅ Tapping the bar opens the correct Match Details — `onTap` → `_openMatch(match.id)`.
   - ✅ Sits above the bottom nav, no overlap — mounted in the `bottomNavigationBar` Column above `StickyBannerBar` + `BottomNav`, wrapped in `SafeArea`.
   - ✅ No Android system overlay permission — no `SYSTEM_ALERT_WINDOW` in the manifest; it is an in-app widget.

4. **Fast endpoint**
   - ✅ Uses `/app/live-scores?ids=<matchId>` via `liveScores()` — confirmed in the service.
   - ✅ Does not poll `/app/home`.
   - ✅ 5s interval, acceptable under backend single-flight.

5. **Lifecycle**
   - ✅ App pause cancels the timer (no aggressive background polling).
   - ✅ Resume refreshes once immediately and re-arms only if still live.
   - ✅ No timer/observer leak — `_stopPolling` cancels the timer and removes the observer on close.

6. **Logs** — temporary debug logs are all `kDebugMode`-gated (`_kHomeDebug = kDebugMode`):
   - ✅ `CricProMiniScore` / `CricProHomePoll` / `CricProHomeHero` only print under `kDebugMode`.

---

## Manual tests still recommended

Static analysis and code inspection cannot confirm on-device runtime behavior.
Run these on a real device/emulator against the live backend:

1. With a live match in the hero, watch a score tick land — confirm the visible
   hero does **not** slide and the carousel page index is unchanged.
2. Cold-start the app on a slow/throttled network — confirm the hero match does
   not flash in the list, and the list is not stuck on a skeleton after the
   12s timeout if the hero request fails.
3. Open a live match → minimize → leave Match Details → confirm the bar keeps
   updating ~every 5s; verify in a network inspector that requests hit
   `/app/live-scores?ids=` and **not** `/app/home`.
4. Background the app for ~1 min → confirm no polling occurs while backgrounded
   → foreground → confirm one immediate refresh, then the 5s cadence resumes.
5. Let the minimized match reach a completed state → confirm polling stops and
   the final score remains on the bar.
6. Tap the minimized bar → confirm it opens the correct Match Details; tap X →
   confirm the bar disappears and polling stops.
7. Confirm the bar never overlaps the bottom nav or banner on a notched / small
   (≤360dp) device.
