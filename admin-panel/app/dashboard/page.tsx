'use client';

import {
  Activity,
  Bell,
  Database,
  DatabaseZap,
  HeartPulse,
  Radio,
  RefreshCw,
  ShieldAlert,
  Trophy,
} from 'lucide-react';
import { useMemo } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { StatCard } from '@/components/ui/StatCard';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { Button } from '@/components/ui/Button';
import { cacheApi, dashboardApi, healthApi } from '@/lib/api';
import { useAuth, usePermissions, useResource } from '@/lib/hooks';
import { formatNumber, formatRelative } from '@/lib/utils';

type ProviderHealth = Record<
  string,
  { name?: string; status?: string; successRate?: number; latencyMs?: number; lastErrorAt?: string } | string | number | null
>;
type DashboardData = {
  cards: {
    liveMatches?: number;
    upcomingMatches?: number;
    finishedMatches?: number;
    activeStreams?: number;
    brokenStreams?: number;
    redisKeys?: number;
    uptime?: number;
    maintenanceMode?: boolean;
  };
  providers?: ProviderHealth;
  recentActions?: Array<{
    action: string;
    admin_email: string;
    entity_type?: string;
    entity_id?: string;
    created_at: string;
  }>;
};

type HealthData = {
  api?: string;
  redis?: string;
  mysql?: string;
  websocket?: string;
  uptime?: number;
};

function formatUptime(secs?: number) {
  if (!secs) return '—';
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  return `${h}h ${m}m`;
}

export default function DashboardPage() {
  return (
    <AdminShell permission="dashboard.view">
      <DashboardInner />
    </AdminShell>
  );
}

function DashboardInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const dash = useResource(() => dashboardApi.get(), []);
  const health = useResource(() => healthApi.get(), []);

  const data = dash.data?.data as DashboardData | undefined;
  const healthData = health.data?.data as HealthData | undefined;
  const cards = data?.cards || {};

  async function refresh() {
    await Promise.all([dash.reload(), health.reload()]);
    toast.success('Dashboard refreshed');
  }

  const providersRows = useMemo(() => {
    const providers = data?.providers || {};
    return Object.entries(providers).map(([key, raw]) => {
      const value = (raw && typeof raw === 'object' ? raw : { status: String(raw ?? '') }) as {
        name?: string;
        status?: string;
        successRate?: number;
        latencyMs?: number;
        lastErrorAt?: string;
      };
      return {
        id: key,
        name: value.name || key,
        status: value.status || 'unknown',
        successRate: value.successRate,
        latencyMs: value.latencyMs,
        lastErrorAt: value.lastErrorAt,
      };
    });
  }, [data]);

  const providerCols: Column<(typeof providersRows)[number]>[] = [
    { id: 'name', header: 'Provider', render: (r) => <span className="font-medium text-slate-100">{r.name}</span> },
    { id: 'status', header: 'Status', render: (r) => <StatusBadge status={r.status} /> },
    {
      id: 'success',
      header: 'Success',
      render: (r) => (r.successRate != null ? `${Math.round(r.successRate * 100)}%` : '—'),
    },
    {
      id: 'latency',
      header: 'Latency',
      render: (r) => (r.latencyMs != null ? `${formatNumber(r.latencyMs)} ms` : '—'),
    },
    {
      id: 'lastError',
      header: 'Last error',
      render: (r) => (r.lastErrorAt ? formatRelative(r.lastErrorAt) : '—'),
    },
  ];

  type Action = NonNullable<DashboardData['recentActions']>[number];
  const actionCols: Column<Action>[] = [
    { id: 'action', header: 'Action', render: (r) => <span className="font-mono text-xs text-cyan-200">{r.action}</span> },
    { id: 'admin', header: 'Admin', render: (r) => r.admin_email },
    {
      id: 'target',
      header: 'Target',
      render: (r) => (
        <span className="text-xs text-slate-300">
          {r.entity_type || '—'}
          {r.entity_id ? `#${r.entity_id}` : ''}
        </span>
      ),
    },
    { id: 'when', header: 'When', render: (r) => formatRelative(r.created_at) },
  ];

  const quickActions = [
    { id: 'manage-streams', label: 'Manage streams', href: '/streams', permission: 'streams.view' },
    { id: 'cache-flush', label: 'Cache console', href: '/cache', permission: 'cache.view' },
    { id: 'home', label: 'Home content', href: '/homepage', permission: 'home.view' },
    { id: 'settings', label: 'App settings', href: '/settings', permission: 'settings.view' },
  ].filter((a) => perms.can(a.permission));

  return (
    <>
      <PageHeader
        title={`Welcome back, ${user?.name || 'Admin'}`}
        description="Premium operations overview for live matches, streams, providers, cache, health, notifications, ads, and maintenance mode."
        right={
          <>
            <Button
              variant="secondary"
              icon={<RefreshCw className="h-4 w-4" />}
              onClick={refresh}
              loading={dash.loading || health.loading}
            >
              Refresh
            </Button>
            {perms.can('cache.write') && (
              <Button
                icon={<DatabaseZap className="h-4 w-4" />}
                onClick={async () => {
                  try {
                    await cacheApi.warmHome();
                    toast.success('Home cache warmed');
                  } catch (err) {
                    toast.error(err instanceof Error ? err.message : 'Failed');
                  }
                }}
              >
                Warm home cache
              </Button>
            )}
          </>
        }
      />

      <div className="mb-6 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
        <StatCard label="Live matches" value={formatNumber(cards.liveMatches ?? 0)} icon={Trophy} />
        <StatCard label="Active streams" value={formatNumber(cards.activeStreams ?? 0)} icon={Radio} tone="positive" />
        <StatCard
          label="Broken streams"
          value={formatNumber(cards.brokenStreams ?? 0)}
          icon={Activity}
          tone={(cards.brokenStreams ?? 0) > 0 ? 'danger' : 'default'}
        />
        <StatCard label="Redis keys" value={formatNumber(cards.redisKeys ?? 0)} icon={DatabaseZap} />
        <StatCard label="Upcoming" value={formatNumber(cards.upcomingMatches ?? 0)} icon={Trophy} />
        <StatCard label="Finished" value={formatNumber(cards.finishedMatches ?? 0)} icon={Database} />
        <StatCard label="Uptime" value={formatUptime(cards.uptime)} icon={HeartPulse} hint={`Node ${healthData?.api ?? 'ok'}`} />
        <StatCard
          label="Maintenance mode"
          value={cards.maintenanceMode ? 'ENABLED' : 'OFF'}
          icon={ShieldAlert}
          tone={cards.maintenanceMode ? 'warning' : 'default'}
        />
      </div>

      <div className="mb-6 grid gap-3 md:grid-cols-4">
        <StatCard label="Redis" value={String(healthData?.redis ?? 'unknown')} tone={healthData?.redis === 'ready' ? 'positive' : 'warning'} />
        <StatCard label="MySQL" value={String(healthData?.mysql ?? 'unknown')} tone={healthData?.mysql === 'ok' ? 'positive' : 'warning'} />
        <StatCard label="WebSocket" value={String(healthData?.websocket ?? 'unknown')} tone="positive" />
        <StatCard label="Notifications sent" value={0} icon={Bell} hint="Lifetime push events" />
      </div>

      {quickActions.length > 0 && (
        <div className="mb-6 grid gap-3 md:grid-cols-4">
          {quickActions.map((action) => (
            <Link
              key={action.id}
              href={action.href}
              className="rounded-xl border border-line bg-white/[0.04] px-4 py-3 text-sm text-slate-200 transition hover:border-cyan-300/30 hover:bg-cyan-400/10"
            >
              {action.label} →
            </Link>
          ))}
        </div>
      )}

      <div className="grid gap-6 xl:grid-cols-2">
        <section className="rounded-2xl border border-line bg-panel/40 p-4">
          <h2 className="mb-3 text-sm font-semibold text-slate-100">Provider health</h2>
          <DataTable
            loading={dash.loading}
            error={dash.error}
            onRetry={dash.reload}
            rows={providersRows}
            columns={providerCols}
            rowKey={(r) => r.id}
            emptyTitle="No providers configured"
            emptyDescription="Add a provider in the Providers Manager."
          />
        </section>
        <section className="rounded-2xl border border-line bg-panel/40 p-4">
          <h2 className="mb-3 text-sm font-semibold text-slate-100">Recent admin actions</h2>
          <DataTable
            loading={dash.loading}
            error={dash.error}
            onRetry={dash.reload}
            rows={(data?.recentActions || []) as Action[]}
            columns={actionCols}
            rowKey={(r) => `${r.action}-${r.created_at}`}
            emptyTitle="No activity yet"
          />
        </section>
      </div>
    </>
  );
}
