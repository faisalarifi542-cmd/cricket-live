import providerManager from '../../providers/provider-manager.js';
import { cacheSet, KEYS, TTL } from '../../lib/redis.js';
import { query } from '../../lib/db.js';
import logger from '../../lib/logger.js';

/**
 * Polls series list and persists to cache + DB.
 */
export async function handleSeriesList(job) {
  const { data: seriesList, provider } = await providerManager.execute('getSeriesList');
  if (!seriesList) return;

  await cacheSet(KEYS.seriesList(), seriesList, TTL.SERIES);

  // Persist to DB
  for (const s of seriesList) {
    try {
      await query(
        `INSERT INTO series (external_id, name, season, start_date, end_date)
         VALUES (?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           name = VALUES(name),
           season = VALUES(season),
           start_date = VALUES(start_date),
           end_date = VALUES(end_date)`,
        [s.series_id, s.name, s.season, s.start_date, s.end_date]
      );
    } catch (err) {
      logger.warn({ msg: 'Series DB upsert failed', seriesId: s.series_id, error: err.message });
    }
  }

  logger.debug({ msg: 'Series list polled', count: seriesList.length, provider });
}

/**
 * Polls points table for a specific series.
 */
export async function handlePointsTable(job) {
  const { seriesId } = job.data;
  if (!seriesId) return;

  const { data: table, provider } = await providerManager.execute('getPointsTable', seriesId);
  if (!table) return;

  await cacheSet(KEYS.pointsTable(seriesId), table, TTL.POINTS_TABLE);

  logger.debug({ msg: 'Points table polled', seriesId, entries: table.length, provider });
}
