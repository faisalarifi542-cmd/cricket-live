'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Activity, KeyRound, Pencil, Plus, RefreshCw, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { Button } from '@/components/ui/Button';
import { Switch } from '@/components/ui/Switch';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { Modal } from '@/components/ui/Modal';
import { Field, Input, Textarea } from '@/components/ui/Input';
import { ProviderForm } from '@/components/forms/ProviderForm';
import { providersApi } from '@/lib/api';
import { useAuth, usePermissions, useResource } from '@/lib/hooks';
import { maskKey } from '@/lib/utils';

type Provider = {
  id: number;
  slug: string;
  name: string;
  base_url?: string;
  provider_type?: string;
  description?: string;
  is_active: boolean;
  priority: number;
  timeout_ms?: number;
  rate_limit_per_minute?: number;
  health_status?: string;
  last_error?: string;
  last_success_at?: string;
  last_failure_at?: string;
  metadata?: { role?: string } | null;
};

export default function ProvidersPage() {
  return (
    <AdminShell permission="providers.view">
      <ProvidersInner />
    </AdminShell>
  );
}

function ProvidersInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const { data, loading, error, reload } = useResource(() => providersApi.list(), []);
  const providers = (data?.data || []) as Provider[];

  const [editing, setEditing] = useState<Provider | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [toDelete, setToDelete] = useState<Provider | null>(null);
  const [keysFor, setKeysFor] = useState<Provider | null>(null);
  const [showTestFetch, setShowTestFetch] = useState(false);

  async function toggle(p: Provider) {
    await providersApi.toggle(p.id);
    toast.success(`Provider ${p.is_active ? 'disabled' : 'enabled'}`);
    reload();
  }
  async function test(p: Provider) {
    const t = toast.loading('Testing provider…');
    try {
      const res = await providersApi.test(p.id);
      toast.dismiss(t);
      toast[res.status === 'healthy' ? 'success' : 'error'](`Provider ${p.name}: ${res.status}`);
      reload();
    } catch (err) {
      toast.dismiss(t);
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  }
  async function reset(p: Provider) {
    await providersApi.reset(p.id);
    toast.success('Provider health reset');
    reload();
  }

  const columns: Column<Provider>[] = [
    {
      id: 'name',
      header: 'Provider',
      render: (p) => (
        <div>
          <div className="font-medium text-slate-100">{p.name}</div>
          <div className="font-mono text-[10px] uppercase tracking-wide text-slate-500">
            {p.slug} · {p.provider_type || 'custom'} · {p.metadata?.role || 'provider'}
          </div>
        </div>
      ),
    },
    { id: 'base_url', header: 'Base URL', render: (p) => <span className="font-mono text-xs text-slate-400">{p.base_url || '—'}</span> },
    { id: 'priority', header: 'Priority', render: (p) => p.priority },
    { id: 'limits', header: 'Limits', render: (p) => <span className="text-xs text-slate-400">{p.timeout_ms || 8000}ms / {p.rate_limit_per_minute || 60} rpm</span> },
    { id: 'health', header: 'Health', render: (p) => <StatusBadge status={p.health_status || 'unknown'} /> },
    {
      id: 'active',
      header: 'Active',
      render: (p) => (
        <Switch
          checked={p.is_active}
          onChange={() => toggle(p)}
          disabled={!perms.can('providers.write')}
        />
      ),
    },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (p) => (
        <div className="flex items-center justify-end gap-1">
          {perms.can('providers.write') && (
            <>
              <Button size="sm" variant="ghost" icon={<Activity className="h-3.5 w-3.5" />} onClick={() => test(p)}>
                Test
              </Button>
              <Button size="sm" variant="ghost" icon={<RefreshCw className="h-3.5 w-3.5" />} onClick={() => reset(p)}>
                Reset
              </Button>
              <Button size="sm" variant="ghost" icon={<KeyRound className="h-3.5 w-3.5" />} onClick={() => setKeysFor(p)}>
                Keys
              </Button>
              <Button
                size="sm"
                variant="secondary"
                icon={<Pencil className="h-3.5 w-3.5" />}
                onClick={() => {
                  setEditing(p);
                  setShowForm(true);
                }}
              >
                Edit
              </Button>
              <Button
                size="sm"
                variant="danger"
                icon={<Trash2 className="h-3.5 w-3.5" />}
                onClick={() => setToDelete(p)}
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
        title="API providers"
        description="Configure cricket data providers, their priority, health, and private API keys. Private keys never leave the backend."
        right={
          <>
            <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>
              Refresh
            </Button>
            {perms.can('providers.write') && (
              <Button variant="secondary" icon={<Activity className="h-4 w-4" />} onClick={() => setShowTestFetch(true)}>
                Test data fetch
              </Button>
            )}
            {perms.can('providers.write') && (
              <Button
                icon={<Plus className="h-4 w-4" />}
                onClick={() => {
                  setEditing(null);
                  setShowForm(true);
                }}
              >
                Add provider
              </Button>
            )}
          </>
        }
      />

      <DataTable
        loading={loading}
        error={error}
        onRetry={reload}
        rows={providers}
        columns={columns}
        rowKey={(p) => p.id}
        emptyTitle="No providers configured"
        emptyDescription="Add a provider to start fetching cricket data."
      />

      <ProviderForm
        open={showForm}
        onClose={() => setShowForm(false)}
        initial={editing}
        onSaved={reload}
      />

      <ConfirmDialog
        open={!!toDelete}
        onClose={() => setToDelete(null)}
        onConfirm={async () => {
          if (toDelete) {
            await providersApi.delete(toDelete.id);
            toast.success('Provider deleted');
            reload();
          }
        }}
        title="Delete provider"
        description="This will remove the provider configuration and its API keys. Cached data is preserved."
        destructive
        confirmLabel="Delete provider"
      />

      <ProviderKeysDialog provider={keysFor} onClose={() => setKeysFor(null)} canWrite={perms.can('providers.write')} />

      <ProviderTestFetchDialog open={showTestFetch} onClose={() => setShowTestFetch(false)} />
    </>
  );
}

function ProviderKeysDialog({
  provider,
  onClose,
  canWrite,
}: {
  provider: Provider | null;
  onClose: () => void;
  canWrite: boolean;
}) {
  const { data, loading, error, reload } = useResource(
    () =>
      provider
        ? providersApi.listKeys(provider.id)
        : Promise.resolve({ success: true as const, data: [] }),
    [provider?.id],
  );
  const [label, setLabel] = useState('');
  const [keyValue, setKeyValue] = useState('');
  const [notes, setNotes] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const keys = (data?.data || []) as Array<{ id: number; label: string; key_value: string; created_at?: string; notes?: string }>;

  async function add() {
    if (!provider || !label || !keyValue) return;
    setSubmitting(true);
    try {
      await providersApi.addKey(provider.id, { label, key_value: keyValue, notes });
      toast.success('Key added');
      setLabel('');
      setKeyValue('');
      setNotes('');
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    } finally {
      setSubmitting(false);
    }
  }

  async function remove(id: number) {
    if (!provider) return;
    await providersApi.deleteKey(provider.id, id);
    toast.success('Key revoked');
    reload();
  }

  return (
    <Modal
      open={!!provider}
      onClose={onClose}
      title={`Keys · ${provider?.name ?? ''}`}
      description="Private provider keys. Stored only on the backend. Never exposed to public Flutter clients."
      size="lg"
    >
      {canWrite && (
        <div className="mb-4 grid gap-2 rounded-xl border border-line bg-white/[0.04] p-3 md:grid-cols-4">
          <Field label="Label">
            <Input value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Primary" />
          </Field>
          <Field label="API key">
            <Input value={keyValue} onChange={(e) => setKeyValue(e.target.value)} placeholder="sk_live_…" />
          </Field>
          <div className="md:col-span-2">
            <Field label="Notes">
              <Textarea
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                placeholder="Optional"
                rows={2}
              />
            </Field>
          </div>
          <div className="md:col-span-4 flex justify-end">
            <Button onClick={add} loading={submitting}>Add key</Button>
          </div>
        </div>
      )}
      {loading ? (
        <p className="text-xs text-slate-400">Loading…</p>
      ) : !keys.length ? (
        <p className="text-xs text-slate-500">No keys yet.</p>
      ) : (
        <ul className="space-y-2 text-sm">
          {keys.map((k) => (
            <li key={k.id} className="flex items-center justify-between gap-3 rounded-lg border border-line bg-white/[0.03] px-3 py-2">
              <div>
                <div className="font-medium text-slate-100">{k.label}</div>
                <div className="font-mono text-xs text-slate-400">{maskKey(k.key_value)}</div>
                {k.notes && <div className="mt-1 text-xs text-slate-500">{k.notes}</div>}
              </div>
              {canWrite && (
                <Button size="sm" variant="danger" onClick={() => remove(k.id)} icon={<Trash2 className="h-3.5 w-3.5" />}>
                  Revoke
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}
    </Modal>
  );
}

function ProviderTestFetchDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [kind, setKind] = useState<'player' | 'team' | 'match'>('player');
  const [id, setId] = useState('');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<{ provider?: string; data?: unknown } | null>(null);
  const [errMsg, setErrMsg] = useState<string | null>(null);

  async function run() {
    if (!id.trim()) {
      toast.error('Enter an ID to test');
      return;
    }
    setBusy(true);
    setResult(null);
    setErrMsg(null);
    try {
      const fn =
        kind === 'player' ? providersApi.testPlayer
        : kind === 'team' ? providersApi.testTeam
        : providersApi.testMatch;
      const res = await fn(id.trim());
      setResult({ provider: res.provider, data: res.data });
      toast.success(`Fetched via ${res.provider || 'provider'}`);
    } catch (err) {
      setErrMsg(err instanceof Error ? err.message : 'Provider fetch failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal
      open={open}
      onClose={busy ? () => {} : onClose}
      title="Test provider data fetch"
      description="Fetch a player, team, or match by ID through the configured provider priority + failover. Confirms keys, base URL, and connectivity end to end."
      size="lg"
    >
      <div className="grid gap-3 md:grid-cols-[160px_minmax(0,1fr)_auto] md:items-end">
        <Field label="Type">
          <select
            value={kind}
            onChange={(e) => setKind(e.target.value as 'player' | 'team' | 'match')}
            className="h-10 w-full rounded-xl border border-line bg-white/5 px-3 text-sm text-slate-100"
          >
            <option value="player">Player</option>
            <option value="team">Team</option>
            <option value="match">Match</option>
          </select>
        </Field>
        <Field label="Provider ID">
          <Input
            value={id}
            onChange={(e) => setId(e.target.value)}
            placeholder="Enter ID"
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); run(); } }}
          />
        </Field>
        <Button icon={<Activity className="h-4 w-4" />} loading={busy} onClick={run}>
          Fetch
        </Button>
      </div>

      {errMsg && (
        <div className="mt-4 rounded-xl border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-200">
          {errMsg}
        </div>
      )}
      {result && (
        <div className="mt-4">
          <div className="mb-2 text-xs uppercase tracking-wide text-slate-400">
            Answered by: <span className="text-cyan-300">{result.provider || 'unknown'}</span>
          </div>
          <pre className="max-h-80 overflow-auto rounded-xl border border-line bg-black/40 p-3 text-xs text-slate-200">
            {JSON.stringify(result.data, null, 2)}
          </pre>
        </div>
      )}
    </Modal>
  );
}
