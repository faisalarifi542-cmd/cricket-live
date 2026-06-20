# AI Project Index — CricPro

## Architecture
- **Framework**: Flutter (Dart), Material 3 with `useMaterial3: true`
- **State**: StatefulWidget + FutureBuilder pattern, no external state management
- **Theme**: Centralized `CricColors` ThemeExtension in `lib/app_theme.dart`
  - Access via `context.cric` (extension on BuildContext)
  - All components branch on `c.isDark` for light/dark styling
- **Navigation**: MaterialPageRoute push/pop, bottom navigation shell

## Key Design Files
| File | Purpose |
|------|---------|
| `lib/app_theme.dart` | `CricColors` ThemeExtension — all color tokens, light/dark definitions |
| `lib/components.dart` | Shared widgets: PremiumCard, GradientButton, BottomNav, TeamLogoWidget, PlayerAvatarWidget, PillChip, StatusBadge, **StadiumImage** |
| `lib/models.dart` | Data models (re-exports) |
| `lib/api_models.dart` | API response models |

## Theme Token Reference (CricColors)
| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| `bg` | `#eef5fc` ice blue | `#020b18` deep navy | App background |
| `card` | `#ffffff` white | `#0a1e3d` dark navy | Card surfaces |
| `text` | `#0a1e3d` navy | `#ffffff` white | Primary text |
| `muted` | `#5e7a9a` slate | `#7a8fa6` | Secondary text |
| `cyan` | `#00c8f0` | `#00e5ff` | Brand accent |
| `border` | `#c9ddf3` soft blue | `#1a3050` | Borders |
| `cardShadow` | Blue-tinted soft | Heavy black | Card shadows |
| `heroShadow` | Blue-tinted medium | Heavy black + cyan glow | Hero/featured card shadows |
| `stadiumOverlayColors` | White fade to bg | Dark fade to bg | Stadium backdrop gradient |
| `heroOverlayColors` | White semi-transparent | Dark navy gradient | Hero card overlays |
| `matchCardOverlayColors` | White semi-transparent | Dark semi-transparent | Match list card overlays |
| `onImageText` | Navy `#0a1e3d` | White `.88` alpha | Text on image surfaces |
| `subtleSurface` | Blue-tinted `#e0ecf6` | White `.02` alpha | Subtle button/chip bg |
| `stadiumImageOpacity` | `.16` faint | `1.0` full | Stadium **backdrop** photo opacity |
| `heroImageOpacity` | `.34` | `1.0` full | Stadium photo **inside cards** opacity |
| `stadiumImageTint` / `stadiumImageBlend` | white `.55` + `lighten` | null + `dst` | Lightens dark stadium art in light mode |

## Screen File Map
| Screen | File |
|--------|------|
| Home | `lib/screens/home/home_screen.dart` |
| Matches | `lib/screens/matches/matches_screen.dart` |
| Schedule | `lib/screens/schedule/schedule_screen.dart` |
| Series List | `lib/screens/series/series_list_screen.dart` |
| Series Detail | `lib/screens/series/series_detail_screen.dart` |
| Match Details | `lib/screens/match_details/match_details_screen.dart` |
| Player Profile | `lib/screens/player/player_detail_screen.dart` |
| More | `lib/screens/more/more_screen.dart` |
| Rankings | `lib/screens/rankings/rankings_screen.dart` |
| Teams | `lib/screens/teams/teams_screen.dart` |
| News | `lib/screens/news/news_screen.dart` |
| Highlights | `lib/screens/highlights/highlight_detail_screen.dart` |
| Live Player | `lib/screens/live/live_player_screen.dart` |

## Design Rules
1. **Never hardcode dark-mode colors** — always use `c.isDark` branching or CricColors tokens
   - Common bug: a `const Color(0xff0…)` navy literal (or a hardcoded `Colors.white` dot)
     inside a widget renders in BOTH themes → muddy dark cards / invisible dots in light mode.
     Audit with: `grep -rn "Color(0xff0" lib/screens lib/components` and check each isn't
     a non-branching surface. Known intentional exceptions below.
   - Intentional dark-in-both: VS badge dark-glass chip + cyan→blue VS gradient
     (`0xff35e2ff/0a86ff`), `live_player_screen.dart` video surfaces, white-text-on-image
     bottom fades, and `ColoredBox` image-load placeholders.
2. **Image overlays**: Use `c.heroOverlayColors` / `c.matchCardOverlayColors` — white-based in light, dark-based in dark
3. **Text on images**: Use `c.onImageText` — navy in light mode, white in dark mode
4. **Shadows**: Use `c.cardShadow` or `c.heroShadow` — blue-tinted in light, black in dark
5. **Image priority**: Admin uploaded → Provider (Cricbuzz) → Initials fallback
6. **Live player/video screens**: Keep dark overlays (intentional for video readability)
7. **Stadium artwork is a DARK photo** — never place it behind content with a raw
   `Image.asset` in light mode; it bleeds through weak overlays as a grey scrim
   (was the #1 "light mode looks like dark mode" bug). Always use the shared
   `StadiumImage` widget (`hero: true` for in-card art). **In light mode
   `StadiumImage` now swaps to the clean `assets/images/light_mode/*` ice-blue
   PNGs** (via the `LightAsset` registry in `components.dart`) rendered at full
   strength (opacity .92 hero / .8 backdrop, no tint/blend) — these have NO dark
   scrim, so the stadium texture stays VISIBLE through the light white veil
   (matches target: ice-blue bg + faint stadium, not flat white). Light overlays
   are intentionally low-alpha (`stadiumOverlayColors` .12/.42, `heroOverlayColors`
   .22/.34/.58, `matchCardOverlayColors` .26/.52) so texture reads but navy text
   stays crisp. Dark mode keeps the night-stadium art.
   Admin/network marketing posters stay full opacity; only their stadium
   *fallback* asset uses `StadiumImage`.
   - **Translucent glass surfaces bleed too** (Series module, 2026-06-11): a
     `c.card.withValues(alpha: .4–.55)` surface used in BOTH themes is fine in
     dark (glassmorphism) but in light mode the semi-transparent white lets the
     dark backdrop/`bgAsset` show through → muddy grey cards. Rule: glass
     surfaces must be `c.isDark ? c.card.withValues(alpha: …) : c.card` (opaque
     white in light). Audit: `grep -rn "c.card.withValues" lib/screens`. Series
     widgets fixed: `PremiumGlassPanel`, `SeriesGlassTabBar`, category tab bar,
     `SeriesSkeleton`, `SeriesEmptyState`, `_SquadToggle`, `_StatusSummaryCard`,
     `_PlayerCard`, `_StatCard`, list filter chip + nav circle.
8. **Watch Live visibility** — show "Watch Live" ONLY when a playable stream
   exists (resolver: `CricketRepository.shouldShowWatchLiveForMatch` /
   `hasPlayableStreams`). When no stream, hide Watch Live entirely and let
   "View Match" expand full width — never a dimmed/disabled button. Implemented
   in Home `_HomeActionBar` and Matches `_DualActionBar` (hides segment +
   divider on `_WatchState.none`).
9. **Cyan glow is dark-mode only** (2026-06-11) — the premium light target uses
   ONE soft blue drop-shadow, no cyan halo. Light `cardShadow`/`heroShadow` are
   now single soft-blue (`#3f6ea5`) shadows. Any per-widget cyan-glow `BoxShadow`
   (active pills/segments, hero/list cards, "top highlight" neon strips,
   `TopCyanHighlight`/`MDTopGlow`, title text `shadows`) MUST be wrapped
   `if (c.isDark)` / `selected && c.isDark`, else it reads as the old
   dark-inspired look on white. Light falls back to plain `c.heroShadow`.
   **Gotcha:** `...c.heroShadow.skip(1)` now drops the ONLY light shadow (light
   heroShadow is a single element) — branch the whole `boxShadow`, don't `skip`.
   Stadium texture is a whisper in light (`stadiumImageOpacity .08`,
   `heroImageOpacity .18`); overlays are near-opaque white. Low-alpha cyan
   borders (≤.5) are kept — they ARE the spec's thin light-blue card edge.

## Build Commands
- `flutter pub get` — Install dependencies
- `flutter analyze` — Lint/type check
- `flutter build web --release` — Production build
- `flutter run -d chrome` — Dev server
