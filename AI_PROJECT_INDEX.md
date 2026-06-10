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
| `lib/components.dart` | Shared widgets: PremiumCard, GradientButton, BottomNav, TeamLogoWidget, PlayerAvatarWidget, PillChip, StatusBadge |
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
2. **Image overlays**: Use `c.heroOverlayColors` / `c.matchCardOverlayColors` — white-based in light, dark-based in dark
3. **Text on images**: Use `c.onImageText` — navy in light mode, white in dark mode
4. **Shadows**: Use `c.cardShadow` or `c.heroShadow` — blue-tinted in light, black in dark
5. **Image priority**: Admin uploaded → Provider (Cricbuzz) → Initials fallback
6. **Live player/video screens**: Keep dark overlays (intentional for video readability)

## Build Commands
- `flutter pub get` — Install dependencies
- `flutter analyze` — Lint/type check
- `flutter build web --release` — Production build
- `flutter run -d chrome` — Dev server
