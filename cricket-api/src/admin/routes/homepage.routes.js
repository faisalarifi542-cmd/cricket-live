import { adminAuth, requirePermissions } from '../auth.js';
import { withAudit } from '../audit.js';
import { query } from '../../lib/db.js';
 
export default async function homepageRoutes(fastify) {
  fastify.addHook('preHandler', adminAuth);
 
  // ---------- Homepage sections ----------
  fastify.get('/sections', { preHandler: [requirePermissions('home.view')] }, async () => {
    const rows = await query(
      `SELECT * FROM homepage_sections ORDER BY sort_order ASC, id ASC`,
    );
    return { success: true, data: rows.map((r) => ({ ...r, is_active: !!r.is_active })) };
  });
 
  fastify.post('/sections', { preHandler: [requirePermissions('home.write')] }, async (request, reply) => {
    const { slug, title, section_type, payload, sort_order = 100, is_active = true, starts_at, ends_at } = request.body || {};
    if (!slug || !title || !section_type) {
      return reply.code(400).send({ success: false, error: 'slug, title, section_type required' });
    }
    const r = await withAudit(
      request,
      { action: 'home.section.create', entityType: 'homepage_section', newValue: { slug, title, section_type } },
      async () =>
        query(
          `INSERT INTO homepage_sections (slug, title, section_type, payload, sort_order, is_active, starts_at, ends_at, updated_by)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [slug, title, section_type, payload ? JSON.stringify(payload) : null, sort_order, is_active ? 1 : 0, starts_at || null, ends_at || null, request.adminUser.id],
        ),
    );
    return reply.code(201).send({ success: true, id: r.insertId });
  });
 
  fastify.put('/sections/:id', { preHandler: [requirePermissions('home.write')] }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT * FROM homepage_sections WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const allowed = ['title', 'section_type', 'payload', 'sort_order', 'is_active', 'starts_at', 'ends_at'];
    const data = {};
    for (const k of allowed) if (request.body[k] !== undefined) data[k] = request.body[k];
    if ('payload' in data && data.payload != null) data.payload = JSON.stringify(data.payload);
    if ('is_active' in data) data.is_active = data.is_active ? 1 : 0;
    if (!Object.keys(data).length) return reply.code(400).send({ success: false, error: 'No fields' });
    const setClause = Object.keys(data).map((k) => `${k} = ?`).join(', ');
    await withAudit(
      request,
      { action: 'home.section.update', entityType: 'homepage_section', entityId: id, oldValue: old[0], newValue: data },
      async () =>
        query(`UPDATE homepage_sections SET ${setClause}, updated_by = ? WHERE id = ?`, [
          ...Object.values(data),
          request.adminUser.id,
          id,
        ]),
    );
    return { success: true };
  });
 
  fastify.delete('/sections/:id', { preHandler: [requirePermissions('home.write')] }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT * FROM homepage_sections WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    await withAudit(
      request,
      { action: 'home.section.delete', entityType: 'homepage_section', entityId: id, oldValue: old[0] },
      async () => query(`DELETE FROM homepage_sections WHERE id = ?`, [id]),
    );
    return { success: true };
  });
 
  // ---------- Featured matches / series / news ----------
  for (const [path, table, idField] of [
    ['featured-matches', 'featured_matches', 'match_external_id'],
    ['featured-series', 'featured_series', 'series_external_id'],
    ['featured-news', 'featured_news', 'news_id'],
  ]) {
    fastify.get(`/${path}`, { preHandler: [requirePermissions('home.view')] }, async () => {
      const rows = await query(`SELECT * FROM ${table} ORDER BY sort_order ASC, id ASC`);
      return { success: true, data: rows.map((r) => ({ ...r, is_active: !!r.is_active })) };
    });
    fastify.post(`/${path}`, { preHandler: [requirePermissions('home.write')] }, async (request, reply) => {
      const body = request.body || {};
      if (!body[idField]) return reply.code(400).send({ success: false, error: `${idField} required` });
      const cols = [idField, 'sort_order', 'is_active', 'note', 'created_by'];
      const vals = [body[idField], body.sort_order ?? 100, body.is_active === false ? 0 : 1, body.note || null, request.adminUser.id];
      if (table === 'featured_matches') {
        cols.push('starts_at', 'ends_at');
        vals.push(body.starts_at || null, body.ends_at || null);
      }
      const r = await withAudit(
        request,
        { action: `${table}.create`, entityType: table, newValue: body },
        async () => query(`INSERT INTO ${table} (${cols.join(', ')}) VALUES (${cols.map(() => '?').join(', ')})`, vals),
      );
      return reply.code(201).send({ success: true, id: r.insertId });
    });
    fastify.delete(`/${path}/:id`, { preHandler: [requirePermissions('home.write')] }, async (request, reply) => {
      const old = await query(`SELECT * FROM ${table} WHERE id = ?`, [request.params.id]);
      if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
      await withAudit(
        request,
        { action: `${table}.delete`, entityType: table, entityId: request.params.id, oldValue: old[0] },
        async () => query(`DELETE FROM ${table} WHERE id = ?`, [request.params.id]),
      );
      return { success: true };
    });
  }
 
  // ---------- Banners ----------
  fastify.get('/banners', { preHandler: [requirePermissions('home.view')] }, async () => {
    const rows = await query(`SELECT * FROM app_banners ORDER BY sort_order ASC, id ASC`);
    return { success: true, data: rows.map((r) => ({ ...r, is_active: !!r.is_active })) };
  });
 
  fastify.post('/banners', { preHandler: [requirePermissions('home.write')] }, async (request, reply) => {
    const { placement, title, subtitle, image_url, cta_label, cta_url, sort_order = 100, is_active = true, starts_at, ends_at } = request.body || {};
    if (!placement) return reply.code(400).send({ success: false, error: 'placement required' });
    const r = await withAudit(
      request,
      { action: 'banner.create', entityType: 'app_banner', newValue: { placement, title } },
      async () =>
        query(
          `INSERT INTO app_banners (placement, title, subtitle, image_url, cta_label, cta_url, sort_order, is_active, starts_at, ends_at, created_by)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          [placement, title || null, subtitle || null, image_url || null, cta_label || null, cta_url || null, sort_order, is_active ? 1 : 0, starts_at || null, ends_at || null, request.adminUser.id],
        ),
    );
    return reply.code(201).send({ success: true, id: r.insertId });
  });
 
  fastify.delete('/banners/:id', { preHandler: [requirePermissions('home.write')] }, async (request, reply) => {
    const old = await query(`SELECT * FROM app_banners WHERE id = ?`, [request.params.id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    await withAudit(
      request,
      { action: 'banner.delete', entityType: 'app_banner', entityId: request.params.id, oldValue: old[0] },
      async () => query(`DELETE FROM app_banners WHERE id = ?`, [request.params.id]),
    );
    return { success: true };
  });
}