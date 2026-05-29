import { query } from '../lib/db.js';
import { getRedis } from '../lib/redis.js';
import config from '../config/index.js';
import logger from '../lib/logger.js';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';

/**
 * API Key authentication middleware.
 * Checks x-api-key header against hashed keys in DB.
 * Caches valid keys in Redis for fast lookups.
 */
export async function apiKeyAuth(request, reply) {
  const apiKey = request.headers[config.auth.apiKeyHeader];

  if (!apiKey) {
    // Allow unauthenticated access to public endpoints
    request.apiTier = 'public';
    request.rateLimit = 30; // lower limit for public
    return;
  }

  // Validate API key format
  if (!apiKey.startsWith('csk_') || apiKey.length < 20) {
    logger.warn({ msg: 'Invalid API key format', ip: request.ip });
    return reply.code(401).send({ error: 'Invalid API key format' });
  }

  const redis = getRedis();
  // Use SHA256 hash of API key for cache key (don't store raw key)
  const keyHash = crypto.createHash('sha256').update(apiKey).digest('hex');
  const cacheKey = `apikey:${keyHash}`;

  // Check if this key is temporarily blocked due to abuse
  const abuseKey = `abuse:apikey:${keyHash}`;
  const abuseCount = await redis.get(abuseKey);
  if (abuseCount && parseInt(abuseCount) > 10) {
    logger.warn({ msg: 'API key temporarily blocked due to abuse', ip: request.ip });
    return reply.code(429).send({ error: 'API key temporarily blocked. Try again later.' });
  }

  // Check Redis cache first
  let keyData = null;
  const cached = await redis.get(cacheKey);

  if (cached) {
    keyData = JSON.parse(cached);
  } else {
    // Lookup in DB — compare hashed keys
    const result = await query(
      `SELECT id, name, tier, rate_limit, is_active, expires_at, key_hash
       FROM api_keys WHERE is_active = true`,
    );

    for (const row of result) {
      const matches = await bcrypt.compare(apiKey, row.key_hash);
      if (matches) {
        keyData = { ...row };
        delete keyData.key_hash; // Don't cache the hash
        break;
      }
    }

    if (keyData) {
      // Cache for 5 minutes
      await redis.setex(cacheKey, 300, JSON.stringify(keyData));

      // Update last_used_at asynchronously
      query('UPDATE api_keys SET last_used_at = NOW() WHERE id = ?', [keyData.id]).catch(() => {});
    } else {
      // Track failed authentication attempts
      await redis.incr(abuseKey);
      await redis.expire(abuseKey, 3600); // 1 hour
    }
  }

  if (!keyData) {
    logger.warn({ msg: 'Invalid API key attempt', ip: request.ip });
    return reply.code(401).send({ error: 'Invalid API key' });
  }

  if (!keyData.is_active) {
    return reply.code(403).send({ error: 'API key is deactivated' });
  }

  if (keyData.expires_at && new Date(keyData.expires_at) < new Date()) {
    return reply.code(403).send({ error: 'API key has expired' });
  }

  request.apiKeyId = keyData.id;
  request.apiTier = keyData.tier;
  request.rateLimit = keyData.rate_limit;
}

/**
 * JWT authentication for admin endpoints.
 */
export async function jwtAuth(request, reply) {
  try {
    await request.jwtVerify();
    
    // Check if token is blacklisted (for logout functionality)
    const redis = getRedis();
    const tokenBlacklist = await redis.get(`blacklist:token:${request.user.id}`);
    if (tokenBlacklist) {
      return reply.code(401).send({ error: 'Token has been revoked' });
    }
  } catch (err) {
    logger.warn({ msg: 'JWT verification failed', ip: request.ip, error: err.message });
    return reply.code(401).send({ error: 'Invalid or expired token' });
  }
}

/**
 * Admin role check (must be used after jwtAuth).
 */
export async function adminOnly(request, reply) {
  if (request.user?.role !== 'admin') {
    logger.warn({ msg: 'Unauthorized admin access attempt', ip: request.ip, user: request.user?.username });
    return reply.code(403).send({ error: 'Admin access required' });
  }
}

/**
 * Brute force protection for login attempts.
 */
export async function loginRateLimit(request, reply) {
  const redis = getRedis();
  const { username } = request.body || {};
  
  if (!username) {
    return reply.code(400).send({ error: 'Username is required' });
  }

  const ipKey = `login:attempts:ip:${request.ip}`;
  const userKey = `login:attempts:user:${username}`;
  
  const [ipAttempts, userAttempts] = await Promise.all([
    redis.get(ipKey),
    redis.get(userKey),
  ]);

  const ipCount = parseInt(ipAttempts) || 0;
  const userCount = parseInt(userAttempts) || 0;

  // Block if too many attempts from IP or for specific user
  if (ipCount > 10) {
    logger.warn({ msg: 'Login brute force detected from IP', ip: request.ip });
    return reply.code(429).send({ 
      error: 'Too many login attempts from this IP. Try again in 15 minutes.' 
    });
  }

  if (userCount > 5) {
    logger.warn({ msg: 'Login brute force detected for user', username, ip: request.ip });
    return reply.code(429).send({ 
      error: 'Too many login attempts for this account. Try again in 15 minutes.' 
    });
  }

  // Store attempt count for tracking
  request.loginAttemptKeys = { ipKey, userKey };
}

/**
 * Record failed login attempt.
 */
export async function recordFailedLogin(request) {
  if (!request.loginAttemptKeys) return;
  
  const redis = getRedis();
  const { ipKey, userKey } = request.loginAttemptKeys;
  
  await Promise.all([
    redis.incr(ipKey),
    redis.incr(userKey),
  ]);
  
  await Promise.all([
    redis.expire(ipKey, 900), // 15 minutes
    redis.expire(userKey, 900),
  ]);
}

/**
 * Clear login attempts on successful login.
 */
export async function clearLoginAttempts(request) {
  if (!request.loginAttemptKeys) return;
  
  const redis = getRedis();
  const { ipKey, userKey } = request.loginAttemptKeys;
  
  await Promise.all([
    redis.del(ipKey),
    redis.del(userKey),
  ]);
}
