import axios from 'axios';
import logger from '../../lib/logger.js';
import { providerRequestDuration, providerErrorsTotal } from '../../lib/metrics.js';
import { getSeriesId, recordMappings } from './match-map.js';

/**
 * ESPN Cricinfo client — talks ONLY to ESPN's public site.api / site.web.api
 * JSON endpoints (the same ones espn.com's own pages call). No hs-consumer-api,
 * no TLS impersonation, no browser automation, no scraping. These endpoints
 * answer plain HTTPS GETs with a normal browser User-Agent.
 *
 * Backends used:
 *   site.web.api.espn.com/apis/v2/scoreboard/header?sport=cricket
 *       -> all current leagues + their events (the "today" match feed)
 *   site.api.espn.com/apis/site/v2/sports/cricket/{seriesId}/scoreboard
 *       -> a single league block + its events (series fixtures/standings)
 *   site.api.espn.com/apis/site/v2/sports/cricket/{seriesId}/summary?event={matchId}
 *       -> match header, rosters, notes, leaders
 *   site.api.espn.com/apis/site/v2/sports/cricket/{seriesId}/playbyplay?event={matchId}
 *       -> paginated ball-by-ball commentary
 *
 * ESPN match endpoints need BOTH matchId AND seriesId; the app only carries the
 * match id, so seriesId is resolved via the persistent match-map (populated from
 * every scoreboard fetch here).
 */

const JSON_HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
  Accept: 'application/json, text/plain, */*',
  'Accept-Language': 'en-US,en;q=0.9',
};

const siteApi = axios.create({
  baseURL: 'https://site.api.espn.com/apis/site/v2/sports/cricket',
  headers: JSON_HEADERS,
  timeout: 10000,
  decompress: true,
  maxRedirects: 5,
});

const siteWebApi = axios.create({
  baseURL: 'https://site.web.api.espn.com/apis/v2',
  headers: JSON_HEADERS,
  timeout: 10000,
  decompress: true,
  maxRedirects: 5,
});

async function fetchJson(client, path, params, context) {
  const start = Date.now();
  const url = `${client.defaults.baseURL || ''}${path}`;
  logger.debug({ msg: 'Cricinfo fetch start', context, url, params });
  try {
    const { data } = await client.get(path, { params });
    providerRequestDuration.observe(
      { provider: 'cricinfo', endpoint: context },
      (Date.now() - start) / 1000,
    );
    return data;
  } catch (err) {
    providerErrorsTotal.inc({ provider: 'cricinfo', error_type: 'fetch' });
    logger.warn({ msg: 'Cricinfo fetch failed', context, url, error: err.message });
    throw err;
  }
}

/**
 * Pull the global cricket scoreboard header (all current leagues + events) and
 * record every matchId -> seriesId link it exposes.
 * @returns {Promise<object>} raw ESPN scoreboard/header payload
 */
export async function getScoreboardHeader() {
  const data = await fetchJson(siteWebApi, '/scoreboard/header', { sport: 'cricket' }, 'scoreboardHeader');
  learnMappingsFromHeader(data);
  return data;
}

/**
 * Fetch a single league/series scoreboard (its events = fixtures). Records the
 * matchId -> seriesId links for that series too.
 * @param {string} seriesId
 */
export async function getSeriesScoreboard(seriesId) {
  const sid = String(seriesId || '').trim();
  if (!sid) throw new Error('cricinfo getSeriesScoreboard: seriesId required');
  const data = await fetchJson(siteApi, `/${sid}/scoreboard`, undefined, 'seriesScoreboard');
  learnMappingsFromLeagueBlock(data, sid);
  return data;
}

/**
 * Fetch a match summary (header + rosters + notes). Resolves seriesId from the
 * mapping table when not provided.
 * @param {string} matchId
 * @param {string} [seriesId]
 */
export async function getSummary(matchId, seriesId) {
  const mId = String(matchId || '').trim();
  if (!mId) throw new Error('cricinfo getSummary: matchId required');
  const sId = String(seriesId || '').trim() || (await getSeriesId(mId));
  if (!sId) throw new Error(`cricinfo getSummary: no seriesId known for match ${mId}`);
  return fetchJson(siteApi, `/${sId}/summary`, { event: mId }, 'summary');
}

/**
 * Fetch one page of ball-by-ball commentary.
 * @param {string} matchId
 * @param {string} [seriesId]
 * @param {number} [page]
 */
export async function getPlayByPlay(matchId, seriesId, page = 1) {
  const mId = String(matchId || '').trim();
  if (!mId) throw new Error('cricinfo getPlayByPlay: matchId required');
  const sId = String(seriesId || '').trim() || (await getSeriesId(mId));
  if (!sId) throw new Error(`cricinfo getPlayByPlay: no seriesId known for match ${mId}`);
  return fetchJson(siteApi, `/${sId}/playbyplay`, { event: mId, page }, 'playbyplay');
}

// --- mapping learners (best-effort, never throw) ---

function learnMappingsFromHeader(data) {
  try {
    const leagues = data?.sports?.[0]?.leagues || [];
    const pairs = [];
    for (const league of leagues) {
      const sId = String(league?.id || '');
      if (!sId) continue;
      for (const ev of league?.events || []) {
        const mId = String(ev?.id || '');
        if (mId) pairs.push({ matchId: mId, seriesId: sId });
      }
    }
    if (pairs.length) recordMappings(pairs).catch(() => {});
  } catch {
    /* ignore */
  }
}

function learnMappingsFromLeagueBlock(data, seriesId) {
  try {
    const leagues = data?.leagues || [];
    const events = data?.events || [];
    const sId =
      String(leagues?.[0]?.id || seriesId || '') || String(seriesId || '');
    const pairs = [];
    for (const ev of events) {
      const mId = String(ev?.id || '');
      if (mId && sId) pairs.push({ matchId: mId, seriesId: sId });
    }
    if (pairs.length) recordMappings(pairs).catch(() => {});
  } catch {
    /* ignore */
  }
}

export const cricinfoClient = {
  getScoreboardHeader,
  getSeriesScoreboard,
  getSummary,
  getPlayByPlay,
};
