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

## Small-device screenshot QA — July 2026 pass

Targeted density/readability/data-presentation pass driven by a fresh set of 360px screenshots (Match Details Info/Live/Squad/Comm/Overs, CricPro Series/Schedule/Matches/Home). No new design language — existing `context.sp()`/`bp`/`isCompact` tokens and shared formatters (`shortVenue`, `shortSeriesTitle`) reused. UI colors unchanged.

**Status legend:** ✅ Fixed + device-verified · 🔧 Fixed (analyze/test/build-verified, NOT device-verified) · ⏳ Remaining · ➖ already-OK (no change needed)

| # | Screenshot issue | Screen | File(s) | Fixed | Verified (analyze/test/build) | Remaining |
|---|---|---|---|---|---|---|
| 1 | Hero cramped at 360: status squeezed between two pills; invisible "balance" pill wasted ~48px; scores hardcoded 26px | Match Details header | `match_details_ui.dart` (`MatchHeroScoreCard`, `MDTeamScoreBlock`) | 🔧 Dropped invisible pill; badge on its own centered row + status note on a dedicated 2-line ellipsized line; scores/code/VS badge now `context.sp()`-scaled + compact VS; inner padding 14→16/18 | analyze clean, 192/192, APK 79.8 MB | device QA |
| 2 | Freshness inconsistency: global row said "Pull to refresh" on Live while other tabs said "Updated just now" (two sources) | Match Details all tabs / Live | `match_details_screen.dart` (`_loadSummary`), `live_match_tab.dart` (`_LiveFooter`) | 🔧 Screen now seeds `_lastUpdatedAt` from `meta.lastUpdated` (never faked) on FIRST load → header row is the single authoritative freshness source on every tab; Live footer demoted to a pure "Live coverage"/"Match completed" status line (removed its duplicate timestamp + dead `_parseLastUpdated`/`dart:async`) | analyze clean, 192/192 | device QA |
| 3 | RRR shows "0" in a Test; Recent Overs prints raw "0 0 0 0 0 0" | Match Details Info | `md_info.dart` (`_InfoPanel`, `_RecentOverPill`) | 🔧 RRR hidden unless value > 0 (real chase); Recent Overs hidden when all-zero, else rendered as per-over pills (wicket-over tinted) | analyze clean, 192/192 | device QA |
| 4 | Overs legend packs densely; a `Wrap` could break a line between a chip and its own label | Match Details Overs | `md_panels.dart` (`_BallLegend`) | 🔧 Each chip+label is now an atomic `Row`; tighter spacing on compact. (Dot vs missing already distinct — unchanged) | analyze clean, 192/192 | device QA |
| 5 | ~94px fixed left gutter before the commentary card cramps long text at 360 | Match Details Commentary | `md_timeline.dart` (`_buildBall`, `_TimelineRail`) | 🔧 Over column 40→32, rail 46→42, gap 8→6, ball chips −4 on compact (~16px reclaimed). Filter bar already horizontally scrollable (usable) | analyze clean, 192/192 | device QA |
| 6 | Series hero title "SWITZERLAND WOMEN TO… GERMANY," — dangling comma, mid-word truncation | Series Detail hero | `series_detail_hero.dart` (`_splitTitle`) | 🔧 Split now handles "to"/"vs" connectors (not just "tour of"); strips edge punctuation + collapses ", 2026"; routes through `shortSeriesTitle`; small line 2 lines; fonts `sp()`-scaled | analyze clean, 192/192 | device QA |
| 7 | Venue "Galle International St…" truncates aggressively (multi-comma name) | Schedule | `schedule_cards.dart` (`_TimeVenuePanel`) | 🔧 Routed through shared `shortVenue()` (consistent with Matches card); duplicate city subtitle dropped | analyze clean, 192/192 | device QA |
| 8 | Series squad grid 3-up at 360 crushes names; ragged card heights (optional role tag) | Series Detail Squads | `series_detail_squads.dart` (`_PlayerGrid`, `_SquadPlayerCard`) | 🔧 2 columns ≤360 (3 at ≥360 inner, 4 at ≥460); fixed-height role-tag slot equalizes card heights | analyze clean, 192/192 | device QA |
| 9 | Home carousel center card reads edge-to-edge/cropped on small phones | Home | `home_hero.dart` (`_HeroMetrics.of`) | 🔧 Small-phone `viewportFraction` 0.965→0.92 for a clean gutter + subtle non-distracting peek | analyze clean, 192/192 | device QA |
| 10 | Series-detail back button had a bare 26px tap target (< 44px) | Series Detail header | `series_detail_hero.dart` (`_DetailAppBar`) | 🔧 44×44 hit area, icon left-aligned to the edge | analyze clean, 192/192 | device QA |
| 11 | Matches-card date `Text` lacked ellipsis guard | Matches | `matches_cards.dart` (`_CardTopRow`) | 🔧 Added `overflow: ellipsis` + `softWrap:false` (defensive) | analyze clean, 192/192 | device QA |

### Corrected instructions (reported issues that were already handled — no rebuild)
- ➖ **Series list filter clipping / selected-chip-off-screen** — already mitigated by `_ensureVisible(alignment:0.0)` on init + selection (`series_poster_cards.dart:1282`); list bottom inset already uses `mainScrollBottomInset`. No change.
- ➖ **Matches card layout** (status top-left / title 2 lines / date top-right / venue `shortVenue`+2 lines / "Match Center" CTA) — already implemented. Only the defensive date-ellipsis micro-fix (#11) applied.
- ➖ **Overs dot-vs-missing** — already distinct (`•` filled vs `–` dashed) from the prior pass; only legend density (#4) addressed.
- ➖ **Points table** — center-aligned values already align column-to-column with the header and don't overflow (fixed-width cols + ellipsized team `Expanded`); sort preserved. Left as-is (changing alignment would risk header mismatch, low benefit).
- ➖ **Squad team selectors** — render short codes ("WI"/"SL") with `Flexible`+ellipsis; readable in screenshots. No change.
- ➖ **Team logos** — single reusable `TeamLogoWidget` with centralized premium initials fallback already in use everywhere; sizes are contextually correct. Named size tokens deferred (no behavior gap); hero accent-ring is intentional premium styling (preserved).

### Backend
- No backend changes were required this pass. Required-RR and Recent-Overs are normalized on the client (display-only); no API response shape changed.

---

## Verification commands run (this session, from clean)

- `flutter clean` — exit 0
- `flutter pub get` — exit 0
- `flutter analyze lib/` — No issues found, exit 0
- `flutter test` — 192/192 passed, exit 0
- `node --check` on 4 changed backend JS files (`match-phase.js`, cricbuzz/cricinfo/cricketdata normalizers) — 4/4 OK
- `flutter build apk --release` — exit 0, `build/app/outputs/flutter-apk/app-release.apk`, 79.8 MB (83,632,445 bytes)
- Device/emulator QA — **NOT run** (see "Device QA" section above)

### Small-device screenshot pass (July 2026) — re-verified
- `flutter analyze lib/` — **No issues found**, exit 0
- `flutter test` — **192/192 passed**, exit 0
- `flutter build apk --release` — exit 0, `build/app/outputs/flutter-apk/app-release.apk`, **79.8 MB (83,632,445 bytes)** (unchanged — UI-only edits)
- Backend — no changes this pass (`node --check` N/A)
- Device/emulator QA at 360px + high text-scale — **still required before release**

---

## Series target design pass — July 2026

Targeted polish of the **existing** premium Series screen to close the last visual gaps versus the attached target design. No rebuild, no new V2 components, no backend/API/sort/filter/navigation changes, no core-color changes — the CricPro dark/cyan design language and all existing reusable widgets (`SeriesLogoRing`, `SeriesLogoRingPair`, `SeriesStatusPillImg`, `SeriesCtaButton`, `SeriesMetaRow`, `SeriesBorderFrame`) are preserved and reused.

**Status legend:** ✅ Fixed + device-verified · 🔧 Fixed (analyze/test/build-verified, NOT device-verified) · ➖ already-OK (no change needed)

| # | Target gap | File(s) | Fixed | Verified |
|---|---|---|---|---|
| 1 | Featured hero had no team-name captions; target shows `AUSTRALIA` / `BANGLADESH` under the two large flags | `series_poster_cards.dart` (`_HeroTeamBadge`, `_heroTeamLabel`, hero `Row`) | 🔧 Each hero ring now stacks a centered uppercase team-name caption beneath it (two-team heroes only); width-capped to the ring so long names ellipsize cleanly instead of widening the hero; renders bare ring when only placeholder text exists | analyze/test/build |
| 2 | Card titles over-truncated ("Switzerland Women tour of G…") + kept redundant trailing ", 2026"/dangling commas | `team_format.dart` (`compactSeriesTitle`), `series_components.dart` (`SeriesView.compactName`), `series_poster_cards.dart` (both card titles) | 🔧 New pure `compactSeriesTitle()` strips a redundant trailing ", YYYY" (incl. season suffixes `-27`/`/27`) and dangling commas, preserves "tour of", and leaves comma-less tournament years (e.g. "… World Cup 2026") intact; poster cards render `series.compactName` | analyze/test/build + `series_title_compact_test.dart` |
| 3 | Hero felt small/compressed vs target | `series_poster_cards.dart` (`_metricsFor`) | 🔧 Safe hero/heroRing bump per breakpoint — 176→190 / 188→204 / 200→216 (height) and 80→86 / 90→96 / 100→106 (ring); still clip-free at 360px | analyze/test/build |
| 4 | Filter chip could sit flush-left with a jarring half-clipped neighbour after selecting Upcoming/Completed | `series_poster_cards.dart` (`SeriesFilterChipBar._ensureVisible`) | 🔧 Selected chip now CENTERS (`alignment:0.5`); framework clamps at row ends so All stays flush-left/fully visible on initial load and the selected chip is always fully visible with balanced neighbour peeks | analyze/test/build |

### Already-OK (verified, no change needed — from the prior redesign)
- ➖ **Watermark on tournament/league card art** — already resolved: `tournamentBg`/`leagueBg` point at the watermark-free `*_asset_01_clean.png` files (the older "REVIEWED/VERIFIED BY … PIXELS" stock watermark is gone).
- ➖ **CTA size** — `SeriesCtaButton` already renders at tap-sized 40–44px height (prior FittedBox-shrink removed); readable "Explore Series"/"View Series".
- ➖ **Bottom padding** — Series list already uses `context.mainScrollBottomInset` (nav ~64 + banner ~64 + safe area + 24 comfort); last card clears the bottom bar.
- ➖ **Status pill / favorite star / team badges / meta row** — already present and premium; favorite-star tap toggle preserved.
- ➖ **Sort/filter/navigation** — `sortSeriesByStatus` (ongoing→upcoming→completed), `filterSeries`, and `_open`/`_openHero` routing untouched.

> Note: this pass changes the filter-chip scroll from `alignment:0.0` to centered `0.5`; the earlier checklist note referencing `alignment:0.0` is superseded here.

### Backend
- No backend changes. API response shapes and admin data source unchanged.

---

## Series target fidelity pass — July 2026 (focused visual pass)

Second, tighter Series-only pass driven by fresh 360px screenshots vs the attached target. Existing premium components are **tuned more aggressively** toward the target (no new V2 system, no backend/sort/filter/nav/color changes). Only `series_list_screen.dart`, `series_poster_cards.dart` and `team_format.dart` touched (+ the QA checklist and a unit test).

**Status legend:** ✅ Fixed + device-verified · 🔧 Fixed (analyze/test/build-verified, NOT device-verified) · ➖ already-OK

| # | Target gap | File(s) | Fixed | Verified |
|---|---|---|---|---|
| 1 | Header logo/title too small + compressed on 360 | `series_list_screen.dart` (`_SeriesHeader`, list top pad) | 🔧 CRICPRO wordmark bumped (30/33 → 34/37/40 responsive); "Series" title `sp(26)` → `sp(32)`, tighter `-.5` tracking; more breathing room (list top pad 8→12, logo→title gap 14→18, header→hero gap 14→20). SafeArea preserved | analyze/test/build |
| 2 | Hero shorter/compressed; small team labels; format chip truncated "3 T20s , 3 …" | `series_poster_cards.dart` (`_metricsFor`, `_HeroPill`, `_HeroTeamBadge`), `team_format.dart` (`normalizeSeriesFormat`) | 🔧 Hero height 190/204/216 → 214/228/242; hero ring 86/96/106 → 96/106/116; team captions `meta*.95` → `meta*1.05`; **new `normalizeSeriesFormat()` renders bullet-separated "3 T20Is • 3 ODIs"** (comma/slash → " • "); `_HeroPill` now `FittedBox(scaleDown)` so the full format text NEVER ellipsizes | analyze/test/build + `series_title_compact_test.dart` |
| 3 | Series cards too compact; small metadata/CTA | `series_poster_cards.dart` (`_metricsFor`, `SeriesCtaButton`) | 🔧 Card heights bumped per breakpoint (tournament 222→238/250/262, league 206→222/232/242, bilateral 190→204/214/224, completed 182→190/200/210); pad, meta (12.5→13/13.5/14), CTA height (40→44/46/48), status pill, rings all up; CTA text ratio `.38`→`.35` keeps label readable without dominating the row | analyze/test/build |
| 4 | Filter row half-clipped a chip on the left after selecting Upcoming/Completed; chips small | `series_poster_cards.dart` (`SeriesFilterChipBar`, `_FilterChip`) | 🔧 Scroll changed from **centered `0.5`** to **left-bias `0.06` (explicit policy)** — earlier chips scroll cleanly OFF the left instead of peeking as a sliced half; selected chip stays fully visible with a small left inset + clean right peek. Chips bigger (h44→48, pad18→20, icon16→17, text14→14.5, radius22→24), stronger selected cyan glow; row h52→58 with leading inset | analyze/test/build |
| 5 | "League" tag clipped to "L…" on the ongoing tournament/league card | `series_poster_cards.dart` (`_CompetitionPosterCard` bottom row) | 🔧 Bottom-left tag changed from `Expanded` (which forced an early ellipsis) to `Flexible` + `Spacer`, so "League"/"Tournament" takes its natural width and the CTA is pushed to the right edge — no more "L…" | analyze/test/build |

### Watermark / artifact confirmation (item 5 of the brief)
- ➖ **"VERIFIED/REVIEWED BY … PIXELS" watermark** — verified NOT present in the current code path. Every rendered Series card background was inspected directly: `tournamentBg` (`sheet1_tournament_asset_01_clean.png`), `leagueBg` (`sheet3_league_asset_01_clean.png`), `leagueBatsman` (`sheet3_league_asset_05.png`), `bilateralBg` (`sheet2_bilateral_asset_01.png`) and `trophyGold` (core) are all clean, and all are bundled via `pubspec.yaml` asset dirs. The dead references (`tournamentTrophy`/`tournamentBurst`/`leagueBgAlt`) are not rendered. The watermark visible in the supplied screenshots is from a **stale build** — a clean `flutter build apk --release` (below) renders watermark-free. Originals kept (non-destructive).

### Superseded note
- Item #4 of the previous "Series target design pass" changed the chip scroll to centered `0.5`; **this pass supersedes it** with the left-bias `0.06` policy (centring was the cause of the reported left half-clip).

### Backend
- No backend changes. API response shapes, admin hero data, sort/filter/navigation, and core colors all unchanged.
