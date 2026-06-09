import { query } from './db.js';

// ============================================================================
// Home layout configuration
// ----------------------------------------------------------------------------
// A single JSON document (stored in app_settings under `home_layout`) drives
// every Home-screen section: enable/disable, source (auto vs manual), counts,
// ordering, titles and per-section toggles. The app reads a merged view of
// this config from /app/home so the Flutter client can hide disabled sections
// and fall back to automatic data when nothing is configured.
//
// Everything here is defensive: missing keys fall back to DEFAULT_HOME_LAYOUT,
// so partially-saved configs and older databases keep working.
// ============================================================================

export const HOME_LAYOUT_KEY = 'home_layout';

export const SECTION_KEYS = ['topFeatured', 'mainMatches', 'featuredMatches', 'featuredSeries'];

export const DEFAULT_HOME_LAYOUT = Object.freeze({
  sectionOrder: ['topFeatured', 'mainMatches', 'featuredMatches', 'featuredSeries'],
  sections: {
    topFeatured: {
      enabled: true,
      source: 'auto', // 'auto' | 'manual'
      manualMatchIds: [],
      maxItems: 5,
      filter: 'mixed', // 'mixed' | 'live' | 'upcoming'
      showDots: true,
    },
    mainMatches: {
      enabled: true,
      showStatusTabs: true,
      defaultTab: 'live', // 'live' | 'upcoming' | 'finished'
      showCategoryFilter: true,
      defaultCategory: 'all', // 'all' | 'international' | 'league' | 'domestic'
      maxItems: 12,
      showWatchLive: true,
      showViewMatch: true,
    },
    featuredMatches: {
      enabled: true,
      title: 'Featured Matches',
      source: 'auto',
      manualMatchIds: [],
      maxItems: 6,
      showSeeAll: true,
    },
    featuredSeries: {
      enabled: true,
      title: 'Featured Series',
      source: 'manual',
      maxItems: 10,
      showSeeAll: true,
    },
  },
});

function isObject(v) {
  return v && typeof v === 'object' && !Array.isArray(v);
}

/** Deep-merge a stored partial config over the defaults (defensive). */
export function mergeHomeLayout(stored) {
  const cfg = isObject(stored) ? stored : {};
  const out = {
    sectionOrder: Array.isArray(cfg.sectionOrder) && cfg.sectionOrder.length
      ? cfg.sectionOrder.filter((s) => SECTION_KEYS.includes(s))
      : [...DEFAULT_HOME_LAYOUT.sectionOrder],
    sections: {},
  };
  // Ensure every known section appears in the order exactly once.
  for (const key of DEFAULT_HOME_LAYOUT.sectionOrder) {
    if (!out.sectionOrder.includes(key)) out.sectionOrder.push(key);
  }
  const storedSections = isObject(cfg.sections) ? cfg.sections : {};
  for (const key of SECTION_KEYS) {
    out.sections[key] = { ...DEFAULT_HOME_LAYOUT.sections[key], ...(isObject(storedSections[key]) ? storedSections[key] : {}) };
    // Normalise array fields.
    if ('manualMatchIds' in out.sections[key]) {
      const ids = out.sections[key].manualMatchIds;
      out.sections[key].manualMatchIds = Array.isArray(ids)
        ? ids.map((x) => String(x)).filter(Boolean)
        : [];
    }
  }
  return out;
}

/** Parse a JSON column value that may already be an object or a string. */
function parseStored(value) {
  if (value == null) return null;
  if (isObject(value)) return value;
  if (typeof value === 'string') {
    try {
      return JSON.parse(value);
    } catch {
      return null;
    }
  }
  return null;
}

/** Load the merged home layout config from app_settings (with safe defaults). */
export async function loadHomeLayout() {
  try {
    const rows = await query(
      `SELECT setting_value FROM app_settings WHERE setting_key = ? LIMIT 1`,
      [HOME_LAYOUT_KEY],
    );
    const raw = rows?.[0]?.setting_value;
    return mergeHomeLayout(parseStored(raw));
  } catch {
    return mergeHomeLayout(null);
  }
}

/** Persist the home layout config (idempotent upsert). */
export async function saveHomeLayout(config, adminUserId = null) {
  const merged = mergeHomeLayout(config);
  await query(
    `INSERT INTO app_settings (setting_key, setting_value, setting_group, type, \`group\`, description, is_public, updated_by)
     VALUES (?, ?, 'home', 'json', 'home', 'Home screen layout configuration', 1, ?)
     ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_by = VALUES(updated_by)`,
    [HOME_LAYOUT_KEY, JSON.stringify(merged), adminUserId],
  );
  return merged;
}
