/**
 * Notification de-duplication log.
 * ----------------------------------------------------------------------------
 * A single, idempotent gate that guarantees an automated notification (stream
 * published, new innings, etc.) is sent at most ONCE per logical event, even
 * across:
 *   - repeated admin saves of the same published stream,
 *   - duplicate poll ticks from the innings watcher,
 *   - backend restarts (the claim is persisted in MySQL, not in memory).
 *
 * The dedupe is enforced by a UNIQUE index on `dedupe_key` in `notification_log`
 * (created in db/migrate.js). `claimNotificationEvent` performs an
 * INSERT IGNORE and reports whether THIS caller won the race (affectedRows === 1).
 * Only the winner should actually dispatch the push; everyone else treats the
 * event as "already sent / skipped".
 *
 * dedupe_key conventions (keep stable — changing them re-opens old events):
 *   stream_published:<streamId>            one publish push per stream record
 *   new_innings:<matchId>:<inningsNumber>  one push per innings of a match
 */
import { query } from './db.js';

export const NOTIFICATION_EVENTS = {
  STREAM_PUBLISHED: 'stream_published',
  NEW_INNINGS: 'new_innings',
};

export function streamPublishedKey(streamId) {
  return `${NOTIFICATION_EVENTS.STREAM_PUBLISHED}:${streamId}`;
}

export function newInningsKey(matchId, inningsNumber) {
  return `${NOTIFICATION_EVENTS.NEW_INNINGS}:${matchId}:${inningsNumber}`;
}

/**
 * Atomically claim a notification event. Returns `{ claimed }`:
 *   claimed === true  -> this caller inserted the row first; it MUST send.
 *   claimed === false -> the event was already claimed/sent; caller skips.
 *
 * Never throws — a DB error degrades to `claimed: false` so a logging failure
 * can never cause a duplicate blast (fail-closed for the user's inbox).
 */
export async function claimNotificationEvent({
  matchId,
  eventType,
  dedupeKey,
  streamId = null,
  title = null,
  body = null,
}) {
  const key = dedupeKey || `${eventType}:${matchId}`;
  try {
    const res = await query(
      `INSERT IGNORE INTO notification_log
         (match_external_id, event_type, dedupe_key, stream_id, status, title, body)
       VALUES (?, ?, ?, ?, 'pending', ?, ?)`,
      [String(matchId || ''), eventType, key, streamId, title, body],
    );
    return { claimed: Number(res?.affectedRows || 0) === 1, dedupeKey: key };
  } catch {
    return { claimed: false, dedupeKey: key };
  }
}

/** Update a previously-claimed log row with the dispatch outcome. */
export async function markNotificationLog(dedupeKey, { status, providerResponse = null, errorMessage = null }) {
  await query(
    `UPDATE notification_log
        SET status = ?, provider_response = ?, error_message = ?, sent_at = CASE WHEN ? = 'sent' THEN NOW() ELSE sent_at END
      WHERE dedupe_key = ?`,
    [
      status,
      providerResponse ? JSON.stringify(providerResponse) : null,
      errorMessage,
      status,
      dedupeKey,
    ],
  ).catch(() => null);
}

/** True if a notification for this dedupe key has already been recorded as sent. */
export async function wasNotificationSent(dedupeKey) {
  const rows = await query(
    `SELECT status FROM notification_log WHERE dedupe_key = ? LIMIT 1`,
    [dedupeKey],
  ).catch(() => []);
  return rows.length > 0 && rows[0].status === 'sent';
}

/** Look up the most recent log status for a stream's publish event (admin UI). */
export async function getStreamNotificationStatus(streamId) {
  const rows = await query(
    `SELECT status, error_message, created_at, sent_at
       FROM notification_log
      WHERE dedupe_key = ? LIMIT 1`,
    [streamPublishedKey(streamId)],
  ).catch(() => []);
  return rows[0] || null;
}
