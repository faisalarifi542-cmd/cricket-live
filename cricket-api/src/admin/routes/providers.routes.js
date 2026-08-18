import { adminAuth, requirePermissions } from '../auth.js';
import { withAudit } from '../audit.js';
import { query, transaction } from '../../lib/db.js';
import { getRedis } from '../../lib/redis.js';
import { ensureDefaultProvider, ensureProviderSchema } from '../provider-seed.js';
import {
  fetchPlayerByProviderId,
  fetchTeamByProviderId,
  fetchMatchByProviderId,
} from '../../lib/provider-fetch.js';
import providerManager from '../../providers/provider-manager.js';
import { probeProvider, toHealthStatus } from '../provider-probe.js';
import logger from '../../lib/logger.js';
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

// The role-column fallbacks below must only trigger when the column is
// actually missing (pre-migration DBs). Swallowing every SQL error there
// masks real failures — e.g. a duplicate-slug insert would be retried
// without `role`, fail again, and surface as an opaque 500.
function isMissingRoleColumn(err) {
  return err?.code === 'ER_BAD_FIELD_ERROR' || err?.errno === 1054;
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
    let rows;
    try {
      rows = await query(
        `SELECT * FROM api_providers ORDER BY CASE WHEN (role IS NULL OR role = '') THEN 'fallback' ELSE role END = 'primary' DESC, priority ASC, name ASC`,
      );
    } catch (err) {
      if (!isMissingRoleColumn(err)) throw err;
      // `role` column may not exist yet on older DBs before the migration runs.
      // Fall back to the old ORDER BY so the page never crashes on a missing column.
      rows = await query(
        `SELECT * FROM api_providers ORDER BY priority ASC, name ASC`,
      );
    }
    // Enrich each row with live capabilities from the provider instance (not stored
    // in the DB — always reflects what the code actually supports right now).
    const enriched = rows.map((r) => {
      const provider = providerManager.getProvider(r.provider_type);
      let capabilities = {};
      try {
        capabilities = provider && typeof provider.getCapabilities === 'function'
          ? provider.getCapabilities()
          : {};
      } catch {
        // Per-provider capabilities map must never crash the list endpoint.
      }
      const configured = provider && typeof provider.isConfigured === 'function'
        ? provider.isConfigured()
        : true;
      const configReasonVal = provider && typeof provider.configReason === 'function'
        ? provider.configReason()
        : null;
      const healthState = provider && typeof provider.healthState === 'function'
        ? provider.healthState()
        : (r.health_status || 'unknown');
      return {
        ...cleanProvider(r),
        capabilities,
        is_configured: configured,
        config_reason: configReasonVal,
        live_health_state: healthState,
      };
    });
    return {
      success: true,
      data: enriched,
    };
  });
 
  fastify.post('/', { preHandler: [requirePermissions('providers.write')] }, async (request, reply) => {
    await ensureProviderSchema();
    const { slug, name, provider_type = 'custom', base_url, description, priority: rawPriority, timeout_ms = 8000, rate_limit_per_minute = 60, is_active = true, role, metadata } = request.body || {};
    if (!slug || !name) {
      return reply.code(400).send({ success: false, error: 'slug and name required' });
    }
    const meta = metadata && typeof metadata === 'object' ? { ...metadata } : {};
    const providerRole = String(role || meta.role || 'fallback').toLowerCase();
    const becomingPrimary = providerRole === 'primary';
    // Keep metadata.role in sync for backward compat but use the dedicated column.
    if (!meta.role) meta.role = providerRole;
    const priority = rawPriority !== undefined && rawPriority !== null
      ? rawPriority
      : (becomingPrimary ? 1 : 100);
    const r = await withAudit(
      request,
      { action: 'provider.create', entityType: 'api_provider', newValue: { slug, name } },
      async () =>
        transaction(async (conn) => {
          // Try with the role column first; fall back to pre-role column set on older DBs.
          try {
            const [res] = await conn.execute(
              `INSERT INTO api_providers (slug, name, provider_type, base_url, description, priority, timeout_ms, rate_limit_per_minute, is_active, role, metadata)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
              [slug, name, provider_type, base_url || null, description || null, priority, timeout_ms, rate_limit_per_minute, is_active ? 1 : 0, providerRole, Object.keys(meta).length ? JSON.stringify(meta) : null],
            );
            if (becomingPrimary) {
              await conn.execute(`UPDATE api_providers SET role = 'fallback' WHERE id <> ?`, [res.insertId]);
            }
            return res;
          } catch (err) {
            if (!isMissingRoleColumn(err)) throw err;
            // role column missing — fall back to insert without it + store role in metadata
            const [res] = await conn.execute(
              `INSERT INTO api_providers (slug, name, provider_type, base_url, description, priority, timeout_ms, rate_limit_per_minute, is_active, metadata)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
              [slug, name, provider_type, base_url || null, description || null, priority, timeout_ms, rate_limit_per_minute, is_active ? 1 : 0, Object.keys(meta).length ? JSON.stringify(meta) : null],
            );
            return res;
          }
        }),
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
    const existing = old[0];
    const body = request.body || {};

    // Merge the partial body over the existing row, then validate the MERGED
    // result — a partial edit (e.g. only role/priority) must not blank out
    // name/slug or drop the rest of the row.
    const oldMeta = typeof existing.metadata === 'string' ? (safeJson(existing.metadata) || {}) : (existing.metadata || {});
    const incomingMeta = body.metadata && typeof body.metadata === 'object' ? body.metadata : {};
    const mergedMeta = { ...oldMeta, ...incomingMeta };

    // Role: dedicated column is the source of truth. Accept `role` from body,
    // fall back to metadata.role, then to the existing DB value.
    const resolvedRole = String(body.role || incomingMeta.role || existing.role || 'fallback').toLowerCase();
    // Sync metadata.role so both stay consistent.
    mergedMeta.role = resolvedRole;

    const merged = {
      slug: body.slug !== undefined ? body.slug : existing.slug,
      name: body.name !== undefined ? body.name : existing.name,
      provider_type: body.provider_type !== undefined ? body.provider_type : existing.provider_type,
      base_url: body.base_url !== undefined ? body.base_url : existing.base_url,
      description: body.description !== undefined ? body.description : existing.description,
      priority: body.priority !== undefined ? body.priority : existing.priority,
      timeout_ms: body.timeout_ms !== undefined ? body.timeout_ms : existing.timeout_ms,
      rate_limit_per_minute: body.rate_limit_per_minute !== undefined ? body.rate_limit_per_minute : existing.rate_limit_per_minute,
      is_active: body.is_active !== undefined ? (body.is_active ? 1 : 0) : existing.is_active,
      health_status: body.health_status !== undefined ? body.health_status : existing.health_status,
      role: resolvedRole,
      metadata: mergedMeta,
    };

    // Validate the merged result, not just the partial body.
    if (!merged.slug || String(merged.slug).trim().length < 2) {
      return reply.code(400).send({ success: false, error: 'slug is required' });
    }
    if (!merged.name || String(merged.name).trim().length < 2) {
      return reply.code(400).send({ success: false, error: 'name is required' });
    }

    // A provider promoted to primary gets a default priority of 1 (if none
    // supplied) and forces every OTHER provider to fallback — only one primary
    // may exist at a time.
    const becomingPrimary = resolvedRole === 'primary';
    if (becomingPrimary && (merged.priority === undefined || merged.priority === null)) {
      merged.priority = 1;
    }

    await withAudit(
      request,
      { action: 'provider.update', entityType: 'api_provider', entityId: id, oldValue: existing, newValue: merged },
      async () =>
        transaction(async (conn) => {
          try {
            await conn.execute(
              `UPDATE api_providers
                  SET slug = ?, name = ?, provider_type = ?, base_url = ?, description = ?,
                      priority = ?, timeout_ms = ?, rate_limit_per_minute = ?, is_active = ?,
                      role = ?, health_status = ?, metadata = ?
                WHERE id = ?`,
              [
                merged.slug, merged.name, merged.provider_type, merged.base_url || null,
                merged.description || null, merged.priority, merged.timeout_ms,
                merged.rate_limit_per_minute, merged.is_active, merged.role,
                merged.health_status,
                JSON.stringify(mergedMeta), id,
              ],
            );
            if (becomingPrimary) {
              await conn.execute(`UPDATE api_providers SET role = 'fallback' WHERE id <> ?`, [id]);
            }
          } catch (err) {
            if (!isMissingRoleColumn(err)) throw err;
            // Fall back when role column is missing on older DBs (pre-migration).
            await conn.execute(
              `UPDATE api_providers
                  SET slug = ?, name = ?, provider_type = ?, base_url = ?, description = ?,
                      priority = ?, timeout_ms = ?, rate_limit_per_minute = ?, is_active = ?,
                      health_status = ?, metadata = ?
                WHERE id = ?`,
              [
                merged.slug, merged.name, merged.provider_type, merged.base_url || null,
                merged.description || null, merged.priority, merged.timeout_ms,
                merged.rate_limit_per_minute, merged.is_active,
                merged.health_status,
                JSON.stringify(mergedMeta), id,
              ],
            );
          }
        }),
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
    const rows = await query(`SELECT id, name, slug, provider_type, base_url, timeout_ms FROM api_providers WHERE id = ?`, [request.params.id]);
    if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const provider = rows[0];
    const startedAll = Date.now();

    // Resolve which capability probe to run. Cricinfo/ESPN is matched across
    // every value it can plausibly carry so it can never fall through to the
    // legacy base_url path loop (which 404s on ESPN and wrongly persists `down`).
    const type = String(provider.provider_type || '').toLowerCase();
    const slug = String(provider.slug || '').toLowerCase();
    const name = String(provider.name || '').toLowerCase();
    const isCricinfo =
      type === 'cricinfo' ||
      type === 'espn' ||
      type === 'espn-cricinfo' ||
      type === 'espn_cricinfo' ||
      slug === 'cricinfo' ||
      slug === 'espn-cricinfo' ||
      slug === 'espn_cricinfo' ||
      name.includes('cricinfo') ||
      name.includes('espn');
    let probeName = null;
    if (isCricinfo) probeName = 'cricinfo';
    else if (type === 'cricketdata' || name.includes('cricketdata')) probeName = 'cricketdata';
    else if (type === 'cricbuzz' || name.includes('cricbuzz')) probeName = 'cricbuzz';

    if (probeName) {
      const probe = await probeProvider(probeName, {
        baseUrl: provider.base_url,
        timeoutMs: Number(provider.timeout_ms || 8000),
      });
      if (probe) {
        const status = toHealthStatus(probe.status);
        const healthy = probe.status === 'up' || probe.status === 'limited';
        logger.info({
          msg: 'Admin provider test selected probe',
          id: provider.id,
          name: provider.name,
          slug: provider.slug,
          provider_type: provider.provider_type,
          base_url: provider.base_url,
          selected_probe: probeName,
          result_status: status,
          result_message: probe.capability_note,
        });
        await query(
          `UPDATE api_providers
              SET health_status = ?,
                  last_success_at = IF(?, NOW(), last_success_at),
                  last_failure_at = IF(?, NOW(), last_failure_at)
            WHERE id = ?`,
          [status, healthy ? 1 : 0, healthy ? 0 : 1, request.params.id],
        );
        return {
          success: true,
          status,
          provider: provider.name,
          selected_probe: probeName,
          latency_ms: Date.now() - startedAll,
          capability_note: probe.capability_note || null,
          routes: probe.routes || [],
          message: probe.capability_note ||
            (status === 'up' ? 'Provider reachable with full capability' : `Provider ${status}`),
        };
      }
    }

    // Legacy fallback for unknown/custom providers only: exercise our own app
    // route shapes against the configured base_url.
    if (!provider.base_url) return reply.code(400).send({ success: false, error: 'Provider base URL is required' });
    const base = String(provider.base_url).replace(/\/+$/, '');
    const results = [];
    let status = 'healthy';
    let lastSuccessfulRoute = null;
    let failedRoute = null;

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
    logger.info({
      msg: 'Admin provider test selected probe',
      id: provider.id,
      name: provider.name,
      slug: provider.slug,
      provider_type: provider.provider_type,
      base_url: provider.base_url,
      selected_probe: 'legacy',
      result_status: status,
      result_message: null,
    });
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
      selected_probe: 'legacy',
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
    // Scope by provider too — the key must belong to the provider in the URL,
    // otherwise a mismatched URL deletes another provider's key.
    const old = await query(
      `SELECT id, provider_id, label FROM provider_api_keys WHERE id = ? AND provider_id = ?`,
      [request.params.keyId, request.params.id],
    );
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    await withAudit(
      request,
      { action: 'providerKey.delete', entityType: 'provider_api_key', entityId: request.params.keyId, oldValue: old[0] },
      async () => query(
        `DELETE FROM provider_api_keys WHERE id = ? AND provider_id = ?`,
        [request.params.keyId, request.params.id],
      ),
    );
    return { success: true };
  });

  // ---------- Role + priority control ----------

  fastify.post('/:id/set-primary', { preHandler: [requirePermissions('providers.write')] }, async (request, reply) => {
    const id = Number(request.params.id);
    const rows = await query(`SELECT id, name, priority FROM api_providers WHERE id = ?`, [id]);
    if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });

    await withAudit(
      request,
      { action: 'provider.setPrimary', entityType: 'api_provider', entityId: id, newValue: { role: 'primary' } },
      async () =>
        transaction(async (conn) => {
          try {
            await conn.execute(
              `UPDATE api_providers SET role = 'fallback' WHERE id <> ? AND (role = 'primary' OR role IS NULL OR role = '')`,
              [id],
            );
            const existingPriority = Number(rows[0].priority || 0);
            const newPriority = existingPriority > 0 && existingPriority < 99 ? existingPriority : 1;
            await conn.execute(
              `UPDATE api_providers SET role = 'primary', priority = ?, is_active = 1 WHERE id = ?`,
              [newPriority, id],
            );
          } catch (err) {
            if (!isMissingRoleColumn(err)) throw err;
            // role column may not exist on older DBs — store primary marker in metadata
            const meta = JSON.stringify({ role: 'primary' });
            const existingPriority = Number(rows[0].priority || 0);
            const newPriority = existingPriority > 0 && existingPriority < 99 ? existingPriority : 1;
            await conn.execute(
              `UPDATE api_providers SET priority = ?, is_active = 1, metadata = ? WHERE id = ?`,
              [newPriority, meta, id],
            );
            await conn.execute(
              `UPDATE api_providers SET metadata = JSON_SET(COALESCE(metadata, '{}'), '$.role', 'fallback') WHERE id <> ?`,
              [id],
            );
          }
        }),
    );
    providerManager.invalidateConfig();
    const updated = await query(`SELECT * FROM api_providers WHERE id = ?`, [id]);
    return { success: true, data: cleanProvider(updated[0]) };
  });

  fastify.patch('/reorder', { preHandler: [requirePermissions('providers.write')] }, async (request, reply) => {
    const { order } = request.body || {};
    if (!Array.isArray(order) || !order.length) {
      return reply.code(400).send({ success: false, error: 'order array required' });
    }
    await withAudit(
      request,
      { action: 'provider.reorder', entityType: 'api_provider', newValue: { count: order.length } },
      async () =>
        transaction(async (conn) => {
          for (const item of order) {
            if (!item.id || item.priority == null) continue;
            // eslint-disable-next-line no-await-in-loop
            await conn.execute(`UPDATE api_providers SET priority = ? WHERE id = ?`, [Number(item.priority), Number(item.id)]);
          }
        }),
    );
    providerManager.invalidateConfig();
    return { success: true };
  });

  fastify.post('/refresh-health', { preHandler: [requirePermissions('providers.write')] }, async () => {
    const rows = await query(`SELECT id, name, slug, provider_type, base_url, timeout_ms FROM api_providers ORDER BY id ASC`);
    const results = [];
    for (const row of rows) {
      const type = String(row.provider_type || '').toLowerCase();
      const slug = String(row.slug || '').toLowerCase();
      const name = String(row.name || '').toLowerCase();
      const isCricinfo =
        type === 'cricinfo' || type === 'espn' || type === 'espn-cricinfo' ||
        slug === 'cricinfo' || slug === 'espn-cricinfo' || slug === 'espn_cricinfo' ||
        name.includes('cricinfo') || name.includes('espn');
      let probeName = null;
      if (isCricinfo) probeName = 'cricinfo';
      else if (type === 'cricketdata' || name.includes('cricketdata')) probeName = 'cricketdata';
      else if (type === 'cricbuzz' || name.includes('cricbuzz')) probeName = 'cricbuzz';

      if (probeName) {
        // eslint-disable-next-line no-await-in-loop
        const probe = await probeProvider(probeName, {
          baseUrl: row.base_url,
          timeoutMs: Number(row.timeout_ms || 8000),
        });
        if (probe) {
          const status = toHealthStatus(probe.status);
          const healthy = probe.status === 'up' || probe.status === 'limited';
          // eslint-disable-next-line no-await-in-loop
          await query(
            `UPDATE api_providers
                SET health_status = ?,
                    last_success_at = IF(?, NOW(), last_success_at),
                    last_failure_at = IF(?, NOW(), last_failure_at)
              WHERE id = ?`,
            [status, healthy ? 1 : 0, healthy ? 0 : 1, row.id],
          );
          results.push({ id: row.id, name: row.name, status, capability_note: probe.capability_note || null });
        }
      }
    }
    providerManager.invalidateConfig();
    return { success: true, data: results };
  });

  fastify.post('/:id/reset-health', { preHandler: [requirePermissions('providers.write')] }, async (request, reply) => {
    const rows = await query(`SELECT id, name, provider_type FROM api_providers WHERE id = ?`, [request.params.id]);
    if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const provider = providerManager.getProvider(rows[0].provider_type);
    await query(
      `UPDATE api_providers SET health_status = 'unknown', last_failure_at = NULL WHERE id = ?`,
      [request.params.id],
    );
    if (provider) {
      provider.healthy = true;
      provider.consecutiveFailures = 0;
      provider.lastFailure = null;
    }
    providerManager.invalidateConfig();
    logger.info({ msg: 'Provider health reset by admin', id: rows[0].id, name: rows[0].name });
    return { success: true };
  });
}
