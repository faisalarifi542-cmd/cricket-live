'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { FlaskConical, Pencil, Plus, RefreshCw, Trash2, ToggleLeft, ToggleRight } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { Button } from '@/components/ui/Button';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { manualMatchesApi } from '@/lib/api';
import { useResource, usePermissions, useAuth } from '@/lib/hooks';

export default function ManualMatchesPage() {
  return (
    <AdminShell permission="matches.view">
      <ManualMatchesInner />
    </AdminShell>
  );
}

function ManualMatchesInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const { data, loading, error, reload } = useResource(() => manualMatchesApi.list(), []);

  const [editing, setEditing] = useState<Record<string, unknown> | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [toDelete, setToDelete] = useState<any>(null);

  const rows = useMemo(() => (data?.data || []) as any[], [data]);

  async function toggle(row: any) {
    try {
      await manualMatchesApi.toggle(row.id);
      toast.success(`Match ${row.is_enabled ? 'disabled' : 'enabled'}`);
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  }

  async function remove(row: any) {
    await manualMatchesApi.delete(row.id);
    toast.success('Manual match deleted');
    reload();
  }

  async function save(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const fd = new FormData(e.currentTarget);
    const body: Record<string, unknown> = {};
    fd.forEach((v, k) => {
      if (v !== '') body[k] = v;
    });
    if (editing?.id) {
      await manualMatchesApi.update(String(editing.id), body);
      toast.success('Updated');
    } else {
      await manualMatchesApi.create(body);
      toast.success('Created');
    }
    setShowForm(false);
    setEditing(null);
    reload();
  }

  const columns: Column<any>[] = [
    {
      id: 'matchId',
      header: 'Match ID',
      render: (r) => <span className="font-mono text-xs text-cyan-200">{r.match_external_id}</span>,
    },
    {
      id: 'title',
      header: 'Title',
      render: (r) => (
        <div>
          <div className="text-sm text-slate-200">{r.title}</div>
          <div className="text-xs text-slate-500">
            {r.team1_name} vs {r.team2_name}
          </div>
        </div>
      ),
    },
    {
      id: 'status',
      header: 'Status',
      render: (r) => (
        <span className="rounded-md bg-white/5 px-2 py-0.5 text-[10px] uppercase text-slate-300">
          {r.status}
        </span>
      ),
    },
    {
      id: 'enabled',
      header: 'Enabled',
      render: (r) => (
        <button
          onClick={() => toggle(r)}
          className="flex items-center gap-1 text-xs"
          disabled={!perms.can('matches.write')}
        >
          {r.is_enabled ? (
            <ToggleRight className="h-5 w-5 text-emerald-400" />
          ) : (
            <ToggleLeft className="h-5 w-5 text-slate-500" />
          )}
        </button>
      ),
    },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (r) => (
        <div className="flex items-center justify-end gap-1">
          {perms.can('matches.write') && (
            <>
              <Button
                size="sm"
                variant="secondary"
                onClick={() => {
                  setEditing(r);
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
        title="Manual Matches"
        description="Admin-controlled test matches that appear in the app alongside real provider matches."
        right={
          <>
            <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>
              Refresh
            </Button>
            {perms.can('matches.write') && (
              <Button
                icon={<Plus className="h-4 w-4" />}
                onClick={() => {
                  setEditing(null);
                  setShowForm(true);
                }}
              >
                Add match
              </Button>
            )}
          </>
        }
      />

      <DataTable
        loading={loading}
        error={error}
        onRetry={reload}
        rows={rows}
        columns={columns}
        rowKey={(r) => r.id}
        emptyTitle="No manual matches"
        emptyDescription="Create a manual match to test the app when no real live matches are available."
      />

      {showForm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm">
          <div className="w-full max-w-lg rounded-xl border border-white/10 bg-[#0b1220] p-6 shadow-2xl">
            <div className="mb-4 flex items-center gap-2 text-lg font-semibold text-slate-100">
              <FlaskConical className="h-5 w-5 text-cyan-300" />
              {editing ? 'Edit manual match' : 'New manual match'}
            </div>
            <form onSubmit={save} className="space-y-3">
              <Field name="match_external_id" label="Match External ID" defaultValue={String((editing as any)?.match_external_id || '')} required />
              <Field name="title" label="Title" defaultValue={String((editing as any)?.title || '')} />
              <div className="grid grid-cols-2 gap-3">
                <Field name="team1_name" label="Team 1 Name" defaultValue={String((editing as any)?.team1_name || '')} />
                <Field name="team2_name" label="Team 2 Name" defaultValue={String((editing as any)?.team2_name || '')} />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <Field name="team1_short" label="Team 1 Short" defaultValue={String((editing as any)?.team1_short || '')} />
                <Field name="team2_short" label="Team 2 Short" defaultValue={String((editing as any)?.team2_short || '')} />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <Field name="status" label="Status" defaultValue={String((editing as any)?.status || 'live')} />
                <Field name="match_state" label="Match State" defaultValue={String((editing as any)?.match_state || 'live')} />
              </div>
              <Field name="venue" label="Venue" defaultValue={String((editing as any)?.venue || '')} />
              <div className="grid grid-cols-2 gap-3">
                <Field name="sort_order" label="Sort Order" defaultValue={String(editing?.sort_order ?? 1)} type="number" />
                <label className="flex items-center gap-2 text-sm text-slate-300">
                  <input type="checkbox" name="is_enabled" defaultChecked={editing ? !!editing.is_enabled : true} className="h-4 w-4 rounded border-slate-600 bg-slate-800 text-cyan-500" />
                  Enabled
                </label>
              </div>
              <div className="mt-4 flex justify-end gap-2">
                <Button variant="ghost" onClick={() => setShowForm(false)}>
                  Cancel
                </Button>
                <Button type="submit" icon={<FlaskConical className="h-4 w-4" />}>
                  {editing ? 'Save changes' : 'Create match'}
                </Button>
              </div>
            </form>
          </div>
        </div>
      )}

      <ConfirmDialog
        open={!!toDelete}
        onClose={() => setToDelete(null)}
        onConfirm={() => {
          if (toDelete) return remove(toDelete);
          return undefined;
        }}
        title="Delete manual match"
        description="This will remove the match from the app. Streams linked to this match ID will remain in the Streams page."
        confirmLabel="Delete"
        destructive
      />
    </>
  );
}

function Field({ name, label, defaultValue = '', type = 'text', required }: { name: string; label: string; defaultValue?: string; type?: string; required?: boolean }) {
  return (
    <div>
      <label className="mb-1 block text-xs font-medium text-slate-400">{label}</label>
      <input
        name={name}
        type={type}
        defaultValue={defaultValue}
        required={required}
        className="w-full rounded-lg border border-white/10 bg-slate-900/50 px-3 py-2 text-sm text-slate-100 outline-none ring-cyan-500/30 transition focus:ring-2"
      />
    </div>
  );
}
