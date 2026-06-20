# Floating Score Over Other Apps — Implementation Report

Optional Android system overlay ("Floating Score over other apps") added as an
advanced, user-initiated feature. The existing in-app minimized score bar is
unchanged and remains the default. iOS is unaffected. Match Details live polling
was not touched beyond adding an entry point.

**Checks:** `flutter analyze lib/` → *No issues found*. Native: `:app:compileDebugKotlin`,
`:app:processDebugResources`, `:app:processDebugMainManifest` (with `--rerun-tasks`)
→ all **BUILD SUCCESSFUL**. No release APK / appbundle built.

---

## 1. Files inspected

Flutter:
- `lib/widgets/minimized_score_bar.dart` — existing in-app minimizer + `MinimizedScoreController`
- `lib/screens/match_details/match_details_screen.dart` — minimize wiring + live poll
- `lib/screens/match_details/widgets/match_details_ui.dart` — `MatchDetailsTopBar` minimize button
- `lib/repositories/cricket_repository.dart` / `lib/services/cricket_api_service.dart` — `liveScores()` → `/app/live-scores`
- `lib/models/cricket_match.dart` — JSON field names, score-text formatting, live/finished status sets
- `lib/core/api/api_config.dart` — base URL, API key, headers
- `lib/screens/more/more_screen.dart` + `lib/main.dart` — settings/menu + app shell
- `lib/screens/home/widgets/home_featured.dart` — `formatWomenCode` (team-code spacing rules)

Backend (read-only, to match native JSON parsing):
- `cricket-api/src/routes/app.js` — `/app/live-scores`, `projectLiveScore`, `normalizeOvers`

Android:
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/cricpro/app/MainActivity.kt`
- `android/app/src/main/kotlin/com/cricpro/app/ads/*` (bridge/SafeResult conventions)
- `android/app/build.gradle.kts` (namespace `com.cricpro.app`, applicationId `com.cric.pro`, minSdk 24 / target 36)

## 2. Files changed

New (Android native):
- `android/app/src/main/kotlin/com/cricpro/app/overlay/FloatingScoreService.kt`
- `android/app/src/main/kotlin/com/cricpro/app/overlay/OverlayBridge.kt`
- `android/app/src/main/res/layout/floating_score_bubble.xml`
- `android/app/src/main/res/drawable/floating_score_bg.xml`
- `android/app/src/main/res/drawable/floating_live_pill.xml`

New (Flutter):
- `lib/services/floating_score_overlay_service.dart`
- `lib/screens/more/floating_score_settings_screen.dart`

Modified:
- `android/app/src/main/AndroidManifest.xml` — permissions + `<service>` declaration
- `android/app/src/main/kotlin/com/cricpro/app/MainActivity.kt` — registers overlay channel + handles bubble-tap deep link
- `lib/main.dart` — registers overlay open-match handler; adds Android-only More tile
- `lib/screens/more/more_screen.dart` — optional "Floating Score over other apps" tile
- `lib/screens/match_details/match_details_screen.dart` — minimize chooser sheet (in-app vs floating)

## 3. Permission flow

`SYSTEM_ALERT_WINDOW` is **never** requested on launch. Flow:
1. User opens a live match → taps the minimize button → bottom sheet offers
   **Minimize in app** (default) or **Floating score over other apps**.
2. Choosing floating: if `Settings.canDrawOverlays()` is already true → start.
3. If not granted → `OverlayBridge.requestPermission()` opens
   `ACTION_MANAGE_OVERLAY_PERMISSION` for `package:com.cric.pro`.
4. On return, permission is re-checked. Granted → bubble starts. Denied →
   graceful fallback to the in-app minimized bar + a brief snackbar.

The More → "Floating Score" settings screen also shows status
(Enabled / Active / Permission needed / Unsupported), a **Grant permission**
button, and a **Stop floating score** button. It re-checks on app resume.

## 4. Android native implementation

- **`FloatingScoreService`** — foreground service (`foregroundServiceType="specialUse"`).
  - Window type: `TYPE_APPLICATION_OVERLAY` only (Android O+). The deprecated
    `TYPE_PHONE` / `TYPE_SYSTEM_ALERT` are **not** used; pre-O is reported
    unsupported and the service no-ops if ever started there.
  - Flags `FLAG_NOT_FOCUSABLE | FLAG_NOT_TOUCH_MODAL` so it never steals
    keyboard/touches from the app behind it.
  - Draggable via an `OnTouchListener` (move threshold distinguishes drag from tap).
  - Foreground notification: title "CricPro", text "Floating score is active",
    `IMPORTANCE_LOW`, ongoing; tapping it opens Match Details.
  - Self-polls `/app/live-scores?ids=<id>` every 5s on a single-thread scheduler.
  - Parses the same JSON shape as `CricketMatch` (`team1/team2.short_name`,
    `innings[].runs/wickets/overs`, `status`, `status_text`, `result`) and applies
    the same formatting (code spacing + overs normalization).
- **`OverlayBridge`** — MethodChannel `cricpro/overlay_bridge`:
  `isSupported`, `hasPermission`, `requestPermission`, `start`, `stop`, `isRunning`.
- **`MainActivity`** — registers the channel; captures
  `EXTRA_OPEN_MATCH_ID` from launch/`onNewIntent`, then invokes `openMatch`
  on the Flutter channel (flushed on resume to survive cold start).

## 5. Flutter integration

- **`FloatingScoreOverlay`** (singleton) wraps the channel. Every method is a
  safe no-op off Android, so callers need no platform guards.
  - `start(CricketMatch)` seeds the bubble with current score (instant display)
    and passes `baseUrl`, `apiKey`, client headers from `ApiConfig` so the
    native poller authenticates exactly like the app.
  - `registerOpenMatchHandler` is wired once in `_RootShellState.initState`;
    a bubble tap calls the existing `_openMatch(id)`.
- **Match Details**: the minimize button now opens a chooser. The in-app branch
  is byte-for-byte the old behavior (`MinimizedScoreController.instance.show`).
- **More**: Android-only tile → `FloatingScoreSettingsScreen`.

## 6. How it uses `/app/live-scores`

Both the seed (Dart) and the live updates (native) use only the fast endpoint
`GET /app/live-scores?ids=<matchId>` with headers `X-API-Key`, `X-Client-Type`,
`X-App-Version`, `X-Package-Name`. No `/app/home`, scorecard, or commentary
calls. Single match id per bubble. 5s interval is within the backend's
single-flight + 4s TTL budget.

## 7. Relationship with the in-app minimizer

- In-app minimizer is the **default** and is unchanged.
- If floating score starts successfully, the in-app bar is cleared to avoid
  duplicate UI (`MinimizedScoreController.instance.clear()`).
- If the overlay is unsupported, permission denied, or the service refuses to
  start, the app falls back to `MinimizedScoreController.instance.show(match)`.

## 8. Polling / lifecycle behavior

- Poll every 5s while the bubble is visible; runs in a foreground service so it
  continues while CricPro is backgrounded.
- Network errors keep the last good score (no error UI), retry next tick.
- On terminal match status (`completed/recent/finished/result/abandoned`) the
  bubble shows the final state for ~4s, then stops polling and the service.
- Stops immediately on close button, `stop()` from Flutter, or `onDestroy`.
- No background work survives teardown (scheduler `shutdownNow`, view removed,
  `stopForeground(REMOVE)`, `stopSelf`).

## 9. Play Store safety notes

- Overlay used **only** for the live score bubble — never ads, promos, login,
  or unrelated UI.
- Permission is user-initiated, explained in plain language
  ("Shows a small live cricket score bubble while you use other apps."), and
  fully reversible (close button + settings Stop/disable).
- No screen content is read. Touches are not blocked
  (`FLAG_NOT_FOCUSABLE | FLAG_NOT_TOUCH_MODAL`).
- FGS declared with `specialUse` subtype + honest notification text.
- No API keys/URLs/tokens are logged.

## 10. Unsupported / denied-permission fallback

- Pre-Android-O or no overlay capability → `isSupported()` returns false →
  Match Details minimize behaves exactly like before (in-app bar).
- Permission denied → in-app bar + snackbar.
- FGS refused (Android Go / restricted) → service stops cleanly; the user can
  retry or use the in-app bar.

## 11. Debug logs added (guarded)

Flutter (`kDebugMode` only, prefix `CricProFloatingScore:`):
`permission status=…`, `request permission`, `start match=<id>`, `stop`,
`open match=<id>`.

Android (`Log.d/w`, tag `CricProOverlay`): `service start`, `show bubble`,
`close`, `permission missing`, plus `permission status=…`, `open match`,
finish/stop transitions. No secrets logged.

## 12. Checks run

- `flutter analyze lib/` → **No issues found**.
- `./gradlew :app:compileDebugKotlin` → **BUILD SUCCESSFUL**.
- `./gradlew :app:processDebugResources :app:processDebugMainManifest --rerun-tasks`
  → **BUILD SUCCESSFUL** (validates new layout/drawables + manifest merge).
- Verified merged manifest contains the permissions and `FloatingScoreService`.
- **Not run:** release APK / appbundle (per instructions).

## 13. Manual device test checklist

1. Fresh install → no overlay permission prompt on launch.
2. Open a live match → minimize → choose **Floating score**.
3. First time: system overlay screen opens for `com.cric.pro`; grant → bubble appears.
4. Leave CricPro → bubble stays and updates score every ~5s.
5. Drag the bubble; confirm it doesn't block the keyboard/taps behind it.
6. Tap bubble → CricPro opens that match's details.
7. Tap ✕ → bubble disappears, polling/service stop (no lingering notification).
8. Deny permission once → app falls back to in-app bar + snackbar.
9. Let a match complete → final score shows briefly, then bubble auto-stops.
10. More → Floating Score: status reflects Enabled/Active/Permission needed; Stop works.
11. iOS / older Android: tile hidden / unsupported; in-app bar still works.

## 14. Intentionally left unchanged

- In-app minimized score bar, `MinimizedScoreController`, Home fast-score overlay.
- Match Details live polling logic (only the minimize button target changed).
- Backend (no changes), ads, stream player, payments/auth.
- No new Flutter packages added (uses platform channels + `dart:`/Flutter SDK only).

---

## 15. Completed-match persistence + premium bubble UI pass (2026-06-15)

### Root cause of auto-close
`FloatingScoreService.applyResponse()` ran `main.postDelayed({ stopSelfClean() }, 4000)`
the moment a terminal status was detected, **and** `onStartCommand` always called
`startPolling()`. So a match seeded as completed (the only thing testable with no
live match) polled once, hit the finished branch, and tore the whole service down
~a few seconds later — the bubble "appeared, then closed by itself".

### How polling and close were separated
Two now-distinct operations:

- **Stop polling** → new `stopPollingKeepBubble()`: shuts down the 5s scheduler,
  refreshes the notification copy, and **leaves the overlay view + foreground
  notification attached**.
- **Close** → existing `stopSelfClean()`: removes the view, stops foreground,
  stops the service. Reached only via the ✕ button or `ACTION_STOP` (More → Stop).

`onStartCommand` now polls only when seeded live; a completed seed logs
`completed -> stop polling, keep bubble visible` and never schedules a poll.

### Completed-match behavior
- Shows final score + result; pill renders **FINAL** (green).
- No 5s polling.
- Bubble + notification ("Final score is visible") stay until the user acts.
- Closes only on ✕ / More → Stop / explicit service stop.

### Live-match behavior (unchanged)
- Polls `/app/live-scores?ids=<id>` every 5s; pill renders **LIVE** (red).
- If a live match completes mid-session: final state rendered, polling stops via
  `stopPollingKeepBubble()`, bubble stays — no auto-close.

### In-app minimized bar
`MinimizedScoreController` already persisted finished matches (no poll, no
auto-clear; cleared only by the user's ✕). Added the required debug log only.

### UI / design changes
- `floating_score_bg.xml`: deep navy **gradient** glass, 20dp corners, cyan border.
- `floating_live_pill.xml` (red, LIVE) kept; **new** `floating_final_pill.xml`
  (green, FINAL).
- **New** `floating_close_bg.xml`: circular dark-glass close button with cyan edge.
- `floating_score_bubble.xml`: premium spacing, bold 15sp team lines, coloured
  status line (cyan live / green final), circular close. Compact (~196–248dp
  content width), fits 360dp phones, still draggable, content tap = open match.
- `render()`: pill text/colour/background + status colour switch by live/final;
  added `render state=live|final score=...` log.
- `shortenResult()`: prefers a parenthetical detail and drops "the" so long
  results shorten, e.g. `Match tied (Sri Lanka A won the Super Over)` →
  `Sri Lanka A won Super Over` (TextView still ellipsizes the remainder).

### Files changed
- `android/.../overlay/FloatingScoreService.kt`
- `android/.../res/layout/floating_score_bubble.xml`
- `android/.../res/drawable/floating_score_bg.xml`
- `android/.../res/drawable/floating_final_pill.xml` *(new)*
- `android/.../res/drawable/floating_close_bg.xml` *(new)*
- `lib/widgets/minimized_score_bar.dart` *(debug logs only)*

`OverlayBridge.kt` unchanged. No new permissions, packages, backend, ad, stream,
or Match Details / Home polling changes.

### Checks run
- `flutter analyze lib/` → **No issues found**.
- `./gradlew :app:compileDebugKotlin :app:mergeDebugResources` → **BUILD
  SUCCESSFUL** (validates new drawables + layout).
- **Not run:** release APK / appbundle (per instructions).

### Manual device test checklist
1. Minimize a completed match as Floating Score → bubble appears and **stays**.
2. Confirm no 5s network polling for the completed match (FINAL pill, static score).
3. Final score + shortened result visible in the premium FINAL card.
4. Tap ✕ → bubble closes and the notification disappears.
5. More → Floating Score → **Stop** closes the overlay (live or completed).
6. In-app minimized bar also persists for a completed match until ✕.
7. Live match still polls every 5s (LIVE pill).
8. Live → completed mid-session: polling stops, final result stays, no auto-close.
9. Tap bubble → opens the correct Match Details.
10. Bubble looks premium (dark glass, cyan border, clean pill) and is draggable.
11. No overlay permission prompt on launch.

---

## 16. Draggable bubble + live score notification pass (2026-06-16)

### Root cause of drag not working
Two bugs compounded:

1. The root drag `OnTouchListener` returned **`false` on ACTION_DOWN**. In Android,
   a view whose touch listener declines DOWN does not receive the following
   MOVE/UP, so the gesture never produced movement.
2. `floating_content` (the bulk of the bubble) had its own `OnClickListener` for
   tap-to-open. A clickable child **consumes the touch stream within its bounds**,
   so the root drag listener never even saw touches over most of the card. Only
   the thin padding around the edge could (in theory) move it.

### Drag fix
- Removed the `floating_content` click listener entirely.
- Rewrote `attachDrag`:
  - ACTION_DOWN returns **`true`** (claims the gesture; records `rawX/rawY` +
    `params.x/y`); logs `drag start`.
  - ACTION_MOVE flips to drag mode once movement exceeds `ViewConfiguration`'s
    `scaledTouchSlop`, then repositions via `windowManager.updateViewLayout`,
    clamped on-screen by `clampX`/`clampY`; logs `drag move x=.. y=..`.
    `updateViewLayout` is wrapped in try/catch so a removed view can't crash.
  - ACTION_UP with **no** drag = a tap → `openApp()`; logs `tap open`.
- The close button keeps its own click listener (small area), so it never blocks
  dragging the rest of the bubble; logs `close`.
- Position is held in the live `WindowManager.LayoutParams` for the whole overlay
  session (the view isn't recreated), so it stays where the user dropped it.

### Live score status-bar notification
Not a custom status-bar widget — an honest **ongoing foreground-service
notification**, enriched from the same poll data:

- Channel `cricpro_live_score`, `IMPORTANCE_LOW` (no sound/peek), `OnlyAlertOnce`.
- Title: `CricPro Live Score` (live) / `CricPro Final Score` (completed).
- Collapsed line: compact team-A line + status (e.g. `IND A  145/3 (16.2 ov)   SL A need 77`).
- Expanded (BigText): team A line, team B line, status.
- Tap → opens that match's Match Details (existing content PendingIntent).
- **Stop** action → `getService` PendingIntent with `ACTION_STOP` → stops service.
- Refreshed every 5s poll (`updateNotification()` after `render()`), and on
  completion. Team codes + normalized overs reuse the existing formatting helpers.

### Notification channel / permission handling
- Android 8+: dedicated channel created in `onCreate` before `startForeground`.
- Android 13+ `POST_NOTIFICATIONS`: already provided/requested via the app's
  existing OneSignal integration; not re-declared or re-requested here. If the
  user has denied it, the foreground service still runs and the overlay still
  works — `updateNotification()` is wrapped in try/catch, so a hidden/blocked
  notification never crashes.

### Completed-match behavior (unchanged from §15)
- Stops polling, keeps the bubble + a `CricPro Final Score` notification visible.
- Closing the overlay (✕ / Stop) tears down the service → notification removed.

### Files changed
- `android/.../overlay/FloatingScoreService.kt` — drag rewrite + clamp helpers,
  rich notification (title/collapsed/bigtext/Stop action), channel rename,
  per-poll notification refresh, logs; removed unused `LinearLayout` import.
- `lib/screens/more/floating_score_settings_screen.dart` — one clarifying line
  that an active overlay also shows a status-bar score (no new control).

No layout/manifest/drawable/backend/ad/stream/Home/Match-Details changes this pass.

### Checks run
- `flutter analyze lib/` → **No issues found**.
- `./gradlew :app:compileDebugKotlin` → **BUILD SUCCESSFUL**.
- **Not run:** release APK / appbundle; no resource/manifest check (no such files
  changed this pass).

### Manual device test checklist
1. Drag the bubble around — it follows the finger and stays on-screen.
2. A drag does **not** open Match Details.
3. A clean tap opens Match Details.
4. ✕ closes the overlay (and removes the notification).
5. While active, a `CricPro Live Score` notification shows in the status bar.
6. Notification score text updates every ~5s.
7. Tap the notification → correct Match Details opens.
8. Notification **Stop** action stops the service + removes the notification.
9. Completed match: `CricPro Final Score`, no polling, stays until closed.
10. Revoke notification permission → overlay/drag still work, no crash.
11. No permission prompt on app launch.
12. In-app minimizer unaffected.
