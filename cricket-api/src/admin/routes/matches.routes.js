/**
 * Admin Matches Manager:
 *   - Lists matches from the existing `matches` table, merged with
 *     match_overrides + the latest stream status from match_streams.
 *   - Allows display label / admin note / hide / feature toggles via
 *     match_overrides, NEVER mutating the real `matches` row.
 *   - Provides a refresh hook that just clears the relevant Redis keys
 *     (the workers will repopulate).
 */
import { adminAuth, requirePermissions } from '../auth.js';
import { withAudit } from '../audit.js';
import { query } from '../../lib/db.js';
import { getRedis } from '../../lib/redis.js';
import { fetchMatchByProviderId } from '../../lib/provider-fetch.js';
 
const STATUS_TABS = new Set(['live', 'upcoming', 'finished', 'all']);
 
export default async function matchAdminRoutes(fastify) {
  fastify.addHook('preHandler', adminAuth);
 
  fastify.get('/', { preHandler: [requirePermissions('matches.view')] }, async (request) => {
    const { tab = 'all', q, format, series_id, from, to, limit = '100' } = request.query;
    if (!STATUS_TABS.has(tab)) {
      return { success: false, error: 'invalid tab' };
    }
    const where = [];
    const params = [];
    if (tab === 'live') {
      where.push("m.status IN ('live','in_progress','innings_break')");
    } else if (tab === 'upcoming') {
      where.push("m.status IN ('upcoming','scheduled')");
    } else if (tab === 'finished') {
      where.push("m.status IN ('finished','complete','completed','abandoned')");
    }
    if (q) {
      where.push('(m.external_id LIKE ? OR m.status_text LIKE ? OR s.name LIKE ?)');
      const like = `%${q}%`;
      params.push(like, like, like);
    }
    if (format) { where.push('m.match_format = ?'); params.push(format); }
    if (series_id) { where.push('m.series_id = ?'); params.push(series_id); }
    if (from) { where.push('m.start_time >= ?'); params.push(from); }
    if (to) { where.push('m.start_time <= ?'); params.push(to); }
    const lim = Math.min(parseInt(limit, 10) || 100, 500);
    const rows = await query(
      `SELECT m.id, m.external_id, m.match_format, m.match_type, m.status, m.status_text,
              m.start_time, m.venue, m.series_id, s.name AS series_name,
              o.display_label, o.admin_note, o.is_hidden, o.is_featured,
              (SELECT COUNT(*) FROM match_streams ms WHERE ms.match_external_id = m.external_id AND ms.is_active = 1) AS active_streams
         FROM matches m
    LEFT JOIN series s ON s.id = m.series_id
    LEFT JOIN match_overrides o ON o.match_external_id = m.external_id
         ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
        ORDER BY COALESCE(m.start_time, m.created_at) DESC
        LIMIT ${lim}`,
      params,
    );
    return {
      success: true,
      data: rows.map((r) => ({
        ...r,
        is_hidden: !!r.is_hidden,
        is_featured: !!r.is_featured,
        active_streams: Number(r.active_streams || 0),
      })),
    };
  });
 
  // Fetch a match by provider ID for the admin auto-fill / preview tool. Runs
  // through providerManager (DB priority + failover). Static path is declared
  // before /:externalId so Fastify routes it here, not as an external id.
  fastify.post('/fetch-by-provider-id', { preHandler: [requirePermissions('matches.write')] }, async (request, reply) => {
    const id = String(request.body?.match_id ?? request.body?.external_id ?? request.body?.id ?? '').trim();
    if (!id) return reply.code(400).send({ success: false, error: 'match_id is required' });
    try {
      const result = await fetchMatchByProviderId(id);
      if (!result || !result.data) {
        return reply.code(404).send({ success: false, error: `No match found for ID ${id}` });
      }
      return { success: true, provider: result.provider, data: result.data };
    } catch (err) {
      return reply.code(502).send({ success: false, error: `Provider fetch failed: ${err.message || 'all providers unavailable'}` });
    }
  });

  fastify.get('/:externalId', { preHandler: [requirePermissions('matches.view')] }, async (request, reply) => {
    const rows = await query(
      `SELECT m.*, s.name AS series_name,
              o.display_label, o.admin_note, o.is_hidden, o.is_featured
         FROM matches m
    LEFT JOIN series s ON s.id = m.series_id
    LEFT JOIN match_overrides o ON o.match_external_id = m.external_id
        WHERE m.external_id = ? LIMIT 1`,
      [request.params.externalId],
    );
    if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const m = rows[0];
    const streams = await query(
      `SELECT id, title, quality, label, language, server_name, stream_type, status,
              is_active, is_premium, priority, last_status_at, updated_at
         FROM match_streams WHERE match_external_id = ? ORDER BY priority ASC, id ASC`,
      [m.external_id],
    );
    return {
      success: true,
      data: {
        ...m,
        is_hidden: !!m.is_hidden,
        is_featured: !!m.is_featured,
        streams: streams.map((s) => ({ ...s, is_active: !!s.is_active, is_premium: !!s.is_premium })),
      },
    };
  });
 
  fastify.put('/:externalId/override', { preHandler: [requirePermissions('matches.write')] }, async (request, reply) => {
    const externalId = request.params.externalId;
    const { display_label, admin_note, is_hidden, is_featured } = request.body || {};
    const old = await query(`SELECT * FROM match_overrides WHERE match_external_id = ?`, [externalId]);
    await withAudit(
      request,
      {
        action: 'match.override',
        entityType: 'match_override',
        entityId: externalId,
        oldValue: old[0] || null,
        newValue: { display_label, admin_note, is_hidden, is_featured },
      },
      async () =>
        query(
          `INSERT INTO match_overrides (match_external_id, display_label, admin_note, is_hidden, is_featured, created_by, updated_by)
           VALUES (?, ?, ?, ?, ?, ?, ?)
           ON DUPLICATE KEY UPDATE
             display_label = COALESCE(VALUES(display_label), display_label),
             admin_note    = COALESCE(VALUES(admin_note), admin_note),
             is_hidden     = COALESCE(VALUES(is_hidden), is_hidden),
             is_featured   = COALESCE(VALUES(is_featured), is_featured),
             updated_by    = VALUES(updated_by)`,
          [
            externalId,
            display_label ?? null,
            admin_note ?? null,
            is_hidden === undefined ? null : is_hidden ? 1 : 0,
            is_featured === undefined ? null : is_featured ? 1 : 0,
            request.adminUser.id,
            request.adminUser.id,
          ],
        ),
    );
    return { success: true };
  });

  fastify.post('/:externalId/feature', { preHandler: [requirePermissions('matches.write')] }, async (request) => {
    request.body = { ...(request.body || {}), is_featured: true };
    const old = await query(`SELECT * FROM match_overrides WHERE match_external_id = ?`, [request.params.externalId]);
    await withAudit(
      request,
      { action: 'match.feature', entityType: 'match_override', entityId: request.params.externalId, oldValue: old[0] || null, newValue: request.body },
      async () => query(
        `INSERT INTO match_overrides (match_external_id, is_featured, created_by, updated_by)
         VALUES (?, 1, ?, ?)
         ON DUPLICATE KEY UPDATE is_featured = 1, updated_by = VALUES(updated_by)`,
        [request.params.externalId, request.adminUser.id, request.adminUser.id],
      ),
    );
    return { success: true };
  });

  fastify.post('/:externalId/hide', { preHandler: [requirePermissions('matches.write')] }, async (request) => {
    const hidden = request.body?.hidden === false ? 0 : 1;
    const old = await query(`SELECT * FROM match_overrides WHERE match_external_id = ?`, [request.params.externalId]);
    await withAudit(
      request,
      { action: hidden ? 'match.hide' : 'match.unhide', entityType: 'match_override', entityId: request.params.externalId, oldValue: old[0] || null, newValue: { is_hidden: hidden } },
      async () => query(
        `INSERT INTO match_overrides (match_external_id, is_hidden, created_by, updated_by)
         VALUES (?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE is_hidden = VALUES(is_hidden), updated_by = VALUES(updated_by)`,
        [request.params.externalId, hidden, request.adminUser.id, request.adminUser.id],
      ),
    );
    return { success: true };
  });
 
  fastify.post('/:externalId/refresh', { preHandler: [requirePermissions('matches.refresh')] }, async (request) => {
    const externalId = request.params.externalId;
    const redis = getRedis();
    const keys = [
      `match:${externalId}`,
      `match:${externalId}:scorecard`,
      `match:${externalId}:commentary`,
      `match:${externalId}:overs`,
    ];
    let cleared = 0;
    for (const k of keys) {
      cleared += (await redis.del(k)) || 0;
    }
    await query(
      `INSERT INTO cache_events (event_type, cache_key, details, triggered_by)
       VALUES ('invalidate', ?, ?, ?)`,
      [`match:${externalId}:*`, JSON.stringify({ cleared, keys }), request.adminUser.id],
    );
    return { success: true, cleared };
  });

  fastify.post('/:externalId/cache-clear', { preHandler: [requirePermissions('matches.refresh')] }, async (request) => {
    const externalId = request.params.externalId;
    const redis = getRedis();
    const keys = await redis.keys(`*${externalId}*`);
    const cleared = keys.length ? await redis.del(...keys) : 0;
    return { success: true, cleared };
  });
}
