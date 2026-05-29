'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import {
  Activity,
  HeartPulse,
  Pencil,
  Plus,
  RefreshCw,
  Trash2,
  Wifi,
} from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { SearchInput } from '@/components/ui/SearchInput';
import { FilterBar } from '@/components/ui/FilterBar';
import { Button } from '@/components/ui/Button';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { Switch } from '@/components/ui/Switch';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { StreamForm, type StreamFormValue } from '@/components/forms/StreamForm';
import { streamsApi, type StreamRow } from '@/lib/api';
import { useDebouncedValue, usePermissions, useResource, useAuth } from '@/lib/hooks';
import { STREAM_QUALITIES, STREAM_TYPES } from '@/lib/constants';
import { formatRelative } from '@/lib/utils';

export default function StreamsPage() {
  return (
    <AdminShell permission="streams.view">
      <StreamsInner />
    </AdminShell>
  );
}

function StreamsInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const [q, setQ] = useState('');
  const debouncedQ = useDebouncedValue(q, 300);
  const [active, setActive] = useState<'all' | 'true' | 'false'>('all');
  const [quality, setQuality] = useState<string>('all');
  const [type, setType] = useState<string>('all');

  const { data, loading, error, reload } = useResource(
    () =>
      streamsApi.list({
        q: debouncedQ || undefined,
        is_active: active === 'all' ? undefined : active,
      }),
    [debouncedQ, active],
  );

  const [editing, setEditing] = useState<StreamFormValue | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [toDelete, setToDelete] = useState<StreamRow | null>(null);

  const rows = useMemo(() => {
    let list = (data?.data || []) as StreamRow[];
    if (quality !== 'all') list = list.filter((r) => r.quality === quality);
    if (type !== 'all') list = list.filter((r) => r.stream_type === type);
    return list;
  }, [data, quality, type]);

  async function toggle(row: StreamRow) {
    try {
      await streamsApi.toggle(row.id);
      toast.success(`Stream ${row.is_active ? 'disabled' : 'enabled'}`);
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  }

  async function test(row: StreamRow) {
    const t = toast.loading('Testing stream…');
    try {
      const res = await streamsApi.test(row.id);
      toast.dismiss(t);
      toast[res.status === 'working' ? 'success' : 'error'](
        `Stream test: ${res.status}${res.latency_ms != null ? ` (${res.latency_ms}ms)` : ''}`,
      );
      reload();
    } catch (err) {
      toast.dismiss(t);
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  }

  async function clearCache(row: StreamRow) {
    try {
      await streamsApi.cacheClear(row.id);
      toast.success('Stream cache cleared');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  }

  async function remove(row: StreamRow) {
    await streamsApi.delete(row.id);
    toast.success('Stream deleted');
    reload();
  }

  const columns: Column<StreamRow>[] = [
    {
      id: 'match',
      header: 'Match',
      render: (r) => (
        <div>
          <div className="font-mono text-xs text-cyan-200">{r.match_external_id}</div>
          {r.title && <div className="text-xs text-slate-500">{r.title}</div>}
        </div>
      ),
    },
    {
      id: 'server',
      header: 'Server',
      render: (r) => (
        <div className="text-sm">
          <div className="text-slate-200">{r.server_name || r.label || '—'}</div>
          {r.language && (
            <div className="text-[10px] uppercase tracking-wide text-slate-500">{r.language}</div>
          )}
        </div>
      ),
    },
    {
      id: 'type',
      header: 'Type',
      render: (r) => (
        <span className="rounded-md bg-white/5 px-2 py-0.5 text-[10px] uppercase text-slate-300">
          {r.stream_type}
        </span>
      ),
    },
    {
      id: 'quality',
      header: 'Quality',
      render: (r) => (
        <span className="rounded-md bg-cyan-300/10 px-2 py-0.5 text-[10px] text-cyan-200">
          {r.quality}
        </span>
      ),
    },
    {
      id: 'priority',
      header: 'Priority',
      render: (r) => <span className="text-slate-300">{r.priority ?? '—'}</span>,
    },
    {
      id: 'status',
      header: 'Status',
      render: (r) => <StatusBadge status={r.status || (r.is_active ? 'active' : 'inactive')} />,
    },
    {
      id: 'flags',
      header: 'Flags',
      render: (r) => (
        <div className="flex flex-wrap items-center gap-1">
          {r.is_premium && <StatusBadge tone="info">PREMIUM</StatusBadge>}
          {r.drm_enabled && <StatusBadge tone="warning">DRM</StatusBadge>}
        </div>
      ),
    },
    {
      id: 'updated',
      header: 'Updated',
      render: (r) => (
        <span className="text-xs text-slate-500">
          {formatRelative(r.updated_at || r.created_at)}
        </span>
      ),
    },
    {
      id: 'active',
      header: 'Active',
      render: (r) => (
        <Switch
          checked={!!r.is_active}
          onChange={() => toggle(r)}
          disabled={!perms.can('streams.write')}
        />
      ),
    },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (r) => (
        <div className="flex items-center justify-end gap-1">
          {perms.can('streams.test') && (
            <Button
              size="sm"
              variant="ghost"
              onClick={() => test(r)}
              icon={<HeartPulse className="h-3.5 w-3.5" />}
            >
              Test
            </Button>
          )}
          {perms.can('streams.write') && (
            <>
              <Button
                size="sm"
                variant="ghost"
                onClick={() => clearCache(r)}
                icon={<Activity className="h-3.5 w-3.5" />}
              >
                Cache
              </Button>
              <Button
                size="sm"
                variant="secondary"
                onClick={() => {
                  setEditing(r as unknown as StreamFormValue);
                  setShowForm(true);
                }}
                icon={<Pencil className="h-3.5 w-3.5" />}
              >
                Edit
              </Button>
              <Button
                size="sm"
                variant="danger"
                onClick={() => setToDelete(r)}
                icon={<Trash2 className="h-3.5 w-3.5" />}
              />
            </>
          )}
        </div>
      ),
    },
  ];

  return (
    <>
      <PageHeader
        title="Live streams"
        description="Manage every live stream URL — quality, server priority, type (HLS/DASH/iframe/external), DRM, premium gating, and health checks."
        right={
          <>
            <Button
              variant="secondary"
              icon={<RefreshCw className="h-4 w-4" />}
              onClick={reload}
              loading={loading}
            >
              Refresh
            </Button>
            {perms.can('streams.write') && (
              <Button
                icon={<Plus className="h-4 w-4" />}
                onClick={() => {
                  setEditing(null);
                  setShowForm(true);
                }}
              >
                Add stream
              </Button>
            )}
          </>
        }
      />

      <SearchInput
        value={q}
        onChange={setQ}
        placeholder="Search by title, server, or notes…"
        className="mb-3 max-w-md"
      />

      <FilterBar
        filters={[
          {
            type: 'select',
            id: 'active',
            label: 'State',
            value: active,
            options: [
              { id: 'all', label: 'All' },
              { id: 'true', label: 'Active' },
              { id: 'false', label: 'Inactive' },
            ],
            onChange: (v) => setActive(v as 'all' | 'true' | 'false'),
          },
          {
            type: 'select',
            id: 'quality',
            label: 'Quality',
            value: quality,
            options: [{ id: 'all', label: 'All' }, ...STREAM_QUALITIES.map((q) => ({ id: q, label: q }))],
            onChange: setQuality,
          },
          {
            type: 'select',
            id: 'type',
            label: 'Type',
            value: type,
            options: [{ id: 'all', label: 'All' }, ...STREAM_TYPES.map((t) => ({ id: t, label: t.toUpperCase() }))],
            onChange: setType,
          },
        ]}
        right={
          <div className="flex items-center gap-2 text-xs text-slate-400">
            <Wifi className="h-3.5 w-3.5 text-cyan-300" />
            <span>
              {rows.length} stream{rows.length === 1 ? '' : 's'}
            </span>
          </div>
        }
      />

      <DataTable
        loading={loading}
        error={error}
        onRetry={reload}
        rows={rows}
        columns={columns}
        rowKey={(r) => r.id}
        emptyTitle="No streams found"
        emptyDescription="Add a stream for an upcoming or live match to make it playable."
      />

      <StreamForm
        open={showForm}
        onClose={() => setShowForm(false)}
        initial={editing}
        onSaved={reload}
      />

      <ConfirmDialog
        open={!!toDelete}
        onClose={() => setToDelete(null)}
        onConfirm={() => {
          if (toDelete) return remove(toDelete);
          return undefined;
        }}
        title="Delete stream"
        description="This will permanently remove the stream URL and its health history. This action cannot be undone."
        confirmLabel="Delete"
        destructive
      />
    </>
  );
}
