'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import Link from 'next/link';
import { Eye, EyeOff, RefreshCw, Star, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { SearchInput } from '@/components/ui/SearchInput';
import { Button } from '@/components/ui/Button';
import { seriesApi } from '@/lib/api';
import { useAuth, useDebouncedValue, usePermissions, useResource } from '@/lib/hooks';
import { formatDate } from '@/lib/utils';

type Series = {
  id?: number;
  series_id?: string | number;
  external_id?: string;
  name?: string;
  series_name?: string;
  series_type?: string;
  start_date?: string;
  end_date?: string;
  is_featured?: boolean | number;
  is_hidden?: boolean | number;
};

export default function SeriesPage() {
  return (
    <AdminShell permission="series.view">
      <SeriesInner />
    </AdminShell>
  );
}

function SeriesInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const [q, setQ] = useState('');
  const debouncedQ = useDebouncedValue(q, 250);
  const { data, loading, error, reload } = useResource(() => seriesApi.list(), []);
  const all = (data?.data || []) as Series[];

  const rows = useMemo(() => {
    const needle = debouncedQ.toLowerCase();
    if (!needle) return all;
    return all.filter((s) =>
      `${s.name ?? s.series_name ?? ''} ${s.series_type ?? ''}`.toLowerCase().includes(needle),
    );
  }, [all, debouncedQ]);

  async function feature(id: string) {
    await seriesApi.feature(id);
    toast.success('Series featured');
    reload();
  }
  async function hide(id: string, hidden?: boolean | number) {
    await seriesApi.hide(id, !hidden);
    toast.success(hidden ? 'Unhidden' : 'Hidden');
    reload();
  }
  async function refresh(id: string) {
    await seriesApi.refresh(id);
    toast.success('Series refreshed');
    reload();
  }
  async function clearCache(id: string) {
    await seriesApi.cacheClear(id);
    toast.success('Series cache cleared');
  }

  const columns: Column<Series>[] = [
    {
      id: 'name',
      header: 'Series',
      render: (s) => (
        <Link
          href={`/series/${encodeURIComponent(String(s.external_id ?? s.series_id ?? s.id ?? ''))}`}
          className="block"
        >
          <div className="font-medium text-slate-100">{s.name || s.series_name || '—'}</div>
          <div className="text-[10px] uppercase tracking-wide text-slate-500">{s.series_type || '—'}</div>
        </Link>
      ),
    },
    {
      id: 'dates',
      header: 'Dates',
      render: (s) => `${formatDate(s.start_date)} → ${formatDate(s.end_date)}`,
    },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (s) => {
        const id = String(s.external_id ?? s.series_id ?? s.id ?? '');
        return (
          <div className="flex items-center justify-end gap-1">
            {perms.can('series.write') && (
              <>
                <Button size="sm" variant="ghost" icon={<Star className="h-3.5 w-3.5" />} onClick={() => feature(id)}>
                  Feature
                </Button>
                <Button size="sm" variant="ghost" icon={<EyeOff className="h-3.5 w-3.5" />} onClick={() => hide(id, s.is_hidden)}>
                  {s.is_hidden ? 'Unhide' : 'Hide'}
                </Button>
                <Button size="sm" variant="ghost" icon={<RefreshCw className="h-3.5 w-3.5" />} onClick={() => refresh(id)}>
                  Refresh
                </Button>
                <Button size="sm" variant="ghost" icon={<Trash2 className="h-3.5 w-3.5" />} onClick={() => clearCache(id)}>
                  Clear cache
                </Button>
              </>
            )}
          </div>
        );
      },
    },
  ];

  return (
    <>
      <PageHeader
        title="Series"
        description="Search, feature, hide, refresh, and clear cache on cricket series. Series-level points table and stats are pulled from the active provider."
        right={
          <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>
            Refresh
          </Button>
        }
      />
      <SearchInput value={q} onChange={setQ} placeholder="Search series…" className="mb-3 max-w-md" />
      <DataTable
        loading={loading}
        error={error}
        onRetry={reload}
        rows={rows}
        columns={columns}
        rowKey={(s) => String(s.id ?? s.series_id ?? s.external_id ?? Math.random())}
        emptyTitle="No series found"
      />
    </>
  );
}
