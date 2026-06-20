# Live Commentary Source Arbitration Report — CricPro

Fixes the residual lag: `/app/live-commentary` returned `/comm` latest `1.2` while
the live score was already `1.3`. Root issue was single-source dependence — `/comm`
sometimes trails the live miniscore by one ball. The endpoint now arbitrates
across Cricbuzz sources by **cricket ball index** and picks the freshest, and
deliveries now classify into proper DOT/RUN/FOUR/SIX/WICKET pills instead of a
generic COMMENTARY marker.

No release APK / appbundle. `flutter analyze lib/` clean; `node --check` on both
changed backend files passes.

---

## 1. Files inspected

Backend:
- `cricket-api/src/routes/app.js` — `/app/live-commentary` + `/app/live-scores`
  (warm score cache reused for arbitration).
- `cricket-api/src/providers/cricbuzz/index.js` — `getCommentary`, `getBallsMap`,
  `getOverByOver`, `getQuickAccess`, `getMatchInfo`, `getFullCommentary`.
- `cricket-api/src/providers/cricbuzz/normalizer.js` — `normalizeCommentary`
  (`/comm`), `normalizeBallsMap`, `normalizeOverByOver`, `normalizeMatchDetail`
  (`current_innings`, innings overs).
- `cricket-api/src/providers/provider-manager.js` — `execute()` returns
  `{ data, provider }`.
- `cricket-api/src/server.js` — live-family no-store list (already includes the route).

Flutter:
- `lib/services/cricket_api_service.dart` — `liveCommentary`.
- `lib/repositories/cricket_repository.dart` — `matchLiveCommentary` + accumulator.
- `lib/screens/match_details/match_details_screen.dart` — poll + `_logCommentaryFreshness`.
- `lib/screens/match_details/widgets/md_timeline.dart` — `_CommentaryTimelineItem`
  (reads `isBall`/`type`/`label`).
- `lib/services/commentary_cache.dart` — no-removal merge + canonical key.

---

## 2. Source comparison results (by shape + freshness behavior)

| Source | Provider method | Granularity | Latest-ball freshness | Carries classification? |
|---|---|---|---|---|
| `/comm/{id}` | `getCommentary` → `normalizeCommentary` | ball + prose | Usually freshest, but **can trail the miniscore by 1 ball** | No (only `event`+`runs`) |
| `/livescore/{id}` | `getMatchInfo` → `normalizeMatchDetail` | score/over only | Freshest over (drives hero) | n/a (no commentary) |
| `/quick-access/{id}` | `getQuickAccess` | mixed/raw | not reliably ball-fresh | varies |
| `/over-by-over/{id}/{inn}` | `getOverByOver` | **over-level only** | over granularity — cannot express 1.3 within an over | No |
| `/balls-map/{id}/{inn}` | `getBallsMap` → `normalizeBallsMap` | **ball-level** (`overNumber`, `ballNumber`, `event`, `totalRuns`) | Advances per delivery — surfaces 1.3 when `/comm` shows 1.2 | derivable from `event`/`totalRuns` |
| `/full-commentary/{inn}` | `getFullCommentary` | full innings history | heavier; not preferred for "latest" | yes |

Conclusion: the live **score** path (`/livescore`) is the freshness reference; the
freshest *ball-level* commentary fallback is **`/balls-map`** (over-by-over is too
coarse to resolve a within-over ball, full-commentary is heavy). So arbitration =
`/comm` primary, `/balls-map` (current innings) fallback, compared by ball index.

---

## 3. Why `/comm` alone was not enough

`/comm` is the prose feed Cricbuzz's live page polls, but its publish cadence can
sit one delivery behind the miniscore that feeds the score/over. The server log
proved it: `source=comm latest=1.2` repeatedly while the hero was at `1.3`. There
is no app/cache bug there — the single source itself was stale. A second
ball-level source (`/balls-map`) often already has the `1.3` ball, so comparing
them and choosing the newer fixes it.

---

## 4. New source arbitration logic (`/app/live-commentary`)

On cache MISS, per id (single-flight preserved):
1. Read current **score over** from the warm `livefast:{id}` cache written by
   `/app/live-scores` — **no extra provider call** in the common case.
2. Fetch `/comm` (primary). Compute its latest ball index.
3. **Only if** `/comm` latest ball index `<` score ball index, fetch
   `/balls-map` for the current innings (one extra call, on lag only).
4. Normalize balls-map rows into the comm item shape (`ballsMapToItems`).
5. **Merge** comm + balls-map, de-duped by innings + canonical over.ball; `/comm`
   text preferred, balls-map contributes any ball `/comm` hasn't delivered yet.
6. `source` = whichever had the newest ball (`comm` or `balls-map`).
7. Classify every item into the app timeline shape (`toAppItem`, see §8).
8. Cache the merged list (5s TTL + grace) with freshness metadata; stale-on-error
   preserved (serves last cached list + `cache=STALE`).

Cricbuzz load: unchanged when `/comm` is current; +1 call (`/balls-map`) only while
`/comm` is actually behind, shared across pollers by single-flight.

---

## 5. Ball-index comparison logic

All over comparisons use cricket ball index, never decimal math:

```
ballIndex(over, ball) = floor(over) * 6 + ball
1.3 -> 1*6 + 3 = 9 ;  2.0 -> 12 ;  1.5 -> 11
```

`overBallOf("1.2")` → `{over:1, ball:2}`. `latestBallOf(list)` returns the row with
the highest ball index (notes ignored). `scoreLatestFromProjection` scans both
teams' innings overs from the cached score projection and returns the newest.
`providerLag = scoreIdx >= 0 && mergedLatestIdx < scoreIdx`. Decimal compares are
explicitly avoided (1.6 is NOT > 2.0 as deliveries).

---

## 6. Cache / single-flight behavior

- Tiny dedicated Redis key `livecomm:{id}`, TTL `LIVE_COMMENTARY_FAST_TTL_MS`
  (default 5s), physical TTL = ceil(TTL)+11s grace. Unchanged from before.
- Per-id single-flight via `liveCommentaryInflight` Map — concurrent pollers share
  one arbitration pass.
- Cache envelope now also stores `src`, `so` (scoreOver), `lag` (providerLag),
  `cand`/`candArr` (candidates) so HIT/STALE responses carry the same metadata.
- Does NOT touch the shared `match:{id}:commentary` SWR key. No existing TTLs
  changed. No new route; older app builds keep working.

---

## 7. Flutter providerLag handling

- `cricket_api_service.dart` `liveCommentary` now passes through `scoreOver`,
  `providerLag`, `sourceCandidates`.
- `_logCommentaryFreshness` (debug only) prefers the backend `providerLag` verdict
  (already arbitrated by ball index), falling back to a local compare for an older
  backend:
  `CricProCommentaryPoll: match=<id> tab=<Live|Comm> scoreOver=<x> latestCommentaryOver=<y> source=<src> providerLag=<bool> applied=true cacheSize=<n>`.
- UI behavior per Task 5: it keeps showing the best-available commentary and does
  **not** render an error for normal one-ball provider lag. The no-internet UI is
  reserved for actual network failure (unchanged). No lag banner was added — a
  badge for routine one-ball lag would be the "ugly indicator" the task warns
  against; the lag is surfaced via logs/headers for QA instead.

---

## 8. Commentary visual classification improvements

Root cause of the generic `COMMENTARY` pills: the fast `/comm` items carry only
`event` + `runs`, not the `isBall`/`type`/`label` fields the timeline
(`_CommentaryTimelineItem`) reads — so every fast item fell through to the
`COMMENTARY` fallback. Fixed server-side with `toAppItem`, applied to every merged
item before caching:

- `no run` → `DOT BALL` (`type:dot`)
- `1 run` → `1 RUN`, `2 runs` → `2 RUNS` (`type:run`)
- `FOUR` → `FOUR` (`type:four`), `SIX` → `SIX` (`type:six`)
- wicket/out → `WICKET` (`type:wicket`)
- non-ball narrative → `note` / `COMMENTARY`
- `over` emitted as display `"1.3"`, `teamShort` preserved, `isBall:true` set so the
  left timeline shows the over + team code and the correct colored ball chip
  (W/6/4/0/runs) instead of a blank gray marker.

Balls-map fallback rows are classified the same way (`classifyBall`) and carry the
short label as text so a delivery `/comm` hasn't narrated yet still renders a
proper pill, not a blank card. No widget layout changed — cards keep the existing
premium dark/cyan design and size; only the data now classifies correctly.

---

## 9. No-removal cache (Task 7) — verified

`CommentaryCache.merge` is unchanged and still correct with multi-source items:
- Canonical key `b:<innings>:<over.ball>` — both `/comm` and balls-map rows pass
  through `toAppItem` so they share the same `over`="1.3" format → no cross-source
  duplicates.
- Deterministic newest-first sort (innings → over.ball → timestamp → stable index).
- Old comments never removed when a poll returns a partial list; newer balls insert
  at top; older stay below; stable order (no blink/jump); selected tab untouched.

---

## 10. Commands run

```
node --check cricket-api/src/routes/app.js      # OK
node --check cricket-api/src/server.js          # OK
flutter analyze lib/                            # No issues found
```

Device curl verification (Task 8) is environment-dependent (needs a live match +
api key) and is left for device QA. Expected:

```
curl -sD - -o /tmp/live-commentary.json \
  -H "Accept: application/json" -H "x-api-key: <key>" \
  "https://<host>/app/live-commentary?ids=121835" \
  | grep -i -E "http/|x-cache|x-cache-age-ms|x-stale|x-commentary|cache-control"
cat /tmp/live-commentary.json | jq ".data[0].latestOver,.data[0].scoreOver,.data[0].source,.data[0].providerLag,.data[0].sourceCandidates"
```
Expect `latestOver` to match `scoreOver` (e.g. `1.3`) when any source has it, with
`source:"balls-map"` and `providerLag:false`; if every source is stale, `1.2` with
`providerLag:true` and `sourceCandidates` proving both `comm` and `balls-map` were
behind.

Response headers added: `X-Commentary-Latest`, `X-Commentary-Score-Over`,
`X-Commentary-Source`, `X-Commentary-Provider-Lag`, plus existing `X-Cache`,
`X-Cache-Age-Ms`, `X-Stale`. No urls/keys/tokens logged or returned.

---

## 11. Remaining device QA checklist

- [ ] Live match, Match Details Comm tab: latest commentary over matches the hero
      score over (e.g. both `1.3`); not stuck on `1.2` when balls-map has `1.3`.
- [ ] Server log shows `LIVE_COMMENTARY_FAST: ... source=balls-map scoreOver=1.3 latest=1.3 providerLag=false candidates=comm:1.2,balls-map:1.3`
      when `/comm` lagged.
- [ ] If every source is stale: log shows `providerLag=true` with candidates proving
      all checked sources were behind, and the response/header agree.
- [ ] Delivery cards show proper pills: DOT BALL / 1 RUN / FOUR / SIX / WICKET; left
      rail shows over (`1.3`) + team code + colored ball chip; no blank gray markers.
- [ ] Non-ball narrative still shows COMMENTARY/note styling.
- [ ] Old commentary not removed on a partial poll; new balls insert at top; no
      duplicates; no blink/jump; selected tab not reset; hero not jumping.
- [ ] `curl` headers present and correct; `Cache-Control: no-store` on the route.
- [ ] Provider-lag case shows best-available list with NO error UI; airplane mode
      still shows the no-internet UI; reconnect recovers.
