# Live Commentary Complete-History Fix Report — CricPro

## 1. Root cause

The previous fix made `/app/live-commentary` an **arbitration** endpoint: `/comm`
(≤20 items) primary, `/balls-map` fallback, capped at `LIVE_COMMENTARY_MAX_ITEMS`
(40). That fixed the "latest ball 1.2 vs 1.3" lag but **replaced the complete
commentary history with a tiny latest page**. Consequences in Match Details → Comm:
- `All` showed only the recent ~20–40 balls, many as generic `COMMENTARY`.
- `Wickets` / `Boundaries` showed only what happened to be in that small page.
- `Key Events` was empty because `/comm` items carried no `isKeyEvent` flag.

The app already had an authoritative complete feed (`buildCommentaryFeed` →
`/match/:id/full-commentary`) that classifies, dedupes and flags every entry. The
fast endpoint simply wasn't using it.

## 2. Files inspected

Backend:
- `cricket-api/src/routes/app.js` — `/app/live-commentary` (rewritten),
  `/app/live-scores` (warm `livefast:{id}` score cache reused).
- `cricket-api/src/routes/matches.js` — existing `/match/:id/full-commentary`
  (the layered full-feed pattern this now mirrors).
- `cricket-api/src/providers/cricbuzz/normalizer.js` — `buildCommentaryFeed`,
  `classifyCommentaryItem`, `normalizeFullCommentary`, `normalizeCommentary`,
  `normalizeBallsMap`.
- `cricket-api/src/providers/cricbuzz/index.js` — `getFullCommentary`,
  `getCommentary`, `getBallsMap`.
- `cricket-api/src/lib/redis.js` — `cacheGetOrFetch`, `cacheGet`, `unwrapSWR`,
  `KEYS.fullCommentary`, `TTL.FULL_COMMENTARY_LIVE/DONE`.

Flutter:
- `lib/services/cricket_api_service.dart` — `liveCommentary` mapping.
- `lib/repositories/cricket_repository.dart` — `matchLiveCommentary`,
  `_accumulateCommentary`.
- `lib/services/commentary_cache.dart` — no-removal merge + canonical key.
- `lib/screens/match_details/match_details_screen.dart` — poll, terminal stop,
  `_logCommentaryFreshness`.
- `lib/screens/match_details/widgets/md_timeline.dart` — `_CommentaryTimelineItem`.
- `lib/screens/match_details/widgets/md_panels.dart` — filter logic (All / Wickets
  / Boundaries / Key Events).

## 3. Why full-commentary must be authoritative

`/full-commentary/{innings}` is the only source that returns the **complete**
innings ball-by-ball with rich prose. `buildCommentaryFeed` already turns the
per-innings lists into one newest-first, de-duped, fully classified feed with
`type`/`label`/`isBall`/`isWicket`/`isBoundary`/`isKeyEvent` — exactly the fields
the Comm tab + filters consume. `/comm` and `/balls-map` are latest-only and
classification-poor, so they can supplement but never replace the feed.

## 4. New layered source strategy

`/app/live-commentary` per id (single-flight preserved):

1. **Score state** from warm `livefast:{id}` cache — latest over + `current_innings`
   + status. No extra provider call.
2. **Authoritative base** — `fetchFullFeed`: fetch `/full-commentary/{n}` for each
   innings (n = 1..inningsCount), build with `buildCommentaryFeed`. Per-innings
   `Promise.allSettled` so one empty/failed innings never fails the whole feed.
   - Live innings 1 → fetch innings 1. Live innings 2 → innings 1 + 2.
   - Completed match → all innings that exist (scorecard bumps Tests to ≤4).
   - Unknown current innings → tries both, keeps non-empty.
3. **Latest-ball supplement** — ONLY when the feed's latest ball is behind the live
   score (ball-index), or the feed is empty: fetch `/comm`; if still behind, fetch
   `/balls-map` for the current innings. Normalized to the feed item shape.
4. **Merge** — feed is the base; supplement only ADDS deliveries the feed lacks
   (keyed by innings + over.ball). Feed's richer text always wins; a supplement
   never overwrites a feed row. Sorted newest innings → newest ball → timestamp.
5. `completeHistory = feed has items`. `providerLag = merged latest < score`.

Priority is exactly: full history first; `/comm` updates newest prose only if
fresher; `/balls-map` adds a latest placeholder only if both are behind; a tiny
page never replaces the full list.

## 5. Cache strategy

Two layers, no Cricbuzz overload:

1. **Full-commentary per innings** — `match:{id}:full-comm:{n}` (shared
   `KEYS.fullCommentary`, same key `/match/:id/full-commentary` already uses):
   - Current/live innings → `TTL.FULL_COMMENTARY_LIVE` (15s).
   - Already-completed innings (match done, or innings < current) →
     `TTL.FULL_COMMENTARY_DONE` (6h) — settled, won't change, so no re-fetch.
   - Shared with the Live-tab full-commentary route → one warm cache, not two.
2. **Fast latest** — `livecomm:{id}`, 5s TTL + 11s physical grace, holds the merged
   list + freshness metadata. Single-flight per id.

Stale-on-error returns the last good merged (full) feed. A failed/partial supplement
can never wipe the full feed (feed is fetched first and is the base). Only the
current live innings pays the short-TTL fetch; settled innings are served from the
6h cache.

## 6. Merge / dedup / sort logic

- **Backend** (feed + supplement): key `b:<innings>:<over>.<ball>` for balls,
  `n:<innings>:<id|text>` for notes. Feed first → supplement only fills gaps. Sort:
  innings desc, ball-index desc, timestamp desc.
- **Ball index, not decimal**: `floor(over)*6 + ball`. A combined `"17.4"` is split
  so 17.4 ≠ decimal — `17.4` → over 17 ball 4 → index 106.
- **Client** (`CommentaryCache`, unchanged): canonical key
  `b:<innings>:<over.ball>` collapses the same delivery from any source; no-removal
  (old balls kept), deterministic newest-first sort, longer text wins on update.
  Backend feed shape (`over`="17.4", `innings`, `isBall`) matches the cache's
  expectations, so feed + supplement dedupe to one row each.

## 7. Filter logic

Filters operate on the complete merged list (`md_panels.dart`):
- **All** — every ball + note.
- **Wickets** — `isBall && isWicket` (`buildCommentaryFeed` sets `isWicket` from the
  `WICKET` event flag / wicketData).
- **Boundaries** — `isBall && (type four|six || isBoundary)`.
- **Key Events** — `isKeyEvent`, set by the builder for wickets, fours, sixes,
  milestones (fifty/hundred/team), and key notes (innings break, drinks, rain,
  presentation, result …). No longer falsely empty because the full feed carries
  these flags across the whole innings, not just a 20-item page.

## 8. Visual classification

`buildCommentaryFeed`'s `classifyCommentaryItem` already emits the correct pill:
`DOT BALL`, `1 RUN`/`2 RUNS`/`3 RUNS`, `FOUR`, `SIX`, `WICKET`; non-ball narrative →
`note` with `COMMENTARY`/`INFO`/`UPDATE`/`INNINGS BREAK`/`PRESENTATION`. Supplement
items (comm/balls-map) are classified into the same shape via `classifyBall` +
`toFeedShape`, so a delivery the feed hasn't narrated yet still renders a proper
pill (never blank, never generic). Left rail: ball rows carry `over` ("17.4") +
`teamShort` + colored chip (wicket red, four/six bright, dot muted, runs cyan);
notes use a neutral dot with no over. No widget layout changed — premium dark/cyan
styling and card sizes preserved.

## 9. Response shape, headers, logs

Response `data[]` per match now includes:
`items` (complete merged feed), `latestOver`, `scoreOver`, `source`
(`full-commentary` | `full-commentary+comm` | `full-commentary+balls-map` | `comm`
| `balls-map`), `sourceCandidates` (`[{source,latest,count}]` incl.
`full-commentary/1`, `full-commentary/2`), `providerLag`, `completeHistory`.
`meta` mirrors `source`/`providerLag`/`completeHistory`.

Headers: `X-Commentary-Latest`, `X-Commentary-Score-Over`, `X-Commentary-Source`,
`X-Commentary-Provider-Lag`, `X-Commentary-Complete-History`, `X-Cache`,
`X-Cache-Age-Ms`, `X-Stale`. No urls/keys/tokens logged or returned.

Backend log:
```
LIVE_COMMENTARY_FULL: match=121835 cache=MISS innings=1,2 fullCounts=120,95 source=full-commentary+comm scoreOver=17.4 latest=17.4 complete=true providerLag=false candidates=full-commentary/1:120,full-commentary/2:95,comm:20 count=215 providerMs=...
```

Flutter debug log (`_logCommentaryFreshness`):
```
CricProCommentaryPoll: match=121835 tab=Comm items=215 all=215 wickets=8 boundaries=17 keyEvents=29 scoreOver=17.4 latestCommentaryOver=17.4 source=full-commentary+comm completeHistory=true providerLag=false applied=true
```

## 10. Commands run

```
node --check cricket-api/src/routes/app.js      # OK
node --check cricket-api/src/server.js          # OK
flutter analyze lib/                            # No issues found
```

curl verification (Task 10) needs a live match + api key, left for device QA:
```
curl -sD - -o /tmp/live-commentary.json -H "Accept: application/json" -H "x-api-key: <key>" \
  "https://<host>/app/live-commentary?ids=121835" \
  | grep -i -E "http/|x-cache|x-cache-age-ms|x-stale|x-commentary|cache-control"
cat /tmp/live-commentary.json | jq '.data[0] | {latestOver, scoreOver, source, completeHistory, providerLag, count: (.items|length), candidates: .sourceCandidates}'
```
Expect `completeHistory:true`, `count` ≫ 20 for late-innings/completed matches,
`latestOver` matching `scoreOver` when a source has it.

## 11. Device QA checklist

- [ ] Comm tab `All` shows the COMPLETE innings history (count ≫ 20), not a recent page.
- [ ] `Wickets` shows every wicket; `Boundaries` every four/six; `Key Events` not empty.
- [ ] Latest live ball stays fresh (matches hero score over); supplement adds it when
      full-commentary lags one ball.
- [ ] Delivery pills correct: DOT BALL / N RUNS / FOUR / SIX / WICKET; notes → COMMENTARY/INFO.
- [ ] Left rail: over (17.4) + team code + colored chip; notes neutral.
- [ ] Old commentary never disappears on a poll; no duplicates; new balls insert at top.
- [ ] No blink/jump, no tab reset, no scroll reset on silent poll.
- [ ] Pull-to-refresh forces refresh; a partial/failed response keeps the old good list.
- [ ] Live tab preview shows newest 5–8 from the same merged cache; "View More
      Commentary" expands to the full list.
- [ ] Completed match: both innings load complete; live polling stops; feed stays cached.
- [ ] Backend log shows `LIVE_COMMENTARY_FULL ... complete=true fullCounts=...`; settled
      innings served from long-TTL cache (no repeated full-commentary fetch).
- [ ] Headers present incl. `X-Commentary-Complete-History`.

## Files changed

- `cricket-api/src/routes/app.js` — `/app/live-commentary` rewritten to layered
  full-history + latest-ball supplement; new imports (`cacheGetOrFetch`, `cacheGet`,
  `unwrapSWR`, `KEYS`, `TTL`, `buildCommentaryFeed`); `completeHistory` +
  `X-Commentary-Complete-History` added; `LIVE_COMMENTARY_FULL` log.
- `lib/services/cricket_api_service.dart` — `liveCommentary` passes through
  `completeHistory`, default source `full-commentary`.
- `lib/screens/match_details/match_details_screen.dart` — `_logCommentaryFreshness`
  now logs items/all/wickets/boundaries/keyEvents/completeHistory.

## Left unchanged

- `CommentaryCache`, `_accumulateCommentary`, filter UI, timeline widget, ball-chip
  styling — already correct; they just receive the complete feed now.
- `/match/:id/full-commentary` route and all other endpoints, TTL constants, polling
  cadence, ads/auth/streaming. No release build run.

## Risks / unverified

- curl + on-device visual confirmation not run here (needs live match + key) — listed
  in §11.
- Per-innings full-commentary adds at most one short-TTL fetch for the live innings per
  cache window (settled innings cached 6h, single-flight shared) — verify provider load
  on device with the `LIVE_COMMENTARY_FULL` log.
