'use client';

import { API_BASE_URL } from './constants';
import {
  clearToken,
  getToken,
  setStoredUser,
  setToken,
  type StoredAdminUser,
} from './auth';

export class ApiError extends Error {
  status: number;
  payload?: unknown;
  constructor(message: string, status: number, payload?: unknown) {
    super(message);
    this.status = status;
    this.payload = payload;
  }
}

type FetchOptions = RequestInit & {
  /** When true, do not redirect to /login on 401. Used by /admin/me */
  silent?: boolean;
  /** When true, do not retry on 401 via /admin/refresh */
  noRefresh?: boolean;
};

let refreshPromise: Promise<string | null> | null = null;

async function performRefresh(): Promise<string | null> {
  try {
    const res = await fetch(`${API_BASE_URL}/admin/refresh`, {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
    });
    if (!res.ok) return null;
    const data = await res.json();
    if (!data?.success || !data?.token) return null;
    setToken(data.token);
    if (data.user) setStoredUser(data.user as StoredAdminUser);
    return data.token as string;
  } catch {
    return null;
  }
}

function refreshAccessToken(): Promise<string | null> {
  if (!refreshPromise) {
    refreshPromise = performRefresh().finally(() => {
      refreshPromise = null;
    });
  }
  return refreshPromise;
}

function redirectToLogin() {
  if (typeof window === 'undefined') return;
  if (window.location.pathname.startsWith('/login')) return;
  const next = encodeURIComponent(
    window.location.pathname + window.location.search,
  );
  window.location.href = `/login?next=${next}`;
}

export async function adminFetch<T = unknown>(
  path: string,
  init: FetchOptions = {},
): Promise<T> {
  const url = path.startsWith('http') ? path : `${API_BASE_URL}${path}`;
  const token = getToken();
  const headers = new Headers(init.headers || {});
  if (!headers.has('Content-Type') && init.body && typeof init.body === 'string') {
    headers.set('Content-Type', 'application/json');
  }
  if (token) headers.set('Authorization', `Bearer ${token}`);

  let res: Response;
  try {
    res = await fetch(url, { ...init, headers, credentials: 'include' });
  } catch (err) {
    throw new ApiError(
      err instanceof Error ? err.message : 'Network error',
      0,
    );
  }

  if (res.status === 401 && !init.noRefresh) {
    const newToken = await refreshAccessToken();
    if (newToken) {
      const retryHeaders = new Headers(headers);
      retryHeaders.set('Authorization', `Bearer ${newToken}`);
      res = await fetch(url, {
        ...init,
        headers: retryHeaders,
        credentials: 'include',
      });
    }
  }

  if (res.status === 401) {
    clearToken();
    if (!init.silent) redirectToLogin();
    const text = await res.text().catch(() => '');
    throw new ApiError('Unauthorized', 401, text);
  }

  let json: unknown;
  const text = await res.text();
  if (text) {
    try {
      json = JSON.parse(text);
    } catch {
      json = text;
    }
  }

  if (!res.ok || (json && typeof json === 'object' && (json as { success?: boolean }).success === false)) {
    const message =
      (json && typeof json === 'object' && 'error' in json
        ? String((json as { error?: unknown }).error)
        : null) ||
      `Request failed (${res.status})`;
    throw new ApiError(message, res.status, json);
  }
  return json as T;
}

const j = (body: unknown) => JSON.stringify(body ?? {});

// =====================================================
// Module-specific clients
// =====================================================

export const authApi = {
  login: (email: string, password: string) =>
    adminFetch<{ success: true; token: string; user: StoredAdminUser }>(
      '/admin/login',
      { method: 'POST', body: j({ username: email, email, password }), noRefresh: true, silent: true },
    ),
  logout: () => adminFetch<{ success: true }>('/admin/logout', { method: 'POST' }),
  me: () => adminFetch<{ success: true; user: StoredAdminUser }>('/admin/me', { silent: true }),
  changePassword: (current_password: string, new_password: string) =>
    adminFetch<{ success: true }>('/admin/me/password', {
      method: 'POST',
      body: j({ current_password, new_password }),
    }),
};

export const dashboardApi = {
  get: () => adminFetch<{ success: true; data: any }>('/admin/dashboard'),
  stats: () => adminFetch<{ success: true; data: any }>('/admin/stats'),
};

export type AnalyticsSummary = {
  range: { from: string; to: string };
  activeUsers: { today: number; last7Days: number; last30Days: number };
  newUsers: { today: number; inRange: number };
  totalUsers: number;
  returningUsersToday: number;
  firstOpensApproxInstalls: { total: number; newInRange: number };
  sessions: number;
  sessionsToday: number;
  appOpens: number;
  screenViews: number;
  matchOpens: number;
  liveStreamOpens: number;
  qualitySelections: number;
  pullRefreshCount: number;
  retryAfterErrorCount: number;
  topScreens: Array<{ screen: string; count: number }>;
  topMatches: Array<{ matchId: string; count: number }>;
  topStreamQualities: Array<{ quality: string; count: number }>;
  appVersions: Array<{ appVersion: string; count: number }>;
  platforms: Array<{ platform: string; count: number }>;
};

export type AnalyticsSeriesPoint = { date: string; value: number };

const analyticsQs = (params: Record<string, string | undefined>) => {
  const sp = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v) sp.set(k, v);
  }
  const s = sp.toString();
  return s ? `?${s}` : '';
};

export const analyticsApi = {
  summary: (from?: string, to?: string) =>
    adminFetch<{ success: true; data: AnalyticsSummary }>(
      `/admin/analytics/summary${analyticsQs({ from, to })}`,
    ),
  timeseries: (metric: string, from?: string, to?: string, granularity = 'day') =>
    adminFetch<{ success: true; data: { metric: string; granularity: string; series: AnalyticsSeriesPoint[] } }>(
      `/admin/analytics/timeseries${analyticsQs({ metric, from, to, granularity })}`,
    ),
  breakdown: (dimension: string, from?: string, to?: string) =>
    adminFetch<{ success: true; data: { dimension: string; items: Array<{ label: string; count: number }> } }>(
      `/admin/analytics/breakdown${analyticsQs({ dimension, from, to })}`,
    ),
};

export type StreamRow = Record<string, any> & {
  id: number;
  match_external_id: string;
  match_title?: string | null;
  team_a?: string | null;
  team_b?: string | null;
  title?: string | null;
  label?: string | null;
  language?: string | null;
  server_name?: string | null;
  quality: string;
  stream_type: string;
  stream_url: string;
  backup_stream_url?: string | null;
  status: string;
  is_active: boolean;
  is_premium: boolean;
  requires_reward_ad?: boolean;
  requires_login?: boolean;
  priority?: number;
  starts_at?: string | null;
  ends_at?: string | null;
  lifecycle_state?: string | null;
  timezone?: string | null;
  early_show_minutes?: number;
  auto_hide_after_end?: boolean;
  user_agent_header?: string | null;
  referer_header?: string | null;
  origin_header?: string | null;
  headers_json?: Record<string, unknown> | string | null;
  drm_enabled?: boolean;
  drm_type?: string | null;
  drm_license_url?: string | null;
  drm_headers?: Record<string, unknown> | string | null;
  clear_key_key_id?: string | null;
  clear_key_key?: string | null;
};

export const streamsApi = {
  list: (params: Record<string, string | undefined> = {}) => {
    const qs = new URLSearchParams(
      Object.entries(params).filter(([, v]) => v != null && v !== '') as [string, string][],
    ).toString();
    return adminFetch<{ success: true; data: StreamRow[] }>(
      `/admin/streams${qs ? `?${qs}` : ''}`,
    );
  },
  get: (id: number | string) =>
    adminFetch<{ success: true; data: StreamRow }>(`/admin/streams/${id}`),
  create: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; data: StreamRow }>('/admin/streams', {
      method: 'POST',
      body: j(body),
    }),
  update: (id: number | string, body: Record<string, unknown>) =>
    adminFetch<{ success: true; data: StreamRow }>(`/admin/streams/${id}`, {
      method: 'PUT',
      body: j(body),
    }),
  delete: (id: number | string) =>
    adminFetch<{ success: true }>(`/admin/streams/${id}`, { method: 'DELETE' }),
  toggle: (id: number | string) =>
    adminFetch<{ success: true; is_active: boolean }>(
      `/admin/streams/${id}/toggle`,
      { method: 'POST' },
    ),
  test: (id: number | string) =>
    adminFetch<{ success: true; status: string; latency_ms: number; http_status?: number }>(
      `/admin/streams/${id}/test`,
      { method: 'POST' },
    ),
  health: (id: number | string) =>
    adminFetch<{ success: true; data: any[] }>(`/admin/streams/${id}/health`),
  cacheClear: (id: number | string) =>
    adminFetch<{ success: true }>(`/admin/streams/${id}/cache-clear`, {
      method: 'POST',
    }),
  servers: () =>
    adminFetch<{ success: true; data: any[] }>('/admin/streams/servers'),
};

export const matchesApi = {
  list: (params: Record<string, string | undefined> = {}) => {
    const qs = new URLSearchParams(
      Object.entries(params).filter(([, v]) => v != null && v !== '') as [string, string][],
    ).toString();
    return adminFetch<{ success: true; data: any[] }>(
      `/admin/matches${qs ? `?${qs}` : ''}`,
    );
  },
  get: (id: string) =>
    adminFetch<{ success: true; data: any }>(`/admin/matches/${id}`),
  override: (id: string, body: Record<string, unknown>) =>
    adminFetch<{ success: true }>(`/admin/matches/${id}/override`, {
      method: 'PUT',
      body: j(body),
    }),
  feature: (id: string) =>
    adminFetch<{ success: true }>(`/admin/matches/${id}/feature`, {
      method: 'POST',
    }),
  hide: (id: string, hidden = true) =>
    adminFetch<{ success: true }>(`/admin/matches/${id}/hide`, {
      method: 'POST',
      body: j({ hidden }),
    }),
  refresh: (id: string) =>
    adminFetch<{ success: true; cleared: number }>(`/admin/matches/${id}/refresh`, {
      method: 'POST',
    }),
  cacheClear: (id: string) =>
    adminFetch<{ success: true; cleared: number }>(
      `/admin/matches/${id}/cache-clear`,
      { method: 'POST' },
    ),
  // Auto-fill: fetch a match from the provider by its ID (preview before save).
  fetchByProviderId: (matchId: string) =>
    adminFetch<{ success: true; provider: string; data: any }>(
      '/admin/matches/fetch-by-provider-id',
      { method: 'POST', body: j({ match_id: matchId }) },
    ),
};

export const providersApi = {
  list: () =>
    adminFetch<{ success: true; data: any[] }>('/admin/providers'),
  create: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; data: any }>('/admin/providers', {
      method: 'POST',
      body: j(body),
    }),
  update: (id: number, body: Record<string, unknown>) =>
    adminFetch<{ success: true; data: any }>(`/admin/providers/${id}`, {
      method: 'PUT',
      body: j(body),
    }),
  delete: (id: number) =>
    adminFetch<{ success: true }>(`/admin/providers/${id}`, { method: 'DELETE' }),
  toggle: (id: number) =>
    adminFetch<{ success: true; is_active: boolean }>(
      `/admin/providers/${id}/toggle`,
      { method: 'POST' },
    ),
  test: (id: number) =>
    adminFetch<{ success: true; status: string; routes?: any[]; latency_ms?: number; failed_route?: string | null }>(
      `/admin/providers/${id}/test`,
      { method: 'POST' },
    ),
  reset: (id: number) =>
    adminFetch<{ success: true }>(`/admin/providers/${id}/reset`, { method: 'POST' }),
  cacheClear: (id: number) =>
    adminFetch<{ success: true; cleared: number }>(
      `/admin/providers/${id}/cache-clear`,
      { method: 'POST' },
    ),
  listKeys: (id: number) =>
    adminFetch<{ success: true; data: any[] }>(`/admin/providers/${id}/keys`),
  addKey: (id: number, body: { label: string; key_value: string; notes?: string }) =>
    adminFetch<{ success: true; id: number }>(`/admin/providers/${id}/keys`, {
      method: 'POST',
      body: j(body),
    }),
  deleteKey: (id: number, keyId: number) =>
    adminFetch<{ success: true }>(`/admin/providers/${id}/keys/${keyId}`, {
      method: 'DELETE',
    }),
  // Connection tests that exercise a real provider data fetch (player/team/match)
  // through the DB-configured priority + failover chain.
  testPlayer: (playerId: string) =>
    adminFetch<{ success: true; provider: string; data: any }>(
      '/admin/providers/test-player',
      { method: 'POST', body: j({ player_id: playerId }) },
    ),
  testTeam: (teamId: string) =>
    adminFetch<{ success: true; provider: string; data: any }>(
      '/admin/providers/test-team',
      { method: 'POST', body: j({ team_id: teamId }) },
    ),
  testMatch: (matchId: string) =>
    adminFetch<{ success: true; provider: string; data: any }>(
      '/admin/providers/test-match',
      { method: 'POST', body: j({ match_id: matchId }) },
    ),
};

export const apiKeysApi = {
  list: () => adminFetch<{ success: true; data: any[] }>('/admin/api-keys'),
  create: (body: {
    name: string;
    email?: string;
    tier?: string;
    rate_limit?: number;
    expires_in_days?: number;
  }) =>
    adminFetch<{
      success: true;
      api_key: string;
      tier: string;
      rate_limit: number;
      expires_at?: string;
    }>('/admin/api-keys', { method: 'POST', body: j(body) }),
  update: (id: number, body: Record<string, unknown>) =>
    adminFetch<{ success: true }>(`/admin/api-keys/${id}`, {
      method: 'PATCH',
      body: j(body),
    }),
  delete: (id: number) =>
    adminFetch<{ success: true }>(`/admin/api-keys/${id}`, { method: 'DELETE' }),
  revoke: (id: number) =>
    adminFetch<{ success: true }>(`/admin/api-keys/${id}/revoke`, { method: 'POST' }),
};

export const settingsApi = {
  list: (group?: string) =>
    adminFetch<{ success: true; data: any[] }>(
      `/admin/app-settings${group ? `?group=${encodeURIComponent(group)}` : ''}`,
    ),
  get: (key: string) =>
    adminFetch<{ success: true; data: any }>(
      `/admin/app-settings/${encodeURIComponent(key)}`,
    ),
  update: (key: string, body: { setting_value: unknown; setting_group?: string; description?: string }) =>
    adminFetch<{ success: true; data: any }>(
      `/admin/app-settings/${encodeURIComponent(key)}`,
      { method: 'PUT', body: j(body) },
    ),
};

export const homeApi = {
  getLayout: () =>
    adminFetch<{ success: true; data: any }>('/admin/home-config/layout'),
  saveLayout: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; data: any }>('/admin/home-config/layout', {
      method: 'PUT',
      body: j(body),
    }),
  listSections: () =>
    adminFetch<{ success: true; data: any[] }>('/admin/home-config/sections'),
  createSection: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; id: number }>('/admin/home-config/sections', {
      method: 'POST',
      body: j(body),
    }),
  updateSection: (id: number, body: Record<string, unknown>) =>
    adminFetch<{ success: true }>(`/admin/home-config/sections/${id}`, {
      method: 'PUT',
      body: j(body),
    }),
  deleteSection: (id: number) =>
    adminFetch<{ success: true }>(`/admin/home-config/sections/${id}`, {
      method: 'DELETE',
    }),
  listFeatured: (kind: 'featured-matches' | 'featured-series' | 'featured-news') =>
    adminFetch<{ success: true; data: any[] }>(`/admin/home-config/${kind}`),
  addFeatured: (
    kind: 'featured-matches' | 'featured-series' | 'featured-news',
    body: Record<string, unknown>,
  ) =>
    adminFetch<{ success: true; id: number }>(`/admin/home-config/${kind}`, {
      method: 'POST',
      body: j(body),
    }),
  deleteFeatured: (
    kind: 'featured-matches' | 'featured-series' | 'featured-news',
    id: number,
  ) =>
    adminFetch<{ success: true }>(`/admin/home-config/${kind}/${id}`, {
      method: 'DELETE',
    }),
  // Featured series support full manual fields (poster, name, date range,
  // location) since the cricket provider has no featured-series feed.
  addFeaturedSeries: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; id: number }>('/admin/home-config/featured-series', {
      method: 'POST',
      body: j(body),
    }),
  updateFeaturedSeries: (id: number, body: Record<string, unknown>) =>
    adminFetch<{ success: true }>(`/admin/home-config/featured-series/${id}`, {
      method: 'PUT',
      body: j(body),
    }),
  // Upload an image as a base64 data URL; returns an absolute public URL.
  uploadImage: (dataUrl: string, mimeType?: string) =>
    adminFetch<{ success: true; url: string; relativeUrl: string; bytes: number }>(
      '/admin/home-config/upload-image',
      { method: 'POST', body: j({ dataUrl, mimeType }) },
    ),
  listBanners: () =>
    adminFetch<{ success: true; data: any[] }>('/admin/home-config/banners'),
  createBanner: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; id: number }>('/admin/home-config/banners', {
      method: 'POST',
      body: j(body),
    }),
  deleteBanner: (id: number) =>
    adminFetch<{ success: true }>(`/admin/home-config/banners/${id}`, {
      method: 'DELETE',
    }),
};

export const seriesApi = {
  list: () => adminFetch<{ success: true; data: any[] }>('/admin/series'),
  get: (id: string) =>
    adminFetch<{ success: true; data: any }>(`/admin/series/${id}`),
  feature: (id: string) =>
    adminFetch<{ success: true }>(`/admin/series/${id}/feature`, { method: 'POST' }),
  hide: (id: string, hidden = true) =>
    adminFetch<{ success: true }>(`/admin/series/${id}/hide`, {
      method: 'POST',
      body: j({ hidden }),
    }),
  refresh: (id: string) =>
    adminFetch<{ success: true }>(`/admin/series/${id}/refresh`, { method: 'POST' }),
  cacheClear: (id: string) =>
    adminFetch<{ success: true }>(`/admin/series/${id}/cache-clear`, {
      method: 'POST',
    }),
};

export const teamsApi = {
  list: () => adminFetch<{ success: true; data: any[] }>('/admin/teams'),
  get: (id: string) =>
    adminFetch<{ success: true; data: any }>(`/admin/teams/${id}`),
  refresh: (id: string) =>
    adminFetch<{ success: true }>(`/admin/teams/${id}/refresh`, { method: 'POST' }),
  cacheClear: (id: string) =>
    adminFetch<{ success: true }>(`/admin/teams/${id}/cache-clear`, {
      method: 'POST',
    }),
  // Persist a team logo (and optionally name/short/country). The app prefers
  // this admin logo over the Cricbuzz source everywhere.
  update: (id: string | number, body: Record<string, unknown>) =>
    adminFetch<{ success: true }>(`/admin/teams/${id}`, {
      method: 'PUT',
      body: j(body),
    }),
  create: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; id: number }>('/admin/teams', {
      method: 'POST',
      body: j(body),
    }),
  delete: (id: string | number) =>
    adminFetch<{ success: true }>(`/admin/teams/${id}`, { method: 'DELETE' }),
  syncFromApi: () =>
    adminFetch<{ success: true; candidates: number; inserted: number; updated: number }>(
      '/admin/teams/sync-from-api',
      { method: 'POST' },
    ),
  // Auto-fill: fetch a team from the provider by its ID to pre-fill the form.
  fetchByProviderId: (teamId: string) =>
    adminFetch<{ success: true; provider: string; data: any }>(
      '/admin/teams/fetch-by-provider-id',
      { method: 'POST', body: j({ team_id: teamId }) },
    ),
  // Upload a team flag/logo as a base64 data URL; returns a public URL.
  uploadFlag: (dataUrl: string, mimeType?: string) =>
    adminFetch<{ success: true; url: string; relativeUrl: string; bytes: number }>(
      '/admin/teams/upload-flag',
      { method: 'POST', body: j({ dataUrl, mimeType }) },
    ),
  // Global team-logo source priority order + master enable flag. The order is a
  // permutation of ["admin","local","api","initials"]; the app applies it
  // everywhere (Home, Match Details, Live Player, …).
  getLogoOrder: () =>
    adminFetch<{ success: true; order: TeamLogoSource[]; enabled: boolean; sources: TeamLogoSource[] }>(
      '/admin/teams/logo-order',
    ),
  setLogoOrder: (order: TeamLogoSource[], enabled: boolean) =>
    adminFetch<{ success: true; order: TeamLogoSource[]; enabled: boolean }>(
      '/admin/teams/logo-order',
      { method: 'PUT', body: j({ order, enabled }) },
    ),
};

export const TEAM_LOGO_SOURCES = ['admin', 'local', 'api', 'initials'] as const;

export type TeamLogoSource = (typeof TEAM_LOGO_SOURCES)[number];

export const DEFAULT_TEAM_LOGO_ORDER: TeamLogoSource[] = [
  'admin',
  'local',
  'api',
  'initials',
];

export const playersApi = {
  list: () =>
    adminFetch<{ success: true; data: any[]; globalMode: string }>('/admin/players'),
  get: (id: string) =>
    adminFetch<{ success: true; data: any }>(`/admin/players/${id}`),
  refresh: (id: string) =>
    adminFetch<{ success: true }>(`/admin/players/${id}/refresh`, { method: 'POST' }),
  cacheClear: (id: string) =>
    adminFetch<{ success: true }>(`/admin/players/${id}/cache-clear`, {
      method: 'POST',
    }),
  // Persist a player's image fields / override. The app resolves the shown
  // image from these according to the global/per-player mode.
  update: (id: string | number, body: Record<string, unknown>) =>
    adminFetch<{ success: true }>(`/admin/players/${id}`, {
      method: 'PUT',
      body: j(body),
    }),
  create: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; id: number; data?: { id: number } }>('/admin/players', {
      method: 'POST',
      body: j(body),
    }),
  // Auto-fill: fetch a player from the provider by its ID to pre-fill the form.
  fetchByProviderId: (playerId: string) =>
    adminFetch<{ success: true; provider: string; data: any }>(
      '/admin/players/fetch-by-provider-id',
      { method: 'POST', body: j({ player_id: playerId }) },
    ),
  delete: (id: string | number) =>
    adminFetch<{ success: true }>(`/admin/players/${id}`, { method: 'DELETE' }),
  // Upload a player photo as a base64 data URL; returns a public URL.
  uploadImage: (dataUrl: string, mimeType?: string) =>
    adminFetch<{ success: true; url: string; relativeUrl: string; bytes: number }>(
      '/admin/players/upload-image',
      { method: 'POST', body: j({ dataUrl, mimeType }) },
    ),
  // Persist ONLY the image fields for a player.
  updateImage: (id: string | number, body: Record<string, unknown>) =>
    adminFetch<{ success: true }>(`/admin/players/${id}/image`, {
      method: 'PUT',
      body: j(body),
    }),
  // Remove only the admin-uploaded image (keeps any provider image).
  removeImage: (id: string | number) =>
    adminFetch<{ success: true }>(`/admin/players/${id}/image`, { method: 'DELETE' }),
  // Global image resolution mode (canonical endpoint + spec-named alias).
  getImageMode: () =>
    adminFetch<{ success: true; mode: string; modes: string[] }>(
      '/admin/players/image-mode',
    ),
  setImageMode: (mode: string) =>
    adminFetch<{ success: true; mode: string }>('/admin/players/image-mode', {
      method: 'PUT',
      body: j({ mode }),
    }),
  getImageSettings: () =>
    adminFetch<{ success: true; data: { mode: string; modes: string[]; defaultMode: string } }>(
      '/admin/player-image-settings',
    ),
  setImageSettings: (mode: string) =>
    adminFetch<{ success: true; data: { mode: string } }>('/admin/player-image-settings', {
      method: 'PUT',
      body: j({ mode }),
    }),
  // Bulk tools.
  refreshImages: (onlyMissing = true) =>
    adminFetch<{ success: true; scanned: number; updated: number }>(
      '/admin/players/refresh-images',
      { method: 'POST', body: j({ onlyMissing }) },
    ),
  applyGlobalMode: () =>
    adminFetch<{ success: true }>('/admin/players/apply-global-mode', {
      method: 'POST',
    }),
  clearAdminImages: () =>
    adminFetch<{ success: true; affected: number }>('/admin/players/clear-admin-images', {
      method: 'POST',
      body: j({ confirm: true }),
    }),
};

export const PLAYER_IMAGE_MODES = [
  'admin_first',
  'cricbuzz_first',
  'admin_only',
  'cricbuzz_only',
  'initials_only',
] as const;

export type PlayerImageMode = (typeof PLAYER_IMAGE_MODES)[number];

export const scheduleApi = {
  list: () => adminFetch<{ success: true; data: any[] }>('/admin/schedule'),
  refresh: () =>
    adminFetch<{ success: true }>('/admin/schedule/refresh', { method: 'POST' }),
  cacheClear: () =>
    adminFetch<{ success: true }>('/admin/schedule/cache-clear', { method: 'POST' }),
};

export const newsApi = {
  list: () => adminFetch<{ success: true; data: any[] }>('/admin/news'),
  create: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; id: number }>('/admin/news', {
      method: 'POST',
      body: j(body),
    }),
  update: (id: number, body: Record<string, unknown>) =>
    adminFetch<{ success: true }>(`/admin/news/${id}`, { method: 'PUT', body: j(body) }),
  delete: (id: number) =>
    adminFetch<{ success: true }>(`/admin/news/${id}`, { method: 'DELETE' }),
  feature: (id: number) =>
    adminFetch<{ success: true }>(`/admin/news/${id}/feature`, { method: 'POST' }),
  hide: (id: number) =>
    adminFetch<{ success: true }>(`/admin/news/${id}/hide`, { method: 'POST' }),
  cacheClear: () =>
    adminFetch<{ success: true }>('/admin/news/cache-clear', { method: 'POST' }),
};

export const notificationsApi = {
  list: () =>
    adminFetch<{ success: true; data: any[] }>('/admin/notifications'),
  create: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; id: number }>('/admin/notifications', {
      method: 'POST',
      body: j(body),
    }),
  update: (id: number, body: Record<string, unknown>) =>
    adminFetch<{ success: true }>(`/admin/notifications/${id}`, {
      method: 'PUT',
      body: j(body),
    }),
  delete: (id: number) =>
    adminFetch<{ success: true }>(`/admin/notifications/${id}`, { method: 'DELETE' }),
  send: (id: number) =>
    adminFetch<{ success: true }>(`/admin/notifications/${id}/send`, { method: 'POST' }),
  sendDirect: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; data?: any }>('/admin/notifications/send', {
      method: 'POST',
      body: j(body),
    }),
  test: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; data?: any }>('/admin/notifications/test', {
      method: 'POST',
      body: j(body),
    }),
  history: () =>
    adminFetch<{ success: true; data: any[] }>('/admin/notifications/history'),
};

export const adsApi = {
  get: () => adminFetch<{ success: true; data: any[] }>('/admin/ads'),
  update: (body: Record<string, unknown>) =>
    adminFetch<{ success: true }>('/admin/ads', { method: 'PUT', body: j(body) }),
};

export const cacheApi = {
  stats: () => adminFetch<{ success: true; data: any }>('/admin/cache/stats'),
  flush: () =>
    adminFetch<{ success: true }>('/admin/cache/flush', { method: 'POST' }),
  flushPrefix: (prefix: string) =>
    adminFetch<{ success: true; deleted: number }>('/admin/cache/flush-prefix', {
      method: 'POST',
      body: j({ prefix }),
    }),
  flushMatch: (matchId: string) =>
    adminFetch<{ success: true; deleted: number }>(
      `/admin/cache/flush-match/${matchId}`,
      { method: 'POST' },
    ),
  flushSeries: (seriesId: string) =>
    adminFetch<{ success: true; deleted: number }>(
      `/admin/cache/flush-series/${seriesId}`,
      { method: 'POST' },
    ),
  warmHome: () =>
    adminFetch<{ success: true; deleted: number }>('/admin/cache/warm-home', {
      method: 'POST',
    }),
  warmSchedule: () =>
    adminFetch<{ success: true; deleted: number }>('/admin/cache/warm-schedule', {
      method: 'POST',
    }),
  warmMatch: (matchId: string) =>
    adminFetch<{ success: true; deleted: number }>(
      `/admin/cache/warm-match/${matchId}`,
      { method: 'POST' },
    ),
};

export const dataControlApi = {
  list: () => adminFetch<{ success: true; data: any[]; cache: any; providers: any[] }>('/admin/data-control/sources'),
  update: (dataType: string, body: Record<string, unknown>) =>
    adminFetch<{ success: true; data: any }>(`/admin/data-control/sources/${dataType}`, {
      method: 'PUT',
      body: j(body),
    }),
  clear: (dataType: string, targetId?: string) =>
    adminFetch<{ success: true; deleted: number }>(`/admin/data-control/sources/${dataType}/clear`, {
      method: 'POST',
      body: j({ targetId }),
    }),
  warm: (dataType: string, targetId?: string) =>
    adminFetch<{ success: true; meta: any }>(`/admin/data-control/sources/${dataType}/warm`, {
      method: 'POST',
      body: j({ targetId }),
    }),
  health: () => adminFetch<{ success: true; data: any }>('/admin/data-control/health-check', { method: 'POST' }),
};

export type AppAssetRow = {
  key: string;
  theme: 'light' | 'dark' | 'both';
  category?: string;
  label: string;
  where?: string | null;
  dimensions: string | null;
  fallback?: string | null;
  large?: boolean;
  wired?: boolean;
  themed?: boolean;
  universalSafe?: boolean;
  url: string | null;
  version: string | null;
  is_active: boolean;
  updated_at: string | null;
  configured: boolean;
};

export type AppAssetGuidance = {
  preferFormats: string[];
  maxUploadBytes: number;
  recommendedWidth: number;
  notes: string[];
};

export const assetsApi = {
  list: () =>
    adminFetch<{ success: true; data: AppAssetRow[]; guidance?: AppAssetGuidance }>('/admin/assets'),
  uploadImage: (dataUrl: string, mimeType?: string) =>
    adminFetch<{ success: true; url: string; relativeUrl: string; bytes: number }>(
      '/admin/assets/upload-image',
      { method: 'POST', body: j({ dataUrl, mimeType }) },
    ),
  upsert: (key: string, theme: string, body: { url?: string | null; is_active?: boolean; version?: string }) =>
    adminFetch<{ success: true }>(`/admin/assets/${encodeURIComponent(key)}/${encodeURIComponent(theme)}`, {
      method: 'PUT',
      body: j(body),
    }),
  toggle: (key: string, theme: string, isActive: boolean) =>
    adminFetch<{ success: true }>(`/admin/assets/${encodeURIComponent(key)}/${encodeURIComponent(theme)}/active`, {
      method: 'PATCH',
      body: j({ is_active: isActive }),
    }),
  remove: (key: string, theme: string) =>
    adminFetch<{ success: true }>(`/admin/assets/${encodeURIComponent(key)}/${encodeURIComponent(theme)}`, {
      method: 'DELETE',
    }),
};

export type SplashAssetSlot = {
  settingKey: string;
  field: string;
  label: string;
  hint: string;
  dimensions: string;
};

export type SplashSettings = {
  splash_enabled: boolean;
  splash_duration_ms: number;
  splash_skip_after_first_launch: boolean;
  splash_stadium_background_url: string;
  splash_cp_logo_url: string;
  splash_wordmark_panel_url: string;
  splash_orbit_trail_url: string;
  splash_pitch_wickets_url: string;
};

export type SplashResolved = {
  enabled: boolean;
  durationMs: number;
  skipAfterFirstLaunch: boolean;
  assets: {
    stadiumBackground: string | null;
    cpLogo: string | null;
    wordmarkPanel: string | null;
    orbitTrail: string | null;
    pitchWickets: string | null;
  };
};

export const splashApi = {
  get: () =>
    adminFetch<{
      success: true;
      data: {
        settings: SplashSettings;
        resolved: SplashResolved;
        slots: SplashAssetSlot[];
        keys: string[];
        defaults: Record<string, unknown>;
      };
    }>('/admin/splash-settings'),
  save: (settings: Partial<SplashSettings>) =>
    adminFetch<{ success: true; data: { settings: SplashSettings; resolved: SplashResolved } }>(
      '/admin/splash-settings',
      { method: 'PUT', body: j({ settings }) },
    ),
  uploadImage: (dataUrl: string, mimeType?: string) =>
    adminFetch<{ success: true; url: string; relativeUrl: string; bytes: number }>(
      '/admin/splash-settings/upload-image',
      { method: 'POST', body: j({ dataUrl, mimeType }) },
    ),
};

export const healthApi = {
  get: () => adminFetch<{ success: true; data: any }>('/admin/health'),
  logs: (params: Record<string, string | undefined> = {}) => {
    const qs = new URLSearchParams(
      Object.entries(params).filter(([, v]) => v != null && v !== '') as [string, string][],
    ).toString();
    return adminFetch<{ success: true; data: any[] }>(
      `/admin/logs${qs ? `?${qs}` : ''}`,
    );
  },
};

export const usersApi = {
  list: () => adminFetch<{ success: true; data: any[] }>('/admin/users'),
  get: (id: number) =>
    adminFetch<{ success: true; data: any }>(`/admin/users/${id}`),
  create: (body: { name: string; email: string; password: string; role?: string }) =>
    adminFetch<{ success: true; id: number }>('/admin/users', {
      method: 'POST',
      body: j(body),
    }),
  update: (id: number, body: Record<string, unknown>) =>
    adminFetch<{ success: true }>(`/admin/users/${id}`, {
      method: 'PUT',
      body: j(body),
    }),
  delete: (id: number) =>
    adminFetch<{ success: true }>(`/admin/users/${id}`, { method: 'DELETE' }),
  setRoles: (id: number, roles: string[]) =>
    adminFetch<{ success: true }>(`/admin/users/${id}/roles`, {
      method: 'POST',
      body: j({ roles }),
    }),
  resetPassword: (id: number, password: string) =>
    adminFetch<{ success: true }>(`/admin/users/${id}/password`, {
      method: 'POST',
      body: j({ password }),
    }),
};

export const rolesApi = {
  list: () =>
    adminFetch<{ success: true; data: any[]; permissions: Record<string, string> }>(
      '/admin/roles',
    ),
  create: (body: { slug: string; name: string; description?: string; permissions: string[] }) =>
    adminFetch<{ success: true; id: number }>('/admin/roles', {
      method: 'POST',
      body: j(body),
    }),
  update: (slug: string, body: Record<string, unknown>) =>
    adminFetch<{ success: true }>(`/admin/roles/${slug}`, {
      method: 'PUT',
      body: j(body),
    }),
  delete: (slug: string) =>
    adminFetch<{ success: true }>(`/admin/roles/${slug}`, { method: 'DELETE' }),
};

export const auditApi = {
  list: (params: Record<string, string | undefined> = {}) => {
    const qs = new URLSearchParams(
      Object.entries(params).filter(([, v]) => v != null && v !== '') as [string, string][],
    ).toString();
    return adminFetch<{ success: true; data: any[] }>(
      `/admin/audit-logs${qs ? `?${qs}` : ''}`,
    );
  },
};

export const manualMatchesApi = {
  list: () => adminFetch<{ success: true; data: any[] }>('/admin/manual-matches'),
  get: (id: number | string) => adminFetch<{ success: true; data: any }>(`/admin/manual-matches/${id}`),
  create: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; data: any }>('/admin/manual-matches', { method: 'POST', body: j(body) }),
  update: (id: number | string, body: Record<string, unknown>) =>
    adminFetch<{ success: true; data: any }>(`/admin/manual-matches/${id}`, { method: 'PUT', body: j(body) }),
  toggle: (id: number | string) =>
    adminFetch<{ success: true; is_enabled: boolean }>(`/admin/manual-matches/${id}/toggle`, { method: 'POST' }),
  delete: (id: number | string) =>
    adminFetch<{ success: true }>(`/admin/manual-matches/${id}`, { method: 'DELETE' }),
};

// =====================================================
// API Security / Access Control
// =====================================================
const qs = (params: Record<string, string | number | undefined> = {}) => {
  const s = new URLSearchParams(
    Object.entries(params).filter(([, v]) => v != null && v !== '') as [string, string][],
  ).toString();
  return s ? `?${s}` : '';
};

export const apiSecurityApi = {
  // Clients
  listClients: () => adminFetch<{ success: true; data: any[] }>('/admin/api-security/clients'),
  createClient: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; id: number; api_key: string; api_key_prefix: string; warning: string }>(
      '/admin/api-security/clients',
      { method: 'POST', body: j(body) },
    ),
  updateClient: (id: number, body: Record<string, unknown>) =>
    adminFetch<{ success: true }>(`/admin/api-security/clients/${id}`, { method: 'PUT', body: j(body) }),
  regenerateClientKey: (id: number) =>
    adminFetch<{ success: true; api_key: string; api_key_prefix: string; warning: string }>(
      `/admin/api-security/clients/${id}/regenerate-key`,
      { method: 'POST' },
    ),
  revokeClient: (id: number) =>
    adminFetch<{ success: true }>(`/admin/api-security/clients/${id}/revoke`, { method: 'POST' }),

  // Allowed origins / domains
  listOrigins: () => adminFetch<{ success: true; data: any[] }>('/admin/api-security/origins'),
  createOrigin: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; id: number }>('/admin/api-security/origins', { method: 'POST', body: j(body) }),
  updateOrigin: (id: number, body: Record<string, unknown>) =>
    adminFetch<{ success: true }>(`/admin/api-security/origins/${id}`, { method: 'PUT', body: j(body) }),
  deleteOrigin: (id: number) =>
    adminFetch<{ success: true }>(`/admin/api-security/origins/${id}`, { method: 'DELETE' }),

  // Endpoint rules
  listEndpointRules: () => adminFetch<{ success: true; data: any[] }>('/admin/api-security/endpoint-rules'),
  createEndpointRule: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; id: number }>('/admin/api-security/endpoint-rules', { method: 'POST', body: j(body) }),
  updateEndpointRule: (id: number, body: Record<string, unknown>) =>
    adminFetch<{ success: true }>(`/admin/api-security/endpoint-rules/${id}`, { method: 'PUT', body: j(body) }),

  // Blocklist
  listBlocklist: () => adminFetch<{ success: true; data: any[] }>('/admin/api-security/blocklist'),
  createBlock: (body: Record<string, unknown>) =>
    adminFetch<{ success: true; id: number }>('/admin/api-security/blocklist', { method: 'POST', body: j(body) }),
  updateBlock: (id: number, body: Record<string, unknown>) =>
    adminFetch<{ success: true }>(`/admin/api-security/blocklist/${id}`, { method: 'PUT', body: j(body) }),
  deleteBlock: (id: number) =>
    adminFetch<{ success: true }>(`/admin/api-security/blocklist/${id}`, { method: 'DELETE' }),

  // Logs
  listLogs: (params: Record<string, string | number | undefined> = {}) =>
    adminFetch<{ success: true; data: any[]; pagination: { page: number; limit: number; total: number } }>(
      `/admin/api-security/logs${qs(params)}`,
    ),
  trimLogs: (days: number) =>
    adminFetch<{ success: true; deleted: number }>('/admin/api-security/logs/trim', {
      method: 'POST',
      body: j({ days }),
    }),

  // Mode + dashboard
  getMode: () => adminFetch<{ success: true; data: { mode: string } }>('/admin/api-security/mode'),
  setMode: (mode: string) =>
    adminFetch<{ success: true; data: { mode: string } }>('/admin/api-security/mode', {
      method: 'PUT',
      body: j({ mode }),
    }),
  dashboard: () => adminFetch<{ success: true; data: any }>('/admin/api-security/dashboard'),
};
