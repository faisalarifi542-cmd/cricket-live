import Fastify from 'fastify';
import cors from '@fastify/cors';
import cookie from '@fastify/cookie';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import jwt from '@fastify/jwt';
import websocket from '@fastify/websocket';
import swagger from '@fastify/swagger';
import swaggerUi from '@fastify/swagger-ui';

import config from './config/index.js';
import logger from './lib/logger.js';
import { shutdownRedis } from './lib/redis.js';
import { shutdownDb } from './lib/db.js';
import { httpRequestDuration, httpRequestTotal } from './lib/metrics.js';
import { registerWebSocket, shutdownGateway } from './websocket/gateway.js';
import { cacheOnSend } from './middleware/cache.js';
import { apiKeyAuth } from './middleware/auth.js';
import {
  sqlInjectionProtection,
  xssProtection,
  blockSuspiciousIPs,
  requestSizeLimit,
  securityHeaders,
  validateContentType,
  logSuspiciousActivity,
} from './middleware/security.js';

import matchRoutes from './routes/matches.js';
import seriesRoutes from './routes/series.js';
import playerRoutes from './routes/players.js';
import healthRoutes from './routes/health.js';
import adminRoutes from './routes/admin.js';
import adminPanelRoutes from './admin/index.js';
import newsRoutes from './routes/news.js';
import scheduleRoutes from './routes/schedule.js';
import appRoutes from './routes/app.js';

async function buildServer() {
  const fastify = Fastify({
    logger: false, // use Winston instead
    trustProxy: true,
    routerOptions: {
      caseSensitive: true,
      maxParamLength: 200,
    },
    bodyLimit: 1_048_576, // 1MB
    keepAliveTimeout: 72_000,
  });

  // ====================================================
  // Plugins
  // ====================================================
  await fastify.register(cors, {
    origin: config.cors.origin === '*' ? true : config.cors.origin.split(','),
    methods: ['GET', 'POST', 'PUT', 'DELETE'],
    allowedHeaders: ['Content-Type', 'Authorization', config.auth.apiKeyHeader],
    credentials: true,
  });

  await fastify.register(cookie);

  await fastify.register(helmet, {
    contentSecurityPolicy: false,
    crossOriginResourcePolicy: { policy: 'cross-origin' },
    hsts: {
      maxAge: 31536000,
      includeSubDomains: true,
    },
  });

  await fastify.register(rateLimit, {
    max: config.rateLimit.max,
    timeWindow: config.rateLimit.timeWindow,
    keyGenerator: (req) => req.headers[config.auth.apiKeyHeader] || req.ip,
    errorResponseBuilder: (req, context) => ({
      error: 'Rate limit exceeded',
      limit: context.max,
      remaining: 0,
      reset: Math.ceil(context.ttl / 1000),
    }),
  });

  await fastify.register(jwt, {
    secret: config.auth.jwtSecret,
    sign: { expiresIn: config.auth.jwtExpiresIn },
  });

  await fastify.register(websocket, {
    options: {
      maxPayload: 65536,
      perMessageDeflate: true,
    },
  });

  await fastify.register(swagger, {
    openapi: {
      info: {
        title: 'Cricket Scoring API',
        description: 'Production-ready live cricket scoring API with real-time updates',
        version: '1.0.0',
      },
      servers: [{ url: `http://localhost:${config.server.port}` }],
      tags: [
        { name: 'Matches', description: 'Live, upcoming, and recent matches' },
        { name: 'Series', description: 'Series and points tables' },
        { name: 'Players', description: 'Player info and stats' },
        { name: 'Teams', description: 'Team info' },
        { name: 'News', description: 'Cricket news stories' },
        { name: 'Schedule', description: 'Upcoming match schedules by day' },
        { name: 'System', description: 'Health, metrics, providers' },
        { name: 'Admin', description: 'Admin management' },
      ],
    },
  });

  await fastify.register(swaggerUi, {
    routePrefix: '/docs',
    uiConfig: { deepLinking: true },
  });

  // ====================================================
  // Hooks
  // ====================================================

  // Security middleware
  fastify.addHook('onRequest', securityHeaders);
  fastify.addHook('onRequest', blockSuspiciousIPs);
  fastify.addHook('onRequest', requestSizeLimit);
  fastify.addHook('onRequest', validateContentType);
  fastify.addHook('preValidation', sqlInjectionProtection);
  fastify.addHook('preValidation', xssProtection);
  fastify.addHook('onRequest', logSuspiciousActivity);

  // Request timing + metrics
  fastify.addHook('onRequest', async (request) => {
    request.startTime = process.hrtime.bigint();
  });

  fastify.addHook('onResponse', async (request, reply) => {
    const duration = Number(process.hrtime.bigint() - request.startTime) / 1e9;
    const route = request.routeOptions?.url || request.routerPath || request.url;

    httpRequestDuration.observe(
      { method: request.method, route, status_code: reply.statusCode },
      duration
    );
    httpRequestTotal.inc({ method: request.method, route, status_code: reply.statusCode });

    logger.debug({
      msg: 'request',
      method: request.method,
      url: request.url,
      status: reply.statusCode,
      duration: `${(duration * 1000).toFixed(1)}ms`,
      ip: request.ip,
    });
  });

  // Cache response hook
  fastify.addHook('onSend', cacheOnSend);

  // Global error handler
  fastify.setErrorHandler((error, request, reply) => {
    logger.error({
      msg: 'Request error',
      url: request.url,
      method: request.method,
      error: error.message,
      stack: config.isDev ? error.stack : undefined,
    });

    const statusCode = error.statusCode || 500;
    return reply.code(statusCode).send({
      success: false,
      error: statusCode === 500 ? 'Internal server error' : error.message,
      ...(config.isDev && { stack: error.stack }),
    });
  });

  // ====================================================
  // API Key auth for API routes (optional — public access allowed)
  // ====================================================
  fastify.addHook('preHandler', apiKeyAuth);

  // ====================================================
  // Routes
  // ====================================================
  await fastify.register(healthRoutes);
  await fastify.register(matchRoutes);
  await fastify.register(seriesRoutes);
  await fastify.register(playerRoutes);
  await fastify.register(newsRoutes);
  await fastify.register(scheduleRoutes);
  await fastify.register(appRoutes);

  // Keep the old username/password admin API away from the new admin panel.
  // The Next.js admin panel posts email/password to /admin/login.
  await fastify.register(adminRoutes, { prefix: '/admin/legacy' });
  await fastify.register(adminPanelRoutes);

  // ====================================================
  // WebSocket
  // ====================================================
  registerWebSocket(fastify);

  // ====================================================
  // 404 handler
  // ====================================================
  fastify.setNotFoundHandler((request, reply) => {
    reply.code(404).send({
      success: false,
      error: 'Route not found',
      path: request.url,
    });
  });

  return fastify;
}

// ====================================================
// Start server
// ====================================================
async function start() {
  const server = await buildServer();

  try {
    await server.listen({ port: config.server.port, host: config.server.host });
    logger.info(`🏏 Cricket Scoring API running on http://${config.server.host}:${config.server.port}`);
    logger.info(`📖 API docs: http://localhost:${config.server.port}/docs`);
    logger.info(`🔌 WebSocket: ws://localhost:${config.server.port}/ws`);
    logger.info(`📊 Metrics: http://localhost:${config.server.port}/metrics`);
  } catch (err) {
    logger.error({ msg: 'Server startup failed', error: err.message });
    console.error(err);
    process.exit(1);
  }

  // Graceful shutdown
  const shutdown = async (signal) => {
    logger.info({ msg: 'Shutting down server', signal });
    shutdownGateway();
    await server.close();
    await shutdownRedis();
    await shutdownDb();
    logger.info('Server shut down gracefully');
    process.exit(0);
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('unhandledRejection', (err) => {
    logger.error({ msg: 'Unhandled rejection', error: err?.message, stack: err?.stack });
  });
}

start();
