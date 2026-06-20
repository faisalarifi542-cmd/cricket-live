/**
 * Admin API for the API Security / Access Control module.
 *
 * Mounted at /admin/api-security. Every route requires an admin JWT plus the
 * apiSecurity.view / apiSecurity.write permission. Mutations are audited and
 * invalidate the in-process security caches so changes take effect within
 * seconds without a redeploy.
 *
 * Raw API keys are returned ONLY once (on create / regenerate). Afterwards only
 * a masked prefix is exposed.
 */
import { nanoid } from 'nanoid';
import { adminAuth, requirePermissions } from '../auth.js';
import { withAudit } from '../audit.js';
import { query } from '../../lib/db.js';
import {
  sha256,
  invalidateSecurityCaches,
  getSecurityMode,
  trimRequestLogs,
} from '../../lib/api-security.js';

const CLIENT_TYPES = ['android', 'ios', 'web', 'server', 'admin'];
const BLOCK_TYPES = ['ip', 'cidr', 'origin', 'domain', 'user_agent', 'client'];

function genApiKey() {
  return `csk_${nanoid(40)}`;
}

function safeJsonArray(value) {
  if (value == null) return null;
  if (Array.isArray(value)) return JSON.stringify(value);
  if (typeof value === 'string') {
    const parts = value.split(',').map((s) => s.trim()).filter(Boolean);
    return parts.length ? JSON.stringify(parts) : null;
  }
  return null;
}

function parseJson(value, fallback = null) {
  if (value == null) return fallback;
  if (typeof value === 'object') return value;
  try { return JSON.parse(value); } catch { return fallback; }
}

function clientDto(row) {
  return {
    id: row.id,
    name: row.name,
    client_type: row.client_type,
    api_key_prefix: row.api_key_prefix,
    api_key_masked: row.api_key_prefix ? `${row.api_key_prefix}••••••••` : null,
    allowed_origins: parseJson(row.allowed_origins, []),
    allowed_domains: parseJson(row.allowed_domains, []),
    allowed_package_names: parseJson(row.allowed_package_names, []),
    allowed_bundle_ids: parseJson(row.allowed_bundle_ids, []),
    scopes: parseJson(row.scopes, []),
    rate_limit_per_minute: row.rate_limit_per_minute,
    rate_limit_per_hour: row.rate_limit_per_hour,
    rate_limit_per_day: row.rate_limit_per_day,
    status: row.status,
    expires_at: row.expires_at,
    last_used_at: row.last_used_at,
    notes: row.notes,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

export default async function apiSecurityRoutes(fastify) {
  fastify.addHook('preHandler', adminAuth);

  const view = [requirePermissions('apiSecurity.view')];
  const write = [requirePermissions('apiSecurity.write')];

  // =====================================================
  // API CLIENTS
  // =====================================================
  fastify.get('/clients', { preHandler: view }, async () => {
    const rows = await query(
      `SELECT * FROM api_clients ORDER BY created_at DESC LIMIT 500`,
    ).catch(() => []);
    return { success: true, data: rows.map(clientDto) };
  });

  fastify.post('/clients', { preHandler: write }, async (request, reply) => {
    const b = request.body || {};
    if (!b.name || String(b.name).trim().length < 3) {
      return reply.code(400).send({ success: false, error: 'name (>=3 chars) required' });
    }
    const clientType = CLIENT_TYPES.includes(b.client_type) ? b.client_type : 'app';
    const rawKey = genApiKey();
    const keyHash = sha256(rawKey);
    const prefix = rawKey.slice(0, 12);
    const secretHash = b.secret ? sha256(b.secret) : null;
    const expiresAt = b.expires_at ? new Date(b.expires_at) : null;

    const result = await withAudit(
      request,
      { action: 'apiSecurity.client.create', entityType: 'api_client', newValue: { name: b.name, client_type: clientType } },
      async () => query(
        `INSERT INTO api_clients
          (name, client_type, api_key_hash, api_key_prefix, secret_hash, allowed_origins, allowed_domains,
           allowed_package_names, allowed_bundle_ids, scopes, rate_limit_per_minute, rate_limit_per_hour,
           rate_limit_per_day, status, expires_at, created_by, notes)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          String(b.name).trim(), clientType, keyHash, prefix, secretHash,
          safeJsonArray(b.allowed_origins), safeJsonArray(b.allowed_domains),
          safeJsonArray(b.allowed_package_names), safeJsonArray(b.allowed_bundle_ids),
          safeJsonArray(b.scopes),
          Number(b.rate_limit_per_minute) || 120,
          Number(b.rate_limit_per_hour) || 5000,
          Number(b.rate_limit_per_day) || 100000,
          b.status && ['active', 'disabled', 'revoked'].includes(b.status) ? b.status : 'active',
          expiresAt,
          request.adminUser?.id || null,
          b.notes || null,
        ],
      ),
    );
    invalidateSecurityCaches();
    return reply.code(201).send({
      success: true,
      id: result.insertId,
      api_key: rawKey,
      api_key_prefix: prefix,
      warning: 'Save this API key now. It cannot be retrieved again.',
    });
  });

  fastify.put('/clients/:id', { preHandler: write }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT * FROM api_clients WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const b = request.body || {};
    const set = [];
    const vals = [];
    const setField = (col, val) => { set.push(`${col} = ?`); vals.push(val); };

    if (b.name !== undefined) setField('name', String(b.name).trim());
    if (b.client_type !== undefined && CLIENT_TYPES.includes(b.client_type)) setField('client_type', b.client_type);
    if (b.allowed_origins !== undefined) setField('allowed_origins', safeJsonArray(b.allowed_origins));
    if (b.allowed_domains !== undefined) setField('allowed_domains', safeJsonArray(b.allowed_domains));
    if (b.allowed_package_names !== undefined) setField('allowed_package_names', safeJsonArray(b.allowed_package_names));
    if (b.allowed_bundle_ids !== undefined) setField('allowed_bundle_ids', safeJsonArray(b.allowed_bundle_ids));
    if (b.scopes !== undefined) setField('scopes', safeJsonArray(b.scopes));
    if (b.rate_limit_per_minute !== undefined) setField('rate_limit_per_minute', Number(b.rate_limit_per_minute) || 0);
    if (b.rate_limit_per_hour !== undefined) setField('rate_limit_per_hour', Number(b.rate_limit_per_hour) || 0);
    if (b.rate_limit_per_day !== undefined) setField('rate_limit_per_day', Number(b.rate_limit_per_day) || 0);
    if (b.status !== undefined && ['active', 'disabled', 'revoked'].includes(b.status)) setField('status', b.status);
    if (b.expires_at !== undefined) setField('expires_at', b.expires_at ? new Date(b.expires_at) : null);
    if (b.notes !== undefined) setField('notes', b.notes || null);
    if (!set.length) return reply.code(400).send({ success: false, error: 'No fields to update' });

    await withAudit(
      request,
      { action: 'apiSecurity.client.update', entityType: 'api_client', entityId: id, oldValue: clientDto(old[0]), newValue: b },
      async () => query(`UPDATE api_clients SET ${set.join(', ')} WHERE id = ?`, [...vals, id]),
    );
    invalidateSecurityCaches();
    return { success: true };
  });

  fastify.post('/clients/:id/regenerate-key', { preHandler: write }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT * FROM api_clients WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const rawKey = genApiKey();
    const keyHash = sha256(rawKey);
    const prefix = rawKey.slice(0, 12);
    await withAudit(
      request,
      { action: 'apiSecurity.client.regenerateKey', entityType: 'api_client', entityId: id },
      async () => query(`UPDATE api_clients SET api_key_hash = ?, api_key_prefix = ? WHERE id = ?`, [keyHash, prefix, id]),
    );
    invalidateSecurityCaches();
    return {
      success: true,
      api_key: rawKey,
      api_key_prefix: prefix,
      warning: 'Save this API key now. The previous key has stopped working.',
    };
  });

  fastify.post('/clients/:id/revoke', { preHandler: write }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT id, name, status FROM api_clients WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    await withAudit(
      request,
      { action: 'apiSecurity.client.revoke', entityType: 'api_client', entityId: id, oldValue: old[0], newValue: { status: 'revoked' } },
      async () => query(`UPDATE api_clients SET status = 'revoked' WHERE id = ?`, [id]),
    );
    invalidateSecurityCaches();
    return { success: true };
  });

  // =====================================================
  // ALLOWED ORIGINS
  // =====================================================
  fastify.get('/origins', { preHandler: view }, async () => {
    const rows = await query(`SELECT * FROM api_allowed_origins ORDER BY created_at DESC LIMIT 500`).catch(() => []);
    return {
      success: true,
      data: rows.map((r) => ({ ...r, allowed_endpoint_groups: parseJson(r.allowed_endpoint_groups, []) })),
    };
  });

  fastify.post('/origins', { preHandler: write }, async (request, reply) => {
    const b = request.body || {};
    if (!b.origin && !b.domain) {
      return reply.code(400).send({ success: false, error: 'origin or domain required' });
    }
    const result = await withAudit(
      request,
      { action: 'apiSecurity.origin.create', entityType: 'api_allowed_origin', newValue: b },
      async () => query(
        `INSERT INTO api_allowed_origins (origin, domain, status, allowed_endpoint_groups, rate_limit_per_minute, notes)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [
          b.origin || null,
          b.domain || null,
          b.status === 'inactive' ? 'inactive' : 'active',
          safeJsonArray(b.allowed_endpoint_groups),
          Number(b.rate_limit_per_minute) || 120,
          b.notes || null,
        ],
      ),
    );
    invalidateSecurityCaches();
    return reply.code(201).send({ success: true, id: result.insertId });
  });

  fastify.put('/origins/:id', { preHandler: write }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT * FROM api_allowed_origins WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const b = request.body || {};
    const set = [];
    const vals = [];
    const setField = (c, v) => { set.push(`${c} = ?`); vals.push(v); };
    if (b.origin !== undefined) setField('origin', b.origin || null);
    if (b.domain !== undefined) setField('domain', b.domain || null);
    if (b.status !== undefined) setField('status', b.status === 'inactive' ? 'inactive' : 'active');
    if (b.allowed_endpoint_groups !== undefined) setField('allowed_endpoint_groups', safeJsonArray(b.allowed_endpoint_groups));
    if (b.rate_limit_per_minute !== undefined) setField('rate_limit_per_minute', Number(b.rate_limit_per_minute) || 0);
    if (b.notes !== undefined) setField('notes', b.notes || null);
    if (!set.length) return reply.code(400).send({ success: false, error: 'No fields to update' });
    await withAudit(
      request,
      { action: 'apiSecurity.origin.update', entityType: 'api_allowed_origin', entityId: id, oldValue: old[0], newValue: b },
      async () => query(`UPDATE api_allowed_origins SET ${set.join(', ')} WHERE id = ?`, [...vals, id]),
    );
    invalidateSecurityCaches();
    return { success: true };
  });

  fastify.delete('/origins/:id', { preHandler: write }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT * FROM api_allowed_origins WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    await withAudit(
      request,
      { action: 'apiSecurity.origin.delete', entityType: 'api_allowed_origin', entityId: id, oldValue: old[0] },
      async () => query(`DELETE FROM api_allowed_origins WHERE id = ?`, [id]),
    );
    invalidateSecurityCaches();
    return { success: true };
  });

  // =====================================================
  // ENDPOINT RULES
  // =====================================================
  fastify.get('/endpoint-rules', { preHandler: view }, async () => {
    const rows = await query(`SELECT * FROM api_endpoint_rules ORDER BY group_name ASC`).catch(() => []);
    return {
      success: true,
      data: rows.map((r) => ({
        ...r,
        enabled: !!r.enabled,
        logging_enabled: !!r.logging_enabled,
        methods: parseJson(r.methods, []),
        allowed_client_types: parseJson(r.allowed_client_types, []),
      })),
    };
  });

  fastify.post('/endpoint-rules', { preHandler: write }, async (request, reply) => {
    const b = request.body || {};
    if (!b.group_name) return reply.code(400).send({ success: false, error: 'group_name required' });
    const result = await withAudit(
      request,
      { action: 'apiSecurity.endpointRule.create', entityType: 'api_endpoint_rule', newValue: b },
      async () => query(
        `INSERT INTO api_endpoint_rules
          (group_name, path_pattern, methods, enabled, auth_required, allowed_client_types,
           rate_limit_per_minute, rate_limit_per_hour, cache_ttl_seconds, logging_enabled, notes)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE path_pattern = VALUES(path_pattern)`,
        [
          b.group_name, b.path_pattern || null, safeJsonArray(b.methods),
          b.enabled === false ? 0 : 1,
          ['none', 'api_key', 'admin_jwt'].includes(b.auth_required) ? b.auth_required : 'api_key',
          safeJsonArray(b.allowed_client_types),
          Number(b.rate_limit_per_minute) || 120,
          Number(b.rate_limit_per_hour) || 0,
          Number(b.cache_ttl_seconds) || 0,
          b.logging_enabled === false ? 0 : 1,
          b.notes || null,
        ],
      ),
    );
    invalidateSecurityCaches();
    return reply.code(201).send({ success: true, id: result.insertId });
  });

  fastify.put('/endpoint-rules/:id', { preHandler: write }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT * FROM api_endpoint_rules WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const b = request.body || {};
    const set = [];
    const vals = [];
    const setField = (c, v) => { set.push(`${c} = ?`); vals.push(v); };
    if (b.path_pattern !== undefined) setField('path_pattern', b.path_pattern || null);
    if (b.methods !== undefined) setField('methods', safeJsonArray(b.methods));
    if (b.enabled !== undefined) setField('enabled', b.enabled ? 1 : 0);
    if (b.auth_required !== undefined && ['none', 'api_key', 'admin_jwt'].includes(b.auth_required)) setField('auth_required', b.auth_required);
    if (b.allowed_client_types !== undefined) setField('allowed_client_types', safeJsonArray(b.allowed_client_types));
    if (b.rate_limit_per_minute !== undefined) setField('rate_limit_per_minute', Number(b.rate_limit_per_minute) || 0);
    if (b.rate_limit_per_hour !== undefined) setField('rate_limit_per_hour', Number(b.rate_limit_per_hour) || 0);
    if (b.cache_ttl_seconds !== undefined) setField('cache_ttl_seconds', Number(b.cache_ttl_seconds) || 0);
    if (b.logging_enabled !== undefined) setField('logging_enabled', b.logging_enabled ? 1 : 0);
    if (b.notes !== undefined) setField('notes', b.notes || null);
    if (!set.length) return reply.code(400).send({ success: false, error: 'No fields to update' });
    await withAudit(
      request,
      { action: 'apiSecurity.endpointRule.update', entityType: 'api_endpoint_rule', entityId: id, oldValue: old[0], newValue: b },
      async () => query(`UPDATE api_endpoint_rules SET ${set.join(', ')} WHERE id = ?`, [...vals, id]),
    );
    invalidateSecurityCaches();
    return { success: true };
  });

  // =====================================================
  // BLOCKLIST
  // =====================================================
  fastify.get('/blocklist', { preHandler: view }, async () => {
    const rows = await query(`SELECT * FROM api_blocklist ORDER BY created_at DESC LIMIT 500`).catch(() => []);
    return { success: true, data: rows.map((r) => ({ ...r, enabled: !!r.enabled })) };
  });

  fastify.post('/blocklist', { preHandler: write }, async (request, reply) => {
    const b = request.body || {};
    if (!BLOCK_TYPES.includes(b.type) || !b.value) {
      return reply.code(400).send({ success: false, error: `type (${BLOCK_TYPES.join('|')}) and value required` });
    }
    const result = await withAudit(
      request,
      { action: 'apiSecurity.blocklist.create', entityType: 'api_blocklist', newValue: b },
      async () => query(
        `INSERT INTO api_blocklist (type, value, reason, enabled, expires_at, created_by)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [b.type, String(b.value).trim(), b.reason || null, b.enabled === false ? 0 : 1,
          b.expires_at ? new Date(b.expires_at) : null, request.adminUser?.id || null],
      ),
    );
    invalidateSecurityCaches();
    return reply.code(201).send({ success: true, id: result.insertId });
  });

  fastify.put('/blocklist/:id', { preHandler: write }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT * FROM api_blocklist WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const b = request.body || {};
    const set = [];
    const vals = [];
    const setField = (c, v) => { set.push(`${c} = ?`); vals.push(v); };
    if (b.type !== undefined && BLOCK_TYPES.includes(b.type)) setField('type', b.type);
    if (b.value !== undefined) setField('value', String(b.value).trim());
    if (b.reason !== undefined) setField('reason', b.reason || null);
    if (b.enabled !== undefined) setField('enabled', b.enabled ? 1 : 0);
    if (b.expires_at !== undefined) setField('expires_at', b.expires_at ? new Date(b.expires_at) : null);
    if (!set.length) return reply.code(400).send({ success: false, error: 'No fields to update' });
    await withAudit(
      request,
      { action: 'apiSecurity.blocklist.update', entityType: 'api_blocklist', entityId: id, oldValue: old[0], newValue: b },
      async () => query(`UPDATE api_blocklist SET ${set.join(', ')} WHERE id = ?`, [...vals, id]),
    );
    invalidateSecurityCaches();
    return { success: true };
  });

  fastify.delete('/blocklist/:id', { preHandler: write }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT * FROM api_blocklist WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    await withAudit(
      request,
      { action: 'apiSecurity.blocklist.delete', entityType: 'api_blocklist', entityId: id, oldValue: old[0] },
      async () => query(`DELETE FROM api_blocklist WHERE id = ?`, [id]),
    );
    invalidateSecurityCaches();
    return { success: true };
  });

  // =====================================================
  // REQUEST LOGS (filters + pagination)
  // =====================================================
  fastify.get('/logs', { preHandler: view }, async (request) => {
    const q = request.query || {};
    const where = [];
    const params = [];
    if (q.blocked === 'true' || q.blocked === '1') where.push('allowed = 0');
    if (q.client_id) { where.push('api_client_id = ?'); params.push(q.client_id); }
    if (q.ip) { where.push('ip = ?'); params.push(q.ip); }
    if (q.group) { where.push('endpoint_group = ?'); params.push(q.group); }
    if (q.status_code) { where.push('status_code = ?'); params.push(Number(q.status_code)); }
    if (q.from) { where.push('created_at >= ?'); params.push(q.from); }
    if (q.to) { where.push('created_at <= ?'); params.push(q.to); }
    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const limit = Math.min(Number(q.limit) || 100, 500);
    const page = Math.max(1, Number(q.page) || 1);
    const offset = (page - 1) * limit;

    const [rows, countRows] = await Promise.all([
      query(`SELECT * FROM api_request_logs ${whereSql} ORDER BY id DESC LIMIT ${limit} OFFSET ${offset}`, params).catch(() => []),
      query(`SELECT COUNT(*) total FROM api_request_logs ${whereSql}`, params).catch(() => [{ total: 0 }]),
    ]);
    return {
      success: true,
      data: rows.map((r) => ({ ...r, allowed: !!r.allowed })),
      pagination: { page, limit, total: Number(countRows[0]?.total || 0) },
    };
  });

  fastify.post('/logs/trim', { preHandler: write }, async (request) => {
    const days = Number(request.body?.days) || 14;
    const deleted = await withAudit(
      request,
      { action: 'apiSecurity.logs.trim', entityType: 'api_request_logs', newValue: { days } },
      async () => trimRequestLogs(days),
    );
    return { success: true, deleted };
  });

  // =====================================================
  // SECURITY MODE (enforce | monitor | off)
  // =====================================================
  fastify.get('/mode', { preHandler: view }, async () => {
    const mode = await getSecurityMode();
    return { success: true, data: { mode } };
  });

  fastify.put('/mode', { preHandler: write }, async (request, reply) => {
    const mode = request.body?.mode;
    if (!['enforce', 'monitor', 'off'].includes(mode)) {
      return reply.code(400).send({ success: false, error: 'mode must be enforce|monitor|off' });
    }
    await withAudit(
      request,
      { action: 'apiSecurity.mode.update', entityType: 'app_setting', entityId: 'apiSecurityMode', newValue: { mode } },
      async () => query(
        `INSERT INTO app_settings (setting_key, setting_value, setting_group, is_public)
         VALUES ('apiSecurityMode', ?, 'security', 0)
         ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)`,
        [JSON.stringify(mode)],
      ),
    );
    invalidateSecurityCaches();
    return { success: true, data: { mode } };
  });

  // =====================================================
  // DASHBOARD
  // =====================================================
  fastify.get('/dashboard', { preHandler: view }, async () => {
    const today = `created_at >= (NOW() - INTERVAL 1 DAY)`;
    const [
      totals, blocked, topClients, topBlockedIps, topEndpoints, rateLimitHits, disabledHits, suspiciousOrigins, mode,
    ] = await Promise.all([
      query(`SELECT COUNT(*) total FROM api_request_logs WHERE ${today}`).catch(() => [{ total: 0 }]),
      query(`SELECT COUNT(*) total FROM api_request_logs WHERE ${today} AND allowed = 0`).catch(() => [{ total: 0 }]),
      query(`SELECT c.name, l.api_client_id, COUNT(*) hits
               FROM api_request_logs l LEFT JOIN api_clients c ON c.id = l.api_client_id
              WHERE l.${today} AND l.api_client_id IS NOT NULL
              GROUP BY l.api_client_id ORDER BY hits DESC LIMIT 10`).catch(() => []),
      query(`SELECT ip, COUNT(*) hits FROM api_request_logs
              WHERE ${today} AND allowed = 0 GROUP BY ip ORDER BY hits DESC LIMIT 10`).catch(() => []),
      query(`SELECT endpoint_group, COUNT(*) hits FROM api_request_logs
              WHERE ${today} GROUP BY endpoint_group ORDER BY hits DESC LIMIT 10`).catch(() => []),
      query(`SELECT COUNT(*) total FROM api_request_logs WHERE ${today} AND blocked_reason = 'rate_limited'`).catch(() => [{ total: 0 }]),
      query(`SELECT COUNT(*) total FROM api_request_logs WHERE ${today} AND blocked_reason = 'endpoint_disabled'`).catch(() => [{ total: 0 }]),
      query(`SELECT origin, COUNT(*) hits FROM api_request_logs
              WHERE ${today} AND blocked_reason IN ('origin_not_allowed','blocked_origin','blocked_domain')
                AND origin IS NOT NULL GROUP BY origin ORDER BY hits DESC LIMIT 10`).catch(() => []),
      getSecurityMode(),
    ]);
    return {
      success: true,
      data: {
        mode,
        totalRequestsToday: Number(totals[0]?.total || 0),
        blockedRequestsToday: Number(blocked[0]?.total || 0),
        rateLimitHitsToday: Number(rateLimitHits[0]?.total || 0),
        disabledEndpointHitsToday: Number(disabledHits[0]?.total || 0),
        topClients,
        topBlockedIps,
        topEndpoints,
        suspiciousOrigins,
      },
    };
  });
}
