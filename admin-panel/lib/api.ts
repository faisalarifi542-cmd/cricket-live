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

export type StreamRow = Record<string, any> & {
  id: number;
  match_external_id: string;
  quality: string;
  stream_url: string;
  status: string;
  is_active: boolean;
  is_premium: boolean;
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
};

export const playersApi = {
  list: () => adminFetch<{ success: true; data: any[] }>('/admin/players'),
  get: (id: string) =>
    adminFetch<{ success: true; data: any }>(`/admin/players/${id}`),
  refresh: (id: string) =>
    adminFetch<{ success: true }>(`/admin/players/${id}/refresh`, { method: 'POST' }),
  cacheClear: (id: string) =>
    adminFetch<{ success: true }>(`/admin/players/${id}/cache-clear`, {
      method: 'POST',
    }),
};

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
