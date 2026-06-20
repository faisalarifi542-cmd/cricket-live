import { adminAuth, requirePermissions } from '../auth.js';
import { withAudit } from '../audit.js';
import { query } from '../../lib/db.js';
import {
  clearDataCache,
  ensureDataControlSchema,
  getCacheStats,
  getDataSources,
  providerFetch,
  warmDataSource,
} from '../../lib/data-control.js';
import providerManager from '../../providers/provider-manager.js';

const writable = [
  'provider_id', 'enabled', 'cache_enabled', 'cache_ttl_seconds',
  'stale_fallback_enabled', 'timeout_ms', 'retry_count', 'refresh_strategy',
  'refresh_frequency_seconds', 'show_stale_in_app', 'show_last_updated_label',
];

export default async function dataControlRoutes(fastify) {
  fastify.addHook('preHandler', adminAuth);

  fastify.get('/sources', { preHandler: [requirePermissions('cache.view')] }, async () => {
    await ensureDataControlSchema();
    return { success: true, data: await getDataSources(), cache: await getCacheStats(), providers: providerManager.getHealthStatus() };
  });

  fastify.put('/sources/:dataType', { preHandler: [requirePermissions('cache.write')] }, async (request, reply) => {
    await ensureDataControlSchema();
    const body = request.body || {};
    const data = {};
    for (const key of writable) if (body[key] !== undefined) data[key] = body[key];
    if (!Object.keys(data).length) return reply.code(400).send({ success: false, error: 'No fields to update' });
    if (['liveMatches', 'liveLine', 'matchDetail'].includes(request.params.dataType) && Number(data.cache_ttl_seconds) > 15) {
      return reply.code(400).send({ success: false, error: 'Live data TTL above 15 seconds can make scores feel delayed' });
    }
    for (const key of ['enabled', 'cache_enabled', 'stale_fallback_enabled', 'show_stale_in_app', 'show_last_updated_label']) {
      if (key in data) data[key] = data[key] ? 1 : 0;
    }
    const setClause = Object.keys(data).map((k) => `${k} = ?`).join(', ');
    await withAudit(
      request,
      { action: 'dataSource.update', entityType: 'api_data_source', entityId: request.params.dataType, newValue: data },
      () => query(`UPDATE api_data_sources SET ${setClause} WHERE data_type = ?`, [...Object.values(data), request.params.dataType]),
    );
    return { success: true, data: (await getDataSources()).find((s) => s.dataType === request.params.dataType) };
  });

  fastify.post('/sources/:dataType/clear', { preHandler: [requirePermissions('cache.write')] }, async (request) => {
    const deleted = await clearDataCache(request.params.dataType, request.body?.targetId || '*');
    await withAudit(request, { action: 'dataSource.cacheClear', entityType: 'api_data_source', entityId: request.params.dataType, newValue: { deleted } }, async () => null);
    return { success: true, deleted };
  });

  fastify.post('/sources/:dataType/warm', { preHandler: [requirePermissions('cache.write')] }, async (request) => {
    const sources = await getDataSources();
    const source = sources.find((s) => s.dataType === request.params.dataType);
    if (!source) return { success: false, error: 'Unknown data source' };
    const targetId = request.body?.targetId || 'default';
    const providerMethod = source.providerMethod;
    const result = await warmDataSource(source.dataType, targetId, async () => {
      if (!providerMethod) return { data: {}, provider: 'local' };
      const args = targetId === 'default' ? [] : [targetId];
      const fetched = await providerManager.execute(providerMethod, ...args);
      return { data: fetched.data, provider: fetched.provider };
    });
    await withAudit(request, { action: 'dataSource.cacheWarm', entityType: 'api_data_source', entityId: source.dataType }, async () => null);
    return { success: true, meta: result.meta };
  });

  fastify.post('/warm-home', { preHandler: [requirePermissions('cache.write')] }, async () => {
    const result = await providerFetch('liveMatches', 'getLiveMatches');
    return { success: true, meta: result.meta };
  });

  fastify.post('/health-check', { preHandler: [requirePermissions('health.view')] }, async () => ({
    success: true,
    data: {
      providers: providerManager.getHealthStatus(),
      cache: await getCacheStats(),
      sources: await getDataSources(),
    },
  }));
}
