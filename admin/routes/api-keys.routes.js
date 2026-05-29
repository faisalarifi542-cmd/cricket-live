/**
 * Public API key management (the keys Flutter clients use, not provider keys).
 * Stored in the existing `api_keys` table created by the original migrate.js.
 */
import bcrypt from 'bcryptjs';
import { nanoid } from 'nanoid';
import { adminAuth, requirePermissions } from '../auth.js';
import { withAudit } from '../audit.js';
import { query } from '../../lib/db.js';
 
export default async function apiKeyRoutes(fastify) {
  fastify.addHook('preHandler', adminAuth);
 
  fastify.get('/', { preHandler: [requirePermissions('apiKeys.view')] }, async () => {
    const rows = await query(
      `SELECT id, name, email, tier, rate_limit, is_active, last_used_at, expires_at, created_at
         FROM api_keys ORDER BY created_at DESC`,
    );
    return {
      success: true,
      data: rows.map((r) => ({ ...r, is_active: !!r.is_active })),
    };
  });
 
  fastify.post('/', { preHandler: [requirePermissions('apiKeys.write')] }, async (request, reply) => {
    const { name, email, tier = 'free', rate_limit = 100, expires_in_days } = request.body || {};
    if (!name || name.length < 3) {
      return reply.code(400).send({ success: false, error: 'name (>=3 chars) required' });
    }
    const raw = `csk_${nanoid(48)}`;
    const hash = await bcrypt.hash(raw, 12);
    const expiresAt = expires_in_days ? new Date(Date.now() + expires_in_days * 24 * 60 * 60 * 1000) : null;
    await withAudit(
      request,
      { action: 'apiKey.create', entityType: 'api_key', newValue: { name, tier, rate_limit } },
      async () =>
        query(
          `INSERT INTO api_keys (key_hash, name, email, tier, rate_limit, expires_at)
           VALUES (?, ?, ?, ?, ?, ?)`,
          [hash, name.trim(), email ? email.trim().toLowerCase() : null, tier, rate_limit, expiresAt],
        ),
    );
    return reply.code(201).send({
      success: true,
      api_key: raw,
      tier,
      rate_limit,
      expires_at: expiresAt,
      warning: 'Store this key now. The raw value cannot be retrieved again.',
    });
  });
 
  fastify.patch('/:id', { preHandler: [requirePermissions('apiKeys.write')] }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT id, name, tier, rate_limit, is_active FROM api_keys WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const allowed = ['name', 'email', 'tier', 'rate_limit', 'is_active'];
    const data = {};
    for (const k of allowed) if (request.body[k] !== undefined) data[k] = request.body[k];
    if ('is_active' in data) data.is_active = data.is_active ? 1 : 0;
    if (!Object.keys(data).length) return reply.code(400).send({ success: false, error: 'No fields' });
    const setClause = Object.keys(data).map((k) => `${k} = ?`).join(', ');
    await withAudit(
      request,
      { action: 'apiKey.update', entityType: 'api_key', entityId: id, oldValue: old[0], newValue: data },
      async () => query(`UPDATE api_keys SET ${setClause} WHERE id = ?`, [...Object.values(data), id]),
    );
    return { success: true };
  });
 
  fastify.delete('/:id', { preHandler: [requirePermissions('apiKeys.write')] }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT id, name FROM api_keys WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    await withAudit(
      request,
      { action: 'apiKey.delete', entityType: 'api_key', entityId: id, oldValue: old[0] },
      async () => query(`DELETE FROM api_keys WHERE id = ?`, [id]),
    );
    return { success: true };
  });
}