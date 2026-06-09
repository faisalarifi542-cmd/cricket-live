import { query } from './db.js';

// ============================================================================
// Admin-managed team logos.
// ----------------------------------------------------------------------------
// The Admin Panel lets operators upload a logo per team (stored under
// /uploads and persisted on the `teams.logo_url` column). This module loads a
// small, cached index of those logos and exposes `enrichTeamLogos(payload)`,
// which is wired into a global Fastify preSerialization hook so EVERY public
// API response that carries team objects gets the admin logo when one exists.
//
// Resolution priority (matches the Flutter widget):
//   1. Admin-uploaded logo (this module)        ← highest
//   2. Cricbuzz/provider logo (left untouched)
//   3. Local asset / initials (handled client-side)
//
// The index is matched against a team object by provider id, then short code,
// then full name (case-insensitive) — whichever hits first.
// ============================================================================

const TTL_MS = 60 * 1000;

let _cache = {
  at: 0,
  byId: new Map(),
  byShort: new Map(),
  byName: new Map(),
  size: 0,
};

/** Loads (and briefly caches) the admin team-logo index from the DB. */
export async function getAdminTeamLogoIndex() {
  const now = Date.now();
  if (_cache.at !== 0 && now - _cache.at < TTL_MS) return _cache;

  const byId = new Map();
  const byShort = new Map();
  const byName = new Map();
  try {
    const rows = await query(
      `SELECT external_id, name, short_name, logo_url
         FROM teams
        WHERE logo_url IS NOT NULL AND TRIM(logo_url) <> ''
          AND COALESCE(is_active, 1) = 1`,
    );
    for (const r of rows) {
      const logo = String(r.logo_url || '').trim();
      if (!logo) continue;
      const ext = String(r.external_id || '').trim();
      const short = String(r.short_name || '').trim().toLowerCase();
      const name = String(r.name || '').trim().toLowerCase();
      if (ext) byId.set(ext, logo);
      if (short) byShort.set(short, logo);
      if (name) byName.set(name, logo);
    }
  } catch {
    // teams table missing/empty — degrade to "no admin logos".
  }
  _cache = { at: now, byId, byShort, byName, size: byId.size + byShort.size + byName.size };
  return _cache;
}

/** Drops the cache so an admin logo edit is reflected on the next request. */
export function invalidateAdminTeamLogoIndex() {
  _cache = { at: 0, byId: new Map(), byShort: new Map(), byName: new Map(), size: 0 };
}

const NAME_KEYS = ['teamName', 'team_name', 'name', 'fullName', 'teamFullName'];
const SHORT_KEYS = [
  'teamShortName', 'teamShort', 'team_short', 'shortName', 'short_name', 'teamSName',
];
const ID_KEYS = ['teamId', 'team_id'];
// Logo-ish fields we will overwrite when an admin logo is found. imageUrl is
// included because some provider team objects carry the logo there.
const LOGO_KEYS = ['logoUrl', 'logo_url', 'logo', 'flag', 'imageUrl', 'image_url'];

function firstString(obj, keys) {
  for (const k of keys) {
    const v = obj[k];
    if (typeof v === 'string' && v.trim()) return v.trim();
  }
  return '';
}

// A node is treated as a team only when it has BOTH a name and a short code.
// Players (name + playerId, no short code) are therefore never matched, so
// their face images are left untouched.
function looksLikeTeam(obj) {
  const hasName = NAME_KEYS.some((k) => typeof obj[k] === 'string' && obj[k].trim());
  const hasShort = SHORT_KEYS.some((k) => typeof obj[k] === 'string' && obj[k].trim());
  return hasName && hasShort;
}

function resolveAdminLogo(index, obj) {
  const id = firstString(obj, ID_KEYS);
  if (id && index.byId.has(id)) return index.byId.get(id);
  const short = firstString(obj, SHORT_KEYS).toLowerCase();
  if (short && index.byShort.has(short)) return index.byShort.get(short);
  const name = firstString(obj, NAME_KEYS).toLowerCase();
  if (name && index.byName.has(name)) return index.byName.get(name);
  return null;
}

/**
 * Recursively walks a response payload and, for every team-shaped object,
 * overwrites its logo fields with the admin-uploaded logo when one exists.
 * Defensive: bounded depth, cycle-safe, and never throws.
 */
export async function enrichTeamLogos(payload, { maxDepth = 12 } = {}) {
  if (!payload || typeof payload !== 'object') return payload;
  let index;
  try {
    index = await getAdminTeamLogoIndex();
  } catch {
    return payload;
  }
  if (!index || index.size === 0) return payload;

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
      const adminLogo = resolveAdminLogo(index, node);
      if (adminLogo) {
        for (const k of LOGO_KEYS) {
          if (k in node) node[k] = adminLogo;
        }
        // Ensure the canonical keys the app reads are always present.
        node.logoUrl = adminLogo;
        node.logo_url = adminLogo;
      }
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
