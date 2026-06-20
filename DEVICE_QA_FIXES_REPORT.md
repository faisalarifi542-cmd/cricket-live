# Device QA Fixes + Premium UX Hardening — Phase 6 Report

Production app: **CricPro** (live on Google Play). All changes are Flutter/Dart
under `lib/`. No backend, stream-player, or live-score polling behaviour was
changed except where a task specifically required it (none did). Verified with
`flutter analyze lib/` → **No issues found!** No release APK / appbundle built.

---

## 1. Files inspected first

- `lib/screens/live/live_player_screen.dart` — pre-roll ad gating
- `lib/services/ads_manager.dart` / ad adapters — `StreamPreRollAdType` enum
- `lib/models/cricket_match.dart` — match phase (live/finished/upcoming)
- `lib/screens/match_details/match_details_screen.dart` — tab routing
- `lib/screens/home/home_screen.dart` + `widgets/home_hero.dart` — hero carousel & CTA
- `lib/repositories/cricket_repository.dart` — TTL cache, stream availability
- `lib/services/notification_service.dart` — OneSignal wrapper
- `lib/services/favorite_countries_service.dart` — prefs + ValueNotifier template
- `lib/screens/more/floating_score_settings_screen.dart` — premium settings style template
- `lib/screens/more/more_screen.dart`, `lib/main.dart` — navigation wiring
- `lib/screens/more/favorite_countries_screen.dart`, `lib/screens/teams/teams_screen.dart`

## 2. Files changed

| File | Task |
|---|---|
| `lib/screens/live/live_player_screen.dart` | 1 — ad prompt fix |
| `lib/screens/home/widgets/home_hero.dart` | 2, 5 — bigger score/logo, smart CTA |
| `lib/models/cricket_match.dart` | 3, 4 — phase registry |
| `lib/screens/match_details/match_details_screen.dart` | 3, 4 — initial tab |
| `lib/screens/home/home_screen.dart` | 5, 6 — CTA wiring, refresh invalidation |
| `lib/repositories/cricket_repository.dart` | 6 — stream-cache invalidation |
| `lib/services/notification_service.dart` | 7 — permission + tag sync |
| `lib/services/notification_settings_service.dart` | 7 — **new** prefs service |
| `lib/screens/more/notification_settings_screen.dart` | 7 — **new** screen |
| `lib/main.dart` | 7 — startup load, tag sync, route |
| `lib/screens/more/more_screen.dart` | 7 — menu entry |
| `lib/screens/more/favorite_countries_screen.dart` | 8 — 1-column list |

---

## 3. Fixes

### Task 1 — Rewarded interstitial showed the wrong opt-in prompt
`_selectStream` previously showed the app-side "Watch a short ad" confirmation
for **both** `rewardedVideo` and `rewardedInterstitial`. A rewarded interstitial
already shows its own SDK intro screen, so the second app prompt looked like the
wrong (rewarded-video) flow. Now the app-side opt-in is shown **only** for
`rewardedVideo`; `rewardedInterstitial` goes straight to the SDK screen.

### Task 2 — Hero carousel score + logo too small
`_HeroMetrics.of` sizes increased (logo/score/code) across wide/normal/small
breakpoints. `FittedBox(scaleDown)` already bounds them so larger values never
overflow on 360 dp.

### Task 3 / 4 — Match opens on the right tab (no Info flash)
Tab previously defaulted to Info(0) and only switched after the network summary
resolved, causing a visible flash. Added a synchronous `MatchPhase` registry in
`cricket_match.dart`, seeded at parse time, so the correct tab renders on the
**first frame**:
- Live → **Live** tab (1), with Scorecard preloaded
- Finished → **Scorecard** tab (2)
- Upcoming/unknown → **Info** tab (0)

The post-frame summary check (`_maybeApplyInitialTab`) now only *corrects* a
stale seed and never fires when the seed already matched — so no flash, and a
user tap (`_userPickedTab`) is never overridden.

### Task 5 — Hero CTA: "Watch Live" vs "Match Center"
Replaced the static Match Center button with a stateful `_HeroCtaButton` that
resolves `repository.shouldShowWatchLiveForMatch(match)` and caches the future
per `(matchId, streamEpoch)` so polling never re-triggers it (no flicker). Shows
a red "Watch Live" pill when a stream exists, else the cyan "Match Center" pill.
Finished matches are never eligible.

### Task 6 — Pull-to-refresh surfaces newly-added streams
Home reuses a single cached `_repository` instance, so a freshly-added stream
wouldn't appear without an app restart. Added
`CricketRepository.invalidateStreamAvailability()` (drops `app:config` and
`match:*:streams` cache entries) and call it from `_refresh()`, bumping
`_streamEpoch` so every hero CTA re-resolves with `forceRefresh`. Match cards
already use fresh repo instances, so they were unaffected.

### Task 7 — Notification Settings screen (More)
- New `NotificationSettingsService` (singleton, SharedPreferences, reactive
  `ValueNotifier`). 9 categories; match/live/favourite default **ON**,
  announcements default **OFF**. Persists locally and mirrors each choice to
  OneSignal tags (`notif_<key>` = '1'/'0') for server-side filtering.
- `NotificationService` gained `permissionGranted`, `requestPermission()`, and
  `syncCategoryTags(...)`.
- New `NotificationSettingsScreen` (premium style matching Floating Score):
  system-permission status chip, an **Enable notifications** button shown only
  when permission is not granted (no aggressive auto-request), and a toggle row
  per category. Re-checks permission on lifecycle resume.
- Wired into More → "SUPPORT & MORE", startup `load()`, and a tag re-sync after
  OneSignal init in `main.dart`.

### Task 8 — Favorite Countries as a 1-column premium list
Replaced the 3-column `GridView` with a `ListView.separated` of full-width rows:
larger flag badge (42 px), team name + code subtitle, and a selected/check
indicator. `TeamsScreen` is an intentional empty-state placeholder (no global
teams feed yet) — it has no grid, so nothing to convert there.

### Task 9 — Targeted visual polish
Spacing/padding tuned on the redesigned Favorite Countries rows and the new
Notification Settings screen; single-line ellipsis on long team names keeps
360 dp safe. No broad restyle — kept minimal per instructions.

### Task 10 — Score stability preserved
No change to live-score polling. Hero CTA future caching, the carousel re-seat
logic, and the tab phase registry all avoid setState churn during polling, so
there is no blink, jump, scroll reset, carousel slide, or button flicker.

---

## 4. Checks run

- `flutter analyze lib/` → **No issues found!** (final run)
- No release APK or appbundle built (production rule).

## 5. Left intentionally unchanged

- **Match Details has no "Watch Live" button.** `MatchDetailsScreen.onWatchLive`
  is declared but unused; the single Watch Live entry point is the Home hero CTA
  (`_openLivePlayer`). Fabricating a button here was out of scope, so the dead
  plumbing was left as-is rather than wiring a new UI element.
- Backend, stream player, and live-score polling untouched.

## 6. Manual device test checklist

- [ ] Rewarded-interstitial stream: no app-side "watch ad" prompt before SDK screen.
- [ ] Rewarded-video stream: app-side opt-in dialog still appears.
- [ ] Open a **live** match → lands on **Live** tab, no Info flash.
- [ ] Open a **finished** match → lands on **Scorecard** tab.
- [ ] Open an **upcoming** match → lands on **Info** tab.
- [ ] Hero shows **Watch Live** for a streamed match, **Match Center** otherwise.
- [ ] Add a stream in admin → pull-to-refresh on Home → CTA flips to Watch Live (no restart).
- [ ] More → Notification Settings: toggles persist across app restart.
- [ ] Deny system notifications → status chip shows "Not enabled" + Enable button.
- [ ] Favorite Countries shows a 1-column list; selection check toggles correctly.
- [ ] Watch a live score update — no blink/jump/scroll-reset/carousel-slide/button-flicker.
- [ ] 360 dp device: hero score/logo and team names don't overflow.

---

# Pre-roll fail-open + quality-card ad session capping fix

## Root cause
The pre-roll ad was **fail-closed**. Both entry points awaited
`AdsManager.showStreamPreRoll(...)` behind a "Loading ad…" dialog with **no
timeout**:
- `main.dart` `_openLivePlayer` (Watch Live tap → entry pre-roll), and
- `live_player_screen.dart` `_selectStream` (in-player stream pre-roll).

If the ad SDK hung on load/show (no response, never returns), the `await` never
completed, so the loading dialog stayed up and the player/stream was never
started. No-fill/load-fail/exception were already handled logically, but a true
SDK hang trapped the user on loading forever.

Additionally, manual **quality-card** switches went straight to `_loadStream`
and never attempted the admin-selected pre-roll, and there was **no session
capping**, so a pre-roll could show on every eligible action.

## Files changed
- `lib/screens/live/live_player_screen.dart` — new `_runPreRollGate()` fail-open
  helper with timeout; `_selectStream` and `_selectQuality` routed through it;
  cleaned opt-in / loading wording.
- `lib/main.dart` — entry pre-roll in `_openLivePlayer` made fail-open
  (timeout + session-cap skip); added `dart:async` import.
- `lib/services/ads/ads_manager.dart` — `PreRollCapDecision` enum,
  `preRollCapDecision()`, `_markPreRollShown()` (counts only ads that actually
  showed: interstitial shown / rewarded earned).
- `lib/models/ad_config.dart` — cap getters: `preRollSessionCapEnabled`,
  `preRollMaxPerSession`, `preRollMinSecondsBetweenAds`,
  `preRollApplyToQualitySwitch`, `preRollApplyToServerSwitch`.
- `cricket-api/src/lib/public-app-state.js` — exposes the five cap fields under
  `ads.frequency` (admin-overridable via existing `frequency_config` JSON).

## Fail-open behavior
Pre-roll never permanently blocks playback. `_runPreRollGate` returns "proceed"
on: session-cap/min-interval skip, load fail, no-fill, show fail, exception, and
timeout. The **only** case that blocks is a **required premium reward unlock**
that wasn't earned — that stays gated by design (requirement 14). Quality-switch
pre-roll always proceeds to load regardless of ad outcome.

## Timeout used
8 seconds, bounding the whole waterfall (load + show across networks) at both
entry points. On timeout the attempt is treated as failed → stream starts.

## Quality / server card behavior
- Quality-card switch attempts the admin pre-roll when
  `preRollApplyToQualitySwitch` is on and not capped, then loads the new
  quality. Internal retries and backup-URL fallback call `_loadStream`
  directly, so they never trigger a pre-roll (no double/spam ads).
- There is **no separate server-card UI** in the current player (quality tiers
  are the only in-player switch). `preRollApplyToServerSwitch` is plumbed and
  defaulted ON for when such a control is added.

## Session capping fields and defaults
Under `ads.frequency` (admin can override via `frequency_config`):
- `preRollSessionCapEnabled` — default **true**
- `preRollMaxPerSession` — default **3**
- `preRollMinSecondsBetweenAds` — default **180**
- `preRollApplyToQualitySwitch` — default **true**
- `preRollApplyToServerSwitch` — default **true**

Impressions are counted **only when an ad actually showed**, tracked in memory,
and reset on app process restart (not persisted across days).

## Admin/backend changed?
Yes — `public-app-state.js` only, to surface the five fields (additive, existing
ad settings untouched). No DB migration added: admins can drive these now via
the existing `frequency_config` JSON; dedicated columns/UI can be added later.

## Double-start guard
A single user action = one pre-roll attempt = one stream start. The existing
`_streamAdInProgress` flag serializes the gate and the `_selectedStream?.id`
equality check blocks auto-select re-entry during live polling, so the
timeout path and any late ad callback cannot both start the stream. (No global
`_streamStartTriggered` flag was added because `_loadStream` is intentionally
reused by retry/backup/quality/go-live paths; a global guard would break those.)

## Checks run
- `flutter analyze lib/` → **No issues found!**
- `node --check cricket-api/src/lib/public-app-state.js` → OK
- No release APK / appbundle built.

## Intentionally left unchanged
- Stream URL handling, video player core playback, HLS parsing, backup-URL
  retry chain.
- Premium/rewarded unlock requirement (still enforced; only a genuine SDK hang
  on a *required* unlock shows the retry message instead of opening).
- Home/Match Details polling, floating score, unrelated ad formats
  (banner/native/app-open/general interstitial).

## Known edge
After an 8s timeout the abandoned ad future is not cancellable via the adapter
API; a very late ad could appear over already-playing video. The video keeps
playing underneath — playback is never blocked.
