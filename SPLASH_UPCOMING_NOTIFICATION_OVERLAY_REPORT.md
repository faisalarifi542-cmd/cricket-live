# SPLASH / UPCOMING / NOTIFICATION / OVERLAY REPORT

CricPro production QA pass. Five issues fixed: premium-but-fast splash, upcoming
Match Details "TBD vs TBD"/"No Details", admin→OneSignal notification flow,
native floating-overlay resize, and a polling-stability recheck.

Constraints honored: no release APK / appbundle built, ads untouched (only ad
*timing* preserved across the splash change), no remote heavy background assets
re-enabled, large static visuals remain local WebP.

---

## 1. Files inspected

Mapped before editing (via scoped sub-agents), then read directly the files I
changed.

Splash / startup
- `lib/features/splash/presentation/premium_splash_screen.dart`
- `lib/features/splash/widgets/splash_asset_image.dart`, `splash_glow_layer.dart`, `splash_particle_field.dart`
- `lib/main.dart` (startup gate, `_loadAppConfig`, App Open ad timing)
- `assets/splash/splash_composed.webp` (75 KB, the only splash bitmap)

Upcoming Match Details
- `lib/screens/match_details/match_details_screen.dart`
- `lib/screens/match_details/widgets/md_panels.dart`, `md_info.dart`
- `lib/models/cricket_match.dart`
- `lib/repositories/cricket_repository.dart`, `lib/services/cricket_api_service.dart` (read only)

Notifications
- `lib/services/notification_service.dart`, `notification_prompt_service.dart`
- `lib/services/notification_settings_service.dart`, `favorite_countries_service.dart`
- `lib/screens/more/notification_settings_screen.dart` (read only)
- `cricket-api/src/lib/onesignal.js` (read only — already correct)
- `admin-panel/lib/constants.ts`, `admin-panel/components/forms/NotificationForm.tsx`, `admin-panel/lib/validators.ts`

Overlay (native Android)
- `android/app/src/main/kotlin/com/cricpro/app/overlay/FloatingScoreService.kt`
- `android/app/src/main/res/layout/floating_score_bubble.xml`
- `android/.../overlay/OverlayBridge.kt`, `lib/services/floating_score_overlay_service.dart` (read only)

---

## 2. Splash screen changes

The splash was already local-only and lightweight (pure-Flutter animation over a
single 75 KB composed WebP — no Lottie/Rive, no network, no remote-asset gate).
The real defects were timing, not the art:

- **Timeline trimmed 2800ms → 2000ms** so the splash feels premium but brisk.
- **Heavy init now runs concurrently with the splash.** Previously `_loadAppConfig()`
  (await `appConfig()` + `AdService.initialize` + `NotificationService.initialize`)
  ran *only after* the splash dismissed, so a slow network produced a freeze /
  "loaded halfway" right after the splash. It is now kicked from `initState` in
  parallel with the animation, so by the time the 2s floor elapses the app is
  usually ready.
- **Soft cross-fade into the app shell** via `AnimatedSwitcher` (350ms) instead of
  a hard `setState` swap, so there is no flash/jump on transition.
- **Added a determinate loader line** (`_SplashLoaderBar`) under the logo — a
  pure-paint gradient bar that fills across the timeline, so any brief wait reads
  as progress rather than a hang.
- **Preserved ad timing:** the cold-start App Open ad must still appear *after* the
  splash, over the app UI. Since init can now finish while the splash is up, the
  cold-start ad is deferred (`_coldStartAppOpenPending`) and fired on splash
  dismissal. Ad gating/logic itself untouched.

## 3. Why the splash is safe / lightweight

- No network and no admin/server asset dependency on the splash render path
  (documented in `SplashLocalImage`; `RemoteAssetsService.load()` is fire-and-forget
  and cannot gate render).
- Single 75 KB WebP, decoded once with `cacheWidth` downscaling.
- All effects are `CustomPainter` + gradients, each wrapped in `RepaintBoundary`;
  the new loader bar is a 3px gradient box (negligible cost).
- No blank/black screen: Android launch background and pre-first-frame system UI
  are both `0xFF060B18`, matching the splash navy.
- `LayoutBuilder` + clamped logo size (`(w*0.56).clamp(190,300)`) — no overflow on
  360dp.

## 4. Upcoming Match Details — TBD / No Details fix

Root cause: `MatchDetailsScreen` is id-only. Every call site (Home, Matches,
Schedule, Series) already holds a fully-populated `CricketMatch` but passed only
`match.id`, so the screen rebuilt the match purely from `/match/:id`. For upcoming
fixtures that payload is often thin → `_team()` fell through to the `'TBD'`
placeholder and the hero showed "Match details are not available yet."

Fix (no call-site/constructor churn — reused the existing global-registry pattern
that already backs `knownPhase`):

- **`CricketMatch._summaryRegistry`** + `knownSummary(id)`: every parsed match with
  real teams (guarded by `_hasRealTeams`, so a placeholder can never overwrite a
  good entry) is cached by id. Populated in `fromJson`, exactly where the phase
  registry is already written.
- **`CricketMatch.fillFrom(other)`**: returns a copy where empty/`TBD` fields are
  backfilled from the known summary. Live-mutable fields (score, status, result,
  phase flags) always come from `this` (the fresher detail), so a refresh updates
  the score but never regresses teams.
- **Hero rendering** now:
  - renders `knownSummary` immediately while detail loads (no bare spinner),
  - on success renders `detail.fillFrom(knownSummary)` (`_matchFromDetail`),
  - on error/thin payload keeps the known summary instead of TBD,
  - only shows "not available" when there is genuinely no known summary.
- **Info tab fallback**: when the `/match/:id` info payload is empty, the Info tab
  synthesizes a basic view (teams, series, venue, format, status) from the known
  summary (`_infoFromSummary`) instead of "Match information is not available yet."
- **Tab selection unchanged**: upcoming → Info, finished → Scorecard, live → Live
  (existing `_tabForSummary`/phase seed; no flash regression).
- **Pull-to-refresh safe**: refresh re-fetches detail and re-merges via `fillFrom`;
  because merge never overwrites good fields with empty, a refresh cannot wipe the
  teams the user already saw.

## 5. Notification admin / OneSignal flow — verification & fixes

Verified end-to-end. Category pipeline was already correct and matches exactly
across all three layers:

| Flutter `notif_<key>` | Admin category id | Backend `CATEGORY_TAGS` |
|---|---|---|
| live_scores, match_start, toss, wickets, innings_result, live_stream, favorite_team, news, announcements | identical | identical |

Favorite tag format `fav_<UPPERCASE_CODE>` (no spaces) matches between Flutter
(`syncFavoriteTags`) and backend (`favoriteFilter`).

Gaps found and fixed:

1. **Fresh-install race (most important).** The first-run prompt could appear
   before OneSignal finished initializing; tapping "Enable" hit
   `requestPermission()`'s `!_initialized` guard and silently no-opped, having
   already burned the one-shot "asked" flag. Fix: `maybePrompt` now waits
   (bounded ~6s poll) for `NotificationService.isInitialized` before showing, and
   does **not** burn the flag if init never lands this session.
2. **Default tags not synced on fresh grant.** `requestPermission()` now syncs
   category **and** favorite tags immediately on a successful grant, so a brand-new
   install is targetable by category/favorite sends **without** opening Settings.
3. **Favorites never re-synced at startup.** Added a single `registerTagsSync` hook
   wired in `_loadAppConfig` right after init, pushing **both** category and
   favorite tags; called at startup (covers "permission already granted") and again
   after a fresh grant.
4. **Favorite sends had no admin entry point.** Backend supported
   `target_type: 'favorite'` but the admin UI only offered all/android/ios/category.
   Added a "By favourite country" target plus a `FavoriteTargetFields` composer
   that emits the exact `"<categoryKey>:<CODE,CODE>"` format the backend parses,
   with a `FAVORITE_COUNTRIES` catalog whose 20 codes match Flutter's
   `FavoriteCountriesService.catalog` exactly (prevents `AUS` vs `AUSTRALIA`
   mismatches).

Denied-permission UX already correct (settings screen shows "Not enabled" + Enable
button; no crash). Broadcast (`All` segment) untouched. Backend `onesignal.js` not
modified — it was already correct.

## 6. Floating overlay resize fix

Root cause: `applySize()` scaled only the four text sizes and one `minWidth` by a
gentle 0.82, while the bubble's dominant dimensions — root paddings (14/10/11/12dp),
the fixed 28dp close button + 8dp margin, inter-line margins, and the LIVE pill —
were hard-coded in XML and never scaled. Net visible change was ~14%, reading as
"not smaller."

Fix (`FloatingScoreService.kt`):
- `applySize()` now scales the **chrome too**: root paddings, close-button
  width/height/glyph/margin, LIVE-pill padding, and the three inter-line margins —
  all multiplied by the size scale via a new `dp(Float)` helper.
- Compact scale **0.82 → 0.7**, large **1.28 → 1.3**, so compact is now clearly
  smaller and large clearly bigger.
- `updateViewLayout` + on-screen clamp after resize unchanged (already correct).
- Drag, close button, tap-to-open, and persisted `sizeIndex` (SharedPreferences)
  all unchanged. Tap-to-open already stops the overlay (Flutter `_openMatch` →
  `FloatingScoreOverlay.stop()`), which also tears down the status-bar notification.
- Added `import android.widget.LinearLayout`.

## 7. Polling stability checks

Re-verified after the changes; nothing in the prior stability work was broken.
- Match Details silent poll still calls `setState` only when `_jsonChanged` detects
  a real change (no blink), restores scroll offset, and never forces the tab.
- `fillFrom` takes live-mutable fields (score/status/result/flags) from the fresh
  detail and only backfills empty/TBD metadata, so a poll updates the score without
  regressing teams or causing a tab reset.
- `_summaryRegistry` is guarded by `_hasRealTeams`, so a thin polling payload can
  never overwrite a good cached summary.
- Home hero / live cards / commentary cache / minimized score bar — **not touched**.
- Pull-to-refresh remains the only full refresh; silent polling updates in place.

## 8. Checks run

- `flutter analyze lib/` → **No issues found.** (run after each area and final)
- `admin-panel`: `npx tsc --noEmit` → **exit 0** (constants.ts + NotificationForm.tsx).
- No backend JS files changed (`onesignal.js` was read-only), so no `node --check`
  needed; admin changes are TypeScript only and covered by `tsc`.
- Per instructions: **no** release APK or appbundle built.

## 9. Intentionally left unchanged

- Ads logic (only the cold-start App Open ad *timing* was preserved across the new
  concurrent-init splash flow).
- Backend `cricket-api/src/lib/onesignal.js` and notification routes — already correct.
- Remote heavy background assets — not re-enabled; splash stays local WebP.
- The 1s countdown ticker in `matches_cards.dart` (noted previously) — still not
  lifecycle-paused; pure UI, out of scope.
- Match Details deep-link types `home`/`schedule`/`rankings` exist in the admin
  deep-link list but are not handled in `_handleNotificationDeepLink` — flagged,
  not fixed (out of this task's scope; would need product decision on targets).

## 10. Manual device QA checklist

Splash
- [ ] Splash renders instantly, no black/white flash, no half-loaded animation.
- [ ] Loader line fills smoothly; transition into Home cross-fades (no jump).
- [ ] On a slow network, splash still dismisses ~2s; app is ready or fills in
      shortly after without a freeze.
- [ ] No overflow on a 360dp / low-end device.
- [ ] Cold-start App Open ad (if enabled) still appears after the splash, over the app.

Upcoming Match Details
- [ ] Open an upcoming match from Home / Matches / Schedule / Series → real teams,
      series, date, venue, format, status; never "TBD vs TBD" or "No Details".
- [ ] Info tab shows useful info even if the provider detail is thin.
- [ ] Pull-to-refresh does not wipe teams; score/status update in place.
- [ ] Live match opens on Live (no Info flash); finished opens on Scorecard.

Notifications
- [ ] Fresh install → grant permission via first-run prompt → send a category push
      from admin → it arrives (defaults synced without opening Settings).
- [ ] Disable a category in Settings → that category push no longer arrives; enable
      → it arrives again.
- [ ] Select favourite AFG in app → admin "By favourite country" AFG push arrives;
      a non-AFG follower does not receive it.
- [ ] Live-stream quick push respects the `live_stream` opt-out.
- [ ] Broadcast (All) still sends to everyone.
- [ ] Deny permission → Settings shows Enable button, no crash.

Floating overlay (Android)
- [ ] Double-tap cycles size; **compact is clearly smaller**, large clearly bigger.
- [ ] Drag still works; bubble never ends up off-screen after resize.
- [ ] Tap opens Match Details and the overlay (and its status-bar notification)
      disappears immediately.
- [ ] No crash during a live score update while resized.
- [ ] Selected size persists across overlay restarts.

### Note on the native overlay change
The Kotlin/XML change is review-verified only — building it requires an Android
compile (APK/appbundle), which was explicitly out of scope. Please run a debug
build on a device to confirm the resize visually before release.

---

## Device QA follow-up verification

Follow-up pass over the five remaining unverified items from the last QA pass.
No new features. No release APK / appbundle. Goal: confirm the previous pass is
device-test-ready and close any code-level gap that doesn't need a device.

### Files inspected
- `android/.../overlay/FloatingScoreService.kt` — `applySize()` / `sizeScale()` /
  `cycleSize()` (overlay resize chrome scaling).
- `lib/main.dart` — `_handleNotificationDeepLink`, `RootShell`, `_RootShellState`
  (`initState`/`dispose`/`_switchTab`), `_loadAppConfig` tag-sync wiring, splash
  swap in `_buildHome`.
- `lib/services/notification_service.dart`, `notification_settings_service.dart`,
  `favorite_countries_service.dart`, `notification_prompt_service.dart` — tag sync.
- `cricket-api/src/lib/onesignal.js`, `admin-panel/lib/constants.ts` — tag parity.
- `lib/models/cricket_match.dart` (`_summaryRegistry`, `_hasRealTeams`, `fillFrom`,
  `knownSummary`), `lib/screens/match_details/match_details_screen.dart`
  (`_matchFromDetail`, `_silentPollLiveMatch`, hero builder) — upcoming fallback.
- `lib/features/splash/presentation/premium_splash_screen.dart` + `assets/splash/`.

### Issues found
1. **Notification deep-link types `home`, `schedule`, `rankings` were dead in the
   app.** The admin panel already lists all three in `NOTIFICATION_DEEP_LINKS`, so
   an admin could select them, but `_handleNotificationDeepLink` only handled
   `match` / `live_stream` / `news` / `series`. Tapping a `home`/`schedule`/
   `rankings` push did nothing. Also, the tab-target screens (Home, Schedule) are
   RootShell bottom-nav tabs — not standalone pushable routes — and the handler
   lives on a *separate* State that only held `appNavigatorKey`, with no bridge to
   switch a tab. (Confirmed via routing map: no named routes, no global key on
   `_RootShellState`, `_switchTab` private.)

### Fixes made (`lib/main.dart`)
- Added a static `RootShell.switchTab` hook. `_RootShellState.initState` registers
  its private `_switchTab`; `dispose` clears it (guarded by `identical` so a newer
  shell can't be unhooked by an older one's teardown). Null while the splash is up
  → callers no-op safely.
- `_handleNotificationDeepLink` now handles three new types, each with an early
  `return`, leaving the existing match/live_stream/news/series cases untouched:
  - `home` → `popUntil(isFirst)` then `RootShell.switchTab?.call(AppTab.home)`.
  - `schedule` → `popUntil(isFirst)` then `switchTab(AppTab.schedule)`.
  - `rankings` → `navigator.push(RankingsScreen())` (same as the More menu).
- `home`/`schedule` pop any pushed routes back to the shell before switching tabs
  so the target tab is actually visible; `rankings` pushes because it is not a tab.

### Verified — no change needed
2. **Floating overlay resize** — `applySize()` already scales every chrome element
   for compact (`sizeScale(SIZE_COMPACT)=0.7`): team/score text (15sp), status
   (11sp), LIVE pill text+padding, inter-line top margins, root paddings
   (14/11/10/12dp ×scale — the dominant footprint), close-button side+glyph+
   marginStart, and content min-width (196dp ×scale). `cycleSize()` is wired to the
   double-tap gesture and persists `sizeIndex`; `applySize()` runs on first show.
   The bubble layout is text-only (no logo/flag ImageView), so "logo size" maps to
   the LIVE pill + team text, which already scale. Re-clamp keeps it on-screen.
   *(Visual confirmation still device-only — see native-change note above.)*
3. **Fresh-install notification sync** — VERIFIED.
   - Permission grant → `requestPermission()` fires `_onTagsSync` (category +
     favorite tags) on success (`notification_service.dart`).
   - Favourite changes → `favorite_countries_service.dart` `_save`/`load` call
     `syncFavoriteTags`.
   - Startup-when-already-granted → `_loadAppConfig` calls `syncAllTags()`
     unconditionally (not gated on permission), so an already-granted user is
     targetable without opening settings.
   - First-run prompt waits for `isInitialized` and does NOT burn the one-shot
     "asked" flag if init never lands (`notification_prompt_service.dart`).
   - **Tag-name parity exact** across Flutter ↔ backend ↔ admin: 9 category keys
     (`live_scores, match_start, toss, wickets, innings_result, live_stream,
     favorite_team, news, announcements`) and 20 favourite codes
     (`AFG…CAN`, no `AFGA`/`AFG A` drift). Format `notif_<key>` / `fav_<CODE>`.
4. **Upcoming Match Details fallback** — VERIFIED.
   - `_summaryRegistry` is written only when `_hasRealTeams` is true → a TBD
     placeholder can never overwrite good teams.
   - `fillFrom` backfills only empty/`TBD` fields from the summary and always takes
     live-mutable fields (score/status/result/flags) from `this` → a refresh can't
     wipe valid teams.
   - Match Details hero renders via `_matchFromDetail` = `fromJson(detail)
     .fillFrom(knownSummary(id))`; `_silentPollLiveMatch` reassigns `_summaryData`
     but the hero still flows through that merge → pull-to-refresh / silent poll
     are safe.
   - Home / Matches / Schedule lists all parse via `CricketMatch.fromJson`, so the
     registry is populated before details opens from any of the three.
5. **Splash safety** — VERIFIED. Single local asset
   `assets/splash/splash_composed.webp` (~75KB, present); no `NetworkImage` /
   remote / `RemoteAssetsService` dependency in the splash. Two lightweight
   controllers only (2s fade-in + 1.5s pulse scale); no `BackdropFilter` /
   `ImageFilter` / shader / Lottie / video layers. Heavy init (`appConfig`, ads,
   OneSignal, tag sync) runs concurrently in `_loadAppConfig` started from
   `initState` while the splash shows; `onFinish` only swaps the splash out — first
   render is never blocked on init.

### Checks run
- `flutter analyze lib/` → **No issues found** (after the `main.dart` deep-link
  changes).
- No release APK / appbundle (per instruction).

### Remaining device-only items
- Visually confirm overlay compact is clearly smaller than normal/large on a real
  device (Kotlin/XML not compiled here).
- Tap a `home` / `schedule` / `rankings` push on device → lands on the right tab /
  Rankings screen; verify `match` / `live_stream` / `news` / `series` still work.
- Re-run the existing device checklist above (favourite priority, category opt-out,
  favourite-only targeting, overlay polling/resume, score-in-place updates).
