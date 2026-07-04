# CricPro / WebCricHD — Full Project Review Report

**Date:** 2026-07-04 (reconciled)
**Branch:** `apply-downloads-folder-changes`
**Method:** Six specialist review tracks run in parallel (Architecture, UI/UX, Cricket Data Logic, Performance, Backend/API, QA/Test). Every P0/P1 finding was independently re-verified against the actual source before being acted on. A reconciliation pass then corrected doc-vs-code contradictions by grep-verifying ground truth first (backend `phase`, standings sort, Flutter phase reading) and fixing the real issues.

---

## 0. Ground truth (verified by grep, not assertion)

- **Backend `phase` — NOW IMPLEMENTED.** A reconciliation grep found zero `phase`/`derivePhase`/`normalizePhase` matches in `cricket-api/src` before this pass. It is now emitted by all three providers via a new shared helper `cricket-api/src/lib/match-phase.js` (`derivePhase(status, statusText)`). Existing `status` fields are unchanged; `phase` is additive.
- **`/series` standings sort — FRONTEND-ONLY.** Backend `normalizePointsTableResponse` (`series.js:69`) passes rows through in provider order; the canonical points→NRR→wins→name sort lives in `lib/screens/series/widgets/series_detail_stats.dart:136`. (An earlier draft of this doc wrongly claimed "frontend + backend".)
- **Flutter reads `phase` — YES.** `lib/models/cricket_match.dart` reads `phase`/`matchPhase`/`match_phase` from backend JSON; `MatchStatusDisplay` (`lib/utils/match_status.dart`) prefers it, then falls back to a `statusText` heuristic, then coarse `status`.

---

## 1. Bugs found

### P0 — Critical (crashes / wrong live data)

| # | Area | Issue | Status |
|---|------|-------|--------|
| P0-1 | Backend / data | No provider emitted the `phase` field that `MatchStatusDisplay` documents as authoritative; stoppages relied on a `statusText` text heuristic that misses non-keyword text. | **FIXED (reconciliation)** |
| P0-2 | Live tab state | `_isLiveStatus` token set was narrower than `CricketMatch.isLive` (omitted stumps/lunch/tea/drinks/rain/innings_break); a stoppage with empty current-batsmen classified as upcoming → "Live data will appear once the match starts." | **FIXED (reconciliation)** |
| P0-3 | Live tab footer | `_LiveFooter` hardcoded `"Updated just now"` with no timestamp input — a fake freshness claim. | **FIXED (reconciliation)** |

### P1 — High (inconsistent data / wrong display)

| # | Area | Issue | Status |
|---|------|-------|--------|
| P1-1 | Schedule card | Pulsing LIVE pill + "Day 1: Stumps" note. | **FIXED (review pass 1)** |
| P1-2 | Series match card | Pulsing "Live" pill + "LIVE NOW" during stumps. | **FIXED (review pass 1)** |
| P1-3 | Matches category | Inline category regexes diverged from canonical `UpcomingSort`; `cup`/`trophy` matched Domestic. | **FIXED (review pass 1)** |
| P1-4 | Live tab commentary | Non-ball notes showed generic "UPDATE" instead of the server label. | **FIXED (review pass 1)** |
| P1-5 | Live tab result | `_looksLikeResult` matched bare "win"/"won" → a live chase ("India need 50 to win") could be classified finished. | **FIXED (reconciliation)** |
| P1-6 | Live tab extras | Recent-over bubble classified wicket/six/four/dot/runs only — a wide (runs=1) rendered as cyan "1" while the Overs tab rendered amber "Wd". | **FIXED (reconciliation)** |
| P1-7 | Standings freshness | `_RefreshStatusRow` reads "Pull to refresh" when backend `meta.lastUpdated` is absent. | Deferred (needs backend `meta.lastUpdated` on every route) |
| P1-8 | UI consistency | Match Details uses custom hero/tab; Series Squads uses a custom squad list instead of shared `PremiumSquad`. | Deferred (regression-prone) |
| P1-9 | UI consistency | 13+ badge classes duplicate shared `StatusBadge`; 4 VS-badge implementations. | Deferred |
| P1-10 | UI consistency | Card radii span 10–40px with no scale; hardcoded hex gradients duplicate `c.primaryGradient`. | Deferred |
| P1-11 | UI consistency | CTA labelled "Match Center" / "View Match" / "View Scorecard" in different places. | Deferred (mostly already "Match Center") |
| P1-12 | Architecture | Live-poll + recovery state machine copy-pasted into 4 screens with different intervals. | Deferred (extract `LivePollController`, needs test) |

### P2 — Medium

| # | Area | Issue | Status |
|---|------|-------|--------|
| P2-1 | Architecture | Static `_phaseRegistry`/`_summaryRegistry` grew unbounded. | **FIXED (reconciliation)** — bounded to 200 entries |
| P2-2 | Architecture | `match_details_screen.dart:151` re-parses `data['status']` instead of `CricketMatch.fromJson(data).isFinished`. | Deferred (latent trap, currently a superset) |
| P2-3 | Architecture | Matches `_matchRefreshKey` omitted `resultText` (and `phase`). | **FIXED (reconciliation)** — both added |
| P2-4 | Architecture | `_BlendImage` + `_BlendPainter` duplicated across Matches + Schedule. | Deferred |
| P2-5 | Architecture | Dead `formatResultText(String?)` in `api_models.dart` shadows the live `team_format.dart` version. | Deferred |
| P2-6 | Data | `md_timeline.dart:577` commentary inline score uses uppercase `OV`; `TeamScoreView` uses lowercase `ov`. | Deferred |
| P2-7 | Data | CricketData `#mapStatus` collapses abandoned/no-result into `completed` → green RESULT badge instead of amber ABANDONED. | **PARTIALLY FIXED** — `derivePhase` now recovers abandoned/no_result from the status text even when `#mapStatus` collapses the coarse status; a full fix would widen `#mapStatus` itself. |
| P2-8 | Data | `match_status.dart` resolver didn't consult `match.status` for stoppage tokens when `phase` + `statusText` were both empty. | **MITIGATED** — backend now emits `phase`, so the empty-phase case is rare; resolver still falls back to coarse `isLive`/`isFinished`. |
| P2-9 | Data | `rankings_screen.dart` rows rendered in backend order, not client-sorted by `rank`. | Deferred (ICC feeds pre-sorted) |
| P2-10 | UI | Home/detail screens use custom headers/buttons instead of shared `AppHeader`/shared back button. | Deferred |
| P2-11 | Hardcoded data | `api_models.dart:488` ~10 national teams → hardcoded Cricbuzz image ids. | Deferred (move to backend/admin) |

### P3 — Low (cleanup / polish)

| # | Area | Issue | Status |
|---|------|-------|--------|
| P3-1 | Architecture | Two `kDebugMode` "TEMP DIAGNOSTIC" `debugPrint` blocks in the parse hot path. | **FIXED (reconciliation)** — deleted + unused `foundation` import removed |
| P3-2 | Architecture | `resolveCricbuzzImageUrl` treats any string starting with `c` as a Cricbuzz image id. | Deferred |
| P3-3 | Architecture | `LightAsset.forStadium` redundant identical ternary. | Left as-is (collapsing makes `hero` unused → new warning) |
| P3-4 | Dead code | `models.dart:111` (`AppData`) empty shell. | Deferred |
| P3-5 | Dead code | `match_details_components.dart:9` (`MatchDetailHeroCard`) never instantiated. | Deferred |
| P3-6 | Code hygiene | One legit `TODO` (DASH/DRM player). No `FIXME`/`HACK`. | No action |

---

## 2. Bugs fixed

### Review pass 1 (commit `04c3149`)
1. **P1-1** Schedule card status pill routed through `MatchStatusDisplay`; STUMPS/LUNCH/TEA with no pulsing dot.
2. **P1-2** Series match card pill + note routed through `MatchStatusDisplay`.
3. **P1-3** Matches `_applyCategory` now calls canonical `UpcomingSort` predicates.
4. **P1-4** Live-tab commentary notes prefer the server event label.

### Performance pass (commit `85769de`)
5. `_StreamAwareLiveCard` converted to `StatefulWidget` — stops repeated `/streams` calls on every 10s poll.
6. `_Countdown` 1s timer self-cancels at zero and doesn't start for past start times.

### Reconciliation pass (commit `bcca3b3`)
7. **P0-1** Backend `phase` implemented in all three providers (new `match-phase.js`).
8. **P0-2** `_isLiveStatus` widened to match `CricketMatch.isLive`; `_MatchStateHelper.of` consults backend `phase`.
9. **P0-3** `_LiveFooter` accepts a real `lastUpdatedAt`; shows a ticking "Updated X ago" or nothing, never fake "Updated just now".
10. **P1-5** `_looksLikeResult` tightened to past-tense/terminal phrases.
11. **P1-6** Live-tab extras bubbles route Wd/Nb/B/Lb in amber via `_BallKind.extra`.
12. **P2-1** Static registries bounded to 200 entries.
13. **P2-3** Matches refresh key includes `phase` + `resultText`.
14. **P3-1** TEMP DIAGNOSTIC debugPrint blocks deleted.

## 3. Bugs deferred (with reason)

- **P1-7** standings freshness — needs backend `meta.lastUpdated` on every route; additive but touches multiple route handlers.
- **P1-8..P1-12** UI shared-component migration — regression-prone across every screen; documented for a dedicated future pass with analyzer + tests gating each step.
- **P2-2, P2-4, P2-5, P2-6, P2-9, P2-10, P2-11, P3-2, P3-4, P3-5** — low impact; bundled for a future cleanup commit.

## 4. Verified NOT bugs (agent claims that did not hold up)

- **"HomeHeroCard/HeroFixture are dead, delete them."** — Incorrect. `test/widget_test.dart:31,65` instantiates both. (Agent only grepped `lib/`, not `test/`.)
- **"`_isLiveMatchData` makes a stumps match stop polling on Match Details."** — Does not occur. `match_details_screen.dart` calls `CricketMatch.fromJson(data).isLive` first; the model treats stumps as live.

## 5. Backups created

No source files were overwritten destructively. The pre-review WIP was committed and pushed before any review work, so the pre-review state is recoverable from git history. Local junk (API dumps, `target/`, design backups) was excluded via `.gitignore` rather than deleted.

## 6. Backend fields added

- **`phase`** (additive) on every match object from all three providers, via `cricket-api/src/lib/match-phase.js`. Canonical values: `upcoming` · `live` · `stumps` · `lunch` · `tea` · `drinks` · `rain` · `innings_break` · `completed` · `no_result` · `abandoned` · `cancelled`. Existing `status` is unchanged.
- Backend files changed: `cricket-api/src/lib/match-phase.js` (new), `cricket-api/src/providers/cricbuzz/normalizer.js`, `cricket-api/src/providers/cricinfo/normalizer.js`, `cricket-api/src/providers/cricketdata/index.js`.
- No `/series` standings backend sort was added or claimed — the canonical sort is and remains frontend-side (`series_detail_stats.dart:136`).

## 7. UI consistency improvements

Six screens now route status through `MatchStatusDisplay` (Home, Matches, Match Details header, minimized bar, Schedule card, Series match card). The Live tab's commentary notes and recent-over extras bubbles now match the Commentary/Overs tabs. Shared-component migration (custom hero/tab/squad/badge/card) is deferred.

## 8. Performance optimizations

See `docs/PERFORMANCE_OPTIMIZATION_REPORT.md`. This pass: stopped repeated `/streams` calls, self-cancelling countdown timers, deleted parse-path debug prints, bounded the static registries, and widened the Matches change-key. The duplicated live-poll state machine (4 copies) remains the biggest deferred item.

## 9. Data logic fixes

- Status badge + phase label agree across all six card surfaces (no LIVE pill + Stumps note).
- Backend now emits `phase`; `MatchStatusDisplay` prefers it, with a safe `statusText` + coarse-status fallback.
- Match category classification is consistent across Matches/Schedule/repository.
- Live-tab state classifier treats stumps/lunch/tea/innings-break/rain as live.
- Live-tab extras (Wd/Nb/B/Lb) read the same as the Overs/Commentary tabs.
- `_looksLikeResult` no longer mis-classifies a live chase as finished.

## 10. Test/build results (run from clean)

| Command | Result |
|---------|--------|
| `flutter clean` | exit 0 |
| `flutter pub get` | exit 0 |
| `flutter analyze lib/` | **No issues found**, exit 0 |
| `flutter test` | **192/192 passed**, exit 0 |
| `node --check` on 4 changed backend JS files | **4/4 OK** |
| `flutter build apk --release` | **exit 0**, `build/app/outputs/flutter-apk/app-release.apk`, **79.8 MB (83,632,445 bytes)**. Font tree-shaking cut MaterialIcons-Regular.otf 98.7%. One non-fatal Kotlin incremental-cache warning in the build log; the build recovered and produced the APK. |

## 11. Manual QA results

**Not verified on emulator/device this session.** All fixes are verified by `flutter analyze` (clean), `flutter test` (192/192), and a release build. Device verification is still required, especially: a live match, a stumps/lunch/tea/innings-break match, a finished match, an upcoming match, a wide/no-ball in the recent-over bubbles, and a live chase ("India need X to win"). See `docs/UI_VISUAL_QA_CHECKLIST.md`.

## 12. Remaining risks

- **Manual QA not run** — the status-contradiction fixes need confirmation on a live stoppage match on a real device.
- **P2-7** CricketData `#mapStatus` still collapses abandoned/no-result into `completed` at the coarse-status level; `derivePhase` recovers it from text, but a match with no status text would still badge as RESULT. Widening `#mapStatus` is the full fix.
- **Shared-component migration deferred** — custom hero/tab/squad/badge implementations remain and can drift.
- **P1-12** duplicated live-poll state machine — four copies, dispose-leak risk until consolidated.

## 13. Next recommended phase

1. **Backend `meta.lastUpdated` on every route** (P1-7) — makes the "Updated X ago" row accurate everywhere.
2. **Widen CricketData `#mapStatus`** (P2-7) — emit `abandoned`/`no_result` coarse status, not just `completed`.
3. **Extract `LivePollController`** (P1-12) — one shared polling state machine, with a test preserving each screen's intervals.
4. **Shared-component consolidation pass** (P1-8..P1-11) — the big UI consistency win, done as a dedicated low-regression-risk sweep.
5. **Device QA** — run the manual checklist against a live + stoppage + finished + upcoming match.
