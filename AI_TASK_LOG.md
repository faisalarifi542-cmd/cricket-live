# AI Task Log

## Task: Home premium landscape refinement — final visual pass (2026-07-14)

Continued Fable 5's partial Home-only work without reverting unrelated changes.
Resolved the approved hero conflict in favour of the 1.34 landscape card and
current/latest innings only; historical innings remain intact in the model and
detail scorecards.

### Changed
- `lib/screens/home/widgets/home_hero.dart`: shared aspect diagnostics, compact
  current-innings labels, no historical hero row, 4–6px carousel peek, darker
  stadium treatment, restrained glow, compact spacing, CTA polish.
- `lib/screens/home/widgets/home_header.dart`: 40→36px logo and outlined bell.
- `lib/screens/home/widgets/home_match_cards.dart`: continuous card metrics,
  current innings only, fixed stable height, subtle depth/rings.
- `lib/screens/home/widgets/home_actions.dart`: two-row venue/date-action footer.
- `lib/screens/home/widgets/home_featured.dart`: restrained heading polish.
- `lib/screens/home/home_screen.dart`: preserved Fable's full-bleed hero and
  Home-only section spacing.
- `test/home_hero_overflow_test.dart`: replaced obsolete previous-innings
  expectation with current score/ordinal/history-preservation assertions.
- Added `test/home_hero_dimensions_test.dart`,
  `test/home_visual_evidence_test.dart`, and `HOME_VISUAL_EVIDENCE.md`.

### Verification
- Format clean.
- Scoped analyze: no errors/warnings; three existing test info notices.
- Overflow suite: 4/4 passed.
- Dimensions suite: 10/10 passed; a later runner invocation timed out without
  output due orphaned Windows Flutter test processes (documented in evidence).
- Visual evidence default mode: 12/12 passed; 12 gated PNGs generated using
  isolated capture processes because Windows kept multi-capture raster workers alive.

### Pending
- Physical-device comparison is still required for subjective darkness, glow,
  balance, and Android font rendering.

---

## Task: Premium Test score presentation — Home/Matches/Schedule (2026-06-29)

Inspect-first pass on the Test stacked-score visuals across all four surfaces.
All screens already route through the shared `TeamScoreView` + `ScorePreset`,
so the fixes were spacing/sizing + a Schedule layout fix — not a new component.

### Root cause — crowded Test rows (Home hero / live card / Matches)
The stacked-row preset used a tight `rowSpacing` (4) and line height (1.06) and
the separator dot had no breathing room, so the two innings rows read as one
block. The hero VS badge (52/60 wide) also ate column width, squeezing the
score.

### Root cause — TINY Schedule score (the biggest issue)
Schedule's `_CardTeam` placed the logo (50px) BESIDE the text inside each
`Expanded`, and the VS badge reserved 64px — so each score column was only
~60–68px wide and the per-row `FittedBox(scaleDown)` shrank the wide Test row
(`288/9d* · 94.0 ov`) down to ~9px. Home/Matches don't have this because they
put the logo ABOVE the score (full-width column).

### Changes
- **`lib/widgets/team_score_view.dart`** (shared): line height 1.06→1.10 /
  overs 1.05→1.08; Test `rowSpacing` hero 4→6, card 4→5, compact 3→4, details
  5→6 — real breathing space between innings rows. Separator dot gets
  `letterSpacing 1.6` for clean spacing WITHOUT changing the rendered string
  (tests/format unaffected). Overs stay white, score dominant — unchanged.
- **`lib/screens/schedule/widgets/schedule_cards.dart`**: `_CardTeam` rebuilt to
  the SAME logo-ABOVE, centred column as Home/Matches, so the score uses the
  FULL team-column width (the fix for the miniaturised score). Logo 50→44, VS
  footprint 64→46 (glow still overflows via `Clip.none`). Removed the now-dead
  `alignEnd` param. Score target 15→18 / overs 11→13 via the shared card preset.
- **`lib/screens/home/widgets/home_hero.dart`**: VS badge 52/60→46/54 (more room
  for the score columns); multi-innings height bonus 22→30 and Test
  `scoreBoxHeight` small 44→50 / normal 50→56 so the roomier rows breathe
  without the outer FittedBox shrinking them; added a 4–6px gap above the status
  pill (more separation from the score block).

### Typography (unchanged ranges, now with better spacing)
Hero Test 15–18 / overs 12–14 · card (Home live + Matches + Schedule) Test
18–22 / overs 13–15 · details 17–20 / 13–15 · compact 16–18 / 12.5–14. Score
weight w900, overs w700 white, cyan separator dot.

### Consistency
The SAME match now renders the same row structure (`438/10 · 114.5 ov` /
`288/9d* · 94.0 ov`, current-innings star, declared `d`, no `1st`/`2nd`) on Home
hero, Home live card, Matches card, Schedule card and Match Details — all via the
shared renderer + presets. T20/ODI single-innings score unchanged (large score +
white overs below; "Yet to bat" muted).

### Tests added/updated
- `test/team_score_view_test.dart`: NEW Schedule narrow-column test (96px) —
  shared card preset (score 18–22, overs 13–15), no overflow, correct row text;
  NEW cross-screen consistency test (hero/card/details render identical row
  strings, no `1st`/`2nd`). Existing hero-Test / white-ball / Matches tests still
  pass (separator letterSpacing kept the plain text identical).

### Commands run + results
- `flutter analyze lib test` → no errors (only pre-existing test infos/warnings).
- `flutter test` → **174/174 passed**.
- `npm test` (cricket-api) → **100/100 passed** (no backend change).

### Manual checks / remaining risks
- Schedule now uses logo-above so the Test score renders at the card preset size
  (~18) instead of ~9 — a major readability win and consistent with Home/Matches.
  This changes Schedule's team layout from logo-beside to logo-above (intended,
  per the "same visual language" requirement).
- The Home hero is height-bounded; on the tightest small-device live T20 the
  outer FittedBox may still scale the single score a little (unchanged from the
  accepted prior pass). Test hero now has more vertical room and breathes.
- Private hero/schedule composites aren't unit-tested directly; the shared score
  sub-widget, sizes, no-overflow and cross-screen consistency are covered. No
  on-device capture from this environment.

## Task: Flutter app support — heartbeat, events, notification prefs — Phase 4 (2026-06-29)

Final phase. Flutter app changes only where needed for the admin-automation
features. Verified: `flutter analyze` (clean) + `flutter test` → 172/172.

### Shipped
- **`lib/services/analytics_service.dart`**: realtime presence heartbeat — a
  45s timer POSTs `/analytics/heartbeat` ({device_id, session_id, app_version,
  platform}) while foregrounded; started on init + app-foreground, stopped on
  background, cancelled on dispose. Added convenience events `matchOpen`,
  `streamOpen` (→ `live_stream_open`), `notificationOpen`. (app_open,
  screen_view, match_open, live_stream_open were already wired in the
  app/match-details/live-player; verified.)
- **`lib/services/notification_settings_service.dart`**: defaults now follow the
  spec — `live_stream` ON (new-innings rides it), every other category opt-in
  (OFF). Added `applyConfigDefaults(...)` so `/app/config`
  `notifications.preferences.defaults` seeds categories the user hasn't
  explicitly toggled (user choice always wins; tracked via `_userSet`).
- **`lib/main.dart`**: `_loadAppConfig` parses `notifications.preferences.defaults`
  and calls `applyConfigDefaults`; the notification deep-link handler now records
  `notification_open` before navigating.

### Commands run + results
- `flutter analyze` (changed files) → No issues.
- `flutter test` → 172/172 passed.

### Final acceptance status
- Sync live + today/tomorrow upcoming from the Live Stream page ✓ (Phase 1 API +
  Phase 2 UI).
- Add stream from synced match with locked, auto-filled metadata ✓.
- Stream edit form always prefills (root-cause reset effect) ✓.
- Publish notification fires once on Draft→Published; re-saving does not resend
  (notification_log dedupe) ✓.
- New-innings notification once per innings, only for streamed matches ✓.
- Stream notifications ON by default; others user-controlled ✓.
- Analytics realtime users from real Redis presence; empty state when none ✓.
- Cricbuzz player sync upserts without duplicates ✓.
- Team/player edit forms prefilled; Editor role limited + enforced server-side ✓.
- Unused admin pages grouped under System & Tools ✓.
- Tests/lint/build pass across backend (100), admin (build), Flutter (172).

### Honest scope notes / not done
- Could not exercise live MySQL/Redis/Cricbuzz here; backend verified via
  `node --check` + full suites (as prior entries). Player sync is a bounded
  synchronous scrape (squads of live/upcoming/recent) with optional capped
  enrichment — a dedicated background job + progress stream remains a future
  enhancement. No `user_notification_preferences` table added: the existing
  OneSignal per-device tag system already segments delivery; defaults are now
  config-driven.

## Task: Backend automation — innings notify, presence, prefs, player sync, RBAC — Phase 3 (2026-06-29)

Backend + matching admin frontend. Verified: `node --check` on all changed
files, `npm test` (cricket-api) → 100/100, admin `tsc --noEmit` clean +
`next build` success.

### Shipped (backend)
- New-innings notifications — `src/lib/innings-notifier.js` (NEW) + hook in
  `src/workers/handlers/live-score.handler.js`. On `current_innings` advance,
  fires ONE "New Innings Started" push, ONLY for matches with a published/active
  stream, deduped once per innings via `notification_log`
  (`new_innings:<matchId>:<inningsNumber>`), targeted to the `live_stream`
  category tag. Skips cold cache / finished matches; never throws into polling.
- Realtime presence — `src/lib/presence.js` (NEW): Redis sorted-set 120s window
  of anonymous device/session ids, auto-trimmed. `POST /analytics/heartbeat`
  (public) + `GET /admin/analytics/realtime`. No PII.
- Notification preference defaults — `public-app-state.js` `/app/config`
  `notifications.preferences`: `live_stream` ON, new-innings ON, all other
  categories opt-in (OFF). No new table (OneSignal tag system already segments).
- Cricbuzz player sync — `POST /admin/players/sync-from-cricbuzz` in
  `extra.routes.js`: bounded squad scrape → dedupe + upsert by Cricbuzz id
  (never overwrites admin photo; sets `last_synced_at`), optional `?enrich=1`.
  `players.last_synced_at` + `short_name` columns added in `migrate.js`.
- RBAC — `rbac.js` Editor gains `streams.write/test`, `teams.write`,
  `players.write`; still denied settings/users/roles/analytics/system. Enforced
  server-side.

### Shipped (admin frontend)
- `lib/api.ts`: `analyticsApi.realtime`, `playersApi.syncFromCricbuzz`.
- `app/analytics/page.tsx`: "Active users now" card (real presence, 30s poll;
  "No live users yet" when empty).
- `app/players/page.tsx`: "Sync Players from Cricbuzz" button.

### Commands run + results
- `node --check` (9 backend files) → OK.
- `npm test` (cricket-api) → 100/100.
- admin `npm run lint` (tsc) → clean; `npm run build` → success.

## Task: Home Hero premium polish — composition, alignment, sizing (2026-06-29)

Hero-only pass. Inspect-first: traced the hero carousel → card → team block →
shared score widget → responsive metrics, then fixed the proven visual issues
for BOTH Test and T20/ODI without redesigning.

### Root cause — batting/bowling columns vertically misaligned
`_HeroTeamBlock` wrapped each side's WHOLE column in its own
`FittedBox(scaleDown)` and the teams `Row` used `CrossAxisAlignment.center`.
Because the two sides have different content heights (a scored side vs a
"Yet to bat" side, or 2 Test rows vs 1), each FittedBox scaled by a DIFFERENT
factor → different rendered logo sizes, and centre-alignment placed the shorter
column lower. So the logos/codes/scores never shared a baseline.

### Root cause — hero too tall / logos too big
Logos were large (66/80/90) and the multi-innings height bonus was +46; the
whole block was then scaled to fit, making the hero feel heavy.

### Fixes (`lib/screens/home/widgets/home_hero.dart`)
- **Identical-scaling alignment**: both team columns now share the SAME fixed
  logo size (`effLogo`, computed once at card level) AND a SHARED fixed
  `scoreBoxHeight`, so each block has an identical intrinsic size and the
  per-side `FittedBox` scales them by the SAME factor — logos stay equal and the
  codes/scores land on the same baseline. The score sits in a fixed-height,
  top-anchored box so a "Yet to bat" side reserves the same height as a scoring
  side (never higher/lower). VS badge stays centred between them.
- **Smaller logos** (~12–15%): 66→56 (small), 80→66 (normal), 90→76 (wide);
  Test trims a further ×0.86. Premium rings/glow unchanged.
- **Less tall**: base heights 286→282 / 312→304 / 348→334; multi-innings bonus
  46→22 (rows are compact now); tightened title→date, venue→CTA gaps and the
  logo→code gap (8→6).
- **Compact Test hero**: `heroMultiInnings` preset retuned to score 15–18 /
  overs 12–14 with a tighter row gap (4) — readable but not stretched.
- **Balanced T20/ODI hero**: single score uses `heroLimitedOvers` 26–34 (capped,
  no longer oversized) with white overs 13–15 directly below; "Yet to bat" stays
  the muted secondary placeholder, top-anchored to align with the score block.

### Data consistency
No score-format/declared/star/Yet-to-bat logic changed — the hero still renders
through the shared `TeamScoreView` + presets, identical to Home/Matches cards.

### Tests added/updated
- `test/home_behavior_test.dart`: NEW T20/ODI hero test — single score strong
  (26–34), overs readable (13–15) and smaller than the score, fits a short hero
  slot at 360dp with no overflow. Existing Test-hero 360dp + Yet-to-bat tests
  still green.
- `test/team_score_view_test.dart`: hero-Test preset assertion updated to the
  new compact 15–18 / 12–14 range (overs still white, not cyan).

### Commands run + results
- `flutter analyze lib test` → no errors (only pre-existing test infos/warnings).
- `flutter test` → **172/172 passed**.
- `npm test` (cricket-api) → **100/100 passed** (no backend change).

### Manual checks / remaining risks
- The private `_HeroMatchCard`/`_HeroTeamBlock` (a `part of` home_screen) can't
  be unit-tested directly; alignment is guaranteed structurally (equal logo +
  equal score-box height + shared scale) and the score sub-widget + no-overflow
  are covered by widget tests. No on-device capture from this environment.
- On the tightest small-device live T20 (lots of chrome: title, date, status
  pill, venue, CTA) the shared FittedBox may still scale the score block down a
  little; both sides scale equally so alignment holds and overs stay readable.

## Task: Admin frontend — Sync UI, edit-prefill fix, simplified stream form — Phase 2 (2026-06-29)

Next.js admin panel. Built against Phase 1's backend. Verified with
`tsc --noEmit` (clean) + `next build` (all routes compiled).

### Root cause fixed — blank edit form
`StreamForm` stayed mounted (only `open` toggled) and seeded state via a
`useState(() => …)` initializer that runs ONCE. Reopening it for a different
stream kept stale/empty values → the reported "edit form is blank". Fixed with
a `useEffect([open, initial, defaultMatchId])` that re-seeds the form every time
it opens. Players/Teams/AppSettings/Notification/Ads dialogs already reset via
their own effects (audited — no bug there).

### Shipped
- **`components/forms/StreamForm.tsx`** (rewrite): open-reset effect; simplified
  primary layout (match, stream title, URL, type [HLS/M3U8·Embed·External·Other],
  quality, Draft/Published status, priority, language, premium/rewarded,
  send-notification-on-publish [default ON], internal note); advanced
  collapsible for scheduling/headers/DRM/clearkey; read-only locked Match card
  when added from a synced match; toasts the publish-notification result.
- **`components/streams/SyncMatchesModal.tsx`** (NEW): calls
  `GET /admin/streams/sync?tz=<browser zone>`; live-first list with
  Published / Stream Added / No-stream badges; Add/Edit/View actions; counts +
  last-synced time + provider; empty/error/loading states; Re-sync.
- **`app/streams/page.tsx`**: "Sync Live & Upcoming Matches" button; Add-from-
  synced opens the locked, pre-filled create form; Edit now fetches the FULL
  record by id first so every field prefills.
- **`app/streams/[id]/page.tsx`**: publish-notification status card + hint.
- **`lib/api.ts`**: `streamsApi.sync` + sync/notification types; create/update
  return `notification`; rows expose `published` + `publish_notification`.
- **`lib/validators.ts`**: `notify_on_publish` (default true) + `send_push_now`
  added to `streamSchema` (were silently stripped before).
- **`lib/constants.ts`** + sidebar: new System & Tools nav group; moved
  App Assets, Cache, Data Control, API Security, Health & Logs into it; Data
  Control gated on `dataControl.view`. Sidebar filters by permission so Editors
  never see restricted pages.

### Commands run + results
- `npm run lint` (tsc --noEmit) → clean.
- `npm run build` (next build) → success, all routes compiled.

## Task: Score typography presets + white overs + declared `d` stability (2026-06-29)

Inspect-first against the LIVE API. Centralized score typography into a preset
system, made overs readable/white, capped the white-ball hero, enlarged Matches
scores, fixed the Matches-card title spacing, and fixed the declared-`d` flicker
at its data source.

### Root cause — `d` flickers on Home / missing on Matches (proven from live API)
Only `/app/live-scores` carries `declared:true`; `/matches/live` and `/app/home`
emit `288/9` with NO declared flag (captured both payloads). So the Matches
screen (which uses `/matches/live`) never showed the `d`, and the Home hero
flickered as the declared (live-scores poll) and non-declared (matches/live
overlay) feeds alternated each tick.

### Root cause — small Matches scores / oversized white-ball hero
Every call site hard-coded its own `mainSize`/`oversSize`; the Matches Test card
passed 16 (tiny) while the white-ball hero passed the full device size (≈40–46 →
the oversized `112/6`). Overs were cyan (low contrast on the blue stadium) and a
single FittedBox scaled score+overs together so overs shrank to unreadable.

### Fixes
- **`lib/models/cricket_match.dart`** — `_deriveDeclared` derives the `d` from
  signals EVERY feed carries (corrected innings order + `battingTeamId`): a
  non-all-out CLOSED innings (an earlier innings of a team, or a team's last
  innings while the OTHER side bats) reads as declared on every screen and is
  stable across polls. Robust against the lying positional ordinal (order
  position + batting id, not raw ordinals). Limited-overs never touched.
  `_stickyDeclared` + `mergeLiveScore` keep the `d` if a degraded tick drops it
  on an unchanged innings. Added `InningsScore.copyWith`.
- **`lib/utils/score_presentation.dart`** — added `ScoreDisplayMode.compactCard`
  + `ScoreLayoutFamily.compact`.
- **`lib/widgets/team_score_view.dart`** — NEW `ScorePreset` + `scorePresetFor`
  central typography system (hero/card/details/compact/bar × Test/white-ball),
  each defining score & overs min/max, weights, line height and row spacing. The
  renderer clamps the call-site target into the preset bounds (white-ball hero
  can't balloon, a Matches Test score can't shrink). Overs render WHITE
  (`Colors.white .92` dark / `c.text` light); only the separator dot stays cyan.
  Tabular figures everywhere for stable numeric alignment.
- **Call sites** — Matches card score target raised (16→22) + VS centerpiece
  footprint reduced (124→100) to give team columns room; Home grid cell routed
  to `compactCard`; hero multipliers retuned to land in-band. Home poster,
  Schedule, Match Details and the bar inherit the presets.
- **`lib/screens/matches/widgets/matches_cards.dart`** — card content padding
  `7→14` top / `7→10` bottom and the header→teams gap raised to 12 (title no
  longer crammed against the top glow/LIVE pill; venue not hugging the bottom).

### Typography presets added (score / overs)
- Home hero white-ball 26–34 / 13–15 · Home hero Test 17–20 / 13–15
- Match list white-ball 22–26 / 13–15 · Match list Test 18–22 / 13–15
- Match details 24–28 (Test 17–20) / 13–15 · Compact grid 16–20 (Test 16–18) /
  12.5–14 · Compact bar 13–18 / 12–14

### Screens affected
Home hero + live/upcoming/finished cards, Home grid cell, Matches screen cards,
Schedule cards, Match Details header, minimized score bar — all via the shared
renderer.

### Tests added/updated
- **`test/declared_marker_test.dart`** (NEW, 5): `/matches/live`-shape (no flag)
  derives NZ `288/9d` while batting ENG `103/4` stays open and all-out `438/10`
  has no `d`; T20 `154/8` never gains a spurious `d`; explicit flag wins;
  `mergeLiveScore` keeps `d` on an unchanged innings (no flicker) but a new score
  does not inherit a stale `d`.
- **`test/team_score_view_test.dart`**: hero-Test hierarchy asserts score 17–20,
  overs 13–15, overs WHITE (luminance > .85) not cyan; white-ball hero score
  capped ≤34; Matches Test card score ≥18.
- Existing ordering/score tests unchanged and still green (derivation is not
  fooled by the lying positional ordinal they guard).

### Commands run + results
- `curl /matches/live`, `/app/home`, `/app/live-scores?ids=129574` — proved only
  live-scores carries `declared`.
- `flutter analyze lib test` → only pre-existing test infos/warnings, no errors.
- `flutter test` → **171/171 passed**.
- Backend normalization NOT touched (client-side fix), so backend tests not
  required this pass.

### Remaining risks / not done
- For a FINISHED match the last-innings declared derivation is intentionally
  skipped (so a successful run-chase like `375/6` never gets a spurious `d`); a
  declared final innings on the recent feed relies on the explicit flag.
- Matches Test card columns are still narrower than the hero; the score is now
  much larger but inline overs can still scale slightly on the tightest 360dp
  two-innings layout (FittedBox safety) — readable, never below the preset floor.
- Matches list cards are private (`part of`), not unit-tested directly; the
  score area is covered via `TeamScoreView` at narrow widths. No on-device
  capture from this environment.

## Task: Admin Live-Stream Sync + idempotent publish notifications — Phase 1 (2026-06-29)

Backend-only, fully additive slice of the larger admin-automation epic. Does
NOT touch any existing Flutter app endpoint. Verified with `node --check` +
the full backend suite (100/100).

### What shipped
- **`cricket-api/src/lib/notification-dedupe.js`** (NEW): one idempotent gate
  for automated pushes. `claimNotificationEvent` does an `INSERT IGNORE` against
  a UNIQUE `dedupe_key`; only the winner (affectedRows===1) sends. Survives
  repeated admin saves, duplicate poll ticks and backend restarts. Keys:
  `stream_published:<streamId>`, `new_innings:<matchId>:<inningsNumber>`.
  Helpers: `markNotificationLog`, `wasNotificationSent`, `getStreamNotificationStatus`.
- **`cricket-api/src/db/migrate.js`**: added the `notification_log` table
  (idempotent `CREATE TABLE IF NOT EXISTS` in `applyCompatibilityMigrations`,
  UNIQUE `dedupe_key`, indexes on match+event and created_at).
- **`cricket-api/src/admin/routes/streams.routes.js`**:
  - `GET /admin/streams/sync?tz=` — loads LIVE + UPCOMING(today/tomorrow,
    timezone-safe via luxon), dedupes by match id (live wins), drops completed,
    joins existing stream records → per-match `stream_status_label`
    (`Published` / `Stream Added` / `Add Stream`) + full auto-fill metadata
    (teams, shorts, logos, series, venue, start, format, status). `streams.view`
    so Editors can run it. Returns counts + provider + window + errors.
  - Publish notification is now **transition-based + deduped**: fires only on a
    real Draft/Inactive→Published change (or explicit `send_push_now` force),
    once per stream, via `notification_log`. Body is premium and built from real
    match metadata ("X vs Y is now live on CricPro. Tap to watch."), targeted to
    the `live_stream` category tag. `notify_on_publish` opt-in defaults ON.
  - Create/Update responses now include a `notification` status
    (`sent`/`failed`/`skipped`/`already_sent`). `GET /:id` exposes `published`
    + `publish_notification` (status/error/sent_at) for the admin UI.

### Commands run + results
- `node --check` streams.routes.js / notification-dedupe.js / migrate.js → OK.
- `npm test` (cricket-api) → **100/100 passed**.

### Not done yet (next phases — see request items 1–14)
- Frontend (Next.js admin): wire the Sync button + result table, edit-form
  prefill across all forms, simplified Live Stream form, surface notification
  status, hide unused pages, UX polish.
- Backend: new-innings notification watcher (item 5), user notification
  preferences table + `/app/config` defaults (item 6), analytics heartbeat
  presence endpoint + Redis realtime count (item 7), Cricbuzz player sync
  (item 8), Editor `streams.write`/sync permissions (item 10).
- Could not exercise the dedupe UNIQUE-index path here (no live MySQL); design
  is fail-closed (a log/DB error degrades to "do not send" so no duplicate
  blast). Verified via parse-check + full suite, as prior entries did.


## Task: Premium stacked-Test overs + BAN/ZIM "Day N" upcoming leak (2026-06-29)

Inspect-first against the LIVE API. Proved the BAN vs ZIM upcoming bug was a
NEW path the prior id-exclusion couldn't catch, and made the stacked Test score
truly premium (readable overs) through the SHARED renderer.

### Root cause — BAN vs ZIM still shows as Upcoming (proven from live API)
Match id `158016` (ZIM vs BAN, One-off Test) is **not** in `/matches/live`,
`/matches/upcoming` (empty) or `/matches/recent`. It appears ONLY in
`/schedule/upcoming` as `"One-off Test, Day 5"` (a continuation DAY of an
in-progress Test; on the user's Jun-29 screenshot it was "Day 2"). The prior
fix excluded ids found in the live/recent feeds — but the provider does NOT
surface this Test as live (it's between days/stumps), so there is no live copy
to exclude by id, and `classifyMatch` (future start + upcoming + no score)
treats the "Day N" entry as a genuine fixture. So it leaked into Home Upcoming.

### Data classification fix
- **`lib/utils/match_classification.dart`** — added `isMultiDayContinuationEntry`
  (regex `\bday\s*(?:[2-9]|1[0-9])\b` on `matchDesc`): a `Day N` (N>=2) entry is
  a later day of an already-started multi-day match. `isUpcomingMatch` now also
  excludes such entries. `Day 1`, `Day/Night`, and no-day descriptions stay
  upcoming.
- **`lib/repositories/cricket_repository.dart`** — `upcomingMatchesMerged.addAll`
  drops continuation-day entries (the single chokepoint feeding BOTH Home and
  Matches Upcoming). Imported `match_classification`.

### Premium stacked Test score (overs readability — the #1 visible issue)
The overs looked tiny because each stacked row is wrapped in
`FittedBox(scaleDown)`: an oversized score (~21–26) made the inline row too wide
for a ~120dp hero column, so the WHOLE row (score+overs) was scaled down,
dragging overs well below their nominal size.
- **`lib/widgets/team_score_view.dart`** — `_stackedInlineRows` now clamps the
  premium hierarchy CENTRALLY for every screen: score (runs/wickets) 15–18,
  overs 12–14, overs always smaller than the score but never tiny. Added
  tabular figures for stable numeric alignment and a touch more vertical air
  between innings rows (`gap + 3`). Separator kept ` · ` (deliberate, premium).
- **`lib/screens/home/widgets/home_hero.dart`** — Test multipliers retuned so
  the base sizes land in-band (score `*0.52`, overs `*0.41`) and the logo
  shrinks a hair more (`*0.82`) to give the row width — so the row fits without
  FittedBox shrinking the overs. Single-innings T20/ODI hero unchanged.
All other call sites (Home grid/poster, Matches, Schedule, Match Details) feed
the same widget, so the clamp makes the stacked format identical app-wide.

### Files changed
- `lib/utils/match_classification.dart`
- `lib/repositories/cricket_repository.dart`
- `lib/widgets/team_score_view.dart`
- `lib/screens/home/widgets/home_hero.dart`
- `test/upcoming_merge_test.dart`, `test/team_score_view_test.dart` (tests)

### Tests added/updated
- `test/upcoming_merge_test.dart`: a `"One-off Test, Day 5"` schedule entry with
  NO live copy is excluded from merged Upcoming while a `Day 1` fixture + a plain
  T20I remain; unit tests for `isMultiDayContinuationEntry` / `isUpcomingMatch`.
- `test/team_score_view_test.dart`: new "overs smaller than score, score 15–18,
  overs 12–14" hierarchy test (clamps an oversized request down).
- Existing stacked-format + 360dp tests unchanged and still green.

### Commands run + results
- `curl` `/matches/{live,upcoming,recent}` + `/schedule/upcoming` — PROVED
  158016 is only a schedule "Day 5" entry (not in live/upcoming/recent).
- `flutter analyze lib test` → only pre-existing test infos/warnings, no errors.
- `flutter test` → **164/164 passed**.
- `npm test` (cricket-api) → **100/100 passed**.
- `node --check` schedule.js / normalizer.js → OK.

### Remaining risks / not done
- The Schedule *calendar* screen (`scheduleByDay`) still lists "Day N" entries
  as day-by-day fixtures — intentional for a calendar; not changed (scope was
  Home/Matches Upcoming).
- If the provider later DOES emit a live copy of 158016, dedupe + the existing
  id-exclusion already keep the live version; the new continuation filter is the
  belt-and-braces for the no-live-copy case.
- No on-device screenshot from this environment; verified via live API payloads,
  analyzer, full Flutter + backend suites, and the new widget/size tests.

## Task: Home Upcoming reconciliation + stacked Test score format (2026-06-28)

Inspect-first against the live API. Two proven fixes + the premium stacked
Test-score format the user asked for, applied through the SHARED renderer so it
is consistent app-wide.

### Root cause — a started/live match showing as "Upcoming"
The Cricbuzz schedule feed lists each remaining DAY of a live multi-day Test as
a separate FUTURE-dated entry under the SAME match id (proved: `/schedule/upcoming`
returns ZIM vs BAN id `158016` as "Day 2/3/4/5", start Jun 29–Jul 2, status
`upcoming`, no score). `CricketRepository.upcomingMatchesMerged` added schedule
entries without checking the live/recent feeds, and neither the model flags nor
`classifyMatch` can tell a future "Day 2" apart from a real fixture (future start
+ upcoming + no score). So it leaked into Home Upcoming.

### Root cause — "More Upcoming Matches" CTA in the Live tab
`_buildSections` rendered `_UpcomingMatchesSection` on Live/Finished tabs and
passed `onOpenSchedule`, which drives the section's internal `_MoreUpcomingCta`.
So the prominent upcoming CTA showed on the Live tab.

### Score format decision
Multi-innings (Test) now renders STACKED per-innings rows with inline overs and
NO `1st`/`2nd` prefix — readable on small devices and identical on every screen:
```
438/10 · 114.5 ov
288/9d* · 94.0 ov      (current starred, declared shows d, order chronological)
```
Single innings (T20/ODI) keeps the large score + overs line; the minimized score
bar keeps the one-line combined form.

### Files changed
- **`lib/repositories/cricket_repository.dart`** — `upcomingMatchesMerged` now
  collects live (tab 0) + recent (tab 2) ids first and EXCLUDES them from the
  merged upcoming list (live/recent priority). Debug log adds
  `excludedLiveRecent=N`.
- **`lib/widgets/team_score_view.dart`** — new `_stackedInlineRows` for Test
  multi-innings (hero/card/details); bar keeps `_combinedLine`. Overs inline per
  row (`· 114.5 ov`), current starred, earlier dimmed.
- **`lib/screens/home/home_screen.dart`** — `_UpcomingMatchesSection` gets
  `onOpenSchedule` only when Upcoming is the ACTIVE content (`showUpcomingInstead`),
  so the "More Upcoming Matches" CTA never shows on a populated Live/Finished tab.

### Data classification fixes
Reused the existing single-rule `classifyMatch` (+ `dedupeMatchesById`,
`isUpcomingMatch`) — a scored match is live not upcoming; dedupe keeps live over
an upcoming duplicate. The new repository exclusion closes the cross-feed gap
those helpers couldn't (the live copy was never in the upcoming merge list).

### Tests added/updated
- **`test/upcoming_merge_test.dart`** (NEW, 3): a LIVE id is excluded from merged
  Upcoming while a genuine future fixture remains (fake-service repository test);
  scored match → live not upcoming; dedupe keeps the live copy.
- **`test/team_score_view_test.dart`**: updated 4 multi-innings tests to the
  stacked inline-overs format (`362/10 · 87.1 ov`, current `90/3* · 20.1 ov`,
  no `1st`/`2nd`).
- **`test/home_behavior_test.dart`**: Test 5 now asserts the stacked rows at
  360dp (`438/10 · 114.5 ov`, `234/8* · 83.0 ov`).
- `score_presentation_test.dart` unchanged (it tests the pure `combinedScore`/
  `oversLine` helpers, still used by the bar + change-detection).

### Commands run + results
- `curl` `/matches/{live,upcoming,recent}` + `/schedule/upcoming` — proved id
  `158016` repeats as future "Day N" upcoming entries.
- `flutter analyze lib` → No issues.
- `flutter test` → **160/160 passed**.
- `npm test` → **100/100 passed**.
- `node --check` schedule.js / normalizer.js / index.js / client.js → OK.

### Remaining risks / not done
- The merged-upcoming exclusion needs the live/recent feeds reachable; if both
  fail transiently a started match could momentarily reappear as upcoming (the
  per-match `classifyMatch` still demotes it once it has a score or ages out).
- Per-tab purity: the Live tab still shows an Upcoming *teaser row* (header
  "See All") — only the prominent CTA was removed; full removal of the teaser
  would be a larger layout change.
- Ireland blank-logo polish and broader header/token unification not in this
  pass.
- Verified via live API + analyzer + full suites + fake-service unit test; no
  on-device capture from this environment.

## Task: Home screen quality/stability pass — inspect-first, prove, lock with tests (2026-06-28)

Audited the full Home data/poll/render lifecycle. The polling architecture was
already well-engineered, so the responsible action was to VERIFY it, extract the
stability-critical logic into pure testable units, and lock the behaviour with
regression tests — NOT to rewrite working code.

### Home loading flow (as found)
- `home_screen.dart` owns loading + polling. Initial: `_loadFeed` (`/app/home`)
  + `_resolveHero` (overlays `/matches/live` on the admin hero) + `_loadTabMatches`
  (`/matches/live|recent|upcoming`) + `_loadUpcomingMerged`.
- Polling: a single `_pollTimer` → `_silentPoll`. Heavy membership refresh only
  every Nth tick; cheap `/app/live-scores` overlay every tick.
- Hero ← `/app/home` topFeatured overlaid by `/matches/live`. Live list ←
  `/matches/live`. Hero fast-updates via `/app/live-scores` + `mergeLiveScore`.

### Verified GOOD (no change needed)
- Poll never shows a full-screen loader: hero `FutureBuilder` treats
  `connectionState==waiting` as loading ONLY when `snapshot.data` is empty, and
  Flutter's `FutureBuilder` retains prior data (`inState`) across a
  `Future.value(...)` swap → no skeleton flash. `_HomeMatchList` renders from the
  cached `data` (`data ?? snapshot.data`), not the future alone.
- `setState` is gated by content-key change-detection (`homeVisibleScoreKey`) on
  BOTH list and hero — no notify when nothing visible changed.
- `PageController` is created ONCE (lazy `??=`), never in `build`.
- Carousel keeps the centred match by id (`_reseatForItems` + `_currentId`); a
  silent poll never reorders (`_preserveHeroOrder`).
- Scroll offset restored after every applied poll (`_restoreScroll`).
- `mergeLiveScore` updates only score/status/innings + preserves logos/venue/
  series/title/streams.

### Changes
- **`lib/screens/home/home_hero_order.dart`** (NEW): extracted the
  carousel-stability core into a pure `preserveHeroOrder(prev, resolved)` (+
  `sameOrder`) so it is unit-testable.
- **`lib/screens/home/home_screen.dart`**: `_preserveHeroOrder` now delegates to
  the pure function (behaviour identical; added import). No polling/rebuild
  logic changed.

### Tests added (`test/home_behavior_test.dart`, 8)
- Test 1 — `preserveHeroOrder`: same id-set keeps existing order (carousel never
  jumps on a re-prioritised poll); membership change adopts new order; null/empty.
- Test 3 — `homeVisibleScoreKey`: identical score/status → identical key (poll
  does NOT notify); a moved score → key changes.
- Test 4 — `mergeLiveScore`: score/status update; series/title/venue/logo
  preserved; merged innings stay chronological (`438/10 & 224/8`).
- Test 5 — Test multi-innings hero score renders at a compact 360dp width with
  no overflow; shows `438/10 & 234/8*` + `114.5 ov • 83.0 ov`.
- Test 6 — "Yet to bat" is muted, size-capped (≤14.5, not the big score), and
  shows no overs line.

### Commands run + results
- `flutter analyze lib` → No issues.
- `flutter test` → **157/157 passed** (was 149).
- `npm test` → **100/100 passed**.
- `node --check` schedule.js / normalizer.js / index.js / client.js → OK.

### Remaining risks / not done
- Full end-to-end carousel-during-live-poll behaviour isn't exercised by a
  widget+timer integration test (needs a fake repository + fake async timers);
  the stability INVARIANTS it relies on are now unit-tested, and the lifecycle
  was verified by inspection. No on-device capture from this environment.
- Larger design-consistency items (unified header language, logo-fallback art
  polish, Home live-list priority dedupe/rename) remain for a dedicated pass;
  the existing hero ordering already buckets Live → Upcoming → Finished.

## Task: Home-hero score flips after poll — /app/live-scores reversed innings (2026-06-28)

Inspect-first. Reproduced the exact regression: Home hero correct on load, then
flips to `222/7 & 438/10*` after a refresh tick, while Schedule stays correct.

### Why correct first, then wrong (root cause, proven with live API)
- Home loads heroes from `/app/home` + `/matches/live` (both return innings in
  CHRONOLOGICAL order with a correct `innings_number`, via `extractHomeInnings`'
  keyed `inngsN` path) → renders correctly.
- Every poll tick `_overlayFastLiveScores` overlays `/app/live-scores` via
  `CricketMatch.mergeLiveScore`. That endpoint is built by `projectLiveScore` →
  `normalizeMatchDetail`, which reads Cricbuzz `inningsScoreList`. For a live
  Test that list is **CURRENT-innings-FIRST**, and the normalizer stamped a
  **positional** `innings_number` (idx). Real captured payload:
  `team1.innings = [224/8 overs 81.1 #1, 438/10 overs 114.5 #2]` — the live
  innings numbered #1. Flutter's `_orderInnings` trusted that ordinal over the
  closed/open reality → reversed render + star on the completed innings.
- Schedule was correct because it merges `/matches/live` (keyed path), not the
  fast `/app/live-scores` overlay.

### Fixes
- **`lib/models/cricket_match.dart` — `_orderInnings`**: PRIMARY sort key is now
  the physical invariant *a CLOSED innings (all out / declared) precedes an
  in-progress one* for the same team; the provider ordinal is only a tiebreaker
  among same-state innings. A bogus positional ordinal can no longer reverse the
  rendered score, and `currentScoredIndexForTeam` (last scored) then stars the
  true OPEN innings.
- **`cricket-api/src/providers/cricbuzz/normalizer.js` — `normalizeMatchDetail`**:
  capture the REAL `inningsId` per innings and sort each team's `inngs` by it,
  so `/match/:id` and `/app/live-scores` emit chronological order with the true
  ordinal (not a positional index). `normalizeTeamFull` already prefers
  `inningsId`, so it now emits the correct number.
- Schedule polish: live status strip recoloured to **dark glass + subtle cyan**
  (red reserved for the LIVE pill only); live match time panel labelled
  **"Started"** so a multi-day match's start date doesn't read as the selected
  schedule date.

### Tests added
- Flutter `test/score_presentation_test.dart`: "a POSITIONAL ordinal that lies
  cannot reverse the order" — exact `/app/live-scores` values (224/8 #1, 438/10
  #2) → renders `438/10 & 224/8`, star on the open 224/8.
- Backend `cricket-api/.../detail-innings-order.test.js` (3): `normalizeMatchDetail`
  with a current-first `inningsScoreList` emits NZ `[438(#1), 222(#3)]`; the live
  innings is not numbered #1; ENG single innings intact.

### Commands run + results
- `curl /matches/live`, `/app/live-scores?ids=129574`, `/app/home` — captured
  the reversed-positional live-scores payload (the proof).
- `flutter analyze lib` → No issues.
- `flutter test` → **149/149 passed**.
- `npm test` → **100/100 passed**.
- `node --check` normalizer.js / app.js / schedule.js → OK.

### Remaining risks / not done
- If a team is bowled out in BOTH innings while the match is still live (rare 4th-
  innings case) and an OLD backend still sends a reversed positional ordinal,
  Flutter has no open/closed signal to disambiguate — the backend `inningsId`
  fix covers it once deployed (and `/app/home`/`/matches/live` are already
  correct).
- Broader design-consistency items (unified header language, logo-fallback
  polish, Home live-list ordering) remain for a dedicated pass.
- Verified via live API + analyzer + full suites + unit tests; no on-device
  screenshot from this environment.

## Task: Schedule opens-today + Home-hero score order (Flutter-robust) (2026-06-28)

Inspect-first pass against the LIVE API. Confirmed two root causes from real
payloads, then fixed them ROBUSTLY on the Flutter side (so they hold even with
the undeployed/older backend and stale caches).

### Root cause — Schedule opened on Jun 25
`scheduleByDay` merges live+recent+upcoming, but the screen's
`_regroupByLocalDate` bucketed matches by their raw start date and then sorted
ascending with `selectedDay = 0`. The live NZ vs ENG Test STARTED Jun 25, so a
Jun 25 bucket was created and selected first. The date strip was derived from
match data instead of "today".

### Root cause — Home hero `215/7 & 438/10*` (reversed + wrong star)
Order depended entirely on backend array order + an ordinal the running backend
didn't always send; the widget then starred the last array item. A reversed
`score.team1` (live innings first) with no/blank ordinal → reversed display and
the `*` on the completed innings. (Live API currently DOES send `innings_number`
and is correctly ordered — proof below — so the reversal was a stale/older
payload; the fix makes it impossible regardless.)

### Flutter changes
- **`lib/models/cricket_match.dart`**
  - `InningsScore.isClosed` (all out / declared).
  - `_orderInnings`: when no usable provider ordinal, a CLOSED innings sorts
    BEFORE an in-progress one (you can't start the 2nd until the 1st closes).
    Deterministically repairs reversed feeds/caches → correct order, and the
    existing "last scored = current" star then lands on the true live innings.
  - `_inningsFromCache` now re-applies `_orderInnings`, so a stale reversed
    cache cannot resurrect the bug.
- **`lib/screens/schedule/schedule_strip.dart`** (NEW, pure/testable):
  `buildScheduleStrip` = FIXED 14-day window from device-local TODAY,
  independent of payload; live matches (incl. multi-day Tests) bucket under
  TODAY via `effectiveScheduleDate`.
- **`lib/screens/schedule/schedule_screen.dart`**: `_regroupByLocalDate`
  delegates to `buildScheduleStrip`; default selected day = today; loading/
  empty/error now driven by the snapshot (strip is never empty). Removed the
  old payload-derived day list + `_localDayLabel`/`_wk`/`_mo`.
- **`lib/screens/schedule/widgets/schedule_cards.dart`**: live/finished schedule
  cards now render the centralized clean score (`438/10 & 215/7*`) under each
  team + a status/result strip (`Day 4 · 2nd Session · NZ lead…`); a side yet to
  bat reads muted. Upcoming keeps the time/venue panel.
- **`lib/widgets/team_score_view.dart`**: "Yet to bat" placeholder is now muted
  + size-capped (≤14.5) so it never looks like a big white score.

### Tests added/updated
- **`test/schedule_strip_test.dart`** (NEW): strip opens on today; upcoming
  buckets by local date; **live multi-day Test (started Jun 25) shows under
  Jun 28**; IRE-live + MLC-upcoming both land on Jun 28.
- **`test/score_presentation_test.dart`**: real `/app/home` shape
  (`score.team1` + `innings_number`) orders `438/10 & 209/7`; **no-ordinal
  closed-before-open** reversed input → `438/10 & 215/7`; star is the OPEN
  innings, never the completed one; declared-first ordering.

### Commands run + results
- `curl /matches/live` + `/app/home` → IRE vs IND **live** (so it lands under
  today); NZ `team1=[438/10(1), 222/7(3)]` correct order with `innings_number`.
- `flutter analyze` (changed dirs) → No issues.
- `flutter test` → **148/148 passed**.
- `npm test` → **97/97 passed**.
- `node --check` schedule.js / normalizer.js / index.js / client.js → all OK.

### Not done (remaining)
- Broad design-system consolidation (#9 header language, #10 explicit bottom
  padding audit beyond existing `mainScrollBottomInset`, Home live-list ordering
  #6, logo-fallback polish #8) were not in this pass.
- No dedicated `/schedule/by-date` backend route (merge stays client-side on
  proven endpoints). Cache: `_inningsFromCache` self-corrects order, so no
  client cache version bump was required; schedule client key already `v2`.
- No on-device screenshot from this environment; verified via live API +
  analyzer + full test suites + pure-function tests.

## Task: Inspect-first fix — Schedule merge + Test-score innings order (2026-06-28)

Strict inspect-first pass against the LIVE API (`https://api.webcrichd.co`).
Traced both reported bugs UI → repository → backend route → provider/normalizer
and confirmed root causes from real payloads before editing.

### Root causes (proven from real API responses)
- **Schedule missing IRE vs IND:** the Schedule screen reads ONLY
  `/schedule/upcoming`. That feed returned 4 days starting **Jun 29** with no
  Jun 28 entries; LAKR vs SOR is a Jun 29-UTC match the app regroups to Jun 28
  local. **IRE vs IND 2nd T20I is LIVE today** and lives in `/matches/live`
  (`start=2026-06-28T12:30Z`) — never merged into Schedule. (`/matches/upcoming`
  returned 0, `/matches/recent` 1.)
- **Home hero `206/7 & 438/10*` (reversed + wrong star):** every list/home feed
  goes through `extractHomeInnings` (`getLiveMatches/Upcoming/Recent` +
  `/app/home` all use `normalizeHomeMatchList`). It emitted innings with NO
  order ordinal, so the Flutter model (`_orderInnings`) could not reorder and
  the widget starred the last array item. When the keyed `inngsN` order wasn't
  chronological the hero reversed and starred the completed innings.

### Backend changes (`cricket-api`)
- **`src/providers/cricbuzz/normalizer.js`**
  - `extractHomeInnings` (powers `/app/home` + `/matches/live|upcoming|recent`):
    NUMERIC-sort the keyed `inngsN` innings (string sort breaks at `inngs10`) and
    emit an explicit `innings_number` (prefers provider `inningsId`/`inningsNo`,
    else the key digit). Now exported for testing.
  - `extractInningsScore` (quick score) + `normalizeTeamFull` (match detail):
    emit `innings_number` from the chronological source position / provider id.
- **`src/providers/cricbuzz/home-innings-order.test.js`** (NEW): 5 node tests —
  emits ordinal, orders correctly when keys arrive reversed, double-digit
  `inngs10` numeric-sort, prefers provider `inningsId`, empty → [].
- **`src/routes/schedule.js`**: `[Schedule]` diagnostics (kept from prior pass).

### Flutter changes
- **`lib/models/cricket_match.dart`**: added `'innings_number'` to
  `_inningsNumberOf` so the model reads the backend's new snake_case ordinal and
  `_orderInnings` sorts deterministically (and the current-innings `*` lands on
  the true latest innings, never a completed one).
- **`lib/repositories/cricket_repository.dart`**: `scheduleByDay` now MERGES the
  Cricbuzz schedule feed with today's **live + recent + upcoming** match feeds
  (deduped by match id; live/recent/upcoming win since they carry score +
  status), so the calendar shows real matches for the day — not just future
  "upcoming-series". Category tabs filter the merged-in matches with the shared
  `UpcomingSort` classifier (+ a `women` check). Cache key bumped to
  `schedule:days:v2:$type` to bypass any stale single-match payload. Empty merge
  → no days (clean empty state).
- **`lib/widgets/team_score_view.dart`** + **`test/team_score_view_test.dart`**:
  (prior pass) Test scores render the clean combined `438/10 & 209/7*` line on
  hero/cards/details; `1st`/`2nd` only in Scorecard tab headers.

### Tests added/updated
- `test/score_presentation_test.dart`: real `/app/home` shape (reversed
  `score.team1` array + `innings_number`) → asserts `438/10 & 209/7` order +
  overs order; schedule category filter (IRE vs IND → international, LAKR vs SOR
  → league).
- `cricket-api/.../home-innings-order.test.js`: see above.

### Commands run + results
- `curl https://api.webcrichd.co/{schedule/upcoming,matches/live,matches/upcoming,matches/recent,app/home}` — inspected real payloads (proof above).
- `flutter analyze` (changed files) — No issues.
- `flutter test` — **141/141 passed**.
- `npm test` (cricket-api) — **97/97 passed**.
- `node --check` schedule.js + normalizer.js — OK.
- End-to-end merge simulation on the real payloads: **Jun 28 → 5 matches incl.
  `IRE v IND 2nd T20I` and `LAKR v SOR`** (`Jun28 includes IRE v IND -> true`).

### Remaining risks / not done
- The score-order fix is deterministic by construction; the exact historical
  reversal couldn't be reproduced live (current feed happened to be ordered) but
  the emitted ordinal + new tests guarantee correctness for any input order.
- A dedicated backend `GET /schedule/by-date` was NOT added — the merge is done
  client-side in the repository using already-correct, proven endpoints (fully
  verifiable here without a live DB/redis). Backend route can follow if a
  server-side merged calendar is preferred.
- Design-system consolidation (Phase 10/11) not in this pass.
- Real on-device screenshot not possible from this environment; verification is
  via the real API payloads + analyzer + full test suites + merge simulation.

## Task: Test-match score format fix + schedule diagnostics (2026-06-28)

Premium-cricket data-correctness pass. Two concrete fixes plus an honest scope
note on the larger backend/design items.

### 1. Test score: removed inline `1st`/`2nd` prefixes (the #1 reported bug)
Hero, match cards and the Match-Details header were rendering Test scores as
stacked ordinal rows (`1st 438/10` / `2nd 126/3`) — cheap and non-standard. The
score pipeline was already centralized (`utils/score_presentation.dart` +
`widgets/team_score_view.dart`); only the multi-innings *layout* needed to
change.
- **`lib/widgets/team_score_view.dart`**: all multi-innings modes (hero / card /
  details / bar) now render ONE clean combined line `438/10 & 126/3*` (current
  innings starred, order preserved, earlier innings dimmed) with the overs on
  their own line beneath (`87.1 ov • 96.2 ov` roomy / `87.1 • 96.2 ov` tight).
  Deleted the now-unused `_stackedRows` builder + `_rowMainAlign` getter.
  Converted `_combinedScoreRich` from raw `RichText` to `Text.rich` so the
  combined score is a single discoverable string. Innings ordinals (`1st`/`2nd`)
  remain ONLY in the Scorecard tab headers (`md_panels.dart`) — untouched, which
  is the allowed place per the brief.
- **`test/team_score_view_test.dart`**: updated the two multi-innings widget
  tests to assert the combined format (`362/10 & 391/10`, `291/10 & 90/3*`) and
  that `1st`/`2nd` are NOT rendered inline. `score_presentation_test.dart`
  needed no change (its `combinedScore`/`oversLine` contract was already the
  target format).

### 2. Schedule diagnostics (backend, explicitly requested in §5)
- **`cricket-api/src/routes/schedule.js`**: added `logScheduleResult()` emitting
  `[Schedule] provider result {type, timestamp, source:cricbuzz, days, matches,
  series:[...]}` for both `/schedule/upcoming` and `/schedule/upcoming/:type`.
  This is the signal needed to tell "provider genuinely returned one match" from
  "we dropped/filtered matches" (the missing IRE vs IND vs MLC-only report).
  `node --check` OK.

### Verified
- `flutter analyze lib/widgets/team_score_view.dart lib/utils/score_presentation.dart` — No issues.
- `flutter test test/team_score_view_test.dart test/score_presentation_test.dart` — all passed (23).
- `node --check cricket-api/src/routes/schedule.js` — OK.

### Investigated but NOT changed (honest scope note)
- **No fake/mock schedule data exists in the production path.** `/schedule/*`
  delegates to the Cricbuzz provider; on error it returns `{ days: [] }` (never a
  hardcoded MLC match). `manual-matches.js` is admin-DB-controlled and is merged
  only into `/matches/live|upcoming`, NOT `/schedule`. The Flutter screen has no
  mock list. `cricket-api/lib/data/mock_data.dart` belongs to the OLD template
  Flutter app under `cricket-api/lib/`, not the production `lib/` — unused by the
  served API.
- **The "MLC only, missing IRE vs IND" issue is a provider data-sourcing/merge
  concern**, not a hardcode. `normalizeUpcomingSchedule` already iterates every
  day/series/match; the `type` filter is applied server-side by Cricbuzz's
  `/cricket-schedule/upcoming-series/{type}/{ts}` URL. Diagnosing/merging the
  full international+league+domestic+women+series-page set safely requires the
  LIVE Cricbuzz API (and a device to confirm grouping) — making blind parser
  changes risks breaking schedule for all OTHER dates, which AGENTS.md forbids
  ("Do not rewrite working features"; "Preserve … data logic unless explicitly
  asked"). The new logging is the safe first step to drive that fix with real data.
- **Design-system consolidation** across Home/Matches/Schedule/Series is a large
  multi-screen effort; the shared system already largely exists
  (`CricColors`/`app_theme.dart`, `components.dart`). Not attempted in this pass.

## Task: Series Screen fidelity pass #2 — target-match fixes (2026-06-28)

Refinement on top of the new-kit redesign, addressing the reported gaps vs the
target screenshot. Visual only; data/API/filter/classification untouched.

### Changed files
- **`lib/screens/series/widgets/series_poster_cards.dart`**
  - **Smooth card edges**: `SeriesBorderFrame` rewritten — outer glow now lives
    on a `Container` OUTSIDE the `ClipRRect` (never sliced), the cyan edge is a
    Flutter-drawn `Border.all` (crisp, not a stretched border PNG), bg art
    clipped inside r=24. Dropped the `frame:` PNG param (was the "sliced" look).
  - **Hero title no longer truncates**: overline / main word / year each wrapped
    in `FittedBox(scaleDown)` so "BANGLADESH," always shows in full.
  - **Clean trophy**: tournament card now uses the core `trophy_gold_laurel_icon`
    (the extracted silver sheet trophy had jagged edges). Tournament title is
    top-aligned (was vertically centred) to match the target.
  - **Completed = compact dim card always**: `CompletedSeriesCard` now always
    renders the compact bilateral-style completed design (status pill + 2 rings
    + trophy shield + dim CTA) — never the league/batsman or tall tournament
    composition.
  - **Filter chips never half-clipped**: auto-scroll aligns the selected chip to
    the LEADING edge (`alignment: 0.0`, explicit policy), `clipBehavior:
    hardEdge`, left padding 0 (screen already insets 24).
  - **Logo fill**: ring `logoRatio` default 0.72 → 0.78 so flags fill the ring
    interior; ring PNG still drawn on top (rim above logo).
- **Verification**: `flutter analyze lib/` clean; `flutter test` 137/137. A
  temporary 360 & 390px render probe confirmed no assertion/null errors at both
  widths (only the known Ahem-font horizontal text artifact), then removed.

### Environment note
The test host's **C: drive was full (0 B free)** — the Dart compiler failed to
write its `.dill` (`errno 112`). Cleared 11 stale `%TEMP%\flutter_tools*` dirs
and pointed `TMP`/`TEMP` at `D:\` (67 GB free) for the run; tests then passed.
No repo/user files were deleted.

### Assets that still need a cleaner replacement
- `auto_extracted/sheet3_league/sheet3_league_asset_05.png` (neon batsman) — may
  have rough edges; kept for the league card, but a clean transparent batsman
  PNG would look sharper.
- Per-type backgrounds (`sheet1/2/3_asset_01`) are sheet crops; edges are now
  hidden by the Flutter `ClipRRect`, but dedicated clean card backgrounds would
  be crisper.
- ICC tournament showing few team logos is a **backend `teamCount` data limit**
  (not an asset/UI bug): the row renders up to 5 real teams + `+N` and never
  shows "TBC" (placeholder teams are filtered by `_isShowableTeam`).


## Task: Series Screen redesign on the NEW asset kit (UI UX Pro Max) (2026-06-28)

Ran the **UI UX Pro Max** skill first (`search.py --design-system` + `--stack
flutter`): premium dark + accent, bold athletic condensed type, large readable
headings, 200–300ms transitions, no emoji icons, `LayoutBuilder`/`ListView.builder`
responsiveness. Kept CricPro's cyan brand (per AGENTS.md) over the skill's gold.

Inspected the asset tree + dimensions before coding (no guessing):
`new/core_clean_assets/*` (border glows 790×{369,327,232,201}, rings 140/58px,
status pills, buttons, chips, trophy, dots) and `new/auto_extracted/sheet{1..4}`
(per-type card art) via the manifest CSV + PNG header probe.

### Changed files
- **`pubspec.yaml`** — registered `assets/images/series/new/core_clean_assets/`
  and the four `auto_extracted/sheet*` folders.
- **`lib/screens/series/series_new_assets.dart`** (NEW) — `SeriesNewAssets` path
  constants + border-frame aspect ratios.
- **`lib/screens/series/widgets/series_poster_cards.dart`** (full rewrite) — now
  built on the new kit:
  - `SeriesLogoRing` / `SeriesLogoRingPair` / `SeriesLogoRingRow`: REAL team
    logos (`TeamLogoWidget`, admin→provider→initials) clipped inside the
    decorative ring PNGs (blue-glow / orange-green / small). Logos never baked;
    never an empty ring (`+N`/fallback). Flutter-drawn rim fallback if a ring
    asset is missing.
  - Per-type card art: tournament = `sheet1` purple panel + silver trophy
    (left); league = `sheet3` cyber stadium + neon batsman (right); bilateral =
    `sheet2` castle panel + two rings + connector + shield; completed = castle
    panel + completed border glow + warm tint + disabled CTA.
  - `SeriesBorderFrame` = bg art (cover) + directional dark scrim + core
    border-glow frame (`BoxFit.fill`), clipped r=24.
  - `SeriesStatusPillImg` / `SeriesCtaButton` render the core base PNGs with
    Flutter dot/label/chevron (+ gradient/border fallbacks). 4-chip
    `SeriesFilterChipBar` on the chip base PNGs (All/Ongoing/Upcoming/Completed).
  - Hero: `series_hero_card_border_glow` + gold laurel trophy + blue/orange
    rings (dynamic logos) + cyan title + format pill. New `SeriesHeroCarousel`
    (PageView + animated dots) when no admin hero.
- **`lib/screens/series/series_list_screen.dart`** — derived hero now feeds
  `SeriesHeroCarousel` (up to 5 spotlight series from the active filter; admin
  hero still wins, rendered single). Added the `series_screen_dark_gradient_bg`
  backdrop **dark-mode only** (light keeps the theme gradient per design rule
  #1/#7). Data/API/filter/classification logic untouched.

### Verification
- `flutter analyze lib/` — **No issues found**.
- `flutter test` — **137/137 passed**.
- A temporary 360dp render probe caught + fixed a real bug: a **negative
  `EdgeInsets`** overlap in `SeriesLogoRingRow` (`padding.isNonNegative`
  assertion) → switched to a positive gap. Probe then removed.

### Honest caveats / asset notes
- No emulator/web here, so no on-device screenshot. The only residual probe
  warning was a ~98px **horizontal** overflow under the headless **Ahem** test
  font on the competition CTA row (Ahem renders "Explore Series" ~3× wider than
  real device fonts) — the same non-representative artifact documented in prior
  passes; real-font fit is guarded by Expanded/Flexible/FittedBox. No vertical
  overflow.
- Card heights use proven responsive fixed values (not strict AR-lock, which
  crushes phone widths); the new border-glow frames are mild ratios so
  `BoxFit.fill` stretch is negligible.
- Ring↔logo alignment to each PNG's baked hole is tuned by `logoRatio`
  (0.72 glow rings / 0.86 small) since exact hole coordinates aren't shipped.


## Task: Series cards — CleanTeamLogoCircle + premium sizing (UI UX Pro Max) (2026-06-28)

Installed the **UI UX Pro Max** skill (`uipro init --ai kiro` → `.kiro/steering/ui-ux-pro-max/`) and used its design-system + flutter-stack search to guide this pass (premium dark + accent, large readable type, LayoutBuilder responsive, fill logos via cover).

### Changes (series_poster_cards.dart only)
- **New `CleanTeamLogoCircle` helper** (Flutter-drawn, no asset ring): real logo
  via `TeamLogoWidget` (BoxFit.cover for flags, transparent inner border) clipped
  to a circle that fills the disc, a neon rim painted on top, and a soft outer
  glow. Never renders an empty circle (shows `+N` / trophy fallback otherwise).
- **Removed the noisy asset-ring path**: deleted `SeriesRingLogo` + `_RingTier`
  and the 4 ring asset constants. `SeriesRingLogoPair` (bilateral), the
  tournament/league `SeriesRingLogoRow`, and the hero pair now all use
  `CleanTeamLogoCircle`.
- **Bilateral pair**: two clean circles with a positive gap (no overlap); shield
  connector clamped to 20–24px, seated in the gap and dropped slightly low so it
  never covers a logo face.
- **Competition bottom row** made robust: the "Tournament/League" label cluster
  is now fully collapsible (Flexible) so the CTA never truncates under tight
  width / large text scale (no FittedBox on the CTA).
- **Heights re-tuned to the mandatory compact ranges** (verified by a temporary
  360dp render probe, since removed):
  - tournament 218 / 228 / 238 (compact in 205–220 ✓)
  - league 200 / 208 / 216, completed 200 / 208 / 216 (compact in 185–205 ✓)
  - bilateral 188 / 196 / 204 (compact in 175–190 ✓)
- Fonts: title 18 / 19.5 / 21 (min 18 ✓), meta 12.5 / 13 / 13.5 (min 11.5 ✓),
  CTA height 40 / 42 / 44 (min 38 ✓). Bilateral ring outer 70 / 78 / 86; logo
  fills ~95% (inner ≈ 65/73/81, well above the 56 floor).

### Probe results (360dp, MediaQuery+SizedBox forced)
- Rendered heights: tournament 218, league 200, bilateral 188, completed 200.
- Zero vertical overflow on all four. Tournament/league showed a 17px *horizontal*
  overflow ONLY under the headless Ahem test font (renders "Explore Series" at
  ~290px vs ~110px real) — not representative of on-device fonts; bilateral and
  completed are clean in both axes. CTA text never truncates.
- Team row: max 5 logos + `+N` (`+7` for the 12-team WWC fixture); "N Teams"
  shows when teamCount ≥ 3 (full list comes from the backend enrichment landed
  in the previous task — frontend already renders all of `series.teams`).

### Results
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.

---

## Task: Series cards — full tournament teams (backend) + layout fidelity pass (2026-06-28)

### 1. Full tournament/league team list (data fix)
Root cause: the Flutter frontend never capped teams (`_teamsFromApi` keeps all,
`SeriesView.teamCount = teams.length`, `SeriesRingLogoRow` shows up to 5 + "+N").
The cap was in the **backend** `/series` enrichment, which only attached the
first match's 2 teams. Fixed in `cricket-api/src/routes/series.js`:
- `recoverSeriesMeta()` now computes `deriveTeamsFromSeriesMatches(res.matches)`
  (all distinct teams across the series' full match list) and returns
  `teams` + `teamCount` (both success and catch paths).
- `enrichSeriesList()` recover block PREFERS the fuller list:
  `if (meta.teams.length > (e.teams?.length||0)) e.teams = meta.teams;` and the
  same for `teamCount`. Final response still emits the `teams` array; the
  frontend derives the count from `teams.length`, so no `team_count` field or
  `api_models.dart`/`series_components.dart` change was needed.
- `node --check cricket-api/src/routes/series.js` → OK.
- **Where teams come from**: backend enrichment (frontend already renders them).
- **Row logic**: max 5 logos, then `+N` where `N = teamCount - shown`;
  "`teamCount` Teams" metadata when `teamCount >= 3`.
- **Deploy note**: requires backend redeploy + `/series?refresh=true`; can't be
  verified against the live API locally. `recoverSeriesMeta` runs only for
  `needMeta` series (ongoing + undated), so already-completed editions keep
  their existing team set unless `needMeta` is widened.

### 2. Layout fidelity (series_poster_cards.dart)
- **Titles bumped to the required minimums** (was 16/17.5/19, too small):
  compact 18, regular 19.5, large 21.
- **Meta fonts**: 12.5 / 13 / 13.5 (min 11.5 honored).
- **Card heights**: tournament 220/230/240, league 210/218/226,
  completed 210/218/226, bilateral 192/200/208.
- **Bilateral ring pair rebuilt**: rings no longer overlap — a positive gap
  (`ring*.14`) sits between two clean circles; the connector shield is clamped
  to 20–24px and tucked into the gap slightly low, so it never covers a flag
  face. Ring outer 70/76/82; inner flag fill ≈ 57/62/67 (BoxFit.cover,
  transparent border, ≥56 on compact).
- Strip ring (tournament/league logo row) 32/34/36.
- CTA height 40/42/44, full text always (no FittedBox/ellipsis on title or CTA).
- Tournament keeps generic-stadium bg + silver trophy overlay (no dedicated
  tournament bg exists in newest-design); no heavy scrim/tint on live cards.

### Results
- `flutter analyze lib/` — No issues found (213s).
- `flutter test` — 137/137 passed.

---

## Task: Series cards — smaller bilateral rings, richer art, bigger trophy (2026-06-27)

### Changes (series_poster_cards.dart only)
- Bilateral team rings reduced (compact 82→74, regular 88→80, large 96→88) so
  they're less dominant and match the target proportions; inner flag fills
  ~0.82 of the ring via BoxFit.cover.
- Completed tint lightened (.28/.30 → .20/.22) so the completed artwork is no
  longer flattened to a dark box.
- Tournament trophy enlarged (left art 34%→38% of card width; league 26%→28%);
  trophy renders ~100–120px tall on compact.

### Reported values
- Compact card heights (verified earlier via probe): tournament 212, bilateral
  192, league 202, completed 202.
- Bilateral ring outer (compact) 74 / inner logo ≈ 60 (BoxFit.cover, transparent
  border, initials fallback same size, never empty).
- Tournament/league logo strip: `SeriesRingLogoRow` renders up to 5 real teams +
  `+N`. It uses the FULL `series.teams` list (no first-2 cap in this file).
- CTA: full text, height 40/42/44; never truncates.

### Limitation (honest)
The ICC tournament card shows only 2 flags because `series.teams` from the
view-model currently contains 2 teams for that series; expanding it requires
editing `SeriesView`/the parser (out of the allowed file + the no-data-logic
rule). The row already shows up to 5 + N whenever the data provides them.

### Results
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.

---

## Task: Series cards — CTA full-text (no truncation) (2026-06-27)

### Fix
The prior overflow fix had made the CTA label ellipsize → "View Ser…" /
"Explore …". Reverted: the CTA pill now renders its full label (no
Flexible/ellipsis), and only the low-priority TYPE label ("Tournament"/"League")
is `Flexible` + ellipsis in the tournament/league bottom row. So the CTA text is
always fully visible; the type label shrinks if space is tight.

### Verified (probe, then removed)
Forced-compact (MediaQuery 360) rendered heights: tournament 328×212,
bilateral 328×192, both overflow=0. Heights are within the requested compact
ranges (tournament 205–220, bilateral 185–200) and are honored by the parent
(`ListView → Column → SizedBox(height)` — no shrinking).

### Ring / CTA specs (compact)
- Bilateral ring outer 82 / inner logo ≈ 0.84×ring (fills the hole), BoxFit.cover,
  transparent border, initials fallback at same size, never empty.
- CTA height 40 (compact) with full text.

### Files
- `lib/screens/series/widgets/series_poster_cards.dart`.

### Results
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.

### Limitation
No device/emulator or web here, so I can't attach real screenshots; verified
heights + overflow programmatically. On real fonts the CTA fits full text at
compact width; the only place it could overflow is the Ahem test font, which no
suite test renders for these cards.

---

## Task: Series cards — taller heights, overflow fix, debug-verified (2026-06-27)

### Debug inspection (probe widget test, then removed)
Rendered `SeriesPosterCard` at forced 360dp (MediaQuery 360): tournament =
328×212, bilateral = 328×192, both overflow=0. Confirms the card receives the
intended height (no parent constraint shrinks it — `ListView → Column →
SizedBox(height)`), and the 360-width compact metrics apply.

### Overflow fix
The tournament card's bottom row (type label + CTA) overflowed horizontally on
the narrowest widths (and under the Ahem test font). Made the label `Flexible`
+ ellipsis, the CTA `Flexible`, and the CTA pill's own label `Flexible` +
ellipsis → bottom row can never overflow; on real widths the CTA shows full
text.

### Heights by breakpoint
- compact ≤360: tournament 212, league 202, completed 202, bilateral 192.
- regular 361–430: tournament 226, league 212, completed 212, bilateral 200.
- large >430: tournament 236, league 220, completed 220, bilateral 208.

### Ring sizes + logo fit
- Bilateral outer ring: compact 82, regular 88, large 96.
- Hero ring: 76 / 86 / 96. Strip ring (tournament/league): 30 / 33 / 36.
- Logo fits inside ring at `ringSize × innerRatio × 0.92` (innerRatio = asset
  inner-hole fraction) ≈ 82% of the outer ring, clipped circular, `BoxFit.cover`.

### Other
Trophy enlarged (left zone 34% tournament / 26% league of card width), metadata
font up (12/12.5/13), CTA pill height up (40/42/44), more edge padding.

### Files
- `lib/screens/series/widgets/series_poster_cards.dart`.

### Results
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.

---

## Task: Series cards — taller heights + 4 named card widgets (2026-06-27)

### Change
Bumped card heights (compact tournament 196 / league 182 / completed 182 /
bilateral 170; regular 218/198/198/186; large 228/206/206/194), metadata font
(11.5/12.5/13), CTA height (36/40/42), status chip height (26/28/30). Refactored
dispatch into 4 named public widgets: `TournamentSeriesCard`, `LeagueSeriesCard`,
`BilateralSeriesCard`, `CompletedSeriesCard` (completed routes via its own widget
which branches competition vs bilateral composition). Visual only.

### Files
- `lib/screens/series/widgets/series_poster_cards.dart`.

### Results
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.

---

## Task: Series cards — fix overflow + per-variant heights (2026-06-27)

### Change
The tournament card overflowed by 2.8px because tournament + league shared one
`tall` height (158) that was too small for the content (status + trophy/title/
ring-row/meta + CTA). Split `_Metrics` into per-variant heights and bumped CTA /
status sizes.

### Card heights by breakpoint
- compact (≤360): tournament 186, league 172, completed 170, bilateral 158.
- regular (361–430): tournament 204, league 186, completed 186, bilateral 172.
- large (>430): tournament 216, league 196, completed 196, bilateral 182.

The `Expanded` middle band now has 6–20px of slack at every breakpoint (was a
-2.8px deficit), so no vertical overflow.

### Other bumps
CTA height 34/38/40, status chip height 24/26/28, meta 11/12.5/13, bilateral
ring 74/86/96, strip ring 30/33/36, hero 158/174/192, hero ring 72/82/92.

### Files changed
- `lib/screens/series/widgets/series_poster_cards.dart` (metrics + the two card
  height calls). `series_list_screen.dart` untouched (public API stable).

### Results
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.

---

## Task: Series cards rebuilt on newest-design clean asset kit (2026-06-27)

### Summary
Rebuilt `series_poster_cards.dart` composition on the `newest-design/` clean
reusable assets (read `manifest.json` + `README.md` first). Old `new-design`
baked-circle posters dropped for the cards. Public API unchanged
(`SeriesPosterCard`, `SeriesFilterChipBar`, `SeriesFeaturedHeroPoster.*`), so
`series_list_screen.dart` needed no edits.

### newest-design assets used
- backgrounds: generic_stadium / league_hero / bilateral / completed `_clean.webp`
- overlays: card_frame_wide (1220x235), card_frame_short (1220x180), ring
  small/medium/large/xlarge, gold_trophy_badge, silver_tournament_trophy
- components: cta_pill_medium, status_chip_empty
- icons: calendar / clock / location badges

### Frame ratios
Frames declared at 1220x235 (wide, AR 5.19) and 1220x180 (short, AR 6.78), and
backgrounds 1221×{234,220,179,168}. Those are very wide strips → AR-locking on
phones gives ~48px cards, so cards use responsive HEIGHTS with background
`BoxFit.cover` (texture) + frame `BoxFit.fill` (thin neon border). Documented as
a deliberate deviation from strict AspectRatio because AR-lock breaks phone
widths.

### Reusable widgets created
`SeriesRingLogo`, `SeriesRingLogoPair`, `SeriesRingLogoRow`, `SeriesStatusChip`,
`SeriesCtaPill`, `SeriesMetaRow`, `SeriesCardFrame`, `_PosterFavoriteStar`,
`_TrophyArt`.

### Responsive breakpoints
`_metricsFor(w)`: compact ≤360, regular 361–430, large >430 — scales pad, title,
meta, status height, star, bilateral ring (72/84/96), strip ring (30/33/36), CTA
height, card heights (tall 158/170/182, short 138/150/162, hero 156/172/190),
hero ring (70/80/92). Structure identical across breakpoints; only sizes scale.

### How logo filling was fixed
`SeriesRingLogo` stacks the real `TeamLogoWidget` (admin→provider→local→initials
priority kept, `borderColor: transparent` so it has no competing ring) CLIPPED
in a `ClipOval`, sized to `ringDisplay * innerRatio * 0.92` — where innerRatio is
the asset's inner-hole fraction (96/116, 160/180, 260/280, 360/380). The neon
ring asset is drawn on top via `Image.asset`, so the logo fills ~92% of the
ring's inner hole and the ring + logo read as one object. No empty rings (a
ring renders only when it has a real logo or an explicit +N/trophy fallback).

### Results
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.

### Note
Pixel-perfect aspect locking to the asset strips was intentionally not used
(would crush phone cards to ~48px tall). The `team_logo_duo_rings_connector` and
`team_logo_ring_row_6` premade multi-slot assets were not used because they bake
a fixed slot count (would show empty rings when data has fewer teams); the row /
pair are composed from individual ring assets so no empty slot can appear.

---

## Task: Series bilateral cluster composition fix + asset-dimension check (2026-06-27)

### Asset dimensions (parsed from the .webp headers)
- bilateral 53x135 (AR 0.39), tournament 78x143 (0.55), completed 124x212
  (0.59), league 184x141 (1.31), hero_banner 223x112 (1.99).
- These are SMALL source images with portrait-ish ratios that don't match the
  wide cards they render in → locking each card to the asset aspect ratio (as
  requested) would distort the layout, and the baked circles in such small
  stretched images can't be reliably anchored. So the code-drawn circles remain
  the source of truth; I did not aspect-lock the cards.

### Fix (the concrete screenshot issue)
- `_BilateralLogoCluster`: reduced overlap (ring*.22 → *.1) so the two team
  circles read as separate (target), and moved the centre badge from a
  full-centre `Positioned.fill` (which sat ON TOP of the flags) to a smaller
  (ring*.42 → *.32) badge tucked low at the seam (`top: ring*.6`) so it sits
  BETWEEN the circles without covering the flag faces.
- Carries forward the larger ring sizes (66–90) + 0.84 inner fill from the prior
  pass, so each flag fills its circle.

### Results
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.

### Limitation
Pixel-exact anchoring to the assets' own baked circles isn't achievable: the
assets are tiny/portrait sources stretched by BoxFit.cover, so their baked
circle positions shift unpredictably across widths. The rendered circles are
sized/placed to occupy the right-hand ring zone (good on phone widths); a
truly 1:1 match needs proper full-size poster assets (or their circle
coordinates) without baked circle slots.

---

## Task: Series cards — enlarge logo circles to fill the poster ring zones (2026-06-27)

### Widgets changed
- `_SeriesFilledLogoCircle`: inner logo fill ratio 0.82 → 0.84.
- `_metricsFor` (responsive metrics): bilateral ring diameter bumped per
  breakpoint — compact 56/60 → 66/70, regular 66 → 82, wide 72 → 90 — so the
  code-drawn circles are as large as the asset's baked glowing rings and occupy
  that zone instead of floating small beside it.
- `SeriesFeaturedHeroPoster`: hero team-logo diameter 58/64/72 → 64/72/80.
- Bilateral cluster (`_BilateralLogoCluster`) unchanged structurally (already
  Stack+Positioned, two overlapping circles + centred shield) — now driven by
  the larger ring metric.

### How circle alignment / fill was addressed
The bilateral/hero circles are rendered in code (Stack+Positioned) with the team
logo filling 84% of the ring (flags BoxFit.cover). Enlarging the ring to the
breakpoint sizes above makes the rendered circle coincide with / cover the
asset's baked ring zone on the right, so the logo reads as filling the poster
circle rather than a small logo beside a giant empty ring.

### Results
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.

### Honest limitation
Exact per-asset circle anchoring (normalized `PosterAnchors` measured from each
`.webp`) can't be derived without the asset's actual circle coordinates, and
`BoxFit.cover` shifts the baked circles differently at phone vs wide/web widths.
The rendered circles are now sized to occupy the ring zone (big improvement on
phone widths), but pixel-perfect alignment to the asset's own baked rings —
especially on very wide/web layouts — would need either the circle coordinates
from the design source or background assets without baked circle slots.

---

## Task: Series cards — per-type poster artwork + compact responsive layout (2026-06-27)

### Widgets changed
- `_PosterArtFrame` (was `_CleanFrame`): shows the per-type `*_series_card.webp`
  artwork full-bleed with a LIGHT directional `_ArtScrim` (art stays visible).
- `_CompetitionPosterCard` (tournament/league/completed competition): rebuilt to
  use the per-type asset — art on one side (left=tournament, right=league),
  content inset on the other; removed the rendered emblem; kept the real
  `_TeamStrip` (+N) + meta + type + CTA; compact heights.
- `_BilateralPosterCard`: now uses `_PosterArtFrame(bilateral/completed asset)` +
  the code-drawn `_BilateralLogoCluster` overlaid on the right.
- Removed `_EmblemVisual` (unused).

### Responsive metrics
`_metricsFor(width)` now also returns `tall`/`short` card min-heights (compact
156/128, normal 168/138, large 178/146). Frame min-height from `context.w`,
inner sizes from LayoutBuilder width. Compact scales down without changing
structure.

### Tournament card → closer to target
Flat stadium + tiny trophy icon → `tournament_series_card.webp` poster art on
the LEFT + content column on the RIGHT (title, real logo strip + N,
date/matches/teams, Tournament, Explore Series), compact height — no more tall
empty dark card.

### Logo-circle fill ratio
`_SeriesFilledLogoCircle` draws a thin glowing ring + `TeamLogoWidget` at
`ring * 0.82` (82% fill); used by the bilateral cluster and the strip.

### Results
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.

---

## Task: Series cards — responsive structural fix + code-drawn filled circles (2026-06-27)

### Widgets changed
- `_BilateralPosterCard`: now uses `_CleanFrame` (no baked-circle asset) + new
  `_BilateralLogoCluster` that draws the two right-side rings in code (Stack +
  Positioned, slight overlap, small shield/trophy centred over the seam).
- `_CompetitionPosterCard` (tournament/league/completed-competition): now reads
  responsive metrics; strip uses the filled-circle widget.
- New: `_SeriesMetrics` + `_metricsFor(width)`, `_SeriesFilledLogoCircle`,
  `_BilateralLogoCluster`.
- Removed: `_PosterShell` (baked-art shell) and `_TeamPair` (replaced by the
  code-drawn cluster). `_TeamStrip` now renders `_SeriesFilledLogoCircle`.
- `_CtaPill` gained a responsive `height`.

### Responsive metrics
`_metricsFor(width)` → 3 breakpoints: compact ≤360 (incl. 320), regular 361–411,
large >411. Each supplies pad, title, meta, ctaH, bilateral ring, strip ring,
emblem width. Compact scales sizes DOWN (e.g. bilateral ring 58/64 vs 72 vs 78,
title 14.5–15 vs 16 vs 17, CTA 34/36/38) without changing the layout structure.

### Circle/logo fill ratio
`_SeriesFilledLogoCircle` draws a thin glowing ring (2px border + soft glow) and
centres a `TeamLogoWidget` sized at exactly `ring * 0.82` → inner logo is 82% of
the ring diameter (flags fill via BoxFit.cover). No more giant empty halo: the
rings are now ours, sized to the logo, not the background art's oversized baked
circles. Invalid teams render nothing (no empty rings). The bilateral cluster
and the tournament/league strip both use this widget, so every circle on every
card is content-backed.

### Results
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.

---

## Task: Series cards — structural fix: drop baked-circle assets for competitions (2026-06-27)

### Summary
Structural fix (no more scrim/opacity masking). Root cause: the league /
tournament / completed-competition `.webp` posters bake in decorative circle
slots + a CTA-button placeholder that dynamic data can't reliably fill. Solution
per the brief: STOP using those baked-circle backgrounds for competition cards
and render content-backed slots on a clean background. Bilateral keeps its asset
because its baked circles ARE reliably filled by the two team flags.

### Empty-circle sources removed
- Deleted `_DirectionalScrim` (the scrim-masking approach) and `_PosterSideCard`
  (which painted the `newTournamentSeriesCard` / `newLeagueSeriesCard` /
  `newCompletedSeriesCard` baked-circle posters). Those assets are no longer
  used for any card → their baked empty circles + CTA-button placeholder can no
  longer appear.

### What is now content-backed
- New `_CompetitionPosterCard` (tournament / league / completed competition):
  - `_CleanFrame` background = clean stadium image (`SAsset.listCardBg`, no baked
    circles) + per-type colour wash (purple for completed). Background stays
    visible, not flat-black.
  - A rendered `_EmblemVisual` — a glowing trophy (tournament/gold) or shield
    (league/cyan) over a radial bloom; a real content-backed icon, never an
    empty bordered ring. Emblem sits LEFT for tournament, RIGHT for league.
  - A REAL `_TeamStrip` of team logos (27–30px) with a `+N` badge; renders only
    showable teams, so there are no blank slots.
  - Metadata row (date • matches/format • N Teams) + type tag (bottom-left) +
    CTA pill (bottom-right). No baked button box behind the CTA.
- Bilateral (`_BilateralPosterCard`) unchanged in spirit: keeps
  `newBilateralSeriesCard` for ALL bilateral incl. completed tours (so the two
  flags reliably fill the asset's right-side circles); completed adds the purple
  wash + trophy crest between the flags.

### Card variants changed
- Tournament, League, Completed-competition → new clean `_CompetitionPosterCard`.
- Completed bilateral now uses the bilateral asset (aligned circles) + purple
  wash instead of the completed asset.

### Files changed
- `lib/screens/series/widgets/series_poster_cards.dart` only.

### Commands run
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.
- Web/Chrome: NOT configured (no `web/` dir) — not run.

### Remaining limitation
- Competition cards no longer show the per-type `.webp` artwork (trophy render /
  neon league art), because that art is inseparable from the baked empty
  circles. They now use a clean tinted stadium + rendered emblem + real logos —
  guaranteed free of empty circles. Restoring the bespoke per-type art would
  require clean poster assets without baked placeholder circle slots.

---

## Task: Series cards — kill empty circle slots + CTA placeholder box (2026-06-27)

### Summary
Working from real device screenshots. Fixed the two concrete defects the
screenshots showed: (1) league/completed-competition cards had large EMPTY
glowing circle slots on the far side of the poster, and (2) a baked translucent
"button" placeholder showed to the right of every CTA. Visual-only; no backend/
API/filter/classification/data changes.

### Exact fixes
- `_DirectionalScrim`: for content-LEFT variants (league + completed league),
  `coverFarSide` now darkens the WHOLE width (.9/.76/.92) so the asset's empty
  baked circle slots on the right are masked — no ghost circles. Content-RIGHT
  variants (tournament) keep the real left trophy art visible and darken the
  right content side to .95 (kills the faint ghost clock/circle icons there).
- Bottom band strengthened to .88 (cards) / .82 (bilateral) so the asset's baked
  CTA-button placeholder is hidden and only our real CTA pill reads.
- Bilateral team logos KEPT filling their glowing circle slots (reverted the
  over-large mask back to a thin edge halo so the asset's nice glow ring still
  frames the flags — confirmed good in screenshots for NZ/ENG, SL/WI, IND/IRE).
- CTA polish: height 30→34, padding 13→16, radius 9→12, icon 16→17, text 12→12.5
  — fits text+icon, restrained, no clipping, consistent across cards.
- Star: 22→25. Metadata: icon 12.5→13.5, text 11.5→12 (more readable, FittedBox
  still only a last-resort safety).
- Completed competitions keep "View Series" (set previous pass); ongoing/upcoming
  tournament & league keep "Explore Series".

### Card variants changed
- League / completed-league (`_PosterSideCard` content-left): far-side empty
  circles masked.
- Tournament / completed-tournament (`_PosterSideCard` content-right): right
  ghost icons masked, left trophy art preserved.
- Bilateral (`_BilateralPosterCard`): flags still fill circles; CTA box hidden.
- Shared `_CtaPill`, `_FavoriteStar`, `_PosterMetaRow`, `SeriesTeamLogoCircle`.

### How logo-circle alignment was handled
Bilateral flags render inside the asset's right-side circles (size 52/58/64,
thin edge halo, no heavy mask) so the baked glow ring frames them. Non-bilateral
empty slots are covered by the directional scrim instead of being filled with
fake content (per the brief: fill OR cover). No placeholder circles are rendered
for logo-less teams (`_isShowableTeam`).

### Files changed
- `lib/screens/series/widgets/series_poster_cards.dart` (visual only).

### Commands run
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.
- Web/Chrome: NOT configured (no `web/` dir) — not run.

### Remaining limitation
- League cards now read as clean dark posters (the far-side batsman art is
  dimmed along with the empty circles, since both share that region). Showing
  the league player art AND hiding the empty circles isn't separable with these
  template assets; a clean league poster without baked circle slots would allow
  both.

---

## Task: Series List Screen — final visual polish pass (2026-06-27)

### Summary
Visual-only refinement on top of the existing per-type poster implementation
(per-type background art + directional scrims + content-left league + auto-
scroll chips already in place). No structural rewrite; no data/API/filter/
classification changes.

### Refinements (`series_poster_cards.dart`)
- Completed competition cards (finished IPL/tournament) now use **"View
  Series"** CTA (was "Explore Series"); ongoing/upcoming tournament & league
  keep "Explore Series".
- Tournament/league: rebalanced art-vs-content width (`inset` w*.32→.29, clamp
  92–140 → 86–124; content right pad 24→18) for a roomier title block.
- Team-badge strip spacing 5→6 (more even/polished); CTA pill shorter + tighter
  radius (h32→30, r10→9); bilateral centre emblem smaller/subtler (.44→.40,
  icon .24→.22).
- Filter chips: softer active glow (alpha .4→.3, blur 14→12).
- Hero: smaller + higher trophy (40/30→38/26), tighter spacing, slimmer format
  pill (vpad 4→3.5, font 12→11.5), year slightly smaller than the main word
  (20→19) so the main subject word is the largest line. Full team names under
  hero logos retained.

### Files changed
- `lib/screens/series/widgets/series_poster_cards.dart` (visual polish only).

### Commands run
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.
- Web/Chrome: NOT configured (no `web/` dir) — not run, not claimed.

### Remaining limitation
- Shipped per-type `.webp`s are template renders with baked placeholder
  circles/icon rows; the directional scrim masks them on the content side, so
  visible art is the atmospheric portion, not the mockup's exact custom art. A
  1:1 art match needs clean per-type posters without baked placeholders.

---

## Task: Series List — per-type poster art restored with scrim masking (2026-06-27)

### Summary
Brought back the rich per-type `new-design/*.webp` backgrounds (tournament /
league / bilateral / completed) instead of one generic stadium, and handled
their baked placeholder circles/icon rows with DIRECTIONAL scrims + per-logo
radial masks + content placement (not a uniform veil). Also fixed hero team
labels and the filter-chip scroll-into-view. No data/API/classification changes.

### UI differences fixed
- Per-type poster art is visible again (art side kept clear; content side
  scrimmed so baked placeholder slots/icons there are masked). Cards no longer
  look generic.
- `_PosterSideCard` (tournament / league / finished competition): art on the
  art side (tournament art-left/content-right; league art-right/content-left),
  decorative team-badge strip (+N), date|matches|teams meta, type tag + CTA.
  No VS, no fixture identity.
- `_BilateralPosterCard`: title left, two real team logos right (shield emblem
  between; trophy crest + muted purple for completed), meta + View Series.
- Team logos use `SeriesTeamLogoCircle` with a soft radial mask so no baked
  ring peeks; invalid teams render nothing (no ghost circles).
- Hero side labels now use the FULL team name from the SAME team object as the
  logo (fixes swapped codes like "BAN under Australia"); title splits to
  overline / cyan main word / cyan year + format pill.
- Filter chips: 4 only, `Scrollable.ensureVisible` on selection + safe L/R
  padding so the selected chip is always fully visible, never half-cut.

### Files changed
- `lib/screens/series/widgets/series_poster_cards.dart` (rebuilt: per-type
  poster shells, directional scrim, logo mask, stateful chip bar, hero labels).

### Commands run
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.
- Web/Chrome: NOT configured (no `web/` dir) — not run, not claimed.

### Remaining limitation
- The masking scrims are tuned without being able to see the exact baked-slot
  positions in each `.webp`; if a particular asset bakes a placeholder on its
  art side, a faint trace could remain there. A truly pixel-perfect match would
  still benefit from clean per-type posters without baked logo slots/icon rows.

---

## Task: Series List Screen — structural rebuild (hero + variant cards) (2026-06-27)

### Summary
Structural rebuild (not opacity tweaks). Replaced the single generic poster
card + generic banner with a dedicated featured-hero poster widget and
variant-based card layouts, and fixed the root cause of the ghost circles: the
bundled `new-design/*.webp` CARD art bakes in placeholder logo circles + a
calendar/clock/pin icon row. Per the brief's point 9/10, the cards no longer use
that template art — they layer a CLEAN local stadium image (`SAsset.listCardBg`,
verified no baked placeholders) + theme-aware readability gradient + per-variant
tint, and render every identity element (trophy/shield emblem, team logos,
strips, badges) as our own widgets on top. Background stays visible; no ghost
placeholders can render. No data/API/classification changes.

### Structural changes (`series_poster_cards.dart` rebuilt)
- `SeriesPosterVariant` enum + `resolveSeriesPosterVariant()` (tournament /
  league / bilateralUpcoming / bilateralOngoing / bilateralCompleted).
- `SeriesPosterCard` now dispatches to variant layouts:
  - `_PosterLeftCard` (tournament / league / finished competition): big glowing
    trophy/shield emblem on the LEFT (radial bloom, not a hard "generic
    circle"), title + team-logo strip (+N) + meta + type tag + CTA on the RIGHT.
  - `_BilateralCard` (bilateral upcoming/ongoing/completed): title LEFT, two
    real team logos RIGHT with a shield emblem (or trophy crest for completed)
    between them, meta + CTA on the bottom row. Completed gets a muted purple
    tint + grey-cyan CTA.
- `SeriesTeamLogoCircle`: reusable, returns `SizedBox.shrink()` for invalid
  teams (no empty circles), subtle glow, logo fills the circle (flags BoxFit
  cover via `TeamLogoWidget`).
- `_PosterFrame`: clean stadium art + colour wash + `heroOverlayColors`
  readability gradient + cyan border/glow. Background visible, not blacked out.
- Responsive via `LayoutBuilder`: emblem/logo sizes, paddings and fonts scale
  down for <360 / <320 widths (OnePlus 10 Pro); FittedBox on strips/meta so
  nothing clips or overflows.
- `SeriesFilterChipBar`: always 4 clean gradient/glass pills (active = cyan→blue
  + glow + white; inactive = dark glass + cyan border), even spacing, no clip.

### Dedicated hero
- New `SeriesFeaturedHeroPoster` (+ `.fromAdmin` / `.fromSeries`) replaces the
  old `_SeriesHeroBanner`. Fixed responsive height (158/172/188), trophy top
  centre, overline + cyan main word + cyan year, bottom format pill, big team
  logo circles + names for bilateral, trophy + "N Teams" pill for tournament/
  league (no fake matchup). Old `_SeriesHeroBanner` + helpers removed from
  `series_list_screen.dart`.

### Files changed
- `lib/screens/series/widgets/series_poster_cards.dart` (full rebuild).
- `lib/screens/series/series_list_screen.dart` (use new hero; removed old hero
  block + unused `cached_network_image` import).

### Commands run
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.
- Web/Chrome: NOT configured (no `web/` dir) — not run, not claimed.

### Remaining visual limitation
- All cards share one clean stadium background (differentiated by tint + emblem
  + layout) because the per-type `new-design` posters bake in placeholder
  circles/icons that can't be cleanly shown. Truly distinct per-type background
  art would need clean per-template poster assets WITHOUT baked placeholder
  logo slots / icon rows.

---

## Task: Series List Screen — kill baked-template artifacts (pass 4) (2026-06-27)

### Summary
Closed the last visible gap vs the target: the bundled card `*.webp` assets are
TEMPLATE art that bakes in placeholder logo circles + a calendar/clock/pin icon
row. Those bled through the earlier veil as stray empty circles / ghost icons on
the tournament + completed/bilateral cards. Strengthened the veil so the baked
template elements disappear, leaving clean dark premium cards with only our own
logos/emblems/text. No data/API/filter changes.

### Visual issue fixed
- Stray empty circles + ghost calendar/clock/pin icons (baked into the asset
  template) are now hidden under a near-opaque vertical veil
  (`.5 → .93 → .97`, top band lighter so a subtle stadium glow + tint remain).
- Softened the left trophy/shield emblem glow for a cleaner look.

### Tradeoff / note
- The real bundled assets are template/placeholder art, not the rich per-card
  posters in the mockup. Showing them at full strength exposes the baked
  placeholders, so they are intentionally muted; card identity now comes from
  the rendered emblem (trophy/shield), team logos, type label and tint. A
  pixel-identical match to the mockup art would require clean per-template
  poster assets.

### Files changed
- `lib/screens/series/widgets/series_poster_cards.dart` (veil opacity + emblem
  glow).

### Commands run
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.
- Web/Chrome: NOT configured (no `web/` dir) — not run.

---

## Task: Series List Screen — target-match pass 3 (chips, veil, tournament emblem) (2026-06-27)

### Summary
Pushed the Series LIST screen closer to the target. Root problem this pass: the
bundled `*.webp` card/chip assets have baked-in decorative rings/lines that
clashed with overlaid content (stray "empty circles") and the chip art stretched
into stitched artifacts. Fixed by muting the asset art under a strong veil,
drawing clean gradient chips, and rendering our own trophy/shield emblem for the
tournament/league "poster-left" visual. No backend/filter/data-logic changes.

### Visual differences fixed
- **Filter chips**: dropped the stretched chip image (stitched-edge artifacts) →
  clean gradient/glass pills matching the target. Active = cyan→blue gradient +
  glow + white label; inactive = dark glass + cyan border + muted label. Equal
  40px height, even spacing, L/R padding so the selected chip is never cut. Four
  chips only.
- **Broken "empty ring" circles** on cards (baked into the asset art): cards now
  use a strong diagonal veil (`.62→.9`) that mutes the baked rings/lines to a
  faint texture while keeping the atmospheric hue (purple for completed). Our
  own clean logos/emblems are the only circles.
- **Tournament / League cards** now read as posters: a rendered glowing trophy
  (tournament / completed competition) or shield (league) emblem on the LEFT,
  title + small team-logo strip (+N) + meta + `[type tag] [Explore Series]` on
  the right. No VS, no two-team fixture identity. Taller (minHeight 178).
- **Completed competitions** (e.g. finished IPL / Asia Cup) now use the
  poster-left trophy layout instead of a franchise "X vs Y" fixture; completed
  bilateral tours keep two real team logos with a trophy crest between them.
- **Type label truncation** ("Tour…") fixed — the type tag is wrapped in a
  scale-down FittedBox so it shrinks instead of ellipsising.
- **Bilateral**: smaller CTA (height 32), compact 40–44px team logos with a
  subtle shield emblem between them, meta + CTA on one bottom row, all inside
  the card.
- **Hero**: format summary now rendered as a bottom pill ("3 T20Is • 3 ODIs")
  like the target; tournament/league heroes keep the trophy + "N Teams" style
  (no fake matchup); bilateral heroes keep both real team logos.

### Card templates updated
- `_PosterLeftBody` (new): tournament, league, completed-competition.
- `_BilateralBody`: bilateral tours + completed bilateral tours.
- `_LeftEmblem` (new) rendered crest; `_isCompetition()` helper routes completed
  leagues/tournaments to the poster-left layout.

### Filter chip changes
- Image assets no longer used for chip fill (kept declared, just unused); clean
  Container gradient styling per the task's allowance.

### Hero changes
- Added `_HeroFormatPill`; format text → pill. Type-aware team/trophy logic from
  the previous pass retained.

### Files changed
- `lib/screens/series/widgets/series_poster_cards.dart` (rewritten).
- `lib/screens/series/series_list_screen.dart` (hero format pill).

### Commands run
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.
- Web/Chrome: NOT configured (no `web/` directory) — not run, not claimed.

### Remaining visual limitations
- The real bundled assets are atmospheric backgrounds (galaxy/castle/stadium),
  not the rich trophy/league posters in the target mockup, and they carry baked
  decorative rings. To avoid those reading as broken circles the art is muted,
  so the cards rely on the rendered emblem + content for the poster feel rather
  than the asset's own art. A pixel-identical match to the mockup would need
  cleaner per-template poster assets.
- 360dp verified structurally (FittedBox/Expanded/LayoutBuilder); an on-device
  screenshot pass is still recommended (no emulator/web here).

---

## Task: Series List Screen poster redesign — clipping/layout pass 2 (2026-06-27)

### Summary
Fixed the visual/clipping problems in the Series LIST poster cards and aligned
them much closer to the target. No backend / filters / data logic / other
screens touched.

### Exact visual issues fixed
- **Horizontal clipping / overflow**: the tournament/league team-logo strip
  (5×30 logos + overflow chip ≈ 210px) overflowed its ~190px content column.
  Logos shrunk to 26px, capped at 5, and the strip + every metadata row are now
  wrapped in a left-aligned `FittedBox(scaleDown)` so they can never overflow.
- **Oversized "merged circle" on bilateral/completed**: was caused by
  `PremiumTeamLogo`'s large cyan halo (`blur = size*0.25`). Switched the team
  pair to the plain `TeamLogoWidget` (subtle drop shadow only) at 40–44px so the
  cluster stays compact and inside the card.
- **CTA buttons touching / clipped at the right edge**: removed the CTA glow
  shadow, gave cards 15–16px right padding, and moved the bilateral/completed
  CTA onto the metadata row (Expanded meta + CTA) so it sits well inside the
  card and never corner-clips.
- **Empty/broken placeholder circles** (MLC/tournament): teams are now filtered
  with `_isShowableTeam` (must have a real logo OR a non-placeholder code), so
  logo-less blank circles never render; the strip is hidden if <2 real teams.
- **Metadata over-truncation**: items use `softWrap:false` inside a scale-down
  FittedBox instead of hard per-item ellipsis, so the row shrinks gracefully and
  stays readable rather than showing "Bilateral Seri…".
- **Filter chips**: active chip art now fills the rounded pill with
  `BoxFit.fill` inside a `Clip.antiAlias` container (no stray inner asset
  edges); chip row has L/R padding so the selected chip is never cut.
- **Featured hero respects series type**: tournament/league derived heroes no
  longer show a random two-team matchup — they hide the side team columns and
  show a larger trophy crest + optional "N Teams" pill. Admin-configured hero
  teams are still honoured.

### Card layouts updated
- Tournament/League: poster art reserved on the LEFT (`LayoutBuilder` inset,
  clamped 78–116px), title + filtered team-logo strip (+N) + meta row, then a
  bottom row of `[type tag]  [Explore Series]`. Taller card (minHeight 172).
- Bilateral/Completed: title left, compact team pair right (trophy crest between
  for completed), then `[meta row]  [View Series]`. Compact card (minHeight
  132).

### Asset fit/crop changes
- Filter chip art: `BoxFit.cover` → `BoxFit.fill` inside a rounded clip.
- Card/hero poster backgrounds remain `BoxFit.cover`, full opacity both themes,
  with `errorBuilder` fallback (no broken images).

### Files changed
- `lib/screens/series/widgets/series_poster_cards.dart` (rewritten card bodies,
  team strip/pair filtering, FittedBox safety, CTA pill, filter chip fill).
- `lib/screens/series/series_list_screen.dart` (hero now type-aware: `twoTeams`
  + `teamCountText`, `_HeroTrophy`, `_HeroTeamCountPill`).

### Commands run
- `flutter analyze lib/` — No issues found.
- `flutter test` — 137/137 passed.
- `flutter run -d chrome` — NOT possible: the project has no `web/` target
  ("This application is not configured to build on the web"). Adding web support
  (`flutter create .`) would alter this production Android project's structure,
  so it was not done. Verified instead via analyze + full test suite.

### Remaining visual limitations
- Exact alignment of overlaid content against each poster's baked-in artwork
  can't be pixel-verified without seeing the rendered assets; the scrim +
  reserved-inset approach keeps text legible regardless.
- A 360dp on-device screenshot pass is still recommended (no emulator/web here),
  though all rows are now overflow-safe via FittedBox/Expanded.

---

## Task: Series List Screen poster redesign (2026-06-27)

### Summary
Redesigned the Series LIST screen visuals only so every item reads as a SERIES
poster (tournament / league / bilateral / completed), not a match fixture. Used
the new bundled artwork under `assets/images/series/new-design`. Filter logic,
detail screens, Home/Matches/Schedule, score system, and the shared bottom nav
were left untouched.

### What changed
- New `lib/screens/series/widgets/series_poster_cards.dart`:
  - `SeriesCardTemplate` enum + `seriesTemplateOf(SeriesView)` classifier
    (completed status wins → completed; league/domestic → league; multi-team
    cups/championships → tournament; genuine `tour of` 2-team series →
    bilateral).
  - `SeriesPosterCard` adaptive widget — full-bleed poster background (treated
    like marketing posters, full opacity both themes, `errorBuilder` fallback so
    no broken image), legibility scrim, white-on-image content:
    - Tournament/League: poster art reserved on the LEFT (LayoutBuilder inset),
      title + representative team-logo strip (`+N` overflow) + meta + "Explore
      Series" CTA on the right.
    - Bilateral/Completed: title left, two team logos right (trophy crest in
      the middle for completed), meta + "View Series" CTA. Completed uses the
      muted `completed_series_card.webp` for a distinct look.
  - Asset-backed `SeriesFilterChipBar` (exactly 4 chips: All / Ongoing /
    Upcoming / Completed) using `filter_chip_active/inactive.webp`.
  - Metadata items are dropped when empty (no `TBD vs TBD`, no fake values).
- `series_list_screen.dart`: list now renders `SeriesPosterCard`; filter row now
  `SeriesFilterChipBar`; hero `_HeroBackground` default art switched to
  `series_hero_banner.webp` (admin network image still wins — admin priority).
- `series_components.dart`: added `SeriesView.teamCount` getter (real provider
  team count; never fabricated) for the "N Teams" meta + "+N" logo overflow.
- `pubspec.yaml`: declared `assets/images/series/new-design/`.

### Asset cleanup (none — verified unsafe to remove)
- Old `SAsset` background webps (`detailHeroBg`, `matchCardBg`, `listCardBg`,
  `overviewPanelBg`, `statsTableBg`, `squadSectionBg`, `emptyStateBg`,
  `topBackdrop`) are STILL referenced by the Series DETAIL screens and/or the
  retained `SeriesListCard`/`SeriesCategoryChips` widgets (covered by
  `test/series_card_test.dart` + `test/series_layout_test.dart`). Removing any
  would break detail screens or tests, so nothing was deleted. New assets are
  purely additive.

### Commands run
- `flutter pub get` — OK.
- `flutter analyze lib/` — No issues found.
- `flutter test test/series_card_test.dart test/series_layout_test.dart` —
  7/7 passed.

### Risks / notes
- New poster backgrounds render at full opacity in BOTH themes (documented
  marketing-poster exception in the index). In light mode these cards therefore
  read dark with white text — intended to match the dark premium target.
- Bottom nav background asset (`bottom_nav_bar.webp`) was NOT wired: the bottom
  nav is a shared/global component and changing it risks regressions on other
  tabs. Left as-is per the task's safety guidance.
- Visual QA on a 360dp device still recommended (no emulator run here).

---

## Task: Release AAB Build for Play Console (2026-06-17)

### Summary
Built the release Android App Bundle after freeing C: drive space. The build uses
Play Console package name `com.cric.pro`, app version `2.0.1`, version code `13`,
and the provided production dart-defines.

### Files Changed
- `AI_TASK_LOG.md` - documented the successful release AAB build.

### Commands Run
- `flutter build appbundle --release --dart-define=CRICKET_API_KEY=... --dart-define=CRICKET_PACKAGE_NAME=com.cric.pro --dart-define=CRICKET_APP_VERSION=2.0.1 --dart-define=ONESIGNAL_APP_ID=...`

### Test Results
- Release AAB built successfully:
  `build/app/outputs/bundle/release/app-release.aab` (57.3 MB).
- Verified config:
  - `pubspec.yaml` version: `2.0.1+13`
  - Android namespace/applicationId: `com.cric.pro`

### Pending Issues
- None.

---

## Task: Live-score static verification + overs/headers cleanup (2026-06-15)

Static pass after `/app/live-scores` deployed (no live match available to test
speed). Verified existing behavior, fixed two real gaps (backend overs + headers).

### 1-3. Flutter live-only polling (verified, no change needed)
- `_overlayFastLiveScores` collects ids ONLY from `m.isLive` matches in
  `_tabData` + `_heroData`, and returns early when the set is empty → the fast
  endpoint is NOT called when nothing is live. ✓ (item 1)
- When a live match completes, the fresh object flips `isLive=false`
  (`status=completed`), so the NEXT tick excludes it → polling stops for that
  match. ✓ (item 2)
- `CricketMatch.mergeLiveScore` copies `status`, `statusText`, `resultText`,
  and the `isLive/isUpcoming/isFinished` flags from the fresh completed object,
  preserving stream/logo/title metadata → completed status/result merges safely
  into the Home card. ✓ (item 3)

### 4. Overs normalization (49.6 -> 50.0)
- Flutter display ALREADY normalizes via `normalizeOversText`
  (`api_models.dart:615`): balls roll over at 6, so 49.6→50.0, 19.6→20.0. The
  Home score formatter uses it. ✓
- ADDED matching normalization in the BACKEND projection
  (`/app/live-scores`): new `normalizeOvers` + `projectInnings` so the response
  body itself shows `50.0`, not raw `49.6`. Body + display now agree.

### 5. A-team code formatting (verified, no change)
- `formatWomenCode` (`home_featured.dart:700`) already maps `INDA→IND A`,
  `SLA→SL A` (regex `^([A-Z]{2,})A$`), plus `…W` and `…U19`. Applied via
  `homeTeamCode` on every Home card/hero. ✓

### 6. Result pill status_text fallback (verified, no change)
- All three finished renderers already fall back to `statusText` when
  `resultText` is empty (`home_match_cards.dart:403-405`, `:974-976`,
  `:1189-1191`). So "Match tied (Sri Lanka A won the Super Over)" from
  `status_text` shows on the finished card. ✓

### 7. Backend debug headers
- ADDED `X-Cache` (aggregate HIT/MISS/STALE/ERROR across requested ids) and
  `X-Score-Key` (compact, log-safe combined score string, single-line ASCII,
  capped 400 chars). `X-Cache-Age-Ms` + `X-Stale` already present.
- These complement the body fields (`cacheStatus`, `cacheAgeMs`) for curl/CDN
  debugging. The earlier curl only showed `x-cache-age-ms` because `X-Cache`/
  `X-Score-Key` weren't emitted yet — now they are.

### 8. Match Details untouched
- All changes are in `/app/live-scores` + Home Flutter only. `/match/:id`,
  `/app/match/:id`, and Match Details polling are unchanged. ✓

### Results
- `flutter analyze lib/` → No issues found.
- `node --check src/routes/app.js` → OK.

### Files Changed
- `cricket-api/src/routes/app.js` (overs normalization + X-Cache/X-Score-Key)

---

## Task: Home fast live score freshness pass (2026-06-15)

### Current confirmed state
Flutter applies score updates correctly (setState-Future bug fixed in the prior
task). The remaining lag was a DATA-SOURCE problem, not a Flutter problem.

### Reason for remaining lag (root cause)
Backend investigation (full route/cache/provider map):
- Home's score data came from the heavy `/app/home` aggregate, whose `homeData`
  cache TTL is **30s** (stale window +15s → up to ~45s old).
- Even `/matches/live` (SWR logical **8s**) pulls Cricbuzz's **`/api/home`**
  aggregate blob (`getLiveMatches` → `getHomeMatches` → `/home`), NOT the fast
  per-match `/livescore/{id}` endpoint. The `/api/home` blob itself updates
  slowly.
- So scores were 1-2 balls behind because the SOURCE endpoint + cache were slow,
  and Flutter was polling the heavy aggregate.

### Endpoint comparison (which provider call is fast)
From the provider map:
- `getMatchInfo(id)` → Cricbuzz `/mcenter/livescore/{id}` → `miniscore` →
  advances within a ball. **Fastest reliable score-only source.**
- `getLiveLine(id)` → aggregates livescore+comm+balls-map → also fast but heavier.
- `getHomeMatches` → `/api/home` → slow aggregate (what Home used before).
Chosen: **`getMatchInfo` / `/livescore/{id}`** for the new lightweight endpoint.

### New lightweight live-score endpoint
`GET /app/live-scores?ids=156146,...` (added in `cricket-api/src/routes/app.js`):
- Per-id fetch via `getMatchInfo`, projected to score-only fields
  (`match_id, status, status_text, result, current_innings, target,
  rem_runs_to_win, current/required RR, team1/team2{id,name,short_name,innings}`).
  No series/images/streams/ads/featured/admin config.
- Dedicated tiny Redis cache `livefast:<id>`, logical TTL `LIVE_SCORE_FAST_TTL_MS`
  (default **4000ms**), physical TTL = logical + 11s grace (`setex`, works on
  ioredis + in-memory fallback).
- **Per-id single-flight** (`liveScoreInflight` Map) so many polling clients
  collapse to one provider call.
- Serves stale cached score on provider error rather than nothing.
- Request fan-out capped at 12 ids.
- Response shape matches the normalized match-detail shape, so the Flutter
  `CricketMatch.fromJson` parser maps it unchanged.

### Cache / HTTP header changes
- `/app/live-scores` added to the server.js `onSend` live-family list →
  `Cache-Control: no-store, no-cache, must-revalidate, max-age=0` + `Pragma`.
- Response headers: `X-Cache-Age-Ms`, `X-Stale` (when any id served stale).
- Did NOT touch the 30s `/app/home` or 8s `/matches/live` TTLs (membership feeds
  can stay slower); only the dedicated score endpoint is fast.

### Flutter polling / merge changes (`home_screen.dart`)
- New `_overlayFastLiveScores()`: collects visible LIVE ids (tab list + hero),
  calls `repository.liveScores(ids)`, overlays via `CricketMatch.mergeLiveScore`
  (score/status/result + live flags only; preserves streams/logos/title/venue).
  Repaints only when `homeVisibleScoreKey` actually moved → no blink, scroll +
  carousel position preserved.
- `_silentPoll` restructured: **every tick** runs the cheap fast overlay; the
  **heavy membership refresh** (full list + hero re-resolve, detects matches
  starting/finishing) is throttled to every `_kMembershipEveryNTicks` (=4) ticks.
- Poll interval **8s → 4s** for live (matches backend 4s cache). 4s × 4 ticks =
  heavy feed only every 16s; scores every 4s.
- Immediate refresh (first paint / resume / tab re-entry / recovery) runs a full
  pass (tick 1 forces membership + overlay).
- `CricketMatch.mergeLiveScore(fresh)` added (`cricket_match.dart`):
  overlays only live-mutable fields.
- `CricketApiService.liveScores(ids)` + `CricketRepository.liveScores(ids)`
  (no client cache — backend already 4s single-flight).

### Logs added (kDebugMode / debugPrint, no secrets)
Flutter:
- `CricProHomeLiveScore: ids=[...] fetched=N listChanged=.. heroChanged=.. applied=.. sample=SLA 190/5 (31.0) | ... cacheTtl=..`
- `CricProHomePoll: membership tab=.. listChanged=.. applied=..` (throttled).
Backend (`LIVE_SCORE_FAST`, winston info):
- `LIVE_SCORE_FAST: match=156146 route=/app/live-scores cache=MISS age=0 provider=getMatchInfo providerMs=430 score=SLA 190/5 (31.0) | WI 44/1 (5.3) [live]`
- `... cache=HIT age=2500 score=...`  /  `... cache=STALE ...`  /  `... cache=ERROR err=..`

### analyze / node-check results
- `flutter analyze lib/` → **No issues found.**
- `node --check src/routes/app.js`, `src/server.js` → OK.

### Verify on VPS / device
Backend (VPS), watch a live match id:
```
# tail API logs for the fast endpoint
pm2 logs cricket-api | grep LIVE_SCORE_FAST
# or hit it directly every 2s and eyeball freshness vs Cricbuzz
watch -n2 'curl -s "http://localhost:PORT/app/live-scores?ids=156146" \
  -H "x-api-key: $API_KEY" | jq ".data[0].team1,.data[0].team2,.meta"'
```
Compare `cache=MISS providerMs` score vs Cricbuzz. If provider score is fresh
but Home is late → Flutter; if provider itself is late → Cricbuzz `/livescore`
source (then we'd try getLiveLine/quick-access). Tune `LIVE_SCORE_FAST_TTL_MS`
env if needed.

Device (debug build), logcat:
```
adb logcat | grep -E "CricProHomeLiveScore|LIVE_SCORE_FAST"
```
Expect `applied=true` + advancing `sample=` score every ~4s during live play.

### Files Changed
Backend:
- `cricket-api/src/routes/app.js` (new `/app/live-scores` + helpers + logs)
- `cricket-api/src/server.js` (no-store list += `/app/live-scores`)
Flutter:
- `lib/services/cricket_api_service.dart` (`liveScores`)
- `lib/repositories/cricket_repository.dart` (`liveScores`)
- `lib/models/cricket_match.dart` (`mergeLiveScore`)
- `lib/screens/home/home_screen.dart` (fast overlay, throttled membership, 4s,
  logs)

---

## Task: Home setState Future polling fix (2026-06-15)

### Exact setState callback that returned a Future
Two arrow-form callbacks in `home_screen.dart`:
```dart
setState(() => _tabFuture = Future.value(fresh));
```
- `_silentPoll` (the changed-list apply path).
- `_armRecovery` (the recovery apply path).

An arrow body `() => x = expr` RETURNS the assigned value. Here that value is a
`Future`, so `setState` received a callback returning a `Future` → Flutter
throws `setState() callback argument returned a Future`. Every poll tick that
detected a real score change (`listChanged=true`) threw at apply time, so the
new score was never committed and the screen looked frozen. The throw was then
mis-classified as an offline failure and armed recovery.

### How it was fixed
Switched both to block bodies so nothing is returned:
```dart
setState(() { _tabFuture = Future.value(fresh); });
```
Audited every other Home `setState`:
- `_heroIds = ids` (arrow) → returns a `Set`, not a Future — safe.
- `_applyFeedConfig`, `_setTopTab`, `_refresh`, `_refreshHeroSilently` → all
  block bodies that ASSIGN futures (assignment inside a block isn't returned) —
  safe, left as-is.

### Why FlutterError was incorrectly treated as offline
The `_silentPoll` catch armed recovery for ANY exception and logged
"offline?". A `FlutterError` (the setState-Future throw) is a code bug, not a
connectivity problem, so recovery looped pointlessly. Fix:
- Classify `FlutterError` / `AssertionError` as `code_bug`.
- Do NOT `_armRecovery()` or bump `_consecutivePollFailures` for code bugs; do
  not cancel the poll timer (next tick can still succeed).
- Only `network` / `timeout` / `parse` / unknown arm recovery.
- Logs `CricProHomePoll: CODE BUG — not arming network recovery`.

### Updated poll logs expected
Per tick:
```
CricProHomePoll: tick tab=0 listChanged=true applied=true prevLen=1 newLen=1
CricProHomePoll: scoreKeyOld=[...163/5 (25.2 OV)...]
CricProHomePoll: scoreKeyNew=[...166/5 (26.4 OV)...]
CricProHomeCard: live build id=156146 score=[265/10 ... | 166/5 ...]
```
No more `setState() callback argument returned a Future`. If `scoreKeyNew`
stays identical across many ticks while `applied`/`changed=false`, Flutter is
NOT frozen — backend/provider is returning the same score (investigate backend
separately, no code change yet).

### Score mapping confirmed working
Yes — real live match `156146` maps correctly:
`CricProHomeCard: live build id=156146 score=[265/10 (49.2 OV) | 163/5 (25.2 OV)]
status=Sri Lanka A need 103 runs`. The earlier `score=null` was the removed
manual match 148382. Score-null mapping work from the prior pass is not the
current issue; the parser widening stays in place as a safety net.

### Files Changed
- `lib/screens/home/home_screen.dart` (setState block bodies, error
  classification, tick/scoreKey logs).

### Commands Run
- `flutter analyze lib/` — No issues found.

---

## Task: Home live score mapping + visible score key fix (2026-06-15)

### Why oldScore/newScore were empty
The hero debug log printed `freshHero.first` — the PRIMARY carousel card. The
primary (heroId=148382) was an admin `/app/home` `topFeaturedMatches` entry
flagged `status=Live` but carrying NO score fields. The `_overlayLiveScores`
step only matched heroes against `/matches/live` by id; that match id was NOT
present in `/matches/live` (it was `overlaid 2/5` — 148382 was one of the 3
NOT overlaid), so the hero kept the stale empty `/app/home` object. The score
key was correct all along — `teamAScoreText`/`teamBScoreText` are exactly what
the UI renders. The freeze was a DATA-PATH problem (stale source object), not a
key problem.

### Exact fields Home UI uses for score
Verified by grep — every Home score widget renders:
- Team A/B score: `match.teamAScoreText` / `match.teamBScoreText`
  (`_HomeTeamBlock`, `_HeroTeamBlock`, `_CompactTeam` all take `score:` from
  these; `_cleanTeamScore` strips the team code, splits `runs/wkts` from
  `(overs OV)`).
- Status / equation note: `match.statusText`.
- Result / winner: `match.resultText`.
- There is NO separate overs field — overs live inside the score string.

### Shared visible-score key
- New `homeVisibleScoreKey(CricketMatch)` in `home_featured.dart`:
  `id|status|statusText|resultText|teamAScoreText|teamBScoreText`.
- `_refreshKey` now delegates to it (single source of truth for both list diff
  and `_heroListKey` hero diff), so a key can never omit a rendered field.

### Parser / mapping fix (`cricket_match.dart`)
- `_scoreMap` now also probes top-level `matchScore` / `scorecard` / `scores` /
  `liveScore` containers, and widened per-team score keys
  (`team1score`, `batTeamScore`, `homeScore`, `bowlTeamScore`, `awayScore`).
- `_team` now extracts innings from nested `score` / `scr` / `scores` objects or
  lists when the team object has no `innings` list (live shapes), via
  `_innsFromScoreMap`.
- Diagnostic `CricProHomeScoreMap` log (kDebugMode): when a LIVE match parses to
  an EMPTY score, dumps top-level keys + score-shaped keys + raw `score`/`team1`/
  `team2` so the real shape is visible on-device. No urls/keys/headers.

### Hero overlay fix (`home_screen.dart`)
- `_overlayLiveScores` now indexes ids from live (0) → recent (2) → upcoming (1)
  with `putIfAbsent` (live wins) and overlays heroes from ANY of them, so a hero
  flagged live in `/app/home` but absent from `/matches/live` still gets a fresh
  scored object. Logs a per-hero WARN when a hero stays LIVE+empty after overlay
  (points at parser or a feed gap).

### List + refresh key fix
- Both list diff (`_silentPoll`) and hero diff use `_refreshKey` →
  `homeVisibleScoreKey`. Any visible change flips `listChanged`/`changed` true →
  `setState`.

### Immediate force-fresh refresh (already in place, confirmed)
- First paint (post-frame), app resume, Home-tab re-entry, offline→online
  recovery all run `_silentPoll` / `_loadTabMatches(forceRefresh: true)` /
  `_resolveHero(forceRefresh: true)`. `forceRefresh` clears the repo cache entry
  before fetch, so Home live polling bypasses stale cache. Match Details
  untouched.

### Error classification (`home_screen.dart`)
- `_silentPoll` catch now classifies: `network` (SocketException/HttpException),
  `timeout` (TimeoutException), `parse` (FormatException), else the runtime type.
  Logs `errType=… msg=<first line>` instead of always "offline?". Added
  `dart:io` import.

### Debug logs (kDebugMode only, debugPrint, no urls/keys/headers)
- `CricProHomeScoreMap` — new: live match parsed empty score, raw shape.
- `CricProHomeHero` — richer: per-hero `id(CODE score | CODE score st=status)`
  list + old/new primary score (`empty` sentinel when blank).
- `CricProHomePoll` — error type + message class on failure.
- `CricProHomeCard` — retained.

### Small visual fixes
- Hero score bumped again: small 25→28, normal 30→33, wide 35→38. Overs stay
  proportional + muted; FittedBox safety only.
- Code-only Home cards + Women/A/U19 suffix spacing (`formatWomenCode`) +
  `homeShortStatus` shortening already landed in the prior pass; unchanged here.

### Files Changed
- `lib/models/cricket_match.dart` (parser widening + diagnostic + foundation import)
- `lib/screens/home/home_screen.dart` (overlay, key delegation, error class, dart:io)
- `lib/screens/home/widgets/home_featured.dart` (`homeVisibleScoreKey`)
- `lib/screens/home/widgets/home_hero.dart` (hero score size)

### Commands Run
- `flutter analyze lib/` — No issues found.

### Next device test
Watch logcat for `CricProHomeScoreMap`. If it fires for 148382, the live JSON
shape is still uncovered — paste the dumped `topKeys`/`scoreKeys` and I extend
the parser to those exact field names. If `CricProHomeHero: WARN ... EMPTY
after overlay` fires WITHOUT a ScoreMap line, the match id is simply absent from
all match feeds (admin featured a match the match API doesn't return).

---

## Task: Final Home premium polish + fast score refresh pass (2026-06-15)

### Summary
Third Home pass: removed secondary full team names from all Home cards
(code-first like the target), generalized the short-code formatter to Women/A/
U19 with a space (`INDW`→`IND W`, `INDA`→`IND A`, `INDU19`→`IND U19`), and made
the Home live score refresh immediately instead of waiting for the 8s tick.

### Hero score size
- (Carried from prior pass + kept) `_HeroMetrics` score small 25 / normal 30 /
  wide 35; overs proportional (×0.46) muted cyan; FittedBox safety only.

### Full team names removed from Home cards
- `_HomeTeamBlock`: dropped the secondary name under the code (code + score +
  overs only). `showFullName` retained for API stability.
- `_MiniTeam` (featured/upcoming mini): code only, no secondary name.
- Hero already code-only.

### Women / A / U19 short-code formatter
- `formatWomenCode` rewritten as a general suffix spacer: `^([A-Z]{2,})U19$` →
  `… U19`, `…W$` → `… W`, `…A$` → `… A`. Base ≥2 letters so `WI`/`SA` never
  split; placeholders (TBC/TBD) and already-spaced codes untouched.
- `homeTeamCode(short, name)` applied to hero, rich, compact, mini blocks and
  the fallback team-vs-team title (`NZ W vs SL W`, `IND A vs SL A`).

### Short status formatter
- `homeShortStatus`: swaps full team names → codes, drops "runs" filler
  (`West Indies need 126 runs in 87 balls` → `WI need 126 in 87 balls`).
  Applied to hero pill, live rich note, compact note.

### Short series title formatter
- `homeShortSeriesTitle`: exact map (Women's T20 WC 2026, CWC League Two, MP
  Premier League 2026) + generic ICC-prefix stripping. Used by `_heroTitle` and
  the mini-card title (1 line).

### Meta row rules (unchanged from prior pass, kept)
- Upcoming: date/time only. Live: `Venue • Date Time` (venue ≤16 chars else
  date/time). Finished: date/time + short format. Single `_CardMetaLine`.

### Home immediate refresh
- `_kickImmediateRefresh(reason)` runs a one-shot silent `_silentPoll` outside
  the cadence. Fired on: first paint (post-frame in `initState`), app resume
  (`didChangeAppLifecycleState`), and Home-tab re-entry.
- Tab re-entry wired via `ValueListenable<int> reentrySignal` from the root
  shell (`_homeReentrySignal`, bumped in `_switchTab`; bottom nav now routes
  through `_switchTab`). Avoids leaking Home's private State. Disposed on both
  sides.
- Existing `_silentPoll` guard (`_polling`) makes the kick idempotent; no
  loader, no blink (key-gated repaint), scroll preserved (`_restoreScroll`).

### Home score key
- `_refreshKey` now `id|status|statusText|resultText|teamAScore|teamBScore`
  (score strings already carry runs/wickets/overs), so any visible change
  triggers a repaint. Used by both list and hero (`_heroListKey`) diffing.

### Debug logs (kDebugMode only)
- Added `CricProHomePoll: immediate refresh (<reason>)`. Existing poll/hero/card
  logs retained. No URLs/keys/headers logged.

### Files Changed
- `lib/screens/home/home_screen.dart`
- `lib/screens/home/widgets/home_match_cards.dart`
- `lib/screens/home/widgets/home_featured.dart`
- `lib/main.dart` (root shell reentry signal wiring)

### Commands Run
- `flutter analyze lib/` — No issues found.

---

## Task: Home text hierarchy + short naming polish pass (2026-06-15)

### Summary
Second Home polish pass focused on text hierarchy and trimmed-text removal to
match the premium target. Women team codes/names now read with a space before
`W` (`INDW` → `IND W`, `NZW` → `NZ W`). Long full names are suppressed on cards
when they would ellipsis (code stands alone). Meta rows collapsed from a cramped
3-column truncated row to a single clean line (or removed entirely on upcoming).
Hero score enlarged, hero/list status text shortened with team codes and made
crisp, and list-card glow reduced another notch.

### Women code / name formatting
- New helpers in `home_featured.dart`: `formatWomenCode`, `formatWomenName`,
  `homeTeamCode`, `homeShortSeriesTitle`, `homeShortStatus` (+ existing
  `normalizeWomenTeamName`, `homeTeamShortName`).
- `formatWomenCode`: `INDW`/`PAKW`/`NZW`/`SLW`/`ENGW`/`IREW`/`AUSW`/`BANW`/`RSAW`
  → spaced `… W`; leaves men's codes and short `WI`/`SA` untouched.
- Applied `homeTeamCode` to `_HomeTeamBlock`, `_CompactTeam`, `_MiniTeam`,
  `_HeroTeamBlock`.
- Fallback team-vs-team title now women-spaced (`NZ W vs SL W`) via `_heroTitle`.

### Long team name removal
- `homeTeamShortName` threshold tightened (>12 chars → code only). USA/long
  names show code only; no ellipsis full names on cards.

### Short series title
- `homeShortSeriesTitle`: `ICC Women's T20 World Cup 2026` → `Women's T20 WC
  2026`, `… League Two 2023-27` → `CWC League Two`, `Madhya Pradesh Premier
  League 2026` → `MP Premier League 2026`, plus generic ICC-prefix stripping.
- Featured upcoming mini-card title now 1 line, cyan, smaller (12 → 11.5).

### Meta row simplification
- Removed `_CardMetaRow` (3-column truncated). Added `_CardMetaLine` +
  `_cardMetaText`.
- Live: `Venue • Date Time` when venue ≤16 chars, else date/time only.
- Upcoming: date/time only (no venue / match number).
- Finished: date/time, plus short match format when ≤12 chars.

### Hero score size
- `_HeroMetrics` score: small 23→25, normal 27→30, wide 31→35. Overs stay
  proportional (×0.46) and muted cyan; FittedBox still guards overflow.

### Status pill shortening / readability
- `homeShortStatus`: `West Indies need 126 runs in 87 balls` → `WI need 126 in
  87 balls`; `India Women opt to bat` → `IND W opt to bat`. Drops "runs" filler,
  swaps names→codes.
- Applied to hero pill, live rich card note, compact card note.
- `_HeroCenterPill`: maxWidth 220→260, `small` font 10.5, dark `#05172b` bg,
  `#d6f6ff` text (carried over from prior glow fix).

### Glow reduction / height
- `_HomeCardShell` border .22→.18; shell padding 12→11.
- `_TopCyanHighlight` alpha .32/.4 → .22/.28.
- `_FeaturedMatchMini` border .38→.2, heroShadow→soft black drop (dark).
- Card minHeights reduced: live/finished 196/214 → 184/200, upcoming 190/208 →
  180/196.

### Files Changed
- `lib/screens/home/widgets/home_match_cards.dart`
- `lib/screens/home/widgets/home_hero.dart`
- `lib/screens/home/widgets/home_featured.dart`

### Commands Run
- `flutter analyze lib/` — No issues found.

---

## Task: Home target visual score/color polish pass (2026-06-15)

### Summary
Pushed the Home screen closer to the premium target. Removed the red `/wickets`
split from all Home score displays — full scores (`169/10`, `274/5`) now read
strong white when live and cyan-white when finished, never red. Bumped list-card
score sizes so the score is one of the strongest elements. Flattened list cards
toward dark navy glass (heavier opaque overlay, thinner subtle border, dimmer top
strip, smaller VS glow, no neon card glow) so they stop reading as mini hero cards.
Added women's-team name normalization (`India Women` → `India W`) and suppressed
long full names on compact cards (code-only when too long). Cleaned up the hero
status pill — removed the heavy glow, darker crisp background, brighter readable
text. Shrank list-card series title so teams/score dominate.

### Score color / red-wicket changes
- `_LiveScoreText` (list) rewritten: single white (live) / passed-color (finished)
  `Text`, no RichText red wicket span.
- `_HeroScoreText` (hero) rewritten the same way — full score white when live.
- Live score color path stays white; finished stays cyan; overs muted cyan.

### Match card background / glow changes
- `matchCardOverlayColors` (dark): now near-opaque flat navy 3-stop
  (`#081a2e`/`#071526`/`#06121f`, .90–.97) — stadium photo barely reads.
- `_HomeCardShell`: border alpha .42→.22, replaced cyan `heroShadow` with a soft
  black drop shadow in dark mode, VS `GlowOrb` 70/.045 → 56/.025.
- `_TopCyanHighlight`: height 2→1.5, alpha .7/.8 → .32/.4, dropped the blur glow.
- `_CenterPill`: removed glow shadow, darker `#071d33` bg, softer border.

### Team name shortening / Women → W
- Added `normalizeWomenTeamName`, `homeTeamShortName` in `home_featured.dart`.
- `_HomeTeamBlock`, `_MiniTeam` now show short name only when it fits (code-only
  otherwise), no long "Women" names.

### Hero status pill readability
- `_HeroCenterPill`: removed glow, `#05172b` .9 bg, `#d6f6ff` text, thinner border.

### List card title hierarchy
- `_CardTopRow` title 14 → 12.5.

### Score sizes
- `_HomeTeamBlock` score 18/19 → 20/21; `_CompactTeam` score 12.5 → 15.

### Files Changed
- `lib/screens/home/widgets/home_match_cards.dart`
- `lib/screens/home/widgets/home_hero.dart`
- `lib/screens/home/widgets/home_featured.dart`
- `lib/app_theme.dart`

### Commands Run
- `flutter analyze lib/` — No issues found.

---

## Task: Home Live Score Colors + Favorite Countries Upcoming Merge (2026-06-14)

### Summary
Finished the in-progress score-color pass on the Home match cards and cleared the
three outstanding analyzer issues. Live match scores now render runs in bright
white (navy in light) with the `/wickets` segment tinted red via `c.live`, matching
the target design; non-live scores stay flat cyan. Wired `live: match.isLive`
through both `_HomeTeamBlock` call sites so the styling activates only for live
matches.

### Files Changed
- `lib/screens/home/widgets/home_match_cards.dart` — added `_LiveScoreText`
  widget (RichText runs/wickets split, red wicket tint when live); passed
  `live: match.isLive` to both `_HomeTeamBlock` instances.
- `lib/repositories/cricket_repository.dart` — removed unnecessary `!` on
  `lastError` (already non-null inside the guard).

### Commands Run
- `flutter analyze lib/` — No issues found (was 1 error + 2 warnings).
- `flutter test` — All 38 tests passed.

### Pending Issues
- Visual QA at 360dp (no emulator): confirm live cards show white runs + red
  wickets, finished cards stay cyan, Dark/Light both correct.

---

## Task: Android Release Signing Gradle KTS Fix (2026-06-13)

### Summary
Fixed `android/app/build.gradle.kts` after Groovy signing syntax was added to a
Kotlin Gradle file. Converted keystore loading and release signing config to
valid Kotlin DSL, removed the duplicate `buildTypes` block, and kept release
minification, resource shrinking, and ProGuard rules enabled.

### Files Changed
- `android/app/build.gradle.kts` - valid Kotlin DSL release signing config using
  `android/key.properties`.
- `AI_TASK_LOG.md` - documented the fix and build result.

### Commands Run
- `flutter build appbundle --release --dart-define=CRICKET_API_KEY=... --dart-define=CRICKET_PACKAGE_NAME=com.cricpro.app --dart-define=CRICKET_APP_VERSION=2.0.0 --dart-define=ONESIGNAL_APP_ID=...`

### Test Results
- Release AAB built successfully:
  `build/app/outputs/bundle/release/app-release.aab` (61.6 MB).

### Pending Issues
- None.

---

## Task: Android APK Size Check (2026-06-13)

### Summary
Investigated why `app-release.apk` showed 67.9 MB after previously reducing the
app near 32 MB. The larger file is the universal release APK, which bundles
native libraries for `armeabi-v7a`, `arm64-v8a`, and `x86_64`. Split-per-ABI
release APKs are still around the expected size.

### Findings
- Universal APK: `app-release.apk` - 67.92 MB.
- Split APKs:
  - `app-armeabi-v7a-release.apk` - 30.81 MB.
  - `app-arm64-v8a-release.apk` - 33.03 MB.
  - `app-x86_64-release.apk` - 34.34 MB.
- Release AAB: `app-release.aab` - 61.51 MB; Play Store serves device-specific
  splits from the AAB, not the whole universal APK.
- Flutter assets inside the universal APK are about 7.48 MB compressed.
- Splash asset is local-only and small:
  `assets/splash/splash_composed.webp` - 77,204 bytes.

### Commands Run
- Inspected APK zip contents by category.
- `flutter build apk --release --split-per-abi` - built successfully.

### Pending Issues
- None.

---

## Task: Android Launcher Icon Update (2026-06-13)

### Summary
Updated the Android launcher icon so the app uses
`assets/icon/cricpro_icon.png` through the existing
`android:icon="@mipmap/ic_launcher"` manifest reference. The source file is named
`.png` but its bytes are WebP, so it was decoded as source art and exported as
real PNG mipmap launcher resources for Android.

### Files Changed
- `android/app/src/main/res/mipmap-mdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-hdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`
- `AI_TASK_LOG.md` - documented the icon update and verification.

### Commands Run
- Generated launcher PNGs from `assets/icon/cricpro_icon.png` at 48, 72, 96,
  144, and 192 px.
- `flutter build apk --release` - built successfully.

### Test Results
- Release APK resource packaging passed:
  `build/app/outputs/flutter-apk/app-release.apk` (67.9 MB).

### Pending Issues
- None.

---

## Task: Android App Bundle Toolchain Fix (2026-06-13)

### Summary
Fixed the release app bundle failure:
`Release app bundle failed to strip debug symbols from native libraries`. The
Gradle build itself succeeded, but Flutter failed its final appbundle
debug-symbol inspection because Android SDK command-line tools were missing from
`D:\Sdk`. Installed the official Android command-line tools into
`D:\Sdk\cmdline-tools\latest` and accepted SDK licenses.

### Files Changed
- `AI_TASK_LOG.md` - documented the toolchain fix and successful build.

### Environment Changes
- Installed Android SDK command-line tools package:
  `commandlinetools-win-14742923_latest.zip`.
- Verified `D:\Sdk\cmdline-tools\latest\bin\sdkmanager.bat`.
- Accepted Android SDK licenses with `flutter doctor --android-licenses`.

### Commands Run
- `flutter doctor -v` - initially showed missing `cmdline-tools` and unknown
  license status.
- `sdkmanager.bat --version` - returned `20.0` after install.
- `flutter doctor -v` - No issues found.
- `flutter build appbundle --release --dart-define=CRICKET_API_KEY=... --dart-define=CRICKET_PACKAGE_NAME=com.cricpro.app --dart-define=CRICKET_APP_VERSION=2.0.0 --dart-define=ONESIGNAL_APP_ID=...` - built successfully.

### Test Results
- Release AAB built successfully:
  `build/app/outputs/bundle/release/app-release.aab` (61.5 MB).

### Pending Issues
- None.

---

## Task: Analyzer Archive Exclusion Fix (2026-06-13)

### Summary
Fixed the full-project Flutter analyzer failure from the attached log by keeping
archived dead Dart code out of analysis. The failing files under `archived/`
reference old relative imports and undefined symbols, so they should not be
treated as live app source. Also removed one unused import from an active test
file so the full analyzer exits cleanly.

### Files Changed
- `analysis_options.yaml` - excluded `archived/**` from Dart analysis.
- `test/analytics_service_test.dart` - removed unused `flutter/widgets.dart`
  import.

### Commands Run
- `flutter analyze` - first pass confirmed archive errors were gone and exposed
  one unused-import warning.
- `flutter analyze` - No issues found.

### Test Results
- Full Flutter analyzer passes with 0 issues.

### Pending Issues
- None.

---

## Task: Ads GDPR / UMP Compliance Check (2026-06-13)

### Summary
Hardened the Flutter ads consent path so UMP consent-info update runs before
AdMob initialization/ad loading on every ads-enabled launch. Removed the Admin
`consentRequired=false` bypass, changed UMP errors to fail closed for ad loading,
added privacy-options status tracking, and added a conditional More -> Privacy
Choices entry when UMP requires it.

### Files Changed
- `lib/services/ads/consent_manager.dart` - strict UMP flow, logs, privacy
  options form API.
- `lib/services/ads/ads_manager.dart` - skips ad SDK init unless UMP
  `canRequestAds=true`.
- `lib/main.dart` - listens for UMP privacy-options requirement.
- `lib/screens/more/more_screen.dart` - conditional Privacy Choices item.
- `ADS_GDPR_COMPLIANCE_CHECK_REPORT.md` - created.

### Commands Run
- `flutter analyze lib/services/ads lib/widgets/ads lib/models/ad_config.dart lib/main.dart lib/screens/more/more_screen.dart` - No issues.
- `flutter test` - 38/38 passed.
- `flutter build apk --debug` - passed.

### Pending Issues
- In AdMob Privacy & Messaging, production European regulations message must be
  created/published for the app ID so UMP has a form to show in EEA/UK/CH.

## Task: Real Ads Mode Pipeline Fix (2026-06-13)

### Summary
Inspected Admin Panel -> backend `/app/config` -> Flutter ad config -> ad
manager/adapter -> placements. Fixed debug builds forcing Google test ads,
added Google Ad Manager path support for live banner/interstitial IDs, made
banners reload after config arrives, added real-mode sample ID guards, and added
clear masked logs for config/load/pre-roll diagnostics.

### Files Changed
- `lib/models/ad_config.dart` - Admin `testMode` is now source of truth; debug no
  longer forces test ads.
- `lib/services/ads/admob_adapter.dart` - supports AdMob IDs and Google Ad
  Manager path units; rejects Google sample units in real mode; logs masked IDs,
  source, success/failure, error code/domain/message.
- `lib/services/ads/ads_manager.dart` - added config revision notifier and
  diagnostics for config/load/preload.
- `lib/widgets/ads/banner_ad_widget.dart` - reloads banner/sticky banner after
  ad config arrives or changes.
- `lib/main.dart` - Watch Live pre-roll logs masked selected unit ID.
- `android/app/src/main/AndroidManifest.xml` - added network permissions.
- `admin-panel/components/forms/AdsSettingsForm.tsx` - warns when sample Google
  units are saved while Test mode is off.
- `ADS_REAL_MODE_FIX_REPORT.md` - created debug report.

### Live `/app/config` Result
- `ads.enabled=true`, `testMode=false`, primary `admob`.
- Banner/interstitial are Google Ad Manager paths and now use Ad Manager loader
  classes.
- Android rewarded unit is still a Google sample ID in live config; Admin must
  replace it for real rewarded-video pre-roll.

### Commands Run
- `curl https://api.webcrichd.co/app/config` - verified current live ads config.
- `flutter analyze lib/models/ad_config.dart lib/services/ads lib/widgets/ads lib/main.dart` - No issues.
- `flutter test` - 38/38 passed.
- `npm run lint` in `admin-panel` - passed.
- `node --check cricket-api/src/lib/public-app-state.js` - passed.
- `node --check cricket-api/src/admin/index.js` - passed.
- `flutter build apk --debug` - passed.
- `flutter build apk --release` - passed.

### Pending Issues
- Admin Panel must replace the live Android rewarded unit; it is still the
  Google sample rewarded ID while Test mode is off.
- On-device ad fill still depends on AdMob/GAM inventory, approval, app-ads.txt,
  policy, and correct account/placement setup.

## Task: Splash Rectangles + Local-Only Composed Startup Fix (2026-06-13)

### Summary
Reworked Flutter splash startup to remove the remaining Admin/config splash path
and eliminate the black/checkerboard rectangles caused by non-transparent overlay
assets. The splash now uses Option A: one optimized local composed image
(`assets/splash/splash_composed.webp`) plus lightweight Flutter glow/particle
painters. No `Image.network`, no `/app/config`, no remote URL selection, and no
Admin splash asset loading occurs before or during the splash.

### Files Changed
- `lib/main.dart` - removed splash config decision path; splash shows immediately
  and `_loadAppConfig()` runs only after splash finish.
- `lib/features/splash/presentation/premium_splash_screen.dart` - single composed
  WebP render path with cheap glow/logo-pulse/particle animation.
- `lib/features/splash/widgets/splash_asset_image.dart` - local-only asset widget.
- `lib/features/splash/widgets/splash_orbit_trail.dart` - removed unused old path.
- `lib/features/splash/data/splash_config_service.dart` - removed from app.
- `assets/splash/splash_composed.webp` - new 900x1600 WebP, 77 KB.
- `assets/splash/` old overlay WebPs and generator script - removed.
- `android/app/src/main/res/drawable/launch_background.xml` - dark navy only.
- `android/app/src/main/res/drawable-v21/launch_background.xml` - dark navy only.
- `CRICPRO_PREMIUM_SPLASH_SCREEN_PHASE_4_REPORT.md` - added local-only and final
  rectangle-fix sections.

### Commands Run
- `flutter clean` - passed
- `flutter pub get` - passed
- `flutter analyze` - failed on pre-existing archived dead-code errors under
  `archived/dead-code/...`, unrelated to splash
- `flutter analyze lib/main.dart lib/features/splash` - passed before final
  composed-image rewrite; will rerun
- `flutter test` - passed before final composed-image rewrite; will rerun
- `flutter run --profile -d 10716344` - interrupted before completion

### Pending Issues
- Rerun focused analyzer and test after final composed-image rewrite.
- Rerun Android profile on `NE2211` and visually confirm no rectangles/flash.
- Run `flutter build apk --release`.

## Task: Android Native Launch + Splash Startup Rebuild (2026-06-13)

### Summary
Rebuilt the CricPro splash startup from the ground up to eliminate white flash,
default Flutter/Android splash icon, and slow startup. The native Android launch
screen now uses a dark theme with CricPro navy (`#060B18`), Android 12+ system
splash is configured with a transparent icon and zero duration, and the Flutter
splash loads instantly from cached/default config instead of blocking on network.
All splash images now decode at display resolution (`cacheWidth`/`cacheHeight`).

### Android Native Changes
- `values/styles.xml`: `Theme.Light.NoTitleBar` → `Theme.Black.NoTitleBar` +
  `windowFullscreen` + `splash_navy` NormalTheme
- `values-night/styles.xml`: aligned with day variant
- `values-v31/styles.xml` (NEW): Android 12+ `windowSplashScreenBackground` =
  navy, `windowSplashScreenAnimatedIcon` = transparent drawable, duration = 0
- `values-night-v31/styles.xml` (NEW): identical for night mode
- `drawable/splash_transparent.xml` (NEW): 1×1 transparent shape for Android 12+ icon
- `AndroidManifest.xml`: label `cricpro_flutter` → `CricPro`

### Flutter Changes
- `main.dart`: dark system UI overlay before `runApp()`, `_decideSplash()` uses
  `loadCachedOrDefaults()` (no network), `refreshInBackground()` fire-and-forget
- `splash_config_service.dart`: new `loadCachedOrDefaults()` (SharedPreferences),
  `refreshInBackground()` (caches remote config for next launch)
- `splash_asset_image.dart`: added `cacheWidth`/`cacheHeight` params
- `premium_splash_screen.dart`: `cacheWidth`/`cacheHeight` on all 4 SplashAssetImage

### Commands Run
- `flutter clean` → ✅
- `flutter pub get` → ✅
- `flutter analyze lib/main.dart lib/features/splash/` → No issues found
- `flutter test` → All 38 tests passed

### Pending Issues
- On-device cold start test (no emulator this session)
- Release APK build (`flutter build apk --release`)
- Launcher icons still default Flutter (separate task)

---


## Task: ICC Women Rankings — Remove "Coming Soon", Wire Real API (2026-06-11)

### Summary
"ICC Women Ranking" in More showed a "Coming Soon" badge + snackbar. Backend
already fully supported women team rankings via Cricbuzz — only the Flutter
wiring was missing. Removed Coming Soon, made the row open the existing premium
RankingsScreen seeded to women/teams/ODI. No hardcoded data; API is the source
of truth.

### Backend — already complete (verified, NOT changed)
- `routes/rankings.js` `GET /rankings?gender&category&format` — gender enum
  men|women, category batting|bowling|allrounder|teams, format test|odi|t20.
  Redis cache (TTL.SERIES) when rows>0, clean empty `{data:[],count:0}` + message
  on provider miss.
- `providers/cricbuzz/client.js` `getRankings` + `parseRankingsHtml` normalizes
  teams → {rank, teamName, teamId, rating, points, matches, movement, gender,
  format, category}. `availableFormats` included.

### Live API tested (https://api.webcrichd.co) via curl/Invoke-WebRequest
- women/teams/odi → count 14 (Australia W rank1 rating163 …) ✓
- women/teams/t20 → count 79 ✓
- women/teams/test → count 0 (clean empty state, NOT Coming Soon) ✓
- men/teams/odi → 20, men/batting/test → 15 (unchanged) ✓

### Flutter
- `screens/rankings/rankings_screen.dart`: added `initialGender`,
  `initialCategory`, `initialFormat` params (default men/batting/test). State
  seeds from them. Existing gender picker + category/format dropdowns + empty
  state reused — same premium light/dark UI.
- `main.dart`: added `_openWomenRanking()` → `RankingsScreen(initialGender:
  'women', initialCategory:'teams', initialFormat:'odi')`.
- `screens/more/more_screen.dart`: added `onOpenWomenRanking` field; Women row
  now calls it; removed `'Coming Soon'` badge + snackbar.
- Active service `services/cricket_api_service.dart` → `core/api/api_client.dart`
  → `core/api/api_config.dart` already defaults baseUrl `https://api.webcrichd.co`.
  Men ranking untouched.

### Commands Run
- Live API curl tests (above) — all pass
- `flutter analyze` (changed files + active api config) — No issues found
- `flutter test` — All 34 tests passed
- NOTE: `lib/core/` legacy tree has pre-existing analyzer errors (dio/google_fonts
  not in pubspec); unused by the active app, untouched.

### Pending Issues
- Visual QA (no emulator): open More → ICC Women Ranking → confirm premium screen
  opens on Women/Teams/ODI with real teams; switch format to Test → clean empty
  state (no Coming Soon); Men ranking still works.

---

## Task: Light Mode — Restore Visible Stadium Texture (not flat white) (2026-06-11)

### Summary
Prior pass over-corrected: light mode read as plain flat white with no
background/texture. Target (target-design/home|matches|schedule.png) shows a
soft ice-blue gradient bg with a VISIBLE faint stadium texture behind headers
AND inside cards, under only a light white veil. Re-tuned the central tokens so
the clean light assets show through. Dark untouched.

### Central changes
- `lib/components.dart` `StadiumImage` light opacity: hero .55→**.92**,
  backdrop .35→**.8** (clean assets are bright ice-blue, no scrim, so render
  strong).
- `lib/app_theme.dart` light overlays lightened so texture shows:
  - `stadiumOverlayColors`: .62/.82 → **.12/.42**
  - `heroOverlayColors`: .48/.66/.90 → **.22/.34/.58**
  - `matchCardOverlayColors`: .55/.88 → **.26/.52**

### Inline card overlays (not on tokens) lightened
- `matches_screen.dart` `_MatchCardShell`: .62/.52/.72 → .26/.18/.38; bottom
  veil .55 → .30.
- `schedule_screen.dart` `_ScheduleMatchCard`: .82/.88/.94 → .40/.50/.62.
- Home hero/live cards already route through tokens (auto-fixed).

### Commands Run
- `flutter analyze lib` — No issues found
- `flutter test` — All 34 tests passed

### Pending Issues
- Visual QA at 360dp (no emulator). Confirm bg shows ice-blue + faint stadium,
  cards show subtle texture (not flat white, not grey), navy text still crisp,
  Dark unchanged.

---

## Task: Match Details Light Mode — Full Premium Conversion (2026-06-11)

### Summary
Match Details still read as a mixed dark/light conversion: hero card showed a
dark stadium with WHITE score text (unreadable on light), top bar/refresh button
inconsistent with other light screens, commentary text white on light cards,
player avatars muddy. Fixed all to the premium light system. Dark untouched.

### Hero score card — `widgets/match_details_ui.dart`
- Background: was a raw `Image.asset(heroBg)` (dark stadium) in both themes. Now
  light mode uses `StadiumImage(hero:true)` (clean ice-blue light asset, no dark
  scrim) over a `c.card` base; dark keeps the raw night-stadium art.
- Status text: hardcoded white → `c.isDark ? white : c.text` (navy).
- Team main score (`MDTeamScoreBlock`): hardcoded `Colors.white` → navy in light.
- Result/status pill + format pill already color-tinted (kept).

### Top bar (`MatchDetailsTopBar`)
- Wrapped in `Padding(top:6,bottom:2)` for consistent SafeArea→appbar spacing.
- Filter button: light border `c.cyan(.75)` → `c.border` (soft, not bright cyan),
  white glass + soft blue shadow; icon tinted navy (`c.text`) in light.
- Back icon + title already `c.text` (navy) — aligned, kept.

### Refresh row (`MDUpdatedRow`)
- Label: `c.onImageText` → `c.isDark ? onImageText : c.muted` (muted blue-grey).
- Refresh button: cyan-tint glass → white `c.card` + `c.border` + soft shadow in
  light (matches top action button).

### Tabs / cards (already branched in prior pass, verified)
- `MatchDetailsTabBar`, `MDGlassPanel`, segmented selectors: opaque white in light
  with blue/cyan active pill (glow gated to dark). Info/Score/Squad use these.

### Player avatar (`MDPlayerAvatar`)
- Ring gradient ended in dark navy `#071726` in BOTH themes (muddy initials in
  light) → `c.isDark ? #071726 : c.card2`.

### Commentary (`match_details_screen.dart`)
- Ball text: hardcoded `white(.9)` → navy in light. Note-card surface:
  `c.card2(.4)` translucent → opaque `c.card2` in light. Ball cards use
  `MDGlassPanel` (already opaque white). Timeline rail/dividers pale cyan (kept).

### Live tab (`live_match_tab.dart`)
- Over-pill surface `c.card2(.6)` → opaque `c.card2` in light. Ball-chip colors
  (dot grey, 4 cyan, 6 green, W red) + white-on-circle labels kept (correct).

### Commands Run
- `flutter analyze lib` — No issues found
- `flutter test` — All 34 tests passed

### Pending Issues
- Visual QA at 360dp (no emulator). Toggle Dark↔Light on every MD tab: confirm
  bright white/ice cards, navy text, blue VS chip, no white-on-light text, no
  grey scrim, Dark unchanged.

---

## Task: Light Mode Full Pass — Clean Ice-Blue System Across All Screens (2026-06-11)

### Summary
Light mode still read grey/dark. Root causes fixed app-wide:
1. **Dark stadium photos dimmed** behind cards left a grey scrim. Now light mode
   swaps to the shipped clean `assets/images/light_mode/*` ice-blue PNGs at full
   strength (no tint/blend) via a central `StadiumImage` + `LightAsset` registry.
2. **Unbranched translucent glass** (`c.card.withValues(alpha: .4–.6)` used in
   BOTH themes) let the backdrop bleed through → muddy grey. Branched every one
   to `c.isDark ? glass : c.card` (opaque white in light).
3. **Ungated cyan-glow `BoxShadow`** read as a dark-inspired halo on white. Gated
   all per-widget glows `if (c.isDark)` (active pills, segments, nav strip, VS
   badges, team-logo rings, icon buttons, ball dots, hero cards).
4. **`...c.heroShadow.skip(1)` bug**: light heroShadow is a single element, so
   `.skip(1)` dropped the ONLY shadow → flat cards. Branched the whole boxShadow.

### Assets
- `pubspec.yaml`: registered `assets/images/light_mode/`.
- `lib/components.dart`: `StadiumImage` now renders clean light asset (opacity
  .55 hero / .35 backdrop, no tint) in light mode; falls back to dimmed dark art.
  New `LightAsset` registry maps dark stadium paths → clean light PNGs.

### Files Changed
- `lib/components.dart` — StadiumImage rewrite + LightAsset; BottomNav strip glow
  + SegmentedTabs surface/indicator gated.
- `lib/screens/home/home_screen.dart` — 8 glass surfaces branched.
- `lib/screens/matches/matches_screen.dart` — bell/tabs/chips surfaces branched,
  status-tab + chip glows gated.
- `lib/screens/schedule/schedule_screen.dart` — date/filter/nav/sort/time-venue
  surfaces branched; VS chip + tournament-logo glows gated.
- `lib/screens/series/series_premium.dart` — `PremiumVsBadge` light blue gradient
  + glow factor 0; `_VsBadgePainter` fillGradient; panel `.skip(1)` fix; team-logo
  + empty-state glows gated.
- `lib/screens/series/series_list_screen.dart` — hero `.skip(1)` fix; trophy,
  nav button, badge glows gated.
- `lib/screens/series/series_detail_screen.dart` — stat-card + badge glows gated.
- `lib/screens/match_details/widgets/match_details_ui.dart` — `MDVsBadge` light
  gradient; `_VsPainter` fillGradient; `MDGlassPanel` + hero `.skip(1)` fix;
  tab bars/filter/team-logo/ball-dot/active-pill glows gated + surfaces branched.
- `lib/screens/match_details/match_details_screen.dart` — info chip branched.
- `lib/screens/rankings/rankings_screen.dart` — dropdown surface branched,
  first-place glow gated.

### Untouched (intentional)
- Dark mode (all `c.isDark` branches unchanged).
- Live stream/video surfaces (dark overlays intentional, rule 6).
- Marketing poster cards (full-opacity, white-on-image text).

### Commands Run
- `flutter pub get` — Got dependencies (assets registered)
- `flutter analyze lib` — No issues found
- `flutter test` — All 34 tests passed

### Pending Issues
- Visual QA at 360dp (no emulator). `flutter run -d chrome`, toggle Dark↔Light:
  confirm bright white/ice-blue cards, no grey scrim, blue VS chips, clean nav,
  Dark unchanged.

---

## Task: Home Light Mode — VS Badge Gradient + Stadium Texture (2026-06-11)

### Summary
Two visible gaps vs target on Home light mode: (1) `_HomeVsBadge` was a dark navy
glass parallelogram with a heavy triple cyan bloom (reading as a dark blob on
white); (2) prior pass dropped `heroImageOpacity` so far (.18) that cards looked
flat white with no stadium texture. Fixed both. Dark untouched.

### VS badge — `lib/screens/home/home_screen.dart`
- `_VsBadgePainter`: added optional `fillGradient` (shader fill). Light mode
  paints a blue→cyan parallelogram (`#35e2ff`→`#0a86ff`), white thin border, no
  glow halo. Dark keeps navy glass + cyan glow.
- `_HomeVsBadge.build`: glow layers A (radial bloom), B (under-pool), C (diagonal
  streak) + VS text cyan shadow now wrapped `if (!light)`. Light gets one subtle
  soft-blue drop glow under the pill instead.
- NOTE: this `_VsBadgePainter` is Home-only; Series (`series_premium.dart`) and
  Match Details (`match_details_ui.dart`) have their own VS painters — out of
  scope, untouched.

### Stadium texture — `lib/app_theme.dart`
- `heroImageOpacity` .18 → **.5** (cards were too plain; stadium is already
  white-tinted via `stadiumImageTint .65` + `BlendMode.lighten`, so higher
  opacity stays bright, not grey).
- `heroOverlayColors` light: top stops lightened .70/.82/.94 → **.48/.66/.90**.
- `matchCardOverlayColors` light: .82/.96 → **.55/.88**.
- Backdrop `stadiumImageOpacity` (.08) left as-is — header stays a faint wash.

### Ad overlap (#11) — verified, no change
`main.dart` already: `extendBody:false` + `StickyBannerBar` ABOVE `BottomNav` in
`bottomNavigationBar` Column → body laid out above ad strip. Screenshot "overlap"
is a mid-scroll card behind the pinned boundary, not a true overlay. Correct.

### Commands Run
- `flutter analyze lib` — No issues found
- `flutter test` — All 34 tests passed

### Pending Issues
- Visual QA at 360dp (no emulator). `flutter run -d chrome`, toggle Dark↔Light
  Home: confirm VS badge = blue gradient (light) / navy glow (dark), cards show
  subtle stadium texture, no grey fog, Dark unchanged.

---

## Task: Home Light Mode — Cyan-Glow Halo Gating (2026-06-11)

### Summary
Home screen still showed neon cyan halos in light mode (active status tab,
notification button, category chips, Watch Live button, VS badge ring, "See All"
arrow button). Gated every per-widget cyan-glow `BoxShadow` to dark-mode only;
light falls back to no halo (clean white, gradient/border kept). Dark untouched.
Follows design rule 9 in `AI_PROJECT_INDEX.md`.

### Files Changed
- `lib/screens/home/home_screen.dart` — 6 `BoxShadow` blocks gated `… && c.isDark`
  / `c.isDark ? […] : null`:
  - notification icon button (~538)
  - main status tab active glow (Live/Upcoming/Finished, ~1012)
  - VS badge ring glow (~1918)
  - Watch Live gradient button glow (~2301)
  - category filter chip active glow (~2606)
  - "See All" circular arrow button glow (~3257)

### Verified, not changed
- `home_components.dart` colored icon-tile shadow (accent-colored under same-color
  tile — not a grey/cyan fog, kept). `_TopCyanHighlight` + `_GlowOrb` α.045
  already handled prior pass. Black image-fades already `isDark`-branched.
- Cyan→blue active gradients + low-alpha cyan borders kept (on-spec).

### Commands Run
- `flutter analyze lib` — No issues found
- `flutter test` — All 34 tests passed

### Pending Issues
- Visual QA at 360dp not run (no emulator). `flutter run -d chrome`, toggle
  Dark↔Light on Home, confirm no halos / clean white / Dark unchanged.

---

## Task: Light Mode Premium Pass — Tokens + Cyan-Glow Gating (2026-06-11)

### Summary
Two-part fix to make Light Mode match the premium target screenshots (clean
white cards, one soft blue shadow, whisper of stadium texture, cyan→blue
gradients only on active pills/buttons). User reported Light Mode still looked
"grey/misty/frosted with too much glow". Dark Mode untouched.

**Root cause:** three things, mostly central tokens —
1. Stadium image bled through as grey haze (`stadiumImageOpacity .16`,
   `heroImageOpacity .34` too high).
2. Frosted translucent overlays/card fills let texture muddy cards.
3. Cyan glow everywhere — `cardShadow`/`heroShadow` carried a cyan glow in
   light mode, plus per-card cyan radial glows + neon "top highlight" strips +
   active-pill glow halos rendered in BOTH themes.

### Central token fixes — `lib/app_theme.dart`
- `cardGradient`: solid opaque white in light (was .98/.96 translucent).
- `cardShadow` / `heroShadow`: light mode now ONE soft blue drop-shadow
  (`#3f6ea5` α.12/.15) — removed the cyan glow layer.
- `stadiumImageOpacity` .16 → **.08**; `heroImageOpacity` .34 → **.18**;
  `stadiumImageTint` white α.55 → **.65**.
- `stadiumOverlayColors` / `heroOverlayColors` / `matchCardOverlayColors`:
  pushed white stops higher (e.g. hero .42/.58/.82 → .70/.82/.94) so cards read
  crisp white.
- `onImageText` light α.78 → **.95** (stronger navy contrast).

### Per-card cyan-glow gating (dark-mode only in light)
- Home: `_TopCyanHighlight` returns `SizedBox.shrink()` in light.
- Matches `_MatchCardShell`: border → `c.border` in light; cyan radial glow
  wrapped `if (c.isDark)`.
- Schedule `_ScheduleMatchCard`: border → `c.border` in light; both radial
  glows + top/bottom edge glow lines wrapped `if (c.isDark)`.
- Match Details `MDTopGlow` + Series `TopCyanHighlight`: `SizedBox.shrink()` in
  light.

### Series Details pass (Overview/Matches/Squads/Stats) — glow halos
Hero card + all four tabs consumed the now-clean tokens, but several inline
cyan-glow shadows still ran in BOTH themes (the visible "dark-with-grey-overlay"
look). Critical: some used `...c.heroShadow.skip(1)` which, now that light
heroShadow is a single element, left light cards with ONLY the glow and no soft
shadow. Gated all to dark-only, light falls back to clean `c.heroShadow`:
- `series_detail_screen.dart`: hero card shadow+border; series title cyan text
  `shadows`; squad team-toggle active glow.
- `series_components.dart`: `SeriesListCard` + series live-hero shadow/border;
  `SeriesTabBar` active-tab glow; `SeriesFilterPills` active glow.
- `series_premium.dart`: three squad format/team segment selector glows
  (`selected/sel && c.isDark`).
Low-alpha cyan borders (≤.5) kept in light — they ARE the spec's "thin light
cyan/blue border". VS badge dark glass + cyan→blue VS gradient kept (per target).

### Files Changed
- `lib/app_theme.dart`
- `lib/screens/home/home_screen.dart`
- `lib/screens/matches/matches_screen.dart`
- `lib/screens/schedule/schedule_screen.dart`
- `lib/screens/match_details/widgets/match_details_ui.dart`
- `lib/screens/series/series_detail_screen.dart`
- `lib/screens/series/series_components.dart`
- `lib/screens/series/series_premium.dart`

### Commands Run
- `flutter analyze lib` — No issues found
- `flutter test` — All 34 tests passed

### Pending Issues
- Visual QA at 360dp not run this session (no emulator). Recommend
  `flutter run -d chrome`, toggle Dark↔Light on Series Details all 4 tabs +
  Home/Matches/Schedule, confirm clean white cards / no glow / Dark unchanged.

---

## Task: Light Mode Fix — Series Details Translucent Glass Surfaces (2026-06-11)

### Summary
User reported the Series Details screen (all tabs: Overview / Matches / Squads /
Stats) still looked "too dark" in Light Mode. Root cause was a **new** variant of
the documented grey-scrim bug: the premium glass surfaces used a **translucent**
card color (`c.card.withValues(alpha: .5/.55/.45/.42/.4)`) in BOTH themes. In dark
mode that's the intended glassmorphism; in light mode the semi-transparent white
let the 320px **dark stadium top backdrop** and the dark `bgAsset` panel textures
bleed through, so every card/tab read as muddy grey. Prior passes had fixed
`SeriesSectionCard` and the header backdrops on other screens, but the Series
Detail glass widgets + its own top backdrop were missed.

### Fix (theme-branch every glass surface; lighten the backdrop at the source)
- Made all translucent glass surfaces **opaque `c.card` in light mode**, keeping
  the original translucent value only when `c.isDark`. Affected widgets:
  `PremiumGlassPanel`, `SeriesGlassTabBar`, the Series-list category tab bar,
  `SeriesSkeleton`, `_SquadToggle` (Squads tab), `_StatusSummaryCard`,
  `_PlayerCard` (Squads), `_StatCard` (Stats), the series-list filter chip + the
  round nav circle.
- `PremiumGlassPanel`: also gated the cyan glow shadow to dark-only and routed
  its dark `bgAsset` texture through the shared `StadiumImage` widget
  (`hero: true`) so the dark photo is lowered/white-blended in light mode instead
  of painted at full opacity behind white text.
- `SeriesEmptyState`: gave it an opaque `c.card` base in light + switched its raw
  `Image.asset` backdrop to `StadiumImage`.
- `series_detail_screen.dart` top 320px backdrop: switched the raw `Image.asset`
  to `const StadiumImage(...)` — this was the global grey scrim sitting behind
  the whole Series Detail screen (the exact #1 bug called out in the index).

Dark Mode is unchanged (every edit is a light-only branch or the `StadiumImage`
swap, which is `dst`/full-opacity in dark). No data, navigation, tab-loading,
Watch Live, or admin image/logo logic touched.

### Files Changed
- `lib/screens/series/series_premium.dart` — `PremiumGlassPanel` (opaque light
  card + StadiumImage bgAsset + dark-only glow), `SeriesGlassTabBar`, secondary
  category tab bar, `SeriesSkeleton`, `SeriesEmptyState` (opaque + StadiumImage),
  filter chip surface.
- `lib/screens/series/series_detail_screen.dart` — top 320px backdrop →
  `const StadiumImage`; `_SquadToggle`, `_StatusSummaryCard`, `_PlayerCard`,
  `_StatCard` surfaces now opaque in light.
- `lib/screens/series/series_list_screen.dart` — round nav circle surface opaque
  in light.

### Verified, not changed
- `SeriesSectionCard` (already `isDark`-branched), VS badge dark glass + cyan VS
  gradient, `_VenueTile` photo poster with white-on-image text, team-logo tint
  fallbacks — left per design rules.
- Dark Mode — only light-branches/StadiumImage swaps, so visually identical.

### Commands Run
- `flutter analyze lib` — No issues found! (ran in 113.9s; first pass flagged 3
  `prefer_const_constructors` on the new `StadiumImage` calls, since fixed)
- `flutter test` — All 34 tests passed

### Pending Issues
- Visual QA at 360dp not run this session (no emulator). Recommend
  `flutter run -d chrome`, open a Series → toggle Dark↔Light, and confirm all
  four tabs now read white/ice with crisp cards. If the faint stadium texture
  inside panels still feels a touch dark, lower `heroImageOpacity` in
  `lib/app_theme.dart` (centralized).

---

## Task: Light Mode Audit + Matches Watch Live Hide Rule (2026-06-11)

### Summary
Verification pass against the premium Light Mode target screenshots, plus a
behavioral fix on the Matches screen.

**Light Mode UI:** Audited the whole app for the patterns called out as the
cause of the old grey/dark Light Mode (`Colors.black.withOpacity`,
`Colors.black54`, `BlendMode.darken`, dark gradients/scrims, grey card
overlays). Every remaining `Colors.black*` usage in screens/components already
branches on `c.isDark` (paints only in dark mode) or lives in intentionally-dark
surfaces (live_player video chrome, VS badge glass, white-text-on-image bottom
fades, image-load `ColoredBox` placeholders) per the design rules in
`AI_PROJECT_INDEX.md`. The grey-scrim root cause (full-opacity dark stadium photo)
was already fixed in the prior pass via the centralized `StadiumImage` widget +
`stadiumImageOpacity`/`heroImageOpacity`/tint/blend tokens. No new color changes
were needed — Light Mode tokens (white/ice bg, navy text, blue-grey muted,
cyan→blue gradients, soft-blue shadows/borders, red live / green result) are
centralized in `CricColors` and used everywhere. Dark Mode untouched.

**Watch Live rule (the actual code change):** The Matches screen live-card
`_DualActionBar` previously rendered a dimmed/disabled "Watch Live" segment when
no playable stream existed. Changed it to **hide Watch Live entirely** when
`_WatchState.none`, so "View Match" expands to full width — matching the target
rule already implemented on Home (`_HomeActionBar`). The `pending` (spinner) and
`available` states are unchanged. No data/stream-resolution logic touched; only
the presentation when the resolver returns "no stream".

**Ads:** Confirmed banners never overlap cards or bottom nav. Global sticky
banner sits in `RootShell.bottomNavigationBar` as `StickyBannerBar` ABOVE
`BottomNav` with `extendBody:false`, so body content is laid out above the
ad strip at every scroll position. `StickyBannerBar`/`BannerAdWidget` render
`SizedBox.shrink()` when unfilled (no blank gap), and the sticky bar wraps its
ad in `Material` + `SafeArea(top:false)`. No changes required.

### Files Changed
- `lib/screens/matches/matches_screen.dart` — `_DualActionBar.build`: hide the
  Watch Live segment + its divider when `watchState == _WatchState.none`;
  View Match becomes full width.

### Verified, not changed
- Home Watch Live hide/full-width rule — already correct (`_HomeActionBar`).
- Light Mode color tokens / `StadiumImage` treatment — already correct from prior passes.
- Ad banner placement / bottom padding — already correct.
- Dark Mode — no token or `isDark`-branch changes, so pixel-identical.

### Commands Run
- `flutter analyze lib` — No issues found! (ran in 162.6s)
- `flutter test` — All 34 tests passed

### Pending Issues
- Visual QA at 360dp not run this session (no emulator). Recommend
  `flutter run -d chrome`, toggle Dark↔Light, and confirm a live match with NO
  stream now shows a single full-width View Match on the Matches screen.

---

## Task: Light Mode Grey-Scrim Fix — Stadium Image Treatment (2026-06-11)

### Summary
Follow-up to the earlier Light Mode passes. Light Mode still read like Dark Mode
under a grey film. Root cause: the stadium-atmosphere artwork is a **dark
night-stadium photo**, and it was rendered at full opacity with only weak white
overlays on top. In light mode the dark pixels bled through everywhere the art
appears — the top ~230–420px header backdrops (the "global grey scrim") and
inside every image-backed card (muddy grey match/hero/series cards). Match
Details looked clean only because it has no full-screen stadium backdrop.

There was **no** global `BackdropFilter` / `Opacity` / modal-barrier / black
scrim — `main.dart` `RootShell` and `MaterialApp` are overlay-free. The grey was
purely the dark images themselves.

### Fix (centralized, no per-screen guesswork)
- New `StadiumImage` widget in `lib/components.dart` — the single place stadium
  art gets its light-mode treatment: lowers opacity and screen-blends a white
  tint so the dark photo becomes a faint ice-blue texture; full-strength in dark.
- New tokens in `lib/app_theme.dart`:
  - `stadiumImageOpacity` (light .16 / dark 1.0) — header backdrops
  - `heroImageOpacity` (light .34 / dark 1.0) — stadium art inside cards
  - `stadiumImageTint` (white .55 in light / null in dark) + `stadiumImageBlend`
    (`BlendMode.lighten` light / `dst` dark)
  - Strengthened existing `stadiumOverlayColors`, `heroOverlayColors`,
    `matchCardOverlayColors` white stops for cleaner light fades.
- Replaced every dark-stadium `Image.asset` behind content with `StadiumImage`
  (`hero: true` for in-card art). Admin/network marketing posters are left at
  full opacity — only their dark stadium *fallback* asset is lightened.

### Files Changed
- `lib/app_theme.dart` — image opacity/tint/blend tokens + retuned overlay stops
- `lib/components.dart` — added `StadiumImage` widget
- `lib/screens/home/home_screen.dart` — header backdrop, hero carousel, featured
  match card, live card, featured-series fallback
- `lib/screens/matches/matches_screen.dart` — header backdrop, match list card
  image + stronger white overlay; removed now-unused `_MAsset.cardBg`
- `lib/screens/schedule/schedule_screen.dart` — header backdrop, match card bg,
  tournament initials-fallback backdrop
- `lib/screens/series/series_list_screen.dart` — header backdrop, featured hero
  background (asset fallback only), list card bg
- `lib/screens/series/series_components.dart` — series live hero, list card bg
- `lib/screens/series/series_detail_screen.dart` — detail hero background

### Not changed (correct as-is / out of scope this pass)
- Card surface colors/decorations — already white/ice in light mode; they only
  looked grey because of the image bleed, now fixed at the source.
- VS badge dark glass + cyan VS gradient, live_player video surfaces (design rule).
- Watch Live / View Match logic, navigation, data, admin image priority — untouched.
- Ad banner placement — already pinned above bottom nav via `extendBody:false`
  + `StickyBannerBar` in `RootShell`; not modified.

### Commands Run
- `flutter analyze lib` — No issues found
- `flutter test` — 34/34 passed

### Pending Issues
- Visual QA at 360dp not run in this session (no emulator). Recommend
  `flutter run -d chrome`, toggle Dark↔Light, confirm light backdrops/cards now
  read white/ice and Dark Mode is unchanged. If header art still feels a touch
  strong, tune `stadiumImageOpacity`; if in-card art too faint, tune
  `heroImageOpacity` — both centralized in `app_theme.dart`.

---

## Task: Light Mode Leftover Dark-Surface Fixes (2026-06-11)

### Summary
Follow-up to the 2026-06-10 Light Mode redesign. The prior pass left a handful of
hardcoded dark surfaces that did not branch on `isDark`, so they painted dark navy
in light mode (muddy Schedule cards, invisible dot-ball markers, dark commentary/
overs nodes, half-dark series section cards). Fixed all of them to branch on
`c.isDark` — dark mode is pixel-identical, light mode now uses white/ice surfaces.
No data, navigation, Watch Live, or admin image/logo logic touched.

### Root cause
Not a token problem — the centralized `CricColors` tokens were already theme-aware.
The bug was specific widgets bypassing tokens with `const Color(0xff0…)` literals
(and one hardcoded `Colors.white` inner dot) that rendered regardless of theme.

### Files Changed
- `lib/screens/schedule/schedule_screen.dart`
  - Schedule match-card image overlay gradient → now `isDark` branch (white/ice glass in light)
  - Tournament logo backing circle color → `c.card` in light
  - Tournament initials-fallback overlay gradient → white/ice in light
  - `_SheetShell` bottom-sheet gradient → `c.card`/`c.card2` in light (was dark navy under navy text)
- `lib/screens/match_details/widgets/match_details_ui.dart`
  - Ball marker `opaqueBase` → `c.card` in light (was dark navy)
  - Dot-ball inner dot → `c.muted` in light (was hardcoded white, invisible on white base)
- `lib/screens/match_details/match_details_screen.dart`
  - Commentary timeline node fill → `c.card` in light (was dark navy)
- `lib/screens/series/series_components.dart`
  - `SeriesSectionCard` gradient second stop → `c.card2` in light (was `0xff081a30` dark navy)

### Intentionally left dark (correct in both themes)
- VS badge dark-glass chip + bright cyan→blue VS gradient (`0xff35e2ff/0a86ff`) — matches target
- `live_player_screen.dart` video surfaces — design rule: video screens keep dark overlays
- Venue thumbnail bottom-fade in series_detail (white text-on-image needs the dark fade)
- `ColoredBox` image placeholders (only visible during load/error, immediately covered)

### Commands Run
- `flutter analyze lib` — No issues found
- `flutter test` — All 34 tests passed

### Test Results
- analyze: 0 issues
- test: 34/34 passed (incl. team logo priority, hero card constrained-height, app boot)

### Pending Issues
- Visual QA at 360dp not performed in this session (no device/emulator run). Recommend a
  quick `flutter run -d chrome` pass on Schedule cards, Match Details Comm/Overs tabs,
  and Series Squads/Stats to confirm the light surfaces read as intended.

---

## Task: Complete Light Mode Redesign (2026-06-10)

### Summary
Redesigned the entire CricPro app Light Mode across all screens to match a premium light-mode reference design. Dark Mode unchanged. All backend data logic preserved.

### Approach
Created a centralized theme token system in `CricColors` ThemeExtension, then systematically replaced hardcoded dark-mode colors across all screens with theme-aware tokens that branch on `isDark`.

### Files Changed

#### Part 1 — Theme Token System
- `lib/app_theme.dart` — Added 8 new theme-aware properties: `cardShadow`, `heroShadow`, `stadiumOverlayColors`, `heroOverlayColors`, `matchCardOverlayColors`, `dotInactive`, `onImageText`, `subtleSurface`
- `lib/components.dart` — Updated PremiumCard, GlowIconButton, BottomNav, PillChip, TeamLogoWidget, PlayerAvatarWidget to use theme tokens

#### Part 2 — Home Screen
- `lib/screens/home/home_screen.dart` — Stadium backdrop, hero carousel, match cards, featured sections, status tabs, carousel dots all theme-aware
- `lib/components/home_components.dart` — HomeHeroCard overlays, shadows, text colors theme-aware

#### Part 3 — Matches Screen
- `lib/screens/matches/matches_screen.dart` — Stadium overlay, match card shadows, card overlays theme-aware

#### Part 4 — Schedule Screen
- `lib/screens/schedule/schedule_screen.dart` — Stadium overlay, match card shadows, VS badge theme-aware

#### Part 5 — Series Screen
- `lib/screens/series/series_list_screen.dart` — Stadium overlay, hero/list card shadows/overlays theme-aware
- `lib/screens/series/series_premium.dart` — Glass panels, status/glass tabs, empty state theme-aware
- `lib/screens/series/series_components.dart` — List cards, category chips, text colors theme-aware

#### Part 6 — Series Detail
- `lib/screens/series/series_detail_screen.dart` — Hero banner, overlay, text-on-image, captain badge theme-aware

#### Part 7 — Match Details
- `lib/screens/match_details/match_details_screen.dart` — Commentary text theme-aware
- `lib/screens/match_details/widgets/match_details_ui.dart` — Glass panels, hero scorecard, overlays theme-aware
- `lib/components/match_details_components.dart` — Match card overlay, VS text theme-aware

#### Parts 8-9 — Player, More, Rankings, Teams, News, Highlights
- `lib/screens/rankings/rankings_screen.dart` — Card shadow theme-aware
- `lib/components/series_components.dart` — Card overlay theme-aware
- `lib/components/highlights_components.dart` — Card overlay theme-aware
- `lib/components/news_components.dart` — Category pill bg theme-aware
- `lib/widgets/home_hero_card.dart` — Shadows/overlay theme-aware
- `lib/screens/highlights/highlight_detail_screen.dart` — Overlay, play button, badges theme-aware
- `lib/screens/news/news_screen.dart` — Category pill bg theme-aware
- Player Profile and More/Teams already used theme tokens (no changes needed)

### Commands Run
- `flutter analyze lib/` — No issues found (ran after each part)
- `flutter pub get` — Dependencies resolved

### Test Results
- `flutter analyze` passes with 0 issues across entire lib/

### Pending Issues
- Parts 10-11 (Backend/Admin image management & controls) deferred — requires server-side API/database changes outside this PR's scope
- Visual QA at 360dp width not performed (requires running app with connected backend)

## 2026-07-14 - Home final visual cleanup

Changed files:
- `lib/screens/home/home_screen.dart`
- `lib/screens/home/widgets/home_hero.dart`
- `lib/screens/home/widgets/home_match_cards.dart`
- `lib/screens/home/widgets/home_featured.dart`
- `HOME_VISUAL_EVIDENCE.md`
- `AI_TASK_LOG.md`

Commands/results:
- `dart format` on changed Home/test files: passed.
- Scoped `flutter analyze --no-pub`: no errors/warnings; 3 existing info notices.
- Hero overflow suite: 4/4 passed.
- Score resilience + behavior + feed suites: 38/38 passed.
- Default visual-evidence render suite: 12/12 passed.
- Dimensions rerun stalled before first test output; terminated, not claimed.
- Gated raster write deadlocked after capture on Windows; only the 352x856
  single PNG refreshed, with the prior 11 evidence PNGs retained.

Pending:
- Physical-device review of darkness, glow restraint, and premium balance.
