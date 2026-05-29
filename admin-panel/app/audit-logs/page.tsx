'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Download, RefreshCw } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { SearchInput } from '@/components/ui/SearchInput';
import { FilterBar } from '@/components/ui/FilterBar';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { auditApi } from '@/lib/api';
import { useDebouncedValue, useResource } from '@/lib/hooks';
import { downloadFile, formatDateTime, safeJsonStringify, toCsv } from '@/lib/utils';

type AuditRow = {
  id: number;
  admin_email?: string;
  action: string;
  entity_type?: string;
  entity_id?: string;
  old_value?: unknown;
  new_value?: unknown;
  ip_address?: string;
  user_agent?: string;
  created_at: string;
};

export default function AuditLogsPage() {
  return (
    <AdminShell permission="audit.view">
      <Inner />
    </AdminShell>
  );
}

function Inner() {
  const [q, setQ] = useState('');
  const debouncedQ = useDebouncedValue(q, 250);
  const [action, setAction] = useState('all');
  const [entity, setEntity] = useState('all');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [detail, setDetail] = useState<AuditRow | null>(null);

  const { data, loading, error, reload } = useResource(
    () =>
      auditApi.list({
        q: debouncedQ || undefined,
        action: action === 'all' ? undefined : action,
        entity_type: entity === 'all' ? undefined : entity,
        from: from || undefined,
        to: to || undefined,
      }),
    [debouncedQ, action, entity, from, to],
  );

  const rows = useMemo(() => (data?.data || []) as AuditRow[], [data]);

  const actions = useMemo(() => Array.from(new Set(rows.map((r) => r.action))).sort(), [rows]);
  const entities = useMemo(() => Array.from(new Set(rows.map((r) => r.entity_type).filter(Boolean))) as string[], [rows]);

  function exportCsv() {
    const csv = toCsv(
      rows.map((r) => ({
        id: r.id,
        admin: r.admin_email ?? '',
        action: r.action,
        entity_type: r.entity_type ?? '',
        entity_id: r.entity_id ?? '',
        ip: r.ip_address ?? '',
        when: r.created_at,
        old_value: safeJsonStringify(r.old_value),
        new_value: safeJsonStringify(r.new_value),
      })),
    );
    downloadFile(`audit-${Date.now()}.csv`, csv, 'text/csv');
    toast.success('CSV downloaded');
  }

  const columns: Column<AuditRow>[] = [
    { id: 'when', header: 'When', render: (r) => formatDateTime(r.created_at) },
    { id: 'admin', header: 'Admin', render: (r) => r.admin_email ?? '—' },
    { id: 'action', header: 'Action', render: (r) => <code className="font-mono text-xs text-cyan-200">{r.action}</code> },
    { id: 'entity', header: 'Entity', render: (r) => `${r.entity_type ?? '—'} ${r.entity_id ? `#${r.entity_id}` : ''}` },
    { id: 'ip', header: 'IP', render: (r) => <span className="font-mono text-[11px] text-slate-400">{r.ip_address ?? '—'}</span> },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (r) => <Button size="sm" variant="ghost" onClick={() => setDetail(r)}>Open</Button>,
    },
  ];

  return (
    <>
      <PageHeader
        title="Audit logs"
        description="Every write action is logged with old/new values. Filter, search, and export to CSV for compliance review."
        right={
          <>
            <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>Refresh</Button>
            <Button variant="secondary" icon={<Download className="h-4 w-4" />} onClick={exportCsv}>Export CSV</Button>
          </>
        }
      />
      <SearchInput value={q} onChange={setQ} placeholder="Search by admin email, entity id, or action…" className="mb-3 max-w-md" />
      <FilterBar
        filters={[
          {
            type: 'select',
            id: 'action',
            label: 'Action',
            value: action,
            options: [{ id: 'all', label: 'All' }, ...actions.map((a) => ({ id: a, label: a }))],
            onChange: setAction,
          },
          {
            type: 'select',
            id: 'entity',
            label: 'Entity',
            value: entity,
            options: [{ id: 'all', label: 'All' }, ...entities.map((e) => ({ id: e, label: e }))],
            onChange: setEntity,
          },
        ]}
        right={
          <div className="flex items-center gap-2">
            <input
              type="date"
              value={from}
              onChange={(e) => setFrom(e.target.value)}
              className="h-9 rounded-lg border border-line bg-white/5 px-3 text-sm text-slate-100"
            />
            <span className="text-xs text-slate-500">to</span>
            <input
              type="date"
              value={to}
              onChange={(e) => setTo(e.target.value)}
              className="h-9 rounded-lg border border-line bg-white/5 px-3 text-sm text-slate-100"
            />
          </div>
        }
      />
      <DataTable loading={loading} error={error} onRetry={reload} rows={rows} columns={columns} rowKey={(r) => r.id} emptyTitle="No audit entries" />

      <Modal
        open={!!detail}
        onClose={() => setDetail(null)}
        title={detail ? `${detail.action} · ${detail.entity_type ?? ''} ${detail.entity_id ?? ''}` : ''}
        size="xl"
        footer={<Button onClick={() => setDetail(null)}>Close</Button>}
      >
        {detail && (
          <div className="grid gap-4 md:grid-cols-2">
            <div>
              <div className="mb-1 text-[10px] uppercase tracking-wide text-slate-500">Admin</div>
              <div className="text-sm text-slate-100">{detail.admin_email ?? '—'}</div>
            </div>
            <div>
              <div className="mb-1 text-[10px] uppercase tracking-wide text-slate-500">When</div>
              <div className="text-sm text-slate-100">{formatDateTime(detail.created_at)}</div>
            </div>
            <div>
              <div className="mb-1 text-[10px] uppercase tracking-wide text-slate-500">IP</div>
              <div className="font-mono text-xs text-slate-300">{detail.ip_address ?? '—'}</div>
            </div>
            <div className="md:col-span-2">
              <div className="mb-1 text-[10px] uppercase tracking-wide text-slate-500">User agent</div>
              <div className="break-all text-xs text-slate-300">{detail.user_agent ?? '—'}</div>
            </div>
            <div className="md:col-span-2">
              <div className="mb-1 text-[10px] uppercase tracking-wide text-slate-500">Old value</div>
              <pre className="max-h-64 overflow-auto rounded-lg border border-line bg-black/40 p-3 font-mono text-[11px] text-slate-200">{safeJsonStringify(detail.old_value)}</pre>
            </div>
            <div className="md:col-span-2">
              <div className="mb-1 text-[10px] uppercase tracking-wide text-slate-500">New value</div>
              <pre className="max-h-64 overflow-auto rounded-lg border border-line bg-black/40 p-3 font-mono text-[11px] text-slate-200">{safeJsonStringify(detail.new_value)}</pre>
            </div>
          </div>
        )}
      </Modal>
    </>
  );
}
