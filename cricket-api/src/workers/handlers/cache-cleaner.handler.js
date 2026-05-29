import { getRedis, KEYS, cacheGet } from '../../lib/redis.js';
import logger from '../../lib/logger.js';

/**
 * Periodically cleans stale cache entries.
 * - Removes per-match keys for completed matches
 * - Prunes old commentary entries
 * - Cleans orphaned WebSocket room data
 */
export async function handleCacheCleaner(job) {
  const redis = getRedis();
  let cleaned = 0;

  // Get list of active matches
  const activeMatches = await cacheGet(KEYS.activeMatches()) || [];
  const activeSet = new Set(activeMatches);

  // Scan for match:*:live keys that are no longer active
  let cursor = '0';
  do {
    const [nextCursor, keys] = await redis.scan(cursor, 'MATCH', 'match:*:live', 'COUNT', 100);
    cursor = nextCursor;

    for (const key of keys) {
      const matchId = key.split(':')[1];
      if (!activeSet.has(matchId)) {
        // Check if match data is stale (no TTL means it was set without expiry)
        const ttl = await redis.ttl(key);
        if (ttl === -1) {
          // No TTL set — mark with short TTL for cleanup
          await redis.expire(key, 300); // expire in 5 min
          cleaned++;
        }
      }
    }
  } while (cursor !== '0');

  // Clean stale commentary keys (completed matches with large commentary)
  cursor = '0';
  do {
    const [nextCursor, keys] = await redis.scan(cursor, 'MATCH', 'match:*:commentary', 'COUNT', 100);
    cursor = nextCursor;

    for (const key of keys) {
      const matchId = key.split(':')[1];
      if (!activeSet.has(matchId)) {
        const ttl = await redis.ttl(key);
        if (ttl === -1) {
          await redis.expire(key, 600);
          cleaned++;
        }
      }
    }
  } while (cursor !== '0');

  if (cleaned > 0) {
    logger.info({ msg: 'Cache cleanup completed', keysMarkedForExpiry: cleaned });
  }

  logger.debug({ msg: 'Cache cleaner ran', activeMatches: activeSet.size, cleaned });
}
