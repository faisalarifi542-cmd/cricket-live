import providerManager from '../../providers/provider-manager.js';
import { cacheSet, cacheSetSWR, cacheGet, unwrapSWR, KEYS, TTL, SWR_WINDOW, getRedis } from '../../lib/redis.js';
import { maybeNotifyNewInnings } from '../../lib/innings-notifier.js';
import logger from '../../lib/logger.js';

/**
 * Polls live score for a specific match.
 * Compares with cached data and publishes diff via Redis pub/sub.
 */
export async function handleLiveScore(job) {
  const { matchId } = job.data;

  const { data: match, provider } = await providerManager.execute('getMatchInfo', matchId);
  if (!match) return;

  // Shared SWR key match:{id}:live — unwrap on read, write the SWR envelope on
  // write so the /match/:id + /live-center routes read it as a fresh envelope
  // (a plain write would look like a hard miss and break the SWR HIT path).
  const prevMatch = unwrapSWR(await cacheGet(KEYS.matchLive(matchId)));

  // Cache new data
  await cacheSetSWR(KEYS.matchLive(matchId), match, TTL.LIVE_SCORE, SWR_WINDOW.MATCH_DETAIL);
  await cacheSet(KEYS.matchInfo(matchId), match, TTL.MATCH_INFO);

  // Detect changes and broadcast
  const changes = detectChanges(prevMatch, match);
  if (changes.hasChanges) {
    const redis = getRedis();
    await redis.publish('ws:events', JSON.stringify({
      event: 'score_update',
      matchId,
      data: match,
      changes: changes.fields,
    }));

    // Check for innings change
    if (changes.fields.includes('current_innings')) {
      await redis.publish('ws:events', JSON.stringify({
        event: 'innings_update',
        matchId,
        data: match,
      }));

      // Fire a "new innings" push for streamed matches (deduped once per
      // innings). Never let a notification failure break score polling.
      await maybeNotifyNewInnings(match, prevMatch).catch((err) =>
        logger.debug({ msg: 'new_innings notify failed', matchId, error: err?.message }),
      );
    }
  }

  logger.debug({ msg: 'Live score polled', matchId, provider, changed: changes.hasChanges });
}

function detectChanges(prev, curr) {
  if (!prev) return { hasChanges: true, fields: ['initial'] };

  const fields = [];

  if (prev.status !== curr.status) fields.push('status');
  if (prev.status_text !== curr.status_text) fields.push('status_text');
  if (prev.current_innings !== curr.current_innings) fields.push('current_innings');

  // Compare scores
  if (JSON.stringify(prev.team1?.innings) !== JSON.stringify(curr.team1?.innings)) fields.push('team1_score');
  if (JSON.stringify(prev.team2?.innings) !== JSON.stringify(curr.team2?.innings)) fields.push('team2_score');

  // Compare result
  if (prev.result !== curr.result) fields.push('result');

  return { hasChanges: fields.length > 0, fields };
}
