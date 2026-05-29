'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Activity, Database, Flame, RefreshCw, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { StatCard } from '@/components/ui/StatCard';
import { Button } from '@/components/ui/Button';
import { Field, Input } from '@/components/ui/Input';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { cacheApi } from '@/lib/api';
import { useAuth, usePermissions, useResource } from '@/lib/hooks';
import { formatNumber } from '@/lib/utils';

export default function CachePage() {
  return (
    <AdminShell permission="cache.view">
      <CacheInner />
    </AdminShell>
  );
}

function CacheInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const { data, loading, reload } = useResource(() => cacheApi.stats(), []);
  const stats = (data?.data || {}) as Record<string, any> & { status?: string; keys?: number; info?: string };
  const [prefix, setPrefix] = useState('');
  const [matchId, setMatchId] = useState('');
  const [seriesId, setSeriesId] = useState('');
  const [confirmFlush, setConfirmFlush] = useState(false);

  async function run(label: string, fn: () => Promise<{ deleted?: number }>) {
    try {
      const r = await fn();
      toast.success(`${label}: ${r.deleted != null ? `${r.deleted} keys` : 'done'}`);
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  }

  const canWrite = perms.can('cache.write');

  return (
    <>
      <PageHeader
        title="Cache console"
        description="Inspect Redis status, flush keys by prefix or entity, and warm caches for home/match/schedule lookups."
        right={
          <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>
            Refresh
          </Button>
        }
      />

      <div className="mb-6 grid gap-3 md:grid-cols-4">
        <StatCard label="Redis status" value={stats.status || 'unknown'} icon={Database} tone={stats.status === 'ready' ? 'positive' : 'warning'} />
        <StatCard label="Keys" value={formatNumber(stats.keys ?? 0)} icon={Activity} />
        <StatCard label="App cache keys" value={formatNumber(stats.appCacheKeys ?? 0)} icon={Activity} />
        <StatCard label="Stale served" value={formatNumber(stats.events?.staleServed ?? 0)} icon={Activity} />
      </div>

      <div className="mb-6 grid gap-3 md:grid-cols-4">
        <StatCard label="Match keys" value={formatNumber(stats.matchCacheKeys ?? 0)} />
        <StatCard label="Series keys" value={formatNumber(stats.seriesCacheKeys ?? 0)} />
        <StatCard label="Schedule keys" value={formatNumber(stats.scheduleCacheKeys ?? 0)} />
        <StatCard label="News keys" value={formatNumber(stats.newsCacheKeys ?? 0)} />
      </div>

      {canWrite ? (
        <div className="grid gap-4 lg:grid-cols-3">
          <section className="rounded-2xl border border-line bg-panel/40 p-4">
            <h2 className="mb-2 text-sm font-semibold text-slate-100">Flush by prefix</h2>
            <p className="mb-3 text-xs text-slate-500">
              Wildcard scan + delete. Example: <code className="text-cyan-200">match:</code>
            </p>
            <Field>
              <Input value={prefix} onChange={(e) => setPrefix(e.target.value)} placeholder="match:" />
            </Field>
            <Button
              className="mt-3"
              variant="danger"
              icon={<Trash2 className="h-4 w-4" />}
              disabled={!prefix}
              onClick={() => prefix && run('Flush prefix', () => cacheApi.flushPrefix(prefix))}
            >
              Flush prefix
            </Button>
          </section>

          <section className="rounded-2xl border border-line bg-panel/40 p-4">
            <h2 className="mb-2 text-sm font-semibold text-slate-100">Flush by entity</h2>
            <Field label="Match ID">
              <Input value={matchId} onChange={(e) => setMatchId(e.target.value)} placeholder="match_external_id" />
            </Field>
            <Button
              className="mt-2"
              variant="secondary"
              disabled={!matchId}
              onClick={() => matchId && run(`Flush match ${matchId}`, () => cacheApi.flushMatch(matchId))}
            >
              Flush match
            </Button>
            <Field label="Series ID" className="mt-3">
              <Input value={seriesId} onChange={(e) => setSeriesId(e.target.value)} placeholder="series external id" />
            </Field>
            <Button
              className="mt-2"
              variant="secondary"
              disabled={!seriesId}
              onClick={() => seriesId && run(`Flush series ${seriesId}`, () => cacheApi.flushSeries(seriesId))}
            >
              Flush series
            </Button>
          </section>

          <section className="rounded-2xl border border-line bg-panel/40 p-4">
            <h2 className="mb-2 text-sm font-semibold text-slate-100">Warm caches</h2>
            <p className="mb-3 text-xs text-slate-500">Preload high-traffic responses.</p>
            <div className="grid gap-2">
              <Button variant="secondary" icon={<Flame className="h-4 w-4" />} onClick={() => run('Warm home', () => cacheApi.warmHome())}>
                Warm home
              </Button>
              <Button variant="secondary" icon={<Flame className="h-4 w-4" />} onClick={() => run('Warm schedule', () => cacheApi.warmSchedule())}>
                Warm schedule
              </Button>
            </div>
            <div className="mt-4 border-t border-line pt-3">
              <Button variant="danger" icon={<Trash2 className="h-4 w-4" />} onClick={() => setConfirmFlush(true)}>
                Flush ALL Redis keys
              </Button>
            </div>
          </section>
        </div>
      ) : (
        <div className="rounded-xl border border-line bg-panel/40 p-6 text-sm text-slate-400">
          You have read-only access. Ask an admin to perform cache writes.
        </div>
      )}

      <ConfirmDialog
        open={confirmFlush}
        onClose={() => setConfirmFlush(false)}
        onConfirm={() => run('Flush all', () => cacheApi.flush().then(() => ({})))}
        title="Flush ALL Redis keys?"
        description="This will delete every key in the current Redis DB. Public traffic may briefly hit cold caches."
        confirmLabel="Flush everything"
        destructive
      />
    </>
  );
}
