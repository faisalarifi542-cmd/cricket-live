import axios from 'axios';
import { BaseProvider } from '../base-provider.js';
import config from '../../config/index.js';
import logger from '../../lib/logger.js';

const client = axios.create({
  baseURL: config.providers.cricketdata.baseUrl,
  timeout: 10000,
  headers: { 'Accept': 'application/json' },
});

/**
 * CricketData.org (cricapi.com) fallback provider.
 * Requires API key — limited free tier (100 req/day).
 */
export class CricketDataProvider extends BaseProvider {
  constructor() {
    super('cricketdata', 3); // lowest priority
  }

  #params(extra = {}) {
    return { params: { apikey: config.providers.cricketdata.apiKey, ...extra } };
  }

  async getLiveMatches() {
    if (!config.providers.cricketdata.apiKey) throw new Error('CricketData API key not configured');
    try {
      const { data } = await client.get('/currentMatches', this.#params());
      this.recordSuccess();
      return this.#normalizeMatchList(data?.data || [], 'live');
    } catch (err) {
      this.recordFailure();
      logger.warn({ msg: 'CricketData getLiveMatches failed', error: err.message });
      throw err;
    }
  }

  async getUpcomingMatches() {
    if (!config.providers.cricketdata.apiKey) throw new Error('CricketData API key not configured');
    try {
      const { data } = await client.get('/matches', this.#params({ type: 'upcoming' }));
      this.recordSuccess();
      return this.#normalizeMatchList(data?.data || [], 'upcoming');
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getRecentMatches() {
    if (!config.providers.cricketdata.apiKey) throw new Error('CricketData API key not configured');
    try {
      const { data } = await client.get('/matches', this.#params({ type: 'recent' }));
      this.recordSuccess();
      return this.#normalizeMatchList(data?.data || [], 'recent');
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getMatchInfo(matchId) {
    if (!config.providers.cricketdata.apiKey) throw new Error('CricketData API key not configured');
    try {
      const { data } = await client.get('/match_info', this.#params({ id: matchId }));
      this.recordSuccess();
      return this.#normalizeMatchDetail(data?.data || {});
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getScorecard(matchId) {
    if (!config.providers.cricketdata.apiKey) throw new Error('CricketData API key not configured');
    try {
      const { data } = await client.get('/match_scorecard', this.#params({ id: matchId }));
      this.recordSuccess();
      return this.#normalizeScorecard(data?.data || {});
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getCommentary(_matchId) {
    // CricketData free tier doesn't support ball-by-ball commentary
    throw new Error('Commentary not available from CricketData provider');
  }

  async getSeriesList() {
    if (!config.providers.cricketdata.apiKey) throw new Error('CricketData API key not configured');
    try {
      const { data } = await client.get('/series', this.#params());
      this.recordSuccess();
      return (data?.data || []).map((s) => ({
        series_id: String(s.id || ''),
        name: s.name || '',
        season: '',
        start_date: s.startDate || null,
        end_date: s.endDate || null,
      }));
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getSeriesInfo(seriesId) {
    if (!config.providers.cricketdata.apiKey) throw new Error('CricketData API key not configured');
    try {
      const { data } = await client.get('/series_info', this.#params({ id: seriesId }));
      this.recordSuccess();
      return this.#normalizeMatchList(data?.data?.matchList || []);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getPointsTable(seriesId) {
    if (!config.providers.cricketdata.apiKey) throw new Error('CricketData API key not configured');
    try {
      const { data } = await client.get('/series_points', this.#params({ id: seriesId }));
      this.recordSuccess();
      return (data?.data || []).map((e, i) => ({
        team_id: String(e.teamId || ''),
        team_name: e.teamName || '',
        team_short: '',
        position: i + 1,
        played: e.played || 0,
        won: e.win || 0,
        lost: e.loss || 0,
        tied: e.tied || 0,
        no_result: e.nr || 0,
        points: e.points || 0,
        nrr: parseFloat(e.nrr || 0),
        group: e.group || '',
        qualified: false,
      }));
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getPlayerInfo(playerId) {
    if (!config.providers.cricketdata.apiKey) throw new Error('CricketData API key not configured');
    try {
      const { data } = await client.get('/players_info', this.#params({ id: playerId }));
      this.recordSuccess();
      const p = data?.data || {};
      return {
        player_id: String(p.id || playerId),
        name: p.name || '',
        full_name: p.name || '',
        dob: p.dateOfBirth || null,
        nationality: p.country || '',
        role: p.role || '',
        batting_style: p.battingStyle || '',
        bowling_style: p.bowlingStyle || '',
        image_url: p.playerImg || '',
        teams: [],
        bio: '',
        stats: {},
        last_updated: new Date().toISOString(),
      };
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getTeamInfo(teamId) {
    throw new Error('Team info not supported by CricketData provider');
  }

  // --- Internal normalizers ---

  #normalizeMatchList(matches, filter) {
    return matches.map((m) => ({
      match_id: String(m.id || ''),
      series_id: String(m.series_id || ''),
      series_name: m.series || '',
      match_format: (m.matchType || '').toLowerCase(),
      status: this.#mapStatus(m.status, m.matchStarted, m.matchEnded),
      status_text: m.status || '',
      team1: { id: String(m.teamInfo?.[0]?.id || ''), name: m.teamInfo?.[0]?.name || m.teams?.[0] || '', short_name: m.teamInfo?.[0]?.shortname || '' },
      team2: { id: String(m.teamInfo?.[1]?.id || ''), name: m.teamInfo?.[1]?.name || m.teams?.[1] || '', short_name: m.teamInfo?.[1]?.shortname || '' },
      venue: { name: m.venue || '', city: '', country: '' },
      start_time: m.dateTimeGMT || m.date || null,
      score: this.#extractScore(m.score || []),
      last_updated: new Date().toISOString(),
    }));
  }

  #normalizeMatchDetail(m) {
    return {
      match_id: String(m.id || ''),
      series_id: String(m.series_id || ''),
      series_name: m.series || '',
      match_format: (m.matchType || '').toLowerCase(),
      status: this.#mapStatus(m.status, m.matchStarted, m.matchEnded),
      status_text: m.status || '',
      team1: { id: String(m.teamInfo?.[0]?.id || ''), name: m.teamInfo?.[0]?.name || '', short_name: m.teamInfo?.[0]?.shortname || '', innings: [] },
      team2: { id: String(m.teamInfo?.[1]?.id || ''), name: m.teamInfo?.[1]?.name || '', short_name: m.teamInfo?.[1]?.shortname || '', innings: [] },
      venue: { name: m.venue || '', city: '', country: '' },
      start_time: m.dateTimeGMT || null,
      toss: { winner: m.tossWinner || '', decision: m.tossChoice || '' },
      result: m.status || '',
      innings: [],
      last_updated: new Date().toISOString(),
    };
  }

  #normalizeScorecard(m) {
    const scorecard = m.scorecard || m.score || [];
    return {
      innings: scorecard.map((inn, idx) => ({
        innings_number: idx + 1,
        batting_team: inn.batting || '',
        batting_team_id: '',
        total: { runs: inn.r || 0, wickets: inn.w || 0, overs: inn.o || 0 },
        run_rate: 0,
        extras: { total: 0, byes: 0, leg_byes: 0, wides: 0, no_balls: 0, penalty: 0 },
        batting: (inn.batsman || []).map((b) => ({
          player_id: String(b.id || ''), name: b.name || '', runs: b.r || 0, balls: b.b || 0,
          fours: b['4s'] || 0, sixes: b['6s'] || 0, strike_rate: b.sr || 0,
          dismissal: b.dismissal || '', is_batting: false, is_striker: false,
        })),
        bowling: (inn.bowler || []).map((b) => ({
          player_id: String(b.id || ''), name: b.name || '', overs: b.o || 0, maidens: b.m || 0,
          runs: b.r || 0, wickets: b.w || 0, economy: b.eco || 0,
          dots: 0, wides: 0, no_balls: 0, is_bowling: false,
        })),
        fall_of_wickets: [],
        partnerships: [],
      })),
      last_updated: new Date().toISOString(),
    };
  }

  #extractScore(scoreArr) {
    const result = {};
    if (scoreArr?.[0]) result.team1 = [{ runs: scoreArr[0].r || 0, wickets: scoreArr[0].w || 0, overs: scoreArr[0].o || 0 }];
    if (scoreArr?.[1]) result.team2 = [{ runs: scoreArr[1].r || 0, wickets: scoreArr[1].w || 0, overs: scoreArr[1].o || 0 }];
    return result;
  }

  #mapStatus(status, started, ended) {
    if (ended) return 'completed';
    if (started) return 'live';
    return 'upcoming';
  }

  // Fallback methods for features not supported by CricketData
  async getPointsTable() {
    return []; // Not implemented
  }

  async getMatchSquads() {
    return { team1: null, team2: null }; // Not implemented
  }

  async getLiveLine() {
    return null; // Not implemented
  }
}
