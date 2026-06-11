# AI Task Log

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
