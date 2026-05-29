import os from 'node:os';
import authRoutes from './routes/auth.routes.js';
import apiKeyRoutes from './routes/api-keys.routes.js';
import homepageRoutes from './routes/homepage.routes.js';
import matchAdminRoutes from './routes/matches.routes.js';
import providerRoutes from './routes/providers.routes.js';
import settingsRoutes from './routes/settings.routes.js';
import streamsRoutes from './routes/streams.routes.js';
import extraRoutes from './routes/extra.routes.js';
import dataControlRoutes from './routes/data-control.routes.js';
import { adminAuth, requirePermissions } from './auth.js';
import { withAudit } from './audit.js';
import { PERMISSIONS, ROLE_DEFINITIONS, ROLE_PERMISSIONS } from './rbac.js';
import { query } from '../lib/db.js';
import { getRedis } from '../lib/redis.js';
import { getCacheStats } from '../lib/data-control.js';
import providerManager from '../providers/provider-manager.js';

const DEFAULT_SETTINGS = {
  appName: 'CricPro',
  appEnvironment: process.env.NODE_ENV || 'production',
  appMaintenanceMode: false,
  maintenanceTitle: 'Maintenance in progress',
  maintenanceMessage: 'CricPro is being tuned. Please check back soon.',
  forceUpdateEnabled: false,
  enableLiveScores: true,
  enableLiveStreaming: true,
  enableNews: true,
  enableRankings: true,
  enableSchedule: true,
  enableSeries: true,
  enableNotifications: true,
  enableAds: false,
  defaultHomeTab: 'live',
  defaultStreamQuality: 'AUTO',
  streamUnavailableMessage: 'Live stream will be available closer to match time.',
  liveScoreRefreshSeconds: 5,
  liveMatchesRefreshSeconds: 10,
  liveLineRefreshSeconds: 5,
  scorecardRefreshSeconds: 30,
  commentaryRefreshSeconds: 30,
  oversRefreshSeconds: 20,
  scheduleRefreshMinutes: 5,
  newsRefreshMinutes: 5,
  homeRefreshSeconds: 30,
  primaryColor: '#06b6d4',
  accentColor: '#3b82f6',
};

function parseSettingValue(value) {
  if (value == null) return null;
  if (typeof value !== 'string') return value;
  try { return JSON.parse(value); } catch { return value; }
}

function safeJson(value) {
  return value == null ? null : JSON.stringify(value);
}

async function getSettingsMap(publicOnly = false) {
  const where = publicOnly ? 'WHERE is_public = 1 OR is_public IS NULL' : '';
  const rows = await query(`SELECT setting_key, setting_value FROM app_settings ${where}`);
  return rows.reduce((acc, row) => {
    acc[row.setting_key] = parseSettingValue(row.setting_value);
    return acc;
  }, { ...DEFAULT_SETTINGS });
}

async function clearPattern(redis, pattern) {
  let cursor = '0';
  let count = 0;
  do {
    const [next, keys] = await redis.scan(cursor, 'MATCH', pattern, 'COUNT', 200);
    cursor = next;
    if (keys.length) count += await redis.del(...keys);
  } while (cursor !== '0');
  return count;
}

export default async function adminPanelRoutes(fastify) {
  await fastify.register(authRoutes, { prefix: '/admin' });
  await fastify.register(matchAdminRoutes, { prefix: '/admin/matches' });
  await fastify.register(streamsRoutes, { prefix: '/admin/streams' });
  await fastify.register(providerRoutes, { prefix: '/admin/providers' });
  await fastify.register(apiKeyRoutes, { prefix: '/admin/api-keys' });
  await fastify.register(settingsRoutes, { prefix: '/admin/app-settings' });
  await fastify.register(homepageRoutes, { prefix: '/admin/home-config' });
  await fastify.register(dataControlRoutes, { prefix: '/admin/data-control' });
  await fastify.register(extraRoutes, { prefix: '/admin' });

  fastify.get('/admin/dashboard', { preHandler: [adminAuth, requirePermissions('dashboard.view')] }, async () => {
    const redis = getRedis();
    const [redisKeys, matchRows, streamRows, auditRows] = await Promise.all([
      redis.dbsize().catch(() => 0),
      query(`SELECT status, COUNT(*) count FROM matches GROUP BY status`).catch(() => []),
      query(`SELECT status, COUNT(*) count FROM match_streams GROUP BY status`).catch(() => []),
      query(`SELECT action, admin_email, entity_type, entity_id, created_at FROM admin_audit_logs ORDER BY created_at DESC LIMIT 10`).catch(() => []),
    ]);
    const matchCounts = Object.fromEntries(matchRows.map((r) => [r.status, Number(r.count)]));
    const streamCounts = Object.fromEntries(streamRows.map((r) => [r.status || 'unknown', Number(r.count)]));
    return {
      success: true,
      data: {
        cards: {
          liveMatches: matchCounts.live || matchCounts.in_progress || 0,
          upcomingMatches: matchCounts.upcoming || matchCounts.scheduled || 0,
          finishedMatches: matchCounts.finished || matchCounts.completed || 0,
          activeStreams: Object.values(streamCounts).reduce((a, b) => a + b, 0),
          brokenStreams: streamCounts.down || 0,
          redisKeys,
          uptime: process.uptime(),
          maintenanceMode: (await getSettingsMap(true)).appMaintenanceMode,
        },
        providers: providerManager.getHealthStatus(),
        recentActions: auditRows,
      },
    };
  });

  fastify.get('/admin/stats', { preHandler: [adminAuth, requirePermissions('dashboard.view')] }, async () => {
    const redis = getRedis();
    return {
      success: true,
      data: {
        uptime: process.uptime(),
        nodeVersion: process.version,
        memory: process.memoryUsage(),
        cpuLoad: os.loadavg(),
        redis: { status: redis.status, keys: await redis.dbsize().catch(() => 0) },
        providers: providerManager.getHealthStatus(),
      },
    };
  });

  fastify.get('/admin/health', { preHandler: [adminAuth, requirePermissions('health.view')] }, async () => ({
    success: true,
    data: {
      api: 'ok',
      redis: getRedis().status,
      mysql: 'ok',
      websocket: 'enabled',
      uptime: process.uptime(),
      memory: process.memoryUsage(),
      providers: providerManager.getHealthStatus(),
    },
  }));

  fastify.get('/admin/logs', { preHandler: [adminAuth, requirePermissions('health.view')] }, async (request) => {
    const { level, q, limit = '100' } = request.query;
    const where = [];
    const params = [];
    if (level) { where.push('level = ?'); params.push(level); }
    if (q) { where.push('(message LIKE ? OR endpoint LIKE ? OR provider LIKE ?)'); params.push(`%${q}%`, `%${q}%`, `%${q}%`); }
    const rows = await query(`SELECT * FROM system_logs ${where.length ? `WHERE ${where.join(' AND ')}` : ''} ORDER BY created_at DESC LIMIT ${Math.min(Number(limit) || 100, 500)}`, params).catch(() => []);
    return { success: true, data: rows };
  });

  fastify.get('/admin/cache/stats', { preHandler: [adminAuth, requirePermissions('cache.view')] }, async () => {
    const redis = getRedis();
    const appStats = await getCacheStats();
    return {
      success: true,
      data: {
        status: redis.status,
        keys: await redis.dbsize().catch(() => 0),
        info: await redis.info('stats').catch(() => ''),
        ...appStats,
      },
    };
  });

  fastify.post('/admin/cache/flush', { preHandler: [adminAuth, requirePermissions('cache.write')] }, async (request) => {
    const redis = getRedis();
    await withAudit(request, { action: 'cache.flush', entityType: 'cache' }, async () => redis.flushdb());
    return { success: true };
  });

  fastify.post('/admin/cache/flush-prefix', { preHandler: [adminAuth, requirePermissions('cache.write')] }, async (request, reply) => {
    const { prefix } = request.body || {};
    if (!prefix) return reply.code(400).send({ success: false, error: 'prefix required' });
    const deleted = await withAudit(request, { action: 'cache.flushPrefix', entityType: 'cache', entityId: prefix }, async () => clearPattern(getRedis(), `${prefix}*`));
    return { success: true, deleted };
  });

  for (const [path, pattern] of [
    ['/admin/cache/flush-match/:matchId', (p) => `*${p.matchId}*`],
    ['/admin/cache/flush-series/:seriesId', (p) => `*${p.seriesId}*`],
    ['/admin/cache/warm-home', () => 'home-config'],
    ['/admin/cache/warm-match/:matchId', (p) => `match:${p.matchId}*`],
    ['/admin/cache/warm-schedule', () => 'schedule*'],
  ]) {
    fastify.post(path, { preHandler: [adminAuth, requirePermissions('cache.write')] }, async (request) => {
      const deleted = await clearPattern(getRedis(), pattern(request.params || {}));
      return { success: true, deleted };
    });
  }

  fastify.get('/admin/audit-logs', { preHandler: [adminAuth, requirePermissions('audit.view')] }, async (request) => {
    const { q, action, entityType, limit = '100' } = request.query;
    const where = [];
    const params = [];
    if (action) { where.push('action = ?'); params.push(action); }
    if (entityType) { where.push('entity_type = ?'); params.push(entityType); }
    if (q) { where.push('(admin_email LIKE ? OR action LIKE ? OR entity_id LIKE ?)'); params.push(`%${q}%`, `%${q}%`, `%${q}%`); }
    const rows = await query(`SELECT * FROM admin_audit_logs ${where.length ? `WHERE ${where.join(' AND ')}` : ''} ORDER BY created_at DESC LIMIT ${Math.min(Number(limit) || 100, 500)}`, params);
    return { success: true, data: rows };
  });

  fastify.get('/admin/roles', { preHandler: [adminAuth, requirePermissions('roles.view')] }, async () => ({
    success: true,
    data: Object.entries(ROLE_DEFINITIONS).map(([slug, role]) => ({ slug, ...role, permissions: ROLE_PERMISSIONS[slug] || [] })),
    permissions: PERMISSIONS,
  }));

  fastify.get('/admin/users', { preHandler: [adminAuth, requirePermissions('adminUsers.view')] }, async () => {
    const rows = await query(`SELECT id, name, email, is_active, last_login_at, created_at, updated_at FROM admin_users ORDER BY created_at DESC`);
    return { success: true, data: rows.map((r) => ({ ...r, is_active: !!r.is_active })) };
  });

  fastify.get('/admin/users/:id', { preHandler: [adminAuth, requirePermissions('adminUsers.view')] }, async (request, reply) => {
    const rows = await query(`SELECT id, name, email, is_active, last_login_at, created_at, updated_at FROM admin_users WHERE id = ?`, [request.params.id]);
    if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });
    return { success: true, data: { ...rows[0], is_active: !!rows[0].is_active } };
  });

  fastify.post('/admin/users', { preHandler: [adminAuth, requirePermissions('adminUsers.write')] }, async (request, reply) => {
    const bcrypt = await import('bcryptjs');
    const { name, email, password, role = 'admin' } = request.body || {};
    if (!name || !email || !password) return reply.code(400).send({ success: false, error: 'name, email, password required' });
    const hash = await bcrypt.default.hash(password, 12);
    const result = await withAudit(request, { action: 'adminUser.create', entityType: 'admin_user', newValue: { name, email, role } }, async () => query(`INSERT INTO admin_users (name, email, password_hash, is_active) VALUES (?, ?, ?, 1)`, [name, email.toLowerCase(), hash]));
    const roleRow = await query(`SELECT id FROM admin_roles WHERE slug = ?`, [role]);
    if (roleRow.length) await query(`INSERT IGNORE INTO admin_user_roles (user_id, role_id) VALUES (?, ?)`, [result.insertId, roleRow[0].id]);
    return reply.code(201).send({ success: true, id: result.insertId });
  });

  fastify.put('/admin/users/:id', { preHandler: [adminAuth, requirePermissions('adminUsers.write')] }, async (request) => {
    const { name, email, is_active } = request.body || {};
    await withAudit(request, { action: 'adminUser.update', entityType: 'admin_user', entityId: request.params.id, newValue: request.body }, async () => query(`UPDATE admin_users SET name = COALESCE(?, name), email = COALESCE(?, email), is_active = COALESCE(?, is_active) WHERE id = ?`, [name ?? null, email ?? null, is_active === undefined ? null : is_active ? 1 : 0, request.params.id]));
    return { success: true };
  });

  fastify.delete('/admin/users/:id', { preHandler: [adminAuth, requirePermissions('adminUsers.write')] }, async (request) => {
    await withAudit(request, { action: 'adminUser.delete', entityType: 'admin_user', entityId: request.params.id }, async () => query(`UPDATE admin_users SET is_active = 0 WHERE id = ?`, [request.params.id]));
    return { success: true };
  });

  const simpleList = async (table, order = 'created_at DESC') => ({ success: true, data: await query(`SELECT * FROM ${table} ORDER BY ${order} LIMIT 500`).catch(() => []) });
  fastify.get('/admin/series', { preHandler: [adminAuth, requirePermissions('series.view')] }, () => simpleList('series', 'start_date DESC'));
  fastify.get('/admin/teams', { preHandler: [adminAuth, requirePermissions('teams.view')] }, () => simpleList('teams', 'name ASC'));
  fastify.get('/admin/players', { preHandler: [adminAuth, requirePermissions('players.view')] }, () => simpleList('players', 'name ASC'));
  fastify.get('/admin/schedule', { preHandler: [adminAuth, requirePermissions('schedule.view')] }, () => simpleList('matches', 'start_time ASC'));
  fastify.get('/admin/news', { preHandler: [adminAuth, requirePermissions('news.view')] }, () => simpleList('custom_news'));
  fastify.get('/admin/notifications', { preHandler: [adminAuth, requirePermissions('notifications.view')] }, () => simpleList('push_notifications'));
  fastify.post('/admin/notifications', { preHandler: [adminAuth, requirePermissions('notifications.write')] }, async (request, reply) => {
    const { title, body, target_type = 'all', scheduled_at = null } = request.body || {};
    if (!title || !body) return reply.code(400).send({ success: false, error: 'title and body required' });
    const result = await withAudit(request, { action: 'notification.create', entityType: 'push_notification', newValue: request.body }, async () => query(`INSERT INTO push_notifications (title, body, target_type, scheduled_at, status, created_by) VALUES (?, ?, ?, ?, 'draft', ?)`, [title, body, target_type, scheduled_at, request.adminUser.id]));
    return reply.code(201).send({ success: true, id: result.insertId });
  });
  fastify.get('/admin/ads', { preHandler: [adminAuth, requirePermissions('ads.view')] }, () => simpleList('ad_settings'));
  fastify.put('/admin/ads', { preHandler: [adminAuth, requirePermissions('ads.write')] }, async (request) => {
    await withAudit(request, { action: 'ads.update', entityType: 'ad_settings', newValue: request.body }, async () => query(`INSERT INTO ad_settings (setting_key, setting_value, is_public) VALUES ('ads_config', ?, 1) ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)`, [safeJson(request.body || {})]));
    return { success: true };
  });

  fastify.get('/app-config', async () => ({ success: true, data: await getSettingsMap(true) }));

  fastify.get('/home-config', async () => {
    const [sections, banners, featuredMatches, featuredSeries, featuredNews] = await Promise.all([
      query(`SELECT slug, title, section_type, payload, sort_order FROM homepage_sections WHERE is_active = 1 ORDER BY sort_order ASC`).catch(() => []),
      query(`SELECT placement, title, subtitle, image_url, cta_label, cta_url, sort_order FROM app_banners WHERE is_active = 1 ORDER BY sort_order ASC`).catch(() => []),
      query(`SELECT * FROM featured_matches WHERE is_active = 1 ORDER BY sort_order ASC`).catch(() => []),
      query(`SELECT * FROM featured_series WHERE is_active = 1 ORDER BY sort_order ASC`).catch(() => []),
      query(`SELECT * FROM featured_news WHERE is_active = 1 ORDER BY sort_order ASC`).catch(() => []),
    ]);
    return { success: true, data: { sections, banners, featuredMatches, featuredSeries, featuredNews } };
  });

  fastify.get('/match/:id/streams', async (request) => {
    const rows = await query(
      `SELECT id, match_external_id, quality, label, language, server_name, stream_type,
              stream_url, is_premium, priority, status
         FROM match_streams
        WHERE match_external_id = ? AND is_active = 1
          AND (starts_at IS NULL OR starts_at <= NOW())
          AND (ends_at IS NULL OR ends_at >= NOW())
        ORDER BY priority ASC, id ASC`,
      [request.params.id],
    ).catch(() => []);
    return {
      success: true,
      data: {
        matchId: request.params.id,
        streams: rows.map((s) => ({
          id: String(s.id),
          quality: s.quality,
          label: s.label || s.quality,
          language: s.language || 'English',
          serverName: s.server_name || 'Server',
          streamType: s.stream_type,
          url: s.stream_url,
          isPremium: !!s.is_premium,
          priority: s.priority,
          status: s.status || 'unknown',
        })),
      },
    };
  });
}
