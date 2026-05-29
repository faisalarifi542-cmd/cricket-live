'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { RefreshCw, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { SearchInput } from '@/components/ui/SearchInput';
import { Button } from '@/components/ui/Button';
import { teamsApi } from '@/lib/api';
import { useAuth, useDebouncedValue, usePermissions, useResource } from '@/lib/hooks';

type Team = {
  id?: number;
  team_id?: string | number;
  name?: string;
  short_name?: string;
  country?: string;
  logo_url?: string;
};

export default function TeamsPage() {
  return (
    <AdminShell permission="teams.view">
      <TeamsInner />
    </AdminShell>
  );
}

function TeamsInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const [q, setQ] = useState('');
  const debouncedQ = useDebouncedValue(q, 250);
  const { data, loading, reload } = useResource(() => teamsApi.list(), []);
  const all = (data?.data || []) as Team[];

  const rows = useMemo(() => {
    const needle = debouncedQ.toLowerCase();
    if (!needle) return all;
    return all.filter((t) =>
      `${t.name ?? ''} ${t.short_name ?? ''} ${t.country ?? ''}`.toLowerCase().includes(needle),
    );
  }, [all, debouncedQ]);

  const columns: Column<Team>[] = [
    {
      id: 'team',
      header: 'Team',
      render: (t) => {
        const id = String(t.team_id ?? t.id ?? '');
        return (
          <Link href={`/teams/${encodeURIComponent(id)}`} className="flex items-center gap-3">
            {t.logo_url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={t.logo_url} alt={t.name ?? ''} className="h-8 w-8 rounded-md object-contain bg-white/5" />
            ) : (
              <div className="grid h-8 w-8 place-items-center rounded-md bg-white/5 text-[10px] uppercase text-slate-400">
                {(t.short_name || t.name || '?').slice(0, 3)}
              </div>
            )}
            <div>
              <div className="font-medium text-slate-100">{t.name ?? '—'}</div>
              <div className="text-[10px] uppercase tracking-wide text-slate-500">{t.country ?? t.short_name ?? '—'}</div>
            </div>
          </Link>
        );
      },
    },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (t) => {
        const id = String(t.team_id ?? t.id ?? '');
        return (
          <div className="flex items-center justify-end gap-1">
            {perms.can('teams.write') && (
              <>
                <Button size="sm" variant="ghost" icon={<RefreshCw className="h-3.5 w-3.5" />} onClick={async () => { await teamsApi.refresh(id); toast.success('Team refreshed'); reload(); }}>
                  Refresh
                </Button>
                <Button size="sm" variant="ghost" icon={<Trash2 className="h-3.5 w-3.5" />} onClick={async () => { await teamsApi.cacheClear(id); toast.success('Cache cleared'); }}>
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
        title="Teams"
        description="Search and manage cricket teams. Refresh and clear cache to pull latest squad and profile data."
        right={
          <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>
            Refresh
          </Button>
        }
      />
      <SearchInput value={q} onChange={setQ} placeholder="Search teams…" className="mb-3 max-w-md" />
      <DataTable loading={loading} rows={rows} columns={columns} rowKey={(t) => String(t.id ?? t.team_id ?? Math.random())} emptyTitle="No teams found" />
    </>
  );
}
