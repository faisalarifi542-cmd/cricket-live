'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { RefreshCw, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { SearchInput } from '@/components/ui/SearchInput';
import { FilterBar } from '@/components/ui/FilterBar';
import { Button } from '@/components/ui/Button';
import { playersApi } from '@/lib/api';
import { useAuth, useDebouncedValue, usePermissions, useResource } from '@/lib/hooks';

type Player = {
  id?: number;
  player_id?: string | number;
  name?: string;
  role?: string;
  country?: string;
  image_url?: string;
};

export default function PlayersPage() {
  return (
    <AdminShell permission="players.view">
      <PlayersInner />
    </AdminShell>
  );
}

function PlayersInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const [q, setQ] = useState('');
  const debouncedQ = useDebouncedValue(q, 250);
  const [role, setRole] = useState('all');
  const [country, setCountry] = useState('all');

  const { data, loading, reload } = useResource(() => playersApi.list(), []);
  const all = (data?.data || []) as Player[];

  const countries = useMemo(() => {
    return Array.from(new Set(all.map((p) => p.country).filter(Boolean))) as string[];
  }, [all]);
  const roles = useMemo(() => {
    return Array.from(new Set(all.map((p) => p.role).filter(Boolean))) as string[];
  }, [all]);

  const rows = useMemo(() => {
    const needle = debouncedQ.toLowerCase();
    return all.filter((p) => {
      if (role !== 'all' && p.role !== role) return false;
      if (country !== 'all' && p.country !== country) return false;
      if (needle && !`${p.name ?? ''} ${p.country ?? ''} ${p.role ?? ''}`.toLowerCase().includes(needle)) return false;
      return true;
    });
  }, [all, debouncedQ, role, country]);

  const columns: Column<Player>[] = [
    {
      id: 'player',
      header: 'Player',
      render: (p) => {
        const id = String(p.player_id ?? p.id ?? '');
        return (
          <Link href={`/players/${encodeURIComponent(id)}`} className="flex items-center gap-3">
            {p.image_url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={p.image_url} alt={p.name ?? ''} className="h-8 w-8 rounded-full object-cover bg-white/5" />
            ) : (
              <div className="grid h-8 w-8 place-items-center rounded-full bg-white/5 text-[10px] uppercase text-slate-400">
                {(p.name || '?').slice(0, 2)}
              </div>
            )}
            <div>
              <div className="font-medium text-slate-100">{p.name ?? '—'}</div>
              <div className="text-[10px] uppercase tracking-wide text-slate-500">{p.role ?? '—'}</div>
            </div>
          </Link>
        );
      },
    },
    { id: 'country', header: 'Country', render: (p) => p.country ?? '—' },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (p) => {
        const id = String(p.player_id ?? p.id ?? '');
        return (
          <div className="flex items-center justify-end gap-1">
            {perms.can('players.write') && (
              <>
                <Button size="sm" variant="ghost" icon={<RefreshCw className="h-3.5 w-3.5" />} onClick={async () => { await playersApi.refresh(id); toast.success('Refreshed'); reload(); }}>
                  Refresh
                </Button>
                <Button size="sm" variant="ghost" icon={<Trash2 className="h-3.5 w-3.5" />} onClick={async () => { await playersApi.cacheClear(id); toast.success('Cache cleared'); }}>
                  Clear
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
        title="Players"
        description="Search players by name, role, or country. Refresh to pull latest profile data."
        right={
          <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>
            Refresh
          </Button>
        }
      />
      <SearchInput value={q} onChange={setQ} placeholder="Search players…" className="mb-3 max-w-md" />
      <FilterBar
        filters={[
          {
            type: 'select',
            id: 'role',
            label: 'Role',
            value: role,
            options: [{ id: 'all', label: 'All' }, ...roles.map((r) => ({ id: r, label: r }))],
            onChange: setRole,
          },
          {
            type: 'select',
            id: 'country',
            label: 'Country',
            value: country,
            options: [{ id: 'all', label: 'All' }, ...countries.map((c) => ({ id: c, label: c }))],
            onChange: setCountry,
          },
        ]}
      />
      <DataTable loading={loading} rows={rows} columns={columns} rowKey={(p) => String(p.id ?? p.player_id ?? Math.random())} emptyTitle="No players found" />
    </>
  );
}
