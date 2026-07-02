'use client';

import {
  Users,
  UserPlus,
  Activity,
  Radio,
  Trophy,
  RefreshCw,
  Eye,
  AlertTriangle,
} from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { StatCard } from '@/components/ui/StatCard';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { Button } from '@/components/ui/Button';
import { analyticsApi, type AnalyticsSeriesPoint } from '@/lib/api';
import { useResource } from '@/lib/hooks';
import { formatNumber } from '@/lib/utils';

// ---- Date range presets -------------------------------------------------
type RangeKey = 'today' | '7d' | '30d' | 'custom';

function isoDay(d: Date) {
  return d.toISOString().slice(0, 10);
}

function rangeFor(key: RangeKey, customFrom?: string, customTo?: string) {
  const to = new Date();
  if (key === 'today') {
    const from = new Date();
    from.setHours(0, 0, 0, 0);
    return { from: from.toISOString(), to: to.toISOString() };
  }
  if (key === '7d') {
    const from = new Date(to.getTime() - 7 * 24 * 3600 * 1000);
    return { from: from.toISOString(), to: to.toISOString() };
  }
  if (key === '30d') {
    const from = new Date(to.getTime() - 30 * 24 * 3600 * 1000);
    return { from: from.toISOString(), to: to.toISOString() };
  }
  // custom
  const from = customFrom ? new Date(`${customFrom}T00:00:00`) : new Date(to.getTime() - 30 * 24 * 3600 * 1000);
  const toD = customTo ? new Date(`${customTo}T23:59:59`) : to;
  return { from: from.toISOString(), to: toD.toISOString() };
}

// ---- Tiny dependency-free bar chart ------------------------------------
function MiniBarChart({ data, color = 'bg-cyan-400/70' }: { data: AnalyticsSeriesPoint[]; color?: string }) {
  const max = Math.max(1, ...data.map((d) => d.value));
  if (!data.length) {
    return <div className="py-8 text-center text-sm text-slate-500">No data in range</div>;
  }
  return (
    <div className="flex h-40 items-end gap-[2px] overflow-hidden">
      {data.map((d) => (
        <div key={d.date} className="group relative flex flex-1 items-end" style={{ minWidth: 2 }}>
          <div
            className={`w-full rounded-t ${color} transition-all`}
            style={{ height: `${Math.max(2, (d.value / max) * 100)}%` }}
            title={`${d.date}: ${d.value}`}
          />
        </div>
      ))}
    </div>
  );
}

export default function AnalyticsPage() {
  return (
    <AdminShell permission="analytics.view">
      <AnalyticsInner />
    </AdminShell>
  );
}

function AnalyticsInner() {
  const [rangeKey, setRangeKey] = useState<RangeKey>('7d');
  const [customFrom, setCustomFrom] = useState(isoDay(new Date(Date.now() - 30 * 24 * 3600 * 1000)));
  const [customTo, setCustomTo] = useState(isoDay(new Date()));

  const { from, to } = useMemo(
    () => rangeFor(rangeKey, customFrom, customTo),
    [rangeKey, customFrom, customTo],
  );

  const summary = useResource(() => analyticsApi.summary(from, to), [from, to]);
  const dau = useResource(() => analyticsApi.timeseries('active_users', from, to, 'day'), [from, to]);
  const sessions = useResource(() => analyticsApi.timeseries('sessions', from, to, 'day'), [from, to]);
  const streams = useResource(() => analyticsApi.timeseries('live_stream_opens', from, to, 'day'), [from, to]);

  // Realtime active users from the Redis presence window — refreshed every 30s.
  const realtime = useResource(() => analyticsApi.realtime(), []);
  useEffect(() => {
    const id = setInterval(() => realtime.reload(), 30_000);
    return () => clearInterval(id);
  }, [realtime.reload]);
  const live = realtime.data?.data;

  const data = summary.data?.data;
  const num = (v?: number) => formatNumber(v ?? 0);

  function reloadAll() {
    summary.reload();
    dau.reload();
    sessions.reload();
    streams.reload();
  }

  const screenCols: Column<{ screen: string; count: number }>[] = [
    { id: 'screen', header: 'Screen', render: (r) => <span className="font-medium text-slate-100">{r.screen}</span> },
    { id: 'count', header: 'Views', render: (r) => formatNumber(r.count) },
  ];
  const matchCols: Column<{ matchId: string; count: number }>[] = [
    { id: 'match', header: 'Match ID', render: (r) => <span className="font-mono text-xs text-cyan-200">{r.matchId}</span> },
    { id: 'count', header: 'Opens', render: (r) => formatNumber(r.count) },
  ];
  const qualityCols: Column<{ quality: string; count: number }>[] = [
    { id: 'quality', header: 'Quality', render: (r) => r.quality },
    { id: 'count', header: 'Selections', render: (r) => formatNumber(r.count) },
  ];
  const versionCols: Column<{ appVersion: string; count: number }>[] = [
    { id: 'version', header: 'App version', render: (r) => <span className="font-mono text-xs">{r.appVersion}</span> },
    { id: 'count', header: 'Devices', render: (r) => formatNumber(r.count) },
  ];
  const platformCols: Column<{ platform: string; count: number }>[] = [
    { id: 'platform', header: 'Platform', render: (r) => r.platform },
    { id: 'count', header: 'Devices', render: (r) => formatNumber(r.count) },
  ];

  const presets: { key: RangeKey; label: string }[] = [
    { key: 'today', label: 'Today' },
    { key: '7d', label: '7 days' },
    { key: '30d', label: '30 days' },
    { key: 'custom', label: 'Custom' },
  ];

  return (
    <>
      <PageHeader
        title="Analytics"
        description="Privacy-safe app usage. Anonymous device/session IDs only — no personal data collected. Install numbers are First Opens / Approx Installs (distinct devices), not exact Play Store installs."
        right={
          <Button
            variant="secondary"
            icon={<RefreshCw className="h-4 w-4" />}
            onClick={reloadAll}
            loading={summary.loading}
          >
            Refresh
          </Button>
        }
      />

      {/* Date range filter */}
      <div className="mb-6 flex flex-wrap items-center gap-2">
        {presets.map((p) => (
          <button
            key={p.key}
            onClick={() => setRangeKey(p.key)}
            className={`rounded-lg border px-3 py-1.5 text-sm transition ${
              rangeKey === p.key
                ? 'border-cyan-300/40 bg-cyan-400/15 text-cyan-100'
                : 'border-line bg-white/[0.03] text-slate-300 hover:border-cyan-300/20'
            }`}
          >
            {p.label}
          </button>
        ))}
        {rangeKey === 'custom' && (
          <div className="flex items-center gap-2">
            <input
              type="date"
              value={customFrom}
              onChange={(e) => setCustomFrom(e.target.value)}
              className="rounded-lg border border-line bg-white/[0.03] px-2 py-1.5 text-sm text-slate-200"
            />
            <span className="text-slate-500">→</span>
            <input
              type="date"
              value={customTo}
              onChange={(e) => setCustomTo(e.target.value)}
              className="rounded-lg border border-line bg-white/[0.03] px-2 py-1.5 text-sm text-slate-200"
            />
          </div>
        )}
      </div>

      {summary.error && (
        <div className="mb-4 rounded-xl border border-red-400/30 bg-red-400/10 px-4 py-3 text-sm text-red-200">
          {summary.error}
        </div>
      )}

      {/* Summary cards */}
      <div className="mb-6 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Active users now"
          value={live ? num(live.activeUsers) : '—'}
          icon={Radio}
          tone={live && live.activeUsers > 0 ? 'positive' : 'default'}
          hint={
            live
              ? `In the last ${live.windowSeconds}s · ${num(live.activeSessions)} sessions`
              : 'No live users yet'
          }
        />
        <StatCard
          label="New users (today)"
          value={num(data?.newUsers.today)}
          icon={UserPlus}
          tone="positive"
          hint="First-time installs today"
        />
        <StatCard
          label="Total users"
          value={num(data?.totalUsers)}
          icon={Users}
          hint={`+${num(data?.newUsers.inRange)} new in range`}
        />
        <StatCard label="Active users (today)" value={num(data?.activeUsers.today)} icon={Users} tone="positive" hint="Unique devices today" />
        <StatCard label="Active users (30d / MAU)" value={num(data?.activeUsers.last30Days)} icon={Users} hint="Unique devices this month" />
        <StatCard label="Active users (7d)" value={num(data?.activeUsers.last7Days)} icon={Users} />
        <StatCard
          label="Returning users (today)"
          value={num(data?.returningUsersToday)}
          icon={Users}
          hint="Active today, installed earlier"
        />
        <StatCard label="Sessions" value={num(data?.sessions)} icon={Activity} hint={`${num(data?.sessionsToday)} today · 30-min window`} />
        <StatCard label="App opens" value={num(data?.appOpens)} icon={RefreshCw} hint="Every open/resume" />
        <StatCard label="Live stream opens" value={num(data?.liveStreamOpens)} icon={Radio} tone="positive" />
        <StatCard label="Match opens" value={num(data?.matchOpens)} icon={Trophy} />
        <StatCard
          label="Retry after error"
          value={num(data?.retryAfterErrorCount)}
          icon={AlertTriangle}
          tone={(data?.retryAfterErrorCount ?? 0) > 0 ? 'warning' : 'default'}
        />
        <StatCard label="Screen views" value={num(data?.screenViews)} icon={Eye} />
        <StatCard label="Quality selections" value={num(data?.qualitySelections)} icon={Radio} />
        <StatCard label="Pull refreshes" value={num(data?.pullRefreshCount)} icon={RefreshCw} />
      </div>

      {/* Charts */}
      <div className="mb-6 grid gap-4 xl:grid-cols-3">
        <section className="rounded-2xl border border-line bg-panel/40 p-4">
          <h2 className="mb-3 text-sm font-semibold text-slate-100">Daily active users</h2>
          <MiniBarChart data={dau.data?.data.series ?? []} color="bg-cyan-400/70" />
        </section>
        <section className="rounded-2xl border border-line bg-panel/40 p-4">
          <h2 className="mb-3 text-sm font-semibold text-slate-100">Sessions over time</h2>
          <MiniBarChart data={sessions.data?.data.series ?? []} color="bg-emerald-400/70" />
        </section>
        <section className="rounded-2xl border border-line bg-panel/40 p-4">
          <h2 className="mb-3 text-sm font-semibold text-slate-100">Live stream starts over time</h2>
          <MiniBarChart data={streams.data?.data.series ?? []} color="bg-violet-400/70" />
        </section>
      </div>

      {/* Tables */}
      <div className="grid gap-6 xl:grid-cols-2">
        <section className="rounded-2xl border border-line bg-panel/40 p-4">
          <h2 className="mb-3 text-sm font-semibold text-slate-100">Top screens</h2>
          <DataTable
            loading={summary.loading}
            error={summary.error}
            onRetry={summary.reload}
            rows={data?.topScreens ?? []}
            columns={screenCols}
            rowKey={(r) => r.screen}
            emptyTitle="No screen views yet"
          />
        </section>
        <section className="rounded-2xl border border-line bg-panel/40 p-4">
          <h2 className="mb-3 text-sm font-semibold text-slate-100">Top matches</h2>
          <DataTable
            loading={summary.loading}
            error={summary.error}
            onRetry={summary.reload}
            rows={data?.topMatches ?? []}
            columns={matchCols}
            rowKey={(r) => r.matchId}
            emptyTitle="No match opens yet"
          />
        </section>
        <section className="rounded-2xl border border-line bg-panel/40 p-4">
          <h2 className="mb-3 text-sm font-semibold text-slate-100">Quality selected breakdown</h2>
          <DataTable
            loading={summary.loading}
            error={summary.error}
            onRetry={summary.reload}
            rows={data?.topStreamQualities ?? []}
            columns={qualityCols}
            rowKey={(r) => r.quality}
            emptyTitle="No quality selections yet"
          />
        </section>
        <section className="rounded-2xl border border-line bg-panel/40 p-4">
          <h2 className="mb-3 text-sm font-semibold text-slate-100">App versions</h2>
          <DataTable
            loading={summary.loading}
            error={summary.error}
            onRetry={summary.reload}
            rows={data?.appVersions ?? []}
            columns={versionCols}
            rowKey={(r) => r.appVersion}
            emptyTitle="No devices yet"
          />
        </section>
        <section className="rounded-2xl border border-line bg-panel/40 p-4">
          <h2 className="mb-3 text-sm font-semibold text-slate-100">Platform breakdown</h2>
          <DataTable
            loading={summary.loading}
            error={summary.error}
            onRetry={summary.reload}
            rows={data?.platforms ?? []}
            columns={platformCols}
            rowKey={(r) => r.platform}
            emptyTitle="No devices yet"
          />
        </section>
      </div>
    </>
  );
}
