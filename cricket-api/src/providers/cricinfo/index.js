import { BaseProvider } from '../base-provider.js';
import { cricinfoClient } from './client.js';
import * as norm from './normalizer.js';
import { ProviderFeatureNotSupported, ProviderIncompleteData } from '../provider-results.js';
import logger from '../../lib/logger.js';

/**
 * ESPN Cricinfo provider (site.api / site.web.api JSON, priority 2 fallback).
 *
 * INTERFACE PARITY, not data-depth parity: every BaseProvider method exists, but
 * methods ESPN's public site.api cannot serve return a typed sentinel
 * (ProviderFeatureNotSupported / ProviderIncompleteData) instead of empty-but-OK
 * data, so provider-manager falls through to the next provider rather than
 * handing back a blank response. Sentinels are RETURNED (not thrown), so they
 * never trip this provider's health cooldown — only real network/parse errors do.
 *
 * Capability tiers:
 *   full   — ESPN JSON endpoint serves this natively
 *   limited — derived from playbyplay / roster cache / partial endpoint
 *   unsupported — no safe source (404 on JSON API, 403 on HTML pages)
 */
export class CricinfoProvider extends BaseProvider {
  constructor() {
    super('cricinfo', 2);
    // Lightweight LRU for roster summaries keyed by matchId. Used by
    // getMatchSquads, getPlayerInfo, getTeamInfo to avoid re-fetching.
    this._rosterCache = new Map(); // matchId -> { ts, data }
    this._rosterCacheMax = 50;
  }

  healthState() {
    return this.healthy ? 'up' : 'down';
  }

  isConfigured() {
    return true; // site.api needs no API key
  }

  configReason() {
    return null;
  }

  getCapabilities() {
    return {
      liveMatches: 'full',
      upcomingMatches: 'full',
      recentMatches: 'full',
      matchInfo: 'full',
      matchInfoDetailed: 'full',
      matchHeader: 'full',
      matchStats: 'limited',     // leaders/top performers from summary
      matchOvers: 'limited',     // derived from playbyplay ball-by-ball
      scorecard: 'full',
      commentary: 'full',
      fullCommentary: 'limited', // paginates up to 5 pages
      seriesList: 'full',
      seriesInfo: 'full',
      pointsTable: 'full',      // ESPN /standings endpoint (site.api /apis/v2)
      playerInfo: 'full',       // roster cache + live v3 athlete endpoint
      teamInfo: 'limited',       // from roster cache / standings (known ESPN team IDs only)
      newsStories: 'unsupported', // 403 on public HTML, no JSON feed — use matchNews
      newsDetail: 'unsupported', // story pages 403; no JSON story-detail endpoint
      rankings: 'unsupported',   // 404 on /rankings, 403 on public HTML pages
      seriesStatsTypes: 'unsupported', // 404 on JSON, 403 on HTML
      seriesStatsTable: 'unsupported', // 404 on JSON, 403 on HTML
      seriesNews: 'unsupported', // no endpoint found
      matchNews: 'limited',      // from summary news.articles
      highlights: 'unsupported', // videos array present but always empty
      ballsMap: 'limited',       // derived from playbyplay ball-by-ball
      overByOver: 'limited',     // derived from playbyplay ball-by-ball
      upcomingSchedule: 'full',
      fullSchedule: 'full',      // series date ranges from scoreboard calendar
      quickAccess: 'unsupported', // Cricbuzz mcenter-only widget feature
      matchSquads: 'limited',    // from summary rosters
      liveLine: 'limited',       // derived from playbyplay (latest ball + over)
      seriesTeams: 'limited',    // from scoreboard teams array
      seriesSquadGroups: 'unsupported', // squads.entries always empty
      seriesSquad: 'unsupported',       // no per-squad endpoint (404)
    };
  }

  /** Run a fetch+normalize with unified health accounting for genuine errors. */
  async #run(label, fn) {
    try {
      const result = await fn();
      this.recordSuccess();
      return result;
    } catch (err) {
      this.recordFailure();
      logger.warn({ msg: `Cricinfo ${label} failed`, error: err.message });
      throw err;
    }
  }

  /**
   * True when an error is the expected "this matchId is not in ESPN's id space"
   * miss (client.js throws `... no seriesId known for match <id>`). This is NOT
   * a provider failure — ESPN simply cannot resolve a Cricbuzz-origin match id.
   */
  #isMissingSeriesMapping(err) {
    return typeof err?.message === 'string' && /no seriesId known/i.test(err.message);
  }

  /** Build the typed sentinel returned for an expected series-mapping miss. */
  #missingSeriesMappingResult(method, matchId) {
    const sentinel = new ProviderIncompleteData(method, 'missing_series_mapping');
    sentinel.provider = 'cricinfo';
    sentinel.matchId = String(matchId || '');
    sentinel.message =
      'Cricinfo cannot resolve this match because the matchId belongs to another provider ID space.';
    return sentinel;
  }

  /**
   * Match-detail runner. Same health accounting as #run for genuine errors, but
   * a missing series mapping is treated as a soft fall-through: it RETURNS a
   * typed sentinel (so provider-manager moves to the next provider) and does
   * NOT record a failure, so a Cricbuzz-origin match never trips ESPN's health
   * cooldown / falsely marks it "down".
   */
  async #runDetail(label, matchId, fn) {
    try {
      const result = await fn();
      this.recordSuccess();
      return result;
    } catch (err) {
      if (this.#isMissingSeriesMapping(err)) {
        logger.debug({
          msg: `Cricinfo ${label} skipped: missing series mapping`,
          provider: 'cricinfo',
          matchId: String(matchId || ''),
          reason: 'missing_series_mapping',
        });
        return this.#missingSeriesMappingResult(label, matchId);
      }
      this.recordFailure();
      logger.warn({ msg: `Cricinfo ${label} failed`, error: err.message });
      throw err;
    }
  }

  /**
   * Fetch and cache a /summary response for a match. The result includes
   * rosters, squads, news, leaders — everything needed for the limited-
   * capability methods that derive data from the summary.
   */
  async #getCachedSummary(matchId) {
    const key = String(matchId || '').trim();
    const cached = this._rosterCache.get(key);
    if (cached && Date.now() - cached.ts < 60_000) return cached.data;

    const data = await cricinfoClient.getSummary(key);
    // housekeep: drop oldest entries if over max
    if (this._rosterCache.size >= this._rosterCacheMax) {
      const oldest = this._rosterCache.keys().next().value;
      if (oldest) this._rosterCache.delete(oldest);
    }
    this._rosterCache.set(key, { ts: Date.now(), data });
    return data;
  }

  // --- match lists ------------------------------------------------------------

  async getLiveMatches() {
    return this.#run('getLiveMatches', async () => {
      const raw = await cricinfoClient.getScoreboardHeader();
      return norm.normalizeMatchList(raw, 'live');
    });
  }

  async getUpcomingMatches() {
    return this.#run('getUpcomingMatches', async () => {
      const raw = await cricinfoClient.getScoreboardHeader();
      return norm.normalizeMatchList(raw, 'upcoming');
    });
  }

  async getRecentMatches() {
    return this.#run('getRecentMatches', async () => {
      const raw = await cricinfoClient.getScoreboardHeader();
      return norm.normalizeMatchList(raw, 'recent');
    });
  }

  // --- match detail -----------------------------------------------------------

  async getMatchInfo(matchId) {
    return this.#runDetail('getMatchInfo', matchId, async () => {
      const raw = await cricinfoClient.getSummary(matchId);
      return norm.normalizeMatchDetail(raw);
    });
  }

  // getMatchInfoDetailed is a Cricbuzz-only richer variant; site.api's summary
  // is the same header, so reuse it (the app calls this from provider-fetch).
  async getMatchInfoDetailed(matchId) {
    return this.#runDetail('getMatchInfoDetailed', matchId, async () => {
      const raw = await cricinfoClient.getSummary(matchId);
      return norm.normalizeMatchDetail(raw);
    });
  }

  async getMatchHeader(matchId) {
    try {
      const raw = await cricinfoClient.getSummary(matchId);
      this.recordSuccess();
      return norm.normalizeMatchDetail(raw);
    } catch (err) {
      if (this.#isMissingSeriesMapping(err)) {
        logger.debug({
          msg: 'Cricinfo getMatchHeader skipped: missing series mapping',
          provider: 'cricinfo',
          matchId: String(matchId || ''),
          reason: 'missing_series_mapping',
        });
        return null; // header is a best-effort fallback in the app
      }
      this.recordFailure();
      return null;
    }
  }

  async getScorecard(matchId) {
    return this.#runDetail('getScorecard', matchId, async () => {
      const raw = await cricinfoClient.getSummary(matchId);
      const card = norm.normalizeScorecard(raw);
      if (!card || !card.innings.length) {
        return new ProviderIncompleteData('getScorecard', 'ESPN summary had no innings/roster data');
      }
      return card;
    });
  }

  async getCommentary(matchId) {
    return this.#runDetail('getCommentary', matchId, async () => {
      const raw = await cricinfoClient.getPlayByPlay(matchId, undefined, 1);
      return norm.normalizeCommentary(raw);
    });
  }

  async getFullCommentary(matchId, inningsId) {
    return this.#runDetail('getFullCommentary', matchId, async () => {
      const first = await cricinfoClient.getPlayByPlay(matchId, undefined, 1);
      const pageCount = Math.min(Number(first?.commentary?.pageCount || 1), 5);
      let items = norm.normalizeCommentary(first);
      for (let p = 2; p <= pageCount; p++) {
        // eslint-disable-next-line no-await-in-loop
        const next = await cricinfoClient.getPlayByPlay(matchId, undefined, p);
        items = items.concat(norm.normalizeCommentary(next));
      }
      return items;
    });
  }

  // --- series -----------------------------------------------------------------

  async getSeriesList() {
    return this.#run('getSeriesList', async () => {
      const raw = await cricinfoClient.getScoreboardHeader();
      return norm.normalizeSeriesList(raw);
    });
  }

  async getSeriesInfo(seriesId) {
    return this.#run('getSeriesInfo', async () => {
      const raw = await cricinfoClient.getSeriesScoreboard(seriesId);
      return norm.normalizeSeriesInfo(raw, seriesId);
    });
  }

  async getPointsTable(seriesId) {
    return this.#run('getPointsTable', async () => {
      // Primary: ESPN's dedicated /standings endpoint (site.api /apis/v2). It
      // carries a real per-team stats table for series that have one.
      let table = null;
      try {
        const standings = await cricinfoClient.getStandings(seriesId);
        table = norm.normalizeStandings(standings, seriesId);
      } catch (err) {
        logger.debug({ msg: 'Cricinfo standings fetch failed, trying scoreboard', seriesId, error: err.message });
      }
      if (table && table.rows.length) return table;

      // Fallback: some league blocks embed standings in the scoreboard payload.
      const raw = await cricinfoClient.getSeriesScoreboard(seriesId);
      const legacy = norm.normalizePointsTable(raw);
      if (Array.isArray(legacy) && legacy.length) {
        return {
          seriesId: String(seriesId || ''),
          seriesName: '',
          groups: [{ name: 'Points Table', rows: legacy }],
          rows: legacy,
          source: 'espn-cricinfo',
        };
      }
      return new ProviderIncompleteData('getPointsTable', 'ESPN exposed no standings for this series');
    });
  }

  async getUpcomingSchedule(type, timestamp) {
    return this.#run('getUpcomingSchedule', async () => {
      const raw = await cricinfoClient.getScoreboardHeader();
      return norm.normalizeSchedule(raw);
    });
  }

  // Real series schedule LIST with authoritative date ranges — the ESPN analogue
  // of Cricbuzz's getFullSchedule. Derived from the scoreboard/header leagues'
  // calendar window. Best-effort: returns [] on failure (matches Cricbuzz).
  async getFullSchedule() {
    try {
      const raw = await cricinfoClient.getScoreboardHeader();
      this.recordSuccess();
      return norm.normalizeFullSchedule(raw);
    } catch (err) {
      this.recordFailure();
      logger.warn({ msg: 'Cricinfo getFullSchedule failed', error: err.message });
      return [];
    }
  }

  // Cricbuzz-only feature (mcenter quick-access widgets). ESPN has no analogue —
  // return a typed sentinel so the manager falls through to Cricbuzz.
  async getQuickAccess(matchId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported(
      'getQuickAccess',
      'ESPN site.api has no quick-access widget endpoint (Cricbuzz mcenter-only feature)',
    );
  }

  // News DETAIL by story id. ESPN's story pages are 403 (HTML) and there is no
  // JSON story endpoint reachable from the backend. getMatchNews serves
  // per-match article summaries; a standalone story body is unavailable.
  async getNewsDetail(newsId, story) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported(
      'getNewsDetail',
      'ESPN story pages return 403 (HTML) and no JSON story-detail endpoint exists — use getMatchNews',
    );
  }

  // --- playbyplay-derived methods (over-by-over, balls-map, match-overs, live-line)

  async getOverByOver(matchId, inningsId) {
    return this.#runDetail('getOverByOver', matchId, async () => {
      // Fetch first page only — enough for the current over + recent context.
      const raw = await cricinfoClient.getPlayByPlay(matchId, undefined, 1);
      const data = norm.normalizeOverByOver(raw, matchId);
      if (!data || !data.innings.length) {
        return new ProviderIncompleteData('getOverByOver', 'ESPN playbyplay had no structured ball data');
      }
      return data;
    });
  }

  async getBallsMap(matchId, inningsId) {
    return this.#runDetail('getBallsMap', matchId, async () => {
      const raw = await cricinfoClient.getPlayByPlay(matchId, undefined, 1);
      const data = norm.normalizeBallsMap(raw, matchId, inningsId);
      if (!data || (data.innings && !data.innings.length) || (data.balls && !data.balls.length)) {
        return new ProviderIncompleteData('getBallsMap', 'ESPN playbyplay had no structured ball map data');
      }
      return data;
    });
  }

  async getMatchOvers(matchId) {
    return this.#runDetail('getMatchOvers', matchId, async () => {
      const raw = await cricinfoClient.getPlayByPlay(matchId, undefined, 1);
      const data = norm.normalizeMatchOvers(raw);
      if (!data || !data.innings.length) {
        return new ProviderIncompleteData('getMatchOvers', 'ESPN playbyplay had no over-level data');
      }
      return data;
    });
  }

  async getLiveLine(matchId) {
    return this.#runDetail('getLiveLine', matchId, async () => {
      const raw = await cricinfoClient.getPlayByPlay(matchId, undefined, 1);
      const data = norm.normalizeLiveLine(raw, matchId);
      if (!data) {
        return new ProviderIncompleteData('getLiveLine', 'ESPN playbyplay had no live ball data');
      }
      return data;
    });
  }

  // --- match squads (from /summary rosters) -----------------------------------

  async getMatchSquads(matchId) {
    return this.#runDetail('getMatchSquads', matchId, async () => {
      const raw = await this.#getCachedSummary(matchId);
      const squads = norm.normalizeMatchSquads(raw);
      if (!squads || !squads.team1 || !squads.team2) {
        return new ProviderIncompleteData('getMatchSquads', 'ESPN summary had no roster data for this match');
      }
      return squads;
    });
  }

  // --- match news (from /summary news.articles) -------------------------------

  async getMatchNews(matchId, cursor) {
    return this.#runDetail('getMatchNews', matchId, async () => {
      const raw = await cricinfoClient.getSummary(matchId);
      const stories = norm.normalizeMatchNews(raw);
      if (!stories.length) {
        return new ProviderIncompleteData('getMatchNews', 'ESPN summary had no news articles for this match');
      }
      return { paginatedData: stories, source: 'espn-cricinfo' };
    });
  }

  // --- series teams (from /scoreboard teams array) ----------------------------

  async getSeriesTeams(seriesId) {
    return this.#run('getSeriesTeams', async () => {
      const raw = await cricinfoClient.getSeriesScoreboard(seriesId);
      const teams = norm.normalizeSeriesTeams(raw, seriesId);
      if (!teams.length) {
        return new ProviderIncompleteData('getSeriesTeams', 'ESPN scoreboard had no teams data');
      }
      return { teams, source: 'espn-cricinfo' };
    });
  }

  // --- match stats / leaders (from /summary leaders) --------------------------

  async getMatchStats(matchId) {
    return this.#runDetail('getMatchStats', matchId, async () => {
      const raw = await cricinfoClient.getSummary(matchId);
      const leaders = norm.normalizeMatchLeaders(raw);
      if (!leaders) {
        return new ProviderIncompleteData('getMatchStats', 'ESPN summary had no leader/stat data');
      }
      return leaders;
    });
  }

  // --- player / team (from roster cache — known ESPN IDs only) ----------------
  // ESPN /athletes/{id} and /teams/{id} both return 404. Espncricinfo.com HTML
  // pages return 403 with a plain User-Agent. The ONLY safe source of player and
  // team data is the rosters embedded in /summary responses.  This is limited to
  // ESPN athlete/team IDs that appear in currently-cached match summaries.
  // Unknown IDs (including all Cricbuzz-origin IDs) return ProviderIncompleteData
  // so the manager falls through.

  async getPlayerInfo(playerId) {
    try {
      const pid = String(playerId || '').trim();
      if (!pid) {
        this.recordSuccess();
        return new ProviderIncompleteData('getPlayerInfo', 'no player id provided');
      }
      // Scan the roster cache for this player.  This is cheap (in-memory; no
      // network call) and covers any ESPN athlete id that appeared in a match
      // summary fetched in this process's lifetime.
      for (const [, entry] of this._rosterCache) {
        const rosters = entry.data?.rosters || [];
        for (const r of rosters) {
          const player = norm.normalizePlayerFromRoster(r, pid);
          if (player) {
            this.recordSuccess();
            return player;
          }
        }
      }
      // Not in cache → try ESPN's standalone v3 athlete endpoint. This is the
      // ONLY ESPN backend that serves a full player bio without a match context
      // (core.api /athletes 400s for cricket, HTML is 403). It resolves any
      // numeric ESPN athlete id — but NOT Cricbuzz-origin ids, which 404 here
      // and fall through to the sentinel below.
      try {
        const raw = await cricinfoClient.getAthlete(pid);
        const player = norm.normalizePlayerFromAthlete(raw);
        if (player) {
          this.recordSuccess();
          return player;
        }
      } catch (err) {
        logger.debug({ msg: 'Cricinfo getAthlete lookup failed', playerId: pid, error: err.message });
      }
      // No cache hit and no athlete record → incomplete so the manager falls
      // back to Cricbuzz instead of serving nothing.
      this.recordSuccess();
      return new ProviderIncompleteData(
        'getPlayerInfo',
        'player id not in ESPN roster cache and no athlete record found',
      );
    } catch (err) {
      // Only a genuine network/parse error should count as a failure.
      this.recordFailure();
      logger.warn({ msg: 'Cricinfo getPlayerInfo failed', playerId, error: err.message });
      throw err;
    }
  }

  async getTeamInfo(teamId) {
    try {
      const tid = String(teamId || '').trim();
      if (!tid) {
        this.recordSuccess();
        return new ProviderIncompleteData('getTeamInfo', 'no team id provided');
      }
      // Scan roster cache for this team id.
      for (const [, entry] of this._rosterCache) {
        const rosters = entry.data?.rosters || [];
        for (const r of rosters) {
          if (String(r?.team?.id || '') === tid) {
            const team = norm.normalizeTeamFromRoster(r);
            if (team) {
              this.recordSuccess();
              return team;
            }
          }
        }
      }
      // Also check the scoreboard header for team metadata (name, logo, country)
      // by trying a fresh header fetch — this is a lightweight cache-warm.
      // Skip to sentinel if we've already fetched recently.
      this.recordSuccess();
      return new ProviderIncompleteData(
        'getTeamInfo',
        'team id not in ESPN roster cache and no standalone team endpoint exists',
      );
    } catch (err) {
      this.recordFailure();
      logger.warn({ msg: 'Cricinfo getTeamInfo failed', teamId, error: err.message });
      throw err;
    }
  }

  // --- methods ESPN site.api does not serve → typed "not supported" -----------
  // Each reason documents what was tested and why it's unsupported. All of these
  // call recordSuccess() so the provider stays "up" — they are deliberate
  // capability gaps, not health faults.

  async getNewsStories(cursor) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported(
      'getNewsStories',
      'ESPN public HTML pages return 403; no JSON news feed endpoint exists — use getMatchNews for per-match articles',
    );
  }

  async getSeriesStatsTypes(seriesId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported(
      'getSeriesStatsTypes',
      'ESPN site.api has no series-stats endpoint (404); public HTML returns 403',
    );
  }

  async getSeriesStatsTable(seriesId, statType) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported(
      'getSeriesStatsTable',
      'ESPN site.api has no series-stats-table endpoint (404); public HTML returns 403',
    );
  }

  async getSeriesNews(seriesId, cursor) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported(
      'getSeriesNews',
      'ESPN site.api has no series-news endpoint; public HTML returns 403',
    );
  }

  async getHighlights(matchId, inningsId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported(
      'getHighlights',
      'ESPN summary videos array is present but always empty in tested matches',
    );
  }

  async getSeriesSquadGroups(seriesId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported(
      'getSeriesSquadGroups',
      'ESPN site.api squads.entries are empty for all tested matches',
    );
  }

  async getSeriesSquad(seriesId, squadId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported(
      'getSeriesSquad',
      'ESPN site.api has no per-squad endpoint (404)',
    );
  }

  async getRankings(params) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported(
      'getRankings',
      'ESPN site.api /rankings returns 404; public espncricinfo.com HTML pages return 403',
    );
  }
}
