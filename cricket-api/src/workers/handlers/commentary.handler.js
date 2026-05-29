import providerManager from '../../providers/provider-manager.js';
import { cacheSet, cacheGet, KEYS, TTL, getRedis } from '../../lib/redis.js';
import logger from '../../lib/logger.js';

/**
 * Polls commentary for a live match.
 * Only broadcasts NEW commentary entries (delta).
 */
export async function handleCommentary(job) {
  const { matchId } = job.data;

  const { data: commentary, provider } = await providerManager.execute('getCommentary', matchId);
  if (!commentary || !Array.isArray(commentary)) return;

  const prevCommentary = await cacheGet(KEYS.matchCommentary(matchId)) || [];

  // Find new entries by comparing timestamps/IDs
  const prevIds = new Set(prevCommentary.map((c) => c.id));
  const newEntries = commentary.filter((c) => !prevIds.has(c.id));

  // Cache full commentary (keep latest 200 entries)
  const merged = [...commentary.slice(0, 200)];
  await cacheSet(KEYS.matchCommentary(matchId), merged, TTL.COMMENTARY);

  // Broadcast only new entries
  if (newEntries.length > 0) {
    const redis = getRedis();
    await redis.publish('ws:events', JSON.stringify({
      event: 'commentary_update',
      matchId,
      data: newEntries,
    }));
  }

  logger.debug({ msg: 'Commentary polled', matchId, total: commentary.length, new: newEntries.length, provider });
}
