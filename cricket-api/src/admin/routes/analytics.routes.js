/**
 * Admin Analytics routes (read-only).
 *
 * Aggregates rows from analytics_events / analytics_devices into dashboard
 * summary cards, time series, and dimension breakdowns. All endpoints require
 * the analytics.view permission. Pure reads — never mutate analytics data.
 *
 * Install numbers are reported as "First Opens / Approx Installs" (distinct
 * devices) because real Play Store install data is not connected.
 */
import { adminAuth, requirePermissions } from '../auth.js';
import { query } from '../../lib/db.js';
import { getPresence } from '../../lib/presence.js';

// Clamp a from/to query into safe DATETIME bounds. Defaults to last 30 days.
function dateRange(q) {
  const to = q?.to ? new Date(q.to) : new Date();
  const from = q?.from ? new Date(q.from) : new Date(to.getTime() - 30 * 24 * 3600 * 1000);
  const fmt = (d) => {
    const safe = Number.isNaN(d.getTime()) ? new Date() : d;
    return safe.toISOString().slice(0, 19).replace('T', ' ');
  };
  return { from: fmt(from), to: fmt(to) };
}

// Calendar-day boundaries for "today" metrics. analytics_events.created_at is
// written with CURRENT_TIMESTAMP (the DB session timezone), so we compare it
// against NOW()/DATE(NOW()) in that SAME clock — never a hand-rolled UTC offset,
// which would desync from how the rows were stored. DAU/MAU and "new users
// today" are bounded to local midnight (DATE(NOW())), NOT a rolling 24h window,
// so the numbers don't drift as the day progresses. To run the dashboard in a
// specific timezone, set the MySQL session/global time_zone — both writes and
// reads then move together.
const DAY_START = 'DATE(NOW())'; // 00:00:00 of the current calendar day
const MONTH_START = "DATE_FORMAT(NOW(), '%Y-%m-01')"; // 1st of the current month

const COUNT_EVENT = (name) => `SUM(event_name = '${name}') `;

export default async function analyticsAdminRoutes(fastify) {
  fastify.addHook('preHandler', adminAuth);

  // GET /admin/analytics/realtime — active users/sessions right now, from the
  // Redis presence window (real heartbeats only; stale users auto-expire).
  fastify.get('/realtime', { preHandler: [requirePermissions('analytics.view')] }, async () => {
    const presence = await getPresence();
    return { success: true, data: presence };
  });

  // GET /admin/analytics/summary?from=&to=
  fastify.get('/summary', { preHandler: [requirePermissions('analytics.view')] }, async (request) => {
    const { from, to } = dateRange(request.query);

    const safe = (p) => p.catch(() => []);

    const [
      activeRows,
      installRows,
      sessionRows,
      eventCountRows,
      topScreens,
      topMatches,
      topQualities,
      versionRows,
      platformRows,
    ] = await Promise.all([
      // Active users = distinct devices, bounded to the CURRENT calendar day /
      // month (not a rolling 24h/30d window), plus a rolling 7d for WAU.
      safe(query(
        `SELECT
           COUNT(DISTINCT CASE WHEN created_at >= ${DAY_START} THEN device_id END) AS dau,
           COUNT(DISTINCT CASE WHEN created_at >= NOW() - INTERVAL 7 DAY THEN device_id END) AS wau,
           COUNT(DISTINCT CASE WHEN created_at >= ${MONTH_START} THEN device_id END) AS mau
         FROM analytics_events
         WHERE device_id IS NOT NULL`,
      )),
      // Installs from the deduped devices table:
      //   total       = every distinct install ever seen
      //   newToday    = installs whose first_seen is today (real "new users")
      //   newInRange  = installs whose first_seen falls in the selected range
      //   returning   = devices active today that were NOT first seen today
      safe(query(
        `SELECT
           COUNT(*) AS total_devices,
           SUM(first_seen >= ${DAY_START}) AS new_today,
           SUM(first_seen BETWEEN ? AND ?) AS new_in_range,
           SUM(last_seen >= ${DAY_START} AND first_seen < ${DAY_START}) AS returning_today
         FROM analytics_devices`,
        [from, to],
      )),
      // Sessions from the deduped sessions table: distinct usage periods, NOT
      // app opens. "today" = sessions started today; "inRange" = within filter.
      safe(query(
        `SELECT
           SUM(started_at >= ${DAY_START}) AS sessions_today,
           SUM(started_at BETWEEN ? AND ?) AS sessions_in_range
         FROM analytics_sessions`,
        [from, to],
      )),
      // Event tallies in window. app_open is a raw open counter (separate from
      // users); session_start kept for backward-compat but Sessions now comes
      // from the deduped sessions table above.
      safe(query(
        `SELECT
           ${COUNT_EVENT('app_open')} AS app_opens,
           ${COUNT_EVENT('screen_view')} AS screen_views,
           ${COUNT_EVENT('match_open')} AS match_opens,
           ${COUNT_EVENT('live_stream_open')} AS live_stream_opens,
           ${COUNT_EVENT('quality_selected')} AS quality_selections,
           ${COUNT_EVENT('pull_refresh')} AS pull_refreshes,
           ${COUNT_EVENT('retry_after_error')} AS retry_after_errors
         FROM analytics_events
         WHERE created_at BETWEEN ? AND ?`,
        [from, to],
      )),
      safe(query(
        `SELECT JSON_UNQUOTE(JSON_EXTRACT(payload, '$.screen_name')) AS screen, COUNT(*) AS count
           FROM analytics_events
          WHERE event_name = 'screen_view' AND created_at BETWEEN ? AND ?
          GROUP BY screen HAVING screen IS NOT NULL
          ORDER BY count DESC LIMIT 10`,
        [from, to],
      )),
      safe(query(
        `SELECT JSON_UNQUOTE(JSON_EXTRACT(payload, '$.match_id')) AS match_id, COUNT(*) AS count
           FROM analytics_events
          WHERE event_name = 'match_open' AND created_at BETWEEN ? AND ?
          GROUP BY match_id HAVING match_id IS NOT NULL
          ORDER BY count DESC LIMIT 10`,
        [from, to],
      )),
      safe(query(
        `SELECT JSON_UNQUOTE(JSON_EXTRACT(payload, '$.quality_label')) AS quality, COUNT(*) AS count
           FROM analytics_events
          WHERE event_name = 'quality_selected' AND created_at BETWEEN ? AND ?
          GROUP BY quality HAVING quality IS NOT NULL
          ORDER BY count DESC LIMIT 10`,
        [from, to],
      )),
      safe(query(
        `SELECT COALESCE(app_version, 'unknown') AS app_version, COUNT(*) AS count
           FROM analytics_devices GROUP BY app_version ORDER BY count DESC LIMIT 20`,
      )),
      safe(query(
        `SELECT COALESCE(platform, 'unknown') AS platform, COUNT(*) AS count
           FROM analytics_devices GROUP BY platform ORDER BY count DESC`,
      )),
    ]);

    const active = activeRows[0] || {};
    const installs = installRows[0] || {};
    const sess = sessionRows[0] || {};
    const counts = eventCountRows[0] || {};
    const num = (v) => Number(v || 0);

    return {
      success: true,
      data: {
        range: { from, to },
        activeUsers: {
          today: num(active.dau),
          last7Days: num(active.wau),
          last30Days: num(active.mau),
        },
        // Real first-time installs (distinct device identities).
        newUsers: {
          today: num(installs.new_today),
          inRange: num(installs.new_in_range),
        },
        totalUsers: num(installs.total_devices),
        returningUsersToday: num(installs.returning_today),
        // Kept for backward-compat with existing UI; mirrors newUsers/totalUsers.
        firstOpensApproxInstalls: {
          total: num(installs.total_devices),
          newInRange: num(installs.new_in_range),
        },
        // Distinct usage periods (deduped sessions), separate from raw app opens.
        sessions: num(sess.sessions_in_range),
        sessionsToday: num(sess.sessions_today),
        appOpens: num(counts.app_opens),
        screenViews: num(counts.screen_views),
        matchOpens: num(counts.match_opens),
        liveStreamOpens: num(counts.live_stream_opens),
        qualitySelections: num(counts.quality_selections),
        pullRefreshCount: num(counts.pull_refreshes),
        retryAfterErrorCount: num(counts.retry_after_errors),
        topScreens: topScreens.map((r) => ({ screen: r.screen, count: num(r.count) })),
        topMatches: topMatches.map((r) => ({ matchId: r.match_id, count: num(r.count) })),
        topStreamQualities: topQualities.map((r) => ({ quality: r.quality, count: num(r.count) })),
        appVersions: versionRows.map((r) => ({ appVersion: r.app_version, count: num(r.count) })),
        platforms: platformRows.map((r) => ({ platform: r.platform, count: num(r.count) })),
      },
    };
  });

  // GET /admin/analytics/timeseries?metric=&from=&to=&granularity=day
  fastify.get('/timeseries', { preHandler: [requirePermissions('analytics.view')] }, async (request) => {
    const { from, to } = dateRange(request.query);
    const metric = String(request.query?.metric || 'active_users');
    const granularity = request.query?.granularity === 'hour' ? 'hour' : 'day';
    const fmt = granularity === 'hour' ? '%Y-%m-%d %H:00:00' : '%Y-%m-%d';

    // metric → SQL value expression. Most metrics aggregate analytics_events;
    // active_users and sessions are deduped (distinct devices / sessions table).
    let valueExpr;
    let whereEvent = '';
    let table = 'analytics_events';
    let timeCol = 'created_at';
    if (metric === 'active_users') {
      valueExpr = 'COUNT(DISTINCT device_id)';
      whereEvent = 'AND device_id IS NOT NULL';
    } else if (metric === 'sessions') {
      // Distinct usage periods from the deduped sessions table.
      valueExpr = 'COUNT(DISTINCT session_id)';
      table = 'analytics_sessions';
      timeCol = 'started_at';
    } else if (metric === 'app_opens') {
      valueExpr = 'COUNT(*)';
      whereEvent = "AND event_name = 'app_open'";
    } else if (metric === 'live_stream_opens') {
      valueExpr = 'COUNT(*)';
      whereEvent = "AND event_name = 'live_stream_open'";
    } else if (metric === 'match_opens') {
      valueExpr = 'COUNT(*)';
      whereEvent = "AND event_name = 'match_open'";
    } else if (metric === 'screen_views') {
      valueExpr = 'COUNT(*)';
      whereEvent = "AND event_name = 'screen_view'";
    } else if (metric === 'retry_after_error') {
      valueExpr = 'COUNT(*)';
      whereEvent = "AND event_name = 'retry_after_error'";
    } else {
      valueExpr = 'COUNT(*)';
    }

    const rows = await query(
      `SELECT DATE_FORMAT(${timeCol}, '${fmt}') AS bucket, ${valueExpr} AS value
         FROM ${table}
        WHERE ${timeCol} BETWEEN ? AND ? ${whereEvent}
        GROUP BY bucket ORDER BY bucket ASC`,
      [from, to],
    ).catch(() => []);

    return {
      success: true,
      data: {
        metric,
        granularity,
        range: { from, to },
        series: rows.map((r) => ({ date: r.bucket, value: Number(r.value || 0) })),
      },
    };
  });

  // GET /admin/analytics/breakdown?dimension=&from=&to=
  fastify.get('/breakdown', { preHandler: [requirePermissions('analytics.view')] }, async (request) => {
    const { from, to } = dateRange(request.query);
    const dimension = String(request.query?.dimension || 'platform');

    let rows = [];
    if (dimension === 'app_version' || dimension === 'platform' || dimension === 'country') {
      const col = dimension; // whitelisted above
      rows = await query(
        `SELECT COALESCE(${col}, 'unknown') AS label, COUNT(*) AS count
           FROM analytics_devices GROUP BY label ORDER BY count DESC LIMIT 50`,
      ).catch(() => []);
    } else if (dimension === 'quality') {
      rows = await query(
        `SELECT JSON_UNQUOTE(JSON_EXTRACT(payload, '$.quality_label')) AS label, COUNT(*) AS count
           FROM analytics_events
          WHERE event_name = 'quality_selected' AND created_at BETWEEN ? AND ?
          GROUP BY label HAVING label IS NOT NULL ORDER BY count DESC LIMIT 50`,
        [from, to],
      ).catch(() => []);
    } else if (dimension === 'screen') {
      rows = await query(
        `SELECT JSON_UNQUOTE(JSON_EXTRACT(payload, '$.screen_name')) AS label, COUNT(*) AS count
           FROM analytics_events
          WHERE event_name = 'screen_view' AND created_at BETWEEN ? AND ?
          GROUP BY label HAVING label IS NOT NULL ORDER BY count DESC LIMIT 50`,
        [from, to],
      ).catch(() => []);
    }

    return {
      success: true,
      data: {
        dimension,
        range: { from, to },
        items: rows.map((r) => ({ label: r.label, count: Number(r.count || 0) })),
      },
    };
  });
}
