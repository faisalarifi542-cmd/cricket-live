import { cacheGetOrFetch, KEYS, TTL } from '../lib/redis.js';
import providerManager from '../providers/provider-manager.js';
import { cacheMiddleware } from '../middleware/cache.js';
import { playerStatsQueue } from '../workers/queues.js';

export default async function playerRoutes(fastify) {
  // GET /player/:id
  fastify.get('/player/:id', {
    schema: {
      description: 'Get player info and career stats',
      tags: ['Players'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
    preHandler: cacheMiddleware((req) => KEYS.player(req.params.id), TTL.PLAYER),
  }, async (request, reply) => {
    const { id } = request.params;
    const { data } = await cacheGetOrFetch(
      KEYS.player(id),
      TTL.PLAYER,
      async () => {
        const result = await providerManager.execute('getPlayerInfo', id);
        // Queue background DB persistence
        await playerStatsQueue.add('persist-player', { playerId: id }, {
          jobId: `player-${id}`,
          delay: 0,
        }).catch(() => {}); // non-critical
        return result.data;
      }
    );
    if (!data) return reply.code(404).send({ success: false, error: 'Player not found' });
    return { success: true, data };
  });

  // GET /team/:id
  fastify.get('/team/:id', {
    schema: {
      description: 'Get team info and squad',
      tags: ['Teams'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
    preHandler: cacheMiddleware((req) => KEYS.team(req.params.id), TTL.TEAM),
  }, async (request, reply) => {
    const { id } = request.params;
    const { data } = await cacheGetOrFetch(
      KEYS.team(id),
      TTL.TEAM,
      async () => (await providerManager.execute('getTeamInfo', id)).data
    );
    if (!data) return reply.code(404).send({ success: false, error: 'Team not found' });
    return { success: true, data };
  });
}
