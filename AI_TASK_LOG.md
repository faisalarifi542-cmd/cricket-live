# AI Task Log

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
