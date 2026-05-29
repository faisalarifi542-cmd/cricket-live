import logger from '../lib/logger.js';
import { getRedis } from '../lib/redis.js';
import config from '../config/index.js';

const SUSPICIOUS_PATTERNS = [
  /(\bor\b|\band\b).*[=<>]/i,
  /union.*select/i,
  /insert.*into/i,
  /delete.*from/i,
  /drop.*table/i,
  /<script[^>]*>.*?<\/script>/i,
  /javascript:/i,
  /on\w+\s*=/i,
  /\.\.\//,
  /etc\/passwd/,
  /proc\/self/,
];

export async function sqlInjectionProtection(request, reply) {
  const checkValue = (val) => {
    if (typeof val !== 'string') return false;
    return SUSPICIOUS_PATTERNS.some(pattern => pattern.test(val));
  };

  const params = { ...request.params, ...request.query, ...request.body };
  for (const [key, value] of Object.entries(params)) {
    if (checkValue(value) || (Array.isArray(value) && value.some(checkValue))) {
      logger.warn({ msg: 'SQL injection attempt detected', ip: request.ip, key, value });
      return reply.code(400).send({ error: 'Invalid input detected' });
    }
  }
}

export async function xssProtection(request, reply) {
  const sanitize = (val) => {
    if (typeof val !== 'string') return val;
    return val.replace(/<script[^>]*>.*?<\/script>/gi, '')
              .replace(/javascript:/gi, '')
              .replace(/on\w+\s*=/gi, '');
  };

  if (request.body && typeof request.body === 'object') {
    for (const key in request.body) {
      if (typeof request.body[key] === 'string') {
        request.body[key] = sanitize(request.body[key]);
      }
    }
  }
}

export async function rateLimitByIP(request, reply) {
  const redis = getRedis();
  const key = `ratelimit:ip:${request.ip}`;
  const limit = request.rateLimit || config.rateLimit.max;
  const window = 60;

  const current = await redis.incr(key);
  if (current === 1) {
    await redis.expire(key, window);
  }

  const ttl = await redis.ttl(key);
  reply.header('X-RateLimit-Limit', limit);
  reply.header('X-RateLimit-Remaining', Math.max(0, limit - current));
  reply.header('X-RateLimit-Reset', Date.now() + (ttl * 1000));

  if (current > limit) {
    logger.warn({ msg: 'Rate limit exceeded', ip: request.ip, count: current });
    return reply.code(429).send({
      error: 'Too many requests',
      retryAfter: ttl,
    });
  }
}

export async function blockSuspiciousIPs(request, reply) {
  const redis = getRedis();
  const blockedKey = `blocked:ip:${request.ip}`;
  
  const isBlocked = await redis.get(blockedKey);
  if (isBlocked) {
    logger.warn({ msg: 'Blocked IP attempted access', ip: request.ip });
    return reply.code(403).send({ error: 'Access denied' });
  }
}

export async function requestSizeLimit(request, reply) {
  const contentLength = request.headers['content-length'];
  const maxSize = 1048576;
  
  if (contentLength && parseInt(contentLength) > maxSize) {
    logger.warn({ msg: 'Request too large', ip: request.ip, size: contentLength });
    return reply.code(413).send({ error: 'Request entity too large' });
  }
}

export async function securityHeaders(request, reply) {
  reply.header('X-Content-Type-Options', 'nosniff');
  reply.header('X-Frame-Options', 'DENY');
  reply.header('X-XSS-Protection', '1; mode=block');
  reply.header('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  reply.header('Referrer-Policy', 'strict-origin-when-cross-origin');
  reply.header('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
}

export async function validateContentType(request, reply) {
  if (['POST', 'PUT', 'PATCH'].includes(request.method)) {
    const contentType = request.headers['content-type'];
    const contentLength = request.headers['content-length'];
    
    // Only validate if there's actually a body
    if (contentLength && parseInt(contentLength) > 0) {
      if (!contentType || !contentType.includes('application/json')) {
        logger.warn({ msg: 'Invalid content type', ip: request.ip, contentType, url: request.url });
        return reply.code(415).send({ 
          success: false,
          error: 'Unsupported media type. Use Content-Type: application/json' 
        });
      }
    }
  }
}

export async function logSuspiciousActivity(request, reply) {
  // Note: x-forwarded-for and x-real-ip are normal when behind a reverse proxy like Nginx
  // Only log truly suspicious patterns
  const suspiciousHeaders = ['x-original-url', 'x-rewrite-url'];
  const hasSuspiciousHeaders = suspiciousHeaders.some(h => request.headers[h]);
  
  if (hasSuspiciousHeaders) {
    logger.warn({
      msg: 'Suspicious headers detected',
      ip: request.ip,
      headers: Object.keys(request.headers),
      url: request.url,
    });
  }
}
