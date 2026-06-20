'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  clearToken,
  getStoredUser,
  setStoredUser,
  type StoredAdminUser,
} from './auth';
import { authApi, ApiError } from './api';
import { hasAny, hasPermission } from './permissions';

export type AuthState = {
  user: StoredAdminUser | null;
  loading: boolean;
  signOut: () => Promise<void>;
  reload: () => Promise<void>;
};

export function useAuth(): AuthState {
  const [user, setUser] = useState<StoredAdminUser | null>(() =>
    typeof window === 'undefined' ? null : getStoredUser(),
  );
  const [loading, setLoading] = useState<boolean>(true);

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      const me = await authApi.me();
      setUser(me.user);
      setStoredUser(me.user);
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) {
        setUser(null);
        clearToken();
      }
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    reload();
  }, [reload]);

  const signOut = useCallback(async () => {
    try {
      await authApi.logout();
    } catch {
      /* ignore */
    } finally {
      clearToken();
      setUser(null);
      if (typeof window !== 'undefined') {
        window.location.href = '/login';
      }
    }
  }, []);

  return { user, loading, signOut, reload };
}

export function usePermissions(user: StoredAdminUser | null) {
  return useMemo(
    () => ({
      can: (permission: string) => hasPermission(user?.permissions, permission),
      canAny: (list: string[]) => hasAny(user?.permissions, list),
      isSuperAdmin: !!user?.roles?.includes('super_admin'),
    }),
    [user],
  );
}

export type ResourceState<T> = {
  data: T | null;
  error: string | null;
  loading: boolean;
  reload: () => Promise<void>;
};

export function useResource<T>(
  loader: () => Promise<T>,
  deps: ReadonlyArray<unknown> = [],
): ResourceState<T> {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const reload = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const result = await loader();
      setData(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load');
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    setError(null);
    loader()
      .then((result) => {
        if (alive) setData(result);
      })
      .catch((err: unknown) => {
        if (alive)
          setError(err instanceof Error ? err.message : 'Failed to load');
      })
      .finally(() => {
        if (alive) setLoading(false);
      });
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  return { data, error, loading, reload };
}

export function useDebouncedValue<T>(value: T, ms = 250): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const t = setTimeout(() => setDebounced(value), ms);
    return () => clearTimeout(t);
  }, [value, ms]);
  return debounced;
}
