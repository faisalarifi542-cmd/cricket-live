import { query } from './db.js';

// ============================================================================
// Admin-managed team logos (order-aware).
// ----------------------------------------------------------------------------
// The Admin Panel lets operators upload a logo per team (stored under
// /uploads and persisted on the `teams.logo_url` column). This module loads a
// small, cached index of those logos and exposes `enrichTeamLogos(payload)`,
// which is wired into a global Fastify preSerialization hook so EVERY public
// API response that carries team objects gets the resolved logo.
//
// Resolution is driven by a global, admin-configurable SOURCE ORDER
// (`team_logo_source_order` in app_settings) over four sources:
//   admin    : the Admin-Panel uploaded logo (teams.logo_url)
//   local    : a logo bundled in the Flutter app (client-side only)
//   api      : the Cricbuzz/provider logo already on the node
//   initials : no logo at all (client renders initials)
//
// The recommended default is `["admin","local","api","initials"]`.
//
// `local` is a CLIENT-only source — the backend cannot serve a bundled asset —
// so the backend only decides between `admin`, `api` and `initials`, and always
// passes the full order to the app (via /app/config) plus enough per-team
// fields (`adminLogoUrl`, `imageId`) for the client to insert `local` at the
// configured position. The backend writes:
//   logoUrl / logo_url : the order-resolved remote URL (admin or api), or null
//   adminLogoUrl       : the admin logo when one exists (else null)
//   logoSource         : 'admin' | 'api' | 'initials' | 'none'
// and clears the raw provider id (imageId) when no remote logo is allowed, so
// the client cannot rebuild a Cricbuzz URL and bypass the configured order.
//
// A team is matched against the index by provider id (any id key), then short
// code, then full name, then a punctuation-stripped name, then aliases
// (`teams.metadata.aliases`) — whichever hits first. This makes franchise sides
// like SFU / LAKR resolve even when the provider's short name differs from the
// admin record across feeds.
// ============================================================================

export const TEAM_LOGO_SOURCES = Object.freeze(['admin', 'local', 'api', 'initials']);
export const DEFAULT_TEAM_LOGO_ORDER = Object.freeze(['admin', 'local', 'api', 'initials']);
export const TEAM_LOGO_ORDER_SETTING_KEY = 'team_logo_source_order';
export const TEAM_LOGOS_ENABLED_SETTING_KEY = 'team_logos_enabled';

const TTL_MS = 60 * 1000;

// Two parallel indexes keyed identically (id → short → name → normalized name):
//   by*    : custom/admin logos      (teams.logo_url)          → logoSource 'admin'
//   cbBy*  : synced Cricbuzz/API logos(teams.cricbuzz_logo_url) → logoSource 'api'
// A team that was only Cricbuzz-synced has logo_url NULL but cricbuzz_logo_url set;
// it must still resolve (to the api logo), so both indexes are loaded.
function emptyIndex() {
  return {
    at: 0,
    order: DEFAULT_TEAM_LOGO_ORDER.slice(),
    enabled: true,
    byId: new Map(),
    byShort: new Map(),
    byName: new Map(),
    byNameNorm: new Map(),
    cbById: new Map(),
    cbByShort: new Map(),
    cbByName: new Map(),
    cbByNameNorm: new Map(),
    size: 0,
  };
}

let _cache = emptyIndex();

/** Normalizes a free-text team key to compare names across feeds. */
function normKey(value) {
  return String(value || '').trim().toLowerCase().replace(/[^a-z0-9]+/g, '');
}

/**
 * Coerces an arbitrary value into a valid, de-duplicated source order that
 * always contains all four sources (missing ones appended in default order).
 */
export function coerceTeamLogoOrder(value) {
  let arr = value;
  if (typeof arr === 'string') {
    try { arr = JSON.parse(arr); } catch { arr = arr.split(/[,>\s]+/); }
  }
  if (arr && typeof arr === 'object' && !Array.isArray(arr)) {
    arr = arr.order || arr.value || arr.sources;
  }
  if (!Array.isArray(arr)) return DEFAULT_TEAM_LOGO_ORDER.slice();
  const out = [];
  for (const raw of arr) {
    const s = String(raw || '').trim().toLowerCase();
    if (TEAM_LOGO_SOURCES.includes(s) && !out.includes(s)) out.push(s);
  }
  for (const s of DEFAULT_TEAM_LOGO_ORDER) if (!out.includes(s)) out.push(s);
  return out;
}

function coerceBool(value, fallback = true) {
  if (value == null) return fallback;
  if (typeof value === 'boolean') return value;
  const s = String(value).trim().toLowerCase();
  if (['false', '0', 'no', 'off', 'disabled'].includes(s)) return false;
  if (['true', '1', 'yes', 'on', 'enabled'].includes(s)) return true;
  return fallback;
}

async function readSetting(key) {
  try {
    const rows = await query(
      `SELECT setting_value FROM app_settings WHERE setting_key = ? LIMIT 1`,
      [key],
    );
    if (rows && rows.length) {
      let raw = rows[0].setting_value;
      if (typeof raw === 'string') {
        try { raw = JSON.parse(raw); } catch { /* plain string */ }
      }
      return raw;
    }
  } catch {
    // app_settings missing — fall back to defaults.
  }
  return undefined;
}

/** Reads the global team-logo source order from app_settings. */
async function loadGlobalOrder() {
  const raw = await readSetting(TEAM_LOGO_ORDER_SETTING_KEY);
  return coerceTeamLogoOrder(raw);
}

/** Reads the master team-logos-enabled flag from app_settings (default on). */
async function loadEnabled() {
  const raw = await readSetting(TEAM_LOGOS_ENABLED_SETTING_KEY);
  if (raw == null) return true;
  const candidate = (raw && typeof raw === 'object')
    ? (raw.enabled ?? raw.value ?? raw)
    : raw;
  return coerceBool(candidate, true);
}

/** Loads (and briefly caches) the admin team-logo index + settings from DB. */
export async function getAdminTeamLogoIndex() {
  const now = Date.now();
  if (_cache.at !== 0 && now - _cache.at < TTL_MS) return _cache;

  const [order, enabled] = await Promise.all([loadGlobalOrder(), loadEnabled()]);

  const idx = emptyIndex();
  const { byId, byShort, byName, byNameNorm, cbById, cbByShort, cbByName, cbByNameNorm } = idx;
  // Index a single (key-set, logo) into the four maps for one source.
  const put = (maps, keys, logo) => {
    const { id, short, name, aliases } = keys;
    if (id) maps.byId.set(id, logo);
    if (short) maps.byShort.set(short, logo);
    if (name) {
      maps.byName.set(name, logo);
      maps.byNameNorm.set(normKey(name), logo);
    }
    for (const a of aliases) {
      maps.byShort.set(a, logo);
      maps.byName.set(a, logo);
      maps.byNameNorm.set(normKey(a), logo);
    }
  };
  try {
    // Load teams that have EITHER an admin (custom) logo OR a synced Cricbuzz
    // logo. Cricbuzz-only teams (logo_url NULL) are valid API fallbacks and must
    // be indexed so match-detail nodes — which carry no logo of their own —
    // still resolve to the api logo.
    const rows = await query(
      `SELECT external_id, name, short_name, logo_url, cricbuzz_logo_url, metadata
         FROM teams
        WHERE (
                (logo_url IS NOT NULL AND TRIM(logo_url) <> '')
                OR (cricbuzz_logo_url IS NOT NULL AND TRIM(cricbuzz_logo_url) <> '')
              )
          AND COALESCE(is_active, 1) = 1`,
    );
    for (const r of rows) {
      const adminLogo = String(r.logo_url || '').trim();
      const cbLogo = String(r.cricbuzz_logo_url || '').trim();
      if (!adminLogo && !cbLogo) continue;
      let meta = r.metadata;
      if (typeof meta === 'string') {
        try { meta = JSON.parse(meta); } catch { meta = null; }
      }
      const aliases = (meta && Array.isArray(meta.aliases) ? meta.aliases : [])
        .map((a) => String(a || '').trim().toLowerCase())
        .filter(Boolean);
      const keys = {
        id: String(r.external_id || '').trim(),
        short: String(r.short_name || '').trim().toLowerCase(),
        name: String(r.name || '').trim().toLowerCase(),
        aliases,
      };
      if (adminLogo) put({ byId, byShort, byName, byNameNorm }, keys, adminLogo);
      if (cbLogo) put({ byId: cbById, byShort: cbByShort, byName: cbByName, byNameNorm: cbByNameNorm }, keys, cbLogo);
    }
  } catch {
    // teams table missing/empty — degrade to "no indexed logos".
  }
  idx.at = now;
  idx.order = order;
  idx.enabled = enabled;
  // size = number of distinct indexed admin logos (kept for telemetry only; the
  // resolver no longer short-circuits on it).
  idx.size = byId.size + byShort.size + byName.size + cbById.size + cbByShort.size + cbByName.size;
  _cache = idx;
  return _cache;
}

/** Drops the cache so an admin logo / order edit is reflected next request. */
export function invalidateAdminTeamLogoIndex() {
  _cache = emptyIndex();
}

/** Returns the current global team-logo source order (reads app_settings). */
export async function getTeamLogoOrder() {
  return loadGlobalOrder();
}

/** Returns whether team logos are enabled at all (reads app_settings). */
export async function isTeamLogosEnabled() {
  return loadEnabled();
}

const NAME_KEYS = ['teamName', 'team_name', 'name', 'fullName', 'teamFullName'];
const SHORT_KEYS = [
  'teamShortName', 'teamShort', 'team_short', 'shortName', 'short_name', 'teamSName',
];
// Every id field a normalized team object might carry. Crucially includes `id`,
// because the Cricbuzz normalizer exposes the team id under `id` (not `teamId`)
// on both list and match-detail payloads — without it, admin id-matching never
// fired on Match Details / Live and those screens fell back to initials.
const ID_KEYS = ['teamId', 'team_id', 'teamID', 'id', 'externalId', 'external_id'];
// Logo-ish fields we will overwrite when resolving. imageUrl is included because
// some provider team objects carry the logo there.
const LOGO_KEYS = ['logoUrl', 'logo_url', 'logo', 'flag', 'imageUrl', 'image_url'];
// Raw provider image-id fields. When no remote logo is allowed (initials /
// disabled) we clear these so the client cannot rebuild a Cricbuzz URL.
const IMAGE_ID_KEYS = ['imageId', 'image_id', 'teamImageId', 'team_image_id'];

function firstString(obj, keys) {
  for (const k of keys) {
    const v = obj[k];
    if (typeof v === 'string' && v.trim()) return v.trim();
    if (typeof v === 'number' && Number.isFinite(v)) return String(v);
  }
  return '';
}

// A node is treated as a team only when it has BOTH a name and a short code.
// Players (name + playerId, no short code) are therefore never matched.
function looksLikeTeam(obj) {
  const hasName = NAME_KEYS.some((k) => typeof obj[k] === 'string' && obj[k].trim());
  const hasShort = SHORT_KEYS.some((k) => typeof obj[k] === 'string' && obj[k].trim());
  return hasName && hasShort;
}

/** Looks up a team node against one set of maps: id → short → name → aliases. */
function lookupLogo(maps, obj) {
  const id = firstString(obj, ID_KEYS);
  if (id && maps.byId.has(id)) return maps.byId.get(id);
  const short = firstString(obj, SHORT_KEYS).toLowerCase();
  if (short && maps.byShort.has(short)) return maps.byShort.get(short);
  const name = firstString(obj, NAME_KEYS).toLowerCase();
  if (name && maps.byName.has(name)) return maps.byName.get(name);
  const nameNorm = normKey(firstString(obj, NAME_KEYS));
  if (nameNorm && maps.byNameNorm.has(nameNorm)) return maps.byNameNorm.get(nameNorm);
  // A short code may itself be an alias key indexed under byName/byNameNorm.
  if (short && maps.byNameNorm.has(normKey(short))) return maps.byNameNorm.get(normKey(short));
  return null;
}

/** Finds the custom/admin logo (teams.logo_url) for a team node. */
function resolveAdminLogo(index, obj) {
  return lookupLogo(
    { byId: index.byId, byShort: index.byShort, byName: index.byName, byNameNorm: index.byNameNorm },
    obj,
  );
}

/** Finds the synced Cricbuzz/API logo (teams.cricbuzz_logo_url) for a team node. */
function resolveCricbuzzLogo(index, obj) {
  return lookupLogo(
    { byId: index.cbById, byShort: index.cbByShort, byName: index.cbByName, byNameNorm: index.cbByNameNorm },
    obj,
  );
}

/**
 * Resolves the remote logo a team node should display for the given order.
 * `local` is transparent here (handled client-side) and skipped; the result is
 * the first of admin/api that yields a URL, or null when `initials` is reached
 * first (or logos are disabled). Returns { url, source }.
 */
export function resolveTeamLogo({ order, enabled, adminLogo, providerLogo }) {
  const admin = adminLogo && String(adminLogo).trim() ? String(adminLogo).trim() : null;
  const provider = providerLogo && String(providerLogo).trim()
    ? String(providerLogo).trim() : null;
  if (enabled === false) return { url: null, source: 'initials' };
  const ord = coerceTeamLogoOrder(order);
  for (const source of ord) {
    if (source === 'local') continue; // client-only — keep looking for a remote fallback
    if (source === 'initials') return { url: null, source: 'initials' };
    if (source === 'admin' && admin) return { url: admin, source: 'admin' };
    if (source === 'api' && provider) return { url: provider, source: 'api' };
  }
  // No source produced a remote logo.
  return { url: null, source: 'none' };
}

/**
 * True when the configured order forbids a remote logo (logos disabled, or
 * `initials` sits ahead of both `admin` and `api`). In that case we strip the
 * raw provider image id so the client cannot rebuild a Cricbuzz URL.
 */
function computeForcesInitials(index) {
  const ord = index.order || DEFAULT_TEAM_LOGO_ORDER;
  const idxAdmin = ord.indexOf('admin');
  const idxApi = ord.indexOf('api');
  const idxInitials = ord.indexOf('initials');
  return index.enabled === false
    || (idxInitials !== -1
        && (idxAdmin === -1 || idxInitials < idxAdmin)
        && (idxApi === -1 || idxInitials < idxApi));
}

/**
 * Annotates a SINGLE team node in place with the resolved logo fields. Always
 * writes `logoSource`, `logoUrl`, `logo_url` and `adminLogoUrl` so the client
 * has the full contract even when no admin/provider logo exists (it can then
 * insert `local` at its configured position). `image_id`/`imageId` are
 * preserved unless the order forbids a remote logo entirely.
 */
function applyTeamLogo(index, node, forcesInitials) {
  const adminLogo = resolveAdminLogo(index, node);
  // The `api` candidate is the Cricbuzz logo already on the node (list/home
  // payloads carry it) OR, when the node has none (match-detail teams), the
  // synced Cricbuzz logo from the index keyed by id/short/name.
  const cricbuzzLogo = (firstString(node, LOGO_KEYS) || resolveCricbuzzLogo(index, node)) || null;
  const { url, source } = resolveTeamLogo({
    order: index.order,
    enabled: index.enabled,
    adminLogo,
    providerLogo: cricbuzzLogo,
  });
  // Always expose both candidate URLs + the chosen source so the client can
  // honor `local` at its configured position regardless of which remote we
  // picked. When the order forces initials, drop the URLs too so the client
  // cannot surface them as a fallback.
  node.adminLogoUrl = source === 'initials' ? null : (adminLogo || null);
  node.cricbuzzLogoUrl = source === 'initials' ? null : (cricbuzzLogo || null);
  node.logoSource = url ? source : (source === 'initials' ? 'initials' : 'none');
  for (const k of LOGO_KEYS) {
    if (k in node) node[k] = url;
  }
  node.logoUrl = url;
  node.logo_url = url;
  // When the configuration intentionally forbids a remote logo (initials
  // first / logos disabled), strip the raw provider id so the client cannot
  // rebuild a Cricbuzz URL and bypass the order. We do NOT strip it when the
  // logo is merely absent (source 'none'), so a provider id-only logo still
  // resolves on the client.
  if (!url && forcesInitials) {
    for (const k of IMAGE_ID_KEYS) {
      if (k in node) node[k] = null;
    }
  }
}

/**
 * Enriches a known list of team nodes (e.g. match-detail `team1`/`team2`) in
 * place. Unlike the recursive walk this does not gate on `looksLikeTeam` — the
 * caller asserts these are team objects — so it works even for partial shapes.
 * Defensive: loads the cached index once, never throws.
 */
export async function enrichTeamNodes(nodes) {
  let index;
  try {
    index = await getAdminTeamLogoIndex();
  } catch {
    return;
  }
  if (!index) return;
  const forcesInitials = computeForcesInitials(index);
  for (const node of nodes) {
    if (!node || typeof node !== 'object' || Array.isArray(node)) continue;
    try {
      applyTeamLogo(index, node, forcesInitials);
    } catch {
      // Never break a response over a single node.
    }
  }
}

/**
 * Recursively walks a response payload and, for every team-shaped object,
 * resolves its logo according to the admin index + global source order.
 * Defensive: bounded depth, cycle-safe, and never throws.
 *
 * NOTE: we intentionally do NOT short-circuit when there are no admin logos.
 * The client contract requires `logoSource`/`logoUrl`/`adminLogoUrl` on EVERY
 * team object (so it can apply `local`/`api`/`initials` in order); skipping the
 * walk when `index.size === 0` previously left every team unannotated.
 */
export async function enrichTeamLogos(payload, { maxDepth = 12 } = {}) {
  if (!payload || typeof payload !== 'object') return payload;
  let index;
  try {
    index = await getAdminTeamLogoIndex();
  } catch {
    return payload;
  }
  if (!index) return payload;

  const forcesInitials = computeForcesInitials(index);

  const seen = new Set();
  const walk = (node, depth) => {
    if (!node || typeof node !== 'object' || depth > maxDepth) return;
    if (seen.has(node)) return;
    seen.add(node);
    if (Array.isArray(node)) {
      for (const item of node) walk(item, depth + 1);
      return;
    }
    if (looksLikeTeam(node)) {
      applyTeamLogo(index, node, forcesInitials);
    }
    for (const key of Object.keys(node)) {
      walk(node[key], depth + 1);
    }
  };
  try {
    walk(payload, 0);
  } catch {
    // Never break a response over logo enrichment.
  }
  return payload;
}
