'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { Eye, EyeOff, RefreshCw, Star, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { SearchInput } from '@/components/ui/SearchInput';
import { FilterBar } from '@/components/ui/FilterBar';
import { Button } from '@/components/ui/Button';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { matchesApi, scheduleApi } from '@/lib/api';
import { useAuth, useDebouncedValue, usePermissions, useResource } from '@/lib/hooks';
import { formatDate, formatDateTime } from '@/lib/utils';

type ScheduleRow = {
  external_id?: string;
  match_external_id?: string;
  id?: number;
  status?: string;
  start_time?: string;
  venue?: string;
  team1?: string;
  team2?: string;
  series_name?: string;
  series_type?: string;
  is_featured?: boolean | number;
  is_hidden?: boolean | number;
};

export default function SchedulePage() {
  return (
    <AdminShell permission="schedule.view">
      <ScheduleInner />
    </AdminShell>
  );
}

function ScheduleInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const [q, setQ] = useState('');
  const debouncedQ = useDebouncedValue(q, 250);
  const [scope, setScope] = useState('all');
  const [date, setDate] = useState('');
  const { data, loading, reload } = useResource(() => scheduleApi.list(), []);
  const all = (data?.data || []) as ScheduleRow[];

  const rows = useMemo(() => {
    const needle = debouncedQ.toLowerCase();
    return all.filter((r) => {
      if (date && !(r.start_time || '').startsWith(date)) return false;
      if (scope !== 'all' && (r.series_type || '').toLowerCase() !== scope) return false;
      if (needle && !`${r.team1 ?? ''} ${r.team2 ?? ''} ${r.series_name ?? ''} ${r.venue ?? ''}`.toLowerCase().includes(needle)) return false;
      return true;
    });
  }, [all, debouncedQ, date, scope]);

  async function refreshAll() {
    await scheduleApi.refresh();
    toast.success('Schedule refreshed');
    reload();
  }
  async function clearAll() {
    await scheduleApi.cacheClear();
    toast.success('Schedule cache cleared');
    reload();
  }
  async function feature(id: string) {
    await matchesApi.feature(id);
    toast.success('Match featured');
    reload();
  }
  async function hide(id: string, hidden?: boolean | number) {
    await matchesApi.hide(id, !hidden);
    toast.success(hidden ? 'Unhidden' : 'Hidden');
    reload();
  }

  const columns: Column<ScheduleRow>[] = [
    {
      id: 'match',
      header: 'Match',
      render: (r) => {
        const id = r.external_id || r.match_external_id || '';
        return (
          <Link href={`/matches/${encodeURIComponent(id)}`} className="block">
            <div className="font-medium text-slate-100">{r.team1 ?? '—'} vs {r.team2 ?? '—'}</div>
            <div className="text-[10px] uppercase tracking-wide text-slate-500">{r.series_name ?? '—'}</div>
          </Link>
        );
      },
    },
    {
      id: 'start',
      header: 'Start',
      render: (r) => <div className="text-sm">{formatDateTime(r.start_time)}</div>,
    },
    { id: 'venue', header: 'Venue', render: (r) => r.venue ?? '—' },
    { id: 'status', header: 'Status', render: (r) => <StatusBadge status={r.status} /> },
    {
      id: 'flags',
      header: 'Flags',
      render: (r) => (
        <div className="flex gap-1">
          {r.is_featured && <StatusBadge tone="info">Featured</StatusBadge>}
          {r.is_hidden && <StatusBadge tone="muted">Hidden</StatusBadge>}
        </div>
      ),
    },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (r) => {
        const id = r.external_id || r.match_external_id || '';
        return (
          <div className="flex items-center justify-end gap-1">
            {perms.can('schedule.write') && (
              <>
                <Button size="sm" variant="ghost" icon={<Star className="h-3.5 w-3.5" />} onClick={() => feature(id)}>
                  Feature
                </Button>
                <Button size="sm" variant="ghost" icon={<EyeOff className="h-3.5 w-3.5" />} onClick={() => hide(id, r.is_hidden)}>
                  {r.is_hidden ? 'Unhide' : 'Hide'}
                </Button>
              </>
            )}
            <Link href={`/matches/${encodeURIComponent(id)}`}>
              <Button size="sm" variant="ghost" icon={<Eye className="h-3.5 w-3.5" />}>Open</Button>
            </Link>
          </div>
        );
      },
    },
  ];

  return (
    <>
      <PageHeader
        title="Schedule"
        description="Browse the full match schedule. Feature or hide individual matches, refresh from upstream, or clear the schedule cache."
        right={
          <>
            <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>
              Refresh
            </Button>
            {perms.can('schedule.write') && (
              <>
                <Button onClick={refreshAll}>Refresh upstream</Button>
                <Button variant="danger" onClick={clearAll} icon={<Trash2 className="h-4 w-4" />}>
                  Clear cache
                </Button>
              </>
            )}
          </>
        }
      />
      <div className="mb-3 flex flex-wrap items-center gap-3">
        <SearchInput value={q} onChange={setQ} placeholder="Search team, series, venue…" className="max-w-md flex-1" />
        <input
          type="date"
          value={date}
          onChange={(e) => setDate(e.target.value)}
          className="h-9 rounded-lg border border-line bg-white/5 px-3 text-sm text-slate-100"
        />
        {date && <Button size="sm" variant="ghost" onClick={() => setDate('')}>Clear date</Button>}
      </div>
      <FilterBar
        filters={[
          {
            type: 'select',
            id: 'scope',
            label: 'Scope',
            value: scope,
            options: [
              { id: 'all', label: 'All' },
              { id: 'international', label: 'International' },
              { id: 'league', label: 'League' },
              { id: 'domestic', label: 'Domestic' },
              { id: 'women', label: 'Women' },
            ],
            onChange: setScope,
          },
        ]}
        right={<div className="text-xs text-slate-500">{formatDate(date) || 'All dates'}</div>}
      />
      <DataTable loading={loading} rows={rows} columns={columns} rowKey={(r) => String(r.external_id ?? r.match_external_id ?? r.id ?? Math.random())} emptyTitle="No matches found" />
    </>
  );
}
