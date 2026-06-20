/**
 * Premium animated splash screen configuration.
 *
 * The 8 splash settings live in `app_settings` (group `splash`, public) so the
 * Flutter app receives them inside `GET /app/config` and operators manage them
 * from Admin → Splash Screen. Everything degrades to a safe default; the app
 * always ships bundled fallback art, so a missing/empty URL never crashes it.
 *
 * Keep these keys in sync with:
 *   - admin route  : src/admin/routes/splash.routes.js
 *   - admin panel  : admin-panel/app/splash/page.tsx
 *   - flutter model: lib/features/splash/data/splash_config_service.dart
 */

export const SPLASH_SETTING_KEYS = [
  'splash_enabled',
  'splash_duration_ms',
  'splash_skip_after_first_launch',
  'splash_stadium_background_url',
  'splash_cp_logo_url',
  'splash_wordmark_panel_url',
  'splash_orbit_trail_url',
  'splash_pitch_wickets_url',
];

export const SPLASH_DEFAULTS = {
  splash_enabled: true,
  splash_duration_ms: 3000,
  splash_skip_after_first_launch: false,
  splash_stadium_background_url: '',
  splash_cp_logo_url: '',
  splash_wordmark_panel_url: '',
  splash_orbit_trail_url: '',
  splash_pitch_wickets_url: '',
};

function normBool(value, fallback = false) {
  if (value == null) return fallback;
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  const t = String(value).trim().toLowerCase();
  if (['1', 'true', 'yes', 'on'].includes(t)) return true;
  if (['0', 'false', 'no', 'off'].includes(t)) return false;
  return fallback;
}

function clampInt(value, fallback, min, max) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, Math.round(n)));
}

function cleanUrl(value) {
  const v = String(value ?? '').trim();
  return v || null;
}

/**
 * Builds the public `splash` block from a flat settings map (the same map
 * produced by buildPublicAppConfig). Unknown/missing keys fall back to
 * SPLASH_DEFAULTS. Duration is clamped to a sane [800, 10000] ms range.
 */
export function buildSplashConfig(settings = {}) {
  const get = (k) =>
    settings[k] !== undefined && settings[k] !== null ? settings[k] : SPLASH_DEFAULTS[k];
  return {
    enabled: normBool(get('splash_enabled'), true),
    durationMs: clampInt(get('splash_duration_ms'), 3000, 800, 10000),
    skipAfterFirstLaunch: normBool(get('splash_skip_after_first_launch'), false),
    assets: {
      stadiumBackground: cleanUrl(get('splash_stadium_background_url')),
      cpLogo: cleanUrl(get('splash_cp_logo_url')),
      wordmarkPanel: cleanUrl(get('splash_wordmark_panel_url')),
      orbitTrail: cleanUrl(get('splash_orbit_trail_url')),
      pitchWickets: cleanUrl(get('splash_pitch_wickets_url')),
    },
  };
}

/** Splash asset slot metadata surfaced to the admin UI (keyed upload slots). */
export const SPLASH_ASSET_SLOTS = [
  {
    settingKey: 'splash_stadium_background_url',
    field: 'stadiumBackground',
    label: 'Stadium background',
    hint: 'Full-screen blue-lit stadium at night. Source: blue_lit_sports_stadium_at_night.png',
    dimensions: '1080x1920',
  },
  {
    settingKey: 'splash_cp_logo_url',
    field: 'cpLogo',
    label: 'CP logo',
    hint: 'Centered glowing CP logo. Source: futuristic_glowing_cp_logo.png',
    dimensions: '600x600',
  },
  {
    settingKey: 'splash_wordmark_panel_url',
    field: 'wordmarkPanel',
    label: 'CRICPRO wordmark panel',
    hint: 'Neon CRICPRO wordmark below the logo. Source: glowing_cricpro_logo_in_neon_blue.png',
    dimensions: '900x300',
  },
  {
    settingKey: 'splash_orbit_trail_url',
    field: 'orbitTrail',
    label: 'Neon orbit trail',
    hint: 'Energy ribbon that sweeps around the logo. Source: neon_energy_ribbon_in_dark_space.png',
    dimensions: '900x900',
  },
  {
    settingKey: 'splash_pitch_wickets_url',
    field: 'pitchWickets',
    label: 'Pitch / wickets foreground',
    hint: 'Glowing cricket pitch + wickets at the bottom. Source: neon_cricket_court_in_darkness.png',
    dimensions: '1080x720',
  },
];
