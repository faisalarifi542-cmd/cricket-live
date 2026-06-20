import { Queue } from 'bullmq';
import { getRedis } from '../lib/redis.js';
import config from '../config/index.js';

const connection = { connection: getRedis() };

const defaultOpts = {
  ...connection,
  defaultJobOptions: {
    removeOnComplete: { count: 100 },
    removeOnFail: { count: 500 },
    attempts: 3,
    backoff: { type: 'exponential', delay: 2000 },
  },
};

export const liveScoreQueue = new Queue('live-score', defaultOpts);
export const commentaryQueue = new Queue('commentary', defaultOpts);
export const scorecardQueue = new Queue('scorecard', defaultOpts);
export const seriesQueue = new Queue('series', defaultOpts);
export const playerStatsQueue = new Queue('player-stats', defaultOpts);
export const matchListQueue = new Queue('match-list', defaultOpts);

/**
 * Schedule repeatable jobs for polling.
 * Called once at startup.
 */
export async function schedulePollingJobs() {
  // Poll live match list every 10 seconds
  await matchListQueue.upsertJobScheduler(
    'poll-live-matches',
    { every: 10_000 },
    { name: 'poll-live-matches', data: { type: 'live' } }
  );

  // Poll upcoming matches every 5 minutes
  await matchListQueue.upsertJobScheduler(
    'poll-upcoming-matches',
    { every: config.polling.upcomingInterval },
    { name: 'poll-upcoming-matches', data: { type: 'upcoming' } }
  );

  // Poll recent matches every 60 seconds
  await matchListQueue.upsertJobScheduler(
    'poll-recent-matches',
    { every: 60_000 },
    { name: 'poll-recent-matches', data: { type: 'recent' } }
  );

  // Poll series list every 5 minutes
  await seriesQueue.upsertJobScheduler(
    'poll-series-list',
    { every: 300_000 },
    { name: 'poll-series-list', data: {} }
  );
}

/**
 * Add per-match polling jobs for a live match.
 */
export async function addLiveMatchJobs(matchId, status) {
  const interval = status === 'innings_break'
    ? config.polling.inningsBreakInterval
    : config.polling.liveInterval;

  const jobId = `live-${matchId}`;
  const commId = `comm-${matchId}`;
  const scId = `sc-${matchId}`;

  // Deduplicate — only add if not already scheduled
  await liveScoreQueue.upsertJobScheduler(
    jobId,
    { every: interval },
    { name: 'poll-live-score', data: { matchId } }
  );

  await commentaryQueue.upsertJobScheduler(
    commId,
    { every: config.polling.commentaryInterval },
    { name: 'poll-commentary', data: { matchId } }
  );

  await scorecardQueue.upsertJobScheduler(
    scId,
    { every: config.polling.scorecardInterval },
    { name: 'poll-scorecard', data: { matchId } }
  );
}

/**
 * Remove per-match polling jobs when match completes.
 */
export async function removeLiveMatchJobs(matchId) {
  await liveScoreQueue.removeJobScheduler(`live-${matchId}`);
  await commentaryQueue.removeJobScheduler(`comm-${matchId}`);
  await scorecardQueue.removeJobScheduler(`sc-${matchId}`);
}
