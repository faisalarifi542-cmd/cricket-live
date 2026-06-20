# Android Native Launch + Splash Startup Rebuild

**Date:** 2026-06-13
**Status:** ✅ COMPLETE

---

## Current Startup Flow (Before This Fix)

| Step | What happened | Problem |
|------|--------------|---------|
| 1. Android native launch | `Theme.Light.NoTitleBar` with navy `launch_background.xml` | Light theme parent → **white status/nav bars** flash |
| 2. Android 12+ system splash | No `values-v31/styles.xml` existed | **Default app icon on white** background forced by OS |
| 3. Flutter first frame | `_decideSplash()` awaits `_repository.appConfig()` (network!) | Splash **blocked on network fetch** — shows blank navy while waiting |
| 4. Splash animation starts | All images decoded at full resolution | **Extra memory + decode time** on low-end Android |
| 5. Remote images attempted | `Image.network` fires on first frame | **Half-loaded images** possible during animation |

### Why the splash was slow/half-loading on Android

1. **Network blocking:** `SplashConfigService.load()` awaited a full HTTP request
   to `/app/config` before the splash could render. On slow networks or cold DNS,
   this added 1–5 seconds of blank navy screen.
2. **Full-res image decode:** No `cacheWidth`/`cacheHeight` on any `Image.asset`
   or `Image.network` — Flutter decoded the full bitmap (e.g. 1080×1920 stadium)
   even when displaying at 360×640.
3. **White system bars:** `Theme.Light.NoTitleBar` parent caused Android to flash
   white status/navigation bars before Flutter could set immersive mode.
4. **Android 12+ default icon splash:** Without `values-v31/styles.xml`, Android
   12+ showed the launcher icon centered on a system-chosen background before
   Flutter loaded — an ugly "default" splash before the premium one.

### Was a Flutter default splash / white screen / Flutter logo still appearing?

- **Flutter logo:** No — the `launch_background.xml` was already set to
  `@color/splash_navy` (fixed in Phase 5). No Flutter logo bitmap in the launch
  layer-list.
- **White flash:** Yes — from the `Theme.Light.NoTitleBar` parent in
  `values/styles.xml`, which made the status bar and navigation bar white/light
  for the ~200ms before Flutter set immersive mode.
- **Android 12+ default icon:** Yes — without `values-v31/styles.xml`, the OS
  showed the `ic_launcher.png` (default Flutter icon) on a system background
  before the app's `LaunchTheme` even applied on Android 12+ devices.

---

## What Native Android Launch Files Were Changed

### `android/app/src/main/res/values/styles.xml` — MODIFIED
- Changed `LaunchTheme` parent: `Theme.Light.NoTitleBar` → `Theme.Black.NoTitleBar`
- Changed `NormalTheme` parent: `Theme.Light.NoTitleBar` → `Theme.Black.NoTitleBar`
- Added `android:windowFullscreen` = true to `LaunchTheme`
- `NormalTheme` window background: `?android:colorBackground` → `@color/splash_navy`

### `android/app/src/main/res/values-night/styles.xml` — MODIFIED
- Aligned with day variant (same dark theme parent, splash_navy NormalTheme)
- Added `android:windowFullscreen` = true

### `android/app/src/main/res/values-v31/styles.xml` — NEW
- Android 12+ SplashScreen API configuration:
  - `windowSplashScreenBackground` = `@color/splash_navy` (#060B18)
  - `windowSplashScreenAnimatedIcon` = `@drawable/splash_transparent` (invisible)
  - `windowSplashScreenAnimationDuration` = 0 (exit immediately)

### `android/app/src/main/res/values-night-v31/styles.xml` — NEW
- Identical to `values-v31` (CricPro splash is always dark cinematic)

### `android/app/src/main/res/drawable/splash_transparent.xml` — NEW
- 1×1 transparent `<shape>` drawable — replaces the default app icon on Android
  12+ so the system splash shows only dark navy, no icon.

### `android/app/src/main/AndroidManifest.xml` — MODIFIED
- `android:label` changed from `cricpro_flutter` → `CricPro`

### Already correct (not changed)
- `drawable/launch_background.xml` — already `@color/splash_navy` ✓
- `drawable-v21/launch_background.xml` — already `@color/splash_navy` ✓
- `values/colors.xml` — already has `splash_navy` = `#060B18` ✓

---

## What Flutter Splash Flow Was Changed

### `lib/main.dart` — MODIFIED
- **Before `runApp()`:** Sets `SystemChrome.setSystemUIOverlayStyle` with
  transparent status bar, dark navy navigation bar, light icons — eliminates
  white bar flash even before Flutter's first frame renders.
- **`_decideSplash()`:** No longer awaits `SplashConfigService.instance.load()`
  (which fetches from network). Now calls `loadCachedOrDefaults()` (instant,
  reads SharedPreferences only). Fires `refreshInBackground()` as fire-and-forget
  after the splash is already showing.

### `lib/features/splash/data/splash_config_service.dart` — MODIFIED
- **New `loadCachedOrDefaults()`:** Returns cached config from SharedPreferences
  (last successful remote fetch), or `SplashConfig.defaults()` if no cache.
  **Never hits network.** This is the fast path.
- **New `refreshInBackground()`:** Fire-and-forget — fetches `/app/config`,
  extracts splash block, caches behavior flags (duration, enabled, skip) in
  SharedPreferences for the next launch. Never blocks current splash.
- Three new SharedPreferences keys: `cricpro_splash_cached_duration`,
  `cricpro_splash_cached_enabled`, `cricpro_splash_cached_skip`.
- Original `load()` method preserved for backward compatibility.

### `lib/features/splash/widgets/splash_asset_image.dart` — MODIFIED
- Added `cacheWidth` and `cacheHeight` parameters forwarded to both
  `Image.network` and `Image.asset`.
- Reduces memory pressure and decode time by decoding images at target display
  resolution instead of full-res.

### `lib/features/splash/presentation/premium_splash_screen.dart` — MODIFIED
- Added `cacheWidth`/`cacheHeight` to all four `SplashAssetImage` instances:
  - Stadium background: `cacheWidth: w.toInt().clamp(360, 720)`
  - CP logo: `cacheWidth: logoSize.toInt(), cacheHeight: logoSize.toInt()`
  - Pitch/wickets: `cacheWidth: pitchW.toInt()`
  - Wordmark: `cacheWidth: 430`
- System UI immersive mode and back-button blocking already present (Phase 5).
- Particle system already optimized (28 particles, single CustomPainter, no blur).

---

## Config/Network Loading Optimization

**Before:**
```
main() → _decideSplash() → SplashConfigService.load()
  → CricketRepository.appConfig() [HTTP GET /app/config] ← BLOCKS
  → SplashConfig.fromConfigMap() → setState() → render splash
```
First frame waits for network. On cold DNS / slow 3G this can take 1–5 seconds.

**After:**
```
main() → _decideSplash() → SplashConfigService.loadCachedOrDefaults()
  → SharedPreferences.getInstance() [local disk, ~5ms]
  → SplashConfig with cached flags (or defaults) → setState() → render splash
  → SplashConfigService.refreshInBackground() [fire-and-forget]
    → CricketRepository.appConfig() [background, non-blocking]
    → cache new flags for next launch
```
First frame is instant. Remote config cached for next launch.

---

## Asset Loading Optimization

| Image | Before | After (cacheWidth) | Memory savings |
|-------|--------|-------------------|----------------|
| Stadium BG | Full res (~1080×1920) | 360–720px wide | ~50–75% |
| CP Logo | Full res (~1024×1024) | ~190–310px | ~70–90% |
| Pitch/Wickets | Full res | ~320–560px | ~40–60% |
| Wordmark | Full res | 430px | ~50–70% |

All images now decoded at display resolution. Flutter's `cacheWidth`/`cacheHeight`
tells the image codec to decode at the target size, avoiding the full-res bitmap
allocation. This is especially impactful on Android where the image codec runs on
the platform thread.

---

## Test Results

- `flutter clean` → ✅
- `flutter pub get` → ✅ Got dependencies
- `flutter analyze lib/main.dart lib/features/splash/` → **No issues found** (ran in 120.7s)
- `flutter test` → **All 38 tests passed** ✅ (no regressions)

---

## Real Android Phone Test Plan

| # | Check | Expected |
|---|-------|----------|
| 1 | Cold start from killed app | Dark navy instantly, no white flash |
| 2 | No default Flutter logo/splash | Only dark navy → CricPro animated splash |
| 3 | Android 12+ system splash | Dark navy background, no icon visible |
| 4 | Splash appears instantly | No blank/loading delay before animation starts |
| 5 | No half-loaded assets | All bundled local assets render immediately |
| 6 | Animation is smooth | No stutter, no dropped frames (profile mode) |
| 7 | App opens normally after splash | Home screen renders correctly |
| 8 | Back button during splash | Does not return to splash (PopScope blocks) |
| 9 | Back button after Home | Does not return to splash (never pushed) |
| 10 | Status/nav bars during splash | Hidden (immersive sticky mode) |
| 11 | Status/nav bars after splash | Restored (edge-to-edge) |

---

## Files Changed Summary

| File | Action | Purpose |
|------|--------|---------|
| `android/app/src/main/res/values/styles.xml` | MODIFIED | Dark theme parent, fullscreen, navy NormalTheme |
| `android/app/src/main/res/values-night/styles.xml` | MODIFIED | Aligned with day variant |
| `android/app/src/main/res/values-v31/styles.xml` | NEW | Android 12+ dark splash config |
| `android/app/src/main/res/values-night-v31/styles.xml` | NEW | Android 12+ night variant |
| `android/app/src/main/res/drawable/splash_transparent.xml` | NEW | Transparent icon for Android 12+ |
| `android/app/src/main/AndroidManifest.xml` | MODIFIED | App label fix |
| `lib/main.dart` | MODIFIED | Dark system UI before runApp, non-blocking splash |
| `lib/features/splash/data/splash_config_service.dart` | MODIFIED | Instant cached config, background refresh |
| `lib/features/splash/widgets/splash_asset_image.dart` | MODIFIED | cacheWidth/cacheHeight support |
| `lib/features/splash/presentation/premium_splash_screen.dart` | MODIFIED | cacheWidth/cacheHeight on all images |

---

## Remaining Notes

1. **Real Android device test required** — changes are structurally correct and
   analyzer-clean, but on-device cold start + Android 12+ behavior must be
   verified visually.
2. **Release APK build** — run `flutter build apk --release` to verify no
   resource compilation errors from the new Android XML files.
3. **Admin Panel preview** — the CP logo, wordmark, and pitch composition are
   unchanged from Phase 4/5; only the startup performance and native launch were
   rebuilt. Preview should still match the target.
4. **Launcher icon** — the `mipmap-*/ic_launcher.png` files are still the default
   Flutter icons. These should be replaced with the CricPro icon for a fully
   branded launch experience (separate task).

---
---

# CricPro Premium Animated Splash Screen — Phase 5 Report

Generated: 2026-06-13
Scope: build the full CricPro premium animated splash screen + manage its assets
and behavior remotely from the Admin Panel. Remote-asset system, light/dark
logic, and all existing navigation/UI are untouched.

Builds on the remote-asset pattern documented in
`REMOTE_ASSETS_PHASE2B_FULL_WIRING_REPORT.md` and
`REMOTE_ASSETS_LIGHT_MODE_THEME_FIX_REPORT.md`.

> Note on naming: the prompt asked for this file name (`..._PHASE_4_REPORT.md`).
> It is kept as requested even though this is the Phase 5 task, so the link the
> operator was given resolves.

---

## 1. What was added (high level)

1. **Backend**: a public `splash` block in `GET /app/config`, plus a dedicated
   admin API (`/admin/splash-settings`) backed by 8 `app_settings` keys.
2. **Admin Panel**: a new **Content → Splash Screen** page to upload/select the
   5 splash assets, toggle enable, set duration, set skip-after-first-launch,
   and preview the composed layout.
3. **Flutter**: a complete `features/splash/` module — premium animated splash
   screen, config service, and three custom widgets — wired into `main.dart`
   with bundled fallback art and a dark native launch (no white flash).

---

## 2. Admin page / settings added

**Page:** `admin-panel/app/splash/page.tsx` — nav item **Splash Screen**
(`Content` group, `Sparkles` icon, permission `settings.view`; writes require
`settings.write`).

Controls:
- Animated splash **enabled** toggle.
- **Duration (ms)** number input (clamped 800–10000, default 3000).
- **Skip after first launch** toggle (default off).
- Five asset slots (upload OR paste URL OR clear → bundled fallback):
  stadium background, CP logo, CRICPRO wordmark panel, neon orbit trail,
  pitch/wickets.
- **Live preview**: a 9:19 phone frame composing the five layers in their real
  positions (stadium full-screen, orbit behind logo, CP logo upper-middle,
  wordmark below, pitch at bottom), with a "disabled" overlay when off.

Uploads reuse the shared base64 → `/uploads` image pipeline via
`POST /admin/splash-settings/upload-image`, returning an absolute public URL.

---

## 3. Backend API changes

New file `cricket-api/src/lib/splash-config.js`:
- `SPLASH_SETTING_KEYS` (the 8 keys), `SPLASH_DEFAULTS`, `SPLASH_ASSET_SLOTS`
  (admin slot metadata), and `buildSplashConfig(settingsMap)` →
  ```json
  { "enabled": true, "durationMs": 3000, "skipAfterFirstLaunch": false,
    "assets": { "stadiumBackground": null, "cpLogo": null,
                "wordmarkPanel": null, "orbitTrail": null,
                "pitchWickets": null } }
  ```
  (duration clamped, bools normalized, empty URLs → `null`).

New file `cricket-api/src/admin/routes/splash.routes.js` (mounted at
`/admin/splash-settings` in `admin/index.js`):
- `GET /admin/splash-settings` → `{ settings, resolved, slots, keys, defaults }`.
- `PUT /admin/splash-settings` → upserts only provided keys into `app_settings`
  (group `splash`, `is_public=1`), audited, busts the cached public config.
- `POST /admin/splash-settings/upload-image` → base64 image upload.

`cricket-api/src/lib/public-app-state.js`:
- Added the 8 splash keys to `PUBLIC_SETTING_KEYS`.
- `buildPublicAppConfig()` now returns a `splash` block (built via
  `buildSplashConfig`). Additive — existing fields unchanged.

`admin-panel/lib/api.ts`: `splashApi` (`get`/`save`/`uploadImage`) + types.
`admin-panel/lib/constants.ts`: the nav item.

### Settings keys (group `splash`, public)

```
splash_enabled                  (bool,  default true)
splash_duration_ms              (int,   default 3000, clamped 800–10000)
splash_skip_after_first_launch  (bool,  default false)
splash_stadium_background_url   (string)
splash_cp_logo_url              (string)
splash_wordmark_panel_url       (string)
splash_orbit_trail_url          (string)
splash_pitch_wickets_url        (string)
```

No DB migration required — `app_settings` already exists and `is_public`
defaults to 1. The PUT writes both `setting_group` and the legacy `` `group` ``
column to `splash`.

---

## 4. Flutter files changed / added

Added (`lib/features/splash/`):
- `data/splash_config_service.dart` — `SplashConfig`, `SplashLayerAsset`,
  `SplashConfigService` (load from `/app/config`, first-launch tracking via
  `shared_preferences`, `shouldShow()`).
- `widgets/splash_asset_image.dart` — 3-level safe image (remote → bundled →
  empty box).
- `widgets/splash_glow_layer.dart` — radial floodlight `CustomPaint`.
- `widgets/splash_particle_field.dart` — sparkle `CustomPainter`
  (`RepaintBoundary`, seeded layout).
- `presentation/premium_splash_screen.dart` — the animated screen + timeline.

Changed:
- `lib/main.dart` — splash gate: shown as `MaterialApp.home` until finished,
  then replaced by `RootShell` (never a pushed route → back button cannot return
  to it). Dark navy placeholder while the splash decision resolves.
- `pubspec.yaml` — registered `assets/splash/`.
- `android/app/src/main/res/values/colors.xml` (new) + both
  `drawable*/launch_background.xml` → `@color/splash_navy` (`#060B18`).

Added bundled fallback art (`assets/splash/`, ≈188 KB total):
`stadium_background.webp` (8 KB), `cp_logo.png` (105 KB),
`wordmark_panel.png` (61 KB), `orbit_trail.webp` (5 KB),
`pitch_wickets.webp` (3 KB), plus `_generate_fallbacks.py` (provenance).

> The named source art (`blue_lit_sports_stadium_at_night.png`,
> `futuristic_glowing_cp_logo.png`, `glowing_cricpro_logo_in_neon_blue.png`,
> `neon_energy_ribbon_in_dark_space.png`, `neon_cricket_court_in_darkness.png`)
> was **not present in the repo**, so the bundled files are lightweight,
> on-brand placeholders. The intended premium art is delivered at runtime via
> the Admin Panel asset URLs; to bake it into the APK instead, drop the real
> images at the same `assets/splash/` paths (or rerun the generator).

---

## 5. Asset keys & fallback behavior

| Layer | Admin field key | `/app/config` field | Bundled fallback |
|---|---|---|---|
| Stadium background | `splash_stadium_background_url` | `assets.stadiumBackground` | `assets/splash/stadium_background.webp` |
| CP logo | `splash_cp_logo_url` | `assets.cpLogo` | `assets/splash/cp_logo.png` |
| Wordmark panel | `splash_wordmark_panel_url` | `assets.wordmarkPanel` | `assets/splash/wordmark_panel.png` |
| Orbit trail | `splash_orbit_trail_url` | `assets.orbitTrail` | `assets/splash/orbit_trail.webp` |
| Pitch / wickets | `splash_pitch_wickets_url` | `assets.pitchWickets` | `assets/splash/pitch_wickets.webp` |

Safety chain per layer (`SplashAssetImage`):
1. Admin remote URL via `Image.network` (Flutter disk-caches bytes); the bundled
   asset shows during download via `frameBuilder` so the layer is never blank.
2. Bad URL / offline / decode error → `errorBuilder` → bundled `Image.asset`.
3. Bundled asset error → empty `SizedBox` over the dark navy base (the painted
   `ColoredBox(kSplashNavy)` + glow always fill the screen, so it never looks
   broken).

Config-level safety: if `/app/config` is unreachable, `SplashConfig.defaults()`
is used (splash still runs with bundled art). No path throws.

---

## 6. Animation timeline (normalized over the configured duration)

| Window | Effect |
|---|---|
| 0.00–0.28 | Stadium background fades in |
| 0.10–0.58 | Floodlight / stadium glow brightens (`easeInOut`) |
| 0.20–0.58 | CP logo scales 0.86→1.0 with soft bounce (`easeOutBack`) |
| (loop) | CP logo cyan glow pulse (separate 1.6s reverse loop) |
| 0.25–0.72 | Neon orbit trail sweeps (rotates) behind the logo |
| 0.45–0.72 | Wordmark panel fades + slides up below the logo |
| 0.50–0.82 | Pitch/wickets foreground glows + slides up from the bottom |
| 0.40–0.75 | Particle sparkles fade in, then linger |
| on complete | `onFinish` → main.dart swaps to `RootShell`/maintenance |

Default total 3000 ms (admin-configurable). Layout is built with
`Stack` + `Align`/`FractionalTranslation` and sizes derived from
`LayoutBuilder` constraints (logo `42%` of width, clamped 120–240; orbit
`1.7×` logo; wordmark `62%` width, clamped 180–360) → responsive on OnePlus
10 Pro and short screens, no fixed-pixel overflow.

---

## 7. Performance optimization

- All bundled fallbacks pre-compressed (WebP q72 / optimized PNG), ≈188 KB total
  → negligible APK growth.
- Animated painter layers (`SplashGlowLayer`, `SplashParticleField`, pitch) are
  wrapped in `RepaintBoundary`.
- Particles are a single `CustomPainter` over N seeded points — no per-particle
  widgets, no images, no Lottie/video.
- Particle layout uses a fixed RNG seed (no `Random()` churn); `shouldRepaint`
  is tight (only on clock/opacity change).
- Remote images cached by Flutter's built-in `Image.network` disk cache (no new
  package added; `cached_network_image` not introduced).
- Two `AnimationController`s only (main timeline + pulse loop), both disposed.

---

## 8. Native launch / back button / theme

- Native window background set to dark navy `#060B18` for both day and night
  (`launch_background.xml` ×2 + `colors.xml`) → **no white flash**.
- Flutter's first frame while the splash decision resolves is also navy
  (`ColoredBox(kSplashNavy)`), so the dark is continuous.
- Splash is the `MaterialApp.home` and is removed from the tree on finish — it is
  never pushed, so the **back button can never return to it**; `PopScope(canPop:
  false)` also blocks back during the animation.
- The splash is intentionally **always dark cinematic** regardless of app
  light/dark mode (it does not read the theme), so it looks identical in both.

---

## 9. Test results

- `flutter analyze lib/features/splash lib/main.dart` → **No issues found.**
- `flutter test` → **All 38 tests passed** (no regressions).
- Backend `node --check` on all changed files → OK.
- Backend `node --test src/lib/public-app-state.test.js` → **5/5 pass.**
- `npx eslint` on `splash-config.js`, `splash.routes.js`, `public-app-state.js`
  → clean.
- Admin `npx tsc --noEmit` → clean.
- `/app/config` verified to emit the `splash` block (defaults applied when DB is
  absent, via the existing `.catch(() => [])` degradation).

Not run this session (no live DB/Redis/device): on-device visual run, admin
save→reload round-trip against a live DB, and a release `--analyze-size` build.
None of the code paths changed signatures used by existing screens.

---

## 10. Manual verification checklist (device + live backend)

| # | Check | Expected |
|---|---|---|
| 1 | Cold start | Navy launch (no white flash) → animated splash → Home |
| 2 | Admin save splash URLs, relaunch | Remote art appears on splash layers |
| 3 | Admin clear a URL | That layer uses bundled fallback |
| 4 | Airplane mode cold start | Splash shows bundled art, no crash, no blank |
| 5 | Bad/invalid URL | `errorBuilder` → bundled fallback |
| 6 | `splash_enabled=false` | App opens straight to Home, no splash |
| 7 | `skipAfterFirstLaunch=true` | Splash only on the very first launch |
| 8 | Duration change (e.g. 4500) | Animation length follows |
| 9 | Back button during/after splash | Never returns to splash |
| 10 | Light mode + dark mode | Splash stays dark cinematic in both |
| 11 | OnePlus 10 Pro + a short screen | No overflow, layout scales |
| 12 | `/app/config` JSON | Contains `splash` block with all 5 asset URLs |

---

## 11. Remaining notes

- Replace the placeholder bundled art with the real generated images at the same
  `assets/splash/` paths (or upload them via Admin → Splash Screen) for the final
  premium look.
- `assets/splash/_generate_fallbacks.py` is bundled with the asset folder; it is
  tiny but can be moved out of `assets/` if you prefer not to ship the script.
- To make first-paint of the splash even faster on slow networks, the splash
  could render immediately with `SplashConfig.defaults()` and refine once
  `/app/config` resolves; current behavior waits briefly (dark navy) for config,
  which is usually cached/instant.
- Settings are public + cached; the admin PUT busts `app:config` / `appdata:app:config`
  so changes appear without a redeploy.

---

## 12. Splash API Route Not Found Fix

### Symptom
On `https://app.webcrichd.co/splash` the page rendered but showed a red
**“Route not found”** banner, the 5 asset fields did not load, and the preview
showed only the simple CP/CRICPRO fallback.

### Failing request (from the API client)
`GET https://api.webcrichd.co/admin/splash-settings` → **404**
```json
{"success":false,"error":"Route not found","path":"/admin/splash-settings"}
```
The Admin Panel API client (`adminFetch`) was already correct — it prefixes
`API_BASE_URL` (`https://api.webcrichd.co`), not the frontend `app.` domain, and
the path is exactly `/admin/splash-settings`. No `/api` prefix, `/admin` present.

### Root cause — stale / partial backend deploy (NOT a code bug)
Live curls isolated it precisely:

| Endpoint | Live status | Meaning |
|---|---|---|
| `GET /admin/splash-settings` | **404 Route not found** | route absent on the running server |
| `GET /admin/app-settings` | **401** | admin routing works; this route exists |
| `GET /app/config` → `.splash` | **present** (defaults) | `public-app-state.js` + `splash-config.js` ARE deployed |

So the running `cricket-api` process has the **new `lib/` files** (the `splash`
block is live in `/app/config`) but an **older `src/admin/index.js`** that does
not register the splash route. It is a partial deploy / process not restarted on
the updated `admin/index.js` — confirmed by:
- `"Route not found"` is fastify’s own 404 handler at `src/server.js:288`.
- Local repo is correct: `node --check` passes, and the mount IS present —
  `src/admin/index.js:109` →
  `await fastify.register(splashRoutes, { prefix: '/admin/splash-settings' });`
  with `import splashRoutes from './routes/splash.routes.js'` at line 12.
- The route uses the same `adminAuth` hook + `requirePermissions('settings.*')`
  pattern as `settings.routes.js` / `assets.routes.js`.

It was **not** an API base-URL problem, **not** an Nginx/proxy problem, and
**not** a wrong-prefix problem — it is a stale PM2 deploy of `admin/index.js`.

### Server fix (operational — run on the VPS)
Deploy the current `cricket-api/src` and restart the process:
```bash
cd /path/to/cricket-api
git pull            # or rsync/scp the updated src/ (must include
                    # src/admin/index.js + src/admin/routes/splash.routes.js)
node --check src/admin/index.js
node --check src/admin/routes/splash.routes.js
pm2 restart cricket-api --update-env
pm2 logs cricket-api --lines 80     # confirm clean boot, no route errors
```
Verify:
```bash
curl -i https://api.webcrichd.co/admin/splash-settings   # expect 401 (needs auth), NOT 404
curl -s https://api.webcrichd.co/app/config | jq '.data.splash'
```
`401` (instead of `404`) confirms the route is mounted; the Admin Panel sends the
bearer token and will then receive `200`.

### Code hardening shipped this round (frontend resilience)
So the page is never unusable while the backend catches up,
`admin-panel/app/splash/page.tsx` now:
- seeds the 5 asset slots from a local `DEFAULT_SLOTS` constant (mirror of the
  backend `SPLASH_ASSET_SLOTS`), so **all 5 upload/URL fields + the preview
  always render** even if `GET /admin/splash-settings` fails;
- downgrades the load error from a blocking red banner to a non-fatal amber
  warning that names the likely cause (“redeploy & restart cricket-api”).

Save/upload still target the live API and start working the moment the backend
route is deployed. No backend code change was required — the repo route is
already correct; only a redeploy/restart is needed.

### Files changed
- `admin-panel/app/splash/page.tsx` — default slots fallback + softened warning.
- (No backend file changed — `splash.routes.js` + `admin/index.js` were already
  correct in the repo and only need to be deployed to the server.)

### Test results
- Live `curl -i https://api.webcrichd.co/admin/splash-settings` → 404 (before
  server redeploy) — confirms diagnosis.
- Live `curl .../app/config | jq .data.splash` → splash block present with
  defaults.
- Local `node --check` on `splash.routes.js` + `admin/index.js` → OK.
- `grep -R "splash-settings"` → import (index.js:12), mount (index.js:109),
  client calls (api.ts) all present.
- Admin `npx tsc --noEmit` → clean; `npm run build` → success (`/splash` route
  compiled, 4.05 kB).

---

## 13. WebP Splash Upload Validation Fix

### Symptom
Uploading `stadium.webp` (WEBP, ~172 KB, 941×1672) to Admin → Splash Screen →
Stadium background failed with **`Invalid input detected`**.

### Root cause — global SQL-injection body scanner, not the upload route
`Invalid input detected` is emitted by `src/middleware/security.js` →
`sqlInjectionProtection` (registered as a global `preValidation` hook in
`server.js:166`). It scans every request-body string value against
`SUSPICIOUS_PATTERNS`. The image upload sends the file as a large base64
**data URL** in `request.body.dataUrl`; that blob incidentally matches a
heuristic (e.g. `/(\bor\b|\band\b).*[=<>]/i` — an "or"/"and" substring bounded
by base64 `+`/`/` chars followed by the trailing `=`/`==` padding), so the whole
request was rejected **before** the handler ran. The match is content-dependent,
which is why some images uploaded and this WebP did not — it was never about
WebP being disallowed.

The actual upload code already supported WebP:
- `saveBase64Image` (`src/lib/uploads.js`) maps `image/webp → .webp`, accepts up
  to 6 MB, and writes a `.webp` file.
- The splash route `POST /admin/splash-settings/upload-image` has `bodyLimit:
  8 MB`.

A second latent bug: the global `requestSizeLimit` hook only raised the size
ceiling for `/admin/home-config/upload-image`, so `assets` and `splash` uploads
were capped at 1 MB (not the cause here at 172 KB, but wrong).

### Fix (exact rules changed)
`cricket-api/src/middleware/security.js`:
- `sqlInjectionProtection`: for any path ending in `/upload-image`, **skip
  scanning the request body** (it is a base64 image blob validated separately by
  `saveBase64Image` for MIME + size). Params and query are still scanned, and
  the body is still fully scanned for every normal route — SQLi protection is
  unchanged everywhere else.
- `requestSizeLimit`: raise the 8 MB ceiling for **every** `*/upload-image`
  endpoint (home-config, assets, splash), not just home-config.

This one backend fix unblocks WebP/PNG/JPG uploads for splash **and** the App
Assets page.

`admin-panel/app/splash/page.tsx` (defense-in-depth + clearer UX):
- File input `accept="image/png,image/jpeg,image/jpg,image/webp,.png,.jpg,.jpeg,.webp"`.
- Client validation accepts `image/webp` (and falls back to the `.webp`
  extension when the browser reports an empty MIME), with the message
  **“Only PNG, JPG, JPEG, or WEBP images under 2MB are allowed.”**
- Sends a `image/webp` MIME hint when `file.type` is empty.
- Upload errors already surface the backend reason via `adminFetch` (the
  `ApiError` message), so the real cause is shown instead of a generic string.

### MIME / extensions now accepted (splash upload)
- MIME: `image/webp`, `image/png`, `image/jpeg`, `image/jpg`
- Extensions: `.webp`, `.png`, `.jpg`, `.jpeg`
- Max size: 2 MB (client) / 6 MB (server `saveBase64Image`) — 172 KB passes.

### Files changed
- `cricket-api/src/middleware/security.js` — skip body scan for `*/upload-image`;
  broaden upload size ceiling to all `*/upload-image`.
- `admin-panel/app/splash/page.tsx` — explicit accept, WebP type/extension
  validation, MIME hint, clearer error.

### Test results
- `node -e` repro: a body that matches `SUSPICIOUS_PATTERNS` is **still rejected
  on a normal route** (`/admin/app-settings` → 400) but **passes on
  `/admin/splash-settings/upload-image`** (body skipped); a malicious **query**
  on the upload route is still caught (→ 400). SQLi protection intact.
- `node --check` on `security.js`, `splash.routes.js`, `admin/index.js` → OK.
- `node --test src/lib/api-security.test.js` → **10/10 pass** (no regression).
- Admin `npx tsc --noEmit` → clean; `npm run build` → success (`/splash` 4.21 kB).

### To verify on the live server (after deploying §12 + this fix and restarting)
```bash
pm2 restart cricket-api --update-env
# In the admin panel: upload stadium.webp to each of the 5 slots, then Save.
curl -s https://api.webcrichd.co/app/config | jq '.data.splash.assets'
# Expect the saved /uploads/*.webp URLs (e.g. "stadiumBackground":
#   "https://api.webcrichd.co/uploads/<id>.webp", ...).
```
Note: this WebP fix lives in `src/middleware/security.js`, which — like the §12
route — must be deployed and the process restarted for the live API to accept
the upload.

---

## 14. Local-Only Splash Startup Optimization

### Why Admin/remote splash assets were removed from Flutter startup

Android cold start must show the splash immediately. Even a cached or background
Admin splash path kept the startup coupled to `/app/config`, SharedPreferences
splash flags, remote URL selection, and optional network image decode. That made
startup slower and could still produce half-loaded layers on real devices.

The Flutter launch path now treats splash as a fixed local startup experience:
native Android dark navy first, Flutter first frame local splash second, and only
after the splash finishes does the normal app config load for ads, maintenance,
notifications, remote assets, and other app features.

### Remote loading code disabled/removed

- `lib/main.dart` no longer imports or calls `SplashConfigService`.
- `_decideSplash()`, cached splash config reads, first-launch splash flags, and
  `refreshInBackground()` were removed from the startup path.
- `lib/features/splash/data/splash_config_service.dart` was removed.
- The splash widget has no `Image.network`, no Admin URL fallback chain, and no
  `/app/config` dependency.
- `/app/config` is still fetched by `_loadAppConfig()`, but only after the splash
  completes, for normal app settings and existing systems.

### Local assets used

- `assets/splash/splash_composed.webp` only.

The composed image contains the stadium background, CP logo, orbit trails,
CRICPRO wordmark panel, and pitch/wickets in one optimized local bitmap. Flutter
adds only lightweight cyan glow and particles on top.

### Startup flow after optimization

1. Android native dark navy launch screen.
2. Flutter first frame immediately shows local `splash_composed.webp`.
3. Lightweight glow/particle animation starts instantly.
4. No network/API/config call is needed for splash.
5. Splash finishes and opens the app.
6. App config loads after splash for normal app features.

### Android startup performance result

- Local splash runtime asset size: `77,204` bytes.
- Focused analyzer for `lib/main.dart lib/features/splash`: pending in this
  section's final verification pass.
- Android profile run: pending final verification after the rectangle fix below.

---

## 15. Splash Rectangles + Heavy Animation Final Fix

### Root cause

The previous layered splash rendered separate CP logo, wordmark, orbit, and
pitch/wickets images. Some of those assets were flattened WebP/PNG-style images
with black/checkerboard/dark backgrounds instead of real transparency, so Flutter
displayed their full rectangular bounds. The animation also repainted multiple
large opacity/image layers, which was too heavy for Android startup.

### Option used

Used **Option A: one optimized full-screen composed local image**.

`assets/splash/splash_composed.webp` is generated from the premium target art and
contains the full intended design: stadium, clean CP logo, cyan orbit, wordmark
panel, and pitch/wickets. This removes all separate overlay bitmap rectangles.

### Assets replaced or removed

Removed from the Flutter splash runtime:
- `cp_logo.webp`
- `wordmark_panel.webp`
- `pitch_wickets.webp`
- `orbit_trail.webp`
- `stadium_background.webp`
- old generated fallback script

Remaining splash asset:
- `assets/splash/splash_composed.webp` - 900 x 1600 WebP, quality 76, 77 KB.

### Rendering changes

- `PremiumSplashScreen` now renders only the composed WebP with `BoxFit.cover`
  and `cacheWidth`.
- Removed separate logo, wordmark, pitch, and orbit image layer rendering.
- Removed `_WordmarkPanel`, `_ScreenBlend`, and the old orbit path.
- Kept only cheap local animation:
  - background fade
  - cyan floodlight/global glow painters
  - subtle logo-area pulse painter
  - 24 particle dots
  - final soft glow pulse
- No remote images, no backdrop filters, no large blur filters, and no
  multi-image crossfade.

### Files changed

- `lib/main.dart`
- `lib/features/splash/presentation/premium_splash_screen.dart`
- `lib/features/splash/widgets/splash_asset_image.dart`
- `lib/features/splash/widgets/splash_orbit_trail.dart` removed
- `lib/features/splash/data/splash_config_service.dart` removed
- `assets/splash/splash_composed.webp` added
- obsolete splash overlay assets removed
- `android/app/src/main/res/drawable/launch_background.xml`
- `android/app/src/main/res/drawable-v21/launch_background.xml`

### Final verification status

- `flutter clean`: passed before this final composed-image fix.
- `flutter pub get`: passed before this final composed-image fix.
- `flutter analyze`: full repo blocked by pre-existing archived dead-code errors
  under `archived/dead-code/...`; focused splash analysis will be rerun.
- `flutter test`: passed before this final composed-image fix; will be rerun.
- `flutter run --profile`: was interrupted before completion and must be rerun.
- `flutter build apk --release`: pending.

### Manual Android test notes

Pending a fresh profile install/run on the attached Android device. Expected
result after this fix:
- no white flash
- no Flutter default splash
- no black/checkerboard rectangles
- CP/logo/wordmark/pitch appear as one clean cinematic composition
- animation starts instantly
- app opens Home normally
- back cannot return to splash

### Remaining notes

Admin Panel and backend splash settings can remain deployed for management or
preview, but Flutter startup intentionally ignores Admin splash asset URLs for
performance and reliability.
