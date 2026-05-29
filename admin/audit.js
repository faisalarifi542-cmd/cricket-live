/**
 * Audit log helpers.
 *
 * Every mutating admin action gets one row in admin_audit_logs:
 *   { adminUserId, action, entityType, entityId, oldValue, newValue,
 *     ipAddress, userAgent, status, errorMessage }
 *
 * Routes call `audit(request, ...)` from a Fastify onResponse hook
 * or directly from controllers. The helper never throws — audit
 * failures should never break the originating action.
 */
import { query } from '../lib/db.js';
import logger from '../lib/logger.js';
 
function safeJson(value) {
  if (value === undefined || value === null) return null;
  try {
    return JSON.stringify(value);
  } catch {
    return null;
  }
}
 
export async function recordAudit({
  adminUserId = null,
  adminEmail = null,
  action,
  entityType,
  entityId = null,
  oldValue = null,
  newValue = null,
  ipAddress = null,
  userAgent = null,
  status = 'ok',
  errorMessage = null,
}) {
  try {
    await query(
      `INSERT INTO admin_audit_logs
        (admin_user_id, admin_email, action, entity_type, entity_id,
         old_value, new_value, ip_address, user_agent, status, error_message)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        adminUserId,
        adminEmail,
        action,
        entityType,
        entityId == null ? null : String(entityId),
        safeJson(oldValue),
        safeJson(newValue),
        ipAddress,
        userAgent ? String(userAgent).substring(0, 400) : null,
        status,
        errorMessage ? String(errorMessage).substring(0, 1000) : null,
      ],
    );
  } catch (err) {
    logger.error({ msg: 'audit_write_failed', error: err.message });
  }
}
 
/**
 * Convenience wrapper for route handlers:
 *   await withAudit(request, { action, entityType, entityId, oldValue, newValue }, fn)
 */
export async function withAudit(request, meta, fn) {
  let result;
  try {
    result = await fn();
    await recordAudit({
      adminUserId: request.adminUser?.id ?? null,
      adminEmail: request.adminUser?.email ?? null,
      ipAddress: request.ip ?? null,
      userAgent: request.headers['user-agent'] ?? null,
      status: 'ok',
      ...meta,
    });
    return result;
  } catch (err) {
    await recordAudit({
      adminUserId: request.adminUser?.id ?? null,
      adminEmail: request.adminUser?.email ?? null,
      ipAddress: request.ip ?? null,
      userAgent: request.headers['user-agent'] ?? null,
      status: 'error',
      errorMessage: err.message,
      ...meta,
    });
    throw err;
  }
}