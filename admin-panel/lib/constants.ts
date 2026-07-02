import {
  Activity,
  Bell,
  BarChart3,
  CalendarDays,
  ClipboardList,
  FileKey,
  Gauge,
  Home,
  KeyRound,
  Megaphone,
  Newspaper,
  PlaySquare,
  Radio,
  Shield,
  Trophy,
  Users,
  UserRound,
  UserSquare2,
  Settings,
  DatabaseZap,
  SlidersHorizontal,
  HeartPulse,
  FlaskConical,
  ShieldCheck,
  ImageIcon,
  Sparkles,
  type LucideIcon,
} from 'lucide-react';

export const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL || 'https://api.webcrichd.co';

export type NavItem = {
  label: string;
  href: string;
  icon: LucideIcon;
  permission?: string;
  group: 'live' | 'content' | 'ops' | 'access' | 'system';
};

export const navigation: NavItem[] = [
  // Live ops
  { label: 'Dashboard', href: '/dashboard', icon: Gauge, permission: 'dashboard.view', group: 'live' },
  { label: 'Matches', href: '/matches', icon: Trophy, permission: 'matches.view', group: 'live' },
  { label: 'Live Streams', href: '/streams', icon: PlaySquare, permission: 'streams.view', group: 'live' },
  { label: 'Manual Matches', href: '/manual-matches', icon: FlaskConical, permission: 'matches.view', group: 'live' },
  { label: 'API Providers', href: '/providers', icon: Radio, permission: 'providers.view', group: 'live' },
  { label: 'API Keys', href: '/api-keys', icon: KeyRound, permission: 'apiKeys.view', group: 'live' },

  // Content
  { label: 'App Settings', href: '/settings', icon: Settings, permission: 'settings.view', group: 'content' },
  { label: 'Home Manager', href: '/homepage', icon: Home, permission: 'home.view', group: 'content' },
  { label: 'Splash Screen', href: '/splash', icon: Sparkles, permission: 'settings.view', group: 'content' },
  { label: 'Series', href: '/series', icon: ClipboardList, permission: 'series.view', group: 'content' },
  { label: 'Teams', href: '/teams', icon: Users, permission: 'teams.view', group: 'content' },
  { label: 'Players', href: '/players', icon: UserRound, permission: 'players.view', group: 'content' },
  { label: 'Schedule', href: '/schedule', icon: CalendarDays, permission: 'schedule.view', group: 'content' },
  { label: 'News', href: '/news', icon: Newspaper, permission: 'news.view', group: 'content' },

  // Operations
  { label: 'Notifications', href: '/notifications', icon: Bell, permission: 'notifications.view', group: 'ops' },
  { label: 'Analytics', href: '/analytics', icon: BarChart3, permission: 'analytics.view', group: 'ops' },
  { label: 'Ads', href: '/ads', icon: Megaphone, permission: 'ads.view', group: 'ops' },

  // Access control
  { label: 'Admin Users', href: '/users', icon: UserSquare2, permission: 'adminUsers.view', group: 'access' },
  { label: 'Roles', href: '/roles', icon: Shield, permission: 'roles.view', group: 'access' },
  { label: 'Audit Logs', href: '/audit-logs', icon: FileKey, permission: 'audit.view', group: 'access' },

  // System & tools (advanced — hidden from Editors who lack these permissions)
  { label: 'App Assets', href: '/assets', icon: ImageIcon, permission: 'settings.view', group: 'system' },
  { label: 'Cache', href: '/cache', icon: DatabaseZap, permission: 'cache.view', group: 'system' },
  { label: 'Data Control', href: '/data-control', icon: SlidersHorizontal, permission: 'dataControl.view', group: 'system' },
  { label: 'API Security', href: '/api-security', icon: ShieldCheck, permission: 'apiSecurity.view', group: 'system' },
  { label: 'Health & Logs', href: '/health', icon: HeartPulse, permission: 'health.view', group: 'system' },
];

export const navigationGroups: { id: NavItem['group']; label: string }[] = [
  { id: 'live', label: 'Live Operations' },
  { id: 'content', label: 'Content' },
  { id: 'ops', label: 'Operations' },
  { id: 'access', label: 'Access Control' },
  { id: 'system', label: 'System & Tools' },
];

export const STREAM_QUALITIES = ['AUTO', 'FHD', 'HD', 'SD'] as const;
export const STREAM_TYPES = ['hls', 'dash', 'mpd', 'iframe', 'external'] as const;
export const STREAM_STATUSES = ['unknown', 'working', 'slow', 'down'] as const;
export const DRM_TYPES = ['none', 'clearkey', 'widevine', 'fairplay', 'aes128'] as const;

export const PROVIDER_HEALTH = ['unknown', 'healthy', 'degraded', 'down'] as const;
export const API_KEY_TIERS = ['free', 'standard', 'premium', 'unlimited'] as const;

export const ROLE_SLUGS = [
  { slug: 'super_admin', label: 'Super Admin' },
  { slug: 'admin', label: 'Admin' },
  { slug: 'editor', label: 'Editor' },
  { slug: 'support', label: 'Support' },
  { slug: 'read_only', label: 'Read Only' },
] as const;

export const MATCH_TABS = [
  { id: 'live', label: 'Live' },
  { id: 'upcoming', label: 'Upcoming' },
  { id: 'finished', label: 'Finished' },
  { id: 'all', label: 'All' },
] as const;

export const SETTING_GROUPS = [
  'general',
  'mobile',
  'live',
  'home',
  'streams',
  'ads',
  'ui',
] as const;

export const NOTIFICATION_TARGETS = [
  { id: 'all', label: 'All users' },
  { id: 'android', label: 'Android only' },
  { id: 'ios', label: 'iOS only' },
  { id: 'category', label: 'By category (respects user choices)' },
  { id: 'favorite', label: 'By favourite country (respects user choices)' },
] as const;

// Notification categories users can toggle in-app. The id MUST match the
// Flutter NotificationSettingsService category keys (synced as OneSignal tags
// `notif_<id>`). A "category" target send only reaches users who left the
// category on.
export const NOTIFICATION_CATEGORIES = [
  { id: 'live_scores', label: 'Live match score updates' },
  { id: 'match_start', label: 'Match start reminders' },
  { id: 'toss', label: 'Toss updates' },
  { id: 'wickets', label: 'Wickets & milestones' },
  { id: 'innings_result', label: 'Innings break & result' },
  { id: 'live_stream', label: 'Live stream available' },
  { id: 'favorite_team', label: 'Favourite team match alerts' },
  { id: 'news', label: 'News & general updates' },
  { id: 'announcements', label: 'App announcements & promotions' },
] as const;

export const NOTIFICATION_DEEP_LINKS = [
  { id: 'home', label: 'Home' },
  { id: 'match', label: 'Match details' },
  { id: 'live_stream', label: 'Live player' },
  { id: 'series', label: 'Series' },
  { id: 'news', label: 'News article' },
  { id: 'schedule', label: 'Schedule' },
  { id: 'rankings', label: 'Rankings' },
] as const;

// Favourite-country codes for "favorite" target sends. These MUST stay in exact
// sync with the Flutter FavoriteCountriesService.catalog codes — the app writes
// `fav_<CODE>` tags using these exact uppercase codes, and the backend
// favoriteFilter matches on `fav_<CODE>`. A mismatch (e.g. "AUSTRALIA" vs "AUS")
// silently reaches nobody.
export const FAVORITE_COUNTRIES = [
  { code: 'AFG', name: 'Afghanistan' },
  { code: 'IND', name: 'India' },
  { code: 'PAK', name: 'Pakistan' },
  { code: 'BAN', name: 'Bangladesh' },
  { code: 'SL', name: 'Sri Lanka' },
  { code: 'AUS', name: 'Australia' },
  { code: 'ENG', name: 'England' },
  { code: 'NZ', name: 'New Zealand' },
  { code: 'SA', name: 'South Africa' },
  { code: 'WI', name: 'West Indies' },
  { code: 'NED', name: 'Netherlands' },
  { code: 'IRE', name: 'Ireland' },
  { code: 'ZIM', name: 'Zimbabwe' },
  { code: 'NEP', name: 'Nepal' },
  { code: 'UAE', name: 'United Arab Emirates' },
  { code: 'USA', name: 'United States' },
  { code: 'OMA', name: 'Oman' },
  { code: 'SCO', name: 'Scotland' },
  { code: 'NAM', name: 'Namibia' },
  { code: 'CAN', name: 'Canada' },
] as const;
