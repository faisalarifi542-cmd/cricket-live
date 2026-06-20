import { cacheGet, cacheGetOrFetch, cacheGetOrFetchSWR, cacheSet, KEYS, SWR_WINDOW, TTL, unwrapSWR } from '../lib/redis.js';
import providerManager from '../providers/provider-manager.js';
import { cacheMiddleware } from '../middleware/cache.js';
import { indexMatchListItems, indexScheduleMatches, getMatchSummary, summaryToMatchDetail } from '../lib/match-index.js';
import logger from '../lib/logger.js';
import {
  buildPublicAppConfig,
  enrichMatchListWithStreams,
  fetchActiveStreamsForMatch,
  isLiveStreamingFeatureEnabled,
  publicStreamDto,
} from '../lib/public-app-state.js';
import {
  fetchManualMatchById,
  mergeManualMatches,
} from '../lib/manual-matches.js';
import { buildCommentaryFeed } from '../providers/cricbuzz/normalizer.js';

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

  // Conservative guard for the match-detail SWR cache: only block clearly-empty
  // payloads so invalid/broken data is never cached (or served stale). A valid
  // match detail must carry at least a match id, a status, or one team identity.
  function isInvalidMatchDetailPayload(data) {
    if (!data || typeof data !== 'object') return true;
    const hasId = !!(data.match_id || data.matchId);
    const hasStatus = !!data.status;
    const hasTeam = !!(data.team1?.name || data.team1?.short_name
      || data.team2?.name || data.team2?.short_name);
    return !(hasId || hasStatus || hasTeam);
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

  async function streamSummaryForMatch(id) {
    const [config, streamRows] = await Promise.all([
      buildPublicAppConfig().catch(() => ({ enableLiveStreaming: true })),
      fetchActiveStreamsForMatch(id).catch(() => []),
    ]);
    const liveStreamsEnabled = isLiveStreamingFeatureEnabled(config);
    const streams = liveStreamsEnabled
      ? streamRows.map(publicStreamDto).filter(Boolean)
      : [];
    return {
      hasLiveStream: streams.length > 0,
      watchLiveEnabled: liveStreamsEnabled && streams.length > 0,
      streamCount: streams.length,
      isPremiumStreamAvailable: streams.some((stream) => stream.isPremium),
      streamBadgeText: streams.length > 0
        ? (streams.some((stream) => stream.isPremium) ? 'Premium' : 'LIVE STREAM')
        : null,
      defaultStreamId: streams[0]?.id || null,
      streams,
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
            fromCache: { type: 'boolean' },
          },
        },
      },
    },
    // No preHandler cacheMiddleware: it does a plain cacheGet that would read the
    // SWR envelope as raw data and short-circuit with a different shape. SWR is
    // handled inside the handler instead (fourth wired route, after live-line +
    // scorecard + commentary). X-Cache is set manually below.
  }, async (request, reply) => {
    // SWR: serve the cached provider live list instantly and refresh in the
    // background within the stale window. TTL.LIVE_LIST (8s) + SWR_WINDOW.LIVE_LIST
    // (4s) → max served age 12s. Validation INSIDE the fetchFn: only an actual
    // array is cached (an empty array is valid — it means no live matches right
    // now — and is cached to avoid hammering the provider); a non-array/broken
    // payload returns null so SWR skips caching.
    const { data, fromCache } = await cacheGetOrFetchSWR(
      KEYS.matchesList('live'),
      TTL.LIVE_LIST,
      SWR_WINDOW.LIVE_LIST,
      async () => {
        const result = await providerManager.execute('getLiveMatches');
        const list = result?.data;
        return Array.isArray(list) ? list : null;
      }
    );
    reply.header('X-Cache', fromCache ? 'HIT' : 'MISS');
    // Manual match merge + stream enrichment run per-request on top of the cached
    // provider list (unchanged) so manual matches and live stream gating fields
    // are never stale-cached.
    const merged = await mergeManualMatches(data || [], { status: 'live' });
    if (merged?.length) indexMatchListItems(merged).catch(() => {});
    // Expose top-level fromCache (boolean, never null) so the response shape
    // matches the other SWR routes and Flutter can read cache state. X-Cache
    // header above is derived from the same value.
    return { success: true, data: await enrichMatchListWithStreams(merged, { allowReplay: false }).catch(() => merged), fromCache };
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
    return { success: true, data: await enrichMatchListWithStreams(data || [], { allowReplay: false }).catch(() => data || []) };
  });

  // GET /matches/recent
  fastify.get('/matches/recent', {
    schema: { description: 'Get recently completed matches', tags: ['Matches'] },
    preHandler: cacheMiddleware(KEYS.matchesList('recent'), TTL.RECENT),
  }, async (request, reply) => {
    return { success: true, data: await enrichMatchListWithStreams(await fetchRecentMatches(), { allowReplay: false }).catch(() => []) };
  });

  // GET /matches/finished — app-facing alias for /matches/recent
  fastify.get('/matches/finished', {
    schema: { description: 'Get completed matches (alias of /matches/recent)', tags: ['Matches'] },
    preHandler: cacheMiddleware(KEYS.matchesList('recent'), TTL.RECENT),
  }, async () => {
    return { success: true, data: await enrichMatchListWithStreams(await fetchRecentMatches(), { allowReplay: false }).catch(() => []) };
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
    // No preHandler cacheMiddleware: it does a plain cacheGet that would read the
    // SWR envelope as raw data and short-circuit with a different shape. The SWR
    // helper handles the cache below and we set X-Cache manually.
  }, async (request, reply) => {
    const { id } = request.params;
    try {
      const { data, fromCache } = await cacheGetOrFetchSWR(
        KEYS.matchLive(id),
        TTL.LIVE_SCORE,
        SWR_WINDOW.MATCH_DETAIL,
        async () => {
          const result = await providerManager.execute('getMatchInfo', id);
          return isInvalidMatchDetailPayload(result?.data) ? null : result.data;
        }
      );

      if (data) {
        reply.header('X-Cache', fromCache ? 'HIT' : 'MISS');
        const summary = await streamSummaryForMatch(id);
        return { success: true, data: { ...data, ...summary }, fromCache };
      }
    } catch {
      // Livescore endpoint failed — try matchHeader fallback for upcoming/preview matches
    }

    // Fallback 2: try matchHeader from provider
    try {
      const headerResult = await providerManager.execute('getMatchHeader', id);
      if (headerResult?.data) {
        const summary = await streamSummaryForMatch(id);
        return {
          success: true,
          data: {
            ...headerResult.data,
            ...summary,
          },
          fromCache: false,
        };
      }
    } catch { /* ignore */ }

    // Fallback 3: look up cached match summary (indexed from schedule/list endpoints)
    try {
      const summary = await getMatchSummary(id);
      if (summary && (summary.team1?.name || summary.team1?.short_name)) {
        const streamSummary = await streamSummaryForMatch(id);
        return {
          success: true,
          data: {
            ...summaryToMatchDetail(summary),
            ...streamSummary,
          },
          fromCache: false,
        };
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
              const streamSummary = await streamSummaryForMatch(id);
              return {
                success: true,
                data: {
                  ...summaryToMatchDetail(summary),
                  ...streamSummary,
                },
                fromCache: false,
              };
            }
          }
        } catch { /* try next type */ }
      }
    } catch { /* ignore */ }

    // Fallback 5: admin-controlled manual / test match
    try {
      const manual = await fetchManualMatchById(id);
      if (manual) {
        const detail = manualMatchToDetail(manual);
        const streams = await streamSummaryForMatch(id);
        return {
          success: true,
          data: {
            ...detail,
            ...streams,
          },
          fromCache: false,
        };
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
        hasLiveStream: false,
        watchLiveEnabled: false,
        streamCount: 0,
        isPremiumStreamAvailable: false,
        streamBadgeText: null,
        defaultStreamId: null,
        streams: [],
      },
      fromCache: false,
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
  }, async (request, reply) => {
    const { id } = request.params;
    try {
      // SWR (second wired route, after live-line): serve cached scorecard
      // instantly and refresh in the background within the stale window.
      // TTL.SCORECARD (5s) + SWR_WINDOW.SCORECARD (3s) → max served age 8s.
      // Validation is preserved INSIDE the fetchFn: only a scorecard with >=1
      // innings is returned (and therefore cached); empty/broken data returns
      // null so SWR skips caching, exactly as the prior [FIXED] guard did.
      const { data, fromCache } = await cacheGetOrFetchSWR(
        KEYS.matchScorecard(id),
        TTL.SCORECARD,
        SWR_WINDOW.SCORECARD,
        async () => {
          const result = await providerManager.execute('getScorecard', id);
          const sc = result?.data || null;
          if (sc && Array.isArray(sc.innings) && sc.innings.length > 0) {
            return sc;
          }
          logger.warn({ msg: '[FIXED] Not caching empty scorecard', matchId: id, innings: sc?.innings?.length });
          return null;
        },
      );

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
    // No preHandler cacheMiddleware: it does a plain cacheGet that would read the
    // SWR envelope as raw data and short-circuit with a different shape. SWR is
    // handled inside the handler instead (third wired route, after live-line +
    // scorecard).
  }, async (request, reply) => {
    const { id } = request.params;
    const { page = 1, limit = 50 } = request.query;

    // SWR: serve cached commentary instantly and refresh in the background within
    // the stale window. TTL.COMMENTARY (5s) + SWR_WINDOW.COMMENTARY (3s) → max
    // served age 8s. Validation is preserved INSIDE the fetchFn: only a non-empty
    // commentary array is returned (and therefore cached); empty/broken data
    // returns null so SWR skips caching and never serves stale junk.
    const { data: commentary, fromCache } = await cacheGetOrFetchSWR(
      KEYS.matchCommentary(id),
      TTL.COMMENTARY,
      SWR_WINDOW.COMMENTARY,
      async () => {
        const result = await providerManager.execute('getCommentary', id);
        const list = result?.data || null;
        return Array.isArray(list) && list.length > 0 ? list : null;
      }
    );

    reply.header('X-Cache', fromCache ? 'HIT' : 'MISS');

    if (!commentary) return { success: true, data: [], pagination: { page, limit, total: 0, pages: 0 }, fromCache, message: 'Commentary not available for this match' };

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
      fromCache,
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
      const match = unwrapSWR(await cacheGet(KEYS.matchLive(id)));
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

  // Build the merged Live Center payload from miniscore + commentary +
  // scorecard. Each section is included only when it carries real data.
  function buildLiveCenterPayload({
    matchId,
    detail,
    commentary,
    scorecard,
    fullCommentary,
    overByOver,
    ballsMap,
    quickAccess,
  }) {
    const base = detail?.live_center || {};
    const status = base.status || detail?.status || 'upcoming';
    const isFinished = base.match_state === 'finished'
      || status === 'completed'
      || status === 'abandoned'
      || status === 'no_result';
    const inningsId = resolveCurrentInningsId(detail, scorecard, fullCommentary, overByOver, ballsMap);
    const fullLines = Array.isArray(fullCommentary?.commentary) ? fullCommentary.commentary : [];
    const basicLines = Array.isArray(commentary) ? commentary : [];
    const allCommentary = mergeCommentaryLines(fullLines, basicLines);
    const overRows = Array.isArray(overByOver?.overs) ? overByOver.overs : [];
    const ballRows = Array.isArray(ballsMap?.balls) ? ballsMap.balls : [];

    // Current batters: prefer miniscore; fall back to not-out batters in the
    // latest scorecard innings (handles brief gaps between balls/over breaks).
    let currentBatters = Array.isArray(base.current_batters) ? base.current_batters : [];
    if (!isFinished && currentBatters.length === 0 && Array.isArray(ballsMap?.batters)) {
      currentBatters = ballsMap.batters
        .filter((b) => b && b.name)
        .slice(0, 2)
        .map((b, idx) => ({
          player_id: String(b.id || b.player_id || ''),
          name: b.name,
          runs: b.runs || 0,
          balls: b.balls || 0,
          fours: b.fours || 0,
          sixes: b.sixes || 0,
          strike_rate: b.strikeRate || b.strike_rate || 0,
          is_batting: true,
          is_striker: idx === 0,
        }));
    }
    if (!isFinished && currentBatters.length === 0 && fullLines.length) {
      currentBatters = latestBattersFromFullCommentary(fullLines);
    }
    if (!isFinished && currentBatters.length === 0 && scorecard?.innings?.length) {
      const lastInn = resolveScorecardInnings(scorecard, inningsId);
      const notOut = (lastInn.batting || [])
        .filter((b) => b && b.name && (b.is_batting || /not out|batting/i.test(b.dismissal || '')))
        .slice(0, 2)
        .map((b, idx) => ({
          player_id: String(b.player_id || ''),
          name: b.name,
          runs: b.runs || 0,
          balls: b.balls || 0,
          fours: b.fours || 0,
          sixes: b.sixes || 0,
          strike_rate: b.strike_rate || 0,
          is_batting: true,
          is_striker: idx === 0,
        }));
      if (notOut.length) currentBatters = notOut;
    }

    // Current bowler: prefer miniscore; fall back to the latest commentary
    // bowler when missing.
    let currentBowler = base.current_bowler || null;
    if (!isFinished && !currentBowler && ballsMap?.bowlers?.length) {
      const latestBall = ballRows.find((b) => b && b.bowlerId);
      const bowler = ballsMap.bowlers.find((b) => String(b.id || b.player_id || '') === String(latestBall?.bowlerId || ''))
        || ballsMap.bowlers[0];
      if (bowler?.name) currentBowler = normalizeLiveCenterBowler(bowler);
    }
    if (!isFinished && !currentBowler && overRows.length) {
      const row = overRows.find((o) => o && (o.bowlerName || o.bowlerId));
      if (row?.bowlerName) {
        currentBowler = {
          player_id: String(row.bowlerId || ''),
          name: row.bowlerName,
          overs: row.bowlerOvers || 0,
          maidens: row.bowlerMaidens || 0,
          runs: row.bowlerRuns || 0,
          wickets: row.bowlerWickets || 0,
          economy: 0,
          is_bowling: true,
        };
      }
    }
    if (!isFinished && !currentBowler && allCommentary.length) {
      const withBowler = allCommentary.find((c) => c && c.bowler && (c.bowler.name || typeof c.bowler === 'string'));
      if (withBowler) {
        const b = withBowler.bowler;
        currentBowler = {
          player_id: String(b.id || b.player_id || ''),
          name: b.name || String(b),
          overs: b.overs || 0,
          maidens: b.maidens || 0,
          runs: b.runs || 0,
          wickets: b.wickets || 0,
          economy: b.economy || 0,
          is_bowling: true,
        };
      }
    }

    // Recent balls: prefer miniscore-parsed; fall back to commentary deliveries.
    let recentBalls = Array.isArray(base.recent_balls) ? base.recent_balls : [];
    if (recentBalls.length < 2 && ballRows.length) {
      recentBalls = ballRows.slice(0, 8).map(ballToRecentBall);
    }
    if (recentBalls.length < 2 && overRows.length) {
      recentBalls = parseOverSummaryBalls(overRows[0]).slice(0, 8);
    }
    if (recentBalls.length < 2 && allCommentary.length) {
      recentBalls = allCommentary
        .filter(hasDelivery)
        .slice(0, 8)
        .map(commentaryToRecentBall);
    }

    // Commentary lines (latest 8).
    const commentaryLines = allCommentary.length
      ? allCommentary
          .filter((c) => c && (c.text || c.commentary || c.rawText))
          .slice(0, 8)
          .map((c) => ({
            over: deliveryOver(c),
            ball: deliveryBall(c),
            text: c.text || c.commentary || c.rawText || '',
            event: eventType(c),
          }))
      : [];
    const scoreInfo = resolveCurrentScore({ base, detail, scorecard, ballsMap, overByOver, inningsId });
    const lastWicket = base.last_wicket || detail?.last_wicket || resolveLastWicket(allCommentary, scorecard, inningsId);

    const payload = {
      match_state: base.match_state || (isFinished ? 'finished' : (status === 'upcoming' ? 'upcoming' : 'live')),
      status,
      status_text: base.status_text || detail?.status_text || '',
      score: scoreInfo.score || base.score || '',
      overs: scoreInfo.overs || base.overs || '',
      current_run_rate: scoreInfo.currentRunRate || base.current_run_rate || detail?.current_run_rate || 0,
      required_run_rate: base.required_run_rate || detail?.required_run_rate || 0,
      target: base.target ?? detail?.target ?? null,
      current_batters: currentBatters,
      current_bowler: currentBowler,
      partnership: base.partnership || detail?.partnership || null,
      last_wicket: lastWicket,
      recent_balls: recentBalls,
      commentary: commentaryLines,
      player_of_match: isFinished
        ? (base.player_of_match || detail?.player_of_match || null)
        : null,
      result: base.result || detail?.result || '',
      innings_id: inningsId,
      sources: {
        quick_access: !!quickAccess && Object.keys(quickAccess || {}).length > 0,
        full_commentary: fullLines.length,
        commentary: basicLines.length,
        over_by_over: overRows.length,
        balls_map: ballRows.length,
        scorecard_innings: scorecard?.innings?.length || 0,
      },
      updated_at: new Date().toISOString(),
    };

    if (process.env.NODE_ENV !== 'production') {
      logger.info({
        msg: '[LiveCenter] built',
        matchId,
        state: payload.match_state,
        currentBatters: payload.current_batters.length,
        hasBowler: !!payload.current_bowler,
        recentBalls: payload.recent_balls.length,
        commentary: payload.commentary.length,
        sources: payload.sources,
      });
    }

    return payload;
  }

  function resolveCurrentInningsId(detail, scorecard, fullCommentary, overByOver, ballsMap) {
    const candidates = [
      detail?.current_innings,
      detail?.live_center?.innings_id,
      ballsMap?.scoreDetails?.inningsId,
      fullCommentary?.inningsId,
      overByOver?.overs?.[0]?.inningsId,
      scorecard?.innings?.[scorecard.innings.length - 1]?.innings_number,
    ];
    const value = candidates.find((v) => Number(v) > 0);
    return Number(value || 1);
  }

  function resolveScorecardInnings(scorecard, inningsId) {
    const innings = scorecard?.innings || [];
    return innings.find((inn) => Number(inn.innings_number) === Number(inningsId))
      || innings[innings.length - 1]
      || {};
  }

  function normalizeLiveCenterBowler(bowler) {
    return {
      player_id: String(bowler.id || bowler.player_id || ''),
      name: bowler.name || '',
      overs: bowler.overs || 0,
      maidens: bowler.maidens || 0,
      runs: bowler.runs || 0,
      wickets: bowler.wickets || 0,
      economy: bowler.economy || 0,
      wides: bowler.wides || 0,
      no_balls: bowler.noBalls || bowler.no_balls || 0,
      is_bowling: true,
    };
  }

  function latestBattersFromFullCommentary(lines) {
    const seen = new Set();
    const batters = [];
    for (const row of lines) {
      const b = row?.batsman;
      if (!b?.name || seen.has(String(b.id || b.name))) continue;
      seen.add(String(b.id || b.name));
      batters.push({
        player_id: String(b.id || ''),
        name: b.name,
        runs: b.runs || 0,
        balls: b.balls || 0,
        fours: b.fours || 0,
        sixes: b.sixes || 0,
        strike_rate: b.strikeRate || b.strike_rate || 0,
        is_batting: true,
        is_striker: batters.length === 0,
      });
      if (batters.length >= 2) break;
    }
    return batters;
  }

  function mergeCommentaryLines(primary, fallback) {
    const rows = [];
    const seen = new Set();
    for (const row of [...(primary || []), ...(fallback || [])]) {
      if (!row) continue;
      const key = String(row.timestamp || row.id || `${deliveryOver(row)}:${deliveryBall(row)}:${row.text || row.commentary || ''}`);
      if (seen.has(key)) continue;
      seen.add(key);
      rows.push(row);
    }
    return rows.sort((a, b) => Number(b.timestamp || 0) - Number(a.timestamp || 0));
  }

  function deliveryOver(row) {
    const value = row?.over ?? row?.overNumber ?? row?.ballMetric ?? '';
    if (value === null || value === undefined) return '';
    return String(value);
  }

  function deliveryBall(row) {
    const value = row?.ball ?? row?.ballNumber ?? row?.ballNbr ?? '';
    if (value === null || value === undefined) return '';
    return String(value);
  }

  function hasDelivery(row) {
    return deliveryOver(row) !== '' || deliveryBall(row) !== '';
  }

  function eventType(row) {
    const event = String(row?.event || '').toLowerCase();
    if (row?.is_wicket || row?.isWicket || event.includes('wicket')) return 'wicket';
    if (row?.is_six || row?.isSix || event.includes('six')) return 'six';
    if (row?.is_four || row?.isFour || event.includes('four')) return 'four';
    return event || 'ball';
  }

  function runValue(row) {
    if (typeof row?.runs === 'number') return row.runs;
    if (typeof row?.runs?.total === 'number') return row.runs.total;
    if (typeof row?.totalRuns === 'number') return row.totalRuns;
    return 0;
  }

  function ballTypeFromValue(value, event) {
    const upper = String(value || '').toUpperCase();
    if (event === 'wicket' || upper.includes('W')) return 'wicket';
    if (event === 'six' || upper === '6') return 'six';
    if (event === 'four' || upper === '4') return 'four';
    if (upper === '0' || upper === '.' || upper === '•') return 'dot';
    if (upper.includes('NB') || upper.includes('WD') || upper.includes('B') || upper.includes('LB')) return 'extra';
    return 'run';
  }

  function commentaryToRecentBall(row) {
    const event = eventType(row);
    const value = event === 'wicket' ? 'W' : String(runValue(row));
    return {
      over: [deliveryOver(row), deliveryBall(row)].filter(Boolean).join('.').replace(/(\.\d+)\.\d+$/, '$1'),
      value,
      type: ballTypeFromValue(value, event),
    };
  }

  function ballToRecentBall(ball) {
    const event = eventType(ball);
    const value = event === 'wicket' ? 'W' : String(ball.ballLabel || ball.totalRuns || 0).replace('•', '0');
    return {
      over: String(ball.overNumber || ''),
      value,
      type: ballTypeFromValue(value, event),
    };
  }

  function parseOverSummaryBalls(overRow) {
    const over = String(overRow?.overNumber || '');
    return String(overRow?.summary || '')
      .split(/\s+/)
      .filter(Boolean)
      .map((value, index) => ({
        over: over ? `${Number(over) - 1}.${index + 1}` : '',
        value: value === '•' || value === '.' ? '0' : value,
        type: ballTypeFromValue(value, value.toUpperCase().includes('W') ? 'wicket' : ''),
      }));
  }

  function resolveCurrentScore({ base, detail, scorecard, ballsMap, overByOver, inningsId }) {
    if (ballsMap?.scoreDetails && Number(ballsMap.scoreDetails.runs) >= 0) {
      const sd = ballsMap.scoreDetails;
      return {
        score: `${sd.runs || 0}/${sd.wickets || 0}`,
        overs: String(sd.overs || ''),
        currentRunRate: sd.runRate || 0,
      };
    }
    const over = overByOver?.overs?.find((o) => Number(o.inningsId) === Number(inningsId)) || overByOver?.overs?.[0];
    if (over && Number(over.totalScore) >= 0) {
      return {
        score: `${over.totalScore || 0}/${over.totalWickets || 0}`,
        overs: String(over.overNumber || ''),
        currentRunRate: 0,
      };
    }
    const inn = resolveScorecardInnings(scorecard, inningsId);
    if (inn?.total) {
      return {
        score: `${inn.total.runs || 0}/${inn.total.wickets || 0}`,
        overs: String(inn.total.overs || ''),
        currentRunRate: inn.run_rate || 0,
      };
    }
    return {
      score: base?.score || '',
      overs: base?.overs || '',
      currentRunRate: detail?.current_run_rate || 0,
    };
  }

  function resolveLastWicket(lines, scorecard, inningsId) {
    const wicketLine = (lines || []).find((row) => eventType(row) === 'wicket' && (row.text || row.commentary));
    if (wicketLine) return wicketLine.text || wicketLine.commentary || '';
    const inn = resolveScorecardInnings(scorecard, inningsId);
    const wickets = inn?.fall_of_wickets || inn?.fallOfWickets || [];
    if (Array.isArray(wickets) && wickets.length) {
      const last = wickets[wickets.length - 1];
      return last.player || last.name || last.wicket || last.text || '';
    }
    return '';
  }

  // GET /match/:id/live-center — one merged object for the app's Live tab.
  fastify.get('/match/:id/live-center', {
    schema: {
      description: 'Merged Live Center: current batters, bowler, partnership, last wicket, recent balls and latest commentary',
      tags: ['Matches'],
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
        required: ['id'],
      },
    },
  }, async (request, reply) => {
    const { id } = request.params;

    // Pull match detail first to decide on the live/finished cache TTL.
    let detail = null;
    try {
      // Shares the match-detail SWR key, so it MUST read/write the same envelope
      // as the /match/:id route — otherwise the two clobber each other and the
      // route degrades to a permanent cache miss.
      const res = await cacheGetOrFetchSWR(
        KEYS.matchLive(id),
        TTL.LIVE_SCORE,
        SWR_WINDOW.MATCH_DETAIL,
        async () => {
          const d = (await providerManager.execute('getMatchInfo', id)).data;
          return isInvalidMatchDetailPayload(d) ? null : d;
        },
      );
      detail = res?.data || null;
    } catch { /* detail optional */ }

    const status = detail?.status || 'upcoming';
    const isFinished = status === 'completed' || status === 'abandoned' || status === 'no_result';
    const ttl = isFinished ? TTL.LIVE_CENTER_DONE : TTL.LIVE_CENTER_LIVE;

    const cacheKey = KEYS.matchLiveCenter(id);
    const cached = await cacheGet(cacheKey);
    if (cached) {
      reply.header('X-Cache', 'HIT');
      return { success: true, data: cached, fromCache: true };
    }

    const currentInningsId = resolveCurrentInningsId(detail, null, null, null, null);

    // Fetch every Cricbuzz source that can contribute Live tab data. These are
    // optional and merged best-effort, so one partial endpoint never empties
    // the whole Live Center.
    const [commentaryRes, scorecardRes] = await Promise.allSettled([
      // Shares the commentary SWR key, so it MUST read/write the same envelope
      // as the /commentary route — otherwise the two clobber each other and the
      // route degrades to a permanent cache miss. Returns the commentary array
      // (or null on empty/invalid), never a raw envelope.
      cacheGetOrFetchSWR(
        KEYS.matchCommentary(id),
        TTL.COMMENTARY,
        SWR_WINDOW.COMMENTARY,
        async () => {
          const list = (await providerManager.execute('getCommentary', id)).data;
          return Array.isArray(list) && list.length > 0 ? list : null;
        },
      ),
      // Shares the scorecard SWR key, so it MUST read/write the same envelope
      // as the /scorecard route — otherwise the two clobber each other and the
      // route degrades to a permanent cache miss. Returns the sc payload (or
      // null), never a raw envelope, so downstream `scorecard.innings` is intact.
      cacheGetOrFetchSWR(
        KEYS.matchScorecard(id),
        TTL.SCORECARD,
        SWR_WINDOW.SCORECARD,
        async () => {
          const sc = (await providerManager.execute('getScorecard', id)).data;
          return sc && Array.isArray(sc.innings) && sc.innings.length > 0 ? sc : null;
        },
      ),
    ]);

    const commentary = commentaryRes.status === 'fulfilled'
      ? (commentaryRes.value?.data || [])
      : [];
    const scorecard = scorecardRes.status === 'fulfilled'
      ? (scorecardRes.value?.data || null)
      : null;

    const inningsId = resolveCurrentInningsId(detail, scorecard, null, null, null) || currentInningsId;
    const [quickAccessRes, fullCommentaryRes, overByOverRes, ballsMapRes] = await Promise.allSettled([
      providerManager.execute('getQuickAccess', id),
      cacheGetOrFetch(
        KEYS.fullCommentary(id, inningsId),
        TTL.COMMENTARY,
        async () => (await providerManager.execute('getFullCommentary', id, String(inningsId))).data,
      ),
      cacheGetOrFetch(
        KEYS.overByOver(id, inningsId),
        TTL.COMMENTARY,
        async () => (await providerManager.execute('getOverByOver', id, String(inningsId))).data,
      ),
      cacheGetOrFetch(
        KEYS.ballsMap(id, inningsId),
        TTL.COMMENTARY,
        async () => (await providerManager.execute('getBallsMap', id, String(inningsId))).data,
      ),
    ]);

    const quickAccess = quickAccessRes.status === 'fulfilled'
      ? (quickAccessRes.value?.data || quickAccessRes.value || null)
      : null;
    const fullCommentary = fullCommentaryRes.status === 'fulfilled'
      ? (fullCommentaryRes.value?.data || null)
      : null;
    const overByOver = overByOverRes.status === 'fulfilled'
      ? (overByOverRes.value?.data || null)
      : null;
    const ballsMap = ballsMapRes.status === 'fulfilled'
      ? (ballsMapRes.value?.data || null)
      : null;

    const payload = buildLiveCenterPayload({
      matchId: id,
      detail,
      commentary,
      scorecard,
      fullCommentary,
      overByOver,
      ballsMap,
      quickAccess,
    });

    // Only cache payloads that carry real data so we never lock in an empty
    // live-center for the full TTL.
    const hasData = payload.current_batters.length > 0
      || !!payload.current_bowler
      || payload.recent_balls.length > 0
      || payload.commentary.length > 0
      || payload.match_state === 'finished';
    if (hasData) {
      await cacheSet(cacheKey, payload, ttl);
    }

    reply.header('X-Cache', 'MISS');
    return { success: true, data: payload, fromCache: false };
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

  // GET /match/:id/full-commentary  (combined, normalized, deduped feed)
  // Fetches every innings' full commentary, classifies each entry on the
  // server, removes duplicates and merges fragments. The app trusts the
  // returned `type`/`label`/`isBall` fields directly.
  fastify.get('/match/:id/full-commentary', {
    schema: {
      description: 'Combined normalized commentary feed for all innings',
      tags: ['Matches'],
      params: {
        type: 'object',
        properties: { id: { type: 'string' } },
        required: ['id'],
      },
    },
  }, async (request) => {
    const { id } = request.params;
    try {
      const { data: feed } = await cacheGetOrFetch(
        `match:${id}:commentary-feed`,
        TTL.FULL_COMMENTARY_LIVE,
        async () => {
          // Only fetch innings we actually expect. Default to 2 (limited
          // overs); a cached scorecard with more innings (Tests) bumps it up.
          // This avoids hammering 404s that would trip the circuit breaker.
          let inningsCount = 2;
          try {
            const sc = unwrapSWR(await cacheGet(KEYS.matchScorecard(id)));
            if (Array.isArray(sc?.innings) && sc.innings.length > 2) {
              inningsCount = Math.min(4, sc.innings.length);
            }
          } catch { /* scorecard optional */ }

          const nums = Array.from({ length: inningsCount }, (_, i) => i + 1);
          const results = await Promise.allSettled(
            nums.map((n) =>
              providerManager.execute('getFullCommentary', id, String(n))),
          );

          const inningsList = [];
          results.forEach((res, idx) => {
            if (res.status !== 'fulfilled') return;
            const data = res.value?.data || res.value;
            const list = Array.isArray(data?.commentary) ? data.commentary : [];
            if (!list.length) return;
            inningsList.push({
              inningsId: data.inningsId || nums[idx],
              teamName: list[0]?.batTeamName || '',
              commentary: list,
            });
          });

          const built = buildCommentaryFeed(id, inningsList);
          if (process.env.NODE_ENV !== 'production') {
            logger.debug({
              msg: 'commentary-feed built',
              matchId: id,
              innings: built.innings.map((i) => ({
                n: i.inningsNumber,
                items: i.items.length,
              })),
              total: built.items.length,
            });
          }
          return built;
        },
      );

      return {
        success: true,
        matchId: id,
        data: feed || { matchId: id, innings: [], items: [] },
        message: (!feed || !feed.items?.length)
          ? 'Commentary not available for this match'
          : null,
      };
    } catch {
      return {
        success: true,
        matchId: id,
        data: { matchId: id, innings: [], items: [] },
        message: 'Commentary not available for this match',
      };
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
      // SWR (first wired route): serve cached live-line instantly and refresh in
      // the background while within the stale window. TTL.LIVE_LINE (5s) +
      // SWR_WINDOW.LIVE_LINE (3s) → max served age 8s. Only valid, cleaned
      // payloads are cached (fetchFn returns null otherwise, so SWR skips them).
      const { data: liveData, fromCache } = await cacheGetOrFetchSWR(
        KEYS.matchLiveLine(id),
        TTL.LIVE_LINE,
        SWR_WINDOW.LIVE_LINE,
        async () => {
          const result = await providerManager.execute('getLiveLine', id);
          const cleaned = cleanLiveLinePayload(result?.data || null, id);
          return cleaned && !isInvalidLiveLinePayload(cleaned) ? cleaned : null;
        },
      );

      return {
        success: true,
        matchId: id,
        data: liveData || null,
        updatedAt: new Date().toISOString(),
        fromCache,
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
