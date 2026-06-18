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
import {
  invalidateAdminPlayerImageIndex,
  getPlayerImageMode,
  resolvePlayerImage,
  PLAYER_IMAGE_MODES,
  PLAYER_IMAGE_MODE_SETTING_KEY,
} from '../../lib/player-images.js';
import { getPlayerImageUrl } from '../../lib/image-helper.js';
import { CricbuzzProvider } from '../../providers/cricbuzz/index.js';
import {
  fetchPlayerByProviderId,
  fetchTeamByProviderId,
} from '../../lib/provider-fetch.js';

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

  // Fetch a team by provider ID for the admin auto-fill form. Runs through
  // providerManager (DB priority + failover); returns shaped fields + provider.
  fastify.post('/teams/fetch-by-provider-id', { preHandler: [requirePermissions('teams.write')] }, async (request, reply) => {
    const id = String(request.body?.team_id ?? request.body?.external_id ?? request.body?.id ?? '').trim();
    if (!id) return reply.code(400).send({ success: false, error: 'team_id is required' });
    try {
      const result = await fetchTeamByProviderId(id);
      if (!result || !result.data) {
        return reply.code(404).send({ success: false, error: `No team found for ID ${id}` });
      }
      return { success: true, provider: result.provider, data: result.data };
    } catch (err) {
      return reply.code(502).send({ success: false, error: `Provider fetch failed: ${err.message || 'all providers unavailable'}` });
    }
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

  /* =====================================================
   * PLAYERS — image management (admin-managed player photos)
   * Mirrors the teams flag/logo system: operators upload a player photo
   * (stored under /uploads, served publicly) or set a provider image URL, and
   * a global resolution mode (admin_first by default) plus per-player override
   * controls which image the app shows everywhere. enrichPlayerImages applies
   * this to every public response carrying player objects.
   * ===================================================== */
  fastify.get('/players', { preHandler: [requirePermissions('players.view')] }, async (request) => {
    const q = String(request.query?.search || request.query?.q || '').trim();
    const params = [];
    let where = `WHERE COALESCE(is_active, 1) IN (0, 1)`;
    if (q) {
      where = `WHERE (name LIKE ? OR full_name LIKE ? OR external_id LIKE ? OR player_external_id LIKE ?)`;
      const like = `%${q}%`;
      params.push(like, like, like, like);
    }
    const rows = await query(
      `SELECT id, external_id, player_external_id, name, full_name, country, role,
              batting_style, bowling_style,
              image_url, admin_image_url, provider_image_url, image_mode,
              image_updated_at, is_image_active, is_active, team_id,
              created_at, updated_at
         FROM players
         ${where}
        ORDER BY COALESCE(is_active, 1) DESC, name ASC
        LIMIT 2000`,
      params,
    ).catch(() => []);
    const mode = await getPlayerImageMode();
    return {
      success: true,
      globalMode: mode,
      data: rows.map((r) => ({
        ...r,
        is_active: r.is_active !== 0,
        is_image_active: r.is_image_active !== 0,
        resolved_image_url: resolvePlayerImage({
          mode: r.image_mode && r.is_image_active !== 0 ? r.image_mode : mode,
          adminImage: r.admin_image_url,
          providerImage: r.provider_image_url || r.image_url,
        }),
      })),
    };
  });

  // Fetch a player by provider ID for the admin auto-fill form. Runs through
  // providerManager (DB priority + failover); returns shaped fields + provider.
  fastify.post('/players/fetch-by-provider-id', { preHandler: [requirePermissions('players.write')] }, async (request, reply) => {
    const id = String(
      request.body?.provider_player_id ?? request.body?.player_id ?? request.body?.external_id ?? request.body?.id ?? '',
    ).trim();
    if (!id) return reply.code(400).send({ success: false, error: 'player_id is required' });
    try {
      const result = await fetchPlayerByProviderId(id);
      if (!result || !result.data) {
        return reply.code(404).send({ success: false, error: `No player found for ID ${id}` });
      }
      return { success: true, provider: result.provider, data: result.data };
    } catch (err) {
      return reply.code(502).send({ success: false, error: `Provider fetch failed: ${err.message || 'all providers unavailable'}` });
    }
  });

  // Global player-image mode (admin_first | cricbuzz_first | admin_only |
  // cricbuzz_only | initials_only). Stored in app_settings.
  fastify.get('/players/image-mode', { preHandler: [requirePermissions('players.view')] }, async () => {
    const mode = await getPlayerImageMode();
    return { success: true, mode, modes: PLAYER_IMAGE_MODES };
  });

  fastify.put('/players/image-mode', { preHandler: [requirePermissions('players.write')] }, async (request, reply) => {
    const mode = String(request.body?.mode || '').trim().toLowerCase();
    if (!PLAYER_IMAGE_MODES.includes(mode)) {
      return reply.code(400).send({ success: false, error: 'Invalid mode' });
    }
    await withAudit(
      request,
      { action: 'players.imageMode.set', entityType: 'player', newValue: { mode } },
      () => query(
        `INSERT INTO app_settings (setting_key, setting_value, \`group\`, description, updated_by)
         VALUES (?, ?, 'players', 'Global player image resolution mode', ?)
         ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_by = VALUES(updated_by)`,
        [PLAYER_IMAGE_MODE_SETTING_KEY, JSON.stringify(mode), request.adminUser?.id || null],
      ),
    );
    invalidateAdminPlayerImageIndex();
    return { success: true, mode };
  });

  // Upload a player photo (base64 data URL) → returns a public /uploads URL.
  fastify.post(
    '/players/upload-image',
    { preHandler: [requirePermissions('players.write')], bodyLimit: 8 * 1024 * 1024 },
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
          { action: 'player.image.upload', entityType: 'player', newValue: { url, bytes } },
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

  // Bulk: fetch/refresh provider images from Cricbuzz for players that are
  // missing a provider image. Best-effort; never throws.
  fastify.post('/players/refresh-images', { preHandler: [requirePermissions('players.write')] }, async (request) => {
    const onlyMissing = bool(request.body?.onlyMissing, 1) === 1;
    const rows = await query(
      `SELECT id, external_id, player_external_id, metadata, image_url, provider_image_url
         FROM players
        WHERE COALESCE(is_active, 1) = 1
        ${onlyMissing ? `AND (provider_image_url IS NULL OR TRIM(provider_image_url) = '')` : ''}
        LIMIT 2000`,
    ).catch(() => []);
    let updated = 0;
    for (const r of rows) {
      let imageId = null;
      const meta = typeof r.metadata === 'string'
        ? (() => { try { return JSON.parse(r.metadata); } catch { return null; } })()
        : r.metadata;
      if (meta && (meta.faceImageId || meta.imageId)) imageId = meta.faceImageId || meta.imageId;
      const providerUrl = imageId ? getPlayerImageUrl(imageId) : null;
      if (!providerUrl) continue;
      // eslint-disable-next-line no-await-in-loop
      await query(
        `UPDATE players
            SET provider_image_url = ?, image_updated_at = NOW()
          WHERE id = ?`,
        [providerUrl, r.id],
      ).catch(() => null);
      updated += 1;
    }
    invalidateAdminPlayerImageIndex();
    await withAudit(
      request,
      { action: 'players.refreshImages', entityType: 'player', newValue: { scanned: rows.length, updated } },
      async () => null,
    );
    return { success: true, scanned: rows.length, updated };
  });

  // Bulk: apply the global mode to every player (clears per-player overrides).
  fastify.post('/players/apply-global-mode', { preHandler: [requirePermissions('players.write')] }, async (request) => {
    await withAudit(
      request,
      { action: 'players.applyGlobalMode', entityType: 'player' },
      () => query(`UPDATE players SET image_mode = NULL WHERE COALESCE(is_active, 1) = 1`),
    );
    invalidateAdminPlayerImageIndex();
    return { success: true };
  });

  // Bulk: clear all admin uploaded images (confirmation required in body).
  fastify.post('/players/clear-admin-images', { preHandler: [requirePermissions('players.write')] }, async (request, reply) => {
    if (request.body?.confirm !== true) {
      return reply.code(400).send({ success: false, error: 'Confirmation required' });
    }
    const result = await withAudit(
      request,
      { action: 'players.clearAdminImages', entityType: 'player' },
      () => query(`UPDATE players SET admin_image_url = NULL, image_updated_at = NOW() WHERE admin_image_url IS NOT NULL`),
    );
    invalidateAdminPlayerImageIndex();
    return { success: true, affected: result?.affectedRows ?? 0 };
  });

  // Create a player record (admin-defined).
  fastify.post('/players', { preHandler: [requirePermissions('players.write')] }, async (request, reply) => {
    const body = request.body || {};
    const name = String(body.name || '').trim();
    if (!name) return reply.code(400).send({ success: false, message: 'name required' });
    const mode = body.image_mode && PLAYER_IMAGE_MODES.includes(body.image_mode) ? body.image_mode : null;
    const teamId = body.team_id === undefined || body.team_id === null || body.team_id === ''
      ? null
      : Number(body.team_id) || null;
    const result = await withAudit(
      request,
      { action: 'player.create', entityType: 'player', newValue: { name } },
      () => query(
        `INSERT INTO players
           (external_id, player_external_id, name, full_name, country, role,
            batting_style, bowling_style, team_id,
            image_url, admin_image_url, provider_image_url, image_mode,
            is_image_active, is_active, image_updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())`,
        [
          cleanTeamText(body.external_id) || null,
          cleanTeamText(body.player_external_id || body.external_id) || null,
          name,
          cleanTeamText(body.full_name) || null,
          cleanTeamText(body.country) || null,
          cleanTeamText(body.role) || null,
          cleanTeamText(body.batting_style) || null,
          cleanTeamText(body.bowling_style) || null,
          teamId,
          cleanTeamText(body.image_url) || null,
          cleanTeamText(body.admin_image_url) || null,
          cleanTeamText(body.provider_image_url) || null,
          mode,
          bool(body.is_image_active, 1),
          bool(body.is_active, 1),
        ],
      ),
    );
    invalidateAdminPlayerImageIndex();
    return reply.code(201).send({ success: true, data: { id: result.insertId }, id: result.insertId });
  });

  // Update a player. Accepts profile fields and image fields together.
  fastify.put('/players/:id', { preHandler: [requirePermissions('players.write')] }, async (request, reply) => {
    const old = await query(
      `SELECT * FROM players WHERE id = ? OR external_id = ? OR player_external_id = ? LIMIT 1`,
      [request.params.id, request.params.id, request.params.id],
    ).catch(() => []);
    if (!old.length) return reply.code(404).send({ success: false, message: 'Not found' });
    const body = request.body || {};
    const allowed = [
      'name', 'full_name', 'country', 'role', 'batting_style', 'bowling_style',
      'team_id', 'external_id', 'player_external_id',
      'image_url', 'admin_image_url', 'provider_image_url', 'image_mode',
      'is_image_active', 'is_active',
    ];
    const set = [];
    const vals = [];
    for (const k of allowed) {
      if (body[k] === undefined) continue;
      if (k === 'image_mode') {
        const m = body[k] == null || body[k] === ''
          ? null
          : (PLAYER_IMAGE_MODES.includes(body[k]) ? body[k] : undefined);
        if (m === undefined) return reply.code(400).send({ success: false, message: 'Invalid image_mode' });
        set.push('image_mode = ?');
        vals.push(m);
      } else if (k === 'is_image_active' || k === 'is_active') {
        set.push(`${k} = ?`);
        vals.push(bool(body[k], 1));
      } else if (k === 'team_id') {
        set.push('team_id = ?');
        vals.push(body[k] === '' || body[k] === null ? null : Number(body[k]) || null);
      } else {
        set.push(`${k} = ?`);
        vals.push(body[k] === '' ? null : body[k]);
      }
    }
    if (!set.length) return reply.code(400).send({ success: false, message: 'No fields to update' });
    set.push('image_updated_at = NOW()');
    await withAudit(
      request,
      { action: 'player.update', entityType: 'player', entityId: old[0].id, oldValue: old[0], newValue: body },
      () => query(`UPDATE players SET ${set.join(', ')} WHERE id = ?`, [...vals, old[0].id]),
    );
    invalidateAdminPlayerImageIndex();
    return { success: true, data: { id: old[0].id } };
  });

  // Update ONLY a player's image fields (upload URL, provider URL, mode, active).
  fastify.put('/players/:id/image', { preHandler: [requirePermissions('players.write')] }, async (request, reply) => {
    const old = await query(
      `SELECT * FROM players WHERE id = ? OR external_id = ? OR player_external_id = ? LIMIT 1`,
      [request.params.id, request.params.id, request.params.id],
    ).catch(() => []);
    if (!old.length) return reply.code(404).send({ success: false, message: 'Not found' });
    const body = request.body || {};
    const allowed = ['admin_image_url', 'provider_image_url', 'image_url', 'image_mode', 'is_image_active'];
    const set = [];
    const vals = [];
    for (const k of allowed) {
      if (body[k] === undefined) continue;
      if (k === 'image_mode') {
        const m = body[k] == null || body[k] === ''
          ? null
          : (PLAYER_IMAGE_MODES.includes(body[k]) ? body[k] : undefined);
        if (m === undefined) return reply.code(400).send({ success: false, message: 'Invalid image_mode' });
        set.push('image_mode = ?');
        vals.push(m);
      } else if (k === 'is_image_active') {
        set.push('is_image_active = ?');
        vals.push(bool(body[k], 1));
      } else {
        set.push(`${k} = ?`);
        vals.push(body[k] === '' ? null : body[k]);
      }
    }
    if (!set.length) return reply.code(400).send({ success: false, message: 'No image fields to update' });
    set.push('image_updated_at = NOW()');
    await withAudit(
      request,
      { action: 'player.image.update', entityType: 'player', entityId: old[0].id, oldValue: old[0], newValue: body },
      () => query(`UPDATE players SET ${set.join(', ')} WHERE id = ?`, [...vals, old[0].id]),
    );
    invalidateAdminPlayerImageIndex();
    return { success: true, data: { id: old[0].id } };
  });

  // Delete a player. Referencing rows (matches/scorecards) use ON DELETE SET
  // NULL so this is safe; we hard-delete so the player truly disappears.
  fastify.delete('/players/:id', { preHandler: [requirePermissions('players.write')] }, async (request, reply) => {
    const old = await query(
      `SELECT * FROM players WHERE id = ? OR external_id = ? OR player_external_id = ? LIMIT 1`,
      [request.params.id, request.params.id, request.params.id],
    ).catch(() => []);
    if (!old.length) return reply.code(404).send({ success: false, message: 'Not found' });
    await withAudit(
      request,
      { action: 'player.delete', entityType: 'player', entityId: old[0].id, oldValue: old[0] },
      () => query(`DELETE FROM players WHERE id = ?`, [old[0].id]),
    );
    invalidateAdminPlayerImageIndex();
    return { success: true, data: { id: old[0].id } };
  });

  // Remove an admin uploaded image for a single player (keeps provider image).
  fastify.delete('/players/:id/image', { preHandler: [requirePermissions('players.write')] }, async (request, reply) => {
    const old = await query(
      `SELECT * FROM players WHERE id = ? OR external_id = ? OR player_external_id = ? LIMIT 1`,
      [request.params.id, request.params.id, request.params.id],
    ).catch(() => []);
    if (!old.length) return reply.code(404).send({ success: false, message: 'Not found' });
    await withAudit(
      request,
      { action: 'player.image.remove', entityType: 'player', entityId: old[0].id, oldValue: old[0] },
      () => query(`UPDATE players SET admin_image_url = NULL, image_updated_at = NOW() WHERE id = ?`, [old[0].id]),
    );
    invalidateAdminPlayerImageIndex();
    return { success: true, data: { id: old[0].id } };
  });

  // Global player image settings (spec-named aliases of /players/image-mode).
  fastify.get('/player-image-settings', { preHandler: [requirePermissions('players.view')] }, async () => {
    const mode = await getPlayerImageMode();
    return { success: true, data: { mode, modes: PLAYER_IMAGE_MODES, defaultMode: 'admin_first' } };
  });

  fastify.put('/player-image-settings', { preHandler: [requirePermissions('players.write')] }, async (request, reply) => {
    const mode = String(request.body?.mode || '').trim().toLowerCase();
    if (!PLAYER_IMAGE_MODES.includes(mode)) {
      return reply.code(400).send({ success: false, message: 'Invalid mode' });
    }
    await withAudit(
      request,
      { action: 'players.imageSettings.set', entityType: 'player', newValue: { mode } },
      () => query(
        `INSERT INTO app_settings (setting_key, setting_value, \`group\`, description, updated_by)
         VALUES (?, ?, 'players', 'Global player image resolution mode', ?)
         ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_by = VALUES(updated_by)`,
        [PLAYER_IMAGE_MODE_SETTING_KEY, JSON.stringify(mode), request.adminUser?.id || null],
      ),
    );
    invalidateAdminPlayerImageIndex();
    return { success: true, data: { mode } };
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
