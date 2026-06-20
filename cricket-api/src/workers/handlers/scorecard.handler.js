import providerManager from '../../providers/provider-manager.js';
import { cacheSetSWR, cacheGet, cacheSet, cacheDel, KEYS, TTL, SWR_WINDOW, getRedis } from '../../lib/redis.js';
import { query } from '../../lib/db.js';
import logger from '../../lib/logger.js';

// --- Rate-limited error logging -------------------------------------------
// The scorecard persist error used to log on every failed write (every poll
// tick, for every innings) which flooded the logs. Rate-limit to at most once
// per RATE_LIMIT_MS per (matchId + innings + error). This still surfaces an
// ongoing failure repeatedly (just not on every tick) — it is NOT a log-once.
const RATE_LIMIT_MS = 5 * 60 * 1000; // 5 minutes
const lastLoggedAt = new Map();

function logThrottled(key, level, payload) {
  const now = Date.now();
  const prev = lastLoggedAt.get(key);
  if (prev && now - prev < RATE_LIMIT_MS) return;
  lastLoggedAt.set(key, now);
  // Opportunistic cleanup so the map cannot grow unbounded across many matches.
  if (lastLoggedAt.size > 500) {
    for (const [k, ts] of lastLoggedAt) {
      if (now - ts > RATE_LIMIT_MS) lastLoggedAt.delete(k);
    }
  }
  logger[level](payload);
}

function logPersistFailureThrottled(matchId, innings, err) {
  const key = `${matchId}:${innings}:${err.code || err.message}`;
  logThrottled(key, 'error', { msg: 'Scorecard DB persist failed', matchId, innings, error: err.message, code: err.code });
}

// --- Scorecard fetch backoff ----------------------------------------------
// The scorecard job is a repeatable scheduler firing every POLL_SCORECARD_INTERVAL
// (~10s). For a match whose scorecard is unavailable (Cricbuzz 404, empty
// JSON/HTML innings, "fetch completely failed after all strategies"), the handler
// would call the provider on EVERY tick forever — the cricbuzz client then runs
// its full JSON -> HTML (3 slug) strategy chain, flooding logs and pinning CPU.
//
// Fix: track consecutive failures per match in Redis and skip the provider call
// entirely while a match is in backoff. State is keyed off matchId only and never
// touches the scorecard cache key, so existing Redis scorecard data and the public
// /match/:id/scorecard route are unaffected. On the first successful fetch the
// backoff state is cleared, so a match that becomes valid recovers immediately.
const BACKOFF_KEY = (matchId) => `worker:scorecard:backoff:${matchId}`;

// After this many consecutive empty/failed fetches, start skipping ticks.
const BACKOFF_AFTER_FAILURES = 2;
// Backoff window for a live/unknown match that is briefly missing a scorecard.
const BACKOFF_LIVE_MS = 5 * 60 * 1000;   // 5 minutes
// Longer backoff once a match looks completed/finished and still has no scorecard.
const BACKOFF_DONE_MS = 30 * 60 * 1000;  // 30 minutes
// Hard cap on the backoff state TTL so the key self-expires if a match is dropped.
const BACKOFF_STATE_TTL_SEC = 6 * 60 * 60; // 6 hours

/**
 * Returns true if the match is currently in a fetch-backoff window and the
 * provider call should be skipped this tick.
 */
async function isInBackoff(matchId) {
  const state = await cacheGet(BACKOFF_KEY(matchId));
  if (!state || !state.until) return false;
  return Date.now() < state.until;
}

/**
 * Record a failed/empty scorecard fetch and (re)arm the backoff window.
 * Backoff only kicks in after BACKOFF_AFTER_FAILURES consecutive failures so a
 * single transient blip does not stall a healthy live match.
 */
async function recordFetchFailure(matchId, reason) {
  let state = null;
  try {
    state = await cacheGet(BACKOFF_KEY(matchId));
  } catch { /* treat as no prior state */ }

  const failures = (state?.failures || 0) + 1;
  const now = Date.now();

  // Use the longer window once the match looks finished and still has nothing.
  const completed = await matchLooksCompleted(matchId);
  const windowMs = completed ? BACKOFF_DONE_MS : BACKOFF_LIVE_MS;

  const until = failures >= BACKOFF_AFTER_FAILURES ? now + windowMs : 0;

  await cacheSet(
    BACKOFF_KEY(matchId),
    { failures, until, reason, completed, updated: now },
    BACKOFF_STATE_TTL_SEC
  );

  // Log at most once per RATE_LIMIT_MS per (match + reason) so an ongoing
  // failure is still surfaced periodically without spamming every tick.
  logThrottled(`backoff:${matchId}:${reason}`, 'warn', {
    msg: 'Scorecard fetch backing off',
    matchId,
    reason,
    failures,
    completed,
    backoffMs: until ? windowMs : 0,
  });
}

/** Clear backoff state after a successful fetch so polling resumes normally. */
async function clearFetchFailure(matchId) {
  try {
    await cacheDel(BACKOFF_KEY(matchId));
  } catch { /* best effort */ }
}

/**
 * Best-effort check of whether the match is completed/finished, read from the
 * live cache the live-score worker already maintains. Never throws and never
 * triggers a provider call — a missing/unknown status is treated as not-completed
 * (shorter backoff), which is the safe default for a possibly-live match.
 */
async function matchLooksCompleted(matchId) {
  try {
    const cached = await cacheGet(KEYS.matchLive(matchId));
    const match = cached?.data ?? cached; // tolerate SWR envelope or plain value
    const status = String(match?.status || '').toLowerCase();
    return status === 'completed' || status === 'finished';
  } catch {
    return false;
  }
}

/**
 * Resolves the internal matches.id (PK) for a provider external match id,
 * creating a minimal stub row if the match has not been ingested yet.
 *
 * Root cause of the historic "Column 'match_id' cannot be null" errors: the
 * innings insert resolved its match_id with `(SELECT id FROM matches WHERE
 * external_id = ?)`, but nothing populates `matches`, so the subquery returned
 * NULL and the NOT NULL `innings.match_id` write failed. We now ensure a row
 * exists first and pass the resolved integer id explicitly.
 *
 * INSERT IGNORE never modifies an existing match row (no schema/constraint
 * change); `match_format` is NOT NULL with no default, so the stub uses a
 * placeholder that real match-detail ingestion can later overwrite.
 */
async function resolveInternalMatchId(matchId) {
  await query(
    `INSERT IGNORE INTO matches (external_id, match_format, status)
     VALUES (?, 'unknown', 'live')`,
    [String(matchId)]
  );
  const rows = await query('SELECT id FROM matches WHERE external_id = ?', [String(matchId)]);
  return rows[0]?.id ?? null;
}

/**
 * Polls scorecard for a live match.
 * Updates Redis cache and persists batting/bowling data to MySQL.
 */
export async function handleScorecard(job) {
  const { matchId } = job.data;

  // Skip the provider call entirely while this match is in a fetch-backoff
  // window. This is the actual CPU/log-spam fix: an unavailable scorecard no
  // longer drives the full JSON->HTML strategy chain every ~10s tick.
  if (await isInBackoff(matchId)) {
    logger.debug({ msg: 'Scorecard fetch skipped (backoff)', matchId });
    return;
  }

  const result = await providerManager.execute('getScorecard', matchId)
    .catch((err) => {
      // All providers threw (network/5xx). Surface periodically, then fall
      // through to the empty-innings guard which records the failure + backoff.
      logThrottled(`provider-throw:${matchId}`, 'warn', { msg: 'Scorecard providers all failed', matchId, error: err.message });
      return { data: { innings: [], _error: err.message }, provider: null };
    });
  const { data: scorecard, provider } = result;

  // An empty/failed scorecard normalizes to { innings: [] } (NOT null), so a
  // truthiness check on scorecard.innings is not enough — guard on length. We
  // must NOT cacheSetSWR an empty scorecard here: that would overwrite valid
  // cached data with nothing. Instead record a failure and arm/extend backoff.
  if (!scorecard || !Array.isArray(scorecard.innings) || scorecard.innings.length === 0) {
    await recordFetchFailure(matchId, scorecard?._error ? 'fetch-failed' : 'empty-innings');
    return;
  }

  // Successful fetch — clear any backoff so polling continues at normal cadence.
  await clearFetchFailure(matchId);

  // Cache in Redis as an SWR envelope so the /scorecard route (which reads SWR
  // envelopes) does not treat a worker write as a hard miss. Same physical TTL
  // (ttl + staleWindow = 8s); TTL.SCORECARD itself is unchanged.
  await cacheSetSWR(KEYS.matchScorecard(matchId), scorecard, TTL.SCORECARD, SWR_WINDOW.SCORECARD);

  // Resolve (and lazily create) the internal matches.id once per poll. Without
  // a row in `matches`, the innings.match_id write would be NULL and fail.
  let internalMatchId;
  try {
    internalMatchId = await resolveInternalMatchId(matchId);
  } catch (err) {
    logPersistFailureThrottled(matchId, 'all', err);
    return;
  }
  if (!internalMatchId) {
    logPersistFailureThrottled(matchId, 'all', new Error('Could not resolve internal match_id'));
    return;
  }

  // Persist to MySQL (upsert innings + batting/bowling scores)
  for (const inn of scorecard.innings) {
    try {
      // Upsert innings record
      await query(
        `INSERT INTO innings (match_id, innings_number, total_runs, total_wickets, total_overs, run_rate, extras, fow)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           total_runs = VALUES(total_runs),
           total_wickets = VALUES(total_wickets),
           total_overs = VALUES(total_overs),
           run_rate = VALUES(run_rate),
           extras = VALUES(extras),
           fow = VALUES(fow)`,
        [
          internalMatchId,
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
        'SELECT id FROM innings WHERE match_id = ? AND innings_number = ?',
        [internalMatchId, inn.innings_number]
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
      logPersistFailureThrottled(matchId, inn.innings_number, err);
    }
  }

  logger.debug({ msg: 'Scorecard polled', matchId, innings: scorecard.innings.length, provider });
}
