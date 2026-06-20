import providerManager from '../../providers/provider-manager.js';
import { cacheSet, cacheSetSWR, cacheGet, KEYS, TTL, SWR_WINDOW, getRedis } from '../../lib/redis.js';
import { addLiveMatchJobs, removeLiveMatchJobs } from '../queues.js';
import { activeMatchesGauge } from '../../lib/metrics.js';
import logger from '../../lib/logger.js';

/**
 * Handles polling of match lists (live, upcoming, recent).
 * For live matches, also manages per-match polling job lifecycle.
 */
export async function handleMatchList(job) {
  const { type } = job.data;

  const { data: matches, provider } = await providerManager.execute(
    type === 'live' ? 'getLiveMatches' :
    type === 'upcoming' ? 'getUpcomingMatches' : 'getRecentMatches'
  );

  if (!matches) return;

  // The live list is read by the /matches/live route as an SWR envelope, so the
  // worker MUST write the same envelope (cacheSetSWR) — a plain cacheSet would be
  // treated as a hard miss by the SWR reader and the two would clobber each other.
  // upcoming/recent are NOT SWR routes, so they keep plain cacheSet.
  if (type === 'live') {
    await cacheSetSWR(KEYS.matchesList(type), matches, TTL.LIVE_LIST, SWR_WINDOW.LIVE_LIST);
  } else {
    const ttl = type === 'upcoming' ? TTL.UPCOMING : TTL.RECENT;
    await cacheSet(KEYS.matchesList(type), matches, ttl);
  }

  // For live matches: manage per-match polling
  if (type === 'live') {
    const redis = getRedis();
    const currentActive = await cacheGet(KEYS.activeMatches()) || [];
    const liveIds = new Set(matches.filter((m) => m.status === 'live' || m.status === 'innings_break').map((m) => m.match_id));

    activeMatchesGauge.set(liveIds.size);

    // Start polling for new live matches
    for (const match of matches) {
      if (match.status === 'live' || match.status === 'innings_break') {
        if (!currentActive.includes(match.match_id)) {
          logger.info({ msg: 'Starting per-match polling', matchId: match.match_id, status: match.status });
          await addLiveMatchJobs(match.match_id, match.status);

          // Publish match_started event
          await redis.publish('ws:events', JSON.stringify({
            event: 'match_started',
            matchId: match.match_id,
            data: match,
          }));
        }
      }
    }

    // Stop polling for completed matches
    for (const id of currentActive) {
      if (!liveIds.has(id)) {
        logger.info({ msg: 'Stopping per-match polling', matchId: id });
        await removeLiveMatchJobs(id);

        // Publish match_finished event
        const finishedMatch = matches.find((m) => m.match_id === id);
        await redis.publish('ws:events', JSON.stringify({
          event: 'match_finished',
          matchId: id,
          data: finishedMatch || { match_id: id, status: 'completed' },
        }));
      }
    }

    // Persist active match IDs
    await cacheSet(KEYS.activeMatches(), [...liveIds], 120);
  }

  logger.debug({ msg: 'Match list polled', type, count: matches.length, provider });
}
