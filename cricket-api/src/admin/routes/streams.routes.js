import { adminAuth, requirePermissions } from '../auth.js';
import { withAudit, recordAudit } from '../audit.js';
import { query } from '../../lib/db.js';
import axios from 'axios';
import { DateTime } from 'luxon';
import { clearDataCache } from '../../lib/data-control.js';
import { getRedis, KEYS } from '../../lib/redis.js';
import { recordNotificationHistory, sendOneSignalNotification } from '../../lib/onesignal.js';
import providerManager from '../../providers/provider-manager.js';
import {
  NOTIFICATION_EVENTS,
  streamPublishedKey,
  claimNotificationEvent,
  markNotificationLog,
  getStreamNotificationStatus,
} from '../../lib/notification-dedupe.js';
 
const ALLOWED_QUALITY = new Set(['AUTO', 'FHD', 'HD', 'SD']);
const ALLOWED_TYPE = new Set(['hls', 'dash', 'mpd', 'iframe', 'external']);
const ALLOWED_STATUS = new Set(['unknown', 'working', 'slow', 'down']);
const ALLOWED_LIFECYCLE = new Set(['draft', 'scheduled', 'active', 'disabled', 'expired']);

// MySQL DATETIME columns reject ISO-8601 strings (e.g. '2026-06-13T07:34:00.000Z').
// Convert any incoming date value to the 'YYYY-MM-DD HH:MM:SS' (UTC) form MySQL
// expects. Empty/invalid input becomes null so the column can be cleared.
function toMysqlDateTime(value) {
  if (value == null || value === '') return null;
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString().slice(0, 19).replace('T', ' ');
}

function normalisePayload(body, { isUpdate = false } = {}) {
  const out = {};
  const map = {
    match_external_id: 'match_external_id',
    match_title: 'match_title',
    title: 'title',
    team_a: 'team_a',
    team_b: 'team_b',
    quality: 'quality',
    label: 'label',
    language: 'language',
    server_id: 'server_id',
    server_name: 'server_name',
    stream_type: 'stream_type',
    stream_url: 'stream_url',
    backup_stream_url: 'backup_stream_url',
    status: 'status',
    is_active: 'is_active',
    is_premium: 'is_premium',
    requires_reward_ad: 'requires_reward_ad',
    requires_login: 'requires_login',
    priority: 'priority',
    starts_at: 'starts_at',
    ends_at: 'ends_at',
    lifecycle_state: 'lifecycle_state',
    timezone: 'timezone',
    early_show_minutes: 'early_show_minutes',
    auto_hide_after_end: 'auto_hide_after_end',
    geo_blocked_countries: 'geo_blocked_countries',
    headers_json: 'headers_json',
    user_agent_header: 'user_agent_header',
    referer_header: 'referer_header',
    origin_header: 'origin_header',
    drm_enabled: 'drm_enabled',
    drm_type: 'drm_type',
    drm_license_url: 'drm_license_url',
    drm_headers: 'drm_headers',
    clear_key_key_id: 'clear_key_key_id',
    clear_key_key: 'clear_key_key',
    notes: 'notes',
  };
  for (const [k, col] of Object.entries(map)) {
    if (body[k] !== undefined) out[col] = body[k];
  }
  if (out.quality && !ALLOWED_QUALITY.has(out.quality)) {
    throw Object.assign(new Error('Invalid quality'), { statusCode: 400 });
  }
  if (out.stream_type && !ALLOWED_TYPE.has(out.stream_type)) {
    throw Object.assign(new Error('Invalid stream_type'), { statusCode: 400 });
  }
  if (out.status && !ALLOWED_STATUS.has(out.status)) {
    throw Object.assign(new Error('Invalid status'), { statusCode: 400 });
  }
  if (out.lifecycle_state && !ALLOWED_LIFECYCLE.has(String(out.lifecycle_state).toLowerCase())) {
    throw Object.assign(new Error('Invalid lifecycle_state'), { statusCode: 400 });
  }
  if (out.lifecycle_state) out.lifecycle_state = String(out.lifecycle_state).toLowerCase();
  if (out.stream_type === 'mpd') out.stream_type = 'dash';
  // A URL whose path contains `.m3u8` is HLS. Normalize a missing/unknown/
  // wrong type (live/external/iframe/mpd/dash/null) to 'hls' so a valid HLS
  // master is never rejected as unsupported. Real DASH (.mpd) is untouched.
  if (out.stream_url) {
    const path = (() => {
      try { return new URL(out.stream_url).pathname.toLowerCase(); }
      catch { return String(out.stream_url).toLowerCase(); }
    })();
    if (path.includes('.m3u8') && out.stream_type !== 'hls') {
      out.stream_type = 'hls';
    }
  }
  if (!isUpdate) {
    if (!out.match_external_id) throw Object.assign(new Error('match_external_id required'), { statusCode: 400 });
    if (!out.stream_url) throw Object.assign(new Error('stream_url required'), { statusCode: 400 });
    out.quality ??= 'AUTO';
    out.stream_type ??= 'hls';
    out.is_active ??= 1;
    out.is_premium ??= 0;
    out.priority ??= 100;
    out.status ??= 'unknown';
    out.lifecycle_state ??= 'scheduled';
    out.early_show_minutes ??= 0;
    out.auto_hide_after_end ??= 1;
  }
  if ('is_active' in out) out.is_active = out.is_active ? 1 : 0;
  if ('is_premium' in out) out.is_premium = out.is_premium ? 1 : 0;
  if ('requires_reward_ad' in out) out.requires_reward_ad = out.requires_reward_ad ? 1 : 0;
  if ('requires_login' in out) out.requires_login = out.requires_login ? 1 : 0;
  if ('auto_hide_after_end' in out) out.auto_hide_after_end = out.auto_hide_after_end ? 1 : 0;
  if ('early_show_minutes' in out && out.early_show_minutes != null) {
    const n = Number(out.early_show_minutes);
    out.early_show_minutes = Number.isFinite(n) && n >= 0 ? Math.floor(n) : 0;
  }
  if ('drm_enabled' in out) out.drm_enabled = out.drm_enabled ? 1 : 0;
  if ('geo_blocked_countries' in out && out.geo_blocked_countries != null) {
    out.geo_blocked_countries = JSON.stringify(out.geo_blocked_countries);
  }
  if ('headers_json' in out && out.headers_json != null && typeof out.headers_json !== 'string') {
    out.headers_json = JSON.stringify(out.headers_json);
  }
  if ('drm_headers' in out && out.drm_headers != null && typeof out.drm_headers !== 'string') {
    out.drm_headers = JSON.stringify(out.drm_headers);
  }
  if ('drm_type' in out && out.drm_type) {
    out.drm_type = String(out.drm_type).toLowerCase();
  }
  if ('starts_at' in out) out.starts_at = toMysqlDateTime(out.starts_at);
  if ('ends_at' in out) out.ends_at = toMysqlDateTime(out.ends_at);
  return out;
}
 
function rowToDto(row) {
  if (!row) return null;
  return {
    ...row,
    is_active: !!row.is_active,
    is_premium: !!row.is_premium,
    requires_reward_ad: !!row.requires_reward_ad,
    requires_login: !!row.requires_login,
    drm_enabled: !!row.drm_enabled,
    auto_hide_after_end: row.auto_hide_after_end == null ? true : !!row.auto_hide_after_end,
    early_show_minutes: Number(row.early_show_minutes || 0),
    lifecycle_state: row.lifecycle_state || 'scheduled',
    geo_blocked_countries: row.geo_blocked_countries
      ? typeof row.geo_blocked_countries === 'string'
        ? safeParse(row.geo_blocked_countries, [])
        : row.geo_blocked_countries
      : [],
    headers_json: row.headers_json
      ? typeof row.headers_json === 'string'
        ? safeParse(row.headers_json, {})
        : row.headers_json
      : {},
    drm_headers: row.drm_headers
      ? typeof row.drm_headers === 'string'
        ? safeParse(row.drm_headers, {})
        : row.drm_headers
      : {},
  };
}
 
function safeParse(s, fallback = []) {
  try { return JSON.parse(s); } catch { return fallback; }
}

// Validate a stream URL without downloading the whole video. Follows redirects,
// reads only the first chunk of the body, and inspects content-type + payload
// to classify the source. Returns a structured result the admin UI can show.
async function validateStreamUrl(url, rawHeaders = {}) {
  const headers = {};
  for (const [k, v] of Object.entries(rawHeaders)) {
    if (v != null && String(v).trim() !== '') headers[k] = String(v);
  }
  const out = {
    playable: false,
    type: 'unknown',
    status: 'down',
    statusCode: null,
    finalUrl: null,
    needsHeaders: false,
    reason: null,
    variants: [],
    latencyMs: 0,
  };
  if (!url) {
    out.reason = 'No stream URL configured.';
    return out;
  }
  const start = Date.now();
  try {
    // GET with a Range header so well-behaved servers send only a small slice.
    // responseType 'text' caps what axios buffers; maxContentLength bounds it.
    const res = await axios.get(url, {
      headers: { Range: 'bytes=0-65535', ...headers },
      timeout: 9000,
      validateStatus: () => true,
      maxRedirects: 5,
      responseType: 'text',
      maxContentLength: 512 * 1024,
      transformResponse: [(d) => d],
    });
    out.statusCode = res.status;
    out.finalUrl = res.request?.res?.responseUrl || url;
    const contentType = String(res.headers?.['content-type'] || '').toLowerCase();
    const body = typeof res.data === 'string' ? res.data : '';

    if (res.status === 401 || res.status === 403) {
      out.status = 'down';
      out.needsHeaders = true;
      out.reason = `Access denied (${res.status}). Stream may require headers or be expired.`;
      return out;
    }
    if (res.status === 404 || res.status === 410) {
      out.status = 'down';
      out.reason = `Stream not found (${res.status}). Link may be expired.`;
      return out;
    }
    if (res.status >= 500) {
      out.status = 'slow';
      out.reason = `Origin server error (${res.status}).`;
      return out;
    }
    if (res.status < 200 || res.status >= 400) {
      out.status = 'down';
      out.reason = `Unexpected HTTP status ${res.status}.`;
      return out;
    }

    // Classify by payload + content-type.
    const looksHls = body.includes('#EXTM3U') ||
      contentType.includes('mpegurl') ||
      url.toLowerCase().includes('.m3u8');
    const looksDash = body.includes('<MPD') ||
      contentType.includes('dash+xml') ||
      url.toLowerCase().includes('.mpd');
    const looksHtml = contentType.includes('text/html') ||
      /^\s*<(?:!doctype|html)/i.test(body);

    if (looksDash && !looksHls) {
      out.type = 'dash';
      out.playable = false; // App player is HLS-only.
      out.status = 'working';
      out.reason = 'DASH/MPD stream detected. The app player supports HLS only.';
      return out;
    }
    if (looksHls) {
      out.type = 'hls';
      out.playable = true;
      out.status = 'working';
      out.reason = 'hls_media_playlist';
      if (body.includes('#EXT-X-STREAM-INF')) {
        // Master playlist — extract variant resolutions/bandwidths.
        const lines = body.split('\n');
        for (const line of lines) {
          if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
          const res = /RESOLUTION=(\d+x\d+)/.exec(line);
          const bw = /BANDWIDTH=(\d+)/.exec(line);
          out.variants.push({
            resolution: res ? res[1] : null,
            bandwidth: bw ? Number(bw[1]) : null,
          });
        }
        out.reason = 'hls_master_playlist';
      }
      return out;
    }
    if (looksHtml) {
      out.type = 'unknown';
      out.status = 'down';
      out.reason = 'URL returned an HTML page, not a stream playlist.';
      return out;
    }
    // 2xx but unrecognized payload — treat as reachable but unverified.
    out.type = 'unknown';
    out.status = 'slow';
    out.reason = `Reachable (HTTP ${res.status}) but content type "${contentType || 'unknown'}" is not a recognized stream.`;
    return out;
  } catch (err) {
    const code = err?.code || '';
    if (code === 'ECONNABORTED' || /timeout/i.test(err?.message || '')) {
      out.reason = 'Stream timed out (no response within 9s).';
    } else if (code === 'CERT_HAS_EXPIRED' || /certificate|ssl|self.signed/i.test(err?.message || '')) {
      out.reason = 'SSL/certificate error on stream host.';
    } else if (code === 'ENOTFOUND' || code === 'EAI_AGAIN') {
      out.reason = 'Stream host could not be resolved (DNS).';
    } else {
      out.reason = err?.message || 'Connection failed.';
    }
    out.status = 'down';
    return out;
  } finally {
    out.latencyMs = Date.now() - start;
  }
}

async function invalidateStreamCaches(matchId) {
  if (!matchId) return;
  await clearDataCache('matchStreams', matchId).catch(() => null);
  await clearDataCache('homeData').catch(() => null);
  await clearDataCache('liveMatches').catch(() => null);
  await clearDataCache('upcomingMatches').catch(() => null);
  await clearDataCache('recentMatches').catch(() => null);
  const redis = getRedis();
  await redis.del(
    KEYS.matchesList('live'),
    KEYS.matchesList('upcoming'),
    KEYS.matchesList('recent'),
    KEYS.matchesList('finished'),
    KEYS.matchLive(matchId),
    KEYS.matchInfo(matchId),
    KEYS.matchSummary(matchId),
    KEYS.matchInfoDetailed(matchId),
    'appdata:app:home',
    'appdata:app:config',
    `appdata:match:${matchId}:detail`,
    `appdata:match:${matchId}:streams`,
  ).catch(() => null);
}

// A stream is "Published" (visible to users) when it is active and the admin
// has not parked it in draft/disabled. Mirrors public-app-state's intent.
function isStreamPublished(row) {
  if (!row) return false;
  const active = Number(row.is_active) === 1;
  const state = String(row.lifecycle_state || 'scheduled').toLowerCase();
  return active && state !== 'draft' && state !== 'disabled';
}

function streamMatchupLabel(row) {
  const a = (row.team_a || '').trim();
  const b = (row.team_b || '').trim();
  if (a && b) return `${a} vs ${b}`;
  return (row.match_title || row.title || 'Your match').trim();
}

// Clean, premium publish notification derived purely from the stream's real
// match metadata (auto-filled at Sync/Add time — no manual typing).
function buildStreamNotification(row) {
  const matchup = streamMatchupLabel(row);
  return {
    title: 'Live Stream Available',
    body: `${matchup} is now live on CricPro. Tap to watch.`,
    target_type: 'category',
    target_value: 'live_stream',
    deep_link_type: 'live_stream',
    deep_link_value: String(row.match_external_id),
    payload: {
      type: 'live_stream',
      matchId: String(row.match_external_id),
      deepLink: `cricpro://match/${row.match_external_id}/live`,
    },
  };
}

/**
 * Send the "stream published" push at most ONCE per stream, only on a real
 * Draft/Inactive -> Published transition (or an explicit force), de-duplicated
 * via notification_log so repeated saves never re-blast users.
 *
 * @returns {Promise<{status: 'sent'|'failed'|'skipped'|'already_sent', reason?: string}>}
 */
async function maybeSendPublishNotification(row, { wasPublished, notifyOptIn, force = false } = {}) {
  if (!row?.match_external_id) return { status: 'skipped', reason: 'no_match' };
  if (!notifyOptIn && !force) return { status: 'skipped', reason: 'opt_out' };
  if (!isStreamPublished(row)) return { status: 'skipped', reason: 'not_published' };
  // Only fire on the transition into published (unless the admin forced a send).
  if (wasPublished && !force) return { status: 'skipped', reason: 'already_published' };

  const dedupeKey = streamPublishedKey(row.id);
  const notification = buildStreamNotification(row);
  const claim = await claimNotificationEvent({
    matchId: row.match_external_id,
    eventType: NOTIFICATION_EVENTS.STREAM_PUBLISHED,
    dedupeKey,
    streamId: row.id,
    title: notification.title,
    body: notification.body,
  });
  if (!claim.claimed) return { status: 'already_sent', reason: 'deduped' };

  try {
    const result = await sendOneSignalNotification(notification);
    await markNotificationLog(dedupeKey, { status: 'sent', providerResponse: result.response });
    await recordNotificationHistory({
      notification,
      payload: result.payload,
      providerResponse: result.response,
      status: 'sent',
    });
    return { status: 'sent' };
  } catch (err) {
    await markNotificationLog(dedupeKey, { status: 'failed', errorMessage: err.message, providerResponse: err.providerResponse || null });
    await recordNotificationHistory({
      notification,
      status: 'failed',
      errorMessage: err.message,
      providerResponse: err.providerResponse || null,
    });
    return { status: 'failed', reason: err.message };
  }
}

// "Send notification on publish" — opt-in flag, ENABLED BY DEFAULT. Accepts the
// new `notify_on_publish` plus the legacy `send_push_now` (manual force).
function publishNotifyOptIn(body = {}) {
  const raw = body.notify_on_publish;
  if (raw === undefined || raw === null) return true; // default ON
  return !(raw === false || raw === 0 || raw === '0' || raw === 'false');
}

// ---------------------------------------------------------------------------
// Sync Live & Upcoming Matches (admin "Sync" button)
// ---------------------------------------------------------------------------
const COMPLETED_STATUSES = new Set(['completed', 'complete', 'finished', 'abandoned', 'no_result', 'recent']);

function matchupTitle(m) {
  const a = m.team1?.short_name || m.team1?.name || '';
  const b = m.team2?.short_name || m.team2?.name || '';
  if (a && b) return `${a} vs ${b}`;
  return m.match_desc || m.series_name || 'Match';
}

// Shape a provider match into the rich, ready-to-autofill record the admin
// "Add Stream" form consumes — the editor never types match metadata.
function syncMatchDto(m, phase) {
  const venueParts = [m.venue?.name, m.venue?.city].filter(Boolean);
  return {
    match_id: String(m.match_id),
    match_external_id: String(m.match_id),
    title: m.match_desc || matchupTitle(m),
    matchup: matchupTitle(m),
    team1_name: m.team1?.name || '',
    team1_short: m.team1?.short_name || '',
    team1_logo: m.team1?.logo_url || null,
    team2_name: m.team2?.name || '',
    team2_short: m.team2?.short_name || '',
    team2_logo: m.team2?.logo_url || null,
    series_id: m.series_id || '',
    series_name: m.series_name || '',
    venue: venueParts.join(', '),
    start_time: m.start_time || null,
    match_format: m.match_format || '',
    match_type: m.match_type || '',
    status: m.status || '',
    status_text: m.status_text || '',
    phase, // 'live' | 'upcoming'
  };
}

// Summarise the existing stream records for a match into an admin-friendly
// status label so the Sync result can show "Published" / "Stream Added" /
// "Add Stream" without the editor digging into each record.
function summariseStreamsForMatch(rows = []) {
  if (!rows.length) {
    return { has_stream: false, stream_count: 0, published: false, stream_status: 'none', stream_status_label: 'Add Stream', streams: [] };
  }
  const published = rows.some((r) => isStreamPublished(r));
  return {
    has_stream: true,
    stream_count: rows.length,
    published,
    stream_status: published ? 'published' : 'draft',
    stream_status_label: published ? 'Published' : 'Stream Added',
    streams: rows.map((r) => ({
      id: r.id,
      title: r.title || r.label || null,
      is_active: !!r.is_active,
      status: r.status || 'unknown',
      lifecycle_state: r.lifecycle_state || 'scheduled',
      priority: Number(r.priority || 100),
    })),
  };
}
 
export default async function streamsRoutes(fastify) {
  fastify.addHook('preHandler', adminAuth);
 
  fastify.get('/sync', { preHandler: [requirePermissions('streams.view')] }, async (request) => {
    const requestedTz = String(request.query?.tz || 'UTC');
    const zone = DateTime.now().setZone(requestedTz).isValid ? requestedTz : 'UTC';
    const now = DateTime.now().setZone(zone);
    const windowStart = now.startOf('day');
    const windowEnd = now.plus({ days: 1 }).endOf('day');

    const [liveRes, upcomingRes] = await Promise.allSettled([
      providerManager.execute('getLiveMatches'),
      providerManager.execute('getUpcomingMatches'),
    ]);
    const liveList = liveRes.status === 'fulfilled' && Array.isArray(liveRes.value?.data) ? liveRes.value.data : [];
    const upcomingList = upcomingRes.status === 'fulfilled' && Array.isArray(upcomingRes.value?.data) ? upcomingRes.value.data : [];
    const provider = liveRes.value?.provider || upcomingRes.value?.provider || null;
    const errors = [];
    if (liveRes.status === 'rejected') errors.push(`live: ${liveRes.reason?.message || 'failed'}`);
    if (upcomingRes.status === 'rejected') errors.push(`upcoming: ${upcomingRes.reason?.message || 'failed'}`);

    // Dedupe by match id — LIVE wins over an upcoming duplicate.
    const byId = new Map();
    for (const m of liveList) {
      const id = String(m?.match_id || '');
      if (!id || COMPLETED_STATUSES.has(String(m.status))) continue;
      byId.set(id, syncMatchDto(m, 'live'));
    }
    for (const m of upcomingList) {
      const id = String(m?.match_id || '');
      if (!id || byId.has(id) || COMPLETED_STATUSES.has(String(m.status))) continue;
      // today/tomorrow window only (timezone-safe).
      const start = m.start_time ? DateTime.fromISO(m.start_time, { zone }) : null;
      if (!start || !start.isValid || start < windowStart || start > windowEnd) continue;
      byId.set(id, syncMatchDto(m, 'upcoming'));
    }

    const items = [...byId.values()];

    // One round-trip to attach existing stream records per match.
    if (items.length) {
      const ids = items.map((i) => i.match_external_id);
      const placeholders = ids.map(() => '?').join(', ');
      const streamRows = await query(
        `SELECT id, match_external_id, title, label, is_active, status, lifecycle_state, priority
           FROM match_streams
          WHERE match_external_id IN (${placeholders})
          ORDER BY priority ASC, id ASC`,
        ids,
      ).catch(() => []);
      const grouped = new Map();
      for (const r of streamRows) {
        const key = String(r.match_external_id);
        if (!grouped.has(key)) grouped.set(key, []);
        grouped.get(key).push(r);
      }
      for (const item of items) {
        Object.assign(item, summariseStreamsForMatch(grouped.get(item.match_external_id) || []));
      }
    }

    // Live first, then upcoming by start time.
    items.sort((a, b) => {
      if (a.phase !== b.phase) return a.phase === 'live' ? -1 : 1;
      return String(a.start_time || '').localeCompare(String(b.start_time || ''));
    });

    return {
      success: true,
      data: {
        timezone: zone,
        provider: provider || 'cricbuzz',
        syncedAt: new Date().toISOString(),
        window: { from: windowStart.toISO(), to: windowEnd.toISO() },
        counts: {
          total: items.length,
          live: items.filter((i) => i.phase === 'live').length,
          upcoming: items.filter((i) => i.phase === 'upcoming').length,
          withStream: items.filter((i) => i.has_stream).length,
          published: items.filter((i) => i.published).length,
        },
        errors,
        matches: items,
      },
    };
  });

  fastify.get('/', { preHandler: [requirePermissions('streams.view')] }, async (request) => {
    const { match_external_id, q, status, is_active } = request.query;
    const where = [];
    const params = [];
    if (match_external_id) { where.push('match_external_id = ?'); params.push(match_external_id); }
    if (status)            { where.push('status = ?'); params.push(status); }
    if (is_active !== undefined) { where.push('is_active = ?'); params.push(is_active === 'true' || is_active === '1' ? 1 : 0); }
    if (q) {
      where.push('(title LIKE ? OR notes LIKE ? OR server_name LIKE ?)');
      const like = `%${q}%`;
      params.push(like, like, like);
    }
    const sql = `SELECT s.*, srv.name AS server_resolved
                   FROM match_streams s
              LEFT JOIN stream_servers srv ON srv.id = s.server_id
              ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
              ORDER BY s.created_at DESC
                 LIMIT 500`;
    const rows = await query(sql, params);
    return { success: true, data: rows.map(rowToDto) };
  });
 
  fastify.get('/:id', { preHandler: [requirePermissions('streams.view')] }, async (request, reply) => {
    const rows = await query(`SELECT * FROM match_streams WHERE id = ?`, [request.params.id]);
    if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const dto = rowToDto(rows[0]);
    const notifyLog = await getStreamNotificationStatus(request.params.id);
    return {
      success: true,
      data: {
        ...dto,
        published: isStreamPublished(rows[0]),
        publish_notification: notifyLog
          ? {
              status: notifyLog.status,
              error: notifyLog.error_message || null,
              sent_at: notifyLog.sent_at || null,
              created_at: notifyLog.created_at || null,
            }
          : null,
      },
    };
  });
 
  fastify.post('/', { preHandler: [requirePermissions('streams.write')] }, async (request, reply) => {
    const data = normalisePayload(request.body || {});
    const cols = Object.keys(data);
    const placeholders = cols.map(() => '?').join(', ');
    const values = cols.map((c) => data[c]);
    const result = await withAudit(
      request,
      {
        action: 'stream.create',
        entityType: 'match_stream',
        newValue: data,
      },
      async () => {
        const r = await query(
          `INSERT INTO match_streams (${cols.join(', ')}, created_by, updated_by)
             VALUES (${placeholders}, ?, ?)`,
          [...values, request.adminUser.id, request.adminUser.id],
        );
        return r;
      },
    );
    const row = await query(`SELECT * FROM match_streams WHERE id = ?`, [result.insertId]);
    await invalidateStreamCaches(data.match_external_id);
    // A freshly-created stream has no prior state, so publishing it now is a
    // genuine transition. Fires once (deduped); manual send_push_now forces it.
    let notification = { status: 'skipped', reason: 'not_published' };
    if (row[0]) {
      notification = await maybeSendPublishNotification(row[0], {
        wasPublished: false,
        notifyOptIn: publishNotifyOptIn(request.body),
        force: !!request.body?.send_push_now,
      });
    }
    return reply.code(201).send({ success: true, data: rowToDto(row[0]), notification });
  });
 
  fastify.put('/:id', { preHandler: [requirePermissions('streams.write')] }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT * FROM match_streams WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const data = normalisePayload(request.body || {}, { isUpdate: true });
    if (!Object.keys(data).length) return reply.code(400).send({ success: false, error: 'No fields to update' });
    const setClause = Object.keys(data).map((k) => `${k} = ?`).join(', ');
    await withAudit(
      request,
      {
        action: 'stream.update',
        entityType: 'match_stream',
        entityId: id,
        oldValue: old[0],
        newValue: data,
      },
      async () =>
        query(`UPDATE match_streams SET ${setClause}, updated_by = ? WHERE id = ?`, [
          ...Object.values(data),
          request.adminUser.id,
          id,
        ]),
    );
    const row = await query(`SELECT * FROM match_streams WHERE id = ?`, [id]);
    await invalidateStreamCaches(old[0].match_external_id);
    if (data.match_external_id && data.match_external_id !== old[0].match_external_id) {
      await invalidateStreamCaches(data.match_external_id);
    }
    // Send the publish push only on a real Draft/Inactive -> Published
    // transition (deduped). Re-saving an already-published stream is a no-op;
    // send_push_now forces a (still deduped) manual send.
    let notification = { status: 'skipped', reason: 'not_published' };
    if (row[0]) {
      notification = await maybeSendPublishNotification(row[0], {
        wasPublished: isStreamPublished(old[0]),
        notifyOptIn: publishNotifyOptIn(request.body),
        force: !!request.body?.send_push_now,
      });
    }
    return reply.send({ success: true, data: rowToDto(row[0]), notification });
  });
 
  fastify.delete('/:id', { preHandler: [requirePermissions('streams.write')] }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT * FROM match_streams WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    await withAudit(
      request,
      {
        action: 'stream.delete',
        entityType: 'match_stream',
        entityId: id,
        oldValue: old[0],
      },
      async () => query(`DELETE FROM match_streams WHERE id = ?`, [id]),
    );
    await invalidateStreamCaches(old[0].match_external_id);
    return reply.send({ success: true });
  });
 
  fastify.post('/:id/test', { preHandler: [requirePermissions('streams.test')] }, async (request, reply) => {
    const id = request.params.id;
    const rows = await query(`SELECT * FROM match_streams WHERE id = ?`, [id]);
    if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const stream = rows[0];
    const result = await validateStreamUrl(stream.stream_url, {
      'User-Agent': stream.user_agent_header || undefined,
      Referer: stream.referer_header || undefined,
      Origin: stream.origin_header || undefined,
    });
    const status = result.status;
    const httpStatus = result.statusCode;
    const errorMessage = result.reason && status !== 'working' ? result.reason : null;
    const latency = result.latencyMs;
    await query(
      `INSERT INTO stream_health_checks (stream_id, status, http_status, latency_ms, error_message)
       VALUES (?, ?, ?, ?, ?)`,
      [id, status, httpStatus, latency, errorMessage],
    );
    await query(
      `UPDATE match_streams SET status = ?, last_status_at = NOW() WHERE id = ?`,
      [status, id],
    );
    await recordAudit({
      adminUserId: request.adminUser.id,
      adminEmail: request.adminUser.email,
      action: 'stream.test',
      entityType: 'match_stream',
      entityId: id,
      newValue: { status, httpStatus, latency, errorMessage },
      ipAddress: request.ip,
      userAgent: request.headers['user-agent'],
    });
    await invalidateStreamCaches(stream.match_external_id);
    return reply.send({
      success: true,
      status,
      http_status: httpStatus,
      latency_ms: latency,
      error: errorMessage,
      playable: result.playable,
      type: result.type,
      final_url: result.finalUrl,
      needs_headers: result.needsHeaders,
      reason: result.reason,
      variants: result.variants,
    });
  });

  fastify.post('/:id/toggle', { preHandler: [requirePermissions('streams.write')] }, async (request, reply) => {
    const rows = await query(`SELECT id, is_active, match_external_id FROM match_streams WHERE id = ?`, [request.params.id]);
    if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const next = rows[0].is_active ? 0 : 1;
    await withAudit(
      request,
      { action: 'stream.toggle', entityType: 'match_stream', entityId: request.params.id, oldValue: rows[0], newValue: { is_active: next } },
      async () => query(`UPDATE match_streams SET is_active = ?, updated_by = ? WHERE id = ?`, [next, request.adminUser.id, request.params.id]),
    );
    await invalidateStreamCaches(rows[0].match_external_id);
    return { success: true, is_active: !!next };
  });

  fastify.post('/:id/cache-clear', { preHandler: [requirePermissions('streams.write')] }, async (request, reply) => {
    const rows = await query(`SELECT match_external_id FROM match_streams WHERE id = ?`, [request.params.id]);
    if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const redis = getRedis();
    const cleared = await redis.del(`match:${rows[0].match_external_id}:streams`, `streams:${rows[0].match_external_id}`);
    await invalidateStreamCaches(rows[0].match_external_id);
    return { success: true, cleared };
  });
 
  fastify.get('/:id/health', { preHandler: [requirePermissions('streams.view')] }, async (request) => {
    const id = request.params.id;
    const rows = await query(
      `SELECT id, status, http_status, latency_ms, error_message, checked_at
         FROM stream_health_checks WHERE stream_id = ?
        ORDER BY checked_at DESC LIMIT 50`,
      [id],
    );
    return { success: true, data: rows };
  });
 
  fastify.get('/servers', { preHandler: [requirePermissions('streams.view')] }, async () => {
    const rows = await query(
      `SELECT s.*, src.name AS source_name
         FROM stream_servers s
    LEFT JOIN stream_sources src ON src.id = s.source_id
        ORDER BY s.name ASC`,
    );
    return { success: true, data: rows };
  });
}
