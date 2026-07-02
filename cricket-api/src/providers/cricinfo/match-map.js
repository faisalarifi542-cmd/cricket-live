/**
 * ESPN match id -> series id mapping.
 * ----------------------------------------------------------------------------
 * ESPN's summary/playbyplay endpoints need BOTH the match id and its series
 * (league) id, but the app only carries the match id. ESPN's scoreboard feed
 * exposes both together, so every time we read the scoreboard we learn and
 * persist the link. Lookups go: in-memory LRU -> `provider_match_mappings`
 * table -> null. Persisting survives restarts (an in-memory-only cache would be
 * cold after a redeploy, breaking the first match-detail request).
 *
 * All DB access degrades to null on error so a mapping miss never throws — the
 * caller decides how to handle a missing series id.
 */
import { query } from '../../lib/db.js';
import logger from '../../lib/logger.js';

const PROVIDER_TYPE = 'cricinfo';
const LRU_MAX = 500;

// Simple insertion-ordered LRU: Map preserves insertion order, so we delete the
// oldest key when we exceed LRU_MAX and re-insert on hit to mark as recent.
const lru = new Map();

function lruGet(matchId) {
  if (!lru.has(matchId)) return undefined;
  const value = lru.get(matchId);
  lru.delete(matchId);
  lru.set(matchId, value);
  return value;
}

function lruSet(matchId, seriesId) {
  if (lru.has(matchId)) lru.delete(matchId);
  lru.set(matchId, seriesId);
  while (lru.size > LRU_MAX) {
    const oldest = lru.keys().next().value;
    lru.delete(oldest);
  }
}

/**
 * Resolve the series id for an ESPN match id. Checks the in-memory LRU, then the
 * persistent table. Returns null when unknown.
 * @param {string|number} matchId
 * @returns {Promise<string|null>}
 */
export async function getSeriesId(matchId) {
  const id = String(matchId || '').trim();
  if (!id) return null;

  const cached = lruGet(id);
  if (cached !== undefined) return cached;

  try {
    const rows = await query(
      `SELECT series_id FROM provider_match_mappings
        WHERE provider_type = ? AND match_id = ? LIMIT 1`,
      [PROVIDER_TYPE, id],
    );
    const seriesId = rows?.[0]?.series_id ? String(rows[0].series_id) : null;
    if (seriesId) lruSet(id, seriesId);
    return seriesId;
  } catch (err) {
    logger.debug({ msg: 'cricinfo match-map lookup failed', matchId: id, error: err.message });
    return null;
  }
}

/**
 * Persist a matchId -> seriesId mapping (upsert). No-op when either id is empty.
 * Updates the LRU immediately so a following read in the same tick hits memory.
 * @param {string|number} matchId
 * @param {string|number} seriesId
 * @returns {Promise<void>}
 */
export async function upsertMapping(matchId, seriesId) {
  const mId = String(matchId || '').trim();
  const sId = String(seriesId || '').trim();
  if (!mId || !sId) return;

  if (lruGet(mId) === sId) return; // already current in memory, skip the write
  lruSet(mId, sId);

  try {
    await query(
      `INSERT INTO provider_match_mappings (provider_type, match_id, series_id)
       VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE series_id = VALUES(series_id)`,
      [PROVIDER_TYPE, mId, sId],
    );
  } catch (err) {
    logger.debug({ msg: 'cricinfo match-map upsert failed', matchId: mId, seriesId: sId, error: err.message });
  }
}

/**
 * Bulk-record mappings from a list of {matchId, seriesId} pairs (e.g. after a
 * scoreboard fetch). Best-effort; individual failures are swallowed.
 * @param {Array<{matchId: string, seriesId: string}>} pairs
 */
export async function recordMappings(pairs = []) {
  for (const { matchId, seriesId } of pairs) {
    await upsertMapping(matchId, seriesId);
  }
}
