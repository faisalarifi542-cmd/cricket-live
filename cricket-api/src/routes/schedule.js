import { cacheGetOrFetch, KEYS, TTL } from '../lib/redis.js';
import providerManager from '../providers/provider-manager.js';
import { indexScheduleMatches } from '../lib/match-index.js';

const VALID_TYPES = ['all', 'international', 'league', 'domestic', 'women'];

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
