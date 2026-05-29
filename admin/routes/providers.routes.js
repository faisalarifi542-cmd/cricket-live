import { adminAuth, requirePermissions } from '../auth.js';
import { withAudit } from '../audit.js';
import { query } from '../../lib/db.js';
 
export default async function providerRoutes(fastify) {
  fastify.addHook('preHandler', adminAuth);
 
  fastify.get('/', { preHandler: [requirePermissions('providers.view')] }, async () => {
    const rows = await query(
      `SELECT * FROM api_providers ORDER BY priority ASC, name ASC`,
    );
    return {
      success: true,
      data: rows.map((r) => ({ ...r, is_active: !!r.is_active })),
    };
  });
 
  fastify.post('/', { preHandler: [requirePermissions('providers.write')] }, async (request, reply) => {
    const { slug, name, base_url, description, priority = 100, is_active = true, metadata } = request.body || {};
    if (!slug || !name) {
      return reply.code(400).send({ success: false, error: 'slug and name required' });
    }
    const r = await withAudit(
      request,
      { action: 'provider.create', entityType: 'api_provider', newValue: { slug, name } },
      async () =>
        query(
          `INSERT INTO api_providers (slug, name, base_url, description, priority, is_active, metadata)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
          [slug, name, base_url || null, description || null, priority, is_active ? 1 : 0, metadata ? JSON.stringify(metadata) : null],
        ),
    );
    const row = await query(`SELECT * FROM api_providers WHERE id = ?`, [r.insertId]);
    return reply.code(201).send({ success: true, data: { ...row[0], is_active: !!row[0].is_active } });
  });
 
  fastify.put('/:id', { preHandler: [requirePermissions('providers.write')] }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT * FROM api_providers WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const allowed = ['name', 'base_url', 'description', 'priority', 'is_active', 'metadata', 'health_status'];
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
    return { success: true, data: { ...row[0], is_active: !!row[0].is_active } };
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
    return { success: true };
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