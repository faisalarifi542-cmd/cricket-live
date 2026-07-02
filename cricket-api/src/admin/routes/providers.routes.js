import { adminAuth, requirePermissions } from '../auth.js';
import { withAudit } from '../audit.js';
import { query } from '../../lib/db.js';
import { getRedis } from '../../lib/redis.js';
import { ensureDefaultProvider, ensureProviderSchema } from '../provider-seed.js';
import {
  fetchPlayerByProviderId,
  fetchTeamByProviderId,
  fetchMatchByProviderId,
} from '../../lib/provider-fetch.js';
import providerManager from '../../providers/provider-manager.js';
import axios from 'axios';

const TEST_PATHS = [
  '/health',
  '/providers',
  '/matches/live',
  '/matches/upcoming',
  '/schedule/upcoming',
  '/news?limit=5',
];

function cleanProvider(row) {
  return {
    ...row,
    is_active: !!row.is_active,
    metadata: typeof row.metadata === 'string' ? safeJson(row.metadata) : row.metadata,
  };
}

function safeJson(value) {
  try { return JSON.parse(value); } catch { return null; }
}

async function clearProviderCache(id) {
  const redis = getRedis();
  const keys = await redis.keys(`*provider*${id}*`);
  const dataKeys = await redis.keys('appdata:*');
  const all = [...new Set([...keys, ...dataKeys])];
  return all.length ? redis.del(...all) : 0;
}
 
export default async function providerRoutes(fastify) {
  fastify.addHook('preHandler', adminAuth);
 
  fastify.get('/', { preHandler: [requirePermissions('providers.view')] }, async () => {
    await ensureDefaultProvider();
    const rows = await query(
      `SELECT * FROM api_providers ORDER BY priority ASC, name ASC`,
    );
    return {
      success: true,
      data: rows.map(cleanProvider),
    };
  });
 
  fastify.post('/', { preHandler: [requirePermissions('providers.write')] }, async (request, reply) => {
    await ensureProviderSchema();
    const { slug, name, provider_type = 'custom', base_url, description, priority = 100, timeout_ms = 8000, rate_limit_per_minute = 60, is_active = true, metadata } = request.body || {};
    if (!slug || !name) {
      return reply.code(400).send({ success: false, error: 'slug and name required' });
    }
    const r = await withAudit(
      request,
      { action: 'provider.create', entityType: 'api_provider', newValue: { slug, name } },
      async () =>
        query(
          `INSERT INTO api_providers (slug, name, provider_type, base_url, description, priority, timeout_ms, rate_limit_per_minute, is_active, metadata)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [slug, name, provider_type, base_url || null, description || null, priority, timeout_ms, rate_limit_per_minute, is_active ? 1 : 0, metadata ? JSON.stringify(metadata) : null],
        ),
    );
    const row = await query(`SELECT * FROM api_providers WHERE id = ?`, [r.insertId]);
    providerManager.invalidateConfig();
    return reply.code(201).send({ success: true, data: cleanProvider(row[0]) });
  });
 
  fastify.put('/:id', { preHandler: [requirePermissions('providers.write')] }, async (request, reply) => {
    await ensureProviderSchema();
    const id = request.params.id;
    const old = await query(`SELECT * FROM api_providers WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const allowed = ['name', 'provider_type', 'base_url', 'description', 'priority', 'timeout_ms', 'rate_limit_per_minute', 'is_active', 'metadata', 'health_status'];
    const data = {};
    for (const k of allowed) if (request.body[k] !== undefined) data[k] = request.body[k];
    if ('is_active' in data) data.is_active = data.is_active ? 1 : 0;
    if ('metadata' in data && data.metadata != null) data.metadata = JSON.stringify(data.metadata);
    if (!Object.keys(data).length) return reply.code(400).send({ success: false, error: 'No fields' });
    const setClause = Object.keys(data).map((k) => `${k} = ?`).join(', ');
    await withAudit(
      request,
      { action: 'provider.update', entityType: 'api_provider', entityId: id, oldValue: old[0], newValue: data },
      async () => query(`UPDATE api_providers SET ${setClause} WHERE id = ?`, [...Object.values(data), id]),
    );
    const row = await query(`SELECT * FROM api_providers WHERE id = ?`, [id]);
    await clearProviderCache(id);
    providerManager.invalidateConfig();
    return { success: true, data: cleanProvider(row[0]) };
  });
 
  fastify.delete('/:id', { preHandler: [requirePermissions('providers.write')] }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT * FROM api_providers WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    await withAudit(
      request,
      { action: 'provider.delete', entityType: 'api_provider', entityId: id, oldValue: old[0] },
      async () => query(`DELETE FROM api_providers WHERE id = ?`, [id]),
    );
    providerManager.invalidateConfig();
    return { success: true };
  });

  fastify.post('/:id/test', { preHandler: [requirePermissions('providers.write')] }, async (request, reply) => {
    const rows = await query(`SELECT id, name, base_url, timeout_ms FROM api_providers WHERE id = ?`, [request.params.id]);
    if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const provider = rows[0];
    if (!provider.base_url) return reply.code(400).send({ success: false, error: 'Provider base URL is required' });
    const base = String(provider.base_url).replace(/\/+$/, '');
    const results = [];
    let status = 'healthy';
    let lastSuccessfulRoute = null;
    let failedRoute = null;
    const startedAll = Date.now();

    for (const path of TEST_PATHS) {
      const started = Date.now();
      try {
        // eslint-disable-next-line no-await-in-loop
        const res = await axios.get(`${base}${path}`, {
          timeout: Number(provider.timeout_ms || 8000),
          validateStatus: () => true,
        });
        const ok = res.status >= 200 && res.status < 400 && res.data && typeof res.data !== 'string';
        const routeResult = {
          route: path,
          statusCode: res.status,
          ok,
          latencyMs: Date.now() - started,
          cache: res.headers?.['x-cache'] || null,
          error: ok ? null : 'Unexpected response',
        };
        results.push(routeResult);
        if (ok) lastSuccessfulRoute = path;
        if (!ok && !failedRoute) failedRoute = path;
      } catch (err) {
        status = 'degraded';
        if (!failedRoute) failedRoute = path;
        results.push({
          route: path,
          statusCode: 0,
          ok: false,
          latencyMs: Date.now() - started,
          cache: null,
          error: err.message,
        });
      }
    }
    const failures = results.filter((r) => !r.ok);
    if (failures.length === TEST_PATHS.length) status = 'down';
    else if (failures.length) status = 'degraded';
    await query(
      `UPDATE api_providers
          SET health_status = ?,
              last_success_at = IF(?, NOW(), last_success_at),
              last_failure_at = IF(?, NOW(), last_failure_at)
        WHERE id = ?`,
      [status, status === 'healthy' ? 1 : 0, status === 'healthy' ? 0 : 1, request.params.id],
    );
    return {
      success: true,
      status,
      provider: provider.name,
      latency_ms: Date.now() - startedAll,
      last_successful_route: lastSuccessfulRoute,
      failed_route: failedRoute,
      routes: results,
      message: status === 'healthy' ? 'All provider routes responded successfully' : 'One or more provider routes failed',
    };
  });

  // ---------- Provider data-fetch tests (player / team / match by ID) ----------
  // These run the request through the shared providerManager so they follow the
  // DB-configured priority + failover. They report which provider answered and
  // a clear error if every enabled provider failed.
  const runFetchTest = async (kind, id, reply) => {
    const value = String(id || '').trim();
    if (!value) {
      return reply.code(400).send({ success: false, error: 'An ID is required' });
    }
    const fetchers = {
      player: fetchPlayerByProviderId,
      team: fetchTeamByProviderId,
      match: fetchMatchByProviderId,
    };
    try {
      const result = await fetchers[kind](value);
      if (!result || !result.data) {
        return reply.code(404).send({ success: false, error: `No ${kind} found for ID ${value}` });
      }
      return { success: true, provider: result.provider, data: result.data };
    } catch (err) {
      return reply.code(502).send({
        success: false,
        error: `Provider fetch failed: ${err.message || 'all providers unavailable'}`,
      });
    }
  };

  fastify.post('/test-player', { preHandler: [requirePermissions('providers.write')] }, (request, reply) =>
    runFetchTest('player', request.body?.player_id ?? request.body?.id, reply),
  );
  fastify.post('/test-team', { preHandler: [requirePermissions('providers.write')] }, (request, reply) =>
    runFetchTest('team', request.body?.team_id ?? request.body?.id, reply),
  );
  fastify.post('/test-match', { preHandler: [requirePermissions('providers.write')] }, (request, reply) =>
    runFetchTest('match', request.body?.match_id ?? request.body?.id, reply),
  );

  fastify.post('/:id/toggle', { preHandler: [requirePermissions('providers.write')] }, async (request, reply) => {
    const rows = await query(`SELECT id, is_active FROM api_providers WHERE id = ?`, [request.params.id]);
    if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const next = rows[0].is_active ? 0 : 1;
    await query(`UPDATE api_providers SET is_active = ? WHERE id = ?`, [next, request.params.id]);
    await clearProviderCache(request.params.id);
    providerManager.invalidateConfig();
    return { success: true, is_active: !!next };
  });

  fastify.post('/:id/reset', { preHandler: [requirePermissions('providers.write')] }, async (request) => {
    await query(`UPDATE api_providers SET health_status = 'unknown', last_failure_at = NULL WHERE id = ?`, [request.params.id]);
    return { success: true };
  });

  fastify.post('/:id/cache-clear', { preHandler: [requirePermissions('providers.write')] }, async (request) => {
    const cleared = await clearProviderCache(request.params.id);
    return { success: true, cleared };
  });
 
  // ---------- Provider API keys ----------
  fastify.get('/:id/keys', { preHandler: [requirePermissions('providers.view')] }, async (request) => {
    const rows = await query(
      `SELECT id, provider_id, label, is_active, rotated_at, last_used_at, notes, created_at, updated_at
         FROM provider_api_keys WHERE provider_id = ? ORDER BY created_at DESC`,
      [request.params.id],
    );
    return { success: true, data: rows.map((r) => ({ ...r, is_active: !!r.is_active })) };
  });
 
  fastify.post('/:id/keys', { preHandler: [requirePermissions('providers.write')] }, async (request, reply) => {
    const { label, key_value, notes } = request.body || {};
    if (!label || !key_value) return reply.code(400).send({ success: false, error: 'label and key_value required' });
    const r = await withAudit(
      request,
      { action: 'providerKey.create', entityType: 'provider_api_key', newValue: { label } },
      async () =>
        query(
          `INSERT INTO provider_api_keys (provider_id, label, key_value, notes, created_by, rotated_at)
           VALUES (?, ?, ?, ?, ?, NOW())`,
          [request.params.id, label, key_value, notes || null, request.adminUser.id],
        ),
    );
    return reply.code(201).send({ success: true, id: r.insertId });
  });
 
  fastify.delete('/:id/keys/:keyId', { preHandler: [requirePermissions('providers.write')] }, async (request, reply) => {
    const old = await query(`SELECT id, provider_id, label FROM provider_api_keys WHERE id = ?`, [request.params.keyId]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    await withAudit(
      request,
      { action: 'providerKey.delete', entityType: 'provider_api_key', entityId: request.params.keyId, oldValue: old[0] },
      async () => query(`DELETE FROM provider_api_keys WHERE id = ?`, [request.params.keyId]),
    );
    return { success: true };
  });
}
