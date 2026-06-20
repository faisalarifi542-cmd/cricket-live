# Production QA Stability Report — CricPro

Focused QA fix pass covering favourite-country priority, notification
preferences, floating-overlay polling + resize, score-polling stability, and
remaining visual formatting. No release/appbundle builds were run.

---

## 1. Files inspected

Flutter:
- `lib/screens/home/home_screen.dart` — hero resolution + favourite prioritisation
- `lib/screens/home/widgets/home_match_cards.dart` — lower match list / grid
- `lib/screens/home/widgets/home_hero.dart`, `home_featured.dart` — hero carousel + change-key
- `lib/screens/matches/matches_screen.dart`, `widgets/matches_cards.dart` — match cards + live card
- `lib/screens/match_details/widgets/match_details_ui.dart` — hero score card, team code, status
- `lib/screens/match_details/widgets/md_timeline.dart` — commentary score validation
- `lib/screens/schedule/widgets/schedule_cards.dart` — verified team-code formatting (already correct)
- `lib/upcoming_sort.dart`, `lib/models/cricket_match.dart` — sort + status flags + merge
- `lib/services/favorite_countries_service.dart` — favourites + tag sync
- `lib/services/notification_service.dart`, `notification_settings_service.dart` — OneSignal tags
- `lib/screens/more/notification_settings_screen.dart`, `floating_score_settings_screen.dart`
- `lib/services/floating_score_overlay_service.dart` — Dart overlay bridge

Android native:
- `android/app/src/main/kotlin/com/cricpro/app/overlay/FloatingScoreService.kt`
- `android/app/src/main/kotlin/com/cricpro/app/overlay/OverlayBridge.kt`
- `android/app/src/main/res/layout/floating_score_bubble.xml`

Backend / admin:
- `cricket-api/src/lib/onesignal.js` — OneSignal payload + targeting
- `cricket-api/src/routes/app.js` — device register/update (inspected, unchanged)
- `cricket-api/src/admin/index.js`, `admin/routes/extra.routes.js` — notification routes (inspected)
- `admin-panel/lib/constants.ts`, `lib/validators.ts`
- `admin-panel/components/forms/NotificationForm.tsx`, `app/notifications/page.tsx`

---

## 2. Favourite country priority fix (Task 1)

Root cause: `_prioritiseHero` floated any favourite match to the front of the
hero carousel regardless of its status. A favourite playing tomorrow was
promoted ahead of an unrelated live match.

Fix (`home_screen.dart`, `_prioritiseHero`):
- Compute the best status bucket present (live > upcoming > finished).
- Only float a favourite to the front if it sits **in that top bucket**.
- A live non-favourite therefore always outranks tomorrow's favourite.
- Among favourites in the same bucket, the soonest start time wins.
- If the chosen favourite is already primary, return the list unchanged so a
  poll never re-seats the carousel.

Result: live matches always lead; favourite only reorders within the same
status bucket; existing hero dedup with lower lists is untouched.

---

## 3. Notification preferences / OneSignal / admin fix (Task 2)

State before: the Flutter app already wrote per-category OneSignal tags
(`notif_<key>` = '1'/'0') and had a complete category-toggle settings screen
with permission-status UI and an Enable button. The **backend ignored those
tags** — every send targeted segments All / Android / iOS only, so disabling a
category had no server-side effect. Favourite-only targeting did not exist.

Changes:
- `cricket-api/src/lib/onesignal.js`:
  - New `category` target type → emits OneSignal `filters: [{tag, notif_<key>, '!=', '0'}]`,
    so a send reaches only users who left the category on (default-on tags and
    explicit '1' both qualify; '0' is excluded).
  - New `favorite` target type (`<categoryKey>:<CODE,CODE,…>`) → ANDs the
    category opt-in with OR-joined `fav_<CODE>` tags.
  - Existing `all` / `android` / `ios` / `subscription` paths unchanged →
    broadcast push is preserved.
- `lib/services/notification_service.dart`: added `syncFavoriteTags` writing
  `fav_<CODE>` = '1'/'0' for the full catalogue (deselected codes cleared).
- `lib/services/favorite_countries_service.dart`: calls `syncFavoriteTags` on
  load and on every save so favourite tags stay in step with the selection.
- `admin-panel/lib/constants.ts`: replaced the dead `premium` target (it
  silently fell back to All) with a real `category` target + `NOTIFICATION_CATEGORIES`
  list whose ids match the Flutter category keys.
- `admin-panel/components/forms/NotificationForm.tsx`: shows a category dropdown
  when target = category instead of a free-text value field.
- `admin-panel/app/notifications/page.tsx`: the "Live stream push" quick action
  now targets `category` / `live_stream` so users who disabled live-stream
  alerts don't receive it.

Acceptance mapping:
- Disable "Live stream available" → tag `notif_live_stream='0'` → category send
  excludes the device. ✔
- Favourite-only → `favorite` target ANDs category + `fav_<CODE>` tags. ✔
- Admin category push respects the chosen category. ✔
- Permission denied → settings screen already explains and offers Enable; no
  crash (OneSignal getters guarded). ✔
- Settings persist across restart (SharedPreferences). ✔

Note: server-side audience counts per category are not computed (would require
querying OneSignal or storing prefs in `app_devices`). Tags remain the source of
truth — intentionally left as-is to avoid schema changes.

---

## 4. Floating overlay polling fix (Task 3)

Finding: native polling **already exists and is correct**. `FloatingScoreService`
polls `GET {baseUrl}/app/live-scores?ids=<id>` every 5s on a
`ScheduledExecutorService` (not a Flutter timer), keeps the last good score on
network failure, auto-recovers on the next tick, mirrors the score into the
status-bar notification each poll, and stops polling (keeping the bubble) when
the match finishes. The task report predates this implementation.

Hardening applied:
- Wrapped the scheduled task body in a catch-all. `scheduleWithFixedDelay`
  silently cancels all future runs if the task throws uncaught; the wrap means a
  single unexpected error can't permanently freeze the bubble.

No secrets are logged (API key/headers never printed). Team-code and overs
formatting in native (`formatCode`, `normalizeOvers`) already match Flutter
(NZW→NZ W, SLW→SL W, INDA→IND A, 49.6→50.0).

---

## 5. Overlay resize behaviour (Task 4)

Added double-tap-to-cycle size (compact → normal → large → compact), the
recommended stable UX:
- `FloatingScoreService.kt`: the root touch listener now feeds a
  `GestureDetector` (single-tap = open Match Details, double-tap = cycle size)
  while still handling drag directly off raw MOVE events. Drag suppresses the
  tap as before; the close button keeps its own listener.
- `cycleSize()` scales score/status/pill text and the content column's min
  width, persists the choice in SharedPreferences (`cricpro_overlay`), then
  re-clamps the window so a grown bubble can't end up off-screen.
- `applySize()` is also called on first show so a saved size is honoured.
- Layout `floating_score_bubble.xml`: content `maxWidth` raised 248dp → 340dp so
  the large size isn't clipped.
- `floating_score_settings_screen.dart`: added a tip describing drag / double-tap
  resize / tap-to-open.

Acceptance: resizable, still draggable, stays on-screen, close + tap-to-open
intact, size persists, no crash during score update (size + render both run on
the main handler). ✔

---

## 6. Score polling stability audit (Task 5)

Existing mechanisms verified sound (no change needed):
- Home uses a two-tier poll: cheap `/app/live-scores` overlay every tick, heavy
  membership refresh every 4th tick; both gated on a content fingerprint
  (`homeVisibleScoreKey`) so `setState` only fires when a visible value changed.
- `CricketMatch.mergeLiveScore` overlays only score/status fields, preserving
  stream/featured metadata.
- Hero carousel is keyed by match id, has no auto-slide, and `_preserveHeroOrder`
  prevents reorder on poll.
- Match Details keys tab content by tab and stops polling on terminal state.

Fix applied — list cards lacked stable identity:
- `home_match_cards.dart`: added `ValueKey('home-card-<id>')` to single-column
  cards, `ValueKey('home-compact-<id>')` to grid cells (and `super.key` on the
  compact card), and a row key in the grid.
- `matches_screen.dart`: added `ValueKey('matches-card-<id>')` to each card.

Without these, a full-list `setState` that changed order matched cards by
position and could recycle one card's element/scroll state onto a different
match (flicker / wrong-card animation). Keying binds state to match identity.

---

## 7. Visual formatting fixes (Task 6)

- **A. Match Details hero team codes** — `MDTeamScoreBlock` now uses
  `formatTeamCode` (NZW→NZ W, SLW→SL W, INDA→IND A, SLA→SL A). `_splitScore`
  made space-insensitive so a raw "NZW" score prefix is still stripped.
- **B. Match Details status** — hero status now runs through `shortMatchStatus`
  ("Sri Lanka Women need 150 runs" → "SL W need 150"); series-name fallback left
  untouched.
- **C. Commentary score** — `_isValidCommentaryScore` now also hides "0/0"
  (innings not begun), alongside the existing "0/N" artifact and >10 wickets
  guards, so no misleading score appears.
- **D. Matches live card** — removed the full-width red `scoreLine`. Per-team
  scores now render inside each team block (white, like the finished card), with
  formatted codes via the existing `teamCodeOf`. Only the short status note
  remains beneath.
- **E. Schedule screen** — verified already using `teamCodeOf` (AFG A not AFGA),
  `shortSeriesTitle`, and `softWrap:false`; no change needed.

---

## 8. Checks run

- `flutter analyze lib/` → **No issues found**.
- `node --check cricket-api/src/lib/onesignal.js` → OK (only changed backend JS file).
- `admin-panel` `tsc --noEmit` → clean (TypeScript files changed; node --check
  does not apply to TS).
- No release APK / appbundle built (per instruction).

---

## 9. Intentionally left unchanged

- Native overlay polling cadence/recovery (already correct; only hardened).
- Remote heavy backgrounds (not re-enabled).
- Ads (untouched).
- `app_devices` schema and device register/update endpoints (no new columns;
  OneSignal tags remain the preference source of truth).
- Existing broadcast/segment push paths (All / Android / iOS / subscription).
- Server-side per-category audience counts (out of scope; would need OneSignal
  query or schema change).

---

## 10. Device QA checklist

- [ ] Favourite = Afghanistan, a live non-AFG match running → hero shows the
      live match first, not tomorrow's AFG match.
- [ ] No live matches, AFG upcoming today → AFG floats up within upcoming.
- [ ] Hero carousel does not auto-slide or jump during score polling.
- [ ] Toggle "Live stream available" off → admin category push to live_stream is
      not received; re-enable → received.
- [ ] Set favourites, send admin `favorite` push (favorite_team:AFG) → only
      devices following AFG receive it.
- [ ] Deny notification permission → settings screen explains + Enable works, no
      crash.
- [ ] Start floating score, open another app → score updates without reopening.
- [ ] Disconnect/reconnect network → overlay resumes; match completes → shows
      final, stops polling.
- [ ] Double-tap bubble → cycles compact/normal/large; stays on-screen and
      draggable; tap opens Match Details; close works.
- [ ] Home / Matches live cards update score in place — no blink, reorder, or
      scroll reset.
- [ ] Match Details live score updates without tab reset; minimized bar updates
      without jump.
- [ ] Team codes read NZ W / SL W / IND A everywhere; commentary never shows 0/0.
