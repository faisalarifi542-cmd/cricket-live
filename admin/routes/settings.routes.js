import { adminAuth, requirePermissions } from '../auth.js';
import { withAudit } from '../audit.js';
import { query } from '../../lib/db.js';
 
export default async function settingsRoutes(fastify) {
  fastify.addHook('preHandler', adminAuth);
 
  fastify.get('/', { preHandler: [requirePermissions('settings.view')] }, async (request) => {
    const { group } = request.query;
    const rows = group
      ? await query(`SELECT * FROM app_settings WHERE setting_group = ? ORDER BY setting_key`, [group])
      : await query(`SELECT * FROM app_settings ORDER BY setting_group, setting_key`);
    return { success: true, data: rows };
  });
 
  fastify.get('/:key', { preHandler: [requirePermissions('settings.view')] }, async (request, reply) => {
    const rows = await query(`SELECT * FROM app_settings WHERE setting_key = ?`, [request.params.key]);
    if (!rows.length) return reply.code(404).send({ success: false, error: 'Not found' });
    return { success: true, data: rows[0] };
  });
 
  fastify.put('/:key', { preHandler: [requirePermissions('settings.write')] }, async (request, reply) => {
    const { setting_value, setting_group, description } = request.body || {};
    if (setting_value === undefined) return reply.code(400).send({ success: false, error: 'setting_value required' });
    const old = await query(`SELECT * FROM app_settings WHERE setting_key = ?`, [request.params.key]);
    const value = JSON.stringify(setting_value);
    await withAudit(
      request,
      {
        action: 'setting.update',
        entityType: 'app_setting',
        entityId: request.params.key,
        oldValue: old[0] || null,
        newValue: { setting_value, setting_group, description },
      },
      async () =>
        query(
          `INSERT INTO app_settings (setting_key, setting_value, setting_group, description, updated_by)
             VALUES (?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value),
                                     setting_group = COALESCE(VALUES(setting_group), setting_group),
                                     description = COALESCE(VALUES(description), description),
                                     updated_by = VALUES(updated_by)`,
          [
            request.params.key,
            value,
            setting_group || 'general',
            description || null,
            request.adminUser.id,
          ],
        ),
    );
    const row = await query(`SELECT * FROM app_settings WHERE setting_key = ?`, [request.params.key]);
    return { success: true, data: row[0] };
  });
}