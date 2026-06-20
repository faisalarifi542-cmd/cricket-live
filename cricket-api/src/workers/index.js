import { Worker, QueueEvents } from 'bullmq';
import { getRedis } from '../lib/redis.js';
import { schedulePollingJobs } from './queues.js';
import { handleMatchList } from './handlers/match-list.handler.js';
import { handleLiveScore } from './handlers/live-score.handler.js';
import { handleCommentary } from './handlers/commentary.handler.js';
import { handleScorecard } from './handlers/scorecard.handler.js';
import { handleSeriesList, handlePointsTable } from './handlers/series.handler.js';
import { handlePlayerStats } from './handlers/player-stats.handler.js';
import { handleProviderHealth } from './handlers/provider-health.handler.js';
import { handleCacheCleaner } from './handlers/cache-cleaner.handler.js';
import { workerJobDuration } from '../lib/metrics.js';
import config from '../config/index.js';
import logger from '../lib/logger.js';

const connection = getRedis();

const workerOpts = {
  connection,
  concurrency: config.workers.concurrency,
  limiter: config.workers.limiter,
  removeOnComplete: { count: 50 },
  removeOnFail: { count: 200 },
};

function createWorker(name, handler) {
  const worker = new Worker(
    name,
    async (job) => {
      const end = workerJobDuration.startTimer({ worker: name });
      try {
        await handler(job);
        end({ status: 'success' });
      } catch (err) {
        end({ status: 'error' });
        logger.error({ msg: `Worker ${name} job failed`, jobId: job.id, error: err.message, stack: err.stack });
        throw err; // re-throw for BullMQ retry
      }
    },
    workerOpts
  );

  worker.on('failed', (job, err) => {
    logger.error({ msg: `Job failed`, worker: name, jobId: job?.id, attempt: job?.attemptsMade, error: err.message });
  });

  worker.on('stalled', (jobId) => {
    logger.warn({ msg: `Job stalled`, worker: name, jobId });
  });

  return worker;
}

// ====================================================
// Create all workers
// ====================================================
const workers = [
  createWorker('match-list', handleMatchList),
  createWorker('live-score', handleLiveScore),
  createWorker('commentary', handleCommentary),
  createWorker('scorecard', handleScorecard),
  createWorker('series', handleSeriesList),
  createWorker('player-stats', handlePlayerStats),
];

// ====================================================
// Maintenance workers (lower concurrency)
// ====================================================
const maintenanceWorker = new Worker(
  'maintenance',
  async (job) => {
    switch (job.name) {
      case 'provider-health':
        await handleProviderHealth(job);
        break;
      case 'cache-cleaner':
        await handleCacheCleaner(job);
        break;
      case 'points-table':
        await handlePointsTable(job);
        break;
      default:
        logger.warn({ msg: 'Unknown maintenance job', name: job.name });
    }
  },
  { ...workerOpts, concurrency: 2 }
);
workers.push(maintenanceWorker);

// ====================================================
// Schedule repeatable jobs
// ====================================================
async function start() {
  logger.info('Starting worker system...');

  await schedulePollingJobs();

  // Schedule maintenance jobs
  const { Queue } = await import('bullmq');
  const maintenanceQueue = new Queue('maintenance', { connection });

  await maintenanceQueue.upsertJobScheduler(
    'provider-health-check',
    { every: 30_000 },
    { name: 'provider-health', data: {} }
  );

  await maintenanceQueue.upsertJobScheduler(
    'cache-cleanup',
    { every: 300_000 },
    { name: 'cache-cleaner', data: {} }
  );

  logger.info(`Worker system started — ${workers.length} workers active`);
}

// ====================================================
// Graceful shutdown
// ====================================================
async function shutdown(signal) {
  logger.info({ msg: 'Shutting down workers', signal });

  await Promise.allSettled(workers.map((w) => w.close()));

  logger.info('All workers closed');
  process.exit(0);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

start().catch((err) => {
  logger.error({ msg: 'Worker system startup failed', error: err.message });
  process.exit(1);
});
