/**
 * Admin authentication helpers + Fastify middleware.
 *
 *   - loadAdminUser(id)          fetch fresh user + roles + permissions
 *   - issueAccessToken(user)     short-lived JWT for the bearer
 *   - issueRefreshToken(user)    long-lived random token, hashed in db
 *   - verifyRefreshToken(token)  returns the admin row if valid
 *   - adminAuth                  preHandler — populates request.adminUser
 *   - requirePermissions(...)    preHandler factory — 403 if missing
 *   - loginRateLimit             brute-force protection per ip/email
 *   - recordFailedLogin / clearLoginAttempts
 */
import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import { query } from '../lib/db.js';
import { getRedis } from '../lib/redis.js';
import config from '../config/index.js';
import logger from '../lib/logger.js';
import { getPermissionsForRoles, hasPermission } from './rbac.js';
 
const ACCESS_TTL = '30m';
const REFRESH_TTL_MS = 1000 * 60 * 60 * 24 * 30; // 30 days
const REFRESH_COOKIE_NAME = 'cricpro_admin_refresh';
 
export const REFRESH_COOKIE = REFRESH_COOKIE_NAME;
export const REFRESH_TTL_SECONDS = REFRESH_TTL_MS / 1000;
 
function sha256(str) {
  return crypto.createHash('sha256').update(str).digest('hex');
}
 
export async function loadAdminUser(id) {
  const rows = await query(
    `SELECT id, email, name, is_active, last_login_at, password_changed_at
       FROM admin_users WHERE id = ?`,
    [id],
  );
  if (!rows.length) return null;
  const user = rows[0];
  const roleRows = await query(
    `SELECT r.slug, r.name
       FROM admin_user_roles ur
       JOIN admin_roles r ON r.id = ur.role_id
       WHERE ur.user_id = ?`,
    [id],
  );
  const roles = roleRows.map((r) => r.slug);
  const permissions = getPermissionsForRoles(roles);
  return {
    id: user.id,
    email: user.email,
    name: user.name,
    isActive: !!user.is_active,
    lastLoginAt: user.last_login_at,
    passwordChangedAt: user.password_changed_at,
    roles,
    roleNames: roleRows.map((r) => r.name),
    permissions,
  };
}
 
export function issueAccessToken(fastify, adminUser) {
  return fastify.jwt.sign(
    {
      sub: adminUser.id,
      email: adminUser.email,
      roles: adminUser.roles,
      typ: 'admin_access',
    },
    { expiresIn: ACCESS_TTL },
  );
}
 
export async function issueRefreshToken(adminUser) {
  const raw = crypto.randomBytes(40).toString('base64url');
  const hash = sha256(raw);
  const expiresAt = new Date(Date.now() + REFRESH_TTL_MS);
  await query(
    `UPDATE admin_users
        SET refresh_token_hash = ?, refresh_token_expires_at = ?
      WHERE id = ?`,
    [hash, expiresAt, adminUser.id],
  );
  return { token: raw, expiresAt };
}
 
export async function verifyRefreshToken(token) {
  if (!token) return null;
  const hash = sha256(token);
  const rows = await query(
    `SELECT id FROM admin_users
       WHERE refresh_token_hash = ?
         AND refresh_token_expires_at IS NOT NULL
         AND refresh_token_expires_at > NOW()
         AND is_active = 1
       LIMIT 1`,
    [hash],
  );
  if (!rows.length) return null;
  return loadAdminUser(rows[0].id);
}
 
export async function revokeRefreshToken(userId) {
  await query(
    `UPDATE admin_users
        SET refresh_token_hash = NULL, refresh_token_expires_at = NULL
      WHERE id = ?`,
    [userId],
  );
}
 
export function setRefreshCookie(reply, token, expiresAt) {
  reply.setCookie(REFRESH_COOKIE_NAME, token, {
    path: '/admin',
    httpOnly: true,
    sameSite: 'lax',
    secure: !config.isDev,
    expires: expiresAt,
  });
}
 
export function clearRefreshCookie(reply) {
  reply.clearCookie(REFRESH_COOKIE_NAME, { path: '/admin' });
}
 
/** preHandler: verifies the bearer JWT and loads request.adminUser. */
export async function adminAuth(request, reply) {
  try {
    await request.jwtVerify();
  } catch (err) {
    logger.debug({ msg: 'admin_jwt_invalid', error: err.message });
    return reply.code(401).send({ success: false, error: 'Unauthorized' });
  }
  if (request.user?.typ !== 'admin_access') {
    return reply.code(401).send({ success: false, error: 'Unauthorized' });
  }
  const admin = await loadAdminUser(request.user.sub);
  if (!admin || !admin.isActive) {
    return reply.code(401).send({ success: false, error: 'Account disabled' });
  }
  request.adminUser = admin;
}
 
/** preHandler factory: ensures the loaded admin has every required permission. */
export function requirePermissions(...required) {
  return async function (request, reply) {
    if (!request.adminUser) {
      return reply.code(401).send({ success: false, error: 'Unauthorized' });
    }
    if (!hasPermission(request.adminUser.permissions, required)) {
      return reply.code(403).send({
        success: false,
        error: 'Forbidden',
        missing: required,
      });
    }
  };
}
 
// -----------------------------------------------------------------------
// Brute-force protection
// -----------------------------------------------------------------------
const IP_ATTEMPT_TTL = 60 * 15; // 15 min
const USER_ATTEMPT_TTL = 60 * 15;
 
export async function loginRateLimit(request, reply) {
  const redis = getRedis();
  const email = (request.body?.email || '').toLowerCase();
  if (!email) {
    return reply.code(400).send({ success: false, error: 'Email is required' });
  }
  const ipKey = `admin:login:ip:${request.ip}`;
  const userKey = `admin:login:user:${email}`;
  const [ipAttempts, userAttempts] = await Promise.all([
    redis.get(ipKey),
    redis.get(userKey),
  ]);
  if (parseInt(ipAttempts || '0', 10) > 10) {
    return reply.code(429).send({
      success: false,
      error: 'Too many login attempts from this IP. Try again later.',
    });
  }
  if (parseInt(userAttempts || '0', 10) > 5) {
    return reply.code(429).send({
      success: false,
      error: 'Account temporarily locked. Try again in a few minutes.',
    });
  }
}
 
export async function recordFailedLogin(request) {
  const redis = getRedis();
  const email = (request.body?.email || '').toLowerCase();
  const ipKey = `admin:login:ip:${request.ip}`;
  const userKey = `admin:login:user:${email}`;
  await Promise.all([
    redis.incr(ipKey).then(() => redis.expire(ipKey, IP_ATTEMPT_TTL)),
    email
      ? redis.incr(userKey).then(() => redis.expire(userKey, USER_ATTEMPT_TTL))
      : null,
  ]);
}
 
export async function clearLoginAttempts(request) {
  const redis = getRedis();
  const email = (request.body?.email || '').toLowerCase();
  const ipKey = `admin:login:ip:${request.ip}`;
  const userKey = `admin:login:user:${email}`;
  await Promise.all([redis.del(ipKey), email ? redis.del(userKey) : null]);
}
 
export async function checkPasswordAndLog(email, password) {
  const rows = await query(
    `SELECT id, email, name, password_hash, is_active
       FROM admin_users WHERE email = ? LIMIT 1`,
    [email.toLowerCase()],
  );
  if (!rows.length) return null;
  const user = rows[0];
  if (!user.is_active) return null;
  const matches = await bcrypt.compare(password, user.password_hash);
  if (!matches) return null;
  return user;
}
 
export async function recordSuccessfulLogin(userId, ip) {
  await query(
    `UPDATE admin_users
        SET last_login_at = NOW(), last_login_ip = ?, failed_login_attempts = 0
      WHERE id = ?`,
    [ip || null, userId],
  );
}
 
export async function incrementFailedLoginCounter(userId) {
  await query(
    `UPDATE admin_users
        SET failed_login_attempts = failed_login_attempts + 1
      WHERE id = ?`,
    [userId],
  );
}