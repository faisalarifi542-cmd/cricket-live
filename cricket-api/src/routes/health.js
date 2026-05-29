import { getRedis } from '../lib/redis.js';
import { getPool } from '../lib/db.js';
import { register } from '../lib/metrics.js';
import providerManager from '../providers/provider-manager.js';
import { getGatewayStats } from '../websocket/gateway.js';

export default async function healthRoutes(fastify) {
  // GET /health — basic liveness check
  fastify.get('/health', {
    schema: { description: 'Health check', tags: ['System'] },
  }, async (request, reply) => {
    const checks = {};
    let healthy = true;

    // Redis check
    try {
      const start = Date.now();
      await getRedis().ping();
      checks.redis = { status: 'ok', latency: Date.now() - start };
    } catch (err) {
      checks.redis = { status: 'error', error: err.message };
      healthy = false;
    }

    // MySQL check
    try {
      const start = Date.now();
      await getPool().execute('SELECT 1');
      checks.mysql = { status: 'ok', latency: Date.now() - start };
    } catch (err) {
      checks.mysql = { status: 'error', error: err.message };
      healthy = false;
    }

    // Providers
    checks.providers = providerManager.getHealthStatus();

    // WebSocket
    try {
      checks.websocket = getGatewayStats();
    } catch {
      checks.websocket = { status: 'not_initialized' };
    }

    const statusCode = healthy ? 200 : 503;
    return reply.code(statusCode).send({
      status: healthy ? 'healthy' : 'degraded',
      uptime: process.uptime(),
      timestamp: new Date().toISOString(),
      version: process.env.npm_package_version || '1.0.0',
      checks,
    });
  });

  // GET /health/ready — readiness probe for k8s/docker
  fastify.get('/health/ready', {
    schema: { description: 'Readiness probe', tags: ['System'] },
  }, async (request, reply) => {
    try {
      await Promise.all([
        getRedis().ping(),
        getPool().execute('SELECT 1'),
      ]);
      return { status: 'ready' };
    } catch {
      return reply.code(503).send({ status: 'not_ready' });
    }
  });

  // GET /metrics — Prometheus metrics
  fastify.get('/metrics', {
    schema: { description: 'Prometheus metrics endpoint', tags: ['System'] },
  }, async (request, reply) => {
    reply.header('Content-Type', register.contentType);
    return register.metrics();
  });

  // GET /providers — provider health status
  fastify.get('/providers', {
    schema: { description: 'Data provider health status', tags: ['System'] },
  }, async (request, reply) => {
    return {
      success: true,
      data: providerManager.getHealthStatus(),
    };
  });
}
