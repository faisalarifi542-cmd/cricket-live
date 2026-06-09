/**
 * Additional admin routes not covered by the dedicated route files.
 *
 * Covers: news CRUD, notifications full lifecycle, roles CRUD,
 * user role assignment + password reset, series/teams/players/schedule
 * detail + refresh + cache-clear + feature/hide actions.
 *
 * All routes inherit the standard adminAuth preHandler and require
 * the matching permission. Write actions go through the audit log.
 */
import { adminAuth, requirePermissions } from '../auth.js';
import { withAudit } from '../audit.js';
import { query } from '../../lib/db.js';
import { getRedis } from '../../lib/redis.js';
import { recordNotificationHistory, sendOneSignalNotification } from '../../lib/onesignal.js';
import { PERMISSIONS, ROLE_PERMISSIONS } from '../rbac.js';
import { saveBase64Image } from '../../lib/uploads.js';
import { invalidateAdminTeamLogoIndex } from '../../lib/team-logos.js';
import { CricbuzzProvider } from '../../providers/cricbuzz/index.js';

async function clearPattern(redis, pattern) {
  let cursor = '0';
  let count = 0;
  do {
    // eslint-disable-next-line no-await-in-loop
    const [next, keys] = await redis.scan(cursor, 'MATCH', pattern, 'COUNT', 200);
    cursor = next;
    // eslint-disable-next-line no-await-in-loop
    if (keys.length) count += await redis.del(...keys);
  } while (cursor !== '0');
  return count;
}

function bool(v, fallback = null) {
  if (v === undefined || v === null) return fallback;
  if (typeof v === 'boolean') return v ? 1 : 0;
  if (v === 1 || v === '1' || v === 'true') return 1;
  if (v === 0 || v === '0' || v === 'false') return 0;
  return fallback;
}

function slugifyTeam(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 220);
}

function cleanTeamText(value) {
  const text = String(value || '').trim();
  return text && text !== '-' && text.toLowerCase() !== 'tbd' ? text : '';
}

function normalizeTeamRecord(team = {}) {
  const externalId = cleanTeamText(team.external_id || team.team_id || team.teamId || team.id);
  const name = cleanTeamText(team.name || team.teamName || team.team_name || team.fullName || team.teamFullName);
  const shortName = cleanTeamText(team.short_name || team.shortName || team.teamShortName || team.team_short || team.teamSName || team.abbr);
  const logo = cleanTeamText(team.logo_url || team.logoUrl || team.logo || team.flag || team.imageUrl || team.image_url);
  const country = cleanTeamText(team.country || team.location || team.region);
  const type = cleanTeamText(team.team_type || team.type || team.category) || 'international';
  if (!name && !shortName) return null;
  return {
    external_id: externalId || null,
    name: name || shortName,
    short_name: shortName || null,
    slug: slugifyTeam(name || shortName),
    country: country || null,
    team_type: type,
    cricbuzz_logo_url: logo || null,
  };
}

function addTeamCandidate(map, team) {
  const normalized = normalizeTeamRecord(team);
  if (!normalized) return;
  const key = normalized.external_id
    ? `id:${normalized.external_id}`
    : normalized.short_name
      ? `short:${normalized.short_name.toLowerCase()}`
      : `name:${normalized.name.toLowerCase()}`;
  const existing = map.get(key);
  map.set(key, { ...(existing || {}), ...normalized });
}

async function upsertTeamCandidate(team) {
  const rows = await query(
    `SELECT id, logo_url
       FROM teams
      WHERE (external_id IS NOT NULL AND external_id <> '' AND external_id = ?)
         OR (short_name IS NOT NULL AND short_name <> '' AND LOWER(short_name) = LOWER(?))
         OR LOWER(name) = LOWER(?)
      LIMIT 1`,
    [team.external_id || '', team.short_name || '', team.name],
  ).catch(() => []);

  if (rows.length) {
    await query(
      `UPDATE teams
          SET external_id = COALESCE(?, external_id),
              name = COALESCE(?, name),
              short_name = COALESCE(?, short_name),
              slug = COALESCE(?, slug),
              country = COALESCE(?, country),
              team_type = COALESCE(?, team_type),
              cricbuzz_logo_url = COALESCE(?, cricbuzz_logo_url),
              is_active = COALESCE(is_active, 1)
        WHERE id = ?`,
      [
        team.external_id,
        team.name,
        team.short_name,
        team.slug,
        team.country,
        team.team_type,
        team.cricbuzz_logo_url,
        rows[0].id,
      ],
    );
    return { inserted: 0, updated: 1 };
  }

  await query(
    `INSERT INTO teams (external_id, name, short_name, slug, logo_url, cricbuzz_logo_url, country, team_type, is_active)
     VALUES (?, ?, ?, ?, NULL, ?, ?, ?, 1)`,
    [team.external_id, team.name, team.short_name, team.slug, team.cricbuzz_logo_url, team.country, team.team_type],
  );
  return { inserted: 1, updated: 0 };
}

export default async function extraAdminRoutes(fastify) {
  fastify.addHook('preHandler', adminAuth);

  /* =====================================================
   * NEWS
   * ===================================================== */
  fastify.get('/news/:id', { preHandler: [requirePermissions('news.view')] }, async (request, reply) => {
    const rows = await query(`SELECT * FROM custom_news WHERE id = ?`, [request.params.id]);
    if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });
    return { success: true, data: rows[0] };
  });

  fastify.post('/news', { preHandler: [requirePermissions('news.write')] }, async (request, reply) => {
    const { headline, body, context = null, story_type = 'custom', image_url = null, source = 'CricPro',
      is_featured = 0, is_hidden = 0, sort_order = 100, published_at = null } = request.body || {};
    if (!headline) return reply.code(400).send({ success: false, error: 'headline required' });
    const result = await withAudit(
      request,
      { action: 'news.create', entityType: 'custom_news', newValue: request.body },
      () => query(
        `INSERT INTO custom_news (headline, body, context, story_type, image_url, source, is_featured, is_hidden, sort_order, published_at, created_by)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, CURRENT_TIMESTAMP), ?)`,
        [headline, body, context, story_type, image_url, source, bool(is_featured, 0), bool(is_hidden, 0), Number(sort_order) || 100, published_at, request.adminUser.id],
      ),
    );
    return reply.code(201).send({ success: true, id: result.insertId });
  });

  fastify.put('/news/:id', { preHandler: [requirePermissions('news.write')] }, async (request) => {
    const { headline, body, context, story_type, image_url, source, is_featured, is_hidden, sort_order, published_at } = request.body || {};
    await withAudit(
      request,
      { action: 'news.update', entityType: 'custom_news', entityId: request.params.id, newValue: request.body },
      () => query(
        `UPDATE custom_news SET
            headline = COALESCE(?, headline),
            body = COALESCE(?, body),
            context = COALESCE(?, context),
            story_type = COALESCE(?, story_type),
            image_url = COALESCE(?, image_url),
            source = COALESCE(?, source),
            is_featured = COALESCE(?, is_featured),
            is_hidden = COALESCE(?, is_hidden),
            sort_order = COALESCE(?, sort_order),
            published_at = COALESCE(?, published_at)
          WHERE id = ?`,
        [
          headline ?? null,
          body ?? null,
          context ?? null,
          story_type ?? null,
          image_url ?? null,
          source ?? null,
          bool(is_featured),
          bool(is_hidden),
          sort_order ?? null,
          published_at ?? null,
          request.params.id,
        ],
      ),
    );
    return { success: true };
  });

  fastify.delete('/news/:id', { preHandler: [requirePermissions('news.write')] }, async (request) => {
    await withAudit(
      request,
      { action: 'news.delete', entityType: 'custom_news', entityId: request.params.id },
      () => query(`DELETE FROM custom_news WHERE id = ?`, [request.params.id]),
    );
    return { success: true };
  });

  fastify.post('/news/:id/feature', { preHandler: [requirePermissions('news.write')] }, async (request) => {
    await withAudit(
      request,
      { action: 'news.feature', entityType: 'custom_news', entityId: request.params.id },
      () => query(`UPDATE custom_news SET is_featured = IF(is_featured = 1, 0, 1) WHERE id = ?`, [request.params.id]),
    );
    return { success: true };
  });

  fastify.post('/news/:id/hide', { preHandler: [requirePermissions('news.write')] }, async (request) => {
    await withAudit(
      request,
      { action: 'news.hide', entityType: 'custom_news', entityId: request.params.id },
      () => query(`UPDATE custom_news SET is_hidden = IF(is_hidden = 1, 0, 1) WHERE id = ?`, [request.params.id]),
    );
    return { success: true };
  });

  fastify.post('/news/cache-clear', { preHandler: [requirePermissions('news.write')] }, async () => {
    const deleted = await clearPattern(getRedis(), 'news*');
    return { success: true, deleted };
  });

  /* =====================================================
   * NOTIFICATIONS — update / delete / send
   * ===================================================== */
  fastify.put('/notifications/:id', { preHandler: [requirePermissions('notifications.write')] }, async (request) => {
    const { title, body, image_url, target_type, target_value, deep_link_type, deep_link_value, scheduled_at, status } = request.body || {};
    await withAudit(
      request,
      { action: 'notification.update', entityType: 'push_notification', entityId: request.params.id, newValue: request.body },
      () => query(
        `UPDATE push_notifications SET
            title = COALESCE(?, title),
            body = COALESCE(?, body),
            image_url = COALESCE(?, image_url),
            target_type = COALESCE(?, target_type),
            target_value = COALESCE(?, target_value),
            deep_link_type = COALESCE(?, deep_link_type),
            deep_link_value = COALESCE(?, deep_link_value),
            scheduled_at = COALESCE(?, scheduled_at),
            status = COALESCE(?, status)
          WHERE id = ?`,
        [title ?? null, body ?? null, image_url ?? null, target_type ?? null, target_value ?? null, deep_link_type ?? null, deep_link_value ?? null, scheduled_at ?? null, status ?? null, request.params.id],
      ),
    );
    return { success: true };
  });

  fastify.delete('/notifications/:id', { preHandler: [requirePermissions('notifications.write')] }, async (request) => {
    await withAudit(
      request,
      { action: 'notification.delete', entityType: 'push_notification', entityId: request.params.id },
      () => query(`DELETE FROM push_notifications WHERE id = ?`, [request.params.id]),
    );
    return { success: true };
  });

  fastify.post('/notifications/:id/send', { preHandler: [requirePermissions('notifications.write')] }, async (request, reply) => {
    const rows = await query(`SELECT * FROM push_notifications WHERE id = ?`, [request.params.id]);
    if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const notification = rows[0];
    let providerResult = null;
    await withAudit(
      request,
      { action: 'notification.send', entityType: 'push_notification', entityId: request.params.id },
      async () => {
        providerResult = await sendOneSignalNotification(notification);
        await query(
          `UPDATE push_notifications SET status = 'sent', sent_at = CURRENT_TIMESTAMP, provider_response = ? WHERE id = ?`,
          [JSON.stringify(providerResult.response), request.params.id],
        );
        await query(
          `INSERT INTO notification_campaigns (notification_id, provider, status, sent_count, metadata) VALUES (?, 'onesignal', 'sent', 1, ?)`,
          [request.params.id, JSON.stringify(providerResult.response)],
        ).catch(() => null);
        await recordNotificationHistory({
          notificationId: request.params.id,
          notification,
          payload: providerResult.payload,
          providerResponse: providerResult.response,
          status: 'sent',
        });
      },
    ).catch(async (err) => {
      await query(
        `UPDATE push_notifications SET status = 'failed', error_message = ? WHERE id = ?`,
        [err.message, request.params.id],
      ).catch(() => null);
      await recordNotificationHistory({
        notificationId: request.params.id,
        notification,
        providerResponse: err.providerResponse || null,
        status: 'failed',
        errorMessage: err.message,
      });
      throw err;
    });
    return { success: true, data: providerResult?.response || null };
  });

  /* =====================================================
   * ROLES — create / update / delete (super admin only)
   * ===================================================== */
  fastify.post('/roles', { preHandler: [requirePermissions('roles.write')] }, async (request, reply) => {
    const { slug, name, description, permissions = [] } = request.body || {};
    if (!slug || !name) return reply.code(400).send({ success: false, error: 'slug and name required' });
    const result = await withAudit(
      request,
      { action: 'role.create', entityType: 'admin_role', newValue: request.body },
      async () => {
        const row = await query(
          `INSERT INTO admin_roles (slug, name, description, is_system) VALUES (?, ?, ?, 0)
           ON DUPLICATE KEY UPDATE name = VALUES(name), description = VALUES(description)`,
          [slug, name, description ?? null],
        );
        const idRow = await query(`SELECT id FROM admin_roles WHERE slug = ?`, [slug]);
        const roleId = idRow[0]?.id;
        if (roleId) {
          await query(`DELETE FROM admin_role_permissions WHERE role_id = ?`, [roleId]);
          for (const p of permissions) {
            // eslint-disable-next-line no-await-in-loop
            const perm = await query(`SELECT id FROM admin_permissions WHERE slug = ?`, [p]);
            // eslint-disable-next-line no-await-in-loop
            if (perm[0]?.id) await query(`INSERT INTO admin_role_permissions (role_id, permission_id) VALUES (?, ?)`, [roleId, perm[0].id]);
          }
        }
        return row;
      },
    );
    return reply.code(201).send({ success: true, id: result.insertId || null });
  });

  fastify.put('/roles/:slug', { preHandler: [requirePermissions('roles.write')] }, async (request) => {
    const { name, description, permissions } = request.body || {};
    await withAudit(
      request,
      { action: 'role.update', entityType: 'admin_role', entityId: request.params.slug, newValue: request.body },
      async () => {
        await query(
          `UPDATE admin_roles SET name = COALESCE(?, name), description = COALESCE(?, description) WHERE slug = ?`,
          [name ?? null, description ?? null, request.params.slug],
        );
        if (Array.isArray(permissions)) {
          const idRow = await query(`SELECT id, is_system FROM admin_roles WHERE slug = ?`, [request.params.slug]);
          const roleId = idRow[0]?.id;
          if (roleId) {
            await query(`DELETE FROM admin_role_permissions WHERE role_id = ?`, [roleId]);
            for (const p of permissions) {
              // eslint-disable-next-line no-await-in-loop
              const perm = await query(`SELECT id FROM admin_permissions WHERE slug = ?`, [p]);
              // eslint-disable-next-line no-await-in-loop
              if (perm[0]?.id) await query(`INSERT INTO admin_role_permissions (role_id, permission_id) VALUES (?, ?)`, [roleId, perm[0].id]);
            }
          }
        }
      },
    );
    return { success: true };
  });

  fastify.delete('/roles/:slug', { preHandler: [requirePermissions('roles.write')] }, async (request, reply) => {
    const row = await query(`SELECT is_system FROM admin_roles WHERE slug = ?`, [request.params.slug]);
    if (!row.length) return reply.code(404).send({ success: false, error: 'Not found' });
    if (row[0].is_system) return reply.code(400).send({ success: false, error: 'Cannot delete system role' });
    await withAudit(
      request,
      { action: 'role.delete', entityType: 'admin_role', entityId: request.params.slug },
      () => query(`DELETE FROM admin_roles WHERE slug = ?`, [request.params.slug]),
    );
    return { success: true };
  });

  /* =====================================================
   * USERS — role assignment + password reset
   * ===================================================== */
  fastify.post('/users/:id/roles', { preHandler: [requirePermissions('adminUsers.write')] }, async (request, reply) => {
    const roles = Array.isArray(request.body?.roles) ? request.body.roles : [];
    const userRows = await query(`SELECT id FROM admin_users WHERE id = ?`, [request.params.id]);
    if (!userRows.length) return reply.code(404).send({ success: false, error: 'Not found' });
    await withAudit(
      request,
      { action: 'adminUser.setRoles', entityType: 'admin_user', entityId: request.params.id, newValue: { roles } },
      async () => {
        await query(`DELETE FROM admin_user_roles WHERE user_id = ?`, [request.params.id]);
        for (const slug of roles) {
          // eslint-disable-next-line no-await-in-loop
          const roleRow = await query(`SELECT id FROM admin_roles WHERE slug = ?`, [slug]);
          if (roleRow.length) {
            // eslint-disable-next-line no-await-in-loop
            await query(`INSERT IGNORE INTO admin_user_roles (user_id, role_id) VALUES (?, ?)`, [request.params.id, roleRow[0].id]);
          }
        }
      },
    );
    return { success: true };
  });

  fastify.post('/users/:id/password', { preHandler: [requirePermissions('adminUsers.write')] }, async (request, reply) => {
    const { password } = request.body || {};
    if (!password || password.length < 8) {
      return reply.code(400).send({ success: false, error: 'Password must be at least 8 characters' });
    }
    const bcrypt = await import('bcryptjs');
    const hash = await bcrypt.default.hash(password, 12);
    await withAudit(
      request,
      { action: 'adminUser.resetPassword', entityType: 'admin_user', entityId: request.params.id },
      () => query(`UPDATE admin_users SET password_hash = ? WHERE id = ?`, [hash, request.params.id]),
    );
    return { success: true };
  });

  /* =====================================================
   * SERIES / TEAMS / PLAYERS / SCHEDULE — detail + actions
   * ===================================================== */
  for (const [path, table, idCol, permView, permWrite] of [
    ['/series/:id', 'series', 'series_id', 'series.view', 'series.write'],
    ['/players/:id', 'players', 'player_id', 'players.view', 'players.write'],
  ]) {
    fastify.get(path, { preHandler: [requirePermissions(permView)] }, async (request, reply) => {
      const rows = await query(`SELECT * FROM ${table} WHERE ${idCol} = ? OR id = ? LIMIT 1`, [request.params.id, request.params.id]).catch(() => []);
      if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });
      return { success: true, data: rows[0] };
    });

    fastify.post(`${path}/refresh`, { preHandler: [requirePermissions(permWrite)] }, async (request) => {
      const deleted = await clearPattern(getRedis(), `${table}:${request.params.id}*`);
      await withAudit(request, { action: `${table}.refresh`, entityType: table, entityId: request.params.id }, async () => null);
      return { success: true, deleted };
    });

    fastify.post(`${path}/cache-clear`, { preHandler: [requirePermissions(permWrite)] }, async (request) => {
      const deleted = await clearPattern(getRedis(), `${table}:${request.params.id}*`);
      await withAudit(request, { action: `${table}.cacheClear`, entityType: table, entityId: request.params.id }, async () => null);
      return { success: true, deleted };
    });
  }

  fastify.post('/series/:id/feature', { preHandler: [requirePermissions('series.write')] }, async (request) => {
    await withAudit(
      request,
      { action: 'series.feature', entityType: 'series', entityId: request.params.id },
      () => query(
        `INSERT INTO featured_series (series_external_id, is_active, sort_order)
         VALUES (?, 1, 100)
         ON DUPLICATE KEY UPDATE is_active = 1`,
        [request.params.id],
      ).catch(() => null),
    );
    return { success: true };
  });

  fastify.post('/series/:id/hide', { preHandler: [requirePermissions('series.write')] }, async (request) => {
    await withAudit(
      request,
      { action: 'series.hide', entityType: 'series', entityId: request.params.id, newValue: request.body },
      () => query(
        `UPDATE featured_series SET is_active = 0 WHERE series_external_id = ?`,
        [request.params.id],
      ).catch(() => null),
    );
    return { success: true };
  });

  /* =====================================================
   * TEAMS — flag/logo management (admin-managed server logos)
   * Lets operators upload a team flag (stored under /uploads and served
   * publicly) and persist its URL on the team record so series/matches/home
   * responses carry a server logo the app prefers over local fallbacks.
   * ===================================================== */
  fastify.get('/teams', { preHandler: [requirePermissions('teams.view')] }, async () => {
    const rows = await query(
      `SELECT id, external_id, name, short_name, slug, country, logo_url,
              cricbuzz_logo_url, team_type, is_active, created_at, updated_at
         FROM teams
        ORDER BY is_active DESC, name ASC
        LIMIT 1000`,
    ).catch(() => []);
    return { success: true, data: rows.map((r) => ({ ...r, is_active: r.is_active !== 0 })) };
  });

  fastify.get('/teams/:id', { preHandler: [requirePermissions('teams.view')] }, async (request, reply) => {
    const rows = await query(
      `SELECT id, external_id, name, short_name, slug, country, logo_url,
              cricbuzz_logo_url, team_type, is_active, created_at, updated_at
         FROM teams
        WHERE id = ? OR external_id = ? OR LOWER(short_name) = LOWER(?)
        LIMIT 1`,
      [request.params.id, request.params.id, request.params.id],
    ).catch(() => []);
    if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });
    return { success: true, data: { ...rows[0], is_active: rows[0].is_active !== 0 } };
  });

  fastify.post('/teams/sync-from-api', { preHandler: [requirePermissions('teams.write')] }, async (request) => {
    const candidates = new Map();
    const addMatchTeams = (matches = []) => {
      for (const match of Array.isArray(matches) ? matches : []) {
        addTeamCandidate(candidates, match?.team1);
        addTeamCandidate(candidates, match?.team2);
        for (const team of Array.isArray(match?.teams) ? match.teams : []) addTeamCandidate(candidates, team);
      }
    };

    const dbMatches = await query(
      `SELECT team1_id, team2_id, team1_name, team2_name, team1_short, team2_short,
              team1_logo_url, team2_logo_url
         FROM matches
        ORDER BY start_time DESC
        LIMIT 300`,
    ).catch(() => []);
    for (const match of dbMatches) {
      addTeamCandidate(candidates, {
        external_id: match.team1_id,
        name: match.team1_name,
        short_name: match.team1_short,
        logo_url: match.team1_logo_url,
      });
      addTeamCandidate(candidates, {
        external_id: match.team2_id,
        name: match.team2_name,
        short_name: match.team2_short,
        logo_url: match.team2_logo_url,
      });
    }

    const provider = new CricbuzzProvider();
    for (const loader of [
      () => provider.getLiveMatches(),
      () => provider.getUpcomingMatches(),
      () => provider.getRecentMatches(),
    ]) {
      try {
        const result = await loader();
        addMatchTeams(Array.isArray(result?.data) ? result.data : Array.isArray(result) ? result : []);
      } catch {
        // Best-effort; DB matches still seed the list when provider is unavailable.
      }
    }

    let inserted = 0;
    let updated = 0;
    for (const team of candidates.values()) {
      const result = await upsertTeamCandidate(team);
      inserted += result.inserted;
      updated += result.updated;
    }
    invalidateAdminTeamLogoIndex();
    await withAudit(
      request,
      { action: 'teams.syncFromApi', entityType: 'team', newValue: { candidates: candidates.size, inserted, updated } },
      async () => null,
    );
    return { success: true, candidates: candidates.size, inserted, updated };
  });

  fastify.post(
    '/teams/upload-flag',
    { preHandler: [requirePermissions('teams.write')], bodyLimit: 8 * 1024 * 1024 },
    async (request, reply) => {
      const body = request.body || {};
      const data = body.dataUrl || body.data || body.image || '';
      try {
        const { relativeUrl, bytes } = saveBase64Image(data, body.mimeType || '');
        const proto = request.headers['x-forwarded-proto'] || request.protocol || 'https';
        const host = request.headers['x-forwarded-host'] || request.headers.host;
        const url = host ? `${proto}://${host}${relativeUrl}` : relativeUrl;
        await withAudit(
          request,
          { action: 'team.flag.upload', entityType: 'team', newValue: { url, bytes } },
          async () => null,
        );
        return reply.code(201).send({ success: true, url, relativeUrl, bytes });
      } catch (err) {
        return reply
          .code(err.statusCode || 500)
          .send({ success: false, error: err.message || 'Upload failed' });
      }
    },
  );

  fastify.post('/teams', { preHandler: [requirePermissions('teams.write')] }, async (request, reply) => {
    const body = request.body || {};
    const name = String(body.name || '').trim();
    if (!name) return reply.code(400).send({ success: false, error: 'name required' });
    const shortName = cleanTeamText(body.short_name || body.shortName);
    const slug = cleanTeamText(body.slug) || slugifyTeam(name);
    const result = await withAudit(
      request,
      { action: 'team.create', entityType: 'team', newValue: { name } },
      () => query(
        `INSERT INTO teams (external_id, name, short_name, slug, logo_url, cricbuzz_logo_url, country, team_type, is_active)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          cleanTeamText(body.external_id) || null,
          name,
          shortName || null,
          slug || null,
          cleanTeamText(body.logo_url) || null,
          cleanTeamText(body.cricbuzz_logo_url) || null,
          cleanTeamText(body.country) || null,
          cleanTeamText(body.team_type || body.type) || 'international',
          bool(body.is_active, 1),
        ],
      ),
    );
    invalidateAdminTeamLogoIndex();
    return reply.code(201).send({ success: true, id: result.insertId });
  });

  fastify.put('/teams/:id', { preHandler: [requirePermissions('teams.write')] }, async (request, reply) => {
    const old = await query(`SELECT * FROM teams WHERE id = ? OR external_id = ? LIMIT 1`, [request.params.id, request.params.id]).catch(() => []);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const body = request.body || {};
    const allowed = ['external_id', 'name', 'short_name', 'slug', 'logo_url', 'cricbuzz_logo_url', 'country', 'team_type', 'is_active'];
    const set = [];
    const vals = [];
    for (const k of allowed) {
      if (body[k] !== undefined) {
        set.push(`${k} = ?`);
        vals.push(k === 'is_active' ? bool(body[k], 1) : body[k]);
      }
    }
    if (body.name !== undefined && body.slug === undefined) {
      set.push('slug = COALESCE(slug, ?)');
      vals.push(slugifyTeam(body.name));
    }
    if (!set.length) return reply.code(400).send({ success: false, error: 'No fields to update' });
    await withAudit(
      request,
      { action: 'team.update', entityType: 'team', entityId: old[0].id, oldValue: old[0], newValue: body },
      () => query(`UPDATE teams SET ${set.join(', ')} WHERE id = ?`, [...vals, old[0].id]),
    );
    invalidateAdminTeamLogoIndex();
    return { success: true };
  });

  fastify.delete('/teams/:id', { preHandler: [requirePermissions('teams.write')] }, async (request, reply) => {
    const old = await query(`SELECT * FROM teams WHERE id = ? OR external_id = ? LIMIT 1`, [request.params.id, request.params.id]).catch(() => []);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    await withAudit(
      request,
      { action: 'team.disable', entityType: 'team', entityId: old[0].id, oldValue: old[0], newValue: { is_active: 0 } },
      () => query(`UPDATE teams SET is_active = 0 WHERE id = ?`, [old[0].id]),
    );
    invalidateAdminTeamLogoIndex();
    return { success: true };
  });

  fastify.post('/schedule/refresh', { preHandler: [requirePermissions('schedule.write')] }, async (request) => {
    const deleted = await clearPattern(getRedis(), 'schedule*');
    await withAudit(request, { action: 'schedule.refresh', entityType: 'schedule' }, async () => null);
    return { success: true, deleted };
  });

  fastify.post('/schedule/cache-clear', { preHandler: [requirePermissions('schedule.write')] }, async (request) => {
    const deleted = await clearPattern(getRedis(), 'schedule*');
    await withAudit(request, { action: 'schedule.cacheClear', entityType: 'schedule' }, async () => null);
    return { success: true, deleted };
  });

  /* =====================================================
   * PERMISSIONS METADATA — for role editor in admin UI
   * ===================================================== */
  fastify.get('/permissions', { preHandler: [requirePermissions('roles.view')] }, async () => ({
    success: true,
    data: Object.entries(PERMISSIONS).map(([slug, description]) => ({ slug, description })),
    rolePermissions: ROLE_PERMISSIONS,
  }));
}
