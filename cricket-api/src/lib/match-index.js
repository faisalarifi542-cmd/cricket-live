import { cacheGet, cacheSet, KEYS, TTL } from './redis.js';
import logger from './logger.js';

/**
 * Index match summaries from various API list responses into Redis.
 * This allows /match/:id to look up basic match info even when the
 * Cricbuzz livescore endpoint fails (e.g. upcoming matches).
 */

/**
 * Index matches from /matches/live, /matches/upcoming, /matches/recent response arrays.
 * Each match object has: match_id, series_id, series_name, match_format, match_desc,
 * status, status_text, team1, team2, venue, start_time, etc.
 */
export async function indexMatchListItems(matches) {
  if (!Array.isArray(matches) || matches.length === 0) return;
  for (const m of matches) {
    const id = m.match_id;
    if (!id) continue;
    try {
      const summary = {
        match_id: id,
        series_id: m.series_id || '',
        series_name: m.series_name || '',
        match_desc: m.match_desc || '',
        match_format: m.match_format || '',
        match_type: m.match_type || '',
        status: m.status || 'upcoming',
        status_text: m.status_text || '',
        short_status: m.short_status || '',
        team1: m.team1 || { id: '', name: '', short_name: '' },
        team2: m.team2 || { id: '', name: '', short_name: '' },
        venue: m.venue || { name: '', city: '', country: '' },
        start_time: m.start_time || null,
        end_time: m.end_time || null,
        score: m.score || null,
        source: 'match_list',
      };
      await cacheSet(KEYS.matchSummary(id), summary, TTL.MATCH_SUMMARY);
    } catch (e) {
      logger.debug({ msg: 'Failed to index match summary', matchId: id, error: e.message });
    }
  }
}

/**
 * Index matches from schedule API response.
 * Schedule data: { days: [{ date, series: [{ seriesId, seriesName, matches: [...] }] }] }
 */
export async function indexScheduleMatches(scheduleData) {
  if (!scheduleData?.days) return;
  for (const day of scheduleData.days) {
    for (const series of (day.series || [])) {
      for (const m of (series.matches || [])) {
        const id = m.matchId;
        if (!id) continue;
        try {
          const startMs = parseInt(m.startTime, 10);
          const endMs = parseInt(m.endTime, 10);
          const summary = {
            match_id: id,
            series_id: m.seriesId || series.seriesId || '',
            series_name: series.seriesName || '',
            match_desc: m.matchDesc || '',
            match_format: m.matchFormat || '',
            match_type: m.matchFormat || '',
            status: 'upcoming',
            status_text: `${m.matchDesc || ''} - ${series.seriesName || ''}`.trim(),
            team1: m.team1 ? {
              id: m.team1.id || '',
              name: m.team1.name || '',
              short_name: m.team1.shortName || '',
              image_id: m.team1.imageId || null,
              logo_url: m.team1.logoUrl || null,
            } : { id: '', name: '', short_name: '' },
            team2: m.team2 ? {
              id: m.team2.id || '',
              name: m.team2.name || '',
              short_name: m.team2.shortName || '',
              image_id: m.team2.imageId || null,
              logo_url: m.team2.logoUrl || null,
            } : { id: '', name: '', short_name: '' },
            venue: m.venue || { name: '', city: '', country: '' },
            start_time: startMs ? new Date(startMs).toISOString() : null,
            end_time: endMs ? new Date(endMs).toISOString() : null,
            source: 'schedule',
          };
          await cacheSet(KEYS.matchSummary(id), summary, TTL.MATCH_SUMMARY);
        } catch (e) {
          logger.debug({ msg: 'Failed to index schedule match', matchId: id, error: e.message });
        }
      }
    }
  }
}

/**
 * Look up a cached match summary by ID.
 * Returns null if not found.
 */
export async function getMatchSummary(matchId) {
  try {
    return await cacheGet(KEYS.matchSummary(matchId));
  } catch {
    return null;
  }
}

/**
 * Convert a cached match summary into the full match detail response shape
 * that the Flutter app expects from /match/:id.
 */
export function summaryToMatchDetail(summary) {
  return {
    match_id: summary.match_id,
    series_id: summary.series_id || '',
    series_name: summary.series_name || '',
    match_desc: summary.match_desc || '',
    match_format: summary.match_format || '',
    match_type: summary.match_type || '',
    match_number: '',
    status: summary.status || 'upcoming',
    status_text: summary.status_text || 'Upcoming',
    result: '',
    man_of_match: '',
    current_innings: 0,
    team1: summary.team1 || { id: '', name: '', short_name: '' },
    team2: summary.team2 || { id: '', name: '', short_name: '' },
    venue: summary.venue || { name: '', city: '', country: '' },
    start_time: summary.start_time || null,
    end_time: summary.end_time || null,
    innings: [],
    current_batsmen: [],
    current_run_rate: 0,
    required_run_rate: 0,
    latest_performance: [],
    powerplay_data: [],
    last_updated: new Date().toISOString(),
    message: 'Match details sourced from schedule/cache',
  };
}
