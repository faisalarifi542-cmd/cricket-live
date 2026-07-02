/**
 * New-innings push notifier.
 * ----------------------------------------------------------------------------
 * Fires a single "New Innings Started" push when a match's innings advances,
 * but ONLY for matches that have a published/active live stream, and ONLY once
 * per innings (deduped in notification_log so polling + restarts never spam).
 *
 * Driven from the live-score worker (handleLiveScore), which already detects a
 * `current_innings` change between the previous and latest match detail. The
 * provider's `current_innings` is the real miniscore innings id, so an increase
 * is a genuine new innings.
 */
import { fetchActiveStreamsForMatch } from './public-app-state.js';
import { recordNotificationHistory, sendOneSignalNotification } from './onesignal.js';
import {
  NOTIFICATION_EVENTS,
  newInningsKey,
  claimNotificationEvent,
  markNotificationLog,
} from './notification-dedupe.js';
import logger from './logger.js';

const FINISHED = new Set(['completed', 'complete', 'finished', 'abandoned', 'no_result']);

function teamName(t) {
  return String(t?.name || t?.short_name || '').trim();
}

function battingTeamName(match, inningsNumber) {
  for (const t of [match?.team1, match?.team2]) {
    const inns = Array.isArray(t?.innings) ? t.innings : [];
    if (inns.some((i) => Number(i.innings_number) === Number(inningsNumber))) {
      return teamName(t);
    }
  }
  return '';
}

function matchup(match) {
  const a = teamName(match?.team1);
  const b = teamName(match?.team2);
  return a && b ? `${a} vs ${b}` : String(match?.match_desc || 'the match');
}

/**
 * @returns {Promise<{status:'sent'|'failed'|'skipped'|'already_sent', reason?:string}>}
 * Never throws — notification problems must not break score polling.
 */
export async function maybeNotifyNewInnings(match, prevMatch) {
  try {
    // Need a real previous snapshot so a cold cache / first poll / restart does
    // not misfire. (notification_log is the belt-and-braces against restarts.)
    if (!match || !prevMatch) return { status: 'skipped', reason: 'no_prev' };

    const matchId = String(match.match_id || prevMatch.match_id || '');
    if (!matchId) return { status: 'skipped', reason: 'no_id' };

    const prevInn = Number(prevMatch.current_innings || 0);
    const currInn = Number(match.current_innings || 0);
    if (!(currInn > prevInn && currInn >= 1)) return { status: 'skipped', reason: 'no_innings_change' };

    if (FINISHED.has(String(match.status || '').toLowerCase())) {
      return { status: 'skipped', reason: 'finished' };
    }

    // Only for matches that actually have a published/active live stream.
    const streams = await fetchActiveStreamsForMatch(matchId).catch(() => []);
    if (!streams.length) return { status: 'skipped', reason: 'no_stream' };

    const dedupeKey = newInningsKey(matchId, currInn);
    const team = battingTeamName(match, currInn);
    const title = 'New Innings Started';
    const body = team
      ? `${team} start their innings. Watch live now on CricPro.`
      : `A new innings has started in ${matchup(match)}. Watch live now on CricPro.`;

    // Targeted to the live_stream category tag so it respects the user's stream
    // notification preference (ON by default) — i.e. "new innings only for
    // streamed matches, on by default for those users".
    const notification = {
      title,
      body,
      target_type: 'category',
      target_value: 'live_stream',
      deep_link_type: 'live_stream',
      deep_link_value: matchId,
      payload: {
        type: 'live_stream',
        matchId,
        event: 'new_innings',
        innings: currInn,
        deepLink: `cricpro://match/${matchId}/live`,
      },
    };

    const claim = await claimNotificationEvent({
      matchId,
      eventType: NOTIFICATION_EVENTS.NEW_INNINGS,
      dedupeKey,
      title,
      body,
    });
    if (!claim.claimed) return { status: 'already_sent', reason: 'deduped' };

    try {
      const result = await sendOneSignalNotification(notification);
      await markNotificationLog(dedupeKey, { status: 'sent', providerResponse: result.response });
      await recordNotificationHistory({ notification, payload: result.payload, providerResponse: result.response, status: 'sent' });
      logger.info({ msg: 'new_innings notification sent', matchId, innings: currInn });
      return { status: 'sent' };
    } catch (err) {
      await markNotificationLog(dedupeKey, { status: 'failed', errorMessage: err.message, providerResponse: err.providerResponse || null });
      await recordNotificationHistory({ notification, status: 'failed', errorMessage: err.message, providerResponse: err.providerResponse || null });
      return { status: 'failed', reason: err.message };
    }
  } catch (err) {
    logger.debug(`maybeNotifyNewInnings error: ${err.message}`);
    return { status: 'skipped', reason: 'error' };
  }
}
