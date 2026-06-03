import { query } from './db.js';
import { cacheSet, KEYS, TTL } from './redis.js';
import logger from './logger.js';

/**
 * Helpers for admin-controlled manual / test matches.
 * These merge seamlessly with provider (Cricbuzz) data so the Flutter
 * app never needs to know the difference.
 */

export async function fetchEnabledManualMatches({ status } = {}) {
  const sql = `SELECT * FROM manual_matches
               WHERE is_enabled = 1
                 AND (status = ? OR ? IS NULL)
               ORDER BY sort_order ASC, created_at DESC`;
  const rows = await query(sql, [status || null, status || null]).catch((err) => {
    logger.warn({ msg: 'manualMatches query failed', error: err.message });
    return [];
  });
  return rows;
}

export async function fetchManualMatchById(matchId) {
  if (!matchId) return null;
  const rows = await query(
    `SELECT * FROM manual_matches WHERE match_external_id = ? AND is_enabled = 1 LIMIT 1`,
    [String(matchId)],
  ).catch((err) => {
    logger.warn({ msg: 'manualMatch by id failed', matchId, error: err.message });
    return [];
  });
  return rows[0] || null;
}

/**
 * Convert a manual_matches DB row to the same shape used by
 * /matches/live and /matches/upcoming so enrichMatchListWithStreams
 * works without any changes.
 */
export function manualMatchToListItem(row) {
  if (!row) return null;
  const status = String(row.status || 'live').toLowerCase();
  const state = String(row.match_state || row.status || 'live').toLowerCase();
  const isLive = state === 'live' || state === 'in_progress';
  return {
    match_id: String(row.match_external_id),
    series_id: '',
    series_name: '',
    match_desc: row.title || '',
    match_format: 'T20',
    match_type: 'T20',
    status: isLive ? 'live' : status,
    status_text: isLive ? 'Live' : row.title || '',
    short_status: isLive ? 'Live' : status,
    team1: {
      id: '',
      name: row.team1_name || '',
      short_name: row.team1_short || '',
      logo_url: row.team1_logo_url || null,
    },
    team2: {
      id: '',
      name: row.team2_name || '',
      short_name: row.team2_short || '',
      logo_url: row.team2_logo_url || null,
    },
    venue: {
      name: row.venue || '',
      city: '',
      country: '',
    },
    start_time: row.start_time ? new Date(row.start_time).toISOString() : null,
    end_time: null,
    score: null,
    source: 'manual',
    isTest: !!row.is_test,
    isLive: isLive,
  };
}

/**
 * Convert a manual_matches DB row to the full match detail shape
 * expected by /match/:id and /app/match/:id.
 */
export function manualMatchToDetail(row) {
  if (!row) return null;
  const listItem = manualMatchToListItem(row);
  return {
    ...listItem,
    match_id: listItem.match_id,
    match_desc: listItem.match_desc,
    match_number: '',
    status: listItem.status,
    status_text: listItem.status_text,
    result: '',
    man_of_match: '',
    current_innings: 0,
    team1: listItem.team1,
    team2: listItem.team2,
    venue: listItem.venue,
    innings: [],
    current_batsmen: [],
    current_run_rate: 0,
    required_run_rate: 0,
    latest_performance: [],
    powerplay_data: [],
    last_updated: new Date().toISOString(),
    message: 'Admin-controlled test match',
  };
}

/**
 * Merge manual matches into an existing array of provider matches.
 * Prepend them so they appear at the top of lists.
 */
export async function mergeManualMatches(providerMatches = [], { status } = {}) {
  const manual = await fetchEnabledManualMatches({ status });
  const manualItems = manual.map(manualMatchToListItem).filter(Boolean);
  if (!manualItems.length) return providerMatches;
  return [...manualItems, ...(providerMatches || [])];
}

/**
 * Index a manual match summary into Redis so /match/:id fallback
 * lookups (getMatchSummary) can find it.
 */
export async function indexManualMatchSummary(row) {
  if (!row?.match_external_id) return;
  const item = manualMatchToListItem(row);
  try {
    await cacheSet(KEYS.matchSummary(item.match_id), item, TTL.MATCH_SUMMARY);
  } catch (e) {
    logger.debug({ msg: 'Failed to index manual match', matchId: item.match_id, error: e.message });
  }
}

/**
 * Re-index all enabled manual matches into Redis summaries.
 */
export async function reindexManualMatches() {
  const rows = await fetchEnabledManualMatches();
  for (const row of rows) {
    await indexManualMatchSummary(row);
  }
}
