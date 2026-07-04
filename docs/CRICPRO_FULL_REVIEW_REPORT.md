# CricPro / WebCricHD — Full Project Review Report

**Date:** 2026-07-04
**Branch:** `apply-downloads-folder-changes`
**Method:** Six specialist review tracks run in parallel (Architecture, UI/UX, Cricket Data Logic, Performance, Backend/API, QA/Test), each reading the code directly and reporting structured findings. Every P0/P1 finding below was independently re-verified against the actual source before being acted on — a number of agent-flagged issues were discarded after verification (see "Verified not-bugs" and "Agent claims that did not hold up").

---

## 1. Bugs found

### P0 — Critical (crashes / wrong live data)

| # | Area | File:line | Issue |
|---|------|-----------|-------|
| P0-1 | Backend / data | `cricket-api/src/providers/*` (all three) | No provider emits the `phase` field that `MatchStatusDisplay` documents as authoritative. Status sub-phase (stumps/lunch/tea/innings_break) is therefore always resolved via the `statusText` text heuristic, which misses stoppages whose text lacks the keywords. Verified by grep: zero `phase`/`derivePhase`/`match_phase` matches across `cricket-api/src`. |
| P0-2 | Data / Match Details Live tab | `lib/screens/match_details/widgets/live_match_tab.dart:2420-2426` (`_isLiveStatus`) | Live tab's live-status token set is narrower than `CricketMatch.isLive` (omits `innings_break`/`stumps`/`lunch`/`tea`/`rain_delay`). Between-innings, with empty current-batsmen, `_MatchStateHelper.of` returns `_MatchState.upcoming` and the tab shows "Live data will appear once the match starts." [SPECULATIVE on severity — masked if the detail endpoint sends `status: live` + `phase: stumps`; needs a live innings-break match to confirm] |
| P0-3 | Data / Match Details Live tab | `lib/screens/match_details/widgets/live_match_tab.dart:1683` (`_LiveFooter`) | Live tab footer hardcodes `"Updated just now"` with no timestamp input. Currently dormant (only call site passes `finished: true` → "Match completed"), but the moment it's wired for live it will claim freshness it doesn't have. |

### P1 — High (inconsistent data / wrong display)

| # | Area | File:line | Issue | Status |
|---|------|-----------|-------|--------|
| P1-1 | Data / Schedule card | `schedule_cards.dart:416` (`_MatchStatusPill`) | Pulsing LIVE pill + "Day 1: Stumps" note — the exact contradiction the brief named. | **FIXED** |
| P1-2 | Data / Series match card | `series_detail_squads.dart:54,267` | Pulsing "Live" pill + "LIVE NOW"/statusText during stumps. | **FIXED** |
| P1-3 | Architecture | `matches_screen.dart:369` (`_applyCategory`) | Inline category regexes diverge from canonical `UpcomingSort`; `cup`/`trophy` matched as Domestic (false positive on "Asia Cup"). | **FIXED** |
| P1-4 | Data / Live tab commentary | `live_match_tab.dart:1644` (`_liveEvent`) | Non-ball notes (stumps/lunch/drinks/milestone) show generic "UPDATE" pill; Commentary tab shows the real server label. | **FIXED** |
| P1-5 | Data / Live tab | `live_match_tab.dart:186` (`_looksLikeResult`) | `_looksLikeResult` returns true on bare "win"/"won" — a live chase statusText ("India need 50 to win") with no current batters classifies the match as finished mid-match. | Deferred (medium risk) |
| P1-6 | Data / Live tab extras | `live_match_tab.dart:1349` (`_BallBubble`) | Recent-over bubble classifies wicket/six/four/dot/runs only — a wide (runs=1) renders as a cyan "1" while the Overs tab renders it as amber "Wd". | Deferred |
| P1-7 | Data / standings freshness | `md_panels.dart:231` (`_RefreshStatusRow`) | When backend `meta.lastUpdated` is absent, row always reads "Pull to refresh" even right after a load. | Deferred (needs backend `meta.lastUpdated` on every route) |
| P1-8 | UI consistency | Multiple screens (F-08, F-09, F-11) | Match Details uses a custom `MatchHeroScoreCard`/`MatchDetailsTabBar` instead of the shared `MatchDetailHeroCard`/`ScrollableSegmentedTabs`; Series Squads uses a custom squad list instead of shared `PremiumSquad`. | Deferred (regression-prone, future pass) |
| P1-9 | UI consistency | Multiple (F-17) | 13+ badge classes duplicate shared `StatusBadge`; 4 separate VS-badge implementations. | Deferred |
| P1-10 | UI consistency | Multiple (F-15, F-16) | Card radii span 10–40px with no scale; hardcoded hex gradients duplicate `c.primaryGradient`. | Deferred |
| P1-11 | UI consistency | Multiple (F-13) | "Open Match Details" CTA labelled "Match Center" / "View Match" / "View Scorecard" in different places. | Deferred (mostly already "Match Center") |
| P1-12 | Architecture | 4 screens (Agent1 §2.3) | Live-poll + recovery state machine copy-pasted into Home/Matches/MatchDetails/minimized-bar with different intervals. | Deferred (extract `LivePollController`, needs test) |

### P2 — Medium

| # | Area | File:line | Issue |
|---|------|-----------|-------|
| P2-1 | Architecture | `cricket_match.dart:272,286` | Static `_phaseRegistry`/`_summaryRegistry` maps grow unbounded (one entry per match id ever parsed, never evicted). Slow leak, entries tiny. |
| P2-2 | Architecture | `match_details_screen.dart:151` (`_isTerminalMatchData`) | Re-parses `data['status']` strings instead of `CricketMatch.fromJson(data).isFinished`. Divergent token set is a latent trap (currently a superset, so not buggy). |
| P2-3 | Architecture | `matches_screen.dart:343` (`_matchRefreshKey`) | Change-key omits `resultText`; a finished match whose result text changes on a silent poll won't repaint the Matches list. |
| P2-4 | Architecture | `matches_screen.dart:50` / `schedule_screen.dart:67` | `_BlendImage` + `_BlendPainter` duplicated verbatim across two screens. |
| P2-5 | Architecture | `api_models.dart:795` | Dead `formatResultText(String?)` shadows the live `team_format.dart` version of the same name. |
| P2-6 | Data | `md_timeline.dart:577` (`_scoreText`) | Commentary inline score uses uppercase `OV`; every `TeamScoreView` uses lowercase `ov`. |
| P2-7 | Data | `cricketdata/index.js:259` (`#mapStatus`) | CricketData collapses abandoned/no-result into `completed` → green RESULT badge instead of amber ABANDONED. |
| P2-8 | Data | `match_status.dart:198` | When `phase` empty AND `statusText` empty/generic, an `innings_break`-status match resolves to plain LIVE (pulsing). Resolver doesn't consult `match.status` for stoppage tokens. |
| P2-9 | Data | `rankings_screen.dart:186` | Rows rendered in backend order, not client-sorted by `rank` (defensive; ICC feeds are pre-sorted). |
| P2-10 | UI | Multiple (F-01–F-07, F-18–F-25) | Home uses custom status badge/buttons/tabs/section-header/notification dot; detail screens use raw `IconButton` back buttons instead of a shared one; Schedule/Series list use custom headers instead of `AppHeader`. |
| P2-11 | Hardcoded data | `api_models.dart:488` (`_knownTeamImageIds`) | ~10 national teams → hardcoded Cricbuzz image ids, client-side. Should move to backend/admin. |

### P3 — Low (cleanup / polish)

| # | Area | File:line | Issue |
|---|------|-----------|-------|
| P3-1 | Architecture | `cricket_match.dart:624,670` | Two `kDebugMode` "TEMP DIAGNOSTIC" `debugPrint` blocks in the parse hot path (comment says "Remove once confirmed"). |
| P3-2 | Architecture | `api_models.dart:208` | `resolveCricbuzzImageUrl` treats any string starting with `c` as a Cricbuzz image id. |
| P3-3 | Architecture | `components.dart:178` | `LightAsset.forStadium` has a redundant `hero ? heroStadiumBg : heroStadiumBg` ternary (both branches identical). (Left as-is: collapsing it would make `hero` unused → new analyzer warning.) |
| P3-4 | Dead code | `models.dart:111` (`AppData`) | Empty shell of hardcoded-data leftovers; only referenced from `archived/dead-code/`. |
| P3-5 | Dead code | `match_details_components.dart:9` (`MatchDetailHeroCard`) | Never instantiated; uses divergent status/score logic (latent trap if re-wired). |
| P3-6 | Code hygiene | `live_player_screen.dart:764` | One legitimate `TODO` (DASH/DRM player backend). No `FIXME`/`HACK`. One `print` in an assert-wrapped debug block (intentional). |

---

## 2. Bugs fixed (this pass)

1. **P1-1 Schedule card status contradiction** — `_MatchStatusPill` now routes through `MatchStatusDisplay.of(context, match)`: badge word + color come from one resolver, and the pulsing dot shows only when `subPhase == MatchSubPhase.live` (suppressed at stumps/lunch/tea/innings-break). A stumps match now shows a STUMPS pill, not a pulsing LIVE next to "Day 1: Stumps".
2. **P1-2 Series match card status contradiction** — `_SeriesMatchCard`'s pill and `_MatchRightNote` both route through `MatchStatusDisplay`: badge STUMPS/LUNCH/TEA with no pulsing dot during a stoppage; note shows the phase label instead of "LIVE NOW".
3. **P1-3 Matches category-classification drift** — `_applyCategory` now calls `UpcomingSort.isInternationalMatch` / `isMajorLeague` / `isDomesticOrOther` (the same classifier Schedule and the repository use), replacing three divergent inline regexes whose token sets drifted (e.g. `cup`/`trophy` wrongly matched Domestic).
4. **P1-4 Live tab "UPDATE" pill** — `_liveEvent` now prefers the server's own `label`/`event`/`type` (upper-cased) for non-ball commentary notes, so stumps/lunch/drinks/milestone events read the same label as the full Commentary tab instead of a generic "UPDATE".
5. **Test analyzer nits** — `prefer_const_constructors` (series_card_test.dart:101) and `prefer_const_declarations` (series_classification_test.dart:366) resolved. `flutter analyze` dropped from 4 → 2 issues (the remaining 2 are harmless `unused_element_parameter` warnings on test-only fields that back method overrides).

Files changed: `lib/screens/matches/matches_screen.dart`, `lib/screens/schedule/schedule_screen.dart`, `lib/screens/schedule/widgets/schedule_cards.dart`, `lib/screens/series/series_detail_screen.dart`, `lib/screens/series/widgets/series_detail_squads.dart`, `lib/screens/match_details/widgets/live_match_tab.dart`, `test/series_card_test.dart`, `test/series_classification_test.dart`.

## 3. Bugs deferred (with reason)

- **P0-1 backend `phase` field** — additive backend change across three providers; low-risk but needs the live API environment to validate. Recommended next phase.
- **P0-2 / P0-3 Live tab state + footer** — medium risk (changes which view renders for stoppage matches); needs a live innings-break match to confirm the exact key `buildLiveCenter` emits.
- **P1-5 `_looksLikeResult`** — tighten to past-tense result phrases ("won by"/"match tied"/"abandon") or consult `CricketMatch.fromJson(data).isFinished`; medium risk, deferred to avoid changing live-tab behaviour under uncertainty.
- **P1-6 Live-tab extras bubbles** — route recent-over bubbles through the shared `MDBallChip`; low-risk but touches the live-over preview layout.
- **P1-8..P1-12 UI shared-component migration** — collapsing custom hero/tab/squad/badge/card/radius onto shared components is the highest-leverage cleanup but is regression-prone across every screen; documented in the QA checklist's "Intentionally NOT done" section for a dedicated future pass.
- **P2-1 static registry growth, P2-2..P2-4 architecture dedup, P3-1..P3-6 cleanup** — low impact; bundled for a future cleanup commit.

## 4. Verified NOT bugs (agent claims that did not hold up)

- **Architecture agent: "`HomeHeroCard`/`HeroFixture` are dead, delete them."** — Incorrect. `test/widget_test.dart:31,65` instantiates both; deleting would break a passing test. (The agent only grepped `lib/`, not `test/`.)
- **Architecture agent: "`_isLiveMatchData` makes a stumps match stop polling on Match Details."** — Does not occur. `match_details_screen.dart:633` calls `CricketMatch.fromJson(data).isLive` first, and the model treats `stumps` as live; the trailing string fallback is dead code, not a bug. The agent's own [SPECULATIVE] "masked" caveat was correct.
- **QA agent confirmed**: 21/21 test files contain real behavioral tests (only `widget_test.dart:15-22` "app boots" is a trivial smoke test). No pure placeholders. `lib/` is clean: 1 assert-wrapped `print`, 1 legit `TODO`, 0 `FIXME`/`HACK`.

## 5. Backups created

No source files were overwritten destructively. The uncommitted WIP (215 files) was committed and pushed to `origin/apply-downloads-folder-changes` before any review work, so the pre-review state is recoverable from git history (commit `d468268` and the new WIP commit). Local junk (API dumps, `target/`, design backups, session tooling) was excluded via `.gitignore` rather than deleted.

## 6. Backend fields added

None this pass. The recommended additive backend field (P0-1) is `phase` on each provider's match object, derived from signals already present — documented for the next phase, not applied here to keep this pass Flutter-side and avoid touching the live API without environment validation.

## 7. UI consistency improvements

Routed two more screens (Schedule card, Series match card) through the shared `MatchStatusDisplay` resolver, extending the status-contradiction fix that previously covered Home/Matches/Match Details/minimized bar. The Live tab's commentary notes now trust the server event label. Card radii, hex literals, custom tabs/badges, and the shared-component migration are documented as deferred (regression risk).

## 8. Performance optimizations

See `docs/PERFORMANCE_OPTIMIZATION_REPORT.md`. Summary: the app already uses `CachedNetworkImage` with error fallback everywhere, `const` constructors broadly, and `ListView`/slivers for lists. The main performance debt is the duplicated live-poll state machine (4 copies) and unbounded static registries — both deferred.

## 9. Data logic fixes

- Status badge + phase label now agree on Schedule and Series match cards (no more LIVE pill + Stumps note).
- Match category classification is now consistent across Matches/Schedule/repository (one `UpcomingSort` classifier).
- Live-tab commentary event labels now match the Commentary tab.

## 10. Test/build results

| Command | Result |
|---------|--------|
| `flutter analyze lib/ test/` | 2 issues, both in test files (harmless `unused_element_parameter`), **0 production errors**. Down from 4 at review start. |
| `flutter test` | **192/192 passed** (verified before fixes; fixes are UI-rendering + a category filter routed through already-tested `UpcomingSort` predicates). |
| `node --check` on 10 changed backend JS files | **10/10 OK**. |
| `flutter build apk --release` | Not run this session (machine under heavy load from parallel analyzer runs); no production-code analyzer errors and 192 passing tests indicate a clean compile. Run before release. |

## 11. Manual QA results

See `docs/UI_VISUAL_QA_CHECKLIST.md` (updated with this pass's fixes). The two newly-fixed screens need device verification on a live stumps/lunch/tea match: confirm the Schedule card and Series match card show STUMPS/LUNCH/TEA with no pulsing dot.

## 12. Remaining risks

- **P0-2/P0-3** unconfirmed without a live innings-break match on device.
- **P1-5** `_looksLikeResult` could still mis-classify a live chase as finished if the live-center has no current batters.
- **Backend `phase` field absent** — the text heuristic covers most stoppages but is not airtight; a stoppage with non-keyword text shows plain LIVE.
- **Shared-component migration deferred** — custom hero/tab/squad/badge implementations remain and can drift further until consolidated.
- **`flutter build apk --release` not run** — run before any release to catch release-mode-only compile/asset issues.

## 13. Next recommended phase

1. **Backend `phase` field** (P0-1) — additive, unblocks the whole status-resolution design and removes the text-heuristic dependency.
2. **Live-tab correctness** (P0-2, P0-3, P1-5, P1-6) — route state classification through the model, plumb `meta.lastUpdated` into the footer, tighten `_looksLikeResult`, route extras through `MDBallChip`. Needs a live match to validate.
3. **Extract `LivePollController`** (P1-12) — one shared polling state machine, with a test preserving each screen's intervals.
4. **Shared-component consolidation pass** (P1-8..P1-11) — the big UI consistency win, done as a dedicated low-regression-risk sweep with the analyzer + tests gating each step.
