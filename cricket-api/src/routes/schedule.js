import { cacheGetOrFetch, KEYS, TTL } from '../lib/redis.js';
import providerManager from '../providers/provider-manager.js';
import { indexScheduleMatches } from '../lib/match-index.js';
import logger from '../lib/logger.js';

const VALID_TYPES = ['all', 'international', 'league', 'domestic', 'women'];

/**
 * Emits structured `[Schedule]` diagnostics so we can see exactly what the
 * provider returned per request — day count, total match count, and the
 * distinct series names — without dumping the whole payload. This is the
 * signal used to tell "provider genuinely returned one match" apart from
 * "we dropped/filtered matches" (e.g. the missing IRE vs IND report).
 */
function logScheduleResult(type, timestamp, data) {
  try {
    const days = Array.isArray(data?.days) ? data.days : [];
    let matchCount = 0;
    const seriesNames = new Set();
    for (const day of days) {
      for (const series of day.series || []) {
        if (series.seriesName) seriesNames.add(series.seriesName);
        matchCount += (series.matches || []).length;
      }
    }
    logger.info({
      msg: '[Schedule] provider result',
      type,
      timestamp: timestamp || null,
      source: 'cricbuzz',
      days: days.length,
      matches: matchCount,
      series: [...seriesNames],
    });
  } catch (err) {
    logger.debug({ msg: '[Schedule] log failed', error: err.message });
  }
}

/**
 * Schedule routes — /schedule/*
 */
export default async function scheduleRoutes(fastify) {
  // GET /schedule/upcoming
  fastify.get('/schedule/upcoming', {
    schema: {
      description: 'Get upcoming match schedule (all types)',
      tags: ['Schedule'],
      querystring: {
        type: 'object',
        properties: {
          timestamp: { type: 'string', description: 'Timestamp for pagination' },
        },
      },
    },
  }, async (request) => {
    const { timestamp } = request.query;
    try {
      const { data } = await cacheGetOrFetch(
        KEYS.schedule('all', timestamp),
        TTL.SCHEDULE,
        async () => (await providerManager.execute('getUpcomingSchedule', 'all', timestamp || undefined)).data
      );
      if (data?.days?.length) indexScheduleMatches(data).catch(() => {});
      logScheduleResult('all', timestamp, data);
      return {
        success: true,
        type: 'all',
        timestamp: timestamp || null,
        data: data || { days: [] },
        message: (!data || !data.days?.length) ? 'No schedule data available' : null,
      };
    } catch {
      return { success: true, type: 'all', timestamp: timestamp || null, data: { days: [] }, message: 'Schedule not available' };
    }
  });

  // GET /schedule/upcoming/:type
  fastify.get('/schedule/upcoming/:type', {
    schema: {
      description: 'Get upcoming match schedule by type (international, league, domestic, women, all)',
      tags: ['Schedule'],
      params: {
        type: 'object',
        properties: { type: { type: 'string', enum: VALID_TYPES } },
        required: ['type'],
      },
      querystring: {
        type: 'object',
        properties: {
          timestamp: { type: 'string', description: 'Timestamp for pagination' },
        },
      },
    },
  }, async (request) => {
    const { type } = request.params;
    const { timestamp } = request.query;

    if (!VALID_TYPES.includes(type)) {
      return {
        success: false,
        error: { code: 'INVALID_TYPE', message: `Invalid schedule type. Valid: ${VALID_TYPES.join(', ')}` },
      };
    }

    try {
      const { data } = await cacheGetOrFetch(
        KEYS.schedule(type, timestamp),
        TTL.SCHEDULE,
        async () => (await providerManager.execute('getUpcomingSchedule', type, timestamp || undefined)).data
      );
      if (data?.days?.length) indexScheduleMatches(data).catch(() => {});
      logScheduleResult(type, timestamp, data);
      return {
        success: true,
        type,
        timestamp: timestamp || null,
        data: data || { days: [] },
        message: (!data || !data.days?.length) ? 'No schedule data available for this type' : null,
      };
    } catch {
      return { success: true, type, timestamp: timestamp || null, data: { days: [] }, message: 'Schedule not available' };
    }
  });
}
