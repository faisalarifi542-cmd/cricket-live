import providerManager from '../../providers/provider-manager.js';
import { cacheSetSWR, cacheGet, KEYS, TTL, SWR_WINDOW, getRedis } from '../../lib/redis.js';
import { query } from '../../lib/db.js';
import logger from '../../lib/logger.js';

/**
 * Polls scorecard for a live match.
 * Updates Redis cache and persists batting/bowling data to PostgreSQL.
 */
export async function handleScorecard(job) {
  const { matchId } = job.data;

  const { data: scorecard, provider } = await providerManager.execute('getScorecard', matchId);
  if (!scorecard || !scorecard.innings) return;

  // Cache in Redis as an SWR envelope so the /scorecard route (which reads SWR
  // envelopes) does not treat a worker write as a hard miss. Same physical TTL
  // (ttl + staleWindow = 8s); TTL.SCORECARD itself is unchanged.
  await cacheSetSWR(KEYS.matchScorecard(matchId), scorecard, TTL.SCORECARD, SWR_WINDOW.SCORECARD);

  // Persist to MySQL (upsert innings + batting/bowling scores)
  for (const inn of scorecard.innings) {
    try {
      // Upsert innings record
      await query(
        `INSERT INTO innings (match_id, innings_number, total_runs, total_wickets, total_overs, run_rate, extras, fow)
         VALUES ((SELECT id FROM matches WHERE external_id = ?), ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           total_runs = VALUES(total_runs),
           total_wickets = VALUES(total_wickets),
           total_overs = VALUES(total_overs),
           run_rate = VALUES(run_rate),
           extras = VALUES(extras),
           fow = VALUES(fow)`,
        [
          matchId,
          inn.innings_number,
          inn.total.runs,
          inn.total.wickets,
          inn.total.overs,
          inn.run_rate || 0,
          JSON.stringify(inn.extras),
          JSON.stringify(inn.fall_of_wickets),
        ]
      );

      // Get the innings ID
      const innRows = await query(
        'SELECT i.id FROM innings i JOIN matches m ON i.match_id = m.id WHERE m.external_id = ? AND i.innings_number = ?',
        [matchId, inn.innings_number]
      );
      const inningsId = innRows[0]?.id;
      if (!inningsId) continue;

      // Insert batting scores (ignore duplicates)
      for (const bat of inn.batting || []) {
        await query(
          `INSERT IGNORE INTO batting_scores (innings_id, player_name, runs, balls, fours, sixes, strike_rate, dismissal_text, is_batting, is_striker, batting_pos)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            inningsId, bat.name, bat.runs, bat.balls, bat.fours, bat.sixes,
            bat.strike_rate, bat.dismissal, bat.is_batting ? 1 : 0, bat.is_striker ? 1 : 0, bat.position,
          ]
        );
      }

      // Insert bowling scores (ignore duplicates)
      for (const bowl of inn.bowling || []) {
        await query(
          `INSERT IGNORE INTO bowling_scores (innings_id, player_name, overs, maidens, runs_conceded, wickets, economy, dots, wides, no_balls, is_bowling)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [
            inningsId, bowl.name, bowl.overs, bowl.maidens, bowl.runs, bowl.wickets,
            bowl.economy, bowl.dots, bowl.wides, bowl.no_balls, bowl.is_bowling ? 1 : 0,
          ]
        );
      }
    } catch (err) {
      logger.error({ msg: 'Scorecard DB persist failed', matchId, innings: inn.innings_number, error: err.message });
    }
  }

  logger.debug({ msg: 'Scorecard polled', matchId, innings: scorecard.innings.length, provider });
}
