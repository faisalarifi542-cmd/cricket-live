import providerManager from '../../providers/provider-manager.js';
import { cacheSet, KEYS, TTL } from '../../lib/redis.js';
import { query } from '../../lib/db.js';
import logger from '../../lib/logger.js';

/**
 * Fetches and caches player info + stats.
 * Triggered on-demand when a player is requested and cache is cold.
 */
export async function handlePlayerStats(job) {
  const { playerId } = job.data;
  if (!playerId) return;

  const { data: player, provider } = await providerManager.execute('getPlayerInfo', playerId);
  if (!player) return;

  await cacheSet(KEYS.player(playerId), player, TTL.PLAYER);

  // Persist to DB
  try {
    await query(
      `INSERT INTO players (external_id, name, full_name, dob, nationality, role, batting_style, bowling_style, image_url, stats)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         name = VALUES(name),
         full_name = VALUES(full_name),
         nationality = VALUES(nationality),
         role = VALUES(role),
         batting_style = VALUES(batting_style),
         bowling_style = VALUES(bowling_style),
         image_url = VALUES(image_url),
         stats = VALUES(stats)`,
      [
        player.player_id, player.name, player.full_name, player.dob || null,
        player.nationality, player.role, player.batting_style, player.bowling_style,
        player.image_url, JSON.stringify(player.stats),
      ]
    );
  } catch (err) {
    logger.warn({ msg: 'Player DB upsert failed', playerId, error: err.message });
  }

  logger.debug({ msg: 'Player stats fetched', playerId, provider });
}
