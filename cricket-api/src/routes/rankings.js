import providerManager from '../providers/provider-manager.js';
import { cacheGet, cacheSet, TTL } from '../lib/redis.js';
import logger from '../lib/logger.js';

export default async function rankingsRoutes(fastify) {
  fastify.get('/rankings', {
    schema: {
      description: 'Get ICC rankings by gender, category, and format',
      tags: ['Series'],
      querystring: {
        type: 'object',
        properties: {
          gender: { type: 'string', enum: ['men', 'women'], default: 'men' },
          category: {
            type: 'string',
            enum: ['batting', 'bowling', 'allrounder', 'all-rounder', 'teams'],
            default: 'batting',
          },
          format: { type: 'string', enum: ['test', 'odi', 't20'], default: 'test' },
        },
      },
    },
  }, async (request) => {
    const gender = String(request.query.gender || 'men').toLowerCase() === 'women' ? 'women' : 'men';
    const category = String(request.query.category || 'batting').toLowerCase();
    const format = String(request.query.format || 'test').toLowerCase();
    const key = `rankings:${gender}:${category}:${format}`;

    try {
      const cached = await cacheGet(key);
      if (cached) {
        return { success: true, ...cached, fromCache: true };
      }

      const result = await providerManager.execute('getRankings', { gender, category, format });
      const data = result?.data || {};
      const rows = Array.isArray(data.rows) ? data.rows : [];
      const response = {
        gender: data.gender || gender,
        category: data.category || category,
        format: data.format || format,
        availableFormats: data.availableFormats || [],
        data: rows,
        count: rows.length,
        source: data.source || 'cricbuzz',
        updatedAt: data.updatedAt || new Date().toISOString(),
      };
      if (rows.length > 0) {
        await cacheSet(key, response, TTL.SERIES);
      }
      return { success: true, ...response, fromCache: false };
    } catch (err) {
      logger.warn({ msg: 'Failed to fetch rankings', gender, category, format, error: err.message });
      return {
        success: true,
        gender,
        category,
        format,
        data: [],
        count: 0,
        source: 'cricbuzz',
        message: 'Rankings are not available for this selection yet.',
      };
    }
  });
}
