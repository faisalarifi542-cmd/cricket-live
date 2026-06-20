# Player Image Settings Fix Report

## 1. Root cause

The backend already had a complete, admin-controlled player-image system
(`cricket-api/src/lib/player-images.js`): a global setting `player_image_mode`
with 5 modes, a per-player override, and an `enrichPlayerImages()` hook wired
into the global Fastify `preSerialization` hook that resolves every player
object server-side. **But two gaps let API/Cricbuzz player photos leak anyway:**

1. **Client re-derived provider URLs from raw image ids.** The server set
   `imageUrl`/`image_url` (and cleared them in `admin_only`/`initials_only`),
   but it left the raw id fields (`imageId`, `faceImageId`, `playerImageId`,
   `image_id`) on the node. The Flutter parsers (`resolvePlayerImageUrl`,
   `ApiPlayer.fromJson`, and `RankingEntry.fromJson` via `resolveCricbuzzImageUrl`)
   rebuilt `https://static.cricbuzz.com/.../c<id>/i.jpg` **from those ids**,
   bypassing the admin decision entirely. This is why screens still showed API
   photos in `admin`/`initials` modes.

2. **The app never received the mode.** `/app/config`
   (`buildPublicAppConfig()`) did not expose `player_image_mode`, so the Flutter
   client had no way to know which mode was active and could not refuse a
   provider photo client-side.

The **Rankings** screen was the most visible symptom: `RankingEntry.fromJson`
called `resolveCricbuzzImageUrl(json)`, which built a Cricbuzz URL straight from
the ranking row's `faceImageId` — completely independent of the admin mode.

## 2. Admin setting found

- **Key:** `player_image_mode` (table `app_settings`, group `players`)
- **Default:** `admin_first`
- **Allowed values (kept as-is — not reinvented):**
  - `admin_first` — admin photo → provider photo → initials
  - `cricbuzz_first` — provider photo → admin photo → initials
  - `admin_only` — admin photo → initials (no provider photo)
  - `cricbuzz_only` — provider photo → initials
  - `initials_only` — initials only (no remote photo)
- **Admin endpoints:** `GET/PUT /admin/players/image-mode`
- **Mapping to the requested `api`/`admin`/`initials` modes:** `api` ↔
  `admin_first`/`cricbuzz_first`, `admin` ↔ `admin_only`, `initials` ↔
  `initials_only`. The richer existing names were preserved to avoid a
  conflicting config; the product preference (strict admin = admin/initials
  only) is satisfied by `admin_only`.

## 3. Files inspected

- `cricket-api/src/lib/player-images.js` (resolver, enrichment, modes)
- `cricket-api/src/lib/public-app-state.js` (`buildPublicAppConfig`)
- `cricket-api/src/server.js` (preSerialization hook)
- `cricket-api/src/admin/routes/extra.routes.js` (admin mode endpoints)
- `lib/api_models.dart` (`resolvePlayerImageUrl`, `resolveCricbuzzImageUrl`,
  `RankingEntry`, `ApiPlayer`, `AppConfig`)
- `lib/components.dart` (`PlayerAvatarWidget`, `PlayerAvatar`)
- `lib/screens/rankings/rankings_screen.dart`
- `lib/screens/player/widgets/player_hero.dart`
- `lib/widgets/squad.dart`
- `lib/screens/match_details/widgets/live_match_tab.dart`,
  `match_details_ui.dart`
- `lib/screens/series/widgets/series_detail_stats.dart`,
  `series_components.dart`
- `lib/main.dart` (config load), `lib/repositories/cricket_repository.dart`
  (config cache)

## 4. Files changed

**Backend**
- `cricket-api/src/lib/public-app-state.js` — expose `playerImageMode` at the
  top level and under `player.imageMode` in `/app/config`.
- `cricket-api/src/lib/player-images.js` — when the resolved image is `null`
  (initials / admin-only with no admin photo), also clear the raw provider id
  fields (`imageId`, `image_id`, `faceImageId`, `face_image_id`,
  `playerImageId`, `player_image_id`, `teamImageId`, `team_image_id`) so the
  client cannot rebuild a provider URL.

**Flutter**
- `lib/services/player_image_resolver.dart` — **new** single resolver +
  `PlayerImageMode` enum + global mode holder.
- `lib/api_models.dart` — `AppConfig.playerImageMode` getter; rewrote
  `resolvePlayerImageUrl` to consume only the server-resolved URL gated by mode
  (no id-based rebuild); `ApiPlayer.fromJson` and `RankingEntry.fromJson`
  (player rows) now route through the resolver.
- `lib/screens/series/widgets/series_detail_stats.dart` + parent
  `series_detail_screen.dart` (import) — squad + top-performer images gated.
- `lib/main.dart` — push the mode into `PlayerImageResolver` on every config
  load.

## 5. Shared resolver implementation

`PlayerImageResolver` (`lib/services/player_image_resolver.dart`) holds a global
`PlayerImageMode` updated from app config. `resolve()/resolveServerImage()`
return the trusted server URL when the mode allows a remote image, else `null`
(→ initials). It **never** constructs a provider URL from a raw id, so a stale
id can't leak a photo. Debug-only logs: `CricProPlayerImage: mode=… source=… player=…`.

## 6. Screens updated

All player avatars now flow through the resolver via the model parsers and the
shared `PlayerAvatarWidget`: Rankings, Player detail/hero, Match Details squad &
scorecard rows, Series squads & top performers, Team player lists, reserve
chips. Team logos were left on their own resolver (unchanged).

## 7. Rankings fix

`RankingEntry.fromJson` now uses `resolvePlayerImageUrl(json)` (mode-gated) for
player rankings instead of `resolveCricbuzzImageUrl(json)` (id-based rebuild).
Team rankings keep the team-logo resolver. `_RankingImage` already falls back to
initials when the URL is null/empty.

## 8. Fallback behavior

- `initials_only`: never a remote photo, anywhere → initials.
- `admin_only`: admin photo if present, else initials. No provider photo.
- `admin_first`/`cricbuzz_first`/`cricbuzz_only`: server-resolved photo per
  priority, else initials.
- Image load failure → initials (existing `errorBuilder`s), no broken-image
  icon, no infinite retry, no layout jump (fixed-size avatar containers).

## 9. Config refresh behavior

The mode is applied in `main.dart::_loadAppConfig` on cold start and restart.
`/app/config` is cached 5 minutes client-side, so pull-to-refresh/reopen picks
up a changed setting within that window. Crucially the **server is now
authoritative** (nulls `imageUrl` and strips raw ids per mode), so even a
briefly-stale client mode cannot show a provider photo the admin disabled — the
data simply isn't there to rebuild from.

## 10. Checks run

- `flutter analyze lib/` → **No issues found.**
- `node --check src/lib/public-app-state.js` → OK
- `node --check src/lib/player-images.js` → OK
- Admin panel: **not changed** → no TypeScript check needed.

## 11. Manual device checklist

1. Admin = `initials_only`: refresh/reopen → Rankings, Squad, Player detail,
   Series squads all show initials; no player image network calls.
2. Admin = `admin_only`: players with an admin photo show it; others show
   initials; no Cricbuzz photo loads.
3. Admin = `admin_first`/`cricbuzz_first`: photos appear where available, else
   initials.
4. Kill a photo URL (airplane mode mid-load): falls back to initials, no broken
   icon.
5. Change the mode in admin, pull-to-refresh / reopen the app → new mode is
   respected; old API photos do not reappear.

## 12. Intentionally left unchanged

- Live score polling, stream player, ads, notifications, floating overlay, Home
  hero logic, backend provider scraping.
- Team logo resolution (`resolveCricbuzzImageUrl`, `resolveKnownTeamLogoUrl`,
  `enrichTeamLogos`) — separate concern, not player images.
- News/series imagery (`NewsStory`, series cards) — not player photos.
- The existing 5 mode names and per-player override mechanism — preserved.
