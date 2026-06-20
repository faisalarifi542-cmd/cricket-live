# Phase 4 — Home Screen Improvement Report

## Update (2026-06-14): Home score refresh verification + target color polish pass

`flutter analyze lib/` → **No issues found** (12.7s). No APK/appbundle/release build run.

### NEW root cause found — hero score still stale on device

The previous fix (`_heroData`/`_heroKey`/8s hero-aware polling) was correct for
the *list-vs-hero* freeze, but missed the actual device bug: **the hero and the
live cards read from two different endpoints.**

- Hero ← `/app/home` `topFeaturedMatches` (admin-curated, **cached/stale** on the
  backend — a featured LIVE match's score there does not advance).
- Live cards ← `/matches/live` (fast, fresh).

So polling fired correctly every 8s, `_resolveHero(forceRefresh:true)` re-hit
`/app/home`, but the bytes came back identical → `_refreshKey` unchanged →
`freshKey == _heroKey` → early-return, no repaint. Exactly the "API fresh but UI
old" symptom: the *live* API was fresh, the *home* API the hero used was not.

**Fix** (`lib/screens/home/home_screen.dart`): new `_overlayLiveScores()`. After
`/app/home` resolves the featured list, we fetch `/matches/live` and **replace any
hero whose id appears in the live feed with its fresh live counterpart** (matched
by id). Non-live heroes and heroes absent from the live feed are untouched. Now a
live hero's score/status tracks the authoritative live endpoint regardless of
`/app/home` caching. Best-effort: a live-feed failure leaves admin heroes intact.
Match Details polling is untouched.

### Score-key coverage

`_refreshKey = id + statusText + teamAScoreText + teamBScoreText` — already
includes both teams' full score text (runs/wkts + overs, since
`teamAScoreText` carries the `(x OV)` suffix) plus status. The key was never the
problem; the **data source feeding it** was. With the live overlay the key now
changes as the live score changes, so the existing repaint path fires.

### Does `_silentPoll` fire independently of the lower list?

Yes. `_refreshHeroSilently()` is called **unconditionally** every poll, outside
the `if (changed)` list branch (home_screen.dart). Verified by reading the path;
also now logged (`CricProHomeHero: refresh changed=…`).

### Hero refresh path updates UI?

Yes — on `freshKey != _heroKey` it `setState`s `_heroFuture = Future.value(...)`,
so the `FutureBuilder` rebuilds with fresh data and scroll is restored (no jump).

### Live card refresh path updates UI?

Yes — `_silentPoll` swaps `_tabFuture` only when the list key changed, so live
cards in the lower list repaint when their score changes; no blink when unchanged.

### Score color changes (target cricket-readability spec)

- Hero overs text was tinted with `sColor` (→ **red** while live). Fixed to muted
  **cyan** always; red is now reserved strictly for the `/wickets` segment.
- Live runs: white (dark) / `c.text` (light); `/wickets`: `c.live` (red/pink);
  overs: muted cyan; finished scores: cyan; result/FINISHED: green; UPCOMING/live
  status pill: cyan. Consistent across `_HeroTeamBlock`, `_HomeTeamBlock`,
  `_CompactTeam` via `_HeroScoreText` / `_LiveScoreText`.

### Hero title priority

`_heroTitle()` hardened: series/tour/tournament → non-generic match title →
`TeamA vs TeamB`. Now skips a full placeholder set (`cricket match`, `match`,
`live match`, `upcoming match`, `finished match`, `tbd`, `tbc`, `null`). Applied
to hero **and** the compact grid card (previously used raw `match.series`).

### Temporary debug logs added (kDebugMode only, compiled out in release)

All via `debugPrint` inside `if (_kHomeDebug)` (`_kHomeDebug = kDebugMode`).
Tags for logcat filtering:

- `CricProHomePoll: configure tab=… heroId=… heroLive=… interval=…s`
- `CricProHomePoll: silentPoll tab=… listChanged=… prevLen=… newLen=…`
- `CricProHomePoll: silentPoll FAILED (offline?) failures=… — arming recovery`
- `CricProHomePoll: recovery fired failures=… delay=…s`
- `CricProHomeHero: refresh changed=… heroId=… oldScore=[…|…] newScore=[…|…] status=…`
- `CricProHomeHero: overlaid N/M hero(es) with fresh /matches/live score`
- `CricProHomeCard: live build id=… score=[…|…] status=…`
- `CricProHomePoll: upcomingMerged matchesUpcoming=… scheduleUpcoming=… afterDedupe=…`

Locations: `lib/screens/home/home_screen.dart` (poll/hero/recovery/overlay),
`lib/screens/home/widgets/home_match_cards.dart` (live card build),
`lib/repositories/cricket_repository.dart` (`upcomingMatchesMerged` counts).

**How to verify on device:** `flutter run` (debug), open Home with a live match,
watch logcat: `adb logcat | grep CricProHome`. Expected ~every 8s a
`silentPoll` line; when the live score advances, a `CricProHomeHero: refresh
changed=true` with differing old/new score, then a `CricProHomeCard` build with
the new score. If `overlaid N/M` shows but `changed=false`, the live feed itself
is static; if no `silentPoll` lines appear, the timer isn't arming (check
`configure` log).

### Upcoming count debug

`CricProHomePoll: upcomingMerged matchesUpcoming=… scheduleUpcoming=…
afterDedupe=…` logged in the repository merge. If `afterDedupe` is high but the
row shows few, the cap/hero-exclusion in the UI is the limiter; if
`scheduleUpcoming=0`, the schedule source/parse path is the issue.

### analyze result

`flutter analyze lib/` → **No issues found! (ran in 12.7s)**

---

## Update (2026-06-14): Duplicate hero + upcoming visibility + score refresh fix

Device-reported gaps closed. `flutter analyze lib/` → No issues found; `flutter
test` → 38/38 passed. No APK/appbundle/release build run.

### Root cause — Home score not updating

The silent poll refreshed the hero ONLY inside the `if (changed)` branch, and
`changed` was computed from the **lower match list** — which **excludes the
primary hero match**. So when the featured match was the only live game, the
list never changed, `changed` stayed false, and the hero score froze until a
manual pull-to-refresh. Two further gaps: on the Upcoming/Finished tabs the live
hero polled slowly or not at all, and offline→online recovery only re-armed for
the Live tab.

Fix (`lib/screens/home/home_screen.dart`):
- Track hero state independently: `_heroData` + `_heroKey` (content fingerprint
  via `_refreshKey`).
- New `_refreshHeroSilently()` re-resolves the hero every poll and swaps it in
  only when its key changed — score updates in place, no blink, scroll
  preserved. Called from `_silentPoll` regardless of whether the list changed.
- `_configurePolling()` now polls at the 8s live cadence on ANY tab while the
  hero is a live match (so a live featured match never freezes behind the
  Upcoming/Finished tab). Finished-tab list refetch is skipped when the poll is
  only keeping the hero fresh.
- `_captureHeroIds()` re-arms polling when the hero's live-ness flips.
- `_armRecovery()` now recovers on any tab when the hero is live (was Live-tab
  only), and self-heals both the list and the hero — so offline→online resumes
  without pull-to-refresh.

### Root cause — Upcoming only showing 2

`/matches/upcoming` returns only 1–2 fixtures (verified live). The broad source
is `/schedule/upcoming`, which returns the full set (**38 fixtures** verified
live, nested `{data:{days:[{series:[{matches:[]}]}]}}`). The repository already
merges both via `upcomingMatchesMerged()`, and `_asList()` already flattens the
`days` shape — so the current code surfaces all 38. The device was running an
older build; no code change required. Both Home (`_loadUpcomingMerged`) and the
Matches screen "All" use the merged + `UpcomingSort`-ordered feed, deduped by
match id, international + league + domestic, sorted by start time with
favourite-aware tie-breaks.

### Hero duplicate

Already fixed in prior work (only the primary/first hero id is excluded from the
list). Confirmed unchanged.

### Score colors (target style)

`_LiveScoreText` (rich list cards) was already in place. Extended the same
runs-white / `/wickets`-red treatment to the remaining card variants:
- Hero: new `_HeroScoreText`, wired `live:` into both `_HeroTeamBlock`s
  (`home_hero.dart`). Still inside `FittedBox(scaleDown)` — scores never
  truncate.
- Compact grid cards: `_CompactTeam` now uses `_LiveScoreText` in a
  `FittedBox(scaleDown)`, `live:` wired (`home_match_cards.dart`).
- Finished scores stay cyan (no red wickets); LIVE badge red, UPCOMING cyan,
  FINISHED green, result/status pills unchanged.

### Hero / card title

`_heroTitle()` now prefers series / tour / tournament (e.g. "Australia tour of
Bangladesh, 2026"), falling back to match title then "TeamA vs TeamB"; generic
"Cricket Match" placeholder is skipped. Applied to hero, live, upcoming, and
finished list cards (`home_featured.dart`, `home_match_cards.dart`). Ellipsis on
overflow.

### Search removal / quick actions

Confirmed already removed: header is CRICPRO logo + notification bell only
(`home_header.dart`), no search icon/callback/route. No quick-action cards in
`_buildSections`.

### Favorite Countries

Confirmed complete: `FavoriteCountriesService` (all 20 countries: AFG IND PAK
BAN SL AUS ENG NZ SA WI NED IRE ZIM NEP UAE USA OMA SCO NAM CAN), SharedPreferences
persistence, `FavoriteCountriesScreen`, More row with live selected-count badge,
used in hero priority + `UpcomingSort` ordering (non-favourites never hidden).

### Home refresh / offline behavior

Live cards + live hero update silently at 8s; no blink, no scroll jump, no full
loader; offline keeps last score; online self-heals via `_armRecovery` without
pull-to-refresh; live→finished transitions update status/result. Match Details
polling untouched.

### Files changed
- `lib/screens/home/home_screen.dart` — independent hero refresh, hero-aware
  polling + recovery.
- `lib/screens/home/widgets/home_hero.dart` — `_HeroScoreText`, `live:` wiring.
- `lib/screens/home/widgets/home_match_cards.dart` — compact `_LiveScoreText`,
  card titles.
- `lib/screens/home/widgets/home_featured.dart` — `_heroTitle` series priority.

### Verification
- `flutter analyze lib/` — No issues found.
- `flutter test` — 38/38 passed.
- Live API checked for data visibility: `/matches/upcoming`=1–2,
  `/schedule/upcoming`=38 (merge yields full set).

---

# Phase 4 — Home Screen Improvement Report (original)

## Summary

The Home screen was already substantially built to the target design in prior
work (admin-driven layout config, hero carousel, premium glass cards, status
tabs, featured matches/series, self-healing live polling). Phase 4 was therefore
a **gap-closing pass**, not a rebuild. Two real gaps against the acceptance
criteria were closed:

1. **Responsive 1-column / 2-column Live Matches** (was always 1 column).
2. **Hero match deduplication** (hero matches could repeat in the list below).

Two items were intentionally deferred after confirming scope with the product
owner: the header search icon (no search screen exists) and a separate
"quick action cards" row (absent from the actual target screenshot).

## 1. Files inspected

- `lib/screens/home/home_screen.dart` — state, polling, hero resolution, section builder
- `lib/screens/home/widgets/home_header.dart` — CRICPRO header + notification bell
- `lib/screens/home/widgets/home_hero.dart` — hero carousel + hero card
- `lib/screens/home/widgets/home_match_cards.dart` — status tabs, match list, live/upcoming/finished cards, team block, VS badge, action bar
- `lib/screens/home/widgets/home_actions.dart` — action buttons, status badge, empty/skeleton states, category filter
- `lib/screens/home/widgets/home_featured.dart` — featured matches row, featured series cards, date helpers
- `lib/models/home_feed.dart` — feed + admin layout config model
- `lib/main.dart` — HomeScreen wiring (callbacks)
- `lib/app_theme.dart` — width/breakpoint/padding helpers

## 2. Files changed

- `lib/screens/home/home_screen.dart`
  - Added `Set<String> _heroIds` state.
  - Added `_captureHeroIds(Future)` helper; wired into `initState`, `_refresh`, and `_silentPoll` so the set always tracks the currently rendered hero carousel ids (with a stale-future guard).
  - Passed `excludeIds: _heroIds` into `_HomeMatchList`.
- `lib/screens/home/widgets/home_match_cards.dart`
  - `_HomeMatchList`: added `excludeIds` param; filters hero matches out before capping to `maxItems`; wrapped layout in `LayoutBuilder` to pick 1 vs 2 columns by width.
  - Added `_HomeMatchGrid` — two-column grid of compact cards, `IntrinsicHeight` row pairs so both columns share an even height.
  - Added `_HomeCompactMatchCard` — leaner card variant for grid cells (status + series, teams + scores, single-line status note with ellipsis, divider, action bar). Live cells still resolve real stream availability via `_LiveActionBar`.
  - Added `_CompactTeam` — smaller logo+code+score block for grid cells.

No other files touched.

## 3. Home layout changes

Section order and all existing sections are unchanged (admin-driven via
`HomeLayoutConfig`): Header → Hero carousel → Status tabs → Category filter →
Main match list → Featured Matches → Featured Series. The only visual change is
the main match list now renders as a 2-column grid on wider layouts.

## 4. Responsive behavior

Implemented with `LayoutBuilder` inside `_HomeMatchList`, keyed on the list's
own `constraints.maxWidth`:

- `maxWidth < 420` → single column of the existing rich `_HomeMatchCard`
  (unchanged for all normal phones, including 360 px). The rich card carries a
  3-cell meta row + full action bar that would squeeze below ~200 px, so it is
  deliberately kept 1-column on narrow phones.
- `maxWidth >= 420` → `_HomeMatchGrid` with two `_HomeCompactMatchCard`s per
  row. This covers large phones (in portrait where padding leaves ≥420 px of
  inner width, and in landscape), foldables, and tablets.

This is the agreed **Hybrid** approach: compact 2-col where there is room, rich
1-col on narrow phones. No hardcoded "always 2 columns". The hero carousel,
upcoming featured-matches row (horizontal scroll), and featured series cards
already adapt their sizes by `context.w`.

## 5. Hero carousel logic

Unchanged from prior work and already matches the required priority via the
backend/admin feed:

- `_resolveHero()` prefers admin-resolved `topFeatured` matches.
- Falls back to `_loadHero()` which aggregates unique matches in priority order:
  live (tab 0) → upcoming (tab 1) → recent (tab 2) → schedule upcoming, capped
  at 5, deduped by id.
- Favorite-team data is not yet implemented in the app; the aggregation already
  sorts live-first then upcoming, satisfying the "prepare logic with fallback"
  requirement. (When favorites land, they can be promoted ahead of the existing
  live-first ordering inside `_loadHero`.)

## 6. Live match exclusion logic (no duplicates)

`_captureHeroIds` records the ids of the (up to 5) matches actually shown in the
hero carousel each time `_heroFuture` resolves — on first load, on
pull-to-refresh, and on each silent poll that swaps the hero. A stale-future
`identical()` guard prevents an old hero load from clobbering newer ids.
`_HomeMatchList` filters `excludeIds` out of the fetched tab data **before**
capping to `maxItems`, so a matchId in the hero never appears again in Live /
Upcoming / Finished. If filtering empties the list, the existing empty-state /
section-hide behavior handles it.

## 7. Watch Live conditional logic

Unchanged. `_LiveActionBar` (used by both the rich live card and the new compact
live card) seeds an optimistic value from the match's embedded stream flags,
then reconciles with the authoritative `repository.shouldShowWatchLiveForMatch`.
Watch Live renders **only** when a playable, admin-enabled stream exists;
otherwise the card shows View Match at full width. Upcoming/Finished cards never
show Watch Live.

## 8. Empty section behavior

Unchanged and already correct:

- Main list with no matches (or none after hero exclusion) → friendly empty
  state (with "View upcoming fixtures" shortcut on the Live tab).
- Featured Matches with no data → section returns `SizedBox.shrink()` (hidden).
- Featured Series with no data → section hidden.
- Hero with no matches → compact empty/offline card.

## 9. Tests / build commands run

- `flutter analyze lib/` → **No issues found**.
- `flutter test` → **All 38 tests passed** (includes existing hero-fits-constrained-height and team-logo-fallback widget tests).
- `flutter build apk --release --target-platform android-arm64` → **Built app-release.apk (28.2 MB)**, unchanged from the prior baseline.

## 10. Devices / widths checked or recommended

- Layout breakpoint logic verified by reading constraints; analyze + existing
  widget tests (which build the hero at constrained mobile heights) pass.
- **Recommended manual checks**: 360 px phone (1-col, no overflow), ~411–430 px
  large phone portrait (confirm whether inner width crosses 420 → 2-col),
  large phone landscape and 7"/10" tablet (2-col grid even heights), long
  series/team/venue names (ellipsis), pull-to-refresh, and a live score tick
  (no blink / no scroll jump). Automated tooling here cannot exercise a live
  device, so on-device verification of the 2-col grid is advised before release.

## 11. Intentionally left unchanged

- **Live-score polling** (`_configurePolling`, `_silentPoll`, `_armRecovery`,
  `_refreshKey`, `_restoreScroll`, intervals) — untouched. Hero exclusion and
  the 2-col layout are pure render-time changes on already-fetched data; no new
  network calls, no change to refresh keys, no blink/scroll-jump risk.
- **Header search icon** — deferred (no SearchScreen exists; per owner decision).
- **Quick action cards row** — not added (absent from the target screenshot;
  current admin category-filter chip row kept instead).
- Stream player, backend, ads, OneSignal, onboarding, score minimizer, cast
  support, pubspec dependencies — all untouched per phase constraints.

---

# Visual gap-closing pass against target design

A second pass to make Home visually match the target screenshot 1:1. Logic from
the first pass (hero dedup, responsive 1/2-col, conditional Watch Live, polling)
is preserved unchanged; this pass is layout/composition + premium styling.

## Files changed

- `lib/main.dart` — added `_switchTab(AppTab)`; wired new HomeScreen callbacks
  `onOpenSchedule` (→ Schedule tab) and `onOpenMatches` (→ Matches tab, also used
  for the header search icon and section "See All").
- `lib/screens/home/home_screen.dart` — rewrote `_buildSections()` to a fixed
  target composition (no longer renders the category chip row or Featured
  Matches); added `onOpenSchedule` / `onOpenMatches` fields; header now passes
  `onSearch`. `categoryIndex` retained only for admin default-tab plumbing.
- `lib/screens/home/widgets/home_header.dart` — larger CRICPRO logo (34–38 px),
  added circular glass search button (`_HeaderIconButton`) left of the bell,
  both 46 px premium glass circles.
- `lib/screens/home/widgets/home_hero.dart` — rebuilt `_HeroMatchCard` to the
  large premium target layout: bigger card (348–372 px), top row = LIVE badge +
  series title + star button, date•time line, big circular team logos (78–88 px)
  with accent glow ring, large scores (26–29 px), centred status pill under VS,
  venue with pin, full-width gradient **Match Center** CTA. Added
  `_HeroTeamBlock`, `_HeroStarButton`, `_HeroCenterPill`,
  `_HeroMatchCenterButton`, `_heroDateLine`. Carousel viewport widened
  (0.9–0.93) so the active card dominates with subtle side-peek.
- `lib/screens/home/widgets/home_featured.dart` — replaced the category chip row
  with `_HomeQuickActions` (Live Scores, Commentary, Schedule, Rankings, Stats —
  compact glass cards, horizontally scrollable, no overflow at 360 px). Replaced
  `_FeaturedMatchesSection` with `_UpcomingMatchesSection` (horizontal scroll
  cards, hero-excluded, hidden on the Upcoming tab to avoid duplicating the main
  list). Featured Series section retained.
- `lib/screens/home/widgets/home_match_cards.dart` — tuned the compact 2-col card
  (logos 44 px, wider VS gap, more vertical breathing room, single-line ellipsis
  status note) so 2-up cells no longer feel squeezed.
- `lib/components.dart` — premium `BottomNav`: rounded glass pill container,
  cyan-tinted active cell highlight, top indicator + icon scale animation,
  larger touch target, softer inactive icons.

## What was fixed (mapped to the request)

1. Header too small → larger logo + search + bell. ✓
2. Hero too small → large premium hero with bigger logos/score, centred Match
   Center button, star, stronger spacing. ✓
3. Default Home shows Live (admin `defaultTab` = `live`; status tabs default to
   index 0). ✓
4. Quick action cards row added (Live Scores / Commentary / Schedule / Rankings
   / Stats). ✓
5. Category chip row removed from Home. ✓
6. Section order: Header → Hero → Live/Upcoming/Finished tabs → Quick actions →
   Live Matches → Upcoming Matches → Featured Series → (bottom nav). ✓
7. "Featured Matches" no longer shown on Home; uses Live Matches / Upcoming
   Matches / Featured Series. ✓
8. Hero match excluded from Live Matches (and from the Upcoming row) via
   `_heroIds`. ✓ (unchanged from first pass)
9. Watch Live only when a real stream exists (`_LiveActionBar`). ✓ (unchanged)
10. < 420 px → 1-column; ≥ 420 px → 2-column compact cards. ✓ (unchanged)
11. Compact card spacing/logos/ellipsis/action height improved. ✓
12. Bottom nav: larger touch area, glass background, cyan active, softer
    inactive. ✓

## Quick action routing (real data, no fake screens)

- Live Scores → selects the Live status tab.
- Commentary → opens Match Center (match details, where Commentary lives).
- Schedule → switches to the Schedule tab.
- Rankings → opens the Rankings screen.
- Stats → opens the Rankings screen (no standalone Stats screen exists; reused
  the closest real destination rather than inventing a placeholder).

## Verification

- `flutter analyze lib/` → No issues found.
- `flutter test` → All 38 tests passed (legacy `HomeHeroCard` constrained-height
  test still green; the live screen uses the new `_HeroMatchCard`).
- `flutter build apk --release --target-platform android-arm64` → Built
  app-release.apk (28.2 MB), unchanged size.

## Notes / left as-is

- Header search routes to the Matches tab as a stopgap (still no dedicated
  SearchScreen); the icon now matches the target visually.
- Stats quick action maps to Rankings until a real Stats destination exists.
- Hero height (348–372 px) is large per target but bounded; long names ellipsis,
  no overflow on 360 px. On-device check of the taller hero on very short
  screens is recommended before release.
- Polling, stream player, backend, ads, onboarding, score minimizer, cast —
  untouched.

---

# Device screenshot polish pass

Real-device screenshots (OnePlus 10 Pro portrait + ~360dp phone) exposed
layout problems the analyzer/build could not catch: a hero that was too tall
and zoomed with truncated scores ("27..."), truncated quick-action labels
("Live Sc..."), an oversized empty Live state, a too-tall bottom nav, and a
2-column breakpoint that squeezed normal phones. This pass fixes those without
touching any business logic or networking.

## What was wrong (from screenshots)

- Hero card too tall/zoomed on small phones; team logos oversized; **team
  scores truncated to "27..."**; status pill competing with the score area;
  venue + CTA pushed too low.
- Carousel side-peek too aggressive on narrow screens.
- Segmented Live/Upcoming/Finished control too tall.
- Quick action labels truncated ("Live Sc...", "Comme...").
- Empty Live Matches state too large and visually heavy.
- Compact 2-column cards too dense (breakpoint 420 too aggressive for phones).
- Upcoming Matches card too tall and cut off at the bottom.
- Featured Series card slightly too tall on small phones.
- Bottom nav too tall; active Home cell too large; reduced visible content.
- Header logo could sit too close to the status bar on small devices.

## Files changed

- `lib/screens/home/widgets/home_hero.dart`
- `lib/screens/home/widgets/home_header.dart`
- `lib/screens/home/widgets/home_match_cards.dart`
- `lib/screens/home/widgets/home_featured.dart`
- `lib/screens/home/widgets/home_actions.dart`
- `lib/screens/home/home_screen.dart`
- `lib/components.dart`

## Hero size changes

Introduced `_HeroMetrics.of(context)` — resolves hero sizing from **both**
width and height so a tall-but-narrow phone and a short device both get the
compact tier:

| Tier | Trigger | Height | Logo | Score | CTA | viewportFraction |
|------|---------|--------|------|-------|-----|------------------|
| Small | width < 400 **or** height < 750 | 308 | 66 | 25 | 48 | 0.96 |
| Normal | phones | 332 | 76 | 30 | 50 | 0.93 |
| Wide | width ≥ 600 | 360 | 86 | 34 | 52 | 0.86 |

- **Scores never ellipsis** — `scoreMain`/`scoreOvers` are wrapped in
  `FittedBox(fit: scaleDown)`, so they shrink to fit the column instead of
  truncating to "27...". Long status text (e.g. "Australia need ...") still
  ellipsis, but in its own centered pill row.
- The status pill moved out of the VS column into a dedicated centered row
  beneath the teams, so it no longer overlaps the scores.
- Carousel side-peek reduced (viewportFraction 0.93–0.96 on phones; less scale
  falloff) so the main card dominates.

## Responsive breakpoint change

- Match-card grid threshold raised **420 → 520**. Most phones now render the
  single rich column; 2-column compact cards are reserved for wide screens,
  foldables, tablets, and landscape where they read cleanly.

## Bottom nav changes

- Container top/bottom padding reduced (8→5 / 4→2), cell vertical padding 8→6,
  indicator 30→28, icon 27→25, label 12→11.5, corner radii tightened. Net
  height down ~12–15% with the same glass look and cyan active highlight.

## Quick action improvements

- Labels now allow **two lines** (fixed 26px label box) so "Live Scores" and
  "Commentary" read fully instead of clipping. Icon circle 38→34, tighter
  inter-card gap so all five fit at 360dp.

## Empty-state behavior

- On the **Live tab with no matches** (after hero exclusion), the entire Live
  Matches section (header + body) is now hidden, so Upcoming Matches flows up
  directly and the empty card never dominates Home.
- For the Upcoming/Finished tabs, the empty state was redesigned as a short
  horizontal row (icon + message) instead of a tall centered block.

## Other polish

- Upcoming Matches row is now a compact horizontal card (height 150, smaller
  logos, date-only footer, venue omitted) so it no longer gets cut off.
- Featured Series height is responsive (134 small / 152 normal / 176 wide) with
  a smaller CTA circle on narrow screens.
- Section "See All" → **"View All"** to match the final target.
- Header logo gets a touch more top padding and line-height headroom so it is
  never clipped under the status bar (Home already sits inside `SafeArea`).
- Segmented control height 50→44 on small screens.
- Section spacing nudged toward the target rhythm (header→hero 14, quick→title
  20).

## Verification

- `flutter analyze lib/` → No issues found.
- `flutter test` → All 38 tests passed (legacy `HomeHeroCard` constrained test
  still green).
- `flutter build apk --release --target-platform android-arm64` → Built
  app-release.apk (28.2 MB).

## Still left as-is (logic untouched)

- Header search → Matches tab; Stats quick action → Rankings (no dedicated
  Search/Stats screens exist).
- Default Home tab remains Live via admin config; Finished only shows after the
  user taps it.
- Live score polling, stream player, backend, ads, onboarding, score minimizer,
  cast, app-size cleanup, pubspec — untouched.

---

# Device screenshot polish pass — follow-up (hero overflow root cause)

A second round of real-device screenshots (OnePlus, 100% battery, 12:50) showed
the earlier polish landed correctly everywhere — quick-action labels readable
("Live Scores" / "Commentary" on two lines), Upcoming row compact, "View All"
labels, slim bottom nav, no status-bar clipping — **except the hero**, which
rendered Flutter's debug overflow stripe: `BOTTOM OVERFLOWED BY 34 PIXELS` on
each team block, with the score collapsing on top of the centre status pill.

## Root cause

The hero team block is a `Column` (logo ring → code → score → overs) placed
inside the hero's `Expanded` middle row. On short/zoomed devices the block's
intrinsic height exceeded the fixed slot height, so it overflowed vertically.
The per-line `FittedBox` added earlier only constrained each score line's
*width*; it did nothing for the *column's total height*, so the block still
overflowed and painted over the status pill.

## Fix

- `lib/screens/home/widgets/home_hero.dart` — wrapped the **entire**
  `_HeroTeamBlock` column in a `FittedBox(fit: BoxFit.scaleDown)`. The block now
  scales down uniformly to fit whatever slot height it's given, so it can never
  overflow regardless of score length, logo size, or screen height. Team scores
  scale rather than truncate, and the status pill keeps its own row underneath
  the teams (no overlap).

This is a pure layout-safety change: no metric tiers, business logic, or
networking were touched in the follow-up.

## Verification

- `flutter analyze lib/` → No issues found.
- `flutter test` → All 38 tests passed.
- `flutter build apk --release` → skipped at user request this round (prior
  passes built cleanly at 28.2 MB; no dependency or asset changes since).

## Expected result on device

- No overflow stripe on the hero.
- BAN / AUS scores fully readable (e.g. "274/5 (50.0 ov)"), no "27...".
- Centre status pill ("Australia need 194 runs") sits in its own row, not over
  the scores.
- Hero stays balanced and premium; Match Center CTA and venue fully visible.

---

# Home visual proportion polish pass

Overflow was fixed and all content readable, but device screenshots showed the
layout still felt oversized/stretched: hero dominated the screen, header and
bottom nav were tall, quick-action "Commentary" broke mid-word ("Commenta\nry"),
and a large gap sat between quick actions and Upcoming Matches. This pass tunes
proportions only — no business logic, networking, or section-order changes.

## Hero size changes (`home_hero.dart`)

Reduced every `_HeroMetrics` tier ~10–15% so the hero is premium but no longer
screen-dominating, leaving more content visible below the fold:

| Tier   | height (was→now) | logo (was→now) | score (was→now) | CTA h (was→now) |
|--------|------------------|----------------|-----------------|------------------|
| small  | 308 → 272        | 66 → 58        | 25 → 23         | 48 → 44          |
| normal | 332 → 296        | 76 → 68        | 30 → 27         | 50 → 46          |
| wide   | 360 → 332        | 86 → 78        | 34 → 31         | 52 → 48          |

- Match Center CTA is no longer full-bleed: centred pill capped at `maxWidth:
  280`, smaller font (15/14) and chevron — reads balanced instead of a big bar.
- Scores still wrapped in `FittedBox(scaleDown)` so they remain readable and
  never truncate at the smaller base sizes.
- Side-peek tightened slightly (viewportFraction normal 0.93 → 0.94, small
  0.96 → 0.965) so the main card dominates.

## Header size changes (`home_header.dart`)

- Header height 54 → 48; top/bottom padding 6/4 → 4/2.
- Logo 32/37 → 30/34.
- Search + bell circles 46 → 42, icons 23 → 21, gap 12 → 10.

## Quick action card changes (`home_featured.dart`)

- Card padding 10 → 9 vertical; icon circle 34 → 32, icon 18 → 17.
- Label is now a single line in a `FittedBox(scaleDown)` (was 2-line wrap) so
  "Commentary" scales to fit cleanly instead of breaking mid-word. Same five
  actions kept.
- Row gap 7 (unchanged); cards are shorter overall.

## Section spacing (`home_screen.dart`)

Tightened the vertical rhythm so Home no longer feels stretched:
- Header → hero: 14 → 12
- Hero/dots → tabs: 16 → 12
- Tabs → quick actions: 16 → 14
- Quick actions → next section: 20 → 16

## Bottom nav (`components.dart`)

Slimmed a further ~10%:
- Container margin-top 6 → 5; padding top 5 → 4, bottom 2/6 → 0/5.
- Active cell vertical padding 6 → 5; indicator gap 6 → 4, label gap 4 → 3.
- Icon 25 → 23; active indicator width 28 → 26.
- Content bottom padding (`mainBottomPadding + 84`) unchanged, so the slimmer
  nav still never covers section content.

## Upcoming / Featured card sizes (`home_featured.dart`)

- Upcoming row height 150 → 138; mini-card padding 10/11 → 9/10, team logo
  40 → 36 — compact horizontal card (status, series, logos/codes, date), venue
  already omitted on Home.
- Featured Series height already responsive and in target range (small 134,
  normal 152, wide 176) with a smaller CTA circle on narrow phones — left as-is.

## Responsive rules (unchanged, confirmed)

- Match-card grid stays 1-column < 520 dp, 2-column ≥ 520 dp.
- No score truncation, no status-bar clipping, no nav overlap.
- Live Matches section still hidden entirely when empty after hero exclusion;
  other tabs use the compact row empty state.

## Verification

- `flutter analyze lib/` → No issues found.
- Release APK build skipped at user request (user builds it themselves).
