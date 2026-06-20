'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { Eye, RefreshCw, Star, EyeOff, Wand2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { SearchInput } from '@/components/ui/SearchInput';
import { Tabs } from '@/components/ui/Tabs';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { Field, Input } from '@/components/ui/Input';
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
  const [showFetch, setShowFetch] = useState(false);
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
        right={
          perms.can('matches.write') ? (
            <Button variant="secondary" icon={<Wand2 className="h-4 w-4" />} onClick={() => setShowFetch(true)}>
              Fetch by Match ID
            </Button>
          ) : undefined
        }
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

      <MatchFetchDialog open={showFetch} onClose={() => setShowFetch(false)} />
    </>
  );
}

function MatchFetchDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [id, setId] = useState('');
  const [busy, setBusy] = useState(false);
  const [data, setData] = useState<Record<string, any> | null>(null);
  const [provider, setProvider] = useState<string | null>(null);
  const [errMsg, setErrMsg] = useState<string | null>(null);

  async function run() {
    if (!id.trim()) {
      toast.error('Enter a match ID');
      return;
    }
    setBusy(true);
    setData(null);
    setErrMsg(null);
    try {
      const res = await matchesApi.fetchByProviderId(id.trim());
      setData(res.data || {});
      setProvider(res.provider || null);
      toast.success(`Fetched via ${res.provider || 'provider'}`);
    } catch (err) {
      setErrMsg(err instanceof Error ? err.message : 'Provider fetch failed');
    } finally {
      setBusy(false);
    }
  }

  const t1 = data?.team1 || {};
  const t2 = data?.team2 || {};

  return (
    <Modal
      open={open}
      onClose={busy ? () => {} : onClose}
      title="Fetch match by provider ID"
      description="Preview provider match data before using it. Admin overrides on the match detail page let you adjust display values without touching live scores."
      size="lg"
    >
      <div className="grid gap-3 md:grid-cols-[minmax(0,1fr)_auto] md:items-end">
        <Field label="Match ID">
          <Input
            value={id}
            onChange={(e) => setId(e.target.value)}
            placeholder="e.g. 105778"
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); run(); } }}
          />
        </Field>
        <Button icon={<Wand2 className="h-4 w-4" />} loading={busy} onClick={run}>
          Fetch Match
        </Button>
      </div>

      {errMsg && (
        <div className="mt-4 rounded-xl border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-200">
          {errMsg}
        </div>
      )}
      {data && (
        <div className="mt-4 space-y-3">
          <div className="text-xs uppercase tracking-wide text-slate-400">
            Answered by: <span className="text-cyan-300">{provider || 'unknown'}</span>
          </div>
          <div className="rounded-xl border border-line bg-white/[0.03] p-4 text-sm text-slate-200">
            <div className="text-base font-medium text-slate-100">{data.title || '—'}</div>
            <div className="mt-1 text-slate-400">{data.series_name || '—'}</div>
            <div className="mt-3 grid gap-2 md:grid-cols-2">
              <div><span className="text-slate-500">Team 1:</span> {t1.name || '—'} ({t1.short_name || '—'})</div>
              <div><span className="text-slate-500">Team 2:</span> {t2.name || '—'} ({t2.short_name || '—'})</div>
              <div><span className="text-slate-500">Venue:</span> {data.venue || '—'}</div>
              <div><span className="text-slate-500">Format:</span> {data.match_format || '—'}</div>
              <div><span className="text-slate-500">Status:</span> {data.status || '—'}</div>
              <div><span className="text-slate-500">Toss:</span> {data.toss || '—'}</div>
            </div>
          </div>
          <details className="rounded-xl border border-line bg-black/40">
            <summary className="cursor-pointer px-3 py-2 text-xs uppercase tracking-wide text-slate-400">Raw provider data</summary>
            <pre className="max-h-72 overflow-auto px-3 pb-3 text-xs text-slate-300">{JSON.stringify(data.raw ?? data, null, 2)}</pre>
          </details>
        </div>
      )}
    </Modal>
  );
}
