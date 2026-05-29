/**
 * Admin Role-Based Access Control.
 *
 * Roles (slugs) and the permission set each grants. The seed script
 * (db/admin-seed.js) materialises these into admin_roles + admin_permissions
 * + admin_role_permissions, but the canonical definition lives here so
 * code can statically reference the slugs.
 *
 * Permission slugs follow `<entity>.<action>` so adding a new module
 * (e.g. `series.write`) doesn't need a migration — just append it here
 * and re-run the seed.
 */
 
export const ROLE_SUPER_ADMIN = 'super_admin';
export const ROLE_ADMIN = 'admin';
export const ROLE_EDITOR = 'editor';
export const ROLE_SUPPORT = 'support';
export const ROLE_READ_ONLY = 'read_only';
 
export const ALL_ROLES = [
  ROLE_SUPER_ADMIN,
  ROLE_ADMIN,
  ROLE_EDITOR,
  ROLE_SUPPORT,
  ROLE_READ_ONLY,
];
 
export const ROLE_DEFINITIONS = {
  [ROLE_SUPER_ADMIN]: {
    name: 'Super Admin',
    description: 'Full control over everything including admin user management',
    isSystem: true,
  },
  [ROLE_ADMIN]: {
    name: 'Admin',
    description: 'Manage matches, streams, settings, cache, notifications, ads',
    isSystem: true,
  },
  [ROLE_EDITOR]: {
    name: 'Editor',
    description: 'Manage home content, news, schedule display settings',
    isSystem: true,
  },
  [ROLE_SUPPORT]: {
    name: 'Support',
    description: 'View matches, logs, health, streams',
    isSystem: true,
  },
  [ROLE_READ_ONLY]: {
    name: 'Read Only',
    description: 'Dashboard read-only access',
    isSystem: true,
  },
};
 
export const PERMISSIONS = {
  // Dashboard
  'dashboard.view': 'View admin dashboard',
 
  // Matches
  'matches.view': 'View matches list',
  'matches.write': 'Override / hide / feature matches',
  'matches.refresh': 'Trigger match data refresh',
 
  // Streams
  'streams.view': 'View live streams',
  'streams.write': 'Create, edit, delete streams',
  'streams.test': 'Run stream health tests',
 
  // Providers / API Keys
  'providers.view': 'View API providers',
  'providers.write': 'Configure providers and provider API keys',
  'apiKeys.view': 'View public API keys',
  'apiKeys.write': 'Issue and revoke public API keys',
 
  // App settings
  'settings.view': 'View app settings',
  'settings.write': 'Update app settings (maintenance, force update, etc.)',
 
  // Home / featured / banners
  'home.view': 'View homepage configuration',
  'home.write': 'Edit homepage sections, featured items, and banners',
 
  // Series / teams / players / schedule / news (Phase 2 modules — wired now so RBAC is forward compatible)
  'series.view': 'View series catalog',
  'series.write': 'Edit series catalog',
  'teams.view': 'View teams',
  'teams.write': 'Edit teams',
  'players.view': 'View players',
  'players.write': 'Edit players',
  'schedule.view': 'View schedule controls',
  'schedule.write': 'Edit schedule controls',
  'news.view': 'View news',
  'news.write': 'Edit news',
 
  // Notifications / Ads
  'notifications.view': 'View notifications',
  'notifications.write': 'Compose and send notifications',
  'ads.view': 'View ad configuration',
  'ads.write': 'Edit ad placements and settings',
 
  // Ops
  'cache.view': 'View cache events',
  'cache.write': 'Trigger cache invalidation and warming',
  'health.view': 'View system health and logs',
 
  // Admin user management
  'adminUsers.view': 'View admin users',
  'adminUsers.write': 'Create, edit, deactivate admin users',
  'roles.view': 'View roles and permissions',
  'roles.write': 'Edit roles and permissions',
  'audit.view': 'View audit logs',
};
 
export const ROLE_PERMISSIONS = {
  [ROLE_SUPER_ADMIN]: Object.keys(PERMISSIONS),
 
  [ROLE_ADMIN]: [
    'dashboard.view',
    'matches.view', 'matches.write', 'matches.refresh',
    'streams.view', 'streams.write', 'streams.test',
    'providers.view', 'providers.write',
    'apiKeys.view', 'apiKeys.write',
    'settings.view', 'settings.write',
    'home.view', 'home.write',
    'series.view', 'series.write',
    'teams.view', 'teams.write',
    'players.view', 'players.write',
    'schedule.view', 'schedule.write',
    'news.view', 'news.write',
    'notifications.view', 'notifications.write',
    'ads.view', 'ads.write',
    'cache.view', 'cache.write',
    'health.view',
    'audit.view',
  ],
 
  [ROLE_EDITOR]: [
    'dashboard.view',
    'matches.view',
    'streams.view',
    'home.view', 'home.write',
    'series.view',
    'teams.view',
    'players.view',
    'schedule.view', 'schedule.write',
    'news.view', 'news.write',
  ],
 
  [ROLE_SUPPORT]: [
    'dashboard.view',
    'matches.view',
    'streams.view',
    'providers.view',
    'health.view',
    'cache.view',
    'audit.view',
  ],
 
  [ROLE_READ_ONLY]: [
    'dashboard.view',
  ],
};
 
export function getPermissionsForRoles(roleSlugs) {
  const set = new Set();
  for (const role of roleSlugs || []) {
    for (const perm of ROLE_PERMISSIONS[role] || []) {
      set.add(perm);
    }
  }
  return [...set];
}
 
export function hasPermission(userPermissions, required) {
  if (!required) return true;
  const list = Array.isArray(required) ? required : [required];
  return list.every((p) => userPermissions.includes(p));
}