import {
  Activity,
  Bell,
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
  type LucideIcon,
} from 'lucide-react';

export const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL || 'https://api.webcrichd.co';

export type NavItem = {
  label: string;
  href: string;
  icon: LucideIcon;
  permission?: string;
  group: 'live' | 'content' | 'ops' | 'access';
};

export const navigation: NavItem[] = [
  // Live ops
  { label: 'Dashboard', href: '/dashboard', icon: Gauge, permission: 'dashboard.view', group: 'live' },
  { label: 'Matches', href: '/matches', icon: Trophy, permission: 'matches.view', group: 'live' },
  { label: 'Live Streams', href: '/streams', icon: PlaySquare, permission: 'streams.view', group: 'live' },
  { label: 'API Providers', href: '/providers', icon: Radio, permission: 'providers.view', group: 'live' },
  { label: 'API Keys', href: '/api-keys', icon: KeyRound, permission: 'apiKeys.view', group: 'live' },

  // Content
  { label: 'App Settings', href: '/settings', icon: Settings, permission: 'settings.view', group: 'content' },
  { label: 'Home Manager', href: '/homepage', icon: Home, permission: 'home.view', group: 'content' },
  { label: 'Series', href: '/series', icon: ClipboardList, permission: 'series.view', group: 'content' },
  { label: 'Teams', href: '/teams', icon: Users, permission: 'teams.view', group: 'content' },
  { label: 'Players', href: '/players', icon: UserRound, permission: 'players.view', group: 'content' },
  { label: 'Schedule', href: '/schedule', icon: CalendarDays, permission: 'schedule.view', group: 'content' },
  { label: 'News', href: '/news', icon: Newspaper, permission: 'news.view', group: 'content' },

  // Operations
  { label: 'Notifications', href: '/notifications', icon: Bell, permission: 'notifications.view', group: 'ops' },
  { label: 'Ads', href: '/ads', icon: Megaphone, permission: 'ads.view', group: 'ops' },
  { label: 'Cache', href: '/cache', icon: DatabaseZap, permission: 'cache.view', group: 'ops' },
  { label: 'Data Control', href: '/data-control', icon: SlidersHorizontal, permission: 'cache.view', group: 'ops' },
  { label: 'Health & Logs', href: '/health', icon: HeartPulse, permission: 'health.view', group: 'ops' },

  // Access control
  { label: 'Admin Users', href: '/users', icon: UserSquare2, permission: 'adminUsers.view', group: 'access' },
  { label: 'Roles', href: '/roles', icon: Shield, permission: 'roles.view', group: 'access' },
  { label: 'Audit Logs', href: '/audit-logs', icon: FileKey, permission: 'audit.view', group: 'access' },
];

export const navigationGroups: { id: NavItem['group']; label: string }[] = [
  { id: 'live', label: 'Live Operations' },
  { id: 'content', label: 'Content' },
  { id: 'ops', label: 'Operations' },
  { id: 'access', label: 'Access Control' },
];

export const STREAM_QUALITIES = ['AUTO', 'FHD', 'HD', 'SD'] as const;
export const STREAM_TYPES = ['hls', 'dash', 'iframe', 'external'] as const;
export const STREAM_STATUSES = ['unknown', 'working', 'slow', 'down'] as const;

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
  { id: 'premium', label: 'Premium users' },
] as const;

export const NOTIFICATION_DEEP_LINKS = [
  { id: 'home', label: 'Home' },
  { id: 'match', label: 'Match details' },
  { id: 'live', label: 'Live player' },
  { id: 'series', label: 'Series' },
  { id: 'news', label: 'News article' },
  { id: 'schedule', label: 'Schedule' },
  { id: 'rankings', label: 'Rankings' },
] as const;
