import { BaseProvider } from '../base-provider.js';
import { cricbuzzApi } from './client.js';
import * as norm from './normalizer.js';
import { getCricbuzzImageUrl } from '../../lib/image-helper.js';
import logger from '../../lib/logger.js';

export class CricbuzzProvider extends BaseProvider {
  constructor() {
    super('cricbuzz', 1); // highest priority
  }

  healthState() {
    return this.healthy ? 'up' : 'down';
  }

  isConfigured() {
    return true; // no API key or config needed
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
      matchStats: 'full',
      matchOvers: 'full',
      scorecard: 'full',
      commentary: 'full',
      fullCommentary: 'full',
      quickAccess: 'full',
      seriesList: 'full',
      seriesInfo: 'full',
      pointsTable: 'full',
      playerInfo: 'full',
      teamInfo: 'full',
      newsStories: 'full',
      newsDetail: 'full',
      rankings: 'full',
      seriesStatsTypes: 'full',
      seriesStatsTable: 'full',
      seriesNews: 'full',
      matchNews: 'full',
      highlights: 'full',
      ballsMap: 'full',
      overByOver: 'full',
      upcomingSchedule: 'full',
      fullSchedule: 'full',
      matchSquads: 'full',
      liveLine: 'full',
      seriesTeams: 'full',
      seriesSquadGroups: 'full',
      seriesSquad: 'full',
    };
  }

  async getLiveMatches() {
    try {
      const raw = await cricbuzzApi.getHomeMatches();
      this.recordSuccess();
      return norm.normalizeHomeMatchList(raw, 'live');
    } catch (err) {
      this.recordFailure();
      logger.error({ msg: 'Cricbuzz getLiveMatches failed', error: err.message });
      throw err;
    }
  }

  async getUpcomingMatches() {
    try {
      const raw = await cricbuzzApi.getHomeMatches();
      this.recordSuccess();
      return norm.normalizeHomeMatchList(raw, 'upcoming');
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getRecentMatches() {
    try {
      const raw = await cricbuzzApi.getHomeMatches();
      this.recordSuccess();
      return norm.normalizeHomeMatchList(raw, 'recent');
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getMatchStats(matchId) {
    try {
      const raw = await cricbuzzApi.getMatchInfo(matchId);
      this.recordSuccess();
      return norm.normalizeMatchStats(raw);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getMatchOvers(matchId) {
    try {
      const raw = await cricbuzzApi.getMatchInfo(matchId);
      this.recordSuccess();
      return norm.normalizeMatchOvers(raw);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getMatchInfo(matchId) {
    try {
      const raw = await cricbuzzApi.getMatchInfo(matchId);
      this.recordSuccess();
      return norm.normalizeMatchDetail(raw);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getScorecard(matchId) {
    try {
      const raw = await cricbuzzApi.getScorecard(matchId);
      this.recordSuccess();
      return norm.normalizeScorecard(raw);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getCommentary(matchId) {
    try {
      const raw = await cricbuzzApi.getCommentary(matchId);
      this.recordSuccess();
      return norm.normalizeCommentary(raw);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getQuickAccess(matchId) {
    try {
      const raw = await cricbuzzApi.getQuickAccess(matchId);
      this.recordSuccess();
      return raw || {};
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getSeriesList() {
    try {
      const raw = await cricbuzzApi.getSeriesList();
      this.recordSuccess();
      return norm.normalizeSeriesList(raw);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getSeriesInfo(seriesId) {
    try {
      const raw = await cricbuzzApi.getSeriesInfo(seriesId);
      this.recordSuccess();
      const matches = norm.normalizeMatchList(raw);
      // Preserve seriesName from the API response but never override individual match series IDs
      return {
        seriesId: String(seriesId),
        seriesName: raw.seriesName || '',
        matches,
      };
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getPointsTable(seriesId) {
    try {
      const raw = await cricbuzzApi.getPointsTable(seriesId);
      this.recordSuccess();
      return norm.normalizePointsTable(raw);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getPlayerInfo(playerId) {
    try {
      const raw = await cricbuzzApi.getPlayerInfo(playerId);
      this.recordSuccess();
      return norm.normalizePlayerInfo(raw);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getTeamInfo(teamId) {
    try {
      const raw = await cricbuzzApi.getTeamInfo(teamId);
      this.recordSuccess();
      // Return raw team info normalized minimally
      const t = raw.team || raw;
      return {
        team_id: String(t.teamId || t.id || teamId),
        name: t.teamName || t.name || '',
        short_name: t.teamSName || t.shortName || '',
        logo_url: t.imageUrl || '',
        country: t.country || '',
        players: (t.players || []).map((p) => ({
          player_id: String(p.id || ''),
          name: p.name || '',
          role: p.role || '',
        })),
        last_updated: new Date().toISOString(),
      };
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getNewsStories(cursor) {
    try {
      const raw = await cricbuzzApi.getNewsStories(cursor);
      this.recordSuccess();
      return norm.normalizeNewsStories(raw);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getNewsDetail(newsId, story) {
    try {
      const raw = await cricbuzzApi.getNewsDetail(newsId, story);
      this.recordSuccess();
      return norm.normalizeNewsDetail(raw, story);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getRankings(params) {
    try {
      const raw = await cricbuzzApi.getRankings(params);
      this.recordSuccess();
      return raw;
    } catch (err) {
      this.recordFailure();
      logger.error({ msg: 'Cricbuzz getRankings failed', error: err.message, params });
      throw err;
    }
  }

  async getSeriesStatsTypes(seriesId) {
    try {
      const raw = await cricbuzzApi.getSeriesStatsTypes(seriesId);
      this.recordSuccess();
      return norm.normalizeSeriesStatsTypes(raw);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getSeriesStatsTable(seriesId, statType) {
    try {
      const raw = await cricbuzzApi.getSeriesStatsTable(seriesId, statType);
      this.recordSuccess();
      return norm.normalizeSeriesStatsTable(raw, statType);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getSeriesNews(seriesId, cursor) {
    try {
      const raw = await cricbuzzApi.getSeriesNews(seriesId, cursor);
      this.recordSuccess();
      return norm.normalizeSeriesNews(raw);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getMatchNews(matchId, cursor) {
    try {
      const raw = await cricbuzzApi.getMatchNews(matchId, cursor);
      this.recordSuccess();
      return norm.normalizeMatchNews(raw);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getFullCommentary(matchId, inningsId) {
    try {
      const raw = await cricbuzzApi.getFullCommentary(matchId, inningsId);
      this.recordSuccess();
      return norm.normalizeFullCommentary(raw, inningsId);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getHighlights(matchId, inningsId) {
    try {
      const raw = await cricbuzzApi.getHighlights(matchId, inningsId);
      this.recordSuccess();
      return norm.normalizeHighlights(raw, matchId, inningsId);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getBallsMap(matchId, inningsId) {
    try {
      const raw = await cricbuzzApi.getBallsMap(matchId, inningsId);
      this.recordSuccess();
      return norm.normalizeBallsMap(raw, matchId, inningsId);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getOverByOver(matchId, inningsId) {
    try {
      const raw = await cricbuzzApi.getOverByOver(matchId, inningsId);
      this.recordSuccess();
      return norm.normalizeOverByOver(raw, matchId, inningsId);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getUpcomingSchedule(type, timestamp) {
    try {
      const raw = await cricbuzzApi.getUpcomingSchedule(type, timestamp);
      this.recordSuccess();
      return norm.normalizeUpcomingSchedule(raw, type);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  // Real Cricbuzz series schedule LIST (section B of /cricket-schedule/series/all)
  // → array of { series_id, name, start_date, end_date, source } with the
  // AUTHORITATIVE series-level date ranges. Best-effort: a parse/fetch failure
  // returns [] rather than throwing.
  async getFullSchedule() {
    try {
      const html = await cricbuzzApi.getScheduleSeriesPage();
      this.recordSuccess();
      return norm.parseScheduleSeriesPage(html);
    } catch (err) {
      this.recordFailure();
      return [];
    }
  }

  async getMatchHeader(matchId) {
    try {
      const raw = await cricbuzzApi.getMatchHeader(matchId);
      if (!raw) return null;
      this.recordSuccess();
      return norm.normalizeMatchDetail(raw);
    } catch (err) {
      this.recordFailure();
      return null;
    }
  }

  async getMatchSquads(matchId) {
    try {
      const raw = await cricbuzzApi.getMatchSquads(matchId);
      this.recordSuccess();
      return norm.normalizeMatchSquads(raw, matchId);
    } catch (err) {
      this.recordFailure();
      logger.error({ msg: 'Cricbuzz getMatchSquads failed', matchId, error: err.message });
      throw err;
    }
  }

  async getLiveLine(matchId) {
    try {
      const raw = await cricbuzzApi.getLiveLine(matchId);
      this.recordSuccess();
      // Live line data is already normalized by the client. Return it directly
      // so API consumers receive data.latestBall, not data.data.latestBall.
      return raw;
    } catch (err) {
      this.recordFailure();
      logger.error({ msg: 'Cricbuzz getLiveLine failed', matchId, error: err.message });
      throw err;
    }
  }

  async getMatchInfoDetailed(matchId) {
    try {
      const raw = await cricbuzzApi.getMatchInfoDetailed(matchId);
      this.recordSuccess();
      return norm.normalizeMatchInfoDetailed(raw, matchId);
    } catch (err) {
      this.recordFailure();
      logger.error({ msg: 'Cricbuzz getMatchInfoDetailed failed', matchId, error: err.message });
      throw err;
    }
  }

  async getSeriesTeams(seriesId) {
    try {
      const raw = await cricbuzzApi.getSeriesTeams(seriesId);
      this.recordSuccess();
      return norm.normalizeSeriesTeams(raw, seriesId);
    } catch (err) {
      this.recordFailure();
      logger.error({ msg: 'Cricbuzz getSeriesTeams failed', seriesId, error: err.message });
      throw err;
    }
  }

  // Discovers squad groups (team x format) for a series.
  async getSeriesSquadGroups(seriesId) {
    try {
      const groups = await cricbuzzApi.getSeriesSquadGroups(seriesId);
      this.recordSuccess();
      return groups;
    } catch (err) {
      this.recordFailure();
      logger.error({ msg: 'Cricbuzz getSeriesSquadGroups failed', seriesId, error: err.message });
      throw err;
    }
  }

  // Fetches and normalizes a single squad group's players.
  async getSeriesSquad(seriesId, squadId) {
    try {
      const raw = await cricbuzzApi.getSeriesSquad(seriesId, squadId);
      this.recordSuccess();
      return norm.normalizeSeriesSquad(raw, seriesId, squadId);
    } catch (err) {
      this.recordFailure();
      logger.error({ msg: 'Cricbuzz getSeriesSquad failed', seriesId, squadId, error: err.message });
      throw err;
    }
  }
}

