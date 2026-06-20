import axios from 'axios';
import { BaseProvider } from '../base-provider.js';
import config from '../../config/index.js';
import logger from '../../lib/logger.js';

const client = axios.create({
  baseURL: config.providers.cricinfo.baseUrl,
  timeout: 10000,
  headers: {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
    'Accept': 'application/json',
  },
});

export class CricinfoProvider extends BaseProvider {
  constructor() {
    super('cricinfo', 2);
  }

  async getLiveMatches() {
    try {
      const { data } = await client.get('/pages/matches/current?lang=en&latest=true');
      this.recordSuccess();
      return this.#normalizeMatchList(data);
    } catch (err) {
      this.recordFailure();
      logger.warn({ msg: 'Cricinfo getLiveMatches failed', error: err.message });
      throw err;
    }
  }

  async getUpcomingMatches() {
    try {
      const { data } = await client.get('/pages/matches/current?lang=en&latest=true');
      this.recordSuccess();
      return this.#normalizeMatchList(data, 'upcoming');
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getRecentMatches() {
    try {
      const { data } = await client.get('/pages/matches/current?lang=en&latest=true');
      this.recordSuccess();
      return this.#normalizeMatchList(data, 'recent');
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getMatchInfo(matchId) {
    try {
      const { data } = await client.get(`/pages/match/details?lang=en&seriesId=0&matchId=${matchId}`);
      this.recordSuccess();
      return this.#normalizeMatchDetail(data);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getScorecard(matchId) {
    try {
      const { data } = await client.get(`/pages/match/scorecard?lang=en&seriesId=0&matchId=${matchId}`);
      this.recordSuccess();
      return this.#normalizeScorecard(data);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getCommentary(matchId) {
    try {
      const { data } = await client.get(`/pages/match/comments?lang=en&seriesId=0&matchId=${matchId}&inningNumber=1&commentType=ALL&fromInningOver=-1`);
      this.recordSuccess();
      return this.#normalizeCommentary(data);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getSeriesList() {
    try {
      const { data } = await client.get('/pages/series/list?lang=en');
      this.recordSuccess();
      return this.#normalizeSeriesList(data);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getSeriesInfo(seriesId) {
    try {
      const { data } = await client.get(`/pages/series/schedule?lang=en&seriesId=${seriesId}`);
      this.recordSuccess();
      return this.#normalizeMatchList(data);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getPointsTable(seriesId) {
    try {
      const { data } = await client.get(`/pages/series/standings?lang=en&seriesId=${seriesId}`);
      this.recordSuccess();
      return this.#normalizePointsTable(data);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getPlayerInfo(playerId) {
    try {
      const { data } = await client.get(`/pages/player/summary?lang=en&playerId=${playerId}`);
      this.recordSuccess();
      return this.#normalizePlayer(data);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  async getTeamInfo(teamId) {
    try {
      const { data } = await client.get(`/pages/team/schedule?lang=en&teamId=${teamId}`);
      this.recordSuccess();
      return this.#normalizeTeam(data, teamId);
    } catch (err) {
      this.recordFailure();
      throw err;
    }
  }

  // --- Normalizers ---

  #normalizeMatchList(data, filter) {
    const matches = data?.matches || data?.content?.matches || [];
    return matches
      .filter((m) => {
        if (!filter) return true;
        const state = (m.state || '').toLowerCase();
        if (filter === 'upcoming') return state === 'upcoming' || state === 'pre';
        if (filter === 'recent') return state === 'post' || state === 'complete';
        return state === 'live';
      })
      .map((m) => ({
        match_id: String(m.objectId || m.id || ''),
        series_id: String(m.series?.objectId || ''),
        series_name: m.series?.longName || '',
        match_format: (m.format || '').toLowerCase(),
        status: this.#mapStatus(m.state),
        status_text: m.statusText || m.status || '',
        team1: { id: String(m.teams?.[0]?.team?.objectId || ''), name: m.teams?.[0]?.team?.longName || '', short_name: m.teams?.[0]?.team?.abbreviation || '' },
        team2: { id: String(m.teams?.[1]?.team?.objectId || ''), name: m.teams?.[1]?.team?.longName || '', short_name: m.teams?.[1]?.team?.abbreviation || '' },
        venue: { name: m.ground?.longName || '', city: m.ground?.town?.name || '', country: m.ground?.country?.name || '' },
        start_time: m.startTime || null,
        score: {},
        last_updated: new Date().toISOString(),
      }));
  }

  #normalizeMatchDetail(data) {
    const m = data?.match || data;
    return {
      match_id: String(m.objectId || ''),
      series_id: String(m.series?.objectId || ''),
      series_name: m.series?.longName || '',
      match_format: (m.format || '').toLowerCase(),
      status: this.#mapStatus(m.state),
      status_text: m.statusText || '',
      team1: { id: String(m.teams?.[0]?.team?.objectId || ''), name: m.teams?.[0]?.team?.longName || '', short_name: m.teams?.[0]?.team?.abbreviation || '', innings: [] },
      team2: { id: String(m.teams?.[1]?.team?.objectId || ''), name: m.teams?.[1]?.team?.longName || '', short_name: m.teams?.[1]?.team?.abbreviation || '', innings: [] },
      venue: { name: m.ground?.longName || '', city: m.ground?.town?.name || '', country: m.ground?.country?.name || '' },
      start_time: m.startTime || null,
      toss: { winner: m.tossWinnerTeamId ? String(m.tossWinnerTeamId) : '', decision: m.tossWinnerChoice || '' },
      result: m.statusText || '',
      innings: [],
      last_updated: new Date().toISOString(),
    };
  }

  #normalizeScorecard(data) {
    const innings = data?.content?.innings || data?.innings || [];
    return {
      innings: innings.map((inn, idx) => ({
        innings_number: idx + 1,
        batting_team: inn.team?.longName || '',
        batting_team_id: String(inn.team?.objectId || ''),
        total: { runs: inn.runs || 0, wickets: inn.wickets || 0, overs: inn.overs || 0 },
        run_rate: inn.runRate || 0,
        extras: { total: inn.extras || 0, byes: inn.byes || 0, leg_byes: inn.legByes || 0, wides: inn.wides || 0, no_balls: inn.noballs || 0, penalty: 0 },
        batting: (inn.inningBatsmen || []).map((b) => ({
          player_id: String(b.player?.objectId || ''),
          name: b.player?.longName || '',
          runs: b.runs || 0, balls: b.balls || 0, fours: b.fours || 0, sixes: b.sixes || 0,
          strike_rate: b.strikerate || 0, dismissal: b.dismissalText?.long || '', is_batting: false, is_striker: false,
        })),
        bowling: (inn.inningBowlers || []).map((b) => ({
          player_id: String(b.player?.objectId || ''),
          name: b.player?.longName || '',
          overs: b.overs || 0, maidens: b.maidens || 0, runs: b.conceded || 0, wickets: b.wickets || 0,
          economy: b.economy || 0, dots: 0, wides: b.wides || 0, no_balls: b.noballs || 0, is_bowling: false,
        })),
        fall_of_wickets: [],
        partnerships: [],
      })),
      last_updated: new Date().toISOString(),
    };
  }

  #normalizeCommentary(data) {
    const comms = data?.content?.comments || data?.comments || [];
    return comms.map((c) => ({
      id: String(c.id || Date.now()),
      innings_number: c.inningNumber || 0,
      over: c.overNumber ?? null,
      ball: c.ballNumber ?? null,
      event: c.type?.toLowerCase() || 'ball',
      text: c.text || '',
      runs: c.totalRuns || 0,
      is_wicket: c.type === 'WICKET',
      is_boundary: c.totalRuns === 4 || c.totalRuns === 6,
      batsman: c.batsmanName || '',
      bowler: c.bowlerName || '',
      timestamp: Date.now(),
    }));
  }

  #normalizeSeriesList(data) {
    const collections = data?.content?.collections || data?.series || [];
    return collections.map((s) => ({
      series_id: String(s.objectId || s.id || ''),
      name: s.longName || s.name || '',
      season: s.season || '',
      start_date: s.startDate || null,
      end_date: s.endDate || null,
    }));
  }

  #normalizePointsTable(data) {
    const groups = data?.content?.standings?.groups || data?.standings || [];
    const result = [];
    for (const group of groups) {
      for (const entry of group.teamStats || []) {
        result.push({
          team_id: String(entry.teamInfo?.objectId || ''),
          team_name: entry.teamInfo?.longName || '',
          team_short: entry.teamInfo?.abbreviation || '',
          position: entry.rank || 0,
          played: entry.matchesPlayed || 0,
          won: entry.matchesWon || 0,
          lost: entry.matchesLost || 0,
          tied: entry.matchesTied || 0,
          no_result: entry.matchesNoResult || 0,
          points: entry.points || 0,
          nrr: parseFloat(entry.nrr || 0),
          group: group.name || '',
          qualified: false,
        });
      }
    }
    return result;
  }

  #normalizePlayer(data) {
    const p = data?.content?.player || data?.player || data;
    return {
      player_id: String(p.objectId || ''),
      name: p.longName || p.name || '',
      full_name: p.longName || '',
      dob: p.dateOfBirth || null,
      nationality: p.country?.name || '',
      role: p.playingRole || '',
      batting_style: p.longBattingStyles?.[0] || '',
      bowling_style: p.longBowlingStyles?.[0] || '',
      image_url: '',
      teams: [],
      bio: '',
      stats: {},
      last_updated: new Date().toISOString(),
    };
  }

  #normalizeTeam(data, teamId) {
    const t = data?.content?.team || {};
    return {
      team_id: String(t.objectId || teamId),
      name: t.longName || '',
      short_name: t.abbreviation || '',
      logo_url: '',
      country: t.country?.name || '',
      players: [],
      last_updated: new Date().toISOString(),
    };
  }

  #mapStatus(state) {
    if (!state) return 'upcoming';
    const s = state.toLowerCase();
    if (s === 'live') return 'live';
    if (s === 'post' || s === 'complete') return 'completed';
    if (s === 'pre' || s === 'upcoming') return 'upcoming';
    return 'upcoming';
  }

  // Fallback methods for features not supported by Cricinfo
  async getPointsTable() {
    return []; // Not implemented in Cricinfo
  }

  async getMatchSquads() {
    return { team1: null, team2: null }; // Not implemented in Cricinfo
  }

  async getLiveLine() {
    return null; // Not implemented in Cricinfo
  }
}
