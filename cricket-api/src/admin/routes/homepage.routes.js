import { adminAuth, requirePermissions } from '../auth.js';
import { withAudit } from '../audit.js';
import { query } from '../../lib/db.js';
import { loadHomeLayout, saveHomeLayout } from '../../lib/home-layout.js';
import { saveBase64Image } from '../../lib/uploads.js';
import { invalidatePublicConfigCaches } from '../../lib/public-cache-invalidation.js';

export default async function homepageRoutes(fastify) {
  fastify.addHook('preHandler', adminAuth);

  // Every mutating homepage endpoint (layout, sections, banners, featured
  // series/matches/news, reorder) changes data the public /app/home + /app/config
  // payloads embed. Invalidate the shared public caches once, after any successful
  // write, instead of repeating the call in all ~13 handlers. GETs and failed
  // writes (4xx/5xx) are skipped so reads stay cheap and a rejected edit doesn't
  // needlessly clear warm caches.
  fastify.addHook('onResponse', async (request, reply) => {
    if (request.method === 'GET') return;
    if (reply.statusCode >= 400) return;
    await invalidatePublicConfigCaches();
  });

  // ---------- Image upload (base64 JSON → saved file + public URL) ----------
  // Used by the Featured Series form to upload a poster instead of pasting a
  // link. Returns an absolute URL pointing at the public /uploads/:file route.
  fastify.post(
    '/upload-image',
    { preHandler: [requirePermissions('home.write')], bodyLimit: 8 * 1024 * 1024 },
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
          { action: 'home.image.upload', entityType: 'upload', newValue: { url, bytes } },
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

  // ---------- Global home layout (section toggles / order / sources) ----------
  fastify.get('/layout', { preHandler: [requirePermissions('home.view')] }, async () => {
    const data = await loadHomeLayout();
    return { success: true, data };
  });

  fastify.put('/layout', { preHandler: [requirePermissions('home.write')] }, async (request) => {
    const saved = await withAudit(
      request,
      { action: 'home.layout.update', entityType: 'home_layout', newValue: request.body },
      async () => saveHomeLayout(request.body, request.adminUser.id),
    );
    return { success: true, data: saved };
  });
 
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
 
  // ---------- Featured series (manual, admin-managed) ----------
  // The cricket provider has no "featured series" feed, so these are created
  // by hand in the Admin Panel with a poster, name, date range and location.
  // series_external_id is optional and only used when an operator wants the
  // card to deep-link to a real provider series.
  const SERIES_FIELDS = [
    'series_external_id', 'title', 'subtitle', 'date_range', 'location',
    'image_url', 'cta_label', 'cta_url', 'sort_order', 'is_active', 'note',
    'starts_at', 'ends_at',
    // Series hero banner fields.
    'format_text', 'team_a_name', 'team_a_short', 'team_a_logo',
    'team_b_name', 'team_b_short', 'team_b_logo',
  ];

  fastify.get('/featured-series', { preHandler: [requirePermissions('home.view')] }, async () => {
    const rows = await query(`SELECT * FROM featured_series ORDER BY sort_order ASC, id ASC`);
    return { success: true, data: rows.map((r) => ({ ...r, is_active: !!r.is_active })) };
  });

  fastify.post('/featured-series', { preHandler: [requirePermissions('home.write')] }, async (request, reply) => {
    const body = request.body || {};
    const title = (body.title || '').trim();
    const externalId = (body.series_external_id || '').trim();
    // A manual series needs at least a title; a provider-linked one needs an id.
    if (!title && !externalId) {
      return reply.code(400).send({ success: false, error: 'title or series_external_id required' });
    }
    const cols = {
      series_external_id: externalId || null,
      title: title || null,
      subtitle: body.subtitle || null,
      date_range: body.date_range || null,
      location: body.location || null,
      image_url: body.image_url || null,
      cta_label: body.cta_label || null,
      cta_url: body.cta_url || null,
      sort_order: body.sort_order ?? 100,
      is_active: body.is_active === false ? 0 : 1,
      note: body.note || null,
      starts_at: body.starts_at || null,
      ends_at: body.ends_at || null,
      format_text: body.format_text || null,
      team_a_name: body.team_a_name || null,
      team_a_short: body.team_a_short || null,
      team_a_logo: body.team_a_logo || null,
      team_b_name: body.team_b_name || null,
      team_b_short: body.team_b_short || null,
      team_b_logo: body.team_b_logo || null,
      created_by: request.adminUser.id,
    };
    const keys = Object.keys(cols);
    let r;
    try {
      r = await withAudit(
        request,
        { action: 'featured_series.create', entityType: 'featured_series', newValue: { title, externalId } },
        async () => query(
          `INSERT INTO featured_series (${keys.join(', ')}) VALUES (${keys.map(() => '?').join(', ')})`,
          Object.values(cols),
        ),
      );
    } catch (err) {
      if (err && (err.code === 'ER_BAD_FIELD_ERROR' || err.code === 'ER_NO_DEFAULT_FOR_FIELD')) {
        return reply.code(503).send({
          success: false,
          error: 'featured_series schema is out of date. Run the database migration (node src/db/migrate.js) to add/relax the required columns.',
          detail: err.sqlMessage || String(err.message || err),
        });
      }
      throw err;
    }
    return reply.code(201).send({ success: true, id: r.insertId });
  });

  fastify.put('/featured-series/:id', { preHandler: [requirePermissions('home.write')] }, async (request, reply) => {
    const id = request.params.id;
    const old = await query(`SELECT * FROM featured_series WHERE id = ?`, [id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    const data = {};
    for (const k of SERIES_FIELDS) if (request.body[k] !== undefined) data[k] = request.body[k];
    if ('is_active' in data) data.is_active = data.is_active ? 1 : 0;
    if (!Object.keys(data).length) return reply.code(400).send({ success: false, error: 'No fields' });
    const setClause = Object.keys(data).map((k) => `${k} = ?`).join(', ');
    try {
      await withAudit(
        request,
        { action: 'featured_series.update', entityType: 'featured_series', entityId: id, oldValue: old[0], newValue: data },
        async () => query(`UPDATE featured_series SET ${setClause} WHERE id = ?`, [...Object.values(data), id]),
      );
    } catch (err) {
      if (err && (err.code === 'ER_BAD_FIELD_ERROR' || err.code === 'ER_NO_DEFAULT_FOR_FIELD')) {
        return reply.code(503).send({
          success: false,
          error: 'featured_series schema is out of date. Run the database migration (node src/db/migrate.js) to add/relax the required columns.',
          detail: err.sqlMessage || String(err.message || err),
        });
      }
      throw err;
    }
    return { success: true };
  });

  fastify.delete('/featured-series/:id', { preHandler: [requirePermissions('home.write')] }, async (request, reply) => {
    const old = await query(`SELECT * FROM featured_series WHERE id = ?`, [request.params.id]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    await withAudit(
      request,
      { action: 'featured_series.delete', entityType: 'featured_series', entityId: request.params.id, oldValue: old[0] },
      async () => query(`DELETE FROM featured_series WHERE id = ?`, [request.params.id]),
    );
    return { success: true };
  });

  // Bulk reorder: body = { order: [id1, id2, ...] }
  fastify.put('/featured-series-order', { preHandler: [requirePermissions('home.write')] }, async (request, reply) => {
    const order = Array.isArray(request.body?.order) ? request.body.order : [];
    if (!order.length) return reply.code(400).send({ success: false, error: 'order array required' });
    await withAudit(
      request,
      { action: 'featured_series.reorder', entityType: 'featured_series', newValue: { order } },
      async () => {
        for (let i = 0; i < order.length; i += 1) {
          await query(`UPDATE featured_series SET sort_order = ? WHERE id = ?`, [(i + 1) * 10, order[i]]);
        }
      },
    );
    return { success: true };
  });

  // ---------- Featured matches / news ----------
  for (const [path, table, idField] of [
    ['featured-matches', 'featured_matches', 'match_external_id'],
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