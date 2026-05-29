import { query } from '../lib/db.js';
import { getRedis } from '../lib/redis.js';
import { jwtAuth, adminOnly, loginRateLimit, recordFailedLogin, clearLoginAttempts } from '../middleware/auth.js';
import providerManager from '../providers/provider-manager.js';
import bcrypt from 'bcryptjs';
import { nanoid } from 'nanoid';
import logger from '../lib/logger.js';

export default async function adminRoutes(fastify) {
  // POST /login — get JWT token (NO AUTH REQUIRED)
  fastify.post('/login', {
    preHandler: [loginRateLimit],
    schema: {
      description: 'Admin login',
      tags: ['Admin'],
      body: {
        type: 'object',
        properties: {
          username: { type: 'string', minLength: 3, maxLength: 100 },
          password: { type: 'string', minLength: 8 },
        },
        required: ['username', 'password'],
      },
    },
  }, async (request, reply) => {
    const { username, password } = request.body;
    
    if (!username || !password) {
      return reply.code(400).send({ error: 'Username and password are required' });
    }

    const result = await query(
      'SELECT id, username, email, role, password_hash FROM users WHERE username = ? AND is_active = 1', 
      [username]
    );
    const user = result[0];

    if (!user || !(await bcrypt.compare(password, user.password_hash))) {
      await recordFailedLogin(request);
      logger.warn({ msg: 'Failed login attempt', username, ip: request.ip });
      return reply.code(401).send({ error: 'Invalid credentials' });
    }

    await clearLoginAttempts(request);

    const token = fastify.jwt.sign(
      { id: user.id, username: user.username, role: user.role },
      { expiresIn: '7d' }
    );

    logger.info({ msg: 'Successful login', username, ip: request.ip });

    return { 
      success: true, 
      token, 
      user: { id: user.id, username: user.username, role: user.role } 
    };
  });

  // POST /logout — invalidate JWT token (AUTH REQUIRED)
  fastify.post('/logout', {
    preHandler: [jwtAuth],
    schema: {
      description: 'Admin logout (invalidate token)',
      tags: ['Admin'],
    },
  }, async (request) => {
    const redis = getRedis();
    const userId = request.user.id;
    
    await redis.setex(`blacklist:token:${userId}`, 604800, '1');
    
    logger.info({ msg: 'User logged out', username: request.user.username });
    return { success: true, message: 'Logged out successfully' };
  });

  // POST /api-keys — generate new API key (AUTH REQUIRED)
  fastify.post('/api-keys', {
    preHandler: [jwtAuth, adminOnly],
    schema: {
      description: 'Generate a new API key',
      tags: ['Admin'],
      body: {
        type: 'object',
        properties: {
          name: { type: 'string', minLength: 3, maxLength: 200 },
          email: { type: 'string', format: 'email', maxLength: 300 },
          tier: { type: 'string', enum: ['free', 'pro', 'enterprise'] },
          rate_limit: { type: 'integer', minimum: 10, maximum: 10000 },
          expires_in_days: { type: 'integer', minimum: 1, maximum: 3650 },
        },
        required: ['name'],
      },
    },
  }, async (request) => {
    const { name, email, tier = 'free', rate_limit = 100, expires_in_days } = request.body;
    
    const sanitizedName = name.trim().substring(0, 200);
    const sanitizedEmail = email ? email.trim().toLowerCase().substring(0, 300) : null;
    
    if (sanitizedEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(sanitizedEmail)) {
      return { success: false, error: 'Invalid email format' };
    }

    const rawKey = `csk_${nanoid(48)}`;
    const keyHash = await bcrypt.hash(rawKey, 12);

    const expiresAt = expires_in_days 
      ? new Date(Date.now() + expires_in_days * 24 * 60 * 60 * 1000)
      : null;

    await query(
      'INSERT INTO api_keys (key_hash, name, email, tier, rate_limit, expires_at) VALUES (?, ?, ?, ?, ?, ?)',
      [keyHash, sanitizedName, sanitizedEmail, tier, rate_limit, expiresAt]
    );

    logger.info({ 
      msg: 'API key generated', 
      name: sanitizedName, 
      tier, 
      admin: request.user.username 
    });

    return {
      success: true,
      api_key: rawKey,
      tier,
      rate_limit,
      expires_at: expiresAt,
      warning: 'Store this key securely. It cannot be retrieved again.',
    };
  });

  // GET /api-keys — list all API keys (AUTH REQUIRED)
  fastify.get('/api-keys', {
    preHandler: [jwtAuth, adminOnly],
    schema: { description: 'List all API keys', tags: ['Admin'] },
  }, async () => {
    const result = await query('SELECT id, name, email, tier, rate_limit, is_active, last_used_at, created_at FROM api_keys ORDER BY created_at DESC');
    return { success: true, data: result };
  });

  // DELETE /api-keys/:id — revoke API key (AUTH REQUIRED)
  fastify.delete('/api-keys/:id', {
    preHandler: [jwtAuth, adminOnly],
    schema: {
      description: 'Revoke an API key',
      tags: ['Admin'],
      params: { type: 'object', properties: { id: { type: 'integer' } }, required: ['id'] },
    },
  }, async (request) => {
    await query('UPDATE api_keys SET is_active = 0 WHERE id = ?', [request.params.id]);
    return { success: true, message: 'API key revoked' };
  });

  // POST /providers/:name/reset — reset provider health (AUTH REQUIRED)
  fastify.post('/providers/:name/reset', {
    preHandler: [jwtAuth, adminOnly],
    schema: {
      description: 'Reset a provider health state',
      tags: ['Admin'],
      params: { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] },
    },
  }, async (request) => {
    providerManager.resetProvider(request.params.name);
    return { success: true, message: `Provider ${request.params.name} health reset` };
  });

  // POST /cache/flush — flush Redis cache (AUTH REQUIRED)
  fastify.post('/cache/flush', {
    preHandler: [jwtAuth, adminOnly],
    schema: { description: 'Flush all cached data', tags: ['Admin'] },
  }, async () => {
    await getRedis().flushdb();
    return { success: true, message: 'Cache flushed' };
  });

  // GET /stats — system statistics (AUTH REQUIRED)
  fastify.get('/stats', {
    preHandler: [jwtAuth, adminOnly],
    schema: { description: 'System statistics', tags: ['Admin'] },
  }, async () => {
    const redis = getRedis();
    const [dbSize, info, matchCount, playerCount] = await Promise.all([
      redis.dbsize(),
      redis.info('memory'),
      query('SELECT COUNT(*) as cnt FROM matches'),
      query('SELECT COUNT(*) as cnt FROM players'),
    ]);

    const memoryMatch = info.match(/used_memory_human:(.+)/);
    return {
      success: true,
      data: {
        redis: { keys: dbSize, memory: memoryMatch?.[1]?.trim() || 'unknown' },
        database: { matches: parseInt(matchCount[0].cnt), players: parseInt(playerCount[0].cnt) },
        providers: providerManager.getHealthStatus(),
        uptime: process.uptime(),
        nodeVersion: process.version,
      },
    };
  });
}
