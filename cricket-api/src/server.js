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
import { startPhase1bWarmers, stopPhase1bWarmers } from './lib/phase1b-warmers.js';
import providerManager from './providers/provider-manager.js';
import { cacheOnSend } from './middleware/cache.js';
import { enrichTeamLogos } from './lib/team-logos.js';
import { enrichPlayerImages } from './lib/player-images.js';
import {
  apiSecurityMiddleware,
  apiSecurityResponseLog,
  corsOriginDelegate,
} from './lib/api-security.js';
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
import rankingsRoutes from './routes/rankings.js';
import analyticsRoutes from './routes/analytics.js';

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
  // CORS is dynamic: allowed origins come from the Admin Panel
  // (api_allowed_origins) plus the configured admin panel origin and localhost
  // in development. Requests without an Origin header (mobile apps / servers)
  // are allowed here and validated via X-API-Key in apiSecurityMiddleware.
  await fastify.register(cors, {
    origin: corsOriginDelegate,
    methods: ['GET', 'POST', 'PUT', 'DELETE'],
    allowedHeaders: [
      'Content-Type',
      'Authorization',
      config.auth.apiKeyHeader,
      'X-Client-Type',
      'X-App-Version',
      'X-Package-Name',
      'X-Bundle-Id',
      'X-Device-Id',
    ],
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

  // Strip the framework fingerprint header if any plugin sets it.
  fastify.addHook('onSend', async (request, reply, payload) => {
    reply.removeHeader('x-powered-by');
    // Live endpoints must never be cached by the browser, Dio/OkHttp, or any
    // CDN/proxy in front of the API — a stale live score is the exact bug we
    // are fixing. Force no-store on the live family. Static/admin routes keep
    // their own (long) Cache-Control set explicitly elsewhere.
    const url = (request.raw?.url || '').split('?')[0];
    const isLiveEndpoint =
      url === '/app/home' ||
      url === '/app/live-scores' ||
      url === '/app/live-commentary' ||
      url === '/matches/live' ||
      /^\/match\/[^/]+$/.test(url) ||
      /^\/match\/[^/]+\/(scorecard|commentary|overs|live-line|live-center|innings)$/.test(url) ||
      /^\/app\/match\/[^/]+$/.test(url);
    if (isLiveEndpoint) {
      reply.header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');
      reply.header('Pragma', 'no-cache');
    }
    return payload;
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

  // Swagger/docs UI exposes the full API map. Off by default in production to
  // avoid handing attackers an endpoint inventory. Override with SWAGGER_ENABLED=true.
  const swaggerEnabled = process.env.SWAGGER_ENABLED
    ? process.env.SWAGGER_ENABLED === 'true'
    : !config.isProd;

  if (swaggerEnabled) {
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
  }

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

    // Dedicated live-score freshness log: makes stale-cache regressions visible
    // in production (endpoint, matchId, cache status/age, provider time). Only
    // fires for the live family so it does not flood logs.
    const liveUrl = (request.raw?.url || '').split('?')[0];
    const liveMatch = liveUrl.match(/^\/(?:app\/)?match\/([^/]+)/);
    const isLiveFamily =
      liveUrl === '/app/home' ||
      liveUrl === '/matches/live' ||
      Boolean(liveMatch);
    if (isLiveFamily) {
      logger.info({
        msg: 'live-fetch',
        endpoint: liveUrl,
        matchId: liveMatch?.[1] || null,
        cache: reply.getHeader('X-Cache') || null,
        cacheAgeMs: reply.getHeader('X-Cache-Age-Ms') || null,
        stale: reply.getHeader('X-Stale') ? true : false,
        status: reply.statusCode,
        durationMs: Number((duration * 1000).toFixed(1)),
      });
    }
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
  // API access security for all incoming requests.
  // Enforces endpoint rules, blocklist, origin, API key, client type, and
  // rate limits (controlled from the Admin Panel). Does NOT affect outbound
  // provider calls. Admin routes still self-enforce JWT/RBAC.
  // ====================================================
  fastify.addHook('preHandler', apiSecurityMiddleware);

  // Write a request log (no secrets) after each response.
  fastify.addHook('onResponse', apiSecurityResponseLog);

  // ====================================================
  // Admin-managed team logos.
  // A single preSerialization hook injects the Admin-Panel uploaded logo into
  // every team object of every public response (Home, Matches, Schedule,
  // Series, Series details, Match details, Scorecard, Squads, Live, ...), so
  // the app is admin-logo dependent everywhere with the provider logo as the
  // automatic fallback. Admin/internal responses are skipped.
  //
  // Player images are enriched in the same hook, right after team logos, so
  // every player object across the same responses resolves to the
  // admin/provider/initials image according to the global mode + per-player
  // overrides. Both steps are defensive and never break a response.
  // ====================================================
  fastify.addHook('preSerialization', async (request, reply, payload) => {
    const url = request.raw?.url || request.url || '';
    if (url.startsWith('/admin') || url.startsWith('/uploads') || url.startsWith('/docs')) {
      return payload;
    }
    let result = payload;
    try {
      result = await enrichTeamLogos(result);
    } catch {
      // keep result as-is
    }
    try {
      result = await enrichPlayerImages(result);
    } catch {
      // keep result as-is
    }
    return result;
  });

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
  await fastify.register(rankingsRoutes);
  await fastify.register(analyticsRoutes);

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

    // Log resolved provider config + reset in-memory health for this fresh
    // process (each PM2 worker records its own runtime order; a restarted
    // process must never inherit a stale "down").
    providerManager.logStartupConfig().catch((err) => {
      logger.warn({ msg: 'Provider startup config log failed', error: err.message });
    });

    // Phase 1b — start in-process cache warmers a moment after the server is up
    // (so Redis/DB connections are ready). Master kill switch: ENABLE_PHASE1B_WARMING.
    setTimeout(() => {
      try { startPhase1bWarmers(); } catch (err) {
        logger.error({ msg: 'Failed to start Phase 1b warmers', error: err.message });
      }
    }, 3000);
  } catch (err) {
    logger.error({ msg: 'Server startup failed', error: err.message });
    console.error(err);
    process.exit(1);
  }

  // Graceful shutdown
  const shutdown = async (signal) => {
    logger.info({ msg: 'Shutting down server', signal });
    stopPhase1bWarmers();
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
  process.on('uncaughtException', (err) => {
    logger.error({ msg: 'Uncaught exception', error: err?.message, stack: err?.stack });
  });
}

start();
