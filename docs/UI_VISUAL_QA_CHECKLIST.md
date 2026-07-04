# CricPro — UI Visual QA Checklist

Tracked against the targeted consistency + data-correctness + reconciliation passes.

**Status legend:** ✅ Fixed + device-verified · 🔧 Fixed (NOT yet device-verified) · ⏳ Remaining · ➖ N/A

**Device QA status: NOT YET RUN.** No emulator/device verification was performed this session — all fixes are verified by `flutter analyze` (clean), `flutter test` (192/192), and `flutter build apk --release` (exit 0, 79.8 MB). The "Device size tested" column is therefore **not yet** for every row. Device verification is required before release, especially for a live match and a stumps/lunch/tea/innings-break match.

**Device sizes to test when run:** 360 (compact), 390/400 (typical), 430+ (large), plus a high font-scale run.

---

## Bottom-nav screens

| Screen | Status | Issues fixed | Remaining issues | Screenshot needed | Device size tested |
|---|---|---|---|---|---|
| Home | 🔧 | Shared `CricLogo` wordmark; consolidated bell on `GlowIconButton`; phase-aware status badge (STUMPS/LUNCH/TEA vs LIVE); removed contradictory "LIVE NOW" + "Day 1 Stumps"; "Match Center" CTA label | Hero/list card shells still hand-rolled (intentionally out of scope) | yes | not yet |
| Home — Live tab | 🔧 | Phase-aware badge + center pill; pulsing dot suppressed at stumps/lunch/tea | — | yes | not yet |
| Home — Upcoming | 🔧 | "Match Center" CTA | — | yes | not yet |
| Home — Finished | 🔧 | Result badge via shared resolver | — | yes | not yet |
| Matches | 🔧 | Shared `CricLogo`; consolidated bell; phase-aware live badge; "Match Center" CTA; category filter uses canonical `UpcomingSort` | Status tabs still hand-rolled (out of scope) | yes | not yet |
| Matches — Live | 🔧 | Phase-aware badge (STUMPS etc.); pulsing dot only for active live | — | yes | not yet |
| Matches — Upcoming | 🔧 | "Match Center" CTA | — | yes | not yet |
| Matches — Finished | 🔧 | "Match Center" CTA | — | yes | not yet |
| Schedule | 🔧 | Per-card time line via shared `formatMatchDateTime` (Today/Tomorrow); day summary shows Today/Tomorrow; status pill routes through `MatchStatusDisplay` (STUMPS/LUNCH/TEA/INN BREAK + no pulsing dot during a stoppage) | Sorting already correct (verified, no change); date strip hand-rolled (out of scope) | yes | not yet |
| Series — All | 🔧 | Canonical sort (ongoing→upcoming→completed, within-section dates); shared `CricLogo` + bell | Filter chips hand-rolled (out of scope) | yes | not yet |
| Series — Ongoing | 🔧 | Sort: live-match series first, then start-date desc | — | yes | not yet |
| Series — Upcoming | 🔧 | Sort: soonest start date first | — | yes | not yet |
| Series — Completed | 🔧 | Sort: most-recent end date first | — | yes | not yet |
| More | 🔧 | "Floating Score Overlay" label (was truncated "Floating Score over oth…"); shared `AppHeader` + `GlowIconButton` already in use | — | yes | not yet |

## Match Details tabs

| Screen | Status | Issues fixed | Remaining issues | Screenshot needed | Device size tested |
|---|---|---|---|---|---|
| Match Details — Info | 🔧 | Info value `maxLines:2 + ellipsis` (long venue/teams no longer wrap unbounded) | — | yes | not yet |
| Match Details — Live | 🔧 | Scorecard via shared `TeamScoreView`; event types trust server `type`; extras (Wd/Nb/B/Lb) labelled; non-ball commentary notes show the server's own label; **live-state classifier treats stumps/lunch/tea/innings-break/rain as live** (no more "Live data will appear once the match starts" during a stoppage); **`_looksLikeResult` tightened so a live chase "India need X to win" is not classified finished**; **recent-over bubbles now render Wd/Nb/B/Lb in amber** (was a cyan "1" for a wide); **footer shows a real ticking "Updated X ago" or nothing, never fake "Updated just now"** | — | yes | not yet |
| Match Details — Score | 🔧 | Agrees with Live tab (both use `TeamScoreView`) | — | yes | not yet |
| Match Details — Squad | 🔧 | Dedicated Wicket-keepers group; "Playing XI not announced yet" empty state when only bench exists | — | yes | not yet |
| Match Details — Commentary | 🔧 | Event styling consistent with Live tab (server `type`); extras handled | Commentary ordering already correct (verified) | yes | not yet |
| Match Details — Overs | 🔧 | Dot vs missing ball distinguished (`•` vs `–`); extra-ball types (Wd/Nb/B/Lb) coloured amber; ball-colour legend added | — | yes | not yet |
| Match Details header | 🔧 | "Updated X ago" ticks every second; "Stale data, retrying" + "Offline cache" states | — | yes | not yet |

## Series detail tabs

| Screen | Status | Issues fixed | Remaining issues | Screenshot needed | Device size tested |
|---|---|---|---|---|---|
| Series Details — Overview | 🔧 | Status uses authoritative `classifySeriesStatus` (agrees with list card); "Match Center" CTA | — | yes | not yet |
| Series Details — Matches | 🔧 | Balanced team columns (match note moved to a centered row under both); status pill + note route through `MatchStatusDisplay` (STUMPS/LUNCH/TEA badge, no pulsing dot during a stoppage; note shows the phase label instead of "LIVE NOW") | — | yes | not yet |
| Series Details — Squads | ➖ | Not touched this pass (uses shared `PremiumSquad` which got the WK-group fix) | — | yes | not yet |
| Series Details — Stats / Points Table | 🔧 | Canonical sort (points→NRR→wins→name) **frontend** (`series_detail_stats.dart:136`); team code via `teamCodeOf` ("SL A" not "SRI LANKA A") | Backend does NOT sort standings (passes rows through in provider order); frontend sort is the single source | yes | not yet |
| Series Details hero | 🔧 | Shared `CricLogo`; removed hardcoded "3" notification badge → dot-only | — | yes | not yet |

## Secondary screens

| Screen | Status | Issues fixed | Remaining issues | Screenshot needed | Device size tested |
|---|---|---|---|---|---|
| ICC Men Ranking | 🔧 | Player name `maxLines:2` (no more "Travis …" truncation); tighter rank column + smaller avatar give name more width | — | yes | not yet |
| ICC Women Ranking | 🔧 | Same name-wrap/layout fix | — | yes | not yet |
| Teams | ➖ | Not touched this pass (no confirmed defect) | — | yes | not yet |
| Favorite Countries | ➖ | Not touched this pass | — | yes | not yet |

---

## Cross-cutting checks

| Check | Status | Notes |
|---|---|---|
| Backend `phase` field | 🔧 | **Implemented (reconciliation pass).** All three providers (Cricbuzz/Cricinfo/CricketData) now emit additive `phase` via `cricket-api/src/lib/match-phase.js`. Existing `status` unchanged. `node --check` 4/4 OK. Not yet device-verified. |
| Status contradiction (LIVE vs Stumps) | 🔧 | Frontend `MatchStatusDisplay` resolver prefers backend `phase`, falls back to `statusText` heuristic, then coarse `status`; badge + label agree on Home hero/list, Matches list, Schedule card, Series match card, Match Details header, and the minimized floating bar |
| Points table order | 🔧 | Sort by points desc → NRR desc → wins desc → name asc — **frontend-only** (`series_detail_stats.dart:136`). Backend `normalizePointsTableResponse` does not sort. (An earlier draft of this checklist wrongly said "frontend + backend".) |
| Series list order | 🔧 | Ongoing → Upcoming → Completed, within-section date ordering |
| Schedule date wording | 🔧 | Today/Tomorrow via shared `formatMatchDateTime` |
| Scorecard single source | 🔧 | Live + Score + minimized bar all use `TeamScoreView` |
| Overs dot vs missing | 🔧 | Distinct visuals + legend |
| Live-tab extras (Wd/Nb/B/Lb) | 🔧 | Recent-over bubbles now match Overs/Commentary tabs (amber Wd/Nb/B/Lb) |
| Live-tab result classification | 🔧 | `_looksLikeResult` no longer matches bare "win"/"won" — a live chase is not classified finished |
| Live-tab freshness label | 🔧 | `_LiveFooter` shows a real ticking "Updated X ago" from `last_updated`, or nothing — never fake "Updated just now" |
| Squad WK group | 🔧 | Dedicated group + partial-data empty state |
| Refresh label accuracy | 🔧 | Ticking timer + stale/offline states |
| Team abbreviations | 🔧 | `teamCodeOf` used in points table; already consistent elsewhere |
| CTA label consistency | 🔧 | "Match Center" everywhere a match opens |
| CRICPRO wordmark | 🔧 | Shared `CricLogo` on Home/Matches/Series list/Series detail |
| Notification bell | 🔧 | Shared `GlowIconButton` (+ unread dot where shown); fake "3" badge removed |
| SafeArea / top clipping | ✅ | Verified already correct on all screens (no change needed) |
| Bottom-nav clipping | ✅ | Verified already correct (`mainScrollBottomInset`) (no change needed) |
| UI colors | ✅ | Unchanged (CLAUDE.md constraint honoured) |
| API response shapes | ✅ | Backend changes additive only — `phase` field added; no existing field removed/renamed; no standings re-order |
| Stray junk assets | 🔧 | 5 `*.png[0-9]+` junk files deleted from `auto_extracted/` |
| "VERIFIED BY 17 PIXELS" watermark | 🔧 | Baked-in stock-design watermark on tournament/league series card backgrounds; generated clean watermark-free replacements and repointed `SeriesNewAssets` at them. Originals kept (non-destructive). |
| Venue truncation ("KSCA Hubli Cricket Gro…") | 🔧 | Matches card `_VenueRow` now `maxLines:2` so a long stadium name wraps |
| Match Details header LIVE vs Stumps | 🔧 | `MatchHeroScoreCard` uses `MatchStatusDisplay` (badge + note agree); pulsing dot suppressed at stumps/lunch/tea |
| Minimized floating bar LIVE vs Stumps | 🔧 | `_LiveBadge` + status line use `MatchStatusDisplay`; badge shows STUMPS/LUNCH/TEA and the pulsing dot is suppressed during a stoppage |

---

## Device QA — required before release (NOT yet run)

Run on a real device or emulator against these match states. Mark each ✅ when verified:

- [ ] Live match (actively bowling) — LIVE badge + pulsing dot, ticking "Updated X ago", batters/bowler/recent over
- [ ] Stumps match — STUMPS badge, NO pulsing dot, no "Live data will appear" upcoming view
- [ ] Lunch / Tea / Innings break — correct badge, no pulsing dot, classified as live
- [ ] Finished match — RESULT badge + result text, footer reads "Match completed"
- [ ] Upcoming match — UPCOMING badge + countdown, "Match yet to begin"
- [ ] Wide in recent over — amber "Wd" bubble (not cyan "1")
- [ ] No-ball in recent over — amber "Nb" bubble
- [ ] Live chase "India need X to win" — stays on the live view, NOT classified as finished
- [ ] Schedule card for a stumps match — STUMPS pill, no pulsing LIVE
- [ ] Series match card for a stumps match — STUMPS badge, phase-label note
- [ ] Points table — sorted points desc → NRR desc → wins desc → name asc
- [ ] Small width (360) — no overflow/clipping on any screen
- [ ] High font scale — no truncation on rankings/match cards

---

## Intentionally NOT done this pass (documented for a future "full shared-component" pass)

- Migrate all hand-rolled card shells to shared `PremiumCard`.
- Migrate all hand-rolled tabs/chips to shared `SegmentedTabs`/`PillChip`.
- Unify the two series status-pill implementations.
- Replace per-screen `_SectionHeader` duplicates with the shared `SectionHeader`.
- Backend `meta.lastUpdated` on every route (so "Updated X ago" is accurate everywhere).
- Widen CricketData `#mapStatus` to emit `abandoned`/`no_result` coarse status (currently collapsed to `completed`; `derivePhase` recovers it from text).
- Extract shared `LivePollController` (4 duplicated state machines).
- Cricinfo scorecard/commentary thinness (provider data limitation).

These were skipped to keep the production-app regression risk low per the approved "Targeted" scope.

---

## Verification commands run (this session, from clean)

- `flutter clean` — exit 0
- `flutter pub get` — exit 0
- `flutter analyze lib/` — No issues found, exit 0
- `flutter test` — 192/192 passed, exit 0
- `node --check` on 4 changed backend JS files (`match-phase.js`, cricbuzz/cricinfo/cricketdata normalizers) — 4/4 OK
- `flutter build apk --release` — exit 0, `build/app/outputs/flutter-apk/app-release.apk`, 79.8 MB (83,632,445 bytes)
- Device/emulator QA — **NOT run** (see "Device QA" section above)
