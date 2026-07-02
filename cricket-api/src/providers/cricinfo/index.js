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
 */
export class CricinfoProvider extends BaseProvider {
  constructor() {
    super('cricinfo', 2);
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

  // --- match lists ---------------------------------------------------------

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

  // --- match detail --------------------------------------------------------

  async getMatchInfo(matchId) {
    return this.#run('getMatchInfo', async () => {
      const raw = await cricinfoClient.getSummary(matchId);
      return norm.normalizeMatchDetail(raw);
    });
  }

  // getMatchInfoDetailed is a Cricbuzz-only richer variant; site.api's summary
  // is the same header, so reuse it (the app calls this from provider-fetch).
  async getMatchInfoDetailed(matchId) {
    return this.#run('getMatchInfoDetailed', async () => {
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
      this.recordFailure();
      return null; // header is a best-effort fallback in the app
    }
  }

  async getScorecard(matchId) {
    return this.#run('getScorecard', async () => {
      const raw = await cricinfoClient.getSummary(matchId);
      const card = norm.normalizeScorecard(raw);
      if (!card || !card.innings.length) {
        return new ProviderIncompleteData('getScorecard', 'ESPN summary had no innings/roster data');
      }
      return card;
    });
  }

  async getCommentary(matchId) {
    return this.#run('getCommentary', async () => {
      const raw = await cricinfoClient.getPlayByPlay(matchId, undefined, 1);
      return norm.normalizeCommentary(raw);
    });
  }

  async getFullCommentary(matchId, inningsId) {
    return this.#run('getFullCommentary', async () => {
      // Page through ESPN commentary; inningsId is not a direct page selector on
      // site.api, so we fetch the first few pages and return the merged list.
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

  // --- series --------------------------------------------------------------

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
      const raw = await cricinfoClient.getSeriesScoreboard(seriesId);
      const table = norm.normalizePointsTable(raw);
      if (!table.length) {
        return new ProviderIncompleteData('getPointsTable', 'ESPN scoreboard exposed no standings');
      }
      return table;
    });
  }

  async getUpcomingSchedule(type, timestamp) {
    return this.#run('getUpcomingSchedule', async () => {
      const raw = await cricinfoClient.getScoreboardHeader();
      return norm.normalizeSchedule(raw);
    });
  }

  // --- player / team -------------------------------------------------------

  // ESPN player/team profiles are not reliably reachable by bare id via the
  // public site.api (they need the enclosing event/series context). Rather than
  // return a hollow record that would shadow Cricbuzz, declare unsupported.
  async getPlayerInfo(playerId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getPlayerInfo', 'ESPN site.api has no standalone player-by-id endpoint');
  }

  async getTeamInfo(teamId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getTeamInfo', 'ESPN site.api has no standalone team-by-id endpoint');
  }

  // --- methods ESPN site.api does not serve → typed "not supported" --------
  // These return (not throw) a sentinel so the manager cleanly falls through to
  // the next provider. recordSuccess() keeps the provider "up" for health.

  async getMatchStats(matchId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getMatchStats');
  }

  async getMatchOvers(matchId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getMatchOvers');
  }

  async getNewsStories(cursor) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getNewsStories');
  }

  async getSeriesStatsTypes(seriesId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getSeriesStatsTypes');
  }

  async getSeriesStatsTable(seriesId, statType) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getSeriesStatsTable');
  }

  async getSeriesNews(seriesId, cursor) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getSeriesNews');
  }

  async getMatchNews(matchId, cursor) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getMatchNews');
  }

  async getHighlights(matchId, inningsId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getHighlights');
  }

  async getBallsMap(matchId, inningsId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getBallsMap');
  }

  async getOverByOver(matchId, inningsId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getOverByOver');
  }

  async getMatchSquads(matchId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getMatchSquads');
  }

  async getLiveLine(matchId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getLiveLine');
  }

  async getSeriesTeams(seriesId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getSeriesTeams');
  }

  async getSeriesSquadGroups(seriesId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getSeriesSquadGroups');
  }

  async getSeriesSquad(seriesId, squadId) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getSeriesSquad');
  }

  async getRankings(params) {
    this.recordSuccess();
    return new ProviderFeatureNotSupported('getRankings');
  }
}
