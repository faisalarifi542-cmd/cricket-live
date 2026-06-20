# Live Commentary Freshness Fix Report — CricPro

Fixes the confirmed live bug: Match Details hero score reaches the 9th over while
the Commentary tab still shows 6.3 / 6.2 / 6.1 (commentary 2+ overs behind). The
root cause was in the client merge, not the visual layer. A fast backend
commentary source and freshness instrumentation were added alongside.

No release APK / appbundle built. `flutter analyze lib/` clean; `node --check` on
both changed backend files passes.

---

## 1. Files inspected

Flutter:
- `lib/screens/match_details/match_details_screen.dart` — tab load, silent poll,
  pull-to-refresh, lifecycle, hero.
- `lib/screens/match_details/widgets/live_match_tab.dart` — Live tab commentary
  preview source.
- `lib/screens/match_details/widgets/md_panels.dart` — `_CommentaryPanel` (renders
  in array order, no re-sort).
- `lib/services/commentary_cache.dart` — no-removal accumulator (**root cause**).
- `lib/repositories/cricket_repository.dart` — commentary repo methods + accumulator.
- `lib/services/cricket_api_service.dart` — endpoint calls.
- `lib/core/api/api_client.dart` — `allowFailure` support.
- `lib/models/cricket_match.dart` — summary parsing / innings overs.

Backend:
- `cricket-api/src/routes/app.js` — `/app/live-scores` fast pattern (mirrored).
- `cricket-api/src/routes/matches.js` — `/match/:id/full-commentary` and the other
  commentary routes + TTLs.
- `cricket-api/src/providers/cricbuzz/normalizer.js` — `normalizeCommentary`
  (`/comm`), `buildCommentaryFeed`, `classifyCommentaryItem` (item shapes).
- `cricket-api/src/providers/cricbuzz/index.js` — `getCommentary` registration.
- `cricket-api/src/lib/redis.js` — cache TTLs.
- `cricket-api/src/server.js` — live-family no-store list.

---

## 2. Current commentary data path (as traced)

| UI area | Repo method | Backend endpoint | Provider source | TTLs (client / server) |
|---|---|---|---|---|
| Match Details hero score | `matchDetail` | `GET /match/:id` | `/livescore/{id}` (miniscore) | 5s / 15s |
| Live tab body | `matchLiveCenter` | `GET /match/:id/live-center` | merged | 4s / 4s |
| Live tab commentary preview | (now) `matchLiveCommentary` | `GET /app/live-commentary` | `/comm/{id}` | 3s / 5s |
| Full Commentary tab | (now) `matchLiveCommentary` | `GET /app/live-commentary` | `/comm/{id}` | 3s / 5s |
| "View More Commentary" button | — | (in-page `_setTab(4)`, no new fetch; then local paging `_shown += 80`) | — | — |
| Pull-to-refresh (Comm/Live) | (now) `matchLiveCommentary` force | `GET /app/live-commentary` | `/comm/{id}` | bypass |
| Silent poll (5s, Live/Comm tab) | (now) `matchLiveCommentary` force | `GET /app/live-commentary` | `/comm/{id}` | bypass |

Before this change the Live preview and Commentary tab both used
`matchFullCommentary` → `GET /match/:id/full-commentary` (server TTL 15s, built
from `getFullCommentary` per-innings, which lags the live `/comm` feed).

Hero score is fed by an independent, always-5s-fresh `/match/:id`, which is why it
kept advancing while commentary stalled.

---

## 3. Root cause of the 2+ over lag

`CommentaryCache.merge` (`lib/services/commentary_cache.dart`) was ordering the
list by **response arrival order**, not by real freshness:

```dart
final newOrder = <String>[...freshKeys, ...retained]; // OLD
```

It put *whatever the latest poll returned* at the top. Live providers periodically
re-emit an older or partial page (e.g. overs 6.1–6.3) on a later poll. Those
became `freshKeys` and were floated above the already-seen newer deliveries (8.x /
9.x), which sank into `retained`. `_CommentaryPanel` renders the list in array
order with no re-sort, so the UI showed 6.3 on top while the score was in the 9th
over. `hardReset` only fires on a terminal match, so during live play the stale
page stayed trapped until a pull-to-refresh.

Contributing (but not sufficient alone): TTL stacking (~23s worst case) and the
fact that `full-commentary` (server TTL 15s) is structurally a few balls behind
the live `/comm` feed.

This is a structural ordering defect visible in the code, independent of any
specific provider payload — confirmed by reading the merge, the repo accumulator,
and the panel (which does no sorting of its own).

---

## 4. Backend / source changes

### New fast endpoint — `GET /app/live-commentary?ids=<matchId>` (`app.js`)
Mirrors `/app/live-scores` exactly:
- Provider source: `providerManager.execute('getCommentary', id)` → Cricbuzz
  `/comm/{id}`, the freshest latest-over ball-by-ball feed (the one Cricbuzz's own
  live page polls). NOT the heavy per-innings `full-commentary`.
- Tiny dedicated Redis key `livecomm:{id}`, TTL `LIVE_COMMENTARY_FAST_TTL_MS`
  (default **5s**), physical TTL = ceil(TTL)+11s grace.
- **Per-id single-flight** via `liveCommentaryInflight` Map so many pollers share
  one provider call.
- **Stale-on-error**: serves the last cached list with `cache=STALE` on provider
  failure; never blanks.
- Returns only the latest `LIVE_COMMENTARY_MAX_ITEMS` (default 40) normalized
  lines — no heavy match detail.
- Does **not** touch the shared `match:{id}:commentary` SWR key, so it cannot
  clobber the Live-tab / full-commentary caches.
- Debug headers: `X-Cache` (HIT/MISS/STALE/ERROR), `X-Cache-Age-Ms`, `X-Stale`,
  `X-Commentary-Source` (`comm`), `X-Commentary-Latest` (`<id>:<over.ball>` per id,
  log-safe — no urls/keys).

### `server.js`
Added `/app/live-commentary` to the live-family `no-store` list so no
browser/Dio/CDN caches a live commentary response.

No existing route changed; no TTL changed. An older app build still works (it just
never calls the new route).

---

## 5. Flutter polling changes

- `cricket_api_service.dart`: new `liveCommentary(matchId)` → `GET /app/live-commentary`
  (`allowFailure: true`), unwraps the single-id row to `{ items, source, latestOver,
  cacheStatus }`.
- `cricket_repository.dart`: new `matchLiveCommentary(matchId)` — 3s client cache,
  merges through the **same** `CommentaryCache` accumulator as `matchFullCommentary`,
  and **falls back to `matchFullCommentary` when the fast source is empty** (older
  backend / provider hiccup) so the UI is never blanked.
- `match_details_screen.dart`:
  - `_loadTab(4)` (Commentary tab) now uses `matchLiveCommentary`.
  - Silent poll (5s, live): Commentary tab (4) and the Live tab's (1) background
    preview refresh both use `matchLiveCommentary` instead of `matchFullCommentary`.
  - Pull-to-refresh commentary uses `matchLiveCommentary(forceRefresh: true)`.
  - **Resume-with-immediate-refresh**: on `AppLifecycleState.resumed`, after
    re-arming the poll timer it fires one `_silentPollLiveMatch()` so a match
    watched from Live/Comm catches up instantly instead of after the next 5s tick.

Polling cadence unchanged at 5s for live matches; only the commentary list/preview
update in place (no full-page reload, hero/tab unchanged). Polling still pauses on
background and stops on terminal state (unchanged).

---

## 6. Commentary cache merge / no-removal logic

Rewrote `CommentaryCache.merge` to keep no-removal but order by **real freshness**,
not arrival order:

- Upsert every incoming item; never delete a previously-seen item.
- Build the union of all known keys, then **sort deterministically newest-first**:
  innings desc → canonical over.ball desc → provider timestamp desc → prior display
  index (stable tie-break, prevents blink).
- Newer overs therefore always lead even if a later poll re-emits an older page;
  older comments stay below; the list still only grows during live play.
- Dedup key made **canonical and source-agnostic**: `b:<innings>:<over.ball>` for
  deliveries (was `id:<id>` first). The fast `/comm` source emits `over` int +
  `ball`, while `full-commentary` emits `over` = "8.4" with different ids — the old
  key would have duplicated the same ball across the two sources. The canonical key
  collapses them; `_mergeItem` still keeps the longer (fuller) text. Notes key on
  explicit id, then text hash.
- New freshness helpers: `_inningsOf`, `_overValueOf` (handles both "8.4" and
  int+ball shapes), `_timestampOf`.

Result: old comments do not disappear; newer 9th-over comments appear above old
6th-over comments; no duplicates across sources; sorted innings + over + ball
newest-first; stable order = no blink.

---

## 7. Freshness comparison logic (score over vs commentary over)

Two layers:

- **Backend**: `/app/live-commentary` returns `latestOver` per id and logs
  `LIVE_COMMENTARY_FAST: ... latest=<over.ball>` so the provider's freshness is
  visible server-side.
- **Flutter** (`_logCommentaryFreshness` in `match_details_screen.dart`, debug
  only): on each Live/Comm poll, parses the current live over from the fresh score
  summary (`_scoreOver`) and the latest commentary over (`_latestCommentaryOver`),
  then flags lag against a format-aware threshold (T20 ≤20 ov → 1 over; ODI/Test →
  2 overs) and logs `applied`.

Because the app now polls the freshest provider feed (`/comm`) directly, the more
aggressive auto-source-switching among quick-access / over-by-over / balls-map was
**not** needed: `/comm` is the source those would fall back from, not to. The
freshness log makes any *residual* lag attributable — if `scoreOver=9.0` while
`latestCommentaryOver=6.3` with `cache=HIT` and the backend log shows the same
`latest=6.3` from `/comm`, the staleness is provably **provider-side**, not app or
cache side. (Documented honestly rather than masked.)

---

## 8. Pull-to-refresh behavior

`_refreshCurrentTab` force-refreshes the summary + the visible tab + scorecard +
live-center + commentary + overs in parallel, restoring scroll offset. Commentary
now force-fetches `matchLiveCommentary` (bypasses the 3s client cache; backend
serves fresh `/comm` or single-flight). Merge is no-removal, so a temporary network
error keeps the existing cached commentary rather than wiping it. Offline shows the
no-internet UI; reconnect + pull recovers and re-arms polling.

---

## 9. Debug logs added

Flutter (debug mode only):
- `CricProCommentaryPoll: match=<id> tab=<Live|Comm> scoreOver=<x> latestCommentaryOver=<y> source=<comm> applied=<bool> cacheSize=<n>`
- `CricProCommentaryMerge: bucket=<full> match=<id> incoming=<n> added=<n> updated=<n> kept=<n> total=<n> latest=<over.ball>`

Backend:
- `LIVE_COMMENTARY_FAST: match=<id> route=/app/live-commentary source=comm cache=<HIT|MISS|STALE|ERROR> age=<ms> [providerMs=<ms>] latest=<over.ball> count=<n>`
- Response headers `X-Cache`, `X-Cache-Age-Ms`, `X-Stale`, `X-Commentary-Source`,
  `X-Commentary-Latest`.

No secrets, URLs, or API keys are logged (matches the existing `/app/live-scores`
log-safe convention).

These three signals together localize any future staleness to Flutter merge,
backend cache, or provider source.

---

## 10. Visual / image-source fixes (Task 8)

Verified state (no code change required for 1–3; they were already done):
1. **Home hero score hierarchy** — DONE. `home_hero.dart`: score `w900` at 33–46px
   responsive; overs `w700` at ~0.46× score; "Yet to bat" `w600` 13.5px muted.
2. **Match Details hero hierarchy** — DONE. `match_details_ui.dart` `MDTeamScoreBlock`:
   score 26 `w900`, overs 12 `w600` muted, code 17 `w900`.
3. **Schedule screen** — DONE. `schedule_cards.dart`: primary uses `teamCodeOf`
   (AFGA→AFG A), `maxLines:1 / softWrap:false / ellipsis`; full name is the muted
   secondary; date/time on its own line. No "Afghanis..." as the main label.

4. **Player images admin-source rule** — **GAP, intentionally not built here.**
   There is no Admin-Panel "player image source" flag in `AppConfig` at all, and no
   shared resolver enforcing "admin-only → no provider face / missing → initials".
   All five surfaces (Rankings, Player Profile, Scoreboard, Squads, Series stats)
   correctly fall back to initials when no image exists, and Squads/Scoreboard/Series
   already reject synthesized/index-guessed faces (`resolvePlayerImageUrl`,
   `_verifiedSquadImage`). But Rankings (`api_models.dart` `RankingEntry.fromJson` →
   `resolveCricbuzzImageUrl`) and Player Profile (`ApiPlayer.fromJson` synthesizes
   `static.cricbuzz.com/.../c<imageId>/i.jpg`) still use provider faces directly.
   Enforcing admin-only requires a new `AppConfig` flag + backend wiring + an
   admin-panel toggle + edits across 5 screens — that is new-feature scope. Per the
   task's instruction not to let image-source work distract from the commentary bug,
   it is reported as a gap rather than half-implemented. Recommend a follow-up:
   add `playerImagesAdminOnly` to AppConfig and route all five through a single
   resolver that returns null (→ initials) when the flag is on and no admin image
   is present.

---

## 11. Checks run

- `flutter analyze lib/` → **No issues found**.
- `node --check cricket-api/src/routes/app.js` → OK.
- `node --check cricket-api/src/server.js` → OK.
- No admin TS files were changed (no admin check needed).
- No release APK / appbundle (per instruction).

Did not break (verified by inspection / analyze): Home score polling (untouched),
Match Details selected-tab stability (tab index logic unchanged), commentary
no-removal cache (preserved, only re-sorted), minimized score / overlay behavior
(`MinimizedScoreController.update` path unchanged), admin image-source rules
(unchanged), ads (untouched).

---

## 12. Remaining device-only QA checklist

- [ ] Open a live match, go to Commentary tab. Latest over matches the hero score
      over (within 1 ball typically). It does NOT sit 2+ overs behind.
- [ ] Watch the Commentary tab for ~30s during live play — new overs appear at the
      top; old overs remain below; no duplicates; no list blink/jump.
- [ ] Live tab preview shows the same latest over as the Commentary tab.
- [ ] Pull-to-refresh on a stale-looking Commentary list → jumps to the latest
      available over.
- [ ] Background the app for a minute during live play, reopen → commentary
      refreshes immediately (resume refresh), not after a 5s wait.
- [ ] Toggle airplane mode → no blank list (keeps cached commentary), offline UI
      where applicable; reconnect → recovers.
- [ ] Match completes → polling stops; final commentary remains.
- [ ] Capture device logs: confirm `CricProCommentaryPoll` shows
      `scoreOver ≈ latestCommentaryOver` and `applied=true`. If a gap persists,
      confirm backend `LIVE_COMMENTARY_FAST: ... latest=<x>` reports the SAME stale
      over from `/comm` — that proves the provider is the stale source, not the app.
- [ ] Switch among Score/Squad/Info/Overs and back to Comm — selected tab never
      resets, hero never blinks.
- [ ] (Follow-up, not in this pass) Player-image admin-only enforcement on Rankings
      + Player Profile.
