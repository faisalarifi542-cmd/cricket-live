import { cacheGet, cacheGetOrFetch, cacheSet, KEYS, TTL } from '../lib/redis.js';
import providerManager from '../providers/provider-manager.js';
import { cacheMiddleware } from '../middleware/cache.js';
import { indexMatchListItems, indexScheduleMatches, getMatchSummary, summaryToMatchDetail } from '../lib/match-index.js';
import logger from '../lib/logger.js';

/**
 * Match routes — /matches/*, /match/:id/*
 */
export default async function matchRoutes(fastify) {
  function isInvalidSquadsPayload(data) {
    const teams = data?.teams || [data?.team1, data?.team2].filter(Boolean);
    if (!Array.isArray(teams) || teams.length < 2) return true;
    return teams.some((team) => {
      const teamName = team.teamName || team.team_name || '';
      const teamShort = team.teamShort || team.team_short || '';
      const playingXI = team.playingXI || team.playing_xi || [];
      const bench = team.bench || [];
      const players = [...playingXI, ...bench];
      return /^Team\s*[12]$/i.test(teamName)
        || /^T[12]$/i.test(teamShort)
        || (playingXI.length === 0 && bench.length === 0)
        || players.some((p) => !p?.name || /(WK-Batter|Bowler|Batter|Allrounder)$/i.test(p.name));
    });
  }

  function isInvalidLiveLinePayload(data) {
    if (!data) return true;
    const latestBall = data.latestBall || data.data?.latestBall;
    return !data.battingTeam
      || !data.bowlingTeam
      || !latestBall
      || (Number(latestBall.over || 0) === 0 && Number(latestBall.ball || 0) === 0);
  }

  async function fetchRecentMatches() {
    const { data } = await cacheGetOrFetch(
      KEYS.matchesList('recent'),
      TTL.RECENT,
      async () => {
        const result = await providerManager.execute('getRecentMatches');
        return result.data;
      }
    );
    if (data?.length) indexMatchListItems(data).catch(() => {});
    return data || [];
  }

  function cleanLiveLinePayload(payload, matchId) {
    const live = payload?.data && Object.keys(payload).length === 1 ? payload.data : payload;
    if (!live) return null;
    const latestBall = live.latestBall || null;
    return {
      matchId: String(live.matchId || matchId),
      status: live.status || 'unknown',
      innings: live.innings || 0,
      battingTeam: live.battingTeam || null,
      bowlingTeam: live.bowlingTeam || null,
      score: live.score || live.battingTeam?.score || null,
      overs: live.overs || live.battingTeam?.overs || null,
      target: live.target ?? null,
      runsNeeded: live.runsNeeded ?? null,
      ballsRemaining: live.ballsRemaining ?? null,
      crr: live.crr ?? 0,
      rrr: live.rrr ?? null,
      latestBall,
      latestBallResult: latestBall?.result || '',
      latestBallKey: latestBall?.key || '',
      recentBalls: live.recentBalls || [],
      currentOverBalls: live.currentOverBalls || live.currentOver || [],
      currentOver: live.currentOver || live.currentOverBalls || [],
      striker: live.striker || null,
      nonStriker: live.nonStriker || null,
      bowler: live.bowler || null,
      partnership: live.partnership || null,
      lastWicket: live.lastWicket || null,
      winProbability: live.winProbability ?? null,
      drs: live.drs || null,
      sessionStats: live.sessionStats || null,
      wormGraph: live.wormGraph || [],
      updatedAt: live.updatedAt || new Date().toISOString(),
    };
  }

  function buildInfoFallback(matchId, match = null) {
    return {
      matchId: String(matchId),
      series: {
        id: String(match?.series_id || ''),
        name: match?.series_name || '',
      },
      date: {
        start: match?.start_time || null,
        end: match?.end_time || null,
      },
      venue: match?.venue?.name || '',
      city: match?.venue?.city || '',
      toss: match?.toss || null,
      result: match?.result || match?.status_text || '',
      playerOfMatch: match?.player_of_match || match?.man_of_match || null,
      officials: {
        umpires: [],
        tvUmpire: null,
        matchReferee: null,
      },
      venueDetails: {
        name: match?.venue?.name || '',
        city: match?.venue?.city || '',
        country: match?.venue?.country || '',
        established: null,
        capacity: null,
        ends: null,
        floodlights: null,
      },
      weather: {
        temperature: null,
        condition: null,
        humidity: null,
        windSpeed: null,
        windDirection: null,
      },
      pitchReport: {
        type: null,
        description: null,
        avgFirstInningsScore: null,
        chaseSuccess: null,
      },
      keyMoments: [],
      updatedAt: new Date().toISOString(),
    };
  }

  function ballsFromSummary(summary = '') {
    return String(summary)
      .split(/\s+/)
      .filter(Boolean)
      .map((result, index) => ({
        ballNumber: index + 1,
        result,
        runs: /^\d+$/.test(result) ? Number(result) : 0,
        isWicket: /^W/i.test(result),
        isBoundary: result === '4' || result === '6',
        commentary: '',
      }));
  }

  function normalizeOversForApp(matchId, oversData = {}, overByOver = null) {
    const overRows = overByOver?.overs || oversData.overs || [];
    const innings = (oversData.innings || []).map((inn) => ({
      inningsId: inn.innings_number || inn.inningsId || 0,
      teamName: inn.batting_team || inn.teamName || '',
      teamShort: inn.batting_team || inn.teamShort || '',
    }));
    const overs = overRows.map((o) => ({
      overNumber: o.overNumber || 0,
      bowlerName: o.bowlerName || '',
      balls: ballsFromSummary(o.summary || ''),
      runs: o.runs || 0,
      wickets: o.wickets || 0,
      scoreAfter: o.score || `${o.totalScore || 0}/${o.totalWickets || 0}`,
      wicketsAfter: o.totalWickets || 0,
      runRate: o.runRate || null,
    }));
    const runRateGraph = overs.map((o, index) => ({
      over: o.overNumber || index + 1,
      runRate: o.runRate || null,
      requiredRunRate: null,
    }));

    return {
      ...oversData,
      matchId: String(matchId),
      innings,
      overs,
      runRateGraph,
    };
  }

  // GET /matches/live
  fastify.get('/matches/live', {
    schema: {
      description: 'Get all currently live matches',
      tags: ['Matches'],
      response: {
        200: {
          type: 'object',
          properties: {
            success: { type: 'boolean' },
            data: { type: 'array' },
            cache: { type: 'boolean' },
          },
        },
      },
    },
    preHandler: cacheMiddleware(KEYS.matchesList('live'), TTL.LIVE_SCORE),
  }, async (request, reply) => {
    const { data } = await cacheGetOrFetch(
      KEYS.matchesList('live'),
      TTL.LIVE_SCORE,
      async () => {
        const result = await providerManager.execute('getLiveMatches');
        return result.data;
      }
    );
    if (data?.length) indexMatchListItems(data).catch(() => {});
    return { success: true, data: data || [] };
  });

  // GET /matches/upcoming
  fastify.get('/matches/upcoming', {
    schema: { description: 'Get upcoming matches', tags: ['Matches'] },
    preHandler: cacheMiddleware(KEYS.matchesList('upcoming'), TTL.UPCOMING),
  }, async (request, reply) => {
    const { data } = await cacheGetOrFetch(
      KEYS.matchesList('upcoming'),
      TTL.UPCOMING,
      async () => {
        const result = await providerManager.execute('getUpcomingMatches');
        return result.data;
      }
    );
    if (data?.length) indexMatchListItems(data).catch(() => {});
    return { success: true, data: data || [] };
  });

  // GET /matches/recent
  fastify.get('/matches/recent', {
    schema: { description: 'Get recently completed matches', tags: ['Matches'] },
    preHandler: cacheMiddleware(KEYS.matchesList('recent'), TTL.RECENT),
  }, async (request, reply) => {
    return { success: true, data: await fetchRecentMatches() };
  });

  // GET /matches/finished — app-facing alias for /matches/recent
  fastify.get('/matches/finished', {
    schema: { description: 'Get completed matches (alias of /matches/recent)', tags: ['Matches'] },
    preHandler: cacheMiddleware(KEYS.matchesList('recent'), TTL.RECENT),
  }, async () => {
    return { success: true, data: await fetchRecentMatches() };
  });

  // GET /match/:id
  fastify.get('/match/:id', {
    schema: {
      description: 'Get detailed match info',
      tags: ['Matches'],
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
        required: ['id'],
      },
    },
    preHandler: cacheMiddleware((req) => KEYS.matchLive(req.params.id), TTL.LIVE_SCORE),
  }, async (request, reply) => {
    const { id } = request.params;
    try {
      const { data } = await cacheGetOrFetch(
        KEYS.matchLive(id),
        TTL.LIVE_SCORE,
        async () => {
          const result = await providerManager.execute('getMatchInfo', id);
          return result.data;
        }
      );

      if (data) return { success: true, data };
    } catch {
      // Livescore endpoint failed — try matchHeader fallback for upcoming/preview matches
    }

    // Fallback 2: try matchHeader from provider
    try {
      const headerResult = await providerManager.execute('getMatchHeader', id);
      if (headerResult?.data) return { success: true, data: headerResult.data };
    } catch { /* ignore */ }

    // Fallback 3: look up cached match summary (indexed from schedule/list endpoints)
    try {
      const summary = await getMatchSummary(id);
      if (summary && (summary.team1?.name || summary.team1?.short_name)) {
        return { success: true, data: summaryToMatchDetail(summary) };
      }
    } catch { /* ignore */ }

    // Fallback 4: actively fetch schedule and try to find this match
    try {
      for (const type of ['league', 'all']) {
        try {
          const schedResult = await providerManager.execute('getUpcomingSchedule', type);
          if (schedResult?.data?.days) {
            await indexScheduleMatches(schedResult.data);
            const summary = await getMatchSummary(id);
            if (summary && (summary.team1?.name || summary.team1?.short_name)) {
              return { success: true, data: summaryToMatchDetail(summary) };
            }
          }
        } catch { /* try next type */ }
      }
    } catch { /* ignore */ }

    // Last resort: return minimal valid response so app never gets a 404 for a known match ID
    return {
      success: true,
      data: {
        match_id: id,
        series_id: '',
        series_name: '',
        match_desc: '',
        match_format: '',
        match_type: '',
        match_number: '',
        status: 'upcoming',
        status_text: 'Match details will be available closer to start time',
        result: '',
        man_of_match: '',
        current_innings: 0,
        team1: { id: '', name: '', short_name: '' },
        team2: { id: '', name: '', short_name: '' },
        venue: { name: '', city: '', country: '' },
        innings: [],
        current_batsmen: [],
        current_run_rate: 0,
        required_run_rate: 0,
        latest_performance: [],
        powerplay_data: [],
        last_updated: new Date().toISOString(),
      },
    };
  });

  // GET /match/:id/scorecard
  fastify.get('/match/:id/scorecard', {
    schema: {
      description: 'Get match scorecard with batting and bowling details',
      tags: ['Matches'],
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
        required: ['id'],
      },
    },
    preHandler: cacheMiddleware((req) => KEYS.matchScorecard(req.params.id), TTL.SCORECARD),
  }, async (request, reply) => {
    const { id } = request.params;
    try {
      // [FIXED] Validate data before caching - don't cache empty failures
      let data = await cacheGet(KEYS.matchScorecard(id));
      let fromCache = !!data;
      
      if (!data) {
        const result = await providerManager.execute('getScorecard', id);
        data = result?.data || null;
        
        // [FIXED] Only cache if we have valid scorecard data
        if (data && data.innings && data.innings.length > 0) {
          await cacheSet(KEYS.matchScorecard(id), data, TTL.SCORECARD);
        } else {
          logger.warn({ msg: '[FIXED] Not caching empty scorecard', matchId: id, innings: data?.innings?.length });
          fromCache = false;
        }
      }

      reply.header('X-Cache', fromCache ? 'HIT' : 'MISS');
      
      if (data && data.innings && data.innings.length > 0) {
        return { success: true, data, fromCache };
      }
    } catch (err) { 
      logger.error({ msg: '[FIXED] Scorecard fetch failed', matchId: id, error: err.message });
    }

    // Scorecard not available — return empty but valid response (never 404)
    return {
      success: true,
      data: { innings: [], scorecard_available: false },
      fromCache: false,
      message: 'Scorecard not available for this match',
    };
  });

  // GET /match/:id/commentary
  fastify.get('/match/:id/commentary', {
    schema: {
      description: 'Get match commentary',
      tags: ['Matches'],
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
        required: ['id'],
      },
      querystring: {
        type: 'object',
        properties: {
          page: { type: 'integer', default: 1 },
          limit: { type: 'integer', default: 50 },
        },
      },
    },
    preHandler: cacheMiddleware((req) => KEYS.matchCommentary(req.params.id), TTL.COMMENTARY),
  }, async (request, reply) => {
    const { id } = request.params;
    const { page = 1, limit = 50 } = request.query;

    const { data: commentary } = await cacheGetOrFetch(
      KEYS.matchCommentary(id),
      TTL.COMMENTARY,
      async () => {
        const result = await providerManager.execute('getCommentary', id);
        return result.data;
      }
    );

    if (!commentary) return { success: true, data: [], pagination: { page, limit, total: 0, pages: 0 }, message: 'Commentary not available for this match' };

    // Paginate
    const start = (page - 1) * limit;
    const paginated = commentary.slice(start, start + limit);

    return {
      success: true,
      data: paginated,
      pagination: {
        page,
        limit,
        total: commentary.length,
        pages: Math.ceil(commentary.length / limit),
      },
    };
  });

  // GET /match/:id/innings
  fastify.get('/match/:id/innings', {
    schema: {
      description: 'Get match innings summary',
      tags: ['Matches'],
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
        required: ['id'],
      },
    },
  }, async (request, reply) => {
    const { id } = request.params;
    try {
      const match = await cacheGet(KEYS.matchLive(id));
      if (match) return { success: true, data: match.innings || [] };

      const result = await providerManager.execute('getMatchInfo', id);
      if (result?.data) return { success: true, data: result.data.innings || [] };
    } catch { /* ignore */ }
    return { success: true, data: [], message: 'Innings data not available for this match' };
  });

  // GET /match/:id/overs
  fastify.get('/match/:id/overs', {
    schema: {
      description: 'Get overs data including recent overs, powerplay, and latest performance',
      tags: ['Matches'],
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
        required: ['id'],
      },
    },
    preHandler: cacheMiddleware((req) => KEYS.matchOvers(req.params.id), TTL.MATCH_OVERS),
  }, async (request, reply) => {
    const { id } = request.params;

    try {
      const { data } = await cacheGetOrFetch(
        KEYS.matchOvers(id),
        TTL.MATCH_OVERS,
        async () => {
          const result = await providerManager.execute('getMatchOvers', id);
          return result.data;
        }
      );
      let overByOver = null;
      try {
        const inningsId = data?.innings?.[data.innings.length - 1]?.innings_number || 1;
        overByOver = (await providerManager.execute('getOverByOver', id, String(inningsId))).data;
      } catch { /* optional enrichment */ }
      const appData = normalizeOversForApp(id, data || {}, overByOver);

      return {
        success: true,
        matchId: id,
        data: appData || {
          recent_overs: [],
          over_summary_list: [],
          latest_performance: [],
          powerplays: [],
          innings: [],
          overs: [],
          runRateGraph: [],
        },
        message: data ? null : 'Overs data not available for this match',
      };
    } catch {
      // Never 404 for valid match IDs — return empty gracefully
      return {
        success: true,
        matchId: id,
        data: {
          recent_overs: [],
          over_summary_list: [],
          latest_performance: [],
          powerplays: [],
          innings: [],
        },
        message: 'Overs data not available for this match',
      };
    }
  });

  // GET /match/:id/stats
  fastify.get('/match/:id/stats', {
    schema: {
      description: 'Get match statistics including summary, powerplay, and recent performance',
      tags: ['Matches'],
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
        required: ['id'],
      },
    },
    preHandler: cacheMiddleware((req) => KEYS.matchStats(req.params.id), TTL.MATCH_STATS),
  }, async (request, reply) => {
    const { id } = request.params;

    try {
      const { data } = await cacheGetOrFetch(
        KEYS.matchStats(id),
        TTL.MATCH_STATS,
        async () => {
          const result = await providerManager.execute('getMatchStats', id);
          return result.data;
        }
      );

      return {
        success: true,
        matchId: id,
        data: data || null,
        message: data ? null : 'Stats not available for this match',
      };
    } catch {
      return {
        success: true,
        matchId: id,
        data: null,
        message: 'Stats not available for this match',
      };
    }
  });

  // GET /match/:id/news
  fastify.get('/match/:id/news', {
    schema: {
      description: 'Get news stories for a match',
      tags: ['Matches'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
      querystring: {
        type: 'object',
        properties: { cursor: { type: 'string' } },
      },
    },
  }, async (request) => {
    const { id } = request.params;
    const { cursor } = request.query;
    try {
      const { data } = await cacheGetOrFetch(
        KEYS.matchNews(id, cursor),
        TTL.MATCH_NEWS,
        async () => (await providerManager.execute('getMatchNews', id, cursor || undefined)).data
      );
      return {
        success: true,
        matchId: id,
        data: data || { stories: [], nextCursor: null },
        message: (!data || !data.stories?.length) ? 'No news available for this match' : null,
      };
    } catch {
      return { success: true, matchId: id, data: { stories: [], nextCursor: null }, message: 'Match news not available' };
    }
  });

  // GET /match/:id/full-commentary/:inningsId
  fastify.get('/match/:id/full-commentary/:inningsId', {
    schema: {
      description: 'Get full ball-by-ball commentary for an innings',
      tags: ['Matches'],
      params: {
        type: 'object',
        properties: { id: { type: 'string' }, inningsId: { type: 'string' } },
        required: ['id', 'inningsId'],
      },
    },
  }, async (request) => {
    const { id, inningsId } = request.params;
    try {
      const { data } = await cacheGetOrFetch(
        KEYS.fullCommentary(id, inningsId),
        TTL.FULL_COMMENTARY_LIVE,
        async () => (await providerManager.execute('getFullCommentary', id, inningsId)).data
      );
      return {
        success: true,
        matchId: id,
        inningsId: Number(inningsId),
        data: data || { commentary: [] },
        message: (!data || !data.commentary?.length) ? 'Commentary not available for this innings' : null,
      };
    } catch {
      return { success: true, matchId: id, inningsId: Number(inningsId), data: { commentary: [] }, message: 'Commentary not available' };
    }
  });

  // GET /match/:id/highlights/:inningsId
  fastify.get('/match/:id/highlights/:inningsId', {
    schema: {
      description: 'Get match highlights (4s, 6s, wickets) for an innings',
      tags: ['Matches'],
      params: {
        type: 'object',
        properties: { id: { type: 'string' }, inningsId: { type: 'string' } },
        required: ['id', 'inningsId'],
      },
    },
  }, async (request) => {
    const { id, inningsId } = request.params;
    try {
      const { data } = await cacheGetOrFetch(
        KEYS.highlights(id, inningsId),
        TTL.HIGHLIGHTS_LIVE,
        async () => (await providerManager.execute('getHighlights', id, inningsId)).data
      );
      return {
        success: true,
        matchId: id,
        inningsId: Number(inningsId),
        data: data || { highlights: [] },
        message: (!data || !data.highlights?.length) ? 'Highlights not available for this innings' : null,
      };
    } catch {
      return { success: true, matchId: id, inningsId: Number(inningsId), data: { highlights: [] }, message: 'Highlights not available' };
    }
  });

  // GET /match/:id/highlights (all innings combined)
  fastify.get('/match/:id/highlights', {
    schema: {
      description: 'Get match highlights for all innings',
      tags: ['Matches'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request) => {
    const { id } = request.params;
    try {
      const allHighlights = [];
      for (let inn = 1; inn <= 4; inn++) {
        try {
          const { data } = await cacheGetOrFetch(
            KEYS.highlights(id, inn),
            TTL.HIGHLIGHTS_LIVE,
            async () => (await providerManager.execute('getHighlights', id, String(inn))).data
          );
          if (data?.highlights?.length) {
            allHighlights.push(...data.highlights.map((h) => ({ ...h, inningsId: inn })));
          }
        } catch { /* skip empty innings */ }
      }
      return {
        success: true,
        matchId: id,
        data: { highlights: allHighlights },
        message: allHighlights.length === 0 ? 'No highlights available' : null,
      };
    } catch {
      return { success: true, matchId: id, data: { highlights: [] }, message: 'Highlights not available' };
    }
  });

  // GET /match/:id/balls-map/:inningsId
  fastify.get('/match/:id/balls-map/:inningsId', {
    schema: {
      description: 'Get ball-by-ball map for an innings',
      tags: ['Matches'],
      params: {
        type: 'object',
        properties: { id: { type: 'string' }, inningsId: { type: 'string' } },
        required: ['id', 'inningsId'],
      },
    },
  }, async (request) => {
    const { id, inningsId } = request.params;
    try {
      const { data } = await cacheGetOrFetch(
        KEYS.ballsMap(id, inningsId),
        TTL.BALLS_MAP_LIVE,
        async () => (await providerManager.execute('getBallsMap', id, inningsId)).data
      );
      return {
        success: true,
        matchId: id,
        inningsId: Number(inningsId),
        data: data || { balls: [], batters: [], bowlers: [], scoreDetails: null, summary: {} },
        message: (!data || !data.balls?.length) ? 'Ball map not available for this innings' : null,
      };
    } catch {
      return { success: true, matchId: id, inningsId: Number(inningsId), data: { balls: [], batters: [], bowlers: [], scoreDetails: null, summary: {} }, message: 'Ball map not available' };
    }
  });

  // GET /match/:id/balls-map (default innings 1)
  fastify.get('/match/:id/balls-map', {
    schema: {
      description: 'Get ball-by-ball map (default innings 1)',
      tags: ['Matches'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request) => {
    const { id } = request.params;
    try {
      const { data } = await cacheGetOrFetch(
        KEYS.ballsMap(id, '1'),
        TTL.BALLS_MAP_LIVE,
        async () => (await providerManager.execute('getBallsMap', id, '1')).data
      );
      return {
        success: true,
        matchId: id,
        inningsId: 1,
        data: data || { balls: [], batters: [], bowlers: [], scoreDetails: null, summary: {} },
        message: (!data || !data.balls?.length) ? 'Ball map not available' : null,
      };
    } catch {
      return { success: true, matchId: id, inningsId: 1, data: { balls: [], batters: [], bowlers: [], scoreDetails: null, summary: {} }, message: 'Ball map not available' };
    }
  });

  // GET /match/:id/over-by-over/:inningsId
  fastify.get('/match/:id/over-by-over/:inningsId', {
    schema: {
      description: 'Get over-by-over updates for an innings',
      tags: ['Matches'],
      params: {
        type: 'object',
        properties: { id: { type: 'string' }, inningsId: { type: 'string' } },
        required: ['id', 'inningsId'],
      },
    },
  }, async (request) => {
    const { id, inningsId } = request.params;
    try {
      const { data } = await cacheGetOrFetch(
        KEYS.overByOver(id, inningsId),
        TTL.OVER_BY_OVER_LIVE,
        async () => (await providerManager.execute('getOverByOver', id, inningsId)).data
      );
      return {
        success: true,
        matchId: id,
        inningsId: Number(inningsId),
        data: data || { overs: [] },
        message: (!data || !data.overs?.length) ? 'Over data not available for this innings' : null,
      };
    } catch {
      return { success: true, matchId: id, inningsId: Number(inningsId), data: { overs: [] }, message: 'Over data not available' };
    }
  });

  // GET /match/:id/over-by-over (default innings 1)
  fastify.get('/match/:id/over-by-over', {
    schema: {
      description: 'Get over-by-over updates (default innings 1)',
      tags: ['Matches'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request) => {
    const { id } = request.params;
    try {
      const { data } = await cacheGetOrFetch(
        KEYS.overByOver(id, '1'),
        TTL.OVER_BY_OVER_LIVE,
        async () => (await providerManager.execute('getOverByOver', id, '1')).data
      );
      return {
        success: true,
        matchId: id,
        inningsId: 1,
        data: data || { overs: [] },
        message: (!data || !data.overs?.length) ? 'Over data not available' : null,
      };
    } catch {
      return { success: true, matchId: id, inningsId: 1, data: { overs: [] }, message: 'Over data not available' };
    }
  });

  // GET /match/:id/squads - Match squads (Playing XI, Bench, Impact Player)
  fastify.get('/match/:id/squads', {
    schema: {
      description: 'Get match squads with Playing XI, Bench, and Impact Player',
      tags: ['Matches'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request, reply) => {
    const { id } = request.params;
    try {
      const cached = await cacheGet(KEYS.matchSquads(id));
      if (cached && !isInvalidSquadsPayload(cached)) {
        reply.header('X-Cache', 'HIT');
        return {
          success: true,
          matchId: id,
          data: cached,
          updatedAt: new Date().toISOString(),
          fromCache: true,
          message: null,
        };
      }

      const data = (await providerManager.execute('getMatchSquads', id)).data;
      if (isInvalidSquadsPayload(data)) {
        reply.header('X-Cache', 'MISS');
        return {
          success: false,
          matchId: id,
          data: null,
          updatedAt: new Date().toISOString(),
          fromCache: false,
          message: 'Squads parser failed',
          debug: {
            pageTitle: data?.page_title || data?.pageTitle || '',
            playersFound: data?._players_found || 0,
            teamsFound: data?._teams_found || 0,
            reason: data?._parse_error || 'Invalid squads payload',
          },
        };
      }

      await cacheSet(KEYS.matchSquads(id), data, TTL.SQUADS);
      reply.header('X-Cache', 'MISS');
      return {
        success: true,
        matchId: id,
        data,
        updatedAt: new Date().toISOString(),
        fromCache: false,
        message: null,
      };
    } catch (err) {
      logger.warn({ msg: 'Failed to fetch squads', matchId: id, error: err.message });
      return {
        success: false,
        matchId: id,
        data: null,
        updatedAt: new Date().toISOString(),
        message: 'Squads parser failed',
        debug: { reason: err.message },
      };
    }
  });

  // GET /match/:id/live-line - Enhanced Live Line (Fast Live Line experience)
  fastify.get('/match/:id/live-line', {
    schema: {
      description: 'Get enhanced live line data for Fast Live Line experience',
      tags: ['Matches'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request) => {
    const { id } = request.params;
    try {
      const cached = await cacheGet(KEYS.matchLiveLine(id));
      if (cached && !isInvalidLiveLinePayload(cleanLiveLinePayload(cached, id))) {
        return {
          success: true,
          matchId: id,
          data: cleanLiveLinePayload(cached, id),
          updatedAt: new Date().toISOString(),
          fromCache: true,
          message: null,
        };
      }

      const result = await providerManager.execute('getLiveLine', id);
      const liveData = cleanLiveLinePayload(result?.data || null, id);

      if (liveData && !isInvalidLiveLinePayload(liveData)) {
        // Cache for only 5 seconds - live data should be fresh
        await cacheSet(KEYS.matchLiveLine(id), liveData, TTL.LIVE_LINE);
      }

      return {
        success: true,
        matchId: id,
        data: liveData,
        updatedAt: new Date().toISOString(),
        fromCache: false,
        message: !liveData ? 'Live line data not available for this match' : null,
      };
    } catch (err) {
      logger.warn({ msg: 'Failed to fetch live line', matchId: id, error: err.message });
      return {
        success: true,
        matchId: id,
        data: null,
        updatedAt: new Date().toISOString(),
        message: 'Live line data not available',
      };
    }
  });

  // GET /match/:id/info-detailed - Detailed match info
  fastify.get('/match/:id/info-detailed', {
    schema: {
      description: 'Get detailed match info including officials, venue, weather',
      tags: ['Matches'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request) => {
    const { id } = request.params;
    try {
      const cached = await cacheGet(KEYS.matchInfoDetailed(id));
      if (cached) {
        return {
          success: true,
          matchId: id,
          data: cached,
          updatedAt: new Date().toISOString(),
          fromCache: true,
        };
      }

      const result = await providerManager.execute('getMatchInfoDetailed', id);
      let infoData = result?.data || null;

      if (!infoData) {
        try {
          const matchResult = await providerManager.execute('getMatchInfo', id);
          infoData = buildInfoFallback(id, matchResult?.data || null);
        } catch {
          infoData = buildInfoFallback(id);
        }
      }

      if (infoData) {
        await cacheSet(KEYS.matchInfoDetailed(id), infoData, TTL.MATCH_INFO_DETAILED);
      }

      return {
        success: true,
        matchId: id,
        data: infoData,
        updatedAt: new Date().toISOString(),
        fromCache: false,
        message: null,
      };
    } catch (err) {
      logger.warn({ msg: 'Failed to fetch detailed match info', matchId: id, error: err.message });
      return {
        success: true,
        matchId: id,
        data: buildInfoFallback(id),
        updatedAt: new Date().toISOString(),
        message: 'Detailed match info fallback returned; some fields are unavailable from provider',
      };
    }
  });
}
