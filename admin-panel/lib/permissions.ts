export const PERMISSION_LABELS: Record<string, string> = {
  'dashboard.view': 'View dashboard',
  'matches.view': 'View matches',
  'matches.write': 'Edit / hide / feature matches',
  'matches.refresh': 'Refresh match data',
  'streams.view': 'View streams',
  'streams.write': 'Edit streams',
  'streams.test': 'Test stream health',
  'providers.view': 'View providers',
  'providers.write': 'Edit providers and keys',
  'apiKeys.view': 'View API keys',
  'apiKeys.write': 'Issue/revoke API keys',
  'settings.view': 'View app settings',
  'settings.write': 'Edit app settings',
  'home.view': 'View home configuration',
  'home.write': 'Edit home configuration',
  'series.view': 'View series',
  'series.write': 'Edit series',
  'teams.view': 'View teams',
  'teams.write': 'Edit teams',
  'players.view': 'View players',
  'players.write': 'Edit players',
  'schedule.view': 'View schedule',
  'schedule.write': 'Edit schedule',
  'news.view': 'View news',
  'news.write': 'Edit news',
  'notifications.view': 'View notifications',
  'notifications.write': 'Send notifications',
  'ads.view': 'View ads',
  'ads.write': 'Edit ads',
  'cache.view': 'View cache events',
  'cache.write': 'Trigger cache actions',
  'health.view': 'View system health',
  'dataControl.view': 'View data control',
  'dataControl.write': 'Edit data control',
  'adminUsers.view': 'View admin users',
  'adminUsers.write': 'Manage admin users',
  'roles.view': 'View roles',
  'roles.write': 'Edit roles',
  'audit.view': 'View audit logs',
};

export const PERMISSION_GROUPS: { label: string; permissions: string[] }[] = [
  { label: 'Dashboard', permissions: ['dashboard.view'] },
  { label: 'Matches', permissions: ['matches.view', 'matches.write', 'matches.refresh'] },
  { label: 'Streams', permissions: ['streams.view', 'streams.write', 'streams.test'] },
  { label: 'Providers & Keys', permissions: ['providers.view', 'providers.write', 'apiKeys.view', 'apiKeys.write'] },
  { label: 'Settings', permissions: ['settings.view', 'settings.write'] },
  { label: 'Home', permissions: ['home.view', 'home.write'] },
  { label: 'Series', permissions: ['series.view', 'series.write'] },
  { label: 'Teams', permissions: ['teams.view', 'teams.write'] },
  { label: 'Players', permissions: ['players.view', 'players.write'] },
  { label: 'Schedule', permissions: ['schedule.view', 'schedule.write'] },
  { label: 'News', permissions: ['news.view', 'news.write'] },
  { label: 'Notifications', permissions: ['notifications.view', 'notifications.write'] },
  { label: 'Ads', permissions: ['ads.view', 'ads.write'] },
  { label: 'Cache', permissions: ['cache.view', 'cache.write'] },
  { label: 'Health', permissions: ['health.view'] },
  { label: 'Data Control', permissions: ['dataControl.view', 'dataControl.write'] },
  { label: 'Admin Users', permissions: ['adminUsers.view', 'adminUsers.write'] },
  { label: 'Roles', permissions: ['roles.view', 'roles.write'] },
  { label: 'Audit', permissions: ['audit.view'] },
];

export function hasPermission(
  userPermissions: string[] | undefined,
  required: string,
): boolean {
  if (!userPermissions) return false;
  return userPermissions.includes(required);
}

export function hasAny(
  userPermissions: string[] | undefined,
  list: string[],
): boolean {
  if (!userPermissions) return false;
  return list.some((p) => userPermissions.includes(p));
}
