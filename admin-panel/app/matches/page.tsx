'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { Eye, RefreshCw, Star, EyeOff } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { SearchInput } from '@/components/ui/SearchInput';
import { Tabs } from '@/components/ui/Tabs';
import { Button } from '@/components/ui/Button';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { matchesApi } from '@/lib/api';
import { useAuth, useDebouncedValue, usePermissions, useResource } from '@/lib/hooks';
import { MATCH_TABS } from '@/lib/constants';
import { formatDateTime, formatRelative } from '@/lib/utils';

type MatchRow = {
  external_id: string;
  match_external_id?: string;
  status?: string;
  status_text?: string;
  start_time?: string;
  venue?: string;
  team1?: string;
  team2?: string;
  team_a?: string;
  team_b?: string;
  series_name?: string;
  is_featured?: boolean;
  is_hidden?: boolean;
  updated_at?: string;
};

type MatchTab = (typeof MATCH_TABS)[number]['id'];

export default function MatchesPage() {
  return (
    <AdminShell permission="matches.view">
      <MatchesInner />
    </AdminShell>
  );
}

function MatchesInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const [tab, setTab] = useState<MatchTab>('live');
  const [q, setQ] = useState('');
  const debouncedQ = useDebouncedValue(q, 250);

  const { data, loading, error, reload } = useResource(
    () => matchesApi.list({ tab, q: debouncedQ || undefined }),
    [tab, debouncedQ],
  );

  const rows = useMemo(() => (data?.data || []) as MatchRow[], [data]);

  async function feature(id: string) {
    await matchesApi.feature(id);
    toast.success('Match featured');
    reload();
  }
  async function hide(id: string, current?: boolean) {
    await matchesApi.hide(id, !current);
    toast.success(current ? 'Match unhidden' : 'Match hidden');
    reload();
  }
  async function refresh(id: string) {
    await matchesApi.refresh(id);
    toast.success('Match refreshed');
    reload();
  }

  const columns: Column<MatchRow>[] = [
    {
      id: 'match',
      header: 'Match',
      render: (r) => {
        const id = r.external_id || r.match_external_id || '';
        return (
          <Link href={`/matches/${encodeURIComponent(id)}`} className="block">
            <div className="font-medium text-slate-100">
              {(r.team1 || r.team_a) ?? '—'} vs {(r.team2 || r.team_b) ?? '—'}
            </div>
            <div className="text-[10px] uppercase tracking-wide text-slate-500">
              {r.series_name || id}
            </div>
          </Link>
        );
      },
    },
    {
      id: 'status',
      header: 'Status',
      render: (r) => <StatusBadge status={r.status || r.status_text} />,
    },
    {
      id: 'start',
      header: 'Start',
      render: (r) => (
        <div>
          <div className="text-sm text-slate-200">{formatDateTime(r.start_time)}</div>
          <div className="text-xs text-slate-500">{formatRelative(r.start_time)}</div>
        </div>
      ),
    },
    {
      id: 'venue',
      header: 'Venue',
      render: (r) => <span className="text-sm text-slate-300">{r.venue || '—'}</span>,
    },
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
            <Link href={`/matches/${encodeURIComponent(id)}`}>
              <Button size="sm" variant="ghost" icon={<Eye className="h-3.5 w-3.5" />}>
                Open
              </Button>
            </Link>
            {perms.can('matches.write') && (
              <>
                <Button
                  size="sm"
                  variant="ghost"
                  icon={<Star className="h-3.5 w-3.5" />}
                  onClick={() => feature(id)}
                >
                  Feature
                </Button>
                <Button
                  size="sm"
                  variant="ghost"
                  icon={<EyeOff className="h-3.5 w-3.5" />}
                  onClick={() => hide(id, r.is_hidden)}
                >
                  {r.is_hidden ? 'Unhide' : 'Hide'}
                </Button>
              </>
            )}
            {perms.can('matches.refresh') && (
              <Button
                size="sm"
                variant="secondary"
                icon={<RefreshCw className="h-3.5 w-3.5" />}
                onClick={() => refresh(id)}
              >
                Refresh
              </Button>
            )}
          </div>
        );
      },
    },
  ];

  return (
    <>
      <PageHeader
        title="Matches"
        description="Search, filter, feature, hide, and refresh matches. Use overrides to fix display data — never replace real cricket scores."
      />

      <div className="mb-4 flex flex-wrap items-center gap-3">
        <Tabs
          tabs={MATCH_TABS}
          value={tab}
          onChange={(t) => setTab(t as MatchTab)}
        />
        <SearchInput
          value={q}
          onChange={setQ}
          placeholder="Search by team, series, venue, ID…"
          className="max-w-md flex-1"
        />
        <div className="ml-auto text-xs text-slate-500">
          {rows.length} match{rows.length === 1 ? '' : 'es'}
        </div>
      </div>

      <DataTable
        loading={loading}
        error={error}
        onRetry={reload}
        rows={rows}
        columns={columns}
        rowKey={(r) => r.external_id || r.match_external_id || ''}
        emptyTitle="No matches found"
      />
    </>
  );
}
