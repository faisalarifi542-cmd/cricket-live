'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Flame, RefreshCw, Save, Search, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { Button } from '@/components/ui/Button';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { Field, Input, Select } from '@/components/ui/Input';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { StatCard } from '@/components/ui/StatCard';
import { dataControlApi } from '@/lib/api';
import { useResource } from '@/lib/hooks';

type Source = {
  id: number;
  dataType: string;
  label: string;
  appScreen?: string;
  endpointPath: string;
  providerMethod?: string;
  cacheKeyPrefix: string;
  providerName: string;
  enabled: boolean;
  cacheEnabled: boolean;
  cacheTtlSeconds: number;
  staleFallbackEnabled: boolean;
  timeoutMs: number;
  retryCount: number;
  refreshStrategy: string;
  refreshFrequencySeconds?: number;
  lastSuccessAt?: string | null;
  lastFailureAt?: string | null;
  lastFetchedAt?: string | null;
  lastError?: string | null;
  healthStatus: string;
  providerHealth: string;
};

export default function DataControlPage() {
  return (
    <AdminShell permission="cache.view">
      <DataControlInner />
    </AdminShell>
  );
}

function DataControlInner() {
  const { data, loading, reload } = useResource(() => dataControlApi.list(), []);
  const rows = (data?.data || []) as Source[];
  const cache = data?.cache || {};
  const [q, setQ] = useState('');
  const [editing, setEditing] = useState<Record<string, Partial<Source>>>({});
  const [busy, setBusy] = useState<string | null>(null);

  const filtered = useMemo(() => {
    const needle = q.trim().toLowerCase();
    if (!needle) return rows;
    return rows.filter((r) => `${r.label} ${r.dataType} ${r.endpointPath} ${r.cacheKeyPrefix}`.toLowerCase().includes(needle));
  }, [q, rows]);

  function value<T extends keyof Source>(row: Source, key: T): Source[T] {
    return (editing[row.dataType]?.[key] as Source[T]) ?? row[key];
  }

  function patch(row: Source, update: Partial<Source>) {
    setEditing((prev) => ({ ...prev, [row.dataType]: { ...(prev[row.dataType] || {}), ...update } }));
  }

  async function run(label: string, key: string, fn: () => Promise<unknown>) {
    setBusy(key);
    try {
      await fn();
      toast.success(label);
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Action failed');
    } finally {
      setBusy(null);
    }
  }

  async function save(row: Source) {
    const draft = editing[row.dataType] || {};
    await run('Data source saved', `save:${row.dataType}`, async () => {
      await dataControlApi.update(row.dataType, {
        enabled: draft.enabled ?? row.enabled,
        cache_enabled: draft.cacheEnabled ?? row.cacheEnabled,
        cache_ttl_seconds: Number(draft.cacheTtlSeconds ?? row.cacheTtlSeconds),
        stale_fallback_enabled: draft.staleFallbackEnabled ?? row.staleFallbackEnabled,
        timeout_ms: Number(draft.timeoutMs ?? row.timeoutMs),
        retry_count: Number(draft.retryCount ?? row.retryCount),
        refresh_strategy: draft.refreshStrategy ?? row.refreshStrategy,
        refresh_frequency_seconds: Number(draft.refreshFrequencySeconds ?? row.refreshFrequencySeconds ?? row.cacheTtlSeconds),
      });
      setEditing((prev) => {
        const next = { ...prev };
        delete next[row.dataType];
        return next;
      });
    });
  }

  const columns: Column<Source>[] = [
    {
      id: 'data',
      header: 'Data Type',
      width: '260px',
      render: (r) => (
        <div>
          <div className="font-medium text-slate-100">{r.label}</div>
          <div className="text-[11px] text-slate-400">{r.appScreen || 'App'}</div>
          <div className="text-xs text-slate-500">{r.endpointPath}</div>
          <div className="mt-1 text-[11px] text-cyan-200">{r.cacheKeyPrefix}</div>
        </div>
      ),
    },
    {
      id: 'source',
      header: 'Source',
      render: (r) => (
        <div className="space-y-1">
          <StatusBadge status={r.providerHealth || 'auto'} />
          <div className="text-xs text-slate-400">{r.providerName}</div>
          <div className="text-[11px] text-slate-500">{r.providerMethod || 'local/admin'}</div>
        </div>
      ),
    },
    {
      id: 'ttl',
      header: 'TTL / Strategy',
      width: '220px',
      render: (r) => (
        <div className="grid gap-2">
          <Input
            type="number"
            min={1}
            value={String(value(r, 'cacheTtlSeconds'))}
            onChange={(e) => patch(r, { cacheTtlSeconds: Number(e.target.value) })}
          />
          <Select value={String(value(r, 'refreshStrategy'))} onChange={(e) => patch(r, { refreshStrategy: e.target.value })}>
            <option value="polling">polling</option>
            <option value="stale-while-revalidate">stale-while-revalidate</option>
            <option value="adaptive">adaptive</option>
            <option value="aggregate">aggregate</option>
            <option value="admin">admin</option>
          </Select>
          {['liveMatches', 'liveLine', 'matchDetail'].includes(r.dataType) && Number(value(r, 'cacheTtlSeconds')) > 15 ? (
            <div className="text-[11px] text-amber-200">Live TTL above 15s will be rejected.</div>
          ) : null}
        </div>
      ),
    },
    {
      id: 'toggles',
      header: 'Rules',
      render: (r) => (
        <div className="space-y-2 text-xs">
          <label className="flex items-center gap-2"><input type="checkbox" checked={!!value(r, 'enabled')} onChange={(e) => patch(r, { enabled: e.target.checked })} /> Enabled</label>
          <label className="flex items-center gap-2"><input type="checkbox" checked={!!value(r, 'cacheEnabled')} onChange={(e) => patch(r, { cacheEnabled: e.target.checked })} /> Cache</label>
          <label className="flex items-center gap-2"><input type="checkbox" checked={!!value(r, 'staleFallbackEnabled')} onChange={(e) => patch(r, { staleFallbackEnabled: e.target.checked })} /> Stale fallback</label>
        </div>
      ),
    },
    {
      id: 'health',
      header: 'Health',
      render: (r) => (
        <div className="space-y-1 text-xs">
          <StatusBadge status={r.healthStatus} />
          <div>Fetched: {r.lastFetchedAt ? new Date(r.lastFetchedAt).toLocaleString() : '-'}</div>
          <div>Success: {r.lastSuccessAt ? new Date(r.lastSuccessAt).toLocaleString() : '-'}</div>
          <div>Failure: {r.lastFailureAt ? new Date(r.lastFailureAt).toLocaleString() : '-'}</div>
          {r.lastError ? <div className="max-w-xs truncate text-red-200">{r.lastError}</div> : null}
        </div>
      ),
    },
    {
      id: 'actions',
      header: 'Actions',
      render: (r) => (
        <div className="flex flex-wrap gap-2">
          <Button size="sm" variant="secondary" icon={<Save className="h-3.5 w-3.5" />} loading={busy === `save:${r.dataType}`} onClick={() => save(r)}>
            Save
          </Button>
          <Button size="sm" variant="secondary" icon={<Flame className="h-3.5 w-3.5" />} loading={busy === `warm:${r.dataType}`} onClick={() => run('Warm requested', `warm:${r.dataType}`, () => dataControlApi.warm(r.dataType))}>
            Warm
          </Button>
          <Button size="sm" variant="danger" icon={<Trash2 className="h-3.5 w-3.5" />} loading={busy === `clear:${r.dataType}`} onClick={() => run('Cache cleared', `clear:${r.dataType}`, () => dataControlApi.clear(r.dataType))}>
            Clear
          </Button>
        </div>
      ),
    },
  ];

  return (
    <>
      <PageHeader
        title="Data Control"
        description="Control app data sources, cache TTLs, stale fallback, warm actions, and provider health for Flutter-facing endpoints."
        right={<Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} loading={loading} onClick={reload}>Refresh</Button>}
      />

      <div className="mb-4 grid gap-3 md:grid-cols-4">
        <StatCard label="Redis keys" value={String(cache.totalKeys ?? 0)} />
        <StatCard label="App cache keys" value={String(cache.appCacheKeys ?? 0)} />
        <StatCard label="Stale served" value={String(cache.events?.staleServed ?? 0)} />
        <StatCard label="Provider failures" value={String(cache.events?.failedProviderFetches ?? 0)} />
      </div>

      <Field className="mb-4">
        <div className="relative max-w-lg">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-500" />
          <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search data type, endpoint, cache key" className="pl-9" />
        </div>
      </Field>

      <DataTable rows={filtered} columns={columns} loading={loading} rowKey={(r) => r.dataType} emptyTitle="No data sources" />
    </>
  );
}
