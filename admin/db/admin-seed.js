/**
 * Admin Panel seed.
 *   - Materialises ROLE_DEFINITIONS and PERMISSIONS into the DB
 *   - Wires ROLE_PERMISSIONS through admin_role_permissions
 *   - Creates an initial super-admin user from env (ADMIN_SEED_EMAIL /
 *     ADMIN_SEED_PASSWORD) or falls back to a generated random password
 *     printed to stdout exactly once.
 */
import 'dotenv/config';
import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import { getPool, query } from '../lib/db.js';
import logger from '../lib/logger.js';
import {
  ROLE_DEFINITIONS,
  ROLE_PERMISSIONS,
  PERMISSIONS,
  ROLE_SUPER_ADMIN,
} from '../admin/rbac.js';
 
async function upsertRole(slug) {
  const def = ROLE_DEFINITIONS[slug];
  await query(
    `INSERT INTO admin_roles (slug, name, description, is_system)
     VALUES (?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE name = VALUES(name),
                             description = VALUES(description),
                             is_system = VALUES(is_system)`,
    [slug, def.name, def.description, def.isSystem ? 1 : 0],
  );
}
 
async function upsertPermission(slug, description) {
  const name = slug;
  await query(
    `INSERT INTO admin_permissions (slug, name, description)
     VALUES (?, ?, ?)
     ON DUPLICATE KEY UPDATE name = VALUES(name),
                             description = VALUES(description)`,
    [slug, name, description],
  );
}
 
async function syncRolePermissions(roleSlug, permissionSlugs) {
  const role = await query(`SELECT id FROM admin_roles WHERE slug = ?`, [roleSlug]);
  if (!role.length) return;
  const roleId = role[0].id;
 
  const perms = await query(
    `SELECT id, slug FROM admin_permissions WHERE slug IN (?)`,
    [permissionSlugs.length ? permissionSlugs : ['__none__']],
  );
  const permIds = perms.map((p) => p.id);
 
  await query(`DELETE FROM admin_role_permissions WHERE role_id = ?`, [roleId]);
  if (permIds.length) {
    const values = permIds.map(() => '(?, ?)').join(', ');
    const params = permIds.flatMap((id) => [roleId, id]);
    await query(
      `INSERT INTO admin_role_permissions (role_id, permission_id) VALUES ${values}`,
      params,
    );
  }
}
 
async function ensureSuperAdmin() {
  const email = (process.env.ADMIN_SEED_EMAIL || 'admin@cricpro.local').toLowerCase();
  const explicitPassword = process.env.ADMIN_SEED_PASSWORD;
  const password = explicitPassword || crypto.randomBytes(16).toString('base64url');
  const passwordHash = await bcrypt.hash(password, 12);
 
  const existing = await query(`SELECT id FROM admin_users WHERE email = ? LIMIT 1`, [email]);
 
  let userId;
  if (existing.length) {
    userId = existing[0].id;
    if (explicitPassword) {
      await query(
        `UPDATE admin_users
            SET password_hash = ?, password_changed_at = NOW(),
                is_active = 1, name = COALESCE(name, ?)
          WHERE id = ?`,
        [passwordHash, 'Super Admin', userId],
      );
      logger.info(`Updated existing super admin: ${email}`);
    } else {
      logger.info(`Super admin already exists: ${email} — password unchanged`);
    }
  } else {
    const result = await query(
      `INSERT INTO admin_users (email, name, password_hash, password_changed_at, is_active)
       VALUES (?, ?, ?, NOW(), 1)`,
      [email, 'Super Admin', passwordHash],
    );
    userId = result.insertId;
    logger.info(`Created super admin: ${email}`);
    if (!explicitPassword) {
      console.log('==============================================');
      console.log(' Super-admin credentials (save these now):    ');
      console.log(`   email:    ${email}`);
      console.log(`   password: ${password}`);
      console.log('==============================================');
    }
  }
 
  const roleRow = await query(`SELECT id FROM admin_roles WHERE slug = ?`, [ROLE_SUPER_ADMIN]);
  if (roleRow.length) {
    await query(
      `INSERT IGNORE INTO admin_user_roles (user_id, role_id) VALUES (?, ?)`,
      [userId, roleRow[0].id],
    );
  }
}
 
async function seed() {
  const pool = getPool();
  try {
    logger.info('Seeding admin panel roles + permissions...');
 
    for (const slug of Object.keys(ROLE_DEFINITIONS)) {
      await upsertRole(slug);
    }
    for (const [slug, description] of Object.entries(PERMISSIONS)) {
      await upsertPermission(slug, description);
    }
    for (const [roleSlug, perms] of Object.entries(ROLE_PERMISSIONS)) {
      await syncRolePermissions(roleSlug, perms);
    }
 
    await ensureSuperAdmin();
 
    // Seed a couple of default app_settings rows so the admin Settings page
    // has something to render right after migration.
    await query(
      `INSERT INTO app_settings (setting_key, setting_value, setting_group, description)
       VALUES
         ('maintenance_mode', JSON_OBJECT('enabled', false, 'message', ''), 'general',
          'Enable app-wide maintenance mode'),
         ('force_update', JSON_OBJECT('enabled', false, 'minimum_version', '1.0.0',
                                       'store_urls', JSON_OBJECT('ios','','android','')),
          'mobile', 'Force update prompt for mobile apps'),
         ('live_score_polling_secs', JSON_OBJECT('value', 3), 'live',
          'Live score polling interval (seconds)')
       ON DUPLICATE KEY UPDATE setting_value = setting_value`,
    );
 
    logger.info('Admin seed complete.');
  } catch (err) {
    logger.error(`Admin seed failed: ${err.message}`);
    console.error(err);
    process.exit(1);
  } finally {
    await pool.end();
  }
}
 
seed();