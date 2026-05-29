'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Download, RefreshCw } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { StatCard } from '@/components/ui/StatCard';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { SearchInput } from '@/components/ui/SearchInput';
import { FilterBar } from '@/components/ui/FilterBar';
import { Button } from '@/components/ui/Button';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { healthApi } from '@/lib/api';
import { useDebouncedValue, useResource } from '@/lib/hooks';
import { downloadFile, formatDateTime, toCsv } from '@/lib/utils';

type LogRow = {
  id: number;
  level: string;
  message: string;
  endpoint?: string;
  provider?: string;
  match_id?: string;
  created_at: string;
};

export default function HealthPage() {
  return (
    <AdminShell permission="health.view">
      <HealthInner />
    </AdminShell>
  );
}

function HealthInner() {
  const health = useResource(() => healthApi.get(), []);
  const [q, setQ] = useState('');
  const debouncedQ = useDebouncedValue(q, 250);
  const [level, setLevel] = useState('all');
  const logs = useResource(
    () => healthApi.logs({ q: debouncedQ || undefined, level: level === 'all' ? undefined : level }),
    [debouncedQ, level],
  );

  const data = (health.data?.data || {}) as {
    api?: string;
    redis?: string;
    mysql?: string;
    websocket?: string;
    uptime?: number;
    memory?: { rss: number; heapUsed: number };
    providers?: Record<string, unknown>;
  };

  const rows = useMemo(() => (logs.data?.data || []) as LogRow[], [logs]);

  function exportCsv() {
    const csv = toCsv(rows as unknown as Record<string, unknown>[]);
    downloadFile(`system-logs-${Date.now()}.csv`, csv, 'text/csv');
    toast.success('CSV downloaded');
  }

  const columns: Column<LogRow>[] = [
    { id: 'level', header: 'Level', render: (r) => <StatusBadge status={r.level} /> },
    { id: 'message', header: 'Message', render: (r) => <span className="font-mono text-xs">{r.message}</span> },
    { id: 'endpoint', header: 'Endpoint', render: (r) => <span className="text-xs text-slate-400">{r.endpoint || '—'}</span> },
    { id: 'provider', header: 'Provider', render: (r) => r.provider || '—' },
    { id: 'when', header: 'When', render: (r) => formatDateTime(r.created_at) },
  ];

  return (
    <>
      <PageHeader
        title="Health & logs"
        description="API, Redis, MySQL, WebSocket, and provider health plus searchable system logs with CSV export."
        right={
          <Button
            variant="secondary"
            icon={<RefreshCw className="h-4 w-4" />}
            onClick={() => {
              health.reload();
              logs.reload();
            }}
            loading={health.loading || logs.loading}
          >
            Refresh
          </Button>
        }
      />

      <div className="mb-6 grid gap-3 md:grid-cols-4">
        <StatCard label="API" value={data.api || 'unknown'} tone={data.api === 'ok' ? 'positive' : 'warning'} />
        <StatCard label="Redis" value={data.redis || 'unknown'} tone={data.redis === 'ready' ? 'positive' : 'warning'} />
        <StatCard label="MySQL" value={data.mysql || 'unknown'} tone={data.mysql === 'ok' ? 'positive' : 'warning'} />
        <StatCard label="WebSocket" value={data.websocket || 'unknown'} tone="positive" />
        <StatCard label="Uptime (s)" value={Math.round(data.uptime ?? 0)} />
        <StatCard label="RSS (MB)" value={Math.round((data.memory?.rss ?? 0) / 1024 / 1024)} />
        <StatCard label="Heap (MB)" value={Math.round((data.memory?.heapUsed ?? 0) / 1024 / 1024)} />
        <StatCard label="Providers" value={Object.keys(data.providers || {}).length} />
      </div>

      <div className="mb-3 flex flex-wrap items-center gap-3">
        <SearchInput value={q} onChange={setQ} placeholder="Search logs by message, endpoint, provider…" className="max-w-md flex-1" />
        <Button variant="secondary" icon={<Download className="h-4 w-4" />} onClick={exportCsv}>
          Export CSV
        </Button>
      </div>

      <FilterBar
        filters={[
          {
            type: 'select',
            id: 'level',
            label: 'Level',
            value: level,
            options: [
              { id: 'all', label: 'All' },
              { id: 'info', label: 'Info' },
              { id: 'warn', label: 'Warning' },
              { id: 'error', label: 'Error' },
            ],
            onChange: setLevel,
          },
        ]}
      />

      <DataTable loading={logs.loading} rows={rows} columns={columns} rowKey={(r) => r.id} emptyTitle="No log entries" />
    </>
  );
}
