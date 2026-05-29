import { cacheGet, cacheSet } from '../lib/redis.js';
import { cacheHitsTotal, cacheMissesTotal } from '../lib/metrics.js';
import logger from '../lib/logger.js';

/**
 * Redis caching middleware factory for Fastify routes.
 *
 * Usage in route:
 *   { preHandler: cacheMiddleware('matches:live', 10) }
 *
 * @param {string|Function} keyOrFn - Cache key string or function(request) => key
 * @param {number} ttl - TTL in seconds
 */
export function cacheMiddleware(keyOrFn, ttl = 30) {
  return async function (request, reply) {
    const key = typeof keyOrFn === 'function' ? keyOrFn(request) : keyOrFn;

    try {
      const cached = await cacheGet(key);
      if (cached) {
        cacheHitsTotal.inc({ key_type: key.split(':')[0] });
        reply.header('X-Cache', 'HIT');
        reply.header('X-Cache-Key', key);
        return reply.send({ success: true, data: cached, cache: true });
      }
    } catch (err) {
      logger.warn({ msg: 'Cache read error', key, error: err.message });
    }

    cacheMissesTotal.inc({ key_type: key.split(':')[0] });
    reply.header('X-Cache', 'MISS');

    // Store ttl and key on request for post-handler caching
    request.cacheKey = key;
    request.cacheTTL = ttl;
  };
}

/**
 * onSend hook to cache successful responses.
 * Register globally or per-route.
 */
export async function cacheOnSend(request, reply, payload) {
  if (request.cacheKey && reply.statusCode === 200 && payload) {
    try {
      const parsed = typeof payload === 'string' ? JSON.parse(payload) : payload;
      if (parsed?.success && parsed?.data) {
        await cacheSet(request.cacheKey, parsed.data, request.cacheTTL);
      }
    } catch {
      // Ignore cache write failures
    }
  }
  return payload;
}
