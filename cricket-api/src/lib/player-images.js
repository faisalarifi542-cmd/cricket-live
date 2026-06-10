import { query } from './db.js';

// ============================================================================
// Admin-managed player images.
// ----------------------------------------------------------------------------
// The Admin Panel lets operators upload a photo per player (stored under
// /uploads and persisted on `players.admin_image_url`) and/or set a provider
// (Cricbuzz) image URL. This module loads a small, cached index of those
// records and exposes `enrichPlayerImages(payload)`, wired into the same
// global Fastify preSerialization hook as team logos, so EVERY public API
// response that carries player objects gets the resolved image.
//
// Resolution is driven by a global mode (an `app_settings` key) with optional
// per-player override:
//   admin_first    : admin photo → provider photo → initials (client-side)
//   cricbuzz_first : provider photo → admin photo → initials
//   admin_only     : admin photo → initials
//   cricbuzz_only  : provider photo → initials
//   initials_only  : never emit an image (clears the field → initials)
//
// The recommended default is `admin_first`.
//
// A player object is matched against the index by provider id, then full
// name (case-insensitive). Team objects (name + short code) are never
// matched, so their logos are left to enrichTeamLogos.
// ============================================================================

export const PLAYER_IMAGE_MODES = Object.freeze([
  'admin_first',
  'cricbuzz_first',
  'admin_only',
  'cricbuzz_only',
  'initials_only',
]);

export const DEFAULT_PLAYER_IMAGE_MODE = 'admin_first';
export const PLAYER_IMAGE_MODE_SETTING_KEY = 'player_image_mode';

const TTL_MS = 60 * 1000;

let _cache = {
  at: 0,
  globalMode: DEFAULT_PLAYER_IMAGE_MODE,
  byId: new Map(),
  byName: new Map(),
  size: 0,
};

function coerceMode(value) {
  const m = String(value || '').trim().toLowerCase();
  return PLAYER_IMAGE_MODES.includes(m) ? m : null;
}

/** Reads the global player-image mode from app_settings (cached with index). */
async function loadGlobalMode() {
  try {
    const rows = await query(
      `SELECT setting_value FROM app_settings WHERE setting_key = ? LIMIT 1`,
      [PLAYER_IMAGE_MODE_SETTING_KEY],
    );
    if (rows && rows.length) {
      let raw = rows[0].setting_value;
      if (typeof raw === 'string') {
        try { raw = JSON.parse(raw); } catch { /* plain string */ }
      }
      // setting_value may be the bare string, { mode }, or { value }.
      const candidate =
        (raw && typeof raw === 'object' ? raw.mode || raw.value : raw) ?? raw;
      const mode = coerceMode(candidate);
      if (mode) return mode;
    }
  } catch {
    // app_settings missing — fall back to the default mode.
  }
  return DEFAULT_PLAYER_IMAGE_MODE;
}

/** Loads (and briefly caches) the admin player-image index from the DB. */
export async function getAdminPlayerImageIndex() {
  const now = Date.now();
  if (_cache.at !== 0 && now - _cache.at < TTL_MS) return _cache;

  const globalMode = await loadGlobalMode();
  const byId = new Map();
  const byName = new Map();
  try {
    const rows = await query(
      `SELECT external_id, player_external_id, name, full_name,
              admin_image_url, provider_image_url, image_url,
              image_mode, is_image_active
         FROM players
        WHERE COALESCE(is_active, 1) = 1`,
    );
    for (const r of rows) {
      const adminImage = String(r.admin_image_url || '').trim();
      const providerImage = String(
        r.provider_image_url || r.image_url || '',
      ).trim();
      const mode = coerceMode(r.image_mode);
      const overrideActive = r.is_image_active == null
        ? true
        : Boolean(Number(r.is_image_active));
      // Skip rows that carry no useful information at all.
      if (!adminImage && !providerImage && !mode) continue;
      const record = {
        adminImage: adminImage || null,
        providerImage: providerImage || null,
        mode: overrideActive ? mode : null,
      };
      const ids = [r.external_id, r.player_external_id]
        .map((v) => String(v || '').trim())
        .filter(Boolean);
      for (const id of ids) byId.set(id, record);
      const name = String(r.full_name || r.name || '').trim().toLowerCase();
      if (name) byName.set(name, record);
    }
  } catch {
    // players table missing/empty — degrade to "no admin images".
  }
  _cache = {
    at: now,
    globalMode,
    byId,
    byName,
    size: byId.size + byName.size,
  };
  return _cache;
}

/** Drops the cache so an admin image edit is reflected on the next request. */
export function invalidateAdminPlayerImageIndex() {
  _cache = {
    at: 0,
    globalMode: DEFAULT_PLAYER_IMAGE_MODE,
    byId: new Map(),
    byName: new Map(),
    size: 0,
  };
}

/** Returns the current global player-image mode (reads app_settings). */
export async function getPlayerImageMode() {
  return loadGlobalMode();
}

const ID_KEYS = ['playerId', 'player_id', 'batId', 'bowlId', 'id'];
const NAME_KEYS = ['fullName', 'full_name', 'name', 'playerName', 'player_name'];
const SHORT_KEYS = [
  'teamShortName', 'teamShort', 'team_short', 'shortName', 'short_name', 'teamSName',
];
// Image-ish fields we overwrite/clear when resolving a player image.
const IMAGE_KEYS = ['imageUrl', 'image_url', 'faceImageUrl', 'faceImage', 'image'];

function firstString(obj, keys) {
  for (const k of keys) {
    const v = obj[k];
    if (typeof v === 'string' && v.trim()) return v.trim();
  }
  return '';
}

function hasAnyKey(obj, keys) {
  return keys.some((k) => k in obj);
}

// A node is treated as a player only when it has a name, at least one
// image-ish field (so we know where to write), and NO team short code (which
// would mark it as a team). The presence of a player id strengthens the match
// but is not strictly required.
function looksLikePlayer(obj) {
  const hasName = NAME_KEYS.some(
    (k) => typeof obj[k] === 'string' && obj[k].trim(),
  );
  if (!hasName) return false;
  const hasShort = SHORT_KEYS.some(
    (k) => typeof obj[k] === 'string' && obj[k].trim(),
  );
  if (hasShort) return false; // it's a team
  const hasPlayerId = ID_KEYS.some((k) => k !== 'id' && obj[k] != null);
  const hasImageField = hasAnyKey(obj, IMAGE_KEYS) || 'imageId' in obj || 'faceImageId' in obj;
  return hasPlayerId || hasImageField;
}

function lookupRecord(index, obj) {
  for (const k of ID_KEYS) {
    const v = obj[k];
    if (v != null) {
      const id = String(v).trim();
      if (id && index.byId.has(id)) return index.byId.get(id);
    }
  }
  const name = firstString(obj, NAME_KEYS).toLowerCase();
  if (name && index.byName.has(name)) return index.byName.get(name);
  return null;
}

/**
 * Resolves the image a player node should display given the effective mode,
 * the admin override record (may be null), and the provider image already on
 * the node. Returns a string URL, or `null` to mean "no image → initials".
 */
export function resolvePlayerImage({ mode, adminImage, providerImage }) {
  const effective = coerceMode(mode) || DEFAULT_PLAYER_IMAGE_MODE;
  const admin = adminImage && String(adminImage).trim() ? String(adminImage).trim() : null;
  const provider = providerImage && String(providerImage).trim()
    ? String(providerImage).trim()
    : null;
  switch (effective) {
    case 'initials_only':
      return null;
    case 'admin_only':
      return admin;
    case 'cricbuzz_only':
      return provider;
    case 'cricbuzz_first':
      return provider || admin;
    case 'admin_first':
    default:
      return admin || provider;
  }
}

/**
 * Recursively walks a response payload and, for every player-shaped object,
 * sets its image fields according to the resolved admin/provider/mode logic.
 * Defensive: bounded depth, cycle-safe, and never throws.
 */
export async function enrichPlayerImages(payload, { maxDepth = 14 } = {}) {
  if (!payload || typeof payload !== 'object') return payload;
  let index;
  try {
    index = await getAdminPlayerImageIndex();
  } catch {
    return payload;
  }
  if (!index) return payload;
  // When there are no overrides AND the global mode is the permissive default,
  // there is nothing to change (the provider image on the node already wins),
  // so we can skip the walk entirely for performance.
  if (index.size === 0 && index.globalMode === 'admin_first') return payload;

  const seen = new Set();
  const walk = (node, depth) => {
    if (!node || typeof node !== 'object' || depth > maxDepth) return;
    if (seen.has(node)) return;
    seen.add(node);
    if (Array.isArray(node)) {
      for (const item of node) walk(item, depth + 1);
      return;
    }
    if (looksLikePlayer(node)) {
      const record = lookupRecord(index, node);
      const providerOnNode = firstString(node, IMAGE_KEYS) || null;
      const resolved = resolvePlayerImage({
        mode: record && record.mode ? record.mode : index.globalMode,
        adminImage: record ? record.adminImage : null,
        providerImage: (record && record.providerImage) || providerOnNode,
      });
      // Write the resolved value (or null) to every image field present, and
      // ensure the canonical keys the app reads are set.
      for (const k of IMAGE_KEYS) {
        if (k in node) node[k] = resolved;
      }
      node.imageUrl = resolved;
      node.image_url = resolved;
    }
    for (const key of Object.keys(node)) {
      walk(node[key], depth + 1);
    }
  };
  try {
    walk(payload, 0);
  } catch {
    // Never break a response over image enrichment.
  }
  return payload;
}
