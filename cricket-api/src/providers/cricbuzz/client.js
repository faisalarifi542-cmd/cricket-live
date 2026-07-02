import axios from 'axios';
import { spawnSync } from 'node:child_process';
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
    logger.info({ msg: 'Fetching scorecard', matchId, hasMatchInfo: !!matchInfo });
    
    // Try JSON API first
    let jsonData = null;
    let jsonError = null;
    try {
      const jsonUrl = `/scorecard/${matchId}`;
      logger.info({ msg: 'Trying JSON scorecard API', matchId, url: `${mcenterClient.defaults.baseURL}${jsonUrl}` });
      
      jsonData = await request(mcenterClient, jsonUrl);
      
      logger.info({ 
        msg: 'JSON scorecard response received', 
        matchId, 
        hasData: !!jsonData,
        hasInnings: !!(jsonData?.innings),
        inningsCount: jsonData?.innings?.length || 0,
        hasScoreCard: !!(jsonData?.scoreCard),
        scoreCardCount: jsonData?.scoreCard?.length || 0,
        keys: jsonData ? Object.keys(jsonData) : []
      });
      
      // Validate JSON response - check for innings OR scoreCard
      const innings = jsonData?.innings || jsonData?.scoreCard || [];
      if (jsonData && innings.length > 0) {
        // Check if innings have actual batting/bowling data
        const hasData = innings.some(inn => 
          (inn.batTeamDetails?.batsmenData && Object.keys(inn.batTeamDetails.batsmenData).length > 0) ||
          (inn.bowlTeamDetails?.bowlersData && Object.keys(inn.bowlTeamDetails.bowlersData).length > 0)
        );
        
        if (hasData) {
          logger.info({ msg: 'Scorecard JSON data found with batting/bowling', matchId, innings: innings.length });
          // Normalize the structure - ensure it's in the format normalizer expects
          return { scoreCard: innings };
        } else {
          logger.warn({ msg: 'JSON scorecard has innings but no batting/bowling data', matchId, innings: innings.length });
        }
      } else {
        logger.warn({ msg: 'JSON scorecard returned empty innings', matchId });
      }
    } catch (jsonErr) {
      jsonError = jsonErr;
      logger.warn({ 
        msg: 'JSON scorecard failed, trying HTML fallback', 
        matchId, 
        error: jsonErr.message,
        status: jsonErr.response?.status,
        statusText: jsonErr.response?.statusText
      });
    }
    
    // JSON failed or empty, try HTML fallback with multiple slug strategies
    const slugStrategies = [];
    
    // Strategy 1: Try to fetch match info first to get proper slug
    try {
      const liveData = await request(mcenterClient, `/${matchId}`);
      if (liveData?.matchInfo) {
        const team1 = liveData.matchInfo.team1?.teamSName || liveData.matchInfo.team1?.teamName || '';
        const team2 = liveData.matchInfo.team2?.teamSName || liveData.matchInfo.team2?.teamName || '';
        const matchDesc = liveData.matchInfo.matchDesc || liveData.matchInfo.matchFormat || '';
        const seriesName = liveData.matchInfo.seriesName || '';
        
        if (team1 && team2 && seriesName) {
          const slug = `${team1}-vs-${team2}-${matchDesc}-${seriesName}`
            .toLowerCase()
            .replace(/[^a-z0-9\s]/g, '')
            .replace(/\s+/g, '-')
            .slice(0, 80);
          slugStrategies.push(slug);
        }
      }
    } catch (err) {
      logger.debug({ msg: 'Could not fetch match info for slug', matchId, error: err.message });
    }
    
    // Strategy 2: Use provided matchInfo
    if (matchInfo && matchInfo.title) {
      const slug = matchInfo.title.toLowerCase()
        .replace(/[^a-z0-9\s]/g, '')
        .replace(/\s+/g, '-')
        .slice(0, 80);
      slugStrategies.push(slug);
    }
    
    // Strategy 3: Generic fallback
    slugStrategies.push('scorecard');
    
    // Try each slug strategy
    for (const slug of slugStrategies) {
      try {
        const htmlUrl = `/live-cricket-scorecard/${matchId}/${slug}`;
        logger.info({ msg: 'Trying HTML scorecard fallback', matchId, url: `${htmlClient.defaults.baseURL}${htmlUrl}`, slug });
        
        const html = await request(htmlClient, htmlUrl, { responseType: 'text' });
        
        logger.info({ 
          msg: 'HTML scorecard response received', 
          matchId, 
          htmlLength: html?.length || 0,
          titleMatch: html?.match(/<title>([^<]*)<\/title>/i)?.[1] || 'No title'
        });
        
        const htmlData = parseScorecardFromHtml(html, matchId);
        
        logger.info({ 
          msg: 'HTML scorecard parsed', 
          matchId, 
          inningsCount: htmlData?.innings?.length || 0,
          hasData: !!(htmlData?.innings?.length)
        });
        
        if (htmlData.innings && htmlData.innings.length > 0) {
          logger.info({ msg: '[FIXED] Scorecard HTML data found', matchId, innings: htmlData.innings.length, slug });
          return htmlData;
        } else {
          logger.warn({ msg: 'HTML scorecard parser returned empty innings', matchId, slug });
        }
      } catch (htmlErr) {
        logger.debug({ 
          msg: 'HTML scorecard attempt failed', 
          matchId, 
          slug,
          error: htmlErr.message,
          status: htmlErr.response?.status
        });
        // Continue to next strategy
      }
    }
    
    // All strategies failed
    logger.error({ 
      msg: 'Scorecard fetch completely failed after all strategies', 
      matchId, 
      jsonError: jsonError?.message,
      jsonStatus: jsonError?.response?.status,
      triedSlugs: slugStrategies
    });
    
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

    // Always scrape the full Cricbuzz series page as well. The JSON endpoint
    // can return only a small global/current schedule subset, while the
    // slugged Next/RSC page contains the complete `matchesData` payload.
    if (seriesId) {
      try {
        const html = await request(htmlClient, `/cricket-series/${seriesId}/matches`, { responseType: 'text' });
        const titleMatch = html.match(/<title>([^<]*)<\/title>/i);
        if (titleMatch && !seriesName) {
          seriesName = (titleMatch[1] || '').split(/\s*[,|\-–]\s*/)[0].trim();
        }

        scrapedMatches = extractSeriesMatchesFromHtml(html, seriesId);
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
        if (scrapedMatches.length > 0) {
          const embeddedSeriesName = scrapedMatches.find((m) => m.matchInfo?.seriesName)?.matchInfo?.seriesName;
          if (embeddedSeriesName) seriesName = embeddedSeriesName;
          logger.info({
            msg: 'Series embedded schedule parsed',
            seriesId,
            matches: scrapedMatches.length,
            jsonMatchIds: matchIds.length,
            seriesName,
            htmlLength: html?.length || 0,
            containsSeriesTitle: seriesName ? html?.includes(seriesName) : false,
            containsMatchKeyword: html?.includes('matchInfo'),
          });
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
    try {
      const seriesInfo = await this.getSeriesInfo(seriesId).catch(() => null);
      const seriesSlug = buildSeriesSlugFromTitle(seriesInfo?.seriesName || seriesInfo?.series_name || '');
      const pointsTableData = fetchPointsTableInCleanProcess(seriesId, seriesSlug);
      if (pointsTableData?.pointsTable?.some((group) => Array.isArray(group.pointsTableInfo) && group.pointsTableInfo.length > 0)) {
        return {
          ...pointsTableData,
          source: 'cricbuzz',
        };
      }
      return pointsTableData;
    } catch (err) {
      logger.error({ msg: 'Failed to parse points table HTML', seriesId, error: err.message });
      return { pointsTable: [], message: 'Points table is not available for this series yet.', source: 'cricbuzz' };
    }
  },

  // --- Player/Team (not available via mcenter, return minimal) ---
  async getPlayerInfo(playerId) {
    const html = await request(htmlClient, `/profiles/${playerId}`, { responseType: 'text' });
    return { player: parsePlayerProfileHtml(html, playerId), source: 'cricbuzz' };
  },

  async getTeamInfo(teamId) {
    return { team: { teamId } };
  },

  // --- News APIs ---
  async getNewsStories(cursor) {
    const path = buildNewsPath(cursor);
    if (path) {
      return request(apiClient, path);
    }

    const html = await request(htmlClient, '/cricket-news/latest-news', { responseType: 'text' });
    const latest = extractNewsCardsFromHtml(html);
    if (latest?.paginatedData?.length) {
      return latest;
    }

    logger.warn({ msg: 'Cricbuzz latest news page did not expose story cards; trying API fallback from page links' });
    const fallbackCursor = extractLatestNewsCursorFromHtml(html);
    if (fallbackCursor) {
      return request(apiClient, `/cricket-news/${fallbackCursor}/latest-news`);
    }

    return { paginatedData: [], nextPaginationURL: null, source: 'cricbuzz-latest-page' };
  },

  async getNewsDetail(newsId, story = null) {
    const id = String(newsId || '').trim();
    if (!id) return null;

    const candidates = [];
    const storyPath = normalizeCricbuzzPath(story?.storyUrl || story?.url || story?.webURL);
    if (storyPath) candidates.push(storyPath);

    const slug = makeNewsSlug(story?.headline || story?.title || story?.seoHeadline || '');
    if (slug) candidates.push(`/cricket-news/${id}/${slug}`);
    candidates.push(`/cricket-news/${id}`);

    const uniqueCandidates = [...new Set(candidates.filter(Boolean))];
    let lastError = null;

    for (const path of uniqueCandidates) {
      try {
        const html = await request(htmlClient, path, { responseType: 'text' });
        const detail = extractNewsDetailFromHtml(html);
        if (detail) {
          const canonical = extractHtmlAttribute(html, /<link[^>]+rel=["']canonical["'][^>]*>/i, 'href');
          const ogUrl = extractMetaContent(html, 'og:url');
          return {
            ...detail,
            storyUrl: canonical || ogUrl || `https://www.cricbuzz.com${path}`,
            htmlPath: path,
          };
        }
      } catch (err) {
        lastError = err;
        logger.debug({ msg: 'Cricbuzz news detail fetch failed', newsId: id, path, error: err.message });
      }
    }

    if (lastError) throw lastError;
    return null;
  },

  async getRankings({ gender = 'men', category = 'batting', format = 'test' } = {}) {
    const safeGender = normalizeRankingGender(gender);
    const safeCategory = normalizeRankingCategory(category);
    const safeFormat = normalizeRankingFormat(format);
    const html = await request(
      htmlClient,
      `/cricket-stats/icc-rankings/${safeGender}/${safeCategory}`,
      { responseType: 'text' },
    );
    return parseRankingsHtml(html, {
      gender: safeGender,
      category: safeCategory,
      format: safeFormat,
    });
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
    const statTypeValue = String(statType || 'mostRuns');
    const matchFormatCandidates = [3, 2, 1];
    let lastData = null;
    let lastError = null;

    for (const matchFormat of matchFormatCandidates) {
      try {
        const path = `/cricket-series/series-stats/${seriesId}?statsType=${encodeURIComponent(statTypeValue)}&seasonSeriesId=${seriesId}&matchFormat=${matchFormat}`;
        const data = await request(apiClient, path);
        const statsKey = data && Object.keys(data).find((k) => k.endsWith('StatsList') || k.toLowerCase().includes('statslist'));
        const values = statsKey ? data?.[statsKey]?.values || [] : [];
        if (values.length > 0) {
          return data;
        }
        if (data) lastData = data;
      } catch (err) {
        lastError = err;
      }
    }

    if (lastData) {
      const statsKey = Object.keys(lastData).find((k) => k.endsWith('StatsList') || k.toLowerCase().includes('statslist'));
      const values = statsKey ? lastData?.[statsKey]?.values || [] : [];
      if (values.length === 0) {
        await saveDebugFile(`stats-${seriesId}-${statTypeValue}.json`, lastData || {});
      }
      return lastData;
    }

    if (lastError) throw lastError;
    return {};
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

  // --- Full schedule (series) page ---
  // Returns the raw HTML of /cricket-schedule/series/all. Its series LIST
  // section carries each series' authoritative date range in the row anchor's
  // `title` attribute — parsed by normalizer.parseScheduleSeriesPage.
  async getScheduleSeriesPage() {
    return request(htmlClient, '/cricket-schedule/series/all', { responseType: 'text' });
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
      const seriesData = await this.getSeriesInfo(seriesId);
      return normalizeSeriesTeamsFromSeriesData(seriesData, seriesId);
    } catch (err) {
      logger.warn({ msg: 'Failed to fetch series teams', seriesId, error: err.message });
      return { teams: [] };
    }
  },

  // --- Series Squads (real, multi-format) ---------------------------------
  // Discovers the squad groups (one per team per format) for a series by
  // parsing the embedded JSON on the Cricbuzz series squads page. Each group
  // carries a squadId we can then resolve via the series-squads JSON API.
  async getSeriesSquadGroups(seriesId) {
    const slug = await resolveSeriesSlug(seriesId);
    const paths = [
      slug ? `/cricket-series/${seriesId}/${slug}/squads` : null,
      `/cricket-series/${seriesId}/squads`,
    ].filter(Boolean);

    for (const p of paths) {
      try {
        const html = await request(htmlClient, p, { responseType: 'text' });
        const groups = parseSeriesSquadGroupsFromHtml(html);
        if (groups.length) return groups;
      } catch (err) {
        logger.debug({ msg: 'Series squad groups scrape failed', seriesId, path: p, error: err.message });
      }
    }
    return [];
  },

  // Fetches one squad group's full player list from the series-squads JSON API.
  async getSeriesSquad(seriesId, squadId) {
    return request(apiClient, `/cricket-series/series-squads/${seriesId}/${squadId}`);
  },
};

// Resolves the URL slug for a series (e.g. "afghanistan-tour-of-india-2026")
// from its name, used to build the canonical squads page path.
async function resolveSeriesSlug(seriesId) {
  try {
    const info = await cricbuzzApi.getSeriesInfo(seriesId).catch(() => null);
    return buildSeriesSlugFromTitle(info?.seriesName || info?.series_name || '');
  } catch {
    return '';
  }
}

// Parses the `"squads":[ ... ]` block embedded in the Cricbuzz Next.js squads
// page. The array interleaves format headers ({squadType, isHeader:true}) with
// squad entries ({squadId, squadType, teamId, imageId}). We attach the most
// recent header format to each entry and derive a clean team name.
function parseSeriesSquadGroupsFromHtml(html = '') {
  // The squads array is embedded in the Next.js flight payload as JS-escaped
  // JSON (\"squads\":[ ... ]). Unescape the whole payload first so the marker
  // and the JSON parse both work on clean text.
  const text = String(html || '').replace(/\\"/g, '"');
  const marker = '"squads":[';
  const start = text.indexOf(marker);
  if (start === -1) return [];

  // Walk from the opening bracket to its matching close, respecting strings.
  const arrStart = start + marker.length - 1;
  let depth = 0;
  let inStr = false;
  let esc = false;
  let end = -1;
  for (let i = arrStart; i < text.length; i++) {
    const ch = text[i];
    if (inStr) {
      if (esc) esc = false;
      else if (ch === '\\') esc = true;
      else if (ch === '"') inStr = false;
      continue;
    }
    if (ch === '"') inStr = true;
    else if (ch === '[') depth++;
    else if (ch === ']') {
      depth--;
      if (depth === 0) { end = i; break; }
    }
  }
  if (end === -1) return [];

  const raw = text.slice(arrStart, end + 1);

  let list;
  try {
    list = JSON.parse(raw);
  } catch {
    return [];
  }
  if (!Array.isArray(list)) return [];

  const groups = [];
  let currentFormat = '';
  for (const entry of list) {
    if (!entry || typeof entry !== 'object') continue;
    if (entry.isHeader) {
      currentFormat = String(entry.squadType || '').trim();
      continue;
    }
    const squadId = String(entry.squadId || '');
    if (!squadId) continue;
    const squadType = String(entry.squadType || '').trim();
    groups.push({
      squadId,
      teamId: String(entry.teamId || ''),
      imageId: String(entry.imageId || ''),
      format: currentFormat,
      squadType,
      teamName: deriveTeamNameFromSquadType(squadType, currentFormat),
    });
  }
  return groups;
}

// "India One-off Test Squad" + format "Test" -> "India".
// Strips the format words and the trailing "Squad" so we get a clean team name.
function deriveTeamNameFromSquadType(squadType = '', format = '') {
  let name = String(squadType || '');
  // Remove trailing "Squad"
  name = name.replace(/\bsquad\b/gi, ' ');
  // Remove format descriptors.
  name = name.replace(/\bone-?off\b/gi, ' ')
    .replace(/\btest\b/gi, ' ')
    .replace(/\bodis?\b/gi, ' ')
    .replace(/\bt20is?\b/gi, ' ')
    .replace(/\bt20\b/gi, ' ')
    .replace(/\bt10\b/gi, ' ')
    .replace(/\bwomen'?s?\b/gi, ' Women ')
    .replace(/\b(\d+)(st|nd|rd|th)?\b/gi, ' ');
  name = name.replace(/\s+/g, ' ').trim();
  return name || String(squadType || '').replace(format, '').trim();
}



function decodeNextPayloadText(html = '') {
  return String(html)
    .replace(/\\"/g, '"')
    .replace(/\\u0026/g, '&')
    .replace(/\\\//g, '/');
}

function normalizeCricbuzzPath(value) {
  const text = String(value || '').trim();
  if (!text) return '';
  if (/^https?:\/\//i.test(text)) {
    try {
      return new URL(text).pathname;
    } catch {
      return '';
    }
  }
  if (text.startsWith('/')) return text;
  return `/${text}`;
}

function makeNewsSlug(value = '') {
  return String(value || '')
    .toLowerCase()
    .replace(/&amp;/g, 'and')
    .replace(/&/g, 'and')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120);
}

function extractHtmlAttribute(html = '', regex, attribute) {
  const match = String(html || '').match(regex);
  if (!match) return '';
  const source = match[0];
  const attrMatch = source.match(new RegExp(`${attribute}=["']([^"']+)["']`, 'i'));
  return attrMatch?.[1] ? decodeHtmlEntities(attrMatch[1]) : '';
}

function extractMetaContent(html = '', name) {
  const regex = new RegExp(
    `<meta[^>]+(?:property|name)=["']${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}["'][^>]*content=["']([^"']+)["'][^>]*>`,
    'i'
  );
  const match = String(html || '').match(regex);
  return match?.[1] ? decodeHtmlEntities(match[1]) : '';
}

function extractBalancedJsonObject(text = '', marker = '') {
  const source = String(text || '');
  const idx = source.indexOf(marker);
  if (idx < 0) return null;
  const start = source.indexOf('{', idx);
  if (start < 0) return null;

  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < source.length; i++) {
    const ch = source[i];
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
      continue;
    }
    if (ch === '{') depth += 1;
    if (ch === '}') {
      depth -= 1;
      if (depth === 0) return source.slice(start, i + 1);
    }
  }
  return null;
}

function extractBalancedJsonArray(text = '', marker = '') {
  const source = String(text || '');
  const idx = source.indexOf(marker);
  if (idx < 0) return null;
  const start = source.indexOf('[', idx);
  if (start < 0) return null;

  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < source.length; i++) {
    const ch = source[i];
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
      continue;
    }
    if (ch === '[') depth += 1;
    if (ch === ']') {
      depth -= 1;
      if (depth === 0) return source.slice(start, i + 1);
    }
  }
  return null;
}

function parseNewsDetailPayload(payload = '') {
  const detailText = extractBalancedJsonObject(payload, '"newsDetail":');
  if (!detailText) return null;
  try {
    return JSON.parse(detailText);
  } catch (err) {
    logger.debug({ msg: 'Failed to parse Cricbuzz news detail JSON', error: err.message });
    return null;
  }
}

function parseNewsCardsPayload(payload = '') {
  const cardsText = extractBalancedJsonArray(payload, '"newsCardsData":');
  if (!cardsText) return [];
  try {
    const parsed = JSON.parse(cardsText);
    return Array.isArray(parsed) ? parsed : [];
  } catch (err) {
    logger.debug({ msg: 'Failed to parse Cricbuzz latest news cards JSON', error: err.message });
    return [];
  }
}

function extractNextPayloadsFromHtml(html = '') {
  const scripts = String(html || '').match(/<script>(self\.__next_f\.push\((.*?)\))<\/script>/gs) || [];
  const payloads = [];
  for (const script of scripts) {
    const raw = script.match(/self\.__next_f\.push\((.*?)\)<\/script>/s)?.[1];
    if (!raw) continue;
    try {
      const parsed = JSON.parse(raw);
      const payload = parsed?.[1];
      if (typeof payload === 'string') payloads.push(payload);
    } catch {
      continue;
    }
  }
  return payloads;
}

function extractNewsCardsFromHtml(html = '') {
  const stories = [];
  const seen = new Set();

  for (const payload of extractNextPayloadsFromHtml(html)) {
    if (!payload.includes('"newsCardsData":')) continue;
    for (const story of parseNewsCardsPayload(payload)) {
      const id = String(story?.id || '').trim();
      if (!id || seen.has(id)) continue;
      seen.add(id);
      stories.push(story);
    }
  }

  const last = stories[stories.length - 1];
  return {
    paginatedData: stories,
    nextPaginationURL: last?.id ? `/api/cricket-news/${last.id}/latest-news` : null,
    source: 'cricbuzz-latest-page',
  };
}

function extractLatestNewsCursorFromHtml(html = '') {
  const match = String(html || '').match(/\/api\/cricket-news\/(\d+)\/latest-news/i);
  return match?.[1] || null;
}

function extractNewsDetailFromHtml(html = '') {
  for (const payload of extractNextPayloadsFromHtml(html)) {
    try {
      if (!payload.includes('"newsDetail":')) continue;
      const detail = parseNewsDetailPayload(payload);
      if (detail) {
        detail.imageUrl = detail.imageUrl || extractMetaContent(html, 'og:image') || extractMetaContent(html, 'twitter:image');
        return normalizeNewsDetailFields(detail);
      }
    } catch {
      continue;
    }
  }

  const detail = {};
  const headline = extractMetaContent(html, 'og:title') || extractHtmlText(html, /<h1[^>]*>(.*?)<\/h1>/is);
  const intro = extractMetaContent(html, 'description') || extractMetaContent(html, 'og:description');
  const imageUrl = extractMetaContent(html, 'og:image') || extractMetaContent(html, 'twitter:image');
  if (headline || intro || imageUrl) {
    detail.id = '';
    detail.headline = headline;
    detail.intro = intro;
    detail.body = '';
    detail.paragraphs = [];
    detail.imageUrl = imageUrl || '';
    return normalizeNewsDetailFields(detail);
  }
  return null;
}

function extractHtmlText(html = '', regex) {
  const match = String(html || '').match(regex);
  if (!match?.[1]) return '';
  return decodeHtmlEntities(match[1].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim());
}

function normalizeNewsDetailFields(detail = {}) {
  const paragraphs = [];
  const contentBlocks = Array.isArray(detail.content) ? detail.content : [];
  for (const block of contentBlocks) {
    const text = block?.content?.contentValue || block?.contentValue || block?.text || block?.paragraph || '';
    const clean = decodeHtmlEntities(String(text || '').replace(/\s+/g, ' ').trim());
    if (clean) paragraphs.push(clean);
  }
  if (Array.isArray(detail.paragraphs)) {
    for (const paragraph of detail.paragraphs) {
      const clean = decodeHtmlEntities(String(paragraph || '').replace(/\s+/g, ' ').trim());
      if (clean) paragraphs.push(clean);
    }
  }

  const relatedStories = Array.isArray(detail.relatedNews)
    ? detail.relatedNews.map((story) => ({
        id: String(story.id || ''),
        headline: story.hline || story.headline || '',
        intro: story.intro || '',
        context: story.context || '',
        publishedTime: story.pubTime || story.publishedTime || '',
        imageId: story.imageId ? String(story.imageId) : (story.coverImage?.id ? String(story.coverImage.id) : null),
        imageUrl: story.imageUrl || (story.imageId ? `https://static.cricbuzz.com/a/img/v1/i3/c${story.imageId}/i.jpg` : ''),
      }))
    : [];

  const imageId = detail.coverImage?.id || detail.imageId || detail.image_id || null;
  const imageUrl = detail.imageUrl || detail.coverImage?.imageUrl || detail.coverImage?.sourceUrl || (imageId ? `https://static.cricbuzz.com/a/img/v1/i3/c${imageId}/i.jpg` : '');

  return {
    id: String(detail.id || ''),
    headline: detail.headline || detail.hline || '',
    intro: detail.intro || '',
    body: paragraphs.length ? paragraphs.join('\n\n') : (detail.body || ''),
    paragraphs,
    source: detail.source || 'Cricbuzz',
    context: detail.context || '',
    publishedTime: detail.publishTime || detail.publishedTime || detail.lastUpdatedTime || '',
    imageId: imageId ? String(imageId) : null,
    imageUrl: imageUrl || '',
    relatedStories,
    storyType: detail.storyType || 'News',
    storyUrl: detail.storyUrl || '',
  };
}

function buildNewsPath(cursor) {
  if (!cursor) return '';
  const raw = String(cursor).trim();
  if (!raw) return '';

  if (raw.startsWith('/api/cricket-news/')) {
    return raw.replace(/^\/api/, '');
  }
  if (raw.startsWith('/cricket-news/')) return raw;

  const urlMatch = raw.match(/\/api\/cricket-news\/(\d+)\/([a-z-]+)/i);
  if (urlMatch) return `/cricket-news/${urlMatch[1]}/${urlMatch[2]}`;

  const idMatch = raw.match(/\d+/);
  return idMatch ? `/cricket-news/${idMatch[0]}/latest-news` : '';
}

function normalizeRankingGender(value) {
  const text = String(value || 'men').toLowerCase();
  return text === 'women' ? 'women' : 'men';
}

function normalizeRankingCategory(value) {
  const text = String(value || 'batting').toLowerCase().replace(/[_\s]/g, '-');
  if (['bowling', 'bowlers', 'bowler'].includes(text)) return 'bowling';
  if (['all-rounder', 'allrounder', 'all-rounders', 'allrounders'].includes(text)) return 'all-rounder';
  if (['teams', 'team'].includes(text)) return 'teams';
  return 'batting';
}

function normalizeRankingFormat(value) {
  const text = String(value || 'test').toLowerCase();
  if (text === 'odi' || text === 'odis') return 'odi';
  if (text === 't20' || text === 't20i' || text === 't20s') return 't20';
  return 'test';
}

function rankingImageUrl(row = {}) {
  const id = row.faceImageId || row.face_image_id || row.imageId || row.image_id;
  if (!id) return '';
  const normalized = String(id).startsWith('c') ? String(id).slice(1) : String(id);
  if (!/^\d+$/.test(normalized)) return '';
  return `https://static.cricbuzz.com/a/img/v1/i1/c${normalized}/i.jpg`;
}

function safeRankingInt(value) {
  const text = String(value ?? '').trim();
  if (!text || text === '$undefined' || text === 'undefined' || text === 'null') return 0;
  const match = text.match(/-?\d+/);
  return match ? Number(match[0]) : 0;
}

function safeRankingText(value) {
  const text = String(value ?? '').trim();
  if (!text || text === '$undefined' || text === 'undefined' || text === 'null') return '';
  return text;
}

function rankingMovement(value) {
  const text = String(value ?? '').trim().toLowerCase();
  if (!text || text === 'flat' || text === 'same') return 0;
  const match = text.match(/-?\d+/);
  const amount = match ? Number(match[0]) : 0;
  if (text.includes('down') || text.includes('fall')) return amount ? -Math.abs(amount) : -1;
  if (text.includes('up') || text.includes('rise')) return amount || 1;
  return 0;
}

function extractRankingsData(html = '') {
  const marker = '\\"categoryType\\"';
  const categoryIndex = html.indexOf(marker);
  const dataMarker = '\\"data\\":';
  const start = html.lastIndexOf(dataMarker, categoryIndex >= 0 ? categoryIndex : html.length);
  if (start < 0) return null;

  const bodyStart = start + dataMarker.length;
  let depth = 0;
  let end = -1;
  for (let i = bodyStart; i < html.length; i += 1) {
    const ch = html[i];
    if (ch === '{') depth += 1;
    if (ch === '}') {
      depth -= 1;
      if (depth === 0) {
        end = i + 1;
        break;
      }
    }
  }
  if (end < 0) return null;

  const escaped = html.slice(start, end);
  const jsonText = `{${decodeNextPayloadText(escaped)}}`;
  return JSON.parse(jsonText).data;
}

function parseRankingsHtml(html, { gender, category, format }) {
  const pageData = extractRankingsData(html);
  const formatData = pageData?.formatTypesData || {};
  const selected = formatData[format] || formatData[pageData?.initialFormatType] || Object.values(formatData)[0] || {};
  const rows = Array.isArray(selected.rank) ? selected.rank : [];
  const isTeam = category === 'teams';

  return {
    gender,
    category: isTeam ? 'teams' : pageData?.categoryType || category,
    format: selected.formatType || format,
    availableFormats: Object.keys(formatData),
    rows: rows.map((row, index) => {
      const common = {
        rank: safeRankingInt(row.rank) || index + 1,
        movement: rankingMovement(row.trend ?? row.movement),
        country: safeRankingText(row.country || row.countryCode),
        rating: safeRankingInt(row.rating),
        points: safeRankingInt(row.points),
        matches: safeRankingInt(row.matches),
        imageId: (() => {
          const id = row.faceImageId || row.face_image_id || row.imageId || row.image_id;
          return id && String(id) !== '$undefined' && String(id) !== 'undefined' ? String(id) : null;
        })(),
        imageUrl: rankingImageUrl(row),
        category: isTeam ? 'teams' : category,
        format,
        gender,
      };
      if (isTeam) {
        return {
          ...common,
          teamId: String(row.id || ''),
          teamName: row.name || '',
        };
      }
      return {
        ...common,
        playerId: String(row.id || ''),
        playerName: row.name || '',
      };
    }),
    source: 'cricbuzz',
    updatedAt: new Date().toISOString(),
  };
}

function stripTags(value = '') {
  return decodeHtmlEntities(String(value)
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim());
}

function makePlayerSlug(name = '') {
  return String(name || '')
    .toLowerCase()
    .replace(/&amp;/g, 'and')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function normalizePlayerImageUrl(url = '') {
  return decodeHtmlEntities(String(url || '').trim())
    .replace(/\s+\d+x.*$/i, '')
    .replace(/&amp;/g, '&');
}

function extractPlayerImage(html = '', playerId = '', slug = '') {
  const profileSlugMatch = html.match(new RegExp(`/profiles/${playerId}/([^"'<\\s/]+)`, 'i'));
  const preferredSlug = slug || profileSlugMatch?.[1] || '';
  if (preferredSlug) {
    const slugPattern = new RegExp(`https://static\\.cricbuzz\\.com/a/img/v1/i1/c(\\d+)/${preferredSlug}\\.jpg[^"'\\\\<\\s]*`, 'i');
    const slugMatch = html.match(slugPattern);
    if (slugMatch) {
      return { imageId: slugMatch[1], imageUrl: normalizePlayerImageUrl(slugMatch[0]) };
    }
  }

  const gthumbMatch = html.match(/https:\/\/static\.cricbuzz\.com\/a\/img\/v1\/i1\/c(\d+)\/[^"'\\<\s]*?\.jpg\?d=low&amp;p=gthumb/i);
  if (gthumbMatch) {
    return { imageId: gthumbMatch[1], imageUrl: normalizePlayerImageUrl(gthumbMatch[0]) };
  }
  return { imageId: null, imageUrl: '' };
}

function extractProfileValue(personalText = '', label = '', nextLabels = []) {
  const labels = [label, ...nextLabels].map((x) => String(x).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
  const next = labels.slice(1).join('|');
  const pattern = next
    ? new RegExp(`${labels[0]}\\s+([\\s\\S]*?)(?=\\s+(?:${next})\\s+|$)`, 'i')
    : new RegExp(`${labels[0]}\\s+([\\s\\S]*)$`, 'i');
  const match = personalText.match(pattern);
  return match ? match[1].replace(/\s+/g, ' ').trim() : '';
}

function parseCareerTable(html = '', title = '') {
  const start = html.indexOf(title);
  if (start < 0) return { formats: [], rows: {}, summary: [] };
  const segment = html.slice(start, start + 30000);
  const tableEnd = segment.indexOf('</table>');
  const table = tableEnd >= 0 ? segment.slice(0, tableEnd) : segment;
  const trMatches = [...table.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/gi)];
  const cellRows = trMatches.map((row) => {
    const cells = [...row[1].matchAll(/<(?:th|td)[^>]*>([\s\S]*?)<\/(?:th|td)>/gi)]
      .map((cell) => stripTags(cell[1]))
      .filter(Boolean);
    return cells;
  }).filter((row) => row.length > 0);

  const formats = (cellRows[0] || []).filter(Boolean);
  const rows = {};
  for (const row of cellRows.slice(1)) {
    const key = row[0];
    if (!key) continue;
    rows[key] = {};
    formats.forEach((formatName, index) => {
      rows[key][formatName] = row[index + 1] ?? '';
    });
  }

  const summary = formats.map((formatName) => {
    const entry = { format: formatName };
    for (const [key, values] of Object.entries(rows)) {
      entry[key] = values[formatName] ?? '';
    }
    return entry;
  });

  return { formats, rows, summary };
}

function parseRecentForm(html = '') {
  const start = html.indexOf('RECENT FORM');
  if (start < 0) return [];
  const end = html.indexOf('Batting Career Summary', start);
  const segment = html.slice(start, end > start ? end : start + 30000);
  const seen = new Set();
  return [...segment.matchAll(/<a href="\/live-cricket-scores\/([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi)]
    .map((match) => {
      const spans = [...match[2].matchAll(/<span[^>]*>([\s\S]*?)<\/span>/gi)]
        .map((span) => stripTags(span[1]))
        .filter(Boolean);
      if (spans.length < 4) return null;
      const item = {
        matchPath: `/live-cricket-scores/${match[1]}`,
        score: spans[0],
        opponent: spans[1],
        format: spans[2],
        date: spans[3],
      };
      const key = `${item.matchPath}:${item.score}:${item.opponent}:${item.format}:${item.date}`;
      if (seen.has(key)) return null;
      seen.add(key);
      return item;
    })
    .filter(Boolean);
}

function parsePlayerProfileHtml(html = '', playerId = '') {
  const titleName = decodeHtmlEntities(html.match(/<title>(.*?)Profile/i)?.[1] || '').trim();
  const name = titleName.replace(/\s+$/, '') || 'Player';
  const slug = makePlayerSlug(name);
  const image = extractPlayerImage(html, playerId, slug);
  const personalStart = html.indexOf('PERSONAL INFORMATION');
  const recentStart = html.indexOf('RECENT FORM', personalStart);
  const personalHtml = personalStart >= 0
    ? html.slice(Math.max(0, personalStart - 1000), recentStart > personalStart ? recentStart : personalStart + 6500)
    : '';
  const personalText = stripTags(personalHtml);
  const countryMatch = personalHtml.match(/src="https:\/\/static\.cricbuzz\.com\/a\/img\/v1\/30x20\/i1\/c\d+\/[^"]+\.jpg"\/><\/div><span[^>]*>([^<]+)<\/span>/i);
  const country = stripTags(countryMatch?.[1] || '');
  const labels = ['Birth Place', 'Height', 'Role', 'Batting Style', 'Bowling Style', 'Teams'];
  const batting = parseCareerTable(html, 'Batting Career Summary');
  const bowling = parseCareerTable(html, 'Bowling Career Summary');
  const teamsText = extractProfileValue(personalText, 'Teams', ['RECENT FORM']);
  const teams = teamsText ? teamsText.split(',').map((team) => team.trim()).filter(Boolean) : [];

  return {
    id: String(playerId),
    playerId: String(playerId),
    name,
    fullName: name,
    country,
    countryCode: country ? country.slice(0, 3).toUpperCase() : '',
    dateOfBirth: extractProfileValue(personalText, 'Born', labels),
    birthPlace: extractProfileValue(personalText, 'Birth Place', labels.slice(1)),
    role: extractProfileValue(personalText, 'Role', labels.slice(3)),
    battingStyle: extractProfileValue(personalText, 'Batting Style', labels.slice(4)),
    bowlingStyle: extractProfileValue(personalText, 'Bowling Style', labels.slice(5)),
    teams,
    imageId: image.imageId,
    imageUrl: image.imageUrl,
    careerSummary: batting.summary.map((row) => ({
      format: row.format,
      matches: row.Matches,
      innings: row.Innings,
      runs: row.Runs,
      average: row.Average,
      strikeRate: row.SR,
      hundreds: row['100s'],
      fifties: row['50s'],
      highest: row.Highest,
      wickets: bowling.rows.Wickets?.[row.format] || '',
      economy: bowling.rows.Eco?.[row.format] || '',
    })),
    battingStats: batting.summary,
    bowlingStats: bowling.summary,
    recentForm: parseRecentForm(html),
    achievements: [],
    stats: { batting: batting.rows, bowling: bowling.rows },
    source: 'cricbuzz',
  };
}

function normalizeSeriesTeamsFromSeriesData(raw, seriesId) {
  const teamMap = new Map();
  const addTeam = (team) => {
    if (!team) return;
    const teamId = String(team.teamId || team.id || team.team_id || team.teamId || '').trim();
    const teamName = String(team.teamName || team.name || team.team_name || '').trim();
    const teamShort = String(team.shortName || team.teamSName || team.teamShort || team.teamShortName || team.short_name || '').trim();
    const imageId = String(team.imageId || team.image_id || '').trim();
    const logoUrl = String(team.logoUrl || team.logo_url || '').trim();
    const normalizedName = teamName.toLowerCase();
    if (!teamName || ['tbc', 'tbd', 'unknown', 'n/a'].includes(normalizedName)) return;
    const key = teamId || normalizedName || teamShort.toLowerCase();
    if (!key || teamMap.has(key)) return;
    teamMap.set(key, {
      team_id: teamId,
      team_name: teamName,
      team_short: teamShort,
      logo_url: logoUrl || (imageId ? `https://static.cricbuzz.com/a/img/v1/i1/c${imageId}/i.jpg` : ''),
      image_id: imageId,
      players: Array.isArray(team.players) ? team.players : Array.isArray(team.squad) ? team.squad : [],
      matches_played: Number(team.matchesPlayed || team.matches_played || team.played || 0) || 0,
      wins: Number(team.matchesWon || team.wins || team.won || 0) || 0,
      losses: Number(team.matchesLost || team.losses || team.lost || 0) || 0,
    });
  };

  if (raw?.teams && Array.isArray(raw.teams)) {
    raw.teams.forEach(addTeam);
  }

  const matches = [];
  if (Array.isArray(raw?.matches)) matches.push(...raw.matches);
  if (Array.isArray(raw?.matchList)) matches.push(...raw.matchList);
  if (Array.isArray(raw?.typeMatches)) {
    for (const group of raw.typeMatches) {
      const seriesMatches = group?.seriesMatches || group?.matchList || group?.matches || [];
      for (const seriesGroup of Array.isArray(seriesMatches) ? seriesMatches : [seriesMatches]) {
        const wrapper = seriesGroup?.seriesAdWrapper || seriesGroup;
        if (Array.isArray(wrapper?.matches)) matches.push(...wrapper.matches);
      }
    }
  }

  for (const match of matches) {
    const matchData = match?.matchInfo || match?.match || match;
    addTeam(matchData?.team1);
    addTeam(matchData?.team2);
  }

  return {
    series_id: String(seriesId),
    teams: Array.from(teamMap.values()),
    updated_at: new Date().toISOString(),
  };
}

function fetchPointsTableInCleanProcess(seriesId, seriesSlug) {
  const url = `https://www.cricbuzz.com/cricket-series/${seriesId}/${seriesSlug || ''}/points-table`.replace(/\/+points-table$/, '/points-table');
  const script = String.raw`
const https = require('node:https');
function decodeNextPayloadText(html = '') {
  return String(html)
    .replace(/\\\"/g, '"')
    .replace(/\\u0026/g, '&')
    .replace(/\\\\\//g, '/');
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
      } else if (ch === '\\\\') {
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
https.get(${JSON.stringify(url)}, {
  headers: {
    'User-Agent': ${JSON.stringify(BROWSER_HEADERS['User-Agent'])},
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': 'https://www.cricbuzz.com/',
  },
}, (res) => {
  let data = '';
  res.setEncoding('utf8');
  res.on('data', (chunk) => { data += chunk; });
  res.on('end', () => {
    const text = decodeNextPayloadText(data);
    const key = '"pointsTableData":';
    const keyIndex = text.indexOf(key);
    if (keyIndex === -1) {
      console.log(JSON.stringify({ seriesId: ${JSON.stringify(String(seriesId))}, pointsTable: [{ groupName: 'Points Table', pointsTableInfo: [] }], source: 'cricbuzz' }));
      return;
    }
    const objectText = extractJsonObjectAt(text, text.indexOf('{', keyIndex));
    if (!objectText) {
      console.log(JSON.stringify({ seriesId: ${JSON.stringify(String(seriesId))}, pointsTable: [{ groupName: 'Points Table', pointsTableInfo: [] }], source: 'cricbuzz' }));
      return;
    }
    try {
      const parsed = JSON.parse(objectText);
      console.log(JSON.stringify(parsed));
    } catch (jsonErr) {
      try {
        const parsed = new Function('return (' + objectText + ');')();
        console.log(JSON.stringify(parsed));
      } catch (evalErr) {
        console.log(JSON.stringify({ seriesId: ${JSON.stringify(String(seriesId))}, pointsTable: [{ groupName: 'Points Table', pointsTableInfo: [] }], source: 'cricbuzz' }));
      }
    }
  });
}).on('error', (err) => {
  console.error(err.message);
  process.exit(1);
});
`;
  const result = spawnSync(process.execPath, ['-e', script], {
    encoding: 'utf8',
    maxBuffer: 10 * 1024 * 1024,
  });
  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || 'Failed to fetch points table').trim());
  }
  const output = String(result.stdout || '').trim();
  if (!output) {
    throw new Error('Empty points table payload from clean process');
  }
  return JSON.parse(output);
}

function extractEmbeddedNextObject(html, key) {
  const text = decodeNextPayloadText(html);
  const needle = `"${key}":`;
  const keyIndex = text.indexOf(needle);
  if (keyIndex === -1) return null;

  const startIndex = text.indexOf('{', keyIndex);
  if (startIndex === -1) return null;

  const objectText = extractJsonObjectAt(text, startIndex);
  if (!objectText) return null;

  try {
    return JSON.parse(objectText);
  } catch (err) {
    try {
      return new Function(`return (${objectText});`)();
    } catch (evalErr) {
      logger.debug({
        msg: 'Failed to parse embedded Next payload object',
        key,
        error: evalErr.message,
      });
      return null;
    }
  }
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
  const rawTitle = String(title || '').trim();
  if (!rawTitle) return '';

  const beforeSite = rawTitle.split('| Cricbuzz')[0].trim() || rawTitle;
  const beforeSchedule = beforeSite.replace(/\s+schedule[\s\S]*$/i, '').trim();
  const parts = beforeSchedule
    .split('|')
    .map((part) => part.trim())
    .filter(Boolean);
  const candidate = parts.length ? parts[parts.length - 1] : beforeSchedule;

  return candidate
    .toLowerCase()
    .replace(/cricbuzz\.com/g, '')
    .replace(/\b(schedule|live scores|scorecards?|points table|videos?|statistics?|results?)\b/g, '')
    .replace(/\band\b/g, ' ')
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
// Parse a ball outcome from natural-language commentary text. Cricbuzz live
// commentary (e.g. "1 run, to cover", "FOUR", "no run", "wide down leg") is
// often the only source of the ball result when the balls-map is empty, so the
// normalizer falls back to this. Returns { runs, result, event } or null when
// nothing parseable. `result` is the display token (e.g. '1', '4', 'Wd', 'W').
export function parseBallResultFromCommentary(text) {
  if (!text) return null;
  const lower = String(text).trim().toLowerCase();
  if (!lower) return null;

  // Wicket (but not "not out"). Checked first: a wicket can also score runs but
  // the canonical result token is W.
  if (/\b(out\b|wicket|caught|bowled|lbw|run[\s-]?out|stumped|c\s*&\s*b|c and b)\b/.test(lower)
    && !/\bnot out\b/.test(lower)) {
    return { runs: 0, result: 'W', event: 'WICKET' };
  }
  // Extras carry their own marker.
  if (/\bwide\b/.test(lower)) return { runs: 1, result: 'Wd', event: 'WIDE' };
  if (/\bno[\s-]?ball\b/.test(lower)) return { runs: 1, result: 'Nb', event: 'NO_BALL' };
  // Boundaries by word.
  if (/\bfour\b|\bboundary\b/.test(lower)) return { runs: 4, result: '4', event: 'FOUR' };
  if (/\bsix\b|\bmaximum\b/.test(lower)) return { runs: 6, result: '6', event: 'SIX' };
  // Dot ball.
  if (/\bno run\b|\bdot ball\b|^dot\b/.test(lower)) return { runs: 0, result: '0', event: 'NONE' };
  // "N run" / "N runs".
  const m = lower.match(/\b(\d+)\s+runs?\b/);
  if (m) {
    const r = Number(m[1]);
    const event = r === 4 ? 'FOUR' : r === 6 ? 'SIX' : 'NONE';
    return { runs: r, result: String(r), event };
  }
  return null;
}

// Normalize live-line status. Cricbuzz often omits a clean status enum, leaving
// 'unknown' even for in-progress matches. When the provider state field or the
// parent match context says the match is live, surface 'live' instead.
export function normalizeLiveLineStatus(rawStatus, context = {}) {
  const s = String(rawStatus || '').trim();
  const lower = s.toLowerCase();
  const stateLower = String(context.state || '').trim().toLowerCase();
  const liveRe = /^(live|in[\s-]?progress)$/;
  if (liveRe.test(lower)) return 'live';
  if (liveRe.test(stateLower)) return 'live';
  if ((!s || lower === 'unknown') && context.isLive === true) return 'live';
  return s && lower !== 'unknown' ? s : 'unknown';
}

export function buildLiveLineData(liveData, commData, ballsData, matchId) {
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
  
  // Canonical display result token, used for both latestBall.result and the
  // animation key. Boundaries/wickets keep their existing single-char tokens;
  // everything else uses the parsed result (e.g. '1' for "1 run") and only
  // falls back to runs when no result could be parsed.
  const resultToken = !latestBall ? 'NONE'
    : latestBall.event === 'WICKET' ? 'W'
      : latestBall.event === 'FOUR' ? '4'
        : latestBall.event === 'SIX' ? '6'
          : latestBall.event === 'WIDE' ? (latestBall.result || 'Wd')
            : latestBall.event === 'NO_BALL' ? (latestBall.result || 'Nb')
              : (latestBall.result || String(latestBall.runs || 0));

  // Build unique key for latest ball (for Flutter animation)
  // Format: matchId-innings-over.ball-score-wickets-result
  const latestBallKey = latestBall
    ? `${matchId}-${currentInningsId}-${latestBall.overNumber}.${latestBall.ballNumber}-${currentScore.runs}-${currentScore.wickets}-${resultToken}`
    : `${matchId}-${currentInningsId}-0.0-0-0-NONE`;

  return {
    matchId: String(matchId),
    status: normalizeLiveLineStatus(scoreDetails.status || header.status, {
      state: header.state,
      isLive: Boolean(miniscore.inningsId) && !/(complete|abandon|stumps|no result)/i.test(String(header.state || header.status || '')),
    }),
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
      result: resultToken,
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
export function extractLatestBall(ballsData, inningsId, commData = null) {
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
  const commentaryText = latest?.commentary || latestCommentary?.commentary || latestCommentary?.text || '';
  const parsed = parseBallResultFromCommentary(commentaryText);

  // Runs: structured ball-map/commentary fields first, parsed commentary as
  // fallback (the balls-map is frequently empty on live matches).
  let runs = Number(useCommentaryBall
    ? (latestCommentary.runs ?? latest?.totalRuns ?? latest?.runs ?? latest?.scoreValue)
    : (latest?.totalRuns ?? latest?.runs ?? latest?.scoreValue ?? latestCommentary?.runs));
  if (!Number.isFinite(runs)) runs = parsed ? parsed.runs : 0;

  // Display result token: structured label first, parsed commentary next.
  let result = String(useCommentaryBall
    ? (latestCommentary?.ballResult || latest?.ballLabel || '')
    : (latest?.ballType || latest?.displayScore || latest?.ballLabel || latestCommentary?.ballResult || '')).trim();
  if (!result && parsed) result = parsed.result;

  // Event enum: raw event first, parsed commentary next, derive from result last.
  let event = rawEvent && rawEvent !== 'NONE' ? rawEvent : '';
  if (!event && parsed) event = parsed.event;
  if (!event) {
    event = /(WICKET|OUT)$/i.test(result) ? 'WICKET'
      : String(result) === '4' ? 'FOUR'
        : String(result) === '6' ? 'SIX'
          : /Wd|WIDE/i.test(result) ? 'WIDE'
            : /Nb|NO.?BALL/i.test(result) ? 'NO_BALL'
              : 'NONE';
  }

  // Final result fallback when still empty: derive from event/runs.
  if (!result) {
    result = event === 'WICKET' ? 'W'
      : event === 'WIDE' ? 'Wd'
        : event === 'NO_BALL' ? 'Nb'
          : String(runs || 0);
  }

  return {
    overNumber,
    ballNumber,
    event,
    runs,
    result,
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
const SUPPORT_STAFF_PATTERN = /\b(?:head\s+coach|assistant\s+coach|batting\s+coach|bowling\s+coach|fielding\s+coach|support\s+staff|team\s+manager|manager|physio|analyst|selector|mentor|coach)\b/i;

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
    .replace(SUPPORT_STAFF_PATTERN, ' ')
    .replace(PLAYER_ROLE_PATTERN, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return name;
}

function isSupportStaffSquadEntry(rawName = '', playerName = '', role = '', context = '') {
  const combined = cleanText(`${rawName} ${playerName} ${role} ${context}`);
  return SUPPORT_STAFF_PATTERN.test(combined);
}

function cleanSquadRole(context = '', rawName = '') {
  const combined = cleanText(`${rawName} ${context}`);
  const matches = [...combined.matchAll(PLAYER_ROLE_PATTERN)].map((m) => m[1]);
  const role = matches.find((r) => !/^WK$/i.test(r)) || (/\(WK\)|wicket.?keeper/i.test(combined) ? 'WK-Batter' : '');
  return role
    .replace(/^Keeper$/i, 'WK-Batter')
    .replace(/^Wicket Keeper$/i, 'WK-Batter');
}

// Extracts the player's real Cricbuzz face image from the squad anchor markup.
// Player faces are served as `/a/img/v1/i1/c<faceImageId>/<player-slug>.jpg`
// (no NxN dimension segment — that prefix is used for team flags). The face
// image id is NOT the same as the player profile id, so it must be read from
// the markup. Returns nulls when no genuine face image is present, so callers
// can fall back to a neutral initials avatar instead of a wrong photo.
// Cricbuzz serves a generic grey silhouette (image id 182026) for players that
// have no real headshot. That is not a wrong face, but it is not a real photo
// either, so we treat it as "no image" and let the app render initials.
const CRICBUZZ_PLACEHOLDER_FACE_IDS = new Set(['182026']);

function extractSquadFaceImage(anchorHtml = '') {
  const matches = [...String(anchorHtml).matchAll(
    /static\.cricbuzz\.com\/a\/img\/v1\/i1\/c(\d+)\/([a-z0-9][a-z0-9-]*)\.jpg/gi,
  )];
  for (const m of matches) {
    const faceImageId = m[1];
    const slug = m[2].toLowerCase();
    // Skip team flag / generic placeholder slugs (defensive — flags normally
    // carry a size prefix such as 25x18 and are excluded by the regex above).
    if (slug === 'i' || /(?:^|[-_])flag(?:$|[-_])/.test(slug)) continue;
    if (CRICBUZZ_PLACEHOLDER_FACE_IDS.has(faceImageId)) {
      return { faceImageId: null, imageUrl: null };
    }
    return {
      faceImageId,
      // 192x192 is a crisp, square headshot crop that suits circular avatars.
      imageUrl: `https://static.cricbuzz.com/a/img/v1/192x192/i1/c${faceImageId}/${slug}.jpg`,
    };
  }
  return { faceImageId: null, imageUrl: null };
}

function normalizeSquadPlayer(p) {
  return {
    player_id: p.player_id,
    name: p.name,
    role: p.role || '',
    image_url: p.image_url || null,
    face_image_id: p.face_image_id || null,
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
    
    if (playerName && playerName.length > 2) {
      const contextStart = Math.max(0, playerMatch.index - 200);
      const contextEnd = Math.min(html.length, playerMatch.index + 300);
      const context = html.slice(contextStart, contextEnd);
      
      const precedingHtml = html.slice(Math.max(0, playerMatch.index - 800), playerMatch.index);
      const lastSectionMatch = precedingHtml.match(/(playing\s*xi|bench|substitutes|impact\s*player)/i);
      const section = lastSectionMatch ? lastSectionMatch[1].toLowerCase() : 'unknown';
      
      const role = cleanSquadRole(context, rawPlayerName) || extractPlayerRole(context);
      if (isSupportStaffSquadEntry(rawPlayerName, playerName, role, context)) {
        continue;
      }
      // Captain/keeper badges live inside the player's own anchor markup, so we
      // detect them from that player's text only (rawPlayerName) instead of a
      // wide character window, which would bleed badges from neighbouring cards.
      const isCaptain = /\(\s*c\s*(?:&\s*wk)?\s*\)/i.test(rawPlayerName)
        || /\(\s*wk\s*&\s*c\s*\)/i.test(rawPlayerName);
      const isWicketkeeper = /\(\s*(?:wk|c\s*&\s*wk|wk\s*&\s*c)\s*\)/i.test(rawPlayerName)
        || /wicket\.?keeper|WK-?Batter/i.test(rawPlayerName);
      // Face image id is parsed from the same anchor; it differs from the player
      // profile id, so we never synthesise it from the player id.
      const face = extractSquadFaceImage(nameHtml);
      
      allPlayers.push({
        player_id: String(playerId),
        name: playerName,
        role,
        is_captain: isCaptain,
        is_wicketkeeper: isWicketkeeper,
        is_impact_player: section.includes('impact'),
        is_substitute: section.includes('substitutes') || section.includes('bench'),
        image_url: face.imageUrl,
        face_image_id: face.faceImageId,
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
 * Parse scorecard from Cricbuzz HTML (Next.js with embedded JSON)
 */
function parseScorecardFromHtml(html, matchId) {
  logger.info({ msg: '[FIXED] Parsing scorecard HTML', matchId, htmlLength: html?.length || 0 });
  
  const innings = [];
  
  // Strategy 1: Try to extract from Next.js JSON payload
  // Look for self.__next_f.push patterns that contain scorecard data
  const nextDataPattern = /self\.__next_f\.push\(\[1,"([^"]+)"\]\)/g;
  let match;
  let combinedJson = '';
  
  while ((match = nextDataPattern.exec(html)) !== null) {
    try {
      // Unescape the JSON string
      const jsonStr = match[1]
        .replace(/\\"/g, '"')
        .replace(/\\n/g, '\n')
        .replace(/\\\\/g, '\\');
      
      combinedJson += jsonStr;
    } catch (err) {
      // Skip malformed JSON chunks
    }
  }
  
  // Try to find innings data in the combined JSON
  if (combinedJson) {
    // Look for batting/bowling data patterns
    const inningsPattern = /"innings[_\w]*":\s*\[([^\]]+)\]/gi;
    const battingPattern = /"bat(?:ting|smen|Cards)":\s*\[([^\]]+)\]/gi;
    const bowlingPattern = /"bowl(?:ing|ers|Cards)":\s*\[([^\]]+)\]/gi;
    
    // Try to extract structured innings data
    let inningsMatch;
    while ((inningsMatch = inningsPattern.exec(combinedJson)) !== null) {
      try {
        const inningsData = JSON.parse(`[${inningsMatch[1]}]`);
        if (Array.isArray(inningsData) && inningsData.length > 0) {
          innings.push(...inningsData);
        }
      } catch (err) {
        logger.debug({ msg: 'Could not parse innings JSON', matchId, error: err.message });
      }
    }
  }
  
  // Strategy 2: Parse from traditional HTML structure (fallback)
  if (innings.length === 0) {
    const inningsPattern = /<div[^>]*id="innings_(\d+)"[^>]*>([\s\S]*?)<\/div>\s*<\/div>/gi;
    let inningsMatch;
    
    while ((inningsMatch = inningsPattern.exec(html)) !== null) {
      const inningsId = inningsMatch[1];
      const inningsHtml = inningsMatch[2];
      
      // Extract innings header/name
      const headerMatch = inningsHtml.match(/<h2[^>]*>([\s\S]*?)<\/h2>/i) || 
                         inningsHtml.match(/<span[^>]*class="[^"]*cb-scrcrd-hdr-rw[^"]*"[^>]*>([\s\S]*?)<\/span>/i) ||
                         inningsHtml.match(/<div[^>]*class="[^"]*cb-col-100[^"]*"[^>]*>([\s\S]*?)<\/div>/i);
      const headerText = headerMatch ? headerMatch[1].replace(/<[^>]+>/g, '').trim() : `Innings ${inningsId}`;
      
      // Parse batting rows
      const battingRows = [];
      const battingPattern = /<tr[^>]*class="[^"]*cb-scrcrd-bat-tr[^"]*"[^>]*>([\s\S]*?)<\/tr>/gi;
      let battingMatch;
      
      while ((battingMatch = battingPattern.exec(inningsHtml)) !== null) {
        const rowHtml = battingMatch[1];
        const cells = rowHtml.match(/<td[^>]*>([\s\S]*?)<\/td>/gi) || [];
        
        if (cells.length >= 7) {
          const playerMatch = cells[0].match(/>([^<]+)</);
          const dismissalMatch = cells[1].match(/>([^<]+)</);
          
          const runs = parseInt(cells[2].replace(/<[^>]+>/g, '').trim()) || 0;
          const balls = parseInt(cells[3].replace(/<[^>]+>/g, '').trim()) || 0;
          const fours = parseInt(cells[5].replace(/<[^>]+>/g, '').trim()) || 0;
          const sixes = parseInt(cells[6].replace(/<[^>]+>/g, '').trim()) || 0;
          const strikeRate = parseFloat(cells[7]?.replace(/<[^>]+>/g, '').trim()) || (balls > 0 ? ((runs / balls) * 100).toFixed(2) : 0);
          
          battingRows.push({
            player: playerMatch ? playerMatch[1].trim() : '',
            dismissal: dismissalMatch ? dismissalMatch[1].trim() : '',
            runs,
            balls,
            fours,
            sixes,
            strike_rate: strikeRate
          });
        }
      }
      
      // Parse bowling rows
      const bowlingRows = [];
      const bowlingPattern = /<tr[^>]*class="[^"]*cb-scrcrd-bwl-tr[^"]*"[^>]*>([\s\S]*?)<\/tr>/gi;
      let bowlingMatch;
      
      while ((bowlingMatch = bowlingPattern.exec(inningsHtml)) !== null) {
        const rowHtml = bowlingMatch[1];
        const cells = rowHtml.match(/<td[^>]*>([\s\S]*?)<\/td>/gi) || [];
        
        if (cells.length >= 8) {
          const playerMatch = cells[0].match(/>([^<]+)</);
          const overs = cells[1].replace(/<[^>]+>/g, '').trim();
          const maidens = parseInt(cells[2].replace(/<[^>]+>/g, '').trim()) || 0;
          const runs = parseInt(cells[3].replace(/<[^>]+>/g, '').trim()) || 0;
          const wickets = parseInt(cells[4].replace(/<[^>]+>/g, '').trim()) || 0;
          const noBalls = parseInt(cells[6]?.replace(/<[^>]+>/g, '').trim()) || 0;
          const wides = parseInt(cells[7]?.replace(/<[^>]+>/g, '').trim()) || 0;
          const economy = parseFloat(cells[8]?.replace(/<[^>]+>/g, '').trim()) || 0;
          
          bowlingRows.push({
            player: playerMatch ? playerMatch[1].trim() : '',
            overs,
            maidens,
            runs,
            wickets,
            no_balls: noBalls,
            wides,
            economy
          });
        }
      }
      
      // Extract extras and total
      const extrasMatch = inningsHtml.match(/extras[\s\S]*?<td[^>]*>(\d+)<\/td>/i);
      const totalMatch = inningsHtml.match(/total[\s\S]*?<td[^>]*>(\d+)[\s\S]*?(\d+\.?\d*)<\/td>/i);
      
      if (battingRows.length > 0 || bowlingRows.length > 0) {
        innings.push({
          id: inningsId,
          name: headerText,
          batting: battingRows,
          bowling: bowlingRows,
          extras: extrasMatch ? parseInt(extrasMatch[1]) : 0,
          total: totalMatch ? parseInt(totalMatch[1]) : 0,
          overs: totalMatch && totalMatch[2] ? totalMatch[2] : ''
        });
      }
    }
  }
  
  // Strategy 3: Try to extract from page title and meta tags as last resort
  if (innings.length === 0) {
    const titleMatch = html.match(/<title>([^<]*)<\/title>/i);
    if (titleMatch) {
      const title = titleMatch[1];
      // Look for score patterns like "RR 214/6 vs GT 219/3"
      const scorePattern = /(\w+)\s+(\d+)\/(\d+).*?vs.*?(\w+)\s+(\d+)\/(\d+)/i;
      const scoreMatch = title.match(scorePattern);
      
      if (scoreMatch) {
        innings.push({
          id: '1',
          name: `${scoreMatch[1]} Innings`,
          batting: [],
          bowling: [],
          extras: 0,
          total: parseInt(scoreMatch[2]),
          overs: '',
          score: `${scoreMatch[2]}/${scoreMatch[3]}`
        });
        
        innings.push({
          id: '2',
          name: `${scoreMatch[4]} Innings`,
          batting: [],
          bowling: [],
          extras: 0,
          total: parseInt(scoreMatch[5]),
          overs: '',
          score: `${scoreMatch[5]}/${scoreMatch[6]}`
        });
      }
    }
  }
  
  logger.info({ 
    msg: '[FIXED] Scorecard HTML parsing complete', 
    matchId, 
    inningsFound: innings.length,
    hasBattingData: innings.some(i => i.batting && i.batting.length > 0),
    hasBowlingData: innings.some(i => i.bowling && i.bowling.length > 0)
  });
  
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
    
    if (playerName && playerName.length > 2) {
      const contextStart = Math.max(0, playerMatch.index - 200);
      const contextEnd = Math.min(html.length, playerMatch.index + 300);
      const context = html.slice(contextStart, contextEnd);
      
      const precedingHtml = html.slice(Math.max(0, playerMatch.index - 800), playerMatch.index);
      const lastSectionMatch = precedingHtml.match(/(playing\s*xi|bench|substitutes|impact\s*player)/i);
      const section = lastSectionMatch ? lastSectionMatch[1].toLowerCase() : 'unknown';
      
      const role = cleanSquadRole(context, rawPlayerName) || extractPlayerRole(context);
      if (isSupportStaffSquadEntry(rawPlayerName, playerName, role, context)) {
        continue;
      }
      // Captain/keeper badges live inside the player's own anchor markup, so we
      // detect them from that player's text only (rawPlayerName) instead of a
      // wide character window, which would bleed badges from neighbouring cards.
      const isCaptain = /\(\s*c\s*(?:&\s*wk)?\s*\)/i.test(rawPlayerName)
        || /\(\s*wk\s*&\s*c\s*\)/i.test(rawPlayerName);
      const isWicketkeeper = /\(\s*(?:wk|c\s*&\s*wk|wk\s*&\s*c)\s*\)/i.test(rawPlayerName)
        || /wicket\.?keeper|WK-?Batter/i.test(rawPlayerName);
      // Face image id is parsed from the same anchor; it differs from the player
      // profile id, so we never synthesise it from the player id.
      const face = extractSquadFaceImage(nameHtml);
      
      allPlayers.push({
        player_id: String(playerId),
        name: playerName,
        role,
        is_captain: isCaptain,
        is_wicketkeeper: isWicketkeeper,
        is_impact_player: section.includes('impact'),
        is_substitute: section.includes('substitutes') || section.includes('bench'),
        image_url: face.imageUrl,
        face_image_id: face.faceImageId,
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
  const embedded = extractEmbeddedNextObject(html, 'pointsTableData');
  if (embedded) {
    logger.info({
      msg: '[FIXED] Parsed embedded points table payload',
      seriesId,
      seriesName: embedded.seriesName || '',
      groups: Array.isArray(embedded.pointsTable) ? embedded.pointsTable.length : 0,
    });
    return {
      ...embedded,
      source: 'cricbuzz',
    };
  }

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
          const values = numbers.map((n) => parseInt(n.replace(/[><]/g, ''), 10));

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
        const cellText = cellMatch[1].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
        cells.push(cellText);
      }

      if (cells.length >= 7) {
        const rank = parseInt(cells[0], 10) || position;
        const teamName = cells[1];

        if (teamName && teamName.length > 1 && !teamName.match(/^\d+$/)) {
          const qualified = cells[1].includes('Q') ? 'Q' : (cells[1].includes('E') ? 'E' : '');

          pointsTableInfo.push({
            rank,
            team_id: '',
            team_name: teamName.replace(/\s+Q\s*$/, '').replace(/\s+E\s*$/, '').trim(),
            team_short: generateShortName(teamName),
            played: parseInt(cells[2], 10) || 0,
            won: parseInt(cells[3], 10) || 0,
            lost: parseInt(cells[4], 10) || 0,
            tied: parseInt(cells[5], 10) || 0,
            no_result: parseInt(cells[6], 10) || 0,
            points: parseInt(cells[7], 10) || 0,
            nrr: parseFloat(cells[8]) || 0,
            qualified,
            logo_url: ''
          });

          position++;
        }
      }
    }
  }

  logger.info({
    msg: '[FIXED] Parsed points table',
    seriesId,
    teams: pointsTableInfo.length,
  });

  return {
    seriesId: String(seriesId),
    pointsTable: [{
      groupName: 'Points Table',
      pointsTableInfo,
    }],
    source: 'cricbuzz',
  };
}
