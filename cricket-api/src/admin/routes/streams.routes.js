import { adminAuth, requirePermissions } from '../auth.js';
import { withAudit, recordAudit } from '../audit.js';
import { query } from '../../lib/db.js';
import axios from 'axios';
import { clearDataCache } from '../../lib/data-control.js';
import { getRedis, KEYS } from '../../lib/redis.js';
import { recordNotificationHistory, sendOneSignalNotification } from '../../lib/onesignal.js';
 
const ALLOWED_QUALITY = new Set(['AUTO', 'FHD', 'HD', 'SD']);
const ALLOWED_TYPE = new Set(['hls', 'dash', 'mpd', 'iframe', 'external']);
const ALLOWED_STATUS = new Set(['unknown', 'working', 'slow', 'down']);
 
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
  if (out.stream_type === 'mpd') out.stream_type = 'dash';
  if (!isUpdate) {
    if (!out.match_external_id) throw Object.assign(new Error('match_external_id required'), { statusCode: 400 });
    if (!out.stream_url) throw Object.assign(new Error('stream_url required'), { statusCode: 400 });
    out.quality ??= 'AUTO';
    out.stream_type ??= 'hls';
    out.is_active ??= 1;
    out.is_premium ??= 0;
    out.priority ??= 100;
    out.status ??= 'unknown';
  }
  if ('is_active' in out) out.is_active = out.is_active ? 1 : 0;
  if ('is_premium' in out) out.is_premium = out.is_premium ? 1 : 0;
  if ('requires_reward_ad' in out) out.requires_reward_ad = out.requires_reward_ad ? 1 : 0;
  if ('requires_login' in out) out.requires_login = out.requires_login ? 1 : 0;
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

async function sendStreamNotification(row) {
  if (!row?.match_external_id) return null;
  const notification = {
    title: row.match_title || row.title || 'Live stream is available',
    body: `Watch live cricket now on CricPro.`,
    target_type: 'all',
    deep_link_type: 'live_stream',
    deep_link_value: row.match_external_id,
    payload: {
      type: 'live_stream',
      matchId: String(row.match_external_id),
      deepLink: `cricpro://match/${row.match_external_id}/live`,
    },
  };
  const result = await sendOneSignalNotification(notification);
  await recordNotificationHistory({
    notification,
    payload: result.payload,
    providerResponse: result.response,
    status: 'sent',
  });
  return result.response;
}
 
export default async function streamsRoutes(fastify) {
  fastify.addHook('preHandler', adminAuth);
 
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
    return { success: true, data: rowToDto(rows[0]) };
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
    if (request.body?.send_push_now && row[0]?.is_active) {
      await sendStreamNotification(row[0]).catch(() => null);
    }
    return reply.code(201).send({ success: true, data: rowToDto(row[0]) });
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
    if (request.body?.send_push_now && row[0]?.is_active) {
      await sendStreamNotification(row[0]).catch(() => null);
    }
    return reply.send({ success: true, data: rowToDto(row[0]) });
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
    const headers = {
      ...(stream.user_agent_header ? { 'User-Agent': stream.user_agent_header } : {}),
      ...(stream.referer_header ? { Referer: stream.referer_header } : {}),
    };
    const start = Date.now();
    let status = 'down';
    let httpStatus = null;
    let errorMessage = null;
    try {
      const res = await axios.head(stream.stream_url, {
        headers,
        timeout: 8000,
        validateStatus: () => true,
        maxRedirects: 5,
      });
      httpStatus = res.status;
      if (res.status >= 200 && res.status < 400) status = 'working';
      else if (res.status >= 400 && res.status < 500) status = 'down';
      else status = 'slow';
    } catch (err) {
      errorMessage = err.message;
      status = 'down';
    }
    const latency = Date.now() - start;
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
    return reply.send({ success: true, status, http_status: httpStatus, latency_ms: latency, error: errorMessage });
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
