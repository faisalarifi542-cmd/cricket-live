# CricPro AI Project Index

Last updated: 2026-06-10
Purpose: Help Claude/Codex/new AI agents understand the repo with minimum token usage.

## Project Summary
CricPro is a premium cricket live score and live stream system:
- Flutter mobile app
- Node.js/Fastify backend API
- Next.js admin panel
- MySQL + Redis
- Cricbuzz/provider data
- Admin-managed home screen, streams, teams, logos, players, ads, notifications, API security

Production:
- API: `https://api.webcrichd.co`
- Admin: `https://app.webcrichd.co`
- PM2 apps: `cricket-api`, `admin-panel`

## Fast Navigation

### Backend root
`cricket-api/`

Important backend files:
- `src/server.js` — Fastify server, global hooks, CORS/security, route registration
- `src/db/migrate.js` — all idempotent DB migrations
- `src/routes/app.js` — app-specific public endpoints like `/app/home`
- `src/admin/index.js` — admin route registration and shared admin routes
- `src/admin/routes/homepage.routes.js` — home layout, featured matches/series admin APIs
- `src/admin/routes/extra.routes.js` — teams/players/other admin utilities if present
- `src/lib/team-logos.js` — team logo enrichment / admin-first logo resolver
- `src/lib/player-images.js` — player image enrichment / admin-first image resolver if implemented

Player image resolver (`src/lib/player-images.js`):
- `enrichPlayerImages(payload)` chained after `enrichTeamLogos` in the `server.js` preSerialization hook.
- Modes: `admin_first` (default), `cricbuzz_first`, `admin_only`, `cricbuzz_only`, `initials_only`.
- Global mode stored in `app_settings` key `player_image_mode`; per-player override via `players.image_mode` (active only when `is_image_active`).
- `resolvePlayerImage({ mode, adminImage, providerImage })` is the pure priority function (unit-tested in `src/lib/player-images.test.js`).
- Matches player-shaped nodes (has name + player id/image field, NO team short code) so team logos are never touched.

Common public endpoints:
- `GET /app/home`
- `GET /app/config`
- `GET /matches/live`
- `GET /matches/upcoming`
- `GET /matches/recent`
- `GET /match/:id`
- `GET /match/:id/scorecard`
- `GET /match/:id/commentary`
- `GET /match/:id/full-commentary`
- `GET /match/:id/squads`
- `GET /match/:id/streams`
- `GET /series`
- `GET /series/:id`
- `GET /series/:id/matches`
- `GET /series/:id/squads`
- `GET /player/:id`

Common admin endpoints:
- `/admin/home-config/*`
- `/admin/teams/*`
- `/admin/players/*`
- `/admin/streams/*`
- `/admin/api-security/*`
- `/admin/ads/*`
- `/admin/notifications/*`

Player admin endpoints (all in `src/admin/routes/extra.routes.js`, prefix `/admin`; do NOT also register in `src/admin/index.js`):
- `GET /admin/players` — list/search (returns image fields, `resolved_image_url`, `globalMode`)
- `GET /admin/players/:id`
- `POST /admin/players` — create
- `PUT /admin/players/:id` — update profile + image fields
- `DELETE /admin/players/:id` — hard delete (FKs are ON DELETE SET NULL)
- `POST /admin/players/upload-image` — base64 upload → `{ success, url, relativeUrl, bytes }`
- `PUT /admin/players/:id/image` — image-only update
- `DELETE /admin/players/:id/image` — remove admin image (keeps provider)
- `GET|PUT /admin/players/image-mode` — global mode (canonical)
- `GET|PUT /admin/player-image-settings` — spec-named alias of image-mode
- bulk: `POST /admin/players/refresh-images|apply-global-mode|clear-admin-images`

### Admin panel root
`admin-panel/`

Important admin files:
- `app/homepage/page.tsx` — Home screen admin configuration
- `app/teams/page.tsx` — Team logo management
- `app/players/page.tsx` — Player CRUD/image management
- `lib/api.ts` — frontend API client methods; must match backend routes
- `lib/constants.ts` — sidebar/navigation
- `lib/permissions.ts` — permission labels/RBAC mapping

Admin rules:
- If adding backend admin endpoint, update `admin-panel/lib/api.ts`.
- If build says method missing on `teamsApi`/`playersApi`, update `lib/api.ts`.
- Avoid Server Action deployment mismatch; prefer client-side API calls where possible.

### Flutter root
`lib/`

Important Flutter files:
- `main.dart` — app shell/bottom nav/scaffold
- `components.dart` — shared widgets; `TeamLogoWidget` and `PlayerAvatarWidget` live here
- `core/api/api_client.dart` — all API requests should pass here
- `core/api/api_config.dart` — API base URL/security headers
- `models/home_feed.dart` — Home response parsing
- `screens/home/home_screen.dart` — Home screen UI
- `screens/match_details/` — Match details tabs
- `screens/series/` — Series list/detail
- `screens/live_stream/` — Live Stream screen
- `screens/player/` — Player profile if present

Flutter logo/image rules:
- Team logo priority: Admin logo → Cricbuzz/provider logo → local rounded flag asset → initials
- Player image priority: Admin image → Cricbuzz/provider image → initials
- Use shared widgets, not raw scattered `Image.network`.
- Player photos: use `PlayerAvatarWidget` (in `components.dart`). `SeriesPlayerAvatar`, squad `_PlayerAvatar`, and `PlayerAvatar` all delegate to it. Backend pre-resolves the URL; widget only renders image or initials (never broken icon).
- Watch Live button: show only if playable stream exists; otherwise hide completely.

## Current Design System
- Dark navy background
- Cyan glow accents
- Rounded cards
- Stadium image backgrounds
- Broadcast-style cricket cards
- Bottom nav fixed, content must not scroll behind it

## Home Screen Rules
File: `lib/screens/home/home_screen.dart`

Rules:
- Top hero carousel uses `/assets/images/home/home_top_featured_card.png` if available.
- List match cards use `/assets/images/home/list_match_card_bg_live_clean.png` if available.
- Match score/team/status logic must not be changed unless requested.
- Watch Live only shows when stream exists.
- View Match always shows.
- If Watch Live hidden, View Match takes full action width.
- Featured Series image must come from admin panel and resolve to absolute URL from backend.
- Featured Matches should show around 1.25–1.4 cards on 360dp.

## Match Details Rules
Files: `lib/screens/match_details/*`

Rules:
- Same top score hero across tabs.
- Tab order: Info, Live, Scorecard, Squad, Commentary, Overs.
- Commentary must show real ball data only.
- Do not mark post-match/interview text as Dot Ball/Wicket unless data says so.
- Live tab target: compact dashboard grid on 360dp.

## Series Rules
Files: `lib/screens/series/*`

Rules:
- Series screen must match premium dark/cyan target.
- Series hero/top bar should be manageable from admin panel.
- If featured series has a series ID, tapping must open exact Series Detail screen, not generic Series tab.

## Database Tables to Know
- `featured_series`
- `featured_matches`
- `teams`
- `players` — image cols: `admin_image_url`, `provider_image_url`, `image_url`, `image_mode`, `is_image_active`, `image_updated_at`, `is_active`, `player_external_id`, `country`, `batting_style`, `bowling_style`
- `streams`
- `api_clients`
- `api_allowed_origins`
- `api_endpoint_rules`
- `api_blocklist`
- `api_request_logs`
- `app_settings` — incl. key `player_image_mode` (global player image mode)

Migration rules:
- Always idempotent.
- Add missing columns safely.
- Production schema may differ from local schema.
- Verify columns after migration if the feature depends on them.

## Common Bug History

### Duplicate `/admin/players` route
Cause: two admin route registrations for `GET /admin/players` (old simpleList in `src/admin/index.js` + richer list in `extra.routes.js`) → `FST_ERR_DUPLICATED_ROUTE` on boot → admin API down → "Failed to fetch".
Status: RESOLVED 2026-06-10 — removed the `index.js` simpleList line; richer list kept in `extra.routes.js`.
Fix rule: merge image/CRUD logic into the existing players route; do not register duplicates.

### `featured_series` missing columns
Cause: production schema differed (`external_id` vs `series_external_id`, missing `is_active`/`note`).
Fix rule: migration must add missing columns explicitly and verify schema.

### Admin failed to fetch after API Security enforce
Cause: CORS/API key/origin/rules or backend crash.
Fix rule: check PM2 backend logs first, then API security settings.

### Next.js Server Action mismatch
Cause: older/newer deployment cache mismatch.
Fix rule: rebuild/restart admin panel, avoid relying on unstable Server Actions for admin CRUD.

## Minimal Commands

Backend:
```bash
cd cricket-api
node src/db/migrate.js
node --check src/server.js
npm run lint
npm test
pm2 restart cricket-api --update-env
```

Admin:
```bash
cd admin-panel
npm run build
pm2 restart admin-panel --update-env
```

Flutter:
```bash
flutter analyze lib
flutter test
```

## Before Broad Search
Use targeted commands:
- Search route: `rg "admin/players|/admin/players|players" cricket-api/src/admin`
- Search API method: `rg "playersApi|teamsApi|homeApi" admin-panel/lib admin-panel/app`
- Search Home widget: `rg "FeaturedMatches|Watch Live|home_top_featured" lib/screens/home/home_screen.dart`
- Search logo/image usage: `rg "TeamLogoWidget|PlayerAvatar|Image.network" lib`

## Pending / Verify Often
- Player CRUD + image management: IMPLEMENTED end-to-end (admin UI + backend routes + Flutter widget). Still verify on live DB: run `node src/db/migrate.js`, then manual add→edit→upload→remove→delete→reload→app squad.
- Player images are admin-first globally (`player_image_mode`) with per-player override (`players.image_mode` + `is_image_active`).
- Home screen visual QA at 360dp after every polish.
- Admin panel build after any `lib/api.ts` or page change.
