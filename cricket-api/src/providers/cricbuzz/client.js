import axios from 'axios';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import logger from '../../lib/logger.js';
import { providerRequestDuration, providerErrorsTotal } from '../../lib/metrics.js';

// Full browser headers to mimic real Chrome browser
const BROWSER_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
  'Accept-Encoding': 'gzip, deflate, br',
  'Accept-Language': 'en-US,en;q=0.9',
  'Cache-Control': 'no-cache',
  'Pragma': 'no-cache',
  'Sec-Ch-Ua': '"Google Chrome";v="125", "Chromium";v="125", "Not.A/Brand";v="24"',
  'Sec-Ch-Ua-Mobile': '?0',
  'Sec-Ch-Ua-Platform': '"Windows"',
  'Sec-Fetch-Dest': 'document',
  'Sec-Fetch-Mode': 'navigate',
  'Sec-Fetch-Site': 'none',
  'Sec-Fetch-User': '?1',
  'Upgrade-Insecure-Requests': '1',
};

const JSON_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
  'Accept': 'application/json, text/plain, */*',
  'Accept-Encoding': 'gzip, deflate, br',
  'Accept-Language': 'en-US,en;q=0.9',
  'Cache-Control': 'no-cache',
  'Pragma': 'no-cache',
  'Sec-Ch-Ua': '"Google Chrome";v="125", "Chromium";v="125", "Not.A/Brand";v="24"',
  'Sec-Ch-Ua-Mobile': '?0',
  'Sec-Ch-Ua-Platform': '"Windows"',
  'X-Requested-With': 'XMLHttpRequest',
};

const mcenterClient = axios.create({
  baseURL: 'https://www.cricbuzz.com/api/mcenter',
  headers: JSON_HEADERS,
  timeout: 10000,
  decompress: true,
  maxRedirects: 5,
});

const apiClient = axios.create({
  baseURL: 'https://www.cricbuzz.com/api',
  headers: JSON_HEADERS,
  timeout: 15000,
  decompress: true,
  maxRedirects: 5,
});

const htmlClient = axios.create({
  baseURL: 'https://www.cricbuzz.com',
  headers: { 
    ...BROWSER_HEADERS,
    Referer: 'https://www.cricbuzz.com/',
  },
  timeout: 15000,
  decompress: true,
  maxRedirects: 5,
});

const DEBUG_DIR = path.resolve(process.cwd(), 'debug');

// Debug logging function for Cricbuz fetches
async function debugRequest(client, path, opts = {}, context = '') {
  const startTime = Date.now();
  const url = `${client.defaults.baseURL || ''}${path}`;
  
  logger.info({
    msg: 'Cricbuzz fetch start',
    context,
    url,
    method: 'GET',
    headers: opts.headers || client.defaults.headers,
  });
  
  try {
    const resp = await client.get(path, opts);
    const duration = Date.now() - startTime;
    
    const contentType = resp.headers?.['content-type'] || 'unknown';
    const isJson = contentType.includes('application/json');
    const isHtml = contentType.includes('text/html');
    
    // Extract title if HTML
    let title = null;
    if (isHtml && typeof resp.data === 'string') {
      const titleMatch = resp.data.match(/<title>([^<]*)<\/title>/i);
      title = titleMatch ? titleMatch[1] : 'No title found';
    }
    
    logger.info({
      msg: 'Cricbuzz fetch success',
      context,
      url: resp.config?.url || url,
      status: resp.status,
      contentType,
      isJson,
      isHtml,
      title,
      dataLength: typeof resp.data === 'string' ? resp.data.length : JSON.stringify(resp.data).length,
      duration,
      sample: isHtml && typeof resp.data === 'string' 
        ? resp.data.slice(0, 500).replace(/\s+/g, ' ')
        : (isJson ? JSON.stringify(resp.data).slice(0, 500) : 'N/A'),
    });
    
    return resp.data;
  } catch (err) {
    const duration = Date.now() - startTime;
    
    logger.error({
      msg: 'Cricbuzz fetch failed',
      context,
      url,
      error: err.message,
      code: err.code,
      status: err.response?.status,
      statusText: err.response?.statusText,
      responseData: err.response?.data?.slice?.(0, 500) || 'N/A',
      duration,
    });
    
    throw err;
  }
}

async function request(client, path, opts = {}) {
  const end = providerRequestDuration.startTimer({ provider: 'cricbuzz', endpoint: path });
  try {
    const resp = await client.get(path, opts);
    end({ status: 'success' });
    return resp.data;
  } catch (err) {
    end({ status: 'error' });
    providerErrorsTotal.inc({ provider: 'cricbuzz', error_type: err.code || 'unknown' });

    if (err.response) {
      logger.warn({
        msg: 'Cricbuzz API error',
        path,
        status: err.response.status,
        statusText: err.response.statusText,
      });
    } else {
      logger.error({ msg: 'Cricbuzz request failed', path, error: err.message });
    }
    throw err;
  }
}

async function saveDebugFile(fileName, content) {
  try {
    await mkdir(DEBUG_DIR, { recursive: true });
    const body = typeof content === 'string' ? content : JSON.stringify(content, null, 2);
    await writeFile(path.join(DEBUG_DIR, fileName), body || '', 'utf8');
  } catch (err) {
    logger.warn({ msg: 'Failed to save Cricbuzz debug file', fileName, error: err.message });
  }
}

function decodeHtmlEntities(text = '') {
  return String(text)
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

/**
 * Scrape a Cricbuzz HTML listing page and extract match IDs.
 */
async function scrapeMatchIds(htmlPath) {
  const html = await request(htmlClient, htmlPath, { responseType: 'text' });
  const ids = new Set();
  // Match IDs appear in URLs like /live-cricket-scores/152174/...
  const pattern = /\/live-cricket-scores\/(\d+)\//g;
  let m;
  while ((m = pattern.exec(html)) !== null) {
    ids.add(m[1]);
  }
  return [...ids];
}

/**
 * Fetch livescore data for a single match.
 * Note: /livescore/{matchId} does NOT return seriesId — only miniscore data.
 * The seriesId is tagged by getSeriesInfo based on which series page listed the match.
 */
async function fetchMatchLivescore(matchId) {
  const data = await request(mcenterClient, `/livescore/${matchId}`);
  return data;
}

/**
 * Cricbuzz API endpoints (mcenter JSON API + HTML scraping for listings).
 *
 * Working mcenter endpoints (www.cricbuzz.com/api/mcenter):
 *   /livescore/{matchId} — live score + miniscore
 *   /scorecard/{matchId} — full scorecard
 *   /comm/{matchId}     — ball-by-ball commentary
 *
 * HTML listing pages (scraped for match IDs):
 *   /cricket-match/live-scores              — live matches
 *   /cricket-match/live-scores/recent-matches   — recent matches
 *   /cricket-match/live-scores/upcoming-matches — upcoming matches
 */

/**
 * Fetch /api/home — returns all featured matches as clean JSON.
 */
async function fetchHomeMatches() {
  return request(apiClient, '/home');
}

export const cricbuzzApi = {
  // --- Match Listing APIs (using /api/home JSON endpoint) ---
  async getHomeMatches() {
    return fetchHomeMatches();
  },

  async getLiveMatches() {
    return fetchHomeMatches();
  },

  async getUpcomingMatches() {
    return fetchHomeMatches();
  },

  async getRecentMatches() {
    return fetchHomeMatches();
  },

  // --- Single Match APIs ---
  async getMatchInfo(matchId) {
    return request(mcenterClient, `/livescore/${matchId}`);
  },

  async getMatchHeader(matchId) {
    try {
      return await request(mcenterClient, `/${matchId}`);
    } catch {
      return null;
    }
  },

  async getQuickAccess(matchId) {
    try {
      return await request(mcenterClient, `/quick-access/${matchId}`);
    } catch {
      return null;
    }
  },

  async getScorecard(matchId, matchInfo = null) {
    // Try JSON API first
    let jsonData = null;
    try {
      jsonData = await request(mcenterClient, `/scorecard/${matchId}`);
      
      // Validate JSON response
      if (jsonData && jsonData.innings && jsonData.innings.length > 0) {
        logger.info({ msg: 'Scorecard JSON data found', matchId, innings: jsonData.innings.length });
        return jsonData;
      }
    } catch (jsonErr) {
      logger.warn({ msg: 'JSON scorecard failed, trying HTML fallback', matchId, error: jsonErr.message });
    }
    
    // JSON failed or empty, try HTML fallback
    try {
      // Build slug from match info if available
      let slug = 'scorecard';
      if (matchInfo && matchInfo.title) {
        slug = matchInfo.title.toLowerCase()
          .replace(/[^a-z0-9\s]/g, '')
          .replace(/\s+/g, '-')
          .slice(0, 50);
      }
      
      const html = await request(htmlClient, `/live-cricket-scorecard/${matchId}/${slug}`, { responseType: 'text' });
      const htmlData = parseScorecardFromHtml(html, matchId);
      
      if (htmlData.innings && htmlData.innings.length > 0) {
        logger.info({ msg: '[FIXED] Scorecard HTML data found', matchId, innings: htmlData.innings.length });
        return htmlData;
      }
    } catch (htmlErr) {
      logger.error({ msg: 'HTML scorecard fallback also failed', matchId, error: htmlErr.message });
    }
    
    // Both failed
    return { innings: [], _error: 'Scorecard not available' };
  },

  async getCommentary(matchId) {
    return request(mcenterClient, `/comm/${matchId}`);
  },

  // --- Series APIs (scrape HTML) ---
  async getSeriesList() {
    const html = await request(htmlClient, '/cricket-schedule/series', { responseType: 'text' });
    const series = [];
    const pattern = /\/cricket-series\/(\d+)\/([^/"]+)/g;
    const seen = new Set();
    let m;
    while ((m = pattern.exec(html)) !== null) {
      if (!seen.has(m[1])) {
        seen.add(m[1]);
        series.push({
          seriesId: m[1],
          seriesName: m[2].replace(/-/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()),
        });
      }
    }
    return { seriesMapProto: [{ series }] };
  },

  async getSeriesInfo(seriesId) {
    // Try JSON API first for reliable series-specific match data
    let seriesName = '';
    let matchIds = [];
    let scrapedMatches = [];

    try {
      const jsonData = await request(apiClient, `/cricket-series/${seriesId}`);
      // JSON API returns matchIdList and seriesName
      if (jsonData) {
        seriesName = jsonData.seriesName || jsonData.name || '';
        if (jsonData.matchIdList && Array.isArray(jsonData.matchIdList)) {
          matchIds = jsonData.matchIdList.map(String);
        }
      }
    } catch (jsonErr) {
      logger.warn({ msg: 'Series JSON API failed, falling back to HTML scraping', seriesId, error: jsonErr.message });
    }

    // Fallback to HTML scraping if JSON API returned no match IDs
    if (matchIds.length === 0) {
      try {
        const html = await request(htmlClient, `/cricket-series/${seriesId}/matches`, { responseType: 'text' });
        const titleMatch = html.match(/<title>([^<]*)<\/title>/i);
        if (titleMatch && !seriesName) {
          seriesName = (titleMatch[1] || '').split(/\s*[,|\-–]\s*/)[0].trim();
        }

        scrapedMatches = extractSeriesMatchesFromHtml(html, seriesId);
        if (scrapedMatches.length < 10) {
          const slug = buildSeriesSlugFromTitle(titleMatch?.[1] || seriesName);
          if (slug) {
            try {
              const slugHtml = await request(htmlClient, `/cricket-series/${seriesId}/${slug}/matches`, { responseType: 'text' });
              const slugMatches = extractSeriesMatchesFromHtml(slugHtml, seriesId);
              if (slugMatches.length > scrapedMatches.length) scrapedMatches = slugMatches;
            } catch (slugErr) {
              logger.debug({ msg: 'Series slug schedule scrape failed', seriesId, slug, error: slugErr.message });
            }
          }
        }
        if (scrapedMatches.length > 0) {
          const embeddedSeriesName = scrapedMatches.find((m) => m.matchInfo?.seriesName)?.matchInfo?.seriesName;
          if (embeddedSeriesName) seriesName = embeddedSeriesName;
          logger.info({ msg: 'Series embedded schedule parsed', seriesId, matches: scrapedMatches.length, seriesName });
        } else {
          await saveDebugFile(`series-${seriesId}.html`, html);
        }

        // Extract the series slug from the page to filter out sidebar/global matches.
        // Match URLs look like: /live-cricket-scores/152218/mi-vs-kkr-65th-match-indian-premier-league
        // We detect the slug from the page title or canonical links.
        // The page title is like "IPL | Indian Premier League 2026 schedule..."
        // We need to find the series name slug used in match URLs.
        
        // Strategy: Find all unique series slug suffixes from match URLs on the page,
        // then pick the most common one as the "real" series slug.
        const fullPattern = /\/live-cricket-scores\/(\d+)\/([^"'\s]+)/g;
        const allMatchUrls = [];
        const seen = new Set();
        let m;
        while ((m = fullPattern.exec(html)) !== null) {
          const matchId = m[1];
          const matchSlug = m[2].toLowerCase();
          if (!seen.has(matchId)) {
            seen.add(matchId);
            allMatchUrls.push({ matchId, matchSlug });
          }
        }

        // Extract the series-name part from each match URL slug
        // URL pattern: {teams}-{matchNum}-{match|t20i|odi|test}-{series-name-slug}
        // The series name is usually the last part after the match description
        // E.g., "mi-vs-kkr-65th-match-indian-premier-league" -> series part contains "indian-premier-league"
        // E.g., "nzw-vs-engw-1st-t20i-new-zealand-women..." -> different series
        
        // Use the FULL page title (not just the first segment) to build filter keywords
        // Title: "IPL | Indian Premier League 2026 schedule, live scores..."
        // We want keywords: ["ipl", "indian", "premier", "league"]
        const fullTitle = titleMatch ? titleMatch[1] : seriesName;
        const seriesKeywords = fullTitle
          .toLowerCase()
          .replace(/[^a-z0-9\s]/g, '')
          .split(/\s+/)
          .filter(w => w.length > 2 && !['the', 'and', 'for', 'schedule', 'live', 'scores', 'scorecards', 'points', 'table', 'videos', 'statistics', 'cricbuzzcom', 'cricbuzz', 'com', '2024', '2025', '2026', '2027'].includes(w));

        logger.info({ msg: 'Series keyword filter', seriesId, seriesName, seriesKeywords, totalUrlsFound: allMatchUrls.length });

        if (seriesKeywords.length > 0) {
          // Include match if its URL slug contains at least 2 series keywords (or 1 if only 1 keyword)
          const minKeywordMatches = seriesKeywords.includes('ipl') ? 1 : Math.min(2, seriesKeywords.length);
          for (const { matchId, matchSlug } of allMatchUrls) {
            const keywordsFound = seriesKeywords.filter(kw => matchSlug.includes(kw));
            if (keywordsFound.length >= minKeywordMatches) {
              matchIds.push(matchId);
            } else {
              logger.debug({ msg: 'Skipped non-series match', matchId, matchSlug, keywordsFound });
            }
          }
        } else {
          // No keywords from title — include all (fallback)
          for (const { matchId } of allMatchUrls) {
            matchIds.push(matchId);
          }
        }

        logger.info({ msg: 'HTML scrape results', seriesId, seriesName, seriesKeywords, totalScraped: seen.size, seriesMatches: matchIds.length });
      } catch (htmlErr) {
        logger.warn({ msg: 'Series HTML scraping also failed', seriesId, error: htmlErr.message });
      }
    }

    if (scrapedMatches.length > 0) {
      return { seriesId, seriesName, typeMatches: [{ seriesMatches: [{ seriesAdWrapper: { matches: scrapedMatches } }] }] };
    }

    // Fetch livescores for each match
    const results = await Promise.allSettled(
      matchIds.slice(0, 80).map((id) => fetchMatchLivescore(id)),
    );
    const matches = results
      .filter((r) => r.status === 'fulfilled' && r.value)
      .map((r) => buildMatchFromLivescore(r.value))
      .filter((m) => m !== null);

    // TAG matches with the series they were fetched from.
    // Cricbuzz livescore does NOT include seriesId, so we must tag based on
    // which Cricbuzz series page listed these match IDs. This is SOURCE-LEVEL
    // tagging, not route-level relabeling — these matches genuinely belong to this series.
    for (const m of matches) {
      if (m.matchInfo && (!m.matchInfo.seriesId || m.matchInfo.seriesId === '')) {
        m.matchInfo.seriesId = seriesId;
        m.matchInfo.seriesName = seriesName;
        m.matchInfo._taggedBySeriesPage = true;
      }
    }

    return { seriesId, seriesName, typeMatches: [{ seriesMatches: [{ seriesAdWrapper: { matches } }] }] };
  },

  async getPointsTable(seriesId) {
    const html = await request(htmlClient, `/cricket-series/${seriesId}/points-table`, { responseType: 'text' });
    
    try {
      // Use FIXED parser for better IPL points table extraction
      const pointsTableData = parsePointsTableFromHtml_FIXED(html, seriesId);
      
      // Validate: Don't return empty for IPL if data exists
      if ((!pointsTableData.pointsTable || pointsTableData.pointsTable.length === 0) && 
          (seriesId === '9241' || seriesId === 9241)) {
        logger.error({ msg: 'IPL points table returned empty', seriesId, htmlLength: html?.length });
        await saveDebugFile(`points-table-${seriesId}.html`, html);
      }
      
      return pointsTableData;
    } catch (err) {
      logger.error({ msg: 'Failed to parse points table HTML', seriesId, error: err.message });
      return { pointsTable: [], _error: err.message };
    }
  },

  // --- Player/Team (not available via mcenter, return minimal) ---
  async getPlayerInfo(playerId) {
    const html = await request(htmlClient, `/profiles/${playerId}`, { responseType: 'text' });
    return { player: { id: playerId }, _raw: html };
  },

  async getTeamInfo(teamId) {
    return { team: { teamId } };
  },

  // --- News APIs ---
  async getNewsStories(cursor = '138847') {
    return request(apiClient, `/cricket-news/${cursor}/all-stories`);
  },

  async getSeriesNews(seriesId, cursor) {
    const path = cursor
      ? `/cricket-series/paginate/news/${seriesId}/${cursor}`
      : `/cricket-series/paginate/news/${seriesId}/0`;
    return request(apiClient, path);
  },

  async getMatchNews(matchId, cursor) {
    const path = cursor
      ? `/mcenter/news/${matchId}/${cursor}`
      : `/mcenter/news/${matchId}/0`;
    return request(apiClient, path);
  },

  // --- Series Stats APIs ---
  async getSeriesStatsTypes(seriesId) {
    const data = await request(apiClient, `/cricket-series/series-stats/${seriesId}`);
    if (!data?.types?.length) await saveDebugFile(`stats-${seriesId}.json`, data || {});
    return data;
  },

  async getSeriesStatsTable(seriesId, statType) {
    const data = await request(apiClient, `/cricket-series/series-stats/${seriesId}/${statType}`);
    const statsKey = data && Object.keys(data).find((k) => k.endsWith('StatsList') || k.toLowerCase().includes('statslist'));
    if (!statsKey || !data?.[statsKey]?.values?.length) {
      await saveDebugFile(`stats-${seriesId}-${statType}.json`, data || {});
    }
    return data;
  },

  // --- Full Commentary ---
  async getFullCommentary(matchId, inningsId) {
    return request(mcenterClient, `/${matchId}/full-commentary/${inningsId}`);
  },

  // --- Match Highlights ---
  async getHighlights(matchId, inningsId) {
    return request(mcenterClient, `/highlights/${matchId}/${inningsId}`);
  },

  // --- Ball-by-ball Map ---
  async getBallsMap(matchId, inningsId) {
    return request(mcenterClient, `/balls-map/${matchId}/${inningsId}`);
  },

  // --- Over-by-over ---
  async getOverByOver(matchId, inningsId) {
    return request(mcenterClient, `/over-by-over/${matchId}/${inningsId}`);
  },

  // --- Upcoming Schedule ---
  async getUpcomingSchedule(type = 'all', timestamp) {
    const ts = timestamp || Date.now();
    return request(apiClient, `/cricket-schedule/upcoming-series/${type}/${ts}`);
  },

  // --- Match Squads (HTML scraping with FIX) ---
  async getMatchSquads(matchId) {
    const html = await request(htmlClient, `/cricket-match-squads/${matchId}`, { responseType: 'text' });
    
    try {
      // Use FIXED parser for better team name extraction and squad parsing
      const squadData = parseMatchSquadsFromHtml_FIXED(html, matchId);
      if (squadData?._parse_error || !squadData?._players_found) {
        await saveDebugFile(`squads-${matchId}.html`, html);
      }
      
      // Log validation results
      logger.info({ 
        msg: '[FIXED] Squad data parsed', 
        matchId, 
        team1: squadData.team1?.team_name,
        team2: squadData.team2?.team_name,
        playersFound: squadData._players_found,
        pageTitle: squadData.page_title
      });
      
      return squadData;
    } catch (err) {
      logger.error({ msg: 'Failed to parse match squads HTML', matchId, error: err.message });
      return { 
        match_id: String(matchId),
        team1: { team_name: 'Team 1', team_short: 'T1', playing_xi: [], bench: [], substitutes: [], impact_player: null },
        team2: { team_name: 'Team 2', team_short: 'T2', playing_xi: [], bench: [], substitutes: [], impact_player: null },
        support_staff: [],
        _parse_error: err.message
      };
    }
  },

  // --- Live Line (JSON aggregation from multiple endpoints) ---
  async getLiveLine(matchId) {
    try {
      // Fetch data from multiple endpoints in parallel
      const [livescore, commentary, ballsMap] = await Promise.allSettled([
        request(mcenterClient, `/livescore/${matchId}`),
        request(mcenterClient, `/comm/${matchId}`),
        request(mcenterClient, `/balls-map/${matchId}/1`).catch(() => null), // Default to innings 1
      ]);

      const liveData = livescore.status === 'fulfilled' ? livescore.value : null;
      const commData = commentary.status === 'fulfilled' ? commentary.value : null;
      const ballsData = ballsMap.status === 'fulfilled' ? ballsMap.value : null;

      if (!liveData) {
        return null;
      }

      return buildLiveLineData(liveData, commData, ballsData, matchId);
    } catch (err) {
      logger.error({ msg: 'Failed to build live line data', matchId, error: err.message });
      return null;
    }
  },

  // --- Match Info Detailed (JSON from mcenter + HTML fallback) ---
  async getMatchInfoDetailed(matchId) {
    try {
      // Try to get match info from mcenter first
      const matchInfo = await request(mcenterClient, `/${matchId}`);
      if (matchInfo) {
        return matchInfo;
      }
    } catch (err) {
      logger.warn({ msg: 'mcenter match info failed, trying HTML fallback', matchId, error: err.message });
    }
    
    // HTML fallback if API fails
    try {
      const html = await request(htmlClient, `/live-cricket-scores/${matchId}`, { responseType: 'text' });
      return parseMatchInfoFromHtml(html, matchId);
    } catch (err) {
      logger.warn({ msg: 'Failed to parse match info HTML', matchId, error: err.message });
      return null;
    }
  },

  // --- Series Teams (from series matches JSON) ---
  async getSeriesTeams(seriesId) {
    try {
      // Get series matches and extract teams
      const seriesData = await this.getSeriesInfo(seriesId);
      return seriesData;
    } catch (err) {
      logger.warn({ msg: 'Failed to fetch series teams', seriesId, error: err.message });
      return { teams: [] };
    }
  },
};

function decodeNextPayloadText(html = '') {
  return String(html)
    .replace(/\\"/g, '"')
    .replace(/\\u0026/g, '&')
    .replace(/\\\//g, '/');
}

function extractJsonObjectAt(text, startIndex) {
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = startIndex; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }
    if (ch === '"') {
      inString = true;
    } else if (ch === '{') {
      depth++;
    } else if (ch === '}') {
      depth--;
      if (depth === 0) return text.slice(startIndex, i + 1);
    }
  }
  return null;
}

function extractSeriesMatchesFromHtml(html, seriesId) {
  const text = decodeNextPayloadText(html);
  const matches = [];
  const seen = new Set();
  let cursor = 0;

  while (cursor < text.length) {
    const keyIndex = text.indexOf('"matchInfo":{', cursor);
    if (keyIndex === -1) break;
    const infoStart = text.indexOf('{', keyIndex);
    const infoJson = extractJsonObjectAt(text, infoStart);
    cursor = infoStart + Math.max(infoJson?.length || 1, 1);
    if (!infoJson) continue;

    try {
      const matchInfo = JSON.parse(infoJson);
      if (!matchInfo?.matchId || seen.has(String(matchInfo.matchId))) continue;
      if (String(matchInfo.seriesId || '') !== String(seriesId)) continue;

      const nextMatchIndex = text.indexOf('"matchInfo":{', cursor);
      const scoreKeyIndex = text.indexOf('"matchScore":{', cursor);
      let matchScore = {};
      if (scoreKeyIndex !== -1 && (nextMatchIndex === -1 || scoreKeyIndex < nextMatchIndex)) {
        const scoreStart = text.indexOf('{', scoreKeyIndex);
        const scoreJson = extractJsonObjectAt(text, scoreStart);
        if (scoreJson) {
          try {
            matchScore = JSON.parse(scoreJson);
          } catch {
            matchScore = {};
          }
        }
      }

      seen.add(String(matchInfo.matchId));
      matches.push({ matchInfo, matchScore });
    } catch (err) {
      logger.debug({ msg: 'Skipped malformed embedded match JSON', seriesId, error: err.message });
    }
  }

  return matches.sort((a, b) => Number(a.matchInfo?.startDate || 0) - Number(b.matchInfo?.startDate || 0));
}

function buildSeriesSlugFromTitle(title = '') {
  const primary = String(title).split('|')[1] || String(title).split('|')[0] || '';
  return primary
    .toLowerCase()
    .replace(/cricbuzz\.com|schedule|live scores|scorecards|points table|videos|statistics|results/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

/**
 * Build a matchInfo-compatible object from mcenter livescore response.
 */
function buildMatchFromLivescore(data) {
  const header = data.matchHeader || {};
  const score = data.miniscore?.matchScoreDetails || data.matchScoreDetails || {};
  const innings = score.inningsScoreList || [];
  const matchTeamInfo = score.matchTeamInfo || [];
  
  const matchId = header.matchId || score.matchId || data.matchId;
  if (!matchId) {
    return null;
  }

  let team1 = header.team1 || {};
  let team2 = header.team2 || {};
  
  if (matchTeamInfo.length >= 1 && (!team1.teamId && !team1.id)) {
    const info = matchTeamInfo[0];
    team1 = {
      id: info.battingTeamId,
      name: info.battingTeamShortName,
      shortName: info.battingTeamShortName,
    };
    team2 = {
      id: info.bowlingTeamId,
      name: info.bowlingTeamShortName,
      shortName: info.bowlingTeamShortName,
    };
  }

  const team1Score = {};
  const team2Score = {};
  const t1Id = team1.id;
  const t2Id = team2.id;

  for (const inn of innings) {
    const target = inn.batTeamId === t1Id ? team1Score : team2Score;
    if (!target.inngs) target.inngs = [];
    target.inngs.push({
      runs: inn.score,
      wickets: inn.wickets,
      overs: inn.overs,
      isDeclared: inn.isDeclared,
      isFollowOn: inn.isFollowOn,
    });
  }

  // ONLY use the ORIGINAL seriesId/seriesName from the livescore response.
  // NEVER inject or override from the requested series.
  return {
    matchInfo: {
      matchId: matchId,
      seriesId: header.seriesId || score.seriesId || '',
      seriesName: header.seriesName || header.seriesDesc || score.seriesName || '',
      matchDesc: header.matchDescription || header.matchDesc || '',
      matchFormat: header.matchFormat || score.matchFormat || '',
      matchType: header.matchType || '',
      matchImageId: header.matchImageId || null,
      state: score.state || header.state || '',
      status: score.customStatus || header.status || '',
      stateTitle: header.status || '',
      team1: {
        teamId: team1.teamId || team1.id,
        teamName: team1.teamName || team1.name,
        teamSName: team1.teamSName || team1.shortName,
        imageId: team1.imageId || null,
      },
      team2: {
        teamId: team2.teamId || team2.id,
        teamName: team2.teamName || team2.name,
        teamSName: team2.teamSName || team2.shortName,
        imageId: team2.imageId || null,
      },
      team1Score,
      team2Score,
      venueInfo: header.venue || header.venueInfo || {},
      startDate: header.matchStartTimestamp ? String(header.matchStartTimestamp) : null,
      endDate: header.matchCompleteTimestamp ? String(header.matchCompleteTimestamp) : null,
      tossResults: score.tossResults || header.tossResults || {},
      currInnings: data.miniscore?.inningsId || 0,
      result: header.result?.resultType || header.status || '',
      playersOfTheMatch: header.playersOfTheMatch || [],
    },
  };
}

/**
 * Parse points table from Cricbuzz HTML page.
 * Extracts team standings data from the HTML table structure.
 * Uses multiple strategies to handle different Cricbuzz page layouts.
 */
function parsePointsTableFromHtml(html, seriesId) {
  const pointsTableInfo = [];
  
  // Log the start of parsing for debugging
  logger.info({ msg: 'Parsing points table HTML', seriesId, htmlLength: html?.length || 0 });
  
  // Strategy 1: Look for cb-srs-pnts class patterns (most common in Cricbuzz)
  let tbodyContent = null;
  
  // Try multiple table class patterns
  const tablePatterns = [
    /class="[^"]*cb-srs-pnts[^"]*"[\s\S]*?<tbody[^>]*>([\s\S]*?)<\/tbody>/i,
    /class="[^"]*cb-srs-pnts-tble[^"]*"[\s\S]*?<tbody[^>]*>([\s\S]*?)<\/tbody>/i,
    /<table[^>]*class="[^"]*points[^"]*"[^>]*>[\s\S]*?<tbody[^>]*>([\s\S]*?)<\/tbody>/i,
    /<table[^>]*class="[^"]*standings[^"]*"[^>]*>[\s\S]*?<tbody[^>]*>([\s\S]*?)<\/tbody>/i,
    /<div[^>]*class="[^"]*cb-srs-pnts[^"]*"[^>]*>([\s\S]*?)<\/div>/i,
    /<section[^>]*class="[^"]*points-table[^"]*"[^>]*>([\s\S]*?)<\/section>/i,
  ];
  
  for (const pattern of tablePatterns) {
    const match = html.match(pattern);
    if (match) {
      tbodyContent = match[1];
      logger.info({ msg: 'Found points table using pattern', seriesId, pattern: pattern.toString().slice(0, 50) });
      break;
    }
  }
  
  // Strategy 2: If no table found, look for div-based points table structure
  if (!tbodyContent) {
    // Look for div rows with team data
    const divRowPattern = /<div[^>]*class="[^"]*cb-srs-pnts[^"]*"[^>]*>[\s\S]*?<div[^>]*class="[^"]*cb-col[^"]*"[^>]*>([\s\S]*?)<\/div>/gi;
    const divRows = [];
    let divMatch;
    while ((divMatch = divRowPattern.exec(html)) !== null) {
      divRows.push(divMatch[0]);
    }
    if (divRows.length > 0) {
      tbodyContent = divRows.join('\n');
      logger.info({ msg: 'Found div-based points table', seriesId, rows: divRows.length });
    }
  }
  
  // Strategy 3: Generic table search
  if (!tbodyContent) {
    // Find any table that has team-like content (numbers followed by team names)
    const allTables = html.match(/<table[^>]*>[\s\S]*?<\/table>/gi) || [];
    for (const table of allTables) {
      if (table.includes('P') && table.includes('W') && table.includes('Pts')) {
        const tbodyMatch = table.match(/<tbody[^>]*>([\s\S]*?)<\/tbody>/i);
        if (tbodyMatch) {
          tbodyContent = tbodyMatch[1];
          logger.info({ msg: 'Found generic points table', seriesId });
          break;
        }
      }
    }
  }
  
  if (!tbodyContent) {
    logger.warn({ msg: 'Could not find points table in HTML - trying to extract from raw content', seriesId, htmlSample: html.slice(0, 500) });
    return { pointsTable: [] };
  }
  
  // Try to parse table rows
  let rowsParsed = 0;
  
  // First try standard table row parsing
  const rowRegex = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
  let rowMatch;
  let position = 1;
  
  while ((rowMatch = rowRegex.exec(tbodyContent)) !== null) {
    const rowHtml = rowMatch[1];
    
    // Extract all cells from the row
    const cellRegex = /<td[^>]*>([\s\S]*?)<\/td>/gi;
    const cells = [];
    let cellMatch;
    
    while ((cellMatch = cellRegex.exec(rowHtml)) !== null) {
      // Clean up cell content - remove HTML tags and decode entities
      let cellContent = cellMatch[1]
        .replace(/<[^>]+>/g, ' ') // Remove HTML tags
        .replace(/&nbsp;/gi, ' ')  // Replace &nbsp; with space
        .replace(/\s+/g, ' ')     // Normalize whitespace
        .trim();
      cells.push(cellContent);
    }
    
    // Standard Cricbuzz points table format: [Rank/Position, Team, P, W, L, T, NR, NRR, Pts]
    // Some tables may have: [Team, P, W, L, T, NR, NRR, Pts] without explicit rank column
    if (cells.length >= 7) {
      let teamName = '';
      let teamShort = '';
      let played = 0;
      let won = 0;
      let lost = 0;
      let tied = 0;
      let noResult = 0;
      let nrr = 0;
      let points = 0;
      
      // Check if first column is position number or team name
      const firstCol = cells[0];
      const isPositionColumn = /^\d+$/.test(firstCol);
      
      if (isPositionColumn) {
        position = parseInt(firstCol, 10) || position;
        teamName = cells[1];
        played = parseInt(cells[2], 10) || 0;
        won = parseInt(cells[3], 10) || 0;
        lost = parseInt(cells[4], 10) || 0;
        tied = parseInt(cells[5], 10) || 0;
        noResult = parseInt(cells[6], 10) || 0;
        nrr = parseFloat(cells[7]) || 0;
        points = parseInt(cells[8], 10) || 0;
      } else {
        // First column is team name
        teamName = cells[0];
        played = parseInt(cells[1], 10) || 0;
        won = parseInt(cells[2], 10) || 0;
        lost = parseInt(cells[3], 10) || 0;
        tied = parseInt(cells[4], 10) || 0;
        noResult = parseInt(cells[5], 10) || 0;
        nrr = parseFloat(cells[6]) || 0;
        points = parseInt(cells[7], 10) || 0;
      }
      
      // Extract team short name from team cell (often in parentheses or after dash)
      const shortMatch = teamName.match(/\(([A-Z]+)\)$/) || teamName.match(/- ([A-Z]+)$/);
      teamShort = shortMatch ? shortMatch[1] : teamName.split(' ').map(w => w[0]).join('').toUpperCase();
      
      // Clean team name - remove short name in parentheses
      teamName = teamName.replace(/\s*\([A-Z]+\)$/, '').replace(/\s+-\s+[A-Z]+$/, '').trim();
      
      // Try to extract team ID from any links in the row
      const teamIdMatch = rowHtml.match(/\/cricket-team\/([\d]+)\//) || rowHtml.match(/teamId[=\"\']+(\d+)/);
      const teamId = teamIdMatch ? teamIdMatch[1] : '';
      
      // Check for qualification status indicators in the row
      const isQualified = rowHtml.includes('cb-srs-pnts-qualified') || 
                          rowHtml.includes('Q') ||
                          rowHtml.toLowerCase().includes('qualified');
      
      if (teamName && played > 0) {
        pointsTableInfo.push({
          teamId: String(teamId),
          teamFullName: teamName,
          teamShortName: teamShort,
          position: position,
          matchesPlayed: played,
          matchesWon: won,
          matchesLost: lost,
          matchesTied: tied,
          noResult: noResult,
          nrr: nrr,
          points: points,
          isQualified: isQualified,
        });
        position++;
      }
    }
  }
  
  logger.info({ 
    msg: 'Parsed points table from HTML', 
    seriesId, 
    teamsFound: pointsTableInfo.length 
  });
  
  return {
    pointsTable: [{
      groupName: '',
      pointsTableInfo: pointsTableInfo,
    }],
  };
}

/**
 * Parse match squads from Cricbuzz HTML page.
 * Extracts Playing XI, Bench, and Impact Player for both teams.
 * Uses multiple strategies to handle different Cricbuzz page layouts.
 */
function parseMatchSquadsFromHtml(html, matchId) {
  logger.info({ msg: 'Parsing match squads HTML', matchId, htmlLength: html?.length || 0 });
  
  // Strategy 1: Look for team squad sections with modern Cricbuzz structure
  // Team sections often have class like "cb-match-sqd" or similar
  
  // Find all team sections
  const teamSectionPatterns = [
    /<div[^>]*class="[^"]*cb-match-sqd[^"]*"[^>]*>([\s\S]*?)<\/div>\s*<div[^>]*class="[^"]*cb-match-sqd[^"]*"[^>]*>([\s\S]*?)<\/div>/i,
    /<div[^>]*class="[^"]*cb-squad[^"]*"[^>]*>([\s\S]*?)<\/div>\s*<div[^>]*class="[^"]*cb-squad[^"]*"[^>]*>([\s\S]*?)<\/div>/i,
    /<section[^>]*class="[^"]*squad[^"]*"[^>]*>([\s\S]*?)<\/section>/gi,
  ];
  
  // Strategy 2: Look for team names in headers first
  let teamNames = [];
  
  // Try to extract from page title
  const titleMatch = html.match(/<title>([^<]*)<\/title>/i);
  if (titleMatch) {
    const title = titleMatch[1].replace(/\s+/g, ' ').trim();
    // Common patterns: "Team A vs Team B, Match Squads" or "Team A vs Team B Match Squads"
    const vsPatterns = [
      /(.+?)\s+(?:vs|VS|v\.s\.|\(v\.s\.\))\s+(.+?)\s*,?\s*(?:Match|Squads|Playing XI)/i,
      /(.+?)\s+(?:vs|VS|v\.s\.)\s+(.+?)\s+-\s*Cricbuzz/i,
      /^([A-Z][a-zA-Z\s]+?)\s+vs\s+([A-Z][a-zA-Z\s]+?)\s+\d/,
    ];
    
    for (const pattern of vsPatterns) {
      const vsMatch = title.match(pattern);
      if (vsMatch) {
        teamNames = [vsMatch[1].trim(), vsMatch[2].trim()];
        logger.info({ msg: 'Found team names from title', matchId, teamNames });
        break;
      }
    }
  }
  
  // If not found in title, try h2/h3 headers
  if (teamNames.length < 2) {
    const headerPatterns = [
      /<h[23][^>]*class="[^"]*cb-match-sqd-text[^"]*"[^>]*>([\s\S]*?)<\/h[23]>/gi,
      /<h[23][^>]*class="[^"]*cb-font-[^"]*"[^>]*>([\s\S]*?)<\/h[23]>/gi,
      /<h[23][^>]*>([\s\S]*?)<\/h[23]>/gi,
    ];
    
    for (const pattern of headerPatterns) {
      const matches = [...html.matchAll(pattern)];
      for (const match of matches) {
        const headerText = match[1].replace(/<[^>]+>/g, '').trim();
        // Skip generic headers and keep team-like names
        if (headerText && 
            headerText.length > 2 && 
            headerText.length < 60 &&
            !headerText.toLowerCase().includes('playing xi') &&
            !headerText.toLowerCase().includes('bench') &&
            !headerText.toLowerCase().includes('impact') &&
            !headerText.toLowerCase().includes('squad') &&
            !headerText.toLowerCase().includes('cricbuzz')) {
          teamNames.push(headerText);
          if (teamNames.length >= 2) break;
        }
      }
      if (teamNames.length >= 2) break;
    }
  }
  
  // Strategy 3: Find player sections
  // Look for player list containers
  const playerListPatterns = [
    /<div[^>]*class="[^"]*cb-col-100[^"]*cb-match-sqd-list[^"]*"[^>]*>([\s\S]*?)<\/div>/gi,
    /<div[^>]*class="[^"]*cb-list-item[^"]*"[^>]*>([\s\S]*?)<\/div>/gi,
    /<div[^>]*class="[^"]*cb-player[^"]*"[^>]*>([\s\S]*?)<\/div>/gi,
  ];
  
  let allPlayerElements = [];
  
  for (const pattern of playerListPatterns) {
    const matches = [...html.matchAll(pattern)];
    if (matches.length > 0) {
      allPlayerElements = matches.map(m => m[0]);
      logger.info({ msg: 'Found player elements', matchId, count: allPlayerElements.length, pattern: pattern.toString().slice(0, 30) });
      break;
    }
  }
  
  // Strategy 4: Parse individual players from elements or raw HTML
  const players = [];
  
  if (allPlayerElements.length > 0) {
    // Parse from found elements
    for (const playerHtml of allPlayerElements) {
      const player = parsePlayerFromHtml(playerHtml);
      if (player && player.name) {
        players.push(player);
      }
    }
  } else {
    // Fallback: Search raw HTML for player patterns
    // Look for profile links which indicate players
    const profilePattern = /<a[^>]*href="[^"]*\/profiles\/(\d+)\/[^"]*"[^>]*>([\s\S]*?)<\/a>/gi;
    let profileMatch;
    while ((profileMatch = profilePattern.exec(html)) !== null) {
      const playerId = profileMatch[1];
      const nameHtml = profileMatch[2];
      const playerName = nameHtml.replace(/<[^>]+>/g, '').trim();
      
      if (playerName && playerName.length > 2) {
        // Get surrounding context for captain/wk detection
        const contextStart = Math.max(0, profileMatch.index - 100);
        const contextEnd = Math.min(html.length, profileMatch.index + 200);
        const context = html.slice(contextStart, contextEnd);
        
        players.push({
          playerId: String(playerId),
          name: playerName,
          role: extractPlayerRole(context),
          isCaptain: context.includes('(c)') || context.includes('(C)') || context.toLowerCase().includes('captain'),
          isWicketkeeper: context.includes('(wk)') || context.includes('(WK)') || context.toLowerCase().includes('wicketkeeper'),
        });
      }
    }
  }
  
  logger.info({ msg: 'Parsed players', matchId, totalPlayers: players.length });
  
  // If no players found, return safe empty structure
  if (players.length === 0) {
    logger.warn({ msg: 'No players found in squad HTML', matchId, htmlSample: html.slice(0, 300) });
    return {
      team1: { teamName: 'Team 1', teamShort: 'T1', playingXi: [], bench: [], impactPlayer: null },
      team2: { teamName: 'Team 2', teamShort: 'T2', playingXi: [], bench: [], impactPlayer: null },
    };
  }
  
  // If we couldn't get team names, use defaults
  if (teamNames.length < 2) {
    teamNames = ['Team 1', 'Team 2'];
  }
  
  // Split players between teams
  // Strategy: Look for section markers or split evenly
  const midpoint = Math.ceil(players.length / 2);
  const team1Players = players.slice(0, midpoint);
  const team2Players = players.slice(midpoint);
  
  // Separate playing XI from bench
  // First 11 of each team are playing XI (if available)
  const playingXiSize = 11;
  
  return {
    team1: {
      teamName: teamNames[0],
      teamShort: generateShortName(teamNames[0]),
      playingXi: team1Players.slice(0, playingXiSize),
      bench: team1Players.slice(playingXiSize),
      impactPlayer: null, // Will be populated if found
    },
    team2: {
      teamName: teamNames[1] || 'Team 2',
      teamShort: generateShortName(teamNames[1] || 'Team 2'),
      playingXi: team2Players.slice(0, playingXiSize),
      bench: team2Players.slice(playingXiSize),
      impactPlayer: null,
    },
  };
}

/**
 * Parse a single player from HTML element
 */
function parsePlayerFromHtml(playerHtml) {
  // Extract player name
  const namePatterns = [
    /<a[^>]*href="[^"]*\/profiles\/\d+\/[^"]*"[^>]*>([\s\S]*?)<\/a>/i,
    /<span[^>]*class="[^"]*player-name[^"]*"[^>]*>([\s\S]*?)<\/span>/i,
    /<div[^>]*class="[^"]*player-name[^"]*"[^>]*>([\s\S]*?)<\/div>/i,
  ];
  
  let playerName = '';
  let playerId = '';
  
  for (const pattern of namePatterns) {
    const match = playerHtml.match(pattern);
    if (match) {
      playerName = match[1].replace(/<[^>]+>/g, '').trim();
      // Extract ID from profile link
      const idMatch = match[0].match(/\/profiles\/(\d+)\//);
      if (idMatch) playerId = idMatch[1];
      break;
    }
  }
  
  if (!playerName) return null;
  
  // Check for captain/wicketkeeper
  const isCaptain = playerHtml.includes('(c)') || playerHtml.includes('(C)') || 
                    playerHtml.toLowerCase().includes('captain');
  const isWicketkeeper = playerHtml.includes('(wk)') || playerHtml.includes('(WK)') || 
                         playerHtml.toLowerCase().includes('wicketkeeper');
  
  // Extract role
  const role = extractPlayerRole(playerHtml);
  
  return {
    playerId: String(playerId),
    name: playerName,
    role,
    isCaptain,
    isWicketkeeper,
  };
}

/**
 * Extract player role from HTML context
 */
function extractPlayerRole(html) {
  const rolePatterns = [
    /(Batsman|Bowler|All-rounder|Wicketkeeper)[\s\w-]*/i,
    /class="[^"]*role[^"]*"[^>]*>([\s\S]*?)<\/\w+>/i,
  ];
  
  for (const pattern of rolePatterns) {
    const match = html.match(pattern);
    if (match) {
      return match[1].replace(/-/g, ' ').trim();
    }
  }
  
  return '';
}

/**
 * Generate short name from full team name
 */
function generateShortName(teamName) {
  if (!teamName) return 'TBD';
  
  // Remove common suffixes
  const cleanName = teamName
    .replace(/^(?:The|Team)\s+/i, '')
    .replace(/\s+(?: cricket|team|xi)$/i, '');
  
  // Get initials
  const words = cleanName.split(/\s+/);
  if (words.length === 1) {
    return words[0].slice(0, 3).toUpperCase();
  }
  
  return words.map(w => w[0]).join('').toUpperCase().slice(0, 3);
}

/**
 * Build enhanced live line data from multiple Cricbuzz API sources.
 * Aggregates livescore, commentary, and balls-map data.
 */
function buildLiveLineData(liveData, commData, ballsData, matchId) {
  const header = liveData.matchHeader || {};
  const miniscore = liveData.miniscore || {};
  const scoreDetails = miniscore.matchScoreDetails || {};
  const inningsList = scoreDetails.inningsScoreList || [];
  
  // Determine current innings
  const currentInningsId = miniscore.inningsId || 1;
  const currentInnings = inningsList.find(i => i.inningsId === currentInningsId) || inningsList[0] || {};
  
  // Get batting team info
  const batTeamId = currentInnings.batTeamId || currentInnings.battingTeamId || miniscore.batTeamId || miniscore.battingTeamId;
  const teamIdOf = (team) => String(team?.id || team?.teamId || '');
  const teamInfo = scoreDetails.matchTeamInfo?.find((t) => String(t.battingTeamId) === String(batTeamId)) || scoreDetails.matchTeamInfo?.[0] || null;
  const batTeam = teamIdOf(header.team1) === String(batTeamId)
    ? header.team1
    : (teamIdOf(header.team2) === String(batTeamId) ? header.team2 : (teamInfo ? {
      teamId: teamInfo.battingTeamId,
      teamName: teamInfo.battingTeamName || teamInfo.battingTeamShortName || currentInnings.batTeamName,
      teamSName: teamInfo.battingTeamShortName || currentInnings.batTeamName,
    } : null));
  const bowlTeam = teamIdOf(header.team1) === String(batTeamId)
    ? header.team2
    : (teamIdOf(header.team2) === String(batTeamId) ? header.team1 : (teamInfo ? {
      teamId: teamInfo.bowlingTeamId,
      teamName: teamInfo.bowlingTeamName || teamInfo.bowlingTeamShortName,
      teamSName: teamInfo.bowlingTeamShortName,
    } : null));
  
  // Current score
  const currentScore = {
    runs: currentInnings.score || 0,
    wickets: currentInnings.wickets || 0,
    overs: currentInnings.overs || '0.0',
  };
  
  // Target and calculations
  const target = scoreDetails.target || null;
  const runsNeeded = target ? target - currentScore.runs : null;
  const ballsRemaining = target ? calculateBallsRemaining(currentScore.overs, target, inningsList) : null;
  const crr = currentInnings.runRate || miniscore.currentRunRate || 0;
  const rrr = runsNeeded !== null && ballsRemaining !== null && ballsRemaining > 0
    ? ((runsNeeded / ballsRemaining) * 6).toFixed(2)
    : null;
  
  // Get latest ball data from balls-map
  const latestBall = extractLatestBall(ballsData, currentInningsId, commData);
  
  // Get recent balls from recentOvsStats
  const recentOvsStats = miniscore.recentOvsStats || '';
  const recentBalls = recentOvsStats ? recentOvsStats.split(/\s+/).filter(s => s && s !== '|') : [];
  
  // Current over balls (balls in the current over)
  const currentOver = latestBall ? recentBalls.slice(-Number(latestBall.ballNumber || 0)) : [];
  
  // Batsmen info
  const batsmen = miniscore.batsmanStriker && miniscore.batsmanNonStriker 
    ? [miniscore.batsmanStriker, miniscore.batsmanNonStriker]
    : [];
  const striker = batsmen[0] || null;
  const nonStriker = batsmen[1] || null;
  
  // Bowler info
  const bowler = miniscore.bowlerStriker || null;
  
  // Partnership
  const partnership = miniscore.partnership || null;
  
  // Last wicket
  const lastWicket = miniscore.lastWicket || null;
  
  // Win probability (not available from Cricbuzz, set to null)
  const winProbability = null;
  
  // Build unique key for latest ball (for Flutter animation)
  // Format: matchId-innings-over.ball-score-wickets-result
  const latestBallKey = latestBall 
    ? `${matchId}-${currentInningsId}-${latestBall.overNumber}.${latestBall.ballNumber}-${currentScore.runs}-${currentScore.wickets}-${latestBall.event}`
    : `${matchId}-${currentInningsId}-0.0-0-0-NONE`;
  
  return {
    matchId: String(matchId),
    status: scoreDetails.status || header.status || 'unknown',
    innings: currentInningsId,
    battingTeam: batTeam ? {
      id: String(batTeam.id || batTeam.teamId || ''),
      name: batTeam.name || batTeam.teamName || '',
      shortName: batTeam.shortName || batTeam.teamSName || '',
      score: `${currentScore.runs}/${currentScore.wickets}`,
      overs: String(currentScore.overs),
    } : null,
    bowlingTeam: bowlTeam ? {
      id: String(bowlTeam.id || bowlTeam.teamId || ''),
      name: bowlTeam.name || bowlTeam.teamName || '',
      shortName: bowlTeam.shortName || bowlTeam.teamSName || '',
    } : null,
    target: target,
    runsNeeded: runsNeeded,
    ballsRemaining: ballsRemaining,
    crr: parseFloat(crr) || 0,
    rrr: rrr ? parseFloat(rrr) : null,
    latestBall: latestBall ? {
      key: latestBallKey,
      over: latestBall.overNumber || 0,
      ball: latestBall.ballNumber || 0,
      result: latestBall.event === 'WICKET' ? 'W' : 
              latestBall.event === 'FOUR' ? '4' : 
              latestBall.event === 'SIX' ? '6' : 
              String(latestBall.runs || 0),
      commentary: latestBall.commentary || '',
      batsman: latestBall.batsman || '',
      bowler: latestBall.bowler || '',
      scoreAfter: `${latestBall.scoreAfter || currentScore.runs}/${latestBall.wicketsAfter || currentScore.wickets}`,
      wicketsAfter: latestBall.wicketsAfter || currentScore.wickets,
      isBoundary: latestBall.isBoundary || false,
      isWicket: latestBall.isWicket || false,
      isWide: latestBall.isWide || false,
      isNoBall: latestBall.isNoBall || false,
      timestamp: latestBall.timestamp || Date.now(),
    } : null,
    recentBalls: recentBalls,
    currentOverBalls: currentOver,
    currentOver: currentOver,
    striker: striker ? {
      name: striker.batName || striker.name || '',
      runs: striker.batRuns || striker.runs || 0,
      balls: striker.batBalls || striker.balls || 0,
      fours: striker.batFours || striker.fours || 0,
      sixes: striker.batSixes || striker.sixes || 0,
    } : null,
    nonStriker: nonStriker ? {
      name: nonStriker.batName || nonStriker.name || '',
      runs: nonStriker.batRuns || nonStriker.runs || 0,
      balls: nonStriker.batBalls || nonStriker.balls || 0,
      fours: nonStriker.batFours || nonStriker.fours || 0,
      sixes: nonStriker.batSixes || nonStriker.sixes || 0,
    } : null,
    bowler: bowler ? {
      name: bowler.bowlName || bowler.name || '',
      overs: bowler.bowlOvs || bowler.overs || 0,
      maidens: bowler.bowlMaidens || bowler.maidens || 0,
      runs: bowler.bowlRuns || bowler.runs || 0,
      wickets: bowler.bowlWkts || bowler.wickets || 0,
      economy: bowler.bowlEcon || bowler.economy || 0,
    } : null,
    partnership: partnership ? {
      runs: partnership.runs || 0,
      balls: partnership.balls || 0,
    } : null,
    lastWicket: lastWicket ? {
      player: lastWicket.playerName || '',
      runs: lastWicket.runs || 0,
      balls: lastWicket.balls || 0,
      dismissal: lastWicket.dismissal || '',
    } : null,
    winProbability: winProbability,
    drs: miniscore.drs || null,
    sessionStats: miniscore.sessionStats || null,
    wormGraph: miniscore.wormGraph || scoreDetails.wormGraph || null,
    updatedAt: new Date().toISOString(),
  };
}

/**
 * Calculate balls remaining in the innings.
 */
function calculateBallsRemaining(currentOvers, target, inningsList) {
  try {
    const [overs, balls] = String(currentOvers).split('.').map(Number);
    const totalBalls = (overs * 6) + (balls || 0);
    
    // Determine match format for max overs
    let maxOvers = 50; // Default ODI
    if (inningsList.length > 0) {
      // Try to infer from first innings
      const firstInnings = inningsList[0];
      if (firstInnings.overs && parseFloat(firstInnings.overs) <= 20) {
        maxOvers = 20; // T20
      }
    }
    
    const maxBalls = maxOvers * 6;
    return Math.max(0, maxBalls - totalBalls);
  } catch {
    return null;
  }
}

/**
 * Extract latest ball information from balls-map data.
 */
function extractLatestBall(ballsData, inningsId, commData = null) {
  const latestCommentary = extractLatestCommentary(commData);
  const sourceBalls = ballsData?.balls || ballsData?.ball || ballsData?.ballMap || [];
  const balls = Array.isArray(sourceBalls)
    ? sourceBalls.filter((b) => String(b.inningsId || b.innings || inningsId) === String(inningsId) || !b.inningsId)
    : [];

  const latest = balls.length
    ? [...balls].sort((a, b) => Number(b.timestamp || b.ballNbr || 0) - Number(a.timestamp || a.ballNbr || 0))[0]
    : null;
  if (!latest && !latestCommentary) return null;

  const useCommentaryBall = latestCommentary?.overNumber
    && Number(latestCommentary.timestamp || 0) >= Number(latest?.timestamp || 0);
  const overNumber = Number(useCommentaryBall ? latestCommentary.overNumber : (latest?.overNumber ?? latest?.overNum ?? latest?.over ?? latestCommentary?.overNumber ?? latestCommentary?.over ?? 0));
  const ballNumber = Number(useCommentaryBall ? latestCommentary.ballNumber : (latest?.ballNumber ?? latest?.ballNbr ?? latest?.ball ?? latestCommentary?.ballNumber ?? latestCommentary?.ball ?? 0));
  const rawEvent = String(latest?.event || latest?.eventType || latestCommentary?.event || '').toUpperCase();
  const runs = Number(useCommentaryBall
    ? (latestCommentary.runs ?? latest?.totalRuns ?? latest?.runs ?? latest?.scoreValue ?? 0)
    : (latest?.totalRuns ?? latest?.runs ?? latest?.scoreValue ?? latestCommentary?.runs ?? 0));
  const result = useCommentaryBall
    ? (latestCommentary?.ballResult || (/no run/i.test(latestCommentary?.commentary || '') ? '0' : latestCommentary?.event || latest?.ballLabel || ''))
    : (latest?.ballType || latest?.displayScore || latest?.ballLabel || latestCommentary?.ballResult || latestCommentary?.event || '');
  const event = rawEvent
    || (/(WICKET|OUT)$/i.test(result) ? 'WICKET'
      : String(result) === '4' ? 'FOUR'
        : String(result) === '6' ? 'SIX'
          : /Wd|WIDE/i.test(result) ? 'WIDE'
            : /Nb|NO.?BALL/i.test(result) ? 'NO_BALL'
              : 'NONE');

  return {
    overNumber,
    ballNumber,
    event,
    runs,
    batsman: latest?.batsman || latest?.batsmanName || latestCommentary?.batsman || '',
    bowler: latest?.bowler || latest?.bowlerName || latestCommentary?.bowler || '',
    commentary: latest?.commentary || latestCommentary?.commentary || latestCommentary?.text || '',
    isBoundary: event === 'FOUR' || event === 'SIX' || runs === 4 || runs === 6,
    isWicket: event === 'WICKET' || latest?.isWicket === true || latestCommentary?.isWicket === true,
    isWide: event === 'WIDE' || latest?.isWide === true,
    isNoBall: event === 'NO_BALL' || latest?.isNoBall === true,
    timestamp: latest?.timestamp || latestCommentary?.timestamp || Date.now(),
    scoreAfter: latest?.scoreAfter || latest?.score || latestCommentary?.scoreAfter || 0,
    wicketsAfter: latest?.wicketsAfter || latest?.wickets || latestCommentary?.wicketsAfter || 0,
  };
}

function extractLatestCommentary(commData) {
  const list = commData?.commentaryList || commData?.matchCommentary || commData?.commentary || commData?.commLines || [];
  const items = Array.isArray(list) ? list : Object.values(list || {});
  const entry = items.find((item) => item?.overNumber || item?.over || item?.commText || item?.commentary || item?.text) || null;
  if (!entry) return null;
  const text = cleanText(entry.commText || entry.commentary || entry.text || entry.commentaryText || '');
  const overText = String(entry.overNumber || entry.over || entry.ballMetric || entry.ballNbr || '');
  const [over, ball] = overText.includes('.') ? overText.split('.') : [entry.over, entry.ball];
  return {
    overNumber: Number(over || 0),
    ballNumber: Number(ball || 0),
    commentary: text,
    text,
    event: Array.isArray(entry.event) ? entry.event[0] : (entry.event || entry.eventType || ''),
    ballResult: entry.ball || entry.ballResult || '',
    batsman: entry.batsman || entry.batsmanName || entry.batsmanDetails?.playerName || '',
    bowler: entry.bowler || entry.bowlerName || entry.bowlerDetails?.playerName || '',
    scoreAfter: entry.score || entry.scoreAfter || 0,
    wicketsAfter: entry.wickets || entry.wicketsAfter || 0,
    timestamp: entry.timestamp || entry.commTimestamp || Date.now(),
    runs: /no run/i.test(text) ? 0 : undefined,
    isWicket: /\bwicket\b|\bcaught\b|\bbowled\b|\blbw\b|\brun-?out\b|\bstumped\b|\bc\&b\b/i.test(text),
  };
}

const TEAM_NAME_BY_SHORT = {
  MI: 'Mumbai Indians',
  RR: 'Rajasthan Royals',
  CSK: 'Chennai Super Kings',
  RCB: 'Royal Challengers Bengaluru',
  PBKS: 'Punjab Kings',
  KKR: 'Kolkata Knight Riders',
  SRH: 'Sunrisers Hyderabad',
  DC: 'Delhi Capitals',
  LSG: 'Lucknow Super Giants',
  GT: 'Gujarat Titans',
};

const PLAYER_ROLE_PATTERN = /(WK-Batter|Wicket Keeper|Keeper|Batter|Bowler|Batting Allrounder|Bowling Allrounder|Allrounder|All-Rounder|WK)/ig;

function extractSquadTeamsFromTitle(html, pageTitle) {
  const title = decodeHtmlEntities(pageTitle || '');
  const shortMatch = title.match(/\|\s*([A-Z]{2,4})\s+vs\s+([A-Z]{2,4})(?:,|\s)/i);
  const fullMatch = html.match(/content="([^"]+?)\s+vs\s+([^"]+?),\s*[^"]*?Squads/i)
    || title.match(/Cricket match squads \|\s*([^,|]+?)\s+vs\s+([^,|]+?),/i);
  const team1Short = shortMatch?.[1]?.toUpperCase() || generateShortName(fullMatch?.[1] || 'Team 1');
  const team2Short = shortMatch?.[2]?.toUpperCase() || generateShortName(fullMatch?.[2] || 'Team 2');
  return [
    {
      name: TEAM_NAME_BY_SHORT[team1Short] || cleanText(fullMatch?.[1] || team1Short),
      shortName: team1Short,
      index: 0,
      fromTitle: true,
    },
    {
      name: TEAM_NAME_BY_SHORT[team2Short] || cleanText(fullMatch?.[2] || team2Short),
      shortName: team2Short,
      index: Math.floor(String(html).length / 2),
      fromTitle: true,
    },
  ];
}

function cleanText(value = '') {
  return decodeHtmlEntities(String(value).replace(/<[^>]+>/g, ' '))
    .replace(/\s+/g, ' ')
    .trim();
}

function cleanSquadPlayerName(rawName = '') {
  let name = cleanText(rawName);
  name = name
    .replace(/\((?:c|C|wk|WK|w\.k\.|C\s*&\s*WK|WK\s*&\s*C)\)/g, ' ')
    .replace(PLAYER_ROLE_PATTERN, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return name;
}

function cleanSquadRole(context = '', rawName = '') {
  const combined = cleanText(`${rawName} ${context}`);
  const matches = [...combined.matchAll(PLAYER_ROLE_PATTERN)].map((m) => m[1]);
  const role = matches.find((r) => !/^WK$/i.test(r)) || (/\(WK\)|wicket.?keeper/i.test(combined) ? 'WK-Batter' : '');
  return role
    .replace(/^Keeper$/i, 'WK-Batter')
    .replace(/^Wicket Keeper$/i, 'WK-Batter');
}

function normalizeSquadPlayer(p) {
  return {
    player_id: p.player_id,
    name: p.name,
    role: p.role || '',
    image_url: p.image_url || '',
    is_captain: !!p.is_captain,
    is_wicketkeeper: !!p.is_wicketkeeper,
    is_impact_player: !!p.is_impact_player,
    is_substitute: !!p.is_substitute,
  };
}

/**
 * FIXED: Parse match squads from Cricbuzz HTML
 * Key fixes: Extract team names from h3 headers (not page title),
 * properly separate Playing XI from Bench, better captain/WK detection
 */
function parseMatchSquadsFromHtml_OLD(html, matchId) {
  logger.info({ msg: '[FIXED] Parsing match squads HTML', matchId, htmlLength: html?.length || 0 });
  
  const titleMatch = html.match(/<title>([^<]*)<\/title>/i);
  const pageTitle = titleMatch ? titleMatch[1].replace(/\s+/g, ' ').trim() : '';
  
  // Find team headers (h3 with cb-match-sqd-text class)
  const teamHeaders = [];
  const teamHeaderPattern = /<h3[^>]*class="[^"]*cb-match-sqd-text[^"]*"[^>]*>([\s\S]*?)<\/h3>/gi;
  let headerMatch;
  
  while ((headerMatch = teamHeaderPattern.exec(html)) !== null) {
    const teamName = headerMatch[1].replace(/<[^>]+>/g, '').trim();
    if (teamName && teamName.length > 2 && !teamName.toLowerCase().includes('playing xi')) {
      teamHeaders.push({
        name: teamName,
        shortName: generateShortName(teamName),
        index: headerMatch.index
      });
    }
  }
  
  // Fallback: try generic h3
  if (teamHeaders.length < 2) {
    const genericH3Pattern = /<h3[^>]*>([\s\S]*?)<\/h3>/gi;
    while ((headerMatch = genericH3Pattern.exec(html)) !== null) {
      const teamName = headerMatch[1].replace(/<[^>]+>/g, '').trim();
      if (teamName && 
          teamName.length > 2 && 
          teamName.length < 50 &&
          !teamName.toLowerCase().includes('playing xi') &&
          !teamName.toLowerCase().includes('bench') &&
          !teamName.toLowerCase().includes('substitutes') &&
          !teamName.toLowerCase().includes('impact') &&
          !teamName.toLowerCase().includes('support staff') &&
          !teamName.toLowerCase().includes('cricbuzz') &&
          !teamHeaders.find(h => h.name === teamName)) {
        teamHeaders.push({
          name: teamName,
          shortName: generateShortName(teamName),
          index: headerMatch.index
        });
      }
      if (teamHeaders.length >= 2) break;
    }
  }
  
  logger.info({ msg: '[FIXED] Found team headers', matchId, teams: teamHeaders.map(h => h.name) });
  
  if (teamHeaders.length < 2) {
    logger.warn({ msg: '[FIXED] Could not find 2 team headers, deriving from title', matchId, pageTitle });
    teamHeaders.splice(0, teamHeaders.length, ...extractSquadTeamsFromTitle(html, pageTitle));
  }
  
  // Parse all player cards
  const allPlayers = [];
  const playerCardPattern = /<a[^>]*href="[^"]*\/profiles\/(\d+)\/[^"]*"[^>]*>([\s\S]*?)<\/a>/gi;
  let playerMatch;
  
  while ((playerMatch = playerCardPattern.exec(html)) !== null) {
    const playerId = playerMatch[1];
    const nameHtml = playerMatch[2];
    const rawPlayerName = nameHtml.replace(/<[^>]+>/g, '').trim();
    const playerName = cleanSquadPlayerName(rawPlayerName);
    
    if (playerName && playerName.length > 2 && !/^(coach|support staff|mentor)$/i.test(playerName)) {
      const contextStart = Math.max(0, playerMatch.index - 200);
      const contextEnd = Math.min(html.length, playerMatch.index + 300);
      const context = html.slice(contextStart, contextEnd);
      
      const precedingHtml = html.slice(Math.max(0, playerMatch.index - 800), playerMatch.index);
      const lastSectionMatch = precedingHtml.match(/(playing\s*xi|bench|substitutes|impact\s*player)/i);
      const section = lastSectionMatch ? lastSectionMatch[1].toLowerCase() : 'unknown';
      
      const role = cleanSquadRole(context, rawPlayerName) || extractPlayerRole(context);
      const captainMatch = `${rawPlayerName} ${context}`.match(/\((c|C)\s*(?:&\s*(?:wk|WK))?\)|captain/i);
      const wkMatch = `${rawPlayerName} ${context}`.match(/\((?:wk|WK|w\.k\.)\s*(?:&\s*(?:c|C))?\)|wicket.?keeper|WK-Batter/i);
      
      allPlayers.push({
        player_id: String(playerId),
        name: playerName,
        role,
        is_captain: !!captainMatch,
        is_wicketkeeper: !!wkMatch,
        is_impact_player: section.includes('impact'),
        is_substitute: section.includes('substitutes') || section.includes('bench'),
        section,
        index: playerMatch.index
      });
    }
  }
  const uniquePlayers = [];
  const seenPlayers = new Set();
  for (const player of allPlayers) {
    if (seenPlayers.has(player.player_id)) continue;
    seenPlayers.add(player.player_id);
    uniquePlayers.push(player);
  }
  
  logger.info({ msg: '[FIXED] Parsed players', matchId, totalPlayers: uniquePlayers.length });
  
  // Assign players to teams
  const teams = [];
  teamHeaders.sort((a, b) => a.index - b.index);
  
  for (let i = 0; i < teamHeaders.length && i < 2; i++) {
    const header = teamHeaders[i];
    const nextHeader = teamHeaders[i + 1];
    
    let teamPlayers = uniquePlayers.filter(p => {
      if (nextHeader) {
        return p.index > header.index && p.index < nextHeader.index;
      }
      return p.index > header.index;
    });

    if (header.fromTitle) {
      const midpoint = Math.ceil(uniquePlayers.length / 2);
      teamPlayers = i === 0 ? uniquePlayers.slice(0, midpoint) : uniquePlayers.slice(midpoint);
    }
    
    const playingXi = teamPlayers
      .filter(p => p.section.includes('playing') || (!p.section.includes('bench') && !p.section.includes('impact') && !p.section.includes('substitutes')))
      .slice(0, 11)
      .map(normalizeSquadPlayer);
    
    const bench = teamPlayers
      .filter(p => p.section.includes('bench') || p.section.includes('substitutes'))
      .map(normalizeSquadPlayer);
    
    const impactPlayer = teamPlayers.find(p => p.section.includes('impact')) || null;
    
    teams.push({
      team_name: header.name,
      team_short: header.shortName,
      playing_xi: playingXi,
      bench: bench,
      substitutes: bench,
      impact_player: impactPlayer ? {
        player_id: impactPlayer.player_id,
        name: impactPlayer.name,
        role: impactPlayer.role
      } : null
    });
  }

  const parseError = uniquePlayers.length === 0 ? 'Could not find player profile links' : null;
  
  return {
    match_id: String(matchId),
    team1: teams[0] || { team_name: teamHeaders[0]?.name || '', team_short: teamHeaders[0]?.shortName || '', playing_xi: [], bench: [], substitutes: [], impact_player: null },
    team2: teams[1] || { team_name: teamHeaders[1]?.name || '', team_short: teamHeaders[1]?.shortName || '', playing_xi: [], bench: [], substitutes: [], impact_player: null },
    support_staff: [],
    page_title: pageTitle,
    _players_found: uniquePlayers.length,
    _teams_found: teamHeaders.length,
    ...(parseError ? { _parse_error: parseError } : {})
  };
}

/**
 * FIXED: Parse points table from Cricbuzz HTML
 * Key fixes: Better table detection, stop at Opposition section, validate IPL teams
 */
function parsePointsTableFromHtml_OLD(html, seriesId) {
  logger.info({ msg: '[FIXED] Parsing points table HTML', seriesId, htmlLength: html?.length || 0 });
  
  const pointsTableInfo = [];
  let tableHtml = null;
  
  // Strategy 1: Look for cb-srs-pnts-tble class
  const tableMatch = html.match(/<table[^>]*class="[^"]*cb-srs-pnts-tble[^"]*"[^>]*>([\s\S]*?)<\/table>/i);
  if (tableMatch) {
    tableHtml = tableMatch[0];
  }
  
  // Strategy 2: Look for any table with points-related headers
  if (!tableHtml) {
    const allTables = html.match(/<table[^>]*>[\s\S]*?<\/table>/gi) || [];
    for (const table of allTables) {
      if (table.includes('Pts') && table.includes('NRR') && table.includes('P')) {
        tableHtml = table;
        break;
      }
    }
  }
  
  // Strategy 3: Div-based points table
  if (!tableHtml) {
    const divTableMatch = html.match(/<div[^>]*class="[^"]*cb-srs-pnts[^"]*"[^>]*>([\s\S]*?)<\/div>/i);
    if (divTableMatch) {
      const divHtml = divTableMatch[1];
      const rowPattern = /<div[^>]*class="[^"]*cb-srs-pnts-dgt-wdg[^"]*"[^>]*>([\s\S]*?)<\/div>/gi;
      let rowMatch;
      let position = 1;
      
      while ((rowMatch = rowPattern.exec(divHtml)) !== null) {
        const rowHtml = rowMatch[1];
        const teamMatch = rowHtml.match(/<a[^>]*>([\s\S]*?)<\/a>/i);
        const teamName = teamMatch ? teamMatch[1].replace(/<[^>]+>/g, '').trim() : '';
        const numbers = rowHtml.match(/>(\d+)</g);
        
        if (teamName && numbers && numbers.length >= 5) {
          const values = numbers.map(n => parseInt(n.replace(/[><]/g, '')));
          pointsTableInfo.push({
            rank: position++,
            team_id: '',
            team_name: teamName,
            team_short: generateShortName(teamName),
            played: values[0] || 0,
            won: values[1] || 0,
            lost: values[2] || 0,
            tied: values[3] || 0,
            no_result: values[4] || 0,
            points: values[5] || 0,
            nrr: parseFloat(values[6] || 0),
            qualified: position <= 4 ? 'Q' : (position <= 6 ? 'E' : ''),
            logo_url: ''
          });
        }
      }
    }
  }
  
  // Parse table rows
  if (tableHtml && pointsTableInfo.length === 0) {
    const tbodyMatch = tableHtml.match(/<tbody[^>]*>([\s\S]*?)<\/tbody>/i);
    const tbody = tbodyMatch ? tbodyMatch[1] : tableHtml;
    
    const rowPattern = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
    let rowMatch;
    let position = 1;
    
    while ((rowMatch = rowPattern.exec(tbody)) !== null) {
      const rowHtml = rowMatch[1];
      
      // Stop at Opposition section
      if (rowHtml.includes('Opposition') || rowHtml.includes('Description') || rowHtml.includes('Date')) {
        break;
      }
      
      const cellPattern = /<td[^>]*>([\s\S]*?)<\/td>/gi;
      const cells = [];
      let cellMatch;
      
      while ((cellMatch = cellPattern.exec(rowHtml)) !== null) {
        let cellText = cellMatch[1].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
        cells.push(cellText);
      }
      
      if (cells.length >= 7) {
        const rank = parseInt(cells[0]) || position;
        const teamName = cells[1];
        
        if (teamName && teamName.length > 1 && !teamName.match(/^\d+$/)) {
          const qualified = cells[1].includes('Q') ? 'Q' : (cells[1].includes('E') ? 'E' : '');
          
          pointsTableInfo.push({
            rank: rank,
            team_id: '',
            team_name: teamName.replace(/\s+Q\s*$/, '').replace(/\s+E\s*$/, '').trim(),
            team_short: generateShortName(teamName),
            played: parseInt(cells[2]) || 0,
            won: parseInt(cells[3]) || 0,
            lost: parseInt(cells[4]) || 0,
            tied: parseInt(cells[5]) || 0,
            no_result: parseInt(cells[6]) || 0,
            points: parseInt(cells[7]) || 0,
            nrr: parseFloat(cells[8]) || 0,
            qualified: qualified,
            logo_url: ''
          });
          
          position++;
        }
      }
    }
  }
  
  // Validate for IPL
  if ((seriesId === '9241' || seriesId === 9241) && pointsTableInfo.length < 8) {
    logger.error({ 
      msg: '[FIXED] IPL points table has too few teams', 
      seriesId, 
      count: pointsTableInfo.length,
      teams: pointsTableInfo.map(t => t.team_name)
    });
    return { pointsTable: [], _error: `Only found ${pointsTableInfo.length} teams, expected 10 for IPL` };
  }
  
  logger.info({ msg: '[FIXED] Parsed points table', seriesId, teams: pointsTableInfo.length });
  
  return { pointsTable: pointsTableInfo };
}

/**
 * Parse scorecard from Cricbuzz HTML
 */
function parseScorecardFromHtml(html, matchId) {
  logger.info({ msg: '[FIXED] Parsing scorecard HTML', matchId, htmlLength: html?.length || 0 });
  
  const innings = [];
  const inningsPattern = /<div[^>]*id="innings_\d+"[^>]*>([\s\S]*?)<\/div>\s*<\/div>/gi;
  let inningsMatch;
  
  while ((inningsMatch = inningsPattern.exec(html)) !== null) {
    const inningsHtml = inningsMatch[1];
    
    const headerMatch = inningsHtml.match(/<h2[^>]*>([\s\S]*?)<\/h2>/i) || 
                       inningsHtml.match(/<span[^>]*class="[^"]*cb-scrcrd-hdr-rw[^"]*"[^>]*>([\s\S]*?)<\/span>/i);
    const headerText = headerMatch ? headerMatch[1].replace(/<[^>]+>/g, '').trim() : '';
    
    // Parse batting
    const battingRows = [];
    const battingPattern = /<tr[^>]*class="[^"]*cb-scrcrd-bat-tr[^"]*"[^>]*>([\s\S]*?)<\/tr>/gi;
    let battingMatch;
    
    while ((battingMatch = battingPattern.exec(inningsHtml)) !== null) {
      const rowHtml = battingMatch[1];
      const cells = rowHtml.match(/<td[^>]*>([\s\S]*?)<\/td>/gi) || [];
      
      if (cells.length >= 8) {
        const playerMatch = cells[0].match(/>([^<]+)</);
        const dismissalMatch = cells[1].match(/>([^<]+)</);
        
        battingRows.push({
          player: playerMatch ? playerMatch[1].trim() : '',
          dismissal: dismissalMatch ? dismissalMatch[1].trim() : '',
          runs: parseInt(cells[2].replace(/<[^>]+>/g, '')) || 0,
          balls: parseInt(cells[3].replace(/<[^>]+>/g, '')) || 0,
          fours: parseInt(cells[5].replace(/<[^>]+>/g, '')) || 0,
          sixes: parseInt(cells[6].replace(/<[^>]+>/g, '')) || 0,
          strike_rate: parseFloat(cells[7].replace(/<[^>]+>/g, '')) || 0
        });
      }
    }
    
    // Parse bowling
    const bowlingRows = [];
    const bowlingPattern = /<tr[^>]*class="[^"]*cb-scrcrd-bwl-tr[^"]*"[^>]*>([\s\S]*?)<\/tr>/gi;
    let bowlingMatch;
    
    while ((bowlingMatch = bowlingPattern.exec(inningsHtml)) !== null) {
      const rowHtml = bowlingMatch[1];
      const cells = rowHtml.match(/<td[^>]*>([\s\S]*?)<\/td>/gi) || [];
      
      if (cells.length >= 8) {
        const playerMatch = cells[0].match(/>([^<]+)</);
        
        bowlingRows.push({
          player: playerMatch ? playerMatch[1].trim() : '',
          overs: cells[1].replace(/<[^>]+>/g, '').trim(),
          maidens: parseInt(cells[2].replace(/<[^>]+>/g, '')) || 0,
          runs: parseInt(cells[3].replace(/<[^>]+>/g, '')) || 0,
          wickets: parseInt(cells[4].replace(/<[^>]+>/g, '')) || 0,
          no_balls: parseInt(cells[6].replace(/<[^>]+>/g, '')) || 0,
          wides: parseInt(cells[7].replace(/<[^>]+>/g, '')) || 0,
          economy: parseFloat(cells[8]?.replace(/<[^>]+>/g, '')) || 0
        });
      }
    }
    
    // Extract extras and total
    const extrasMatch = inningsHtml.match(/extras[\s\S]*?<td[^>]*>(\d+)<\/td>/i);
    const totalMatch = inningsHtml.match(/total[\s\S]*?<td[^>]*>(\d+)[\s\S]*?(\d+\.\d+)<\/td>/i);
    
    innings.push({
      name: headerText,
      batting: battingRows,
      bowling: bowlingRows,
      extras: extrasMatch ? parseInt(extrasMatch[1]) : 0,
      total: totalMatch ? parseInt(totalMatch[1]) : 0,
      overs: totalMatch && totalMatch[2] ? totalMatch[2] : ''
    });
  }
  
  return { innings };
}

// FIXED: Parse match squads from Cricbuzz HTML
function parseMatchSquadsFromHtml_FIXED(html, matchId) {
  logger.info({ msg: '[FIXED] Parsing match squads HTML', matchId, htmlLength: html?.length || 0 });
  
  const titleMatch = html.match(/<title>([^<]*)<\/title>/i);
  const pageTitle = titleMatch ? titleMatch[1].replace(/\s+/g, ' ').trim() : '';
  
  // Find team headers (h3 with cb-match-sqd-text class)
  const teamHeaders = [];
  const teamHeaderPattern = /<h3[^>]*class="[^"]*cb-match-sqd-text[^"]*"[^>]*>([\s\S]*?)<\/h3>/gi;
  let headerMatch;
  
  while ((headerMatch = teamHeaderPattern.exec(html)) !== null) {
    const teamName = headerMatch[1].replace(/<[^>]+>/g, '').trim();
    if (teamName && teamName.length > 2 && !teamName.toLowerCase().includes('playing xi')) {
      teamHeaders.push({
        name: teamName,
        shortName: generateShortName(teamName),
        index: headerMatch.index
      });
    }
  }
  
  // Fallback: try generic h3
  if (teamHeaders.length < 2) {
    const genericH3Pattern = /<h3[^>]*>([\s\S]*?)<\/h3>/gi;
    while ((headerMatch = genericH3Pattern.exec(html)) !== null) {
      const teamName = headerMatch[1].replace(/<[^>]+>/g, '').trim();
      if (teamName && 
          teamName.length > 2 && 
          teamName.length < 50 &&
          !teamName.toLowerCase().includes('playing xi') &&
          !teamName.toLowerCase().includes('bench') &&
          !teamName.toLowerCase().includes('substitutes') &&
          !teamName.toLowerCase().includes('impact') &&
          !teamName.toLowerCase().includes('support staff') &&
          !teamName.toLowerCase().includes('cricbuzz') &&
          !teamHeaders.find(h => h.name === teamName)) {
        teamHeaders.push({
          name: teamName,
          shortName: generateShortName(teamName),
          index: headerMatch.index
        });
      }
      if (teamHeaders.length >= 2) break;
    }
  }
  
  logger.info({ msg: '[FIXED] Found team headers', matchId, teams: teamHeaders.map(h => h.name) });
  
  if (teamHeaders.length < 2) {
    logger.warn({ msg: '[FIXED] Could not find 2 team headers, deriving from title', matchId, pageTitle });
    teamHeaders.splice(0, teamHeaders.length, ...extractSquadTeamsFromTitle(html, pageTitle));
  }
  
  // Parse all player cards
  const allPlayers = [];
  const playerCardPattern = /<a[^>]*href="[^"]*\/profiles\/(\d+)\/[^"]*"[^>]*>([\s\S]*?)<\/a>/gi;
  let playerMatch;
  
  while ((playerMatch = playerCardPattern.exec(html)) !== null) {
    const playerId = playerMatch[1];
    const nameHtml = playerMatch[2];
    const rawPlayerName = nameHtml.replace(/<[^>]+>/g, '').trim();
    const playerName = cleanSquadPlayerName(rawPlayerName);
    
    if (playerName && playerName.length > 2 && !/^(coach|support staff|mentor)$/i.test(playerName)) {
      const contextStart = Math.max(0, playerMatch.index - 200);
      const contextEnd = Math.min(html.length, playerMatch.index + 300);
      const context = html.slice(contextStart, contextEnd);
      
      const precedingHtml = html.slice(Math.max(0, playerMatch.index - 800), playerMatch.index);
      const lastSectionMatch = precedingHtml.match(/(playing\s*xi|bench|substitutes|impact\s*player)/i);
      const section = lastSectionMatch ? lastSectionMatch[1].toLowerCase() : 'unknown';
      
      const role = cleanSquadRole(context, rawPlayerName) || extractPlayerRole(context);
      const captainMatch = `${rawPlayerName} ${context}`.match(/\((c|C)\s*(?:&\s*(?:wk|WK))?\)|captain/i);
      const wkMatch = `${rawPlayerName} ${context}`.match(/\((?:wk|WK|w\.k\.)\s*(?:&\s*(?:c|C))?\)|wicket.?keeper|WK-Batter/i);
      
      allPlayers.push({
        player_id: String(playerId),
        name: playerName,
        role,
        is_captain: !!captainMatch,
        is_wicketkeeper: !!wkMatch,
        is_impact_player: section.includes('impact'),
        is_substitute: section.includes('substitutes') || section.includes('bench'),
        section,
        index: playerMatch.index
      });
    }
  }
  const uniquePlayers = [];
  const seenPlayers = new Set();
  for (const player of allPlayers) {
    if (seenPlayers.has(player.player_id)) continue;
    seenPlayers.add(player.player_id);
    uniquePlayers.push(player);
  }
  
  logger.info({ msg: '[FIXED] Parsed players', matchId, totalPlayers: uniquePlayers.length });
  
  // Assign players to teams
  const teams = [];
  teamHeaders.sort((a, b) => a.index - b.index);
  
  for (let i = 0; i < teamHeaders.length && i < 2; i++) {
    const header = teamHeaders[i];
    const nextHeader = teamHeaders[i + 1];
    
    let teamPlayers = uniquePlayers.filter(p => {
      if (nextHeader) {
        return p.index > header.index && p.index < nextHeader.index;
      }
      return p.index > header.index;
    });

    if (header.fromTitle) {
      const midpoint = Math.ceil(uniquePlayers.length / 2);
      teamPlayers = i === 0 ? uniquePlayers.slice(0, midpoint) : uniquePlayers.slice(midpoint);
    }
    
    const playingXi = teamPlayers
      .filter(p => p.section.includes('playing') || (!p.section.includes('bench') && !p.section.includes('impact') && !p.section.includes('substitutes')))
      .slice(0, 11)
      .map(normalizeSquadPlayer);
    
    const bench = teamPlayers
      .filter(p => p.section.includes('bench') || p.section.includes('substitutes'))
      .map(normalizeSquadPlayer);
    
    const impactPlayer = teamPlayers.find(p => p.section.includes('impact')) || null;
    
    teams.push({
      team_name: header.name,
      team_short: header.shortName,
      playing_xi: playingXi,
      bench: bench,
      substitutes: bench,
      impact_player: impactPlayer ? {
        player_id: impactPlayer.player_id,
        name: impactPlayer.name,
        role: impactPlayer.role
      } : null
    });
  }
  
  return {
    match_id: String(matchId),
    team1: teams[0] || { team_name: teamHeaders[0]?.name || '', team_short: teamHeaders[0]?.shortName || '', playing_xi: [], bench: [], substitutes: [], impact_player: null },
    team2: teams[1] || { team_name: teamHeaders[1]?.name || '', team_short: teamHeaders[1]?.shortName || '', playing_xi: [], bench: [], substitutes: [], impact_player: null },
    support_staff: [],
    page_title: pageTitle,
    _players_found: uniquePlayers.length,
    _teams_found: teamHeaders.length,
    ...(uniquePlayers.length === 0 ? { _parse_error: 'Could not find player profile links' } : {})
  };
}

// FIXED: Parse points table from Cricbuzz HTML
function parsePointsTableFromHtml_FIXED(html, seriesId) {
  logger.info({ msg: '[FIXED] Parsing points table HTML', seriesId, htmlLength: html?.length || 0 });
  
  const pointsTableInfo = [];
  let tableHtml = null;
  
  // Strategy 1: Look for cb-srs-pnts-tble class
  const tableMatch = html.match(/<table[^>]*class="[^"]*cb-srs-pnts-tble[^"]*"[^>]*>([\s\S]*?)<\/table>/i);
  if (tableMatch) {
    tableHtml = tableMatch[0];
  }
  
  // Strategy 2: Look for any table with points-related headers
  if (!tableHtml) {
    const allTables = html.match(/<table[^>]*>[\s\S]*?<\/table>/gi) || [];
    for (const table of allTables) {
      if (table.includes('Pts') && table.includes('NRR') && table.includes('P')) {
        tableHtml = table;
        break;
      }
    }
  }
  
  // Strategy 3: Div-based points table
  if (!tableHtml) {
    const divTableMatch = html.match(/<div[^>]*class="[^"]*cb-srs-pnts[^"]*"[^>]*>([\s\S]*?)<\/div>/i);
    if (divTableMatch) {
      const divHtml = divTableMatch[1];
      const rowPattern = /<div[^>]*class="[^"]*cb-srs-pnts-dgt-wdg[^"]*"[^>]*>([\s\S]*?)<\/div>/gi;
      let rowMatch;
      let position = 1;
      
      while ((rowMatch = rowPattern.exec(divHtml)) !== null) {
        const rowHtml = rowMatch[1];
        const teamMatch = rowHtml.match(/<a[^>]*>([\s\S]*?)<\/a>/i);
        const teamName = teamMatch ? teamMatch[1].replace(/<[^>]+>/g, '').trim() : '';
        const numbers = rowHtml.match(/>(\d+)</g);
        
        if (teamName && numbers && numbers.length >= 5) {
          const values = numbers.map(n => parseInt(n.replace(/[><]/g, '')));
          
          pointsTableInfo.push({
            rank: position++,
            team_id: '',
            team_name: teamName,
            team_short: generateShortName(teamName),
            played: values[0] || 0,
            won: values[1] || 0,
            lost: values[2] || 0,
            tied: values[3] || 0,
            no_result: values[4] || 0,
            points: values[5] || 0,
            nrr: parseFloat(values[6] || 0),
            qualified: position <= 4 ? 'Q' : (position <= 6 ? 'E' : ''),
            logo_url: ''
          });
        }
      }
    }
  }
  
  // Parse table rows
  if (tableHtml && pointsTableInfo.length === 0) {
    const tbodyMatch = tableHtml.match(/<tbody[^>]*>([\s\S]*?)<\/tbody>/i);
    const tbody = tbodyMatch ? tbodyMatch[1] : tableHtml;
    
    const rowPattern = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
    let rowMatch;
    let position = 1;
    
    while ((rowMatch = rowPattern.exec(tbody)) !== null) {
      const rowHtml = rowMatch[1];
      
      // Stop at Opposition section
      if (rowHtml.includes('Opposition') || rowHtml.includes('Description') || rowHtml.includes('Date')) {
        break;
      }
      
      const cellPattern = /<td[^>]*>([\s\S]*?)<\/td>/gi;
      const cells = [];
      let cellMatch;
      
      while ((cellMatch = cellPattern.exec(rowHtml)) !== null) {
        let cellText = cellMatch[1].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
        cells.push(cellText);
      }
      
      if (cells.length >= 7) {
        const rank = parseInt(cells[0]) || position;
        const teamName = cells[1];
        
        if (teamName && teamName.length > 1 && !teamName.match(/^\d+$/)) {
          const qualified = cells[1].includes('Q') ? 'Q' : (cells[1].includes('E') ? 'E' : '');
          
          pointsTableInfo.push({
            rank: rank,
            team_id: '',
            team_name: teamName.replace(/\s+Q\s*$/, '').replace(/\s+E\s*$/, '').trim(),
            team_short: generateShortName(teamName),
            played: parseInt(cells[2]) || 0,
            won: parseInt(cells[3]) || 0,
            lost: parseInt(cells[4]) || 0,
            tied: parseInt(cells[5]) || 0,
            no_result: parseInt(cells[6]) || 0,
            points: parseInt(cells[7]) || 0,
            nrr: parseFloat(cells[8]) || 0,
            qualified: qualified,
            logo_url: ''
          });
          
          position++;
        }
      }
    }
  }
  
  // Validate for IPL
  if ((seriesId === '9241' || seriesId === 9241) && pointsTableInfo.length < 8) {
    logger.error({ 
      msg: '[FIXED] IPL points table has too few teams', 
      seriesId, 
      count: pointsTableInfo.length,
      teams: pointsTableInfo.map(t => t.team_name)
    });
    return { pointsTable: [], _error: `Only found ${pointsTableInfo.length} teams, expected 10 for IPL` };
  }
  
  logger.info({ msg: '[FIXED] Parsed points table', seriesId, teams: pointsTableInfo.length });
  
  return { pointsTable: pointsTableInfo };
}
