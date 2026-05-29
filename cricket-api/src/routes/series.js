import { cacheGet, cacheGetOrFetch, cacheSet, KEYS, TTL } from '../lib/redis.js';
import providerManager from '../providers/provider-manager.js';
import { cacheMiddleware } from '../middleware/cache.js';
import logger from '../lib/logger.js';

export default async function seriesRoutes(fastify) {
  function normalizePointsTableResponse(seriesId, raw, seriesName = '') {
    const rows = Array.isArray(raw?.groups)
      ? raw.groups.flatMap((g) => (g.teams || []).map((t) => ({ ...t, groupName: g.groupName || '' })))
      : Array.isArray(raw)
        ? raw
        : [];

    const teams = rows.map((team, index) => ({
      position: team.position || team.rank || index + 1,
      teamId: String(team.teamId || team.team_id || ''),
      teamName: team.teamName || team.team_name || '',
      teamShort: team.teamShort || team.team_short || '',
      played: team.played || 0,
      won: team.won || 0,
      lost: team.lost || 0,
      tied: team.tied || 0,
      noResult: team.noResult ?? team.no_result ?? 0,
      nrr: Number(team.nrr || 0),
      points: Number(team.points || 0),
      qualified: team.qualified || false,
      logoUrl: team.logoUrl || team.logo_url || '',
    }));

    return {
      seriesId: String(seriesId),
      seriesName,
      groups: teams.length ? [{ groupName: rows[0]?.groupName || '', teams }] : [],
      updatedAt: new Date().toISOString(),
    };
  }

  function normalizeSeriesSchedule(seriesId, result) {
    const matches = (result?.matches || []).map((m) => ({
      matchId: String(m.match_id || m.matchId || ''),
      matchDesc: m.match_desc || m.matchDesc || '',
      matchFormat: m.match_format || m.matchFormat || '',
      status: m.status || '',
      statusText: m.status_text || m.statusText || '',
      team1: m.team1 || null,
      team2: m.team2 || null,
      venue: m.venue?.name || '',
      city: m.venue?.city || '',
      startTime: m.start_time || m.startTime || null,
      endTime: m.end_time || m.endTime || null,
      score: m.score || {},
      result: m.result || (m.status === 'completed' ? m.status_text : ''),
    }));

    return {
      seriesId: String(seriesId),
      seriesName: result?.seriesName || '',
      matches,
      updatedAt: new Date().toISOString(),
    };
  }

  function normalizeStatsAlias(type) {
    const t = String(type || '').toLowerCase();
    if (['batting', 'bat', 'oranges', 'orange-cap', 'orange', 'runs', 'most-runs', 'mostruns'].includes(t)) return 'mostRuns';
    if (['bowling', 'bowl', 'purple-cap', 'purple', 'wickets', 'most-wickets', 'mostwickets'].includes(t)) return 'mostWickets';
    return type;
  }

  function normalizeStatTableForApp(table, requestedType) {
    const players = table?.players || [];
    const isBowling = String(requestedType).toLowerCase().includes('wicket') || String(requestedType).toLowerCase().includes('bowl');
    return {
      header: table?.header || requestedType,
      category: table?.category || '',
      type: requestedType,
      players: players.map((p, index) => {
        const stats = p.stats || p;
        if (isBowling) {
          return {
            rank: index + 1,
            playerId: String(p.playerId || p.player_id || ''),
            playerName: p.playerName || p.player_name || '',
            team: p.team || p.Team || '',
            matches: Number(stats.Mat || stats.Matches || stats.MATCHES || stats.matches || 0),
            innings: Number(stats.Inns || stats.INNS || stats.innings || 0),
            overs: stats.Overs || stats.OVERS || stats.O || stats.overs || '',
            wickets: Number(stats.Wkts || stats.Wickets || stats.WKTS || stats.wickets || 0),
            economy: Number(stats.Econ || stats.Economy || stats.ECON || stats.economy || 0),
            average: Number(stats.Avg || stats.Average || stats.AVG || stats.average || 0),
            bestBowling: stats.BBI || stats.Best || stats.BEST || stats.bestBowling || '',
            fourWickets: Number(stats['4W'] || stats['4-FERS'] || stats.fourWickets || 0),
            fiveWickets: Number(stats['5W'] || stats['5-FERS'] || stats.fiveWickets || 0),
            imageUrl: p.imageUrl || '',
          };
        }
        return {
          rank: index + 1,
          playerId: String(p.playerId || p.player_id || ''),
          playerName: p.playerName || p.player_name || '',
          team: p.team || p.Team || '',
          matches: Number(stats.Mat || stats.Matches || stats.MATCHES || stats.matches || 0),
          innings: Number(stats.Inns || stats.INNS || stats.innings || 0),
          runs: Number(stats.Runs || stats.RUNS || stats.runs || 0),
          average: Number(stats.Avg || stats.Average || stats.AVG || stats.average || 0),
          strikeRate: Number(stats.SR || stats.StrikeRate || stats.strikeRate || 0),
          highestScore: stats.HS || stats['HS'] || stats.highestScore || '',
          fours: Number(stats['4s'] || stats.Fours || stats.fours || 0),
          sixes: Number(stats['6s'] || stats.Sixes || stats.sixes || 0),
          hundreds: Number(stats['100s'] || stats.hundreds || 0),
          fifties: Number(stats['50s'] || stats.fifties || 0),
          imageUrl: p.imageUrl || '',
        };
      }),
      headers: table?.headers || [],
      filters: table?.filters || null,
    };
  }

  function toAppStatsType(providerType) {
    return providerType === 'mostWickets' ? 'bowling' : 'batting';
  }

  function toStatsRows(table, providerType) {
    const normalized = normalizeStatTableForApp(table, providerType);
    return {
      type: toAppStatsType(providerType),
      rows: normalized.players,
      players: normalized.players,
      headers: normalized.headers,
      filters: normalized.filters,
    };
  }

  async function fetchSeriesStatsTable(seriesId, providerType) {
    const cacheKey = KEYS.seriesStatsTable(seriesId, providerType);
    const cached = await cacheGet(cacheKey);
    if (cached?.players?.length) {
      return { table: cached, fromCache: true, sourcePath: `/api/cricket-series/series-stats/${seriesId}/${providerType}` };
    }

    const result = await providerManager.execute('getSeriesStatsTable', seriesId, providerType);
    const table = result?.data || null;
    if (table?.players?.length) {
      await cacheSet(cacheKey, table, TTL.SERIES_STATS_TABLE);
    }
    return { table, fromCache: false, sourcePath: `/api/cricket-series/series-stats/${seriesId}/${providerType}` };
  }

  function emptyStatsFailure(seriesId, type, sourcePath, table) {
    return {
      success: false,
      seriesId: String(seriesId),
      ...(type ? { type } : {}),
      data: null,
      message: 'Series stats source returned no rows',
      debug: {
        type: type || 'grouped',
        sourcePath,
        rawKeys: table ? Object.keys(table) : [],
        reason: 'No stats rows found',
      },
    };
  }

  async function fetchPointsTable(seriesId) {
    const hasUsableRows = (value) => {
      const rows = Array.isArray(value?.groups)
        ? value.groups.flatMap((g) => g.teams || [])
        : Array.isArray(value)
          ? value
          : [];
      return rows.some((team) => {
        const name = team.teamName || team.team_name || '';
        const played = Number(team.played || 0);
        const won = Number(team.won || 0);
        const lost = Number(team.lost || 0);
        const points = Number(team.points || 0);
        return name && name !== 'Team' && (played || won || lost || points);
      });
    };
    let data = await cacheGet(KEYS.pointsTable(seriesId));
    const cachedHasRows = hasUsableRows(data);
    let fromCache = !!cachedHasRows;

    if (!cachedHasRows) {
      const result = await providerManager.execute('getPointsTable', seriesId);
      data = result?.data || [];
      const hasRows = hasUsableRows(data);
      if (hasRows) await cacheSet(KEYS.pointsTable(seriesId), data, TTL.POINTS_TABLE);
      fromCache = false;
    }

    return { data, fromCache };
  }

  // GET /series
  fastify.get('/series', {
    schema: { description: 'Get all series', tags: ['Series'] },
    preHandler: cacheMiddleware(KEYS.seriesList(), TTL.SERIES),
  }, async (request, reply) => {
    const { data } = await cacheGetOrFetch(
      KEYS.seriesList(),
      TTL.SERIES,
      async () => (await providerManager.execute('getSeriesList')).data
    );
    return { success: true, data: data || [] };
  });

  /**
   * Helper: fetch series data and strictly filter matches by source_series_id.
   * NEVER relabels matches — preserves original Cricbuzz series IDs.
   */
  async function fetchSeriesMatches(requestedSeriesId) {
    const cacheKey = `series:${requestedSeriesId}:data:v4`;
    const { data } = await cacheGetOrFetch(
      cacheKey,
      TTL.SERIES,
      async () => {
        const result = await providerManager.execute('getSeriesInfo', requestedSeriesId);
        return result.data;
      }
    );

    const seriesData = data?.matches ? data : { seriesId: requestedSeriesId, seriesName: data?.seriesName || '', matches: Array.isArray(data) ? data : [] };
    const allMatches = seriesData.matches || [];

    // STRICT FILTER: Only include matches whose ORIGINAL source series ID matches the requested one.
    // NEVER relabel or inject series_id — each match keeps its original Cricbuzz data.
    const filtered = [];
    const rejected = [];

    for (const m of allMatches) {
      const sourceId = String(m.source_series_id || m.series_id || '');
      if (sourceId === String(requestedSeriesId)) {
        filtered.push(m);
      } else if (sourceId === '') {
        // Match has no seriesId at all — cannot verify, exclude it
        rejected.push({ match_id: m.match_id, teams: `${m.team1?.name || '?'} vs ${m.team2?.name || '?'}`, reason: 'no_source_series_id' });
      } else {
        rejected.push({ match_id: m.match_id, teams: `${m.team1?.name || '?'} vs ${m.team2?.name || '?'}`, source_series_id: sourceId, source_series_name: m.source_series_name || m.series_name || '', reason: 'wrong_series' });
      }
    }

    if (rejected.length > 0) {
      logger.info({ msg: 'Series match filter', requestedSeriesId, accepted: filtered.length, rejected: rejected.length });
    }

    return {
      seriesId: requestedSeriesId,
      seriesName: seriesData.seriesName || '',
      matches: filtered,
      totalFetched: allMatches.length,
      totalFiltered: filtered.length,
    };
  }

  // GET /series/:id
  fastify.get('/series/:id', {
    schema: {
      description: 'Get series details and matches',
      tags: ['Series'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request, reply) => {
    const { id } = request.params;
    const result = await fetchSeriesMatches(id);
    if (!result) return reply.code(404).send({ success: false, error: 'Series not found' });
    return { success: true, ...result };
  });

  // GET /series/:id/matches — source of truth for series-specific matches
  fastify.get('/series/:id/matches', {
    schema: {
      description: 'Get only matches belonging to this series (strict source_series_id filtering). Supports ?status=live|upcoming|completed.',
      tags: ['Series'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
      querystring: {
        type: 'object',
        properties: {
          status: { type: 'string', enum: ['live', 'upcoming', 'completed'], description: 'Filter by match status' },
        },
      },
    },
  }, async (request, reply) => {
    const { id } = request.params;
    const { status } = request.query;

    const result = await fetchSeriesMatches(id);
    let matches = result.matches;

    // Apply status filter if provided
    if (status) {
      matches = matches.filter((m) => m.status === status);
    }

    return {
      success: true,
      seriesId: id,
      seriesName: result.seriesName,
      data: matches,
      totalFetched: result.totalFetched,
      totalFiltered: matches.length,
      ...(matches.length === 0 ? { message: 'No matches available for this series yet' } : {}),
    };
  });

  // GET /points-table/:seriesId
  fastify.get('/points-table/:seriesId', {
    schema: {
      description: 'Get points table for a series',
      tags: ['Series'],
      params: { type: 'object', properties: { seriesId: { type: 'string' } }, required: ['seriesId'] },
    },
  }, async (request, reply) => {
    const { seriesId } = request.params;
    try {
      const { data, fromCache } = await fetchPointsTable(seriesId);
      const response = normalizePointsTableResponse(seriesId, data);
      
      reply.header('X-Cache', fromCache ? 'HIT' : 'MISS');
      if (!response.groups.length) {
        return {
          success: false,
          seriesId,
          data: null,
          fromCache,
          message: 'Points table source not found',
          debug: {
            reason: data?._error || 'No team rows parsed from Cricbuzz points table source',
            teamsCount: 0,
          },
        };
      }
      
      return {
        success: true,
        seriesId,
        data: response,
        ...response,
        fromCache,
        message: response.groups.length === 0
          ? 'Points table not available for this series'
          : null,
      };
    } catch (err) {
      logger.error({ msg: '[FIXED] Points table fetch failed', seriesId, error: err.message });
      return {
        success: false,
        seriesId,
        data: null,
        message: 'Points table source not found',
        debug: { reason: err.message },
      };
    }
  });

  // GET /series/:id/points-table — app-facing points-table path
  fastify.get('/series/:id/points-table', {
    schema: {
      description: 'Get points table for a series',
      tags: ['Series'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request, reply) => {
    const { id } = request.params;
    try {
      const { data, fromCache } = await fetchPointsTable(id);
      const series = await fetchSeriesMatches(id).catch(() => ({ seriesName: '' }));
      const response = normalizePointsTableResponse(id, data, series.seriesName);
      reply.header('X-Cache', fromCache ? 'HIT' : 'MISS');
      if (!response.groups.length) {
        return {
          success: false,
          seriesId: id,
          data: null,
          fromCache,
          message: 'Points table source not found',
          debug: {
            reason: data?._error || 'No team rows parsed from Cricbuzz points table source',
            teamsCount: 0,
          },
        };
      }
      return {
        success: true,
        ...response,
        data: response,
        fromCache,
        message: response.groups.length === 0 ? 'Points table not available for this series' : null,
      };
    } catch (err) {
      logger.error({ msg: 'Points table fetch failed', seriesId: id, error: err.message });
      return { success: false, seriesId: id, data: null, message: 'Points table source not found', debug: { reason: err.message } };
    }
  });

  // GET /series/:id/stats
  fastify.get('/series/:id/stats', {
    schema: {
      description: 'Get available stat types for a series',
      tags: ['Series'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
      response: {
        200: {
          type: 'object',
          properties: {
            success: { type: 'boolean' },
            seriesId: { type: 'string' },
            data: { type: 'object', nullable: true, additionalProperties: true },
            counts: {
              type: 'object',
              nullable: true,
              additionalProperties: true,
            },
            message: { type: 'string', nullable: true },
            debug: { type: 'object', nullable: true, additionalProperties: true },
          },
        },
      },
    },
  }, async (request, reply) => {
    const { id } = request.params;
    try {
      const [battingResult, bowlingResult] = await Promise.all([
        fetchSeriesStatsTable(id, 'mostRuns'),
        fetchSeriesStatsTable(id, 'mostWickets'),
      ]);
      const batting = toStatsRows(battingResult.table, 'mostRuns');
      const bowling = toStatsRows(bowlingResult.table, 'mostWickets');

      if (!batting.rows.length && !bowling.rows.length) {
        reply.header('X-Cache', 'MISS');
        return emptyStatsFailure(
          id,
          null,
          `${battingResult.sourcePath}, ${bowlingResult.sourcePath}`,
          { batting: battingResult.table, bowling: bowlingResult.table },
        );
      }

      reply.header('X-Cache', battingResult.fromCache && bowlingResult.fromCache ? 'HIT' : 'MISS');
      return {
        success: true,
        seriesId: id,
        data: { batting, bowling },
        counts: {
          batting: batting.rows.length,
          bowling: bowling.rows.length,
        },
        message: null,
      };
    } catch (err) {
      return {
        success: false,
        seriesId: id,
        data: null,
        message: 'Series stats source returned no rows',
        debug: {
          type: 'grouped',
          sourcePath: `/api/cricket-series/series-stats/${id}/mostRuns, /api/cricket-series/series-stats/${id}/mostWickets`,
          rawKeys: [],
          reason: err.message,
        },
      };
    }
  });

  // GET /series/:id/stats/:type
  fastify.get('/series/:id/stats/:type', {
    schema: {
      description: 'Get stat table (player rankings) for a series by stat type',
      tags: ['Series'],
      params: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          type: { type: 'string', description: 'Stat type e.g. mostRuns, mostWickets' },
        },
        required: ['id', 'type'],
      },
      response: {
        200: {
          type: 'object',
          properties: {
            success: { type: 'boolean' },
            seriesId: { type: 'string' },
            type: { type: 'string' },
            providerType: { type: 'string', nullable: true },
            data: { type: 'object', nullable: true, additionalProperties: true },
            count: { type: 'integer', nullable: true },
            message: { type: 'string', nullable: true },
            debug: { type: 'object', nullable: true, additionalProperties: true },
          },
        },
      },
    },
  }, async (request, reply) => {
    const { id, type } = request.params;
    const providerType = normalizeStatsAlias(type);
    try {
      const { table, fromCache, sourcePath } = await fetchSeriesStatsTable(id, providerType);
      const data = toStatsRows(table, providerType);
      reply.header('X-Cache', fromCache ? 'HIT' : 'MISS');
      if (!data.rows.length) {
        return emptyStatsFailure(id, toAppStatsType(providerType), sourcePath, table);
      }
      return {
        success: true,
        seriesId: id,
        type: toAppStatsType(providerType),
        providerType,
        data,
        count: data.rows.length,
        message: null,
      };
    } catch (err) {
      return {
        success: false,
        seriesId: id,
        type: toAppStatsType(providerType),
        data: null,
        message: 'Series stats source returned no rows',
        debug: {
          type: toAppStatsType(providerType),
          sourcePath: `/api/cricket-series/series-stats/${id}/${providerType}`,
          rawKeys: [],
          reason: err.message,
        },
      };
    }
  });

  // GET /series/:id/schedule
  fastify.get('/series/:id/schedule', {
    schema: {
      description: 'Get app-ready series schedule',
      tags: ['Series'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request) => {
    const { id } = request.params;
    const result = await fetchSeriesMatches(id);
    const data = normalizeSeriesSchedule(id, result);
    return {
      success: true,
      ...data,
      data,
      message: data.matches.length === 0 ? 'No schedule available for this series' : null,
    };
  });

  // GET /series/:id/news
  fastify.get('/series/:id/news', {
    schema: {
      description: 'Get news stories for a series',
      tags: ['Series'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
      querystring: {
        type: 'object',
        properties: {
          cursor: { type: 'string', description: 'Pagination cursor (story ID)' },
          limit: { type: 'integer', minimum: 1, maximum: 50, default: 10 },
        },
      },
    },
  }, async (request, reply) => {
    const { id } = request.params;
    const { cursor, limit = 10 } = request.query;
    try {
      const { data } = await cacheGetOrFetch(
        KEYS.seriesNews(id, cursor),
        TTL.SERIES_NEWS,
        async () => (await providerManager.execute('getSeriesNews', id, cursor || undefined)).data
      );
      if (!data || !data.stories) {
        return { success: true, seriesId: id, data: { stories: [], nextCursor: null }, message: 'No news available for this series' };
      }
      const stories = data.stories.slice(0, limit);
      return { success: true, seriesId: id, data: { stories, nextCursor: data.nextCursor || null }, message: null };
    } catch {
      return { success: true, seriesId: id, data: { stories: [], nextCursor: null }, message: 'Series news not available' };
    }
  });

  // GET /series/:id/teams - Series teams list
  fastify.get('/series/:id/teams', {
    schema: {
      description: 'Get teams participating in a series',
      tags: ['Series'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request) => {
    const { id } = request.params;
    try {
      const cached = await cacheGet(KEYS.seriesTeams(id));
      if (cached) {
        return {
          success: true,
          seriesId: id,
          data: cached,
          updatedAt: new Date().toISOString(),
          fromCache: true,
        };
      }

      const result = await providerManager.execute('getSeriesTeams', id);
      const teamsData = result?.data || { teams: [] };

      if (teamsData && teamsData.teams && teamsData.teams.length > 0) {
        await cacheSet(KEYS.seriesTeams(id), teamsData, TTL.SERIES);
      }

      return {
        success: true,
        seriesId: id,
        data: teamsData,
        updatedAt: new Date().toISOString(),
        fromCache: false,
        message: (!teamsData.teams || teamsData.teams.length === 0) ? 'No teams data available for this series' : null,
      };
    } catch (err) {
      logger.warn({ msg: 'Failed to fetch series teams', seriesId: id, error: err.message });
      return {
        success: true,
        seriesId: id,
        data: { teams: [] },
        updatedAt: new Date().toISOString(),
        message: 'Series teams not available',
      };
    }
  });
}
