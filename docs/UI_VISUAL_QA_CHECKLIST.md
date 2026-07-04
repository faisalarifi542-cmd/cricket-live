# CricPro — UI Visual QA Checklist

Tracked against the targeted consistency & data-correctness pass. Update the
status column as each screen is verified on a real device/emulator.

**Status legend:** ✅ Fixed + verified · 🔧 Fixed (needs device verify) · ⏳ Remaining · ➖ N/A

**Device sizes to test:** 360 (compact), 390/400 (typical), 430+ (large), plus a high font-scale run.

---

## Bottom-nav screens

| Screen | Status | Issues fixed | Remaining issues | Screenshot needed | Device size tested |
|---|---|---|---|---|---|
| Home | 🔧 | Shared `CricLogo` wordmark; consolidated bell on `GlowIconButton`; phase-aware status badge (STUMPS/LUNCH/TEA vs LIVE); removed contradictory "LIVE NOW" + "Day 1 Stumps"; "Match Center" CTA label | Hero/list card shells still hand-rolled (intentionally out of scope) | yes | 390 |
| Home — Live tab | 🔧 | Phase-aware badge + center pill; pulsing dot suppressed at stumps/lunch/tea | — | yes | 390 |
| Home — Upcoming | 🔧 | "Match Center" CTA | — | yes | 390 |
| Home — Finished | 🔧 | Result badge via shared resolver | — | yes | 390 |
| Matches | 🔧 | Shared `CricLogo`; consolidated bell; phase-aware live badge; "Match Center" CTA | Status tabs still hand-rolled (out of scope) | yes | 390 |
| Matches — Live | 🔧 | Phase-aware badge (STUMPS etc.); pulsing dot only for active live | — | yes | 390 |
| Matches — Upcoming | 🔧 | "Match Center" CTA | — | yes | 390 |
| Matches — Finished | 🔧 | "Match Center" CTA | — | yes | 390 |
| Schedule | 🔧 | Per-card time line via shared `formatMatchDateTime` (Today/Tomorrow); day summary shows Today/Tomorrow | Sorting already correct (verified, no change); date strip hand-rolled (out of scope) | yes | 390 |
| Series — All | 🔧 | Canonical sort (ongoing→upcoming→completed, within-section dates); shared `CricLogo` + bell | Filter chips hand-rolled (out of scope) | yes | 390 |
| Series — Ongoing | 🔧 | Sort: live-match series first, then start-date desc | — | yes | 390 |
| Series — Upcoming | 🔧 | Sort: soonest start date first | — | yes | 390 |
| Series — Completed | 🔧 | Sort: most-recent end date first | — | yes | 390 |
| More | 🔧 | "Floating Score Overlay" label (was truncated "Floating Score over oth…"); shared `AppHeader` + `GlowIconButton` already in use | — | yes | 390 |

## Match Details tabs

| Screen | Status | Issues fixed | Remaining issues | Screenshot needed | Device size tested |
|---|---|---|---|---|---|
| Match Details — Info | 🔧 | Info value `maxLines:2 + ellipsis` (long venue/teams no longer wrap unbounded) | — | yes | 390 |
| Match Details — Live | 🔧 | Scorecard via shared `TeamScoreView` (no more duplicated formatting); event types trust server `type`; extras (Wd/Nb/B/Lb) labelled, not mis-read as runs | — | yes | 390 |
| Match Details — Score | 🔧 | Agrees with Live tab (both use `TeamScoreView`) | — | yes | 390 |
| Match Details — Squad | 🔧 | Dedicated Wicket-keepers group; "Playing XI not announced yet" empty state when only bench exists | — | yes | 390 |
| Match Details — Commentary | 🔧 | Event styling consistent with Live tab (server `type`); extras handled | Commentary ordering already correct (verified) | yes | 390 |
| Match Details — Overs | 🔧 | Dot vs missing ball distinguished (`•` vs `–`); extra-ball types (Wd/Nb/B/Lb) coloured amber; ball-colour legend added | — | yes | 390 |
| Match Details header | 🔧 | "Updated X ago" now ticks every second; "Stale data, retrying" + "Offline cache" states | — | yes | 390 |

## Series detail tabs

| Screen | Status | Issues fixed | Remaining issues | Screenshot needed | Device size tested |
|---|---|---|---|---|---|
| Series Details — Overview | 🔧 | Status uses authoritative `classifySeriesStatus` (agrees with list card); "Match Center" CTA | — | yes | 390 |
| Series Details — Matches | 🔧 | Balanced team columns (match note moved to a centered row under both) | — | yes | 390 |
| Series Details — Squads | ➖ | Not touched this pass (uses shared `PremiumSquad` which got the WK-group fix) | — | yes | 390 |
| Series Details — Stats / Points Table | 🔧 | Canonical sort (points→NRR→wins→name) frontend + backend; team code via `teamCodeOf` ("SL A" not "SRI LANKA A") | — | yes | 390 |
| Series Details hero | 🔧 | Shared `CricLogo`; removed hardcoded "3" notification badge → dot-only | — | yes | 390 |

## Secondary screens

| Screen | Status | Issues fixed | Remaining issues | Screenshot needed | Device size tested |
|---|---|---|---|---|---|
| ICC Men Ranking | 🔧 | Player name `maxLines:2` (no more "Travis …" truncation); tighter rank column + smaller avatar give name more width | — | yes | 390 |
| ICC Women Ranking | 🔧 | Same name-wrap/layout fix | — | yes | 390 |
| Teams | ➖ | Not touched this pass (no confirmed defect) | — | yes | 390 |
| Favorite Countries | ➖ | Not touched this pass | — | yes | 390 |

---

## Cross-cutting checks

| Check | Status | Notes |
|---|---|---|
| Status contradiction (LIVE vs Stumps) | 🔧 | Backend `phase` field + frontend `MatchStatusDisplay` resolver; badge + label now agree on Home hero/list, Matches list, **Match Details header, and the minimized floating bar** (all wired in the screenshot-review pass) |
| Points table order | 🔧 | Sort by points desc → NRR desc → wins desc → name asc (frontend + backend) |
| Series list order | 🔧 | Ongoing → Upcoming → Completed, within-section date ordering |
| Schedule date wording | 🔧 | Today/Tomorrow via shared `formatMatchDateTime` |
| Scorecard single source | 🔧 | Live + Score + minimized bar all use `TeamScoreView` |
| Overs dot vs missing | 🔧 | Distinct visuals + legend |
| Squad WK group | 🔧 | Dedicated group + partial-data empty state |
| Refresh label accuracy | 🔧 | Ticking timer + stale/offline states |
| Team abbreviations | 🔧 | `teamCodeOf` used in points table; already consistent elsewhere |
| CTA label consistency | 🔧 | "Match Center" everywhere a match opens |
| CRICPRO wordmark | 🔧 | Shared `CricLogo` on Home/Matches/Series list/Series detail |
| Notification bell | 🔧 | Shared `GlowIconButton` (+ unread dot where shown); fake "3" badge removed |
| SafeArea / top clipping | ✅ | Verified already correct on all screens (no change needed) |
| Bottom-nav clipping | ✅ | Verified already correct (`mainScrollBottomInset`) (no change needed) |
| UI colors | ✅ | Unchanged (CLAUDE.md constraint honoured) |
| API response shapes | ✅ | Backend changes additive only (`phase` field + standings re-order) |
| Stray junk assets | 🔧 | 5 `*.png[0-9]+` junk files deleted from `auto_extracted/` |
| "VERIFIED BY 17 PIXELS" watermark | 🔧 | **Found in the screenshot review** — a baked-in stock-design watermark on the tournament/league series card backgrounds (`sheet1_tournament_asset_01.png`, `sheet3_league_asset_01.png`), NOT in Dart code (which is why an earlier code-search missed it). Generated clean watermark-free replacements (`*_clean.png`) and repointed `SeriesNewAssets.tournamentBg`/`leagueBg` at them. Originals kept on disk (non-destructive). |
| Venue truncation ("KSCA Hubli Cricket Gro…") | 🔧 | Matches card `_VenueRow` now `maxLines:2` so a long stadium name wraps instead of cutting mid-word (brief #7, named defect) |
| Match Details header LIVE vs Stumps | 🔧 | `MatchHeroScoreCard` now uses `MatchStatusDisplay` (badge + note agree); pulsing dot suppressed at stumps/lunch/tea |
| Minimized floating bar LIVE vs Stumps | 🔧 | `_LiveBadge` + status line now use `MatchStatusDisplay`; badge shows STUMPS/LUNCH/TEA and the pulsing dot is suppressed during a stoppage |

---

## Intentionally NOT done this pass (documented for a future "full shared-component" pass)

- Migrate all hand-rolled card shells (`_HomeCardShell`, `_MatchCardShell`, `_FeaturedMatchMini`, `_FeaturedSeriesCard`, `_ScheduleMatchCard`) to shared `PremiumCard`.
- Migrate all hand-rolled tabs/chips (`_HomeStatusTabs`, Matches `_StatusTabs`, Schedule `_CategoryChip`, `SeriesFilterChipBar`, `SeriesGlassTabBar`, `_SquadToggle`, `MatchDetailsTabBar`) to shared `SegmentedTabs`/`PillChip`.
- Unify the two series status-pill implementations (`SeriesStatusPill` vs `SeriesStatusPillImg`).
- Replace per-screen `_SectionHeader` duplicates with the shared `SectionHeader`.
- Backend response-envelope standardization (#27).
- Cricinfo scorecard/commentary thinness (provider data limitation).

These were skipped to keep the production-app regression risk low per the approved "Targeted" scope.

---

## Verification commands run

- `flutter analyze lib/` — see final report
- `flutter test` — see final report
- `node --check` on changed backend files (cricbuzz/cricinfo/cricketdata normalizers + series.js) — passed
- `flutter build apk --release` — see final report
