import {
  adminAuth,
  loginRateLimit,
  recordFailedLogin,
  clearLoginAttempts,
  checkPasswordAndLog,
  recordSuccessfulLogin,
  incrementFailedLoginCounter,
  loadAdminUser,
  issueAccessToken,
  issueRefreshToken,
  verifyRefreshToken,
  revokeRefreshToken,
  setRefreshCookie,
  clearRefreshCookie,
  REFRESH_COOKIE,
} from '../auth.js';
import { recordAudit } from '../audit.js';
import bcrypt from 'bcryptjs';
import { query } from '../../lib/db.js';
 
export default async function authRoutes(fastify) {
  fastify.post(
    '/login',
    { preHandler: [loginRateLimit] },
    async (request, reply) => {
      const { email, password } = request.body || {};
      if (!email || !password) {
        return reply.code(400).send({ success: false, error: 'Email and password required' });
      }
      const candidate = await checkPasswordAndLog(email, password);
      if (!candidate) {
        await recordFailedLogin(request);
        await recordAudit({
          adminEmail: email,
          action: 'login.failed',
          entityType: 'admin_user',
          ipAddress: request.ip,
          userAgent: request.headers['user-agent'],
          status: 'error',
          errorMessage: 'Invalid credentials',
        });
        return reply.code(401).send({ success: false, error: 'Invalid email or password' });
      }
      await clearLoginAttempts(request);
      await recordSuccessfulLogin(candidate.id, request.ip);
      const adminUser = await loadAdminUser(candidate.id);
      const accessToken = issueAccessToken(fastify, adminUser);
      const { token: refreshToken, expiresAt } = await issueRefreshToken(adminUser);
      setRefreshCookie(reply, refreshToken, expiresAt);
      await recordAudit({
        adminUserId: adminUser.id,
        adminEmail: adminUser.email,
        action: 'login.success',
        entityType: 'admin_user',
        entityId: adminUser.id,
        ipAddress: request.ip,
        userAgent: request.headers['user-agent'],
      });
      return reply.send({
        success: true,
        token: accessToken,
        user: publicUser(adminUser),
      });
    },
  );
 
  fastify.post('/refresh', async (request, reply) => {
    const refresh = request.cookies?.[REFRESH_COOKIE];
    if (!refresh) return reply.code(401).send({ success: false, error: 'No refresh token' });
    const adminUser = await verifyRefreshToken(refresh);
    if (!adminUser) return reply.code(401).send({ success: false, error: 'Invalid refresh token' });
    const accessToken = issueAccessToken(fastify, adminUser);
    const { token: newRefresh, expiresAt } = await issueRefreshToken(adminUser);
    setRefreshCookie(reply, newRefresh, expiresAt);
    return reply.send({ success: true, token: accessToken, user: publicUser(adminUser) });
  });
 
  fastify.post('/logout', { preHandler: [adminAuth] }, async (request, reply) => {
    await revokeRefreshToken(request.adminUser.id);
    clearRefreshCookie(reply);
    await recordAudit({
      adminUserId: request.adminUser.id,
      adminEmail: request.adminUser.email,
      action: 'logout',
      entityType: 'admin_user',
      entityId: request.adminUser.id,
      ipAddress: request.ip,
      userAgent: request.headers['user-agent'],
    });
    return reply.send({ success: true });
  });
 
  fastify.get('/me', { preHandler: [adminAuth] }, async (request) => {
    return { success: true, user: publicUser(request.adminUser) };
  });
 
  fastify.post('/me/password', { preHandler: [adminAuth] }, async (request, reply) => {
    const { current_password, new_password } = request.body || {};
    if (!current_password || !new_password || new_password.length < 8) {
      return reply.code(400).send({
        success: false,
        error: 'current_password and new_password (>=8 chars) required',
      });
    }
    const rows = await query(`SELECT password_hash FROM admin_users WHERE id = ?`, [
      request.adminUser.id,
    ]);
    if (!rows.length || !(await bcrypt.compare(current_password, rows[0].password_hash))) {
      return reply.code(401).send({ success: false, error: 'Current password is incorrect' });
    }
    const newHash = await bcrypt.hash(new_password, 12);
    await query(
      `UPDATE admin_users SET password_hash = ?, password_changed_at = NOW(),
                              refresh_token_hash = NULL, refresh_token_expires_at = NULL
       WHERE id = ?`,
      [newHash, request.adminUser.id],
    );
    clearRefreshCookie(reply);
    await recordAudit({
      adminUserId: request.adminUser.id,
      adminEmail: request.adminUser.email,
      action: 'password.change',
      entityType: 'admin_user',
      entityId: request.adminUser.id,
      ipAddress: request.ip,
      userAgent: request.headers['user-agent'],
    });
    return { success: true };
  });
}
 
function publicUser(u) {
  return {
    id: u.id,
    email: u.email,
    name: u.name,
    roles: u.roles,
    roleNames: u.roleNames,
    permissions: u.permissions,
    lastLoginAt: u.lastLoginAt,
  };
}