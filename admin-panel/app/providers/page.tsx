'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import {
  Activity,
  ArrowDown,
  ArrowUp,
  ChevronDown,
  ChevronUp,
  KeyRound,
  Pencil,
  Plus,
  RefreshCw,
  Star,
  Trash2,
} from 'lucide-react';
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
import type { Provider, ProviderCapabilities } from '@/types/provider';

function roleBadge(role?: string | null) {
  const r = String(role || 'fallback').toLowerCase();
  if (r === 'primary') return { label: 'Primary', color: 'bg-cyan-500/15 text-cyan-300 border-cyan-500/30' } as const;
  return { label: 'Fallback', color: 'bg-slate-500/15 text-slate-400 border-slate-500/30' } as const;
}

function healthVariant(status?: string): 'up' | 'down' | 'limited' | 'disabled' | 'misconfigured' {
  const s = String(status || 'unknown').toLowerCase();
  if (s === 'healthy' || s === 'up') return 'up';
  if (s === 'limited') return 'limited';
  if (s === 'down') return 'down';
  if (s === 'disabled') return 'disabled';
  if (s === 'misconfigured') return 'misconfigured';
  return 'down';
}

function capsSummary(caps?: ProviderCapabilities | null): string {
  if (!caps || !Object.keys(caps).length) return '—';
  const full = Object.entries(caps).filter(([, v]) => v === 'full').length;
  const limited = Object.entries(caps).filter(([, v]) => v === 'limited').length;
  const unsupported = Object.entries(caps).filter(([, v]) => v === 'unsupported').length;
  const parts: string[] = [];
  if (full) parts.push(`${full} full`);
  if (limited) parts.push(`${limited} limited`);
  if (unsupported) parts.push(`${unsupported} unsupported`);
  return parts.join(', ');
}

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
  const [expandedCap, setExpandedCap] = useState<number | null>(null);

  async function toggle(p: Provider) {
    try {
      await providersApi.toggle(p.id);
      toast.success(`Provider ${p.is_active ? 'disabled' : 'enabled'}`);
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  }
  async function test(p: Provider) {
    const t = toast.loading('Testing provider…');
    try {
      const res = await providersApi.test(p.id);
      toast.dismiss(t);
      const good = res.status === 'healthy' || res.status === 'up' || res.status === 'limited';
      const note = (res as { capability_note?: string }).capability_note;
      const label = note
        ? `Provider ${p.name}: ${res.status} — ${note}`
        : `Provider ${p.name}: ${res.status}`;
      toast[good ? 'success' : 'error'](label);
      reload();
    } catch (err) {
      toast.dismiss(t);
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  }
  async function reset(p: Provider) {
    try {
      await providersApi.reset(p.id);
      toast.success('Provider health reset');
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  }
  async function setPrimary(p: Provider) {
    try {
      await providersApi.setPrimary(p.id);
      toast.success(`${p.name} is now the primary provider`);
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  }
  async function resetHealth(p: Provider) {
    try {
      await providersApi.resetHealth(p.id);
      toast.success(`${p.name} in-memory health reset`);
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  }
  async function refreshAllHealth() {
    const t = toast.loading('Refreshing all provider health…');
    try {
      const res = await providersApi.refreshHealth();
      toast.dismiss(t);
      toast.success(`Health refreshed for ${res.data?.length ?? 0} providers`);
      reload();
    } catch (err) {
      toast.dismiss(t);
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  }
  async function movePriority(p: Provider, direction: 'up' | 'down') {
    const index = providers.findIndex((r) => r.id === p.id);
    if (index < 0) return;
    const swapIndex = direction === 'up' ? index - 1 : index + 1;
    if (swapIndex < 0 || swapIndex >= providers.length) return;
    const rows = [...providers];
    [rows[index], rows[swapIndex]] = [rows[swapIndex], rows[index]];
    // Re-number the whole chain rather than swapping two priority VALUES: a
    // value swap is a no-op when both rows share a priority, and new providers
    // all default to 100.
    const order = rows.map((r, i) => ({ id: r.id, priority: (i + 1) * 10 }));
    try {
      await providersApi.reorder(order);
      toast.success('Provider order updated');
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  }

  const columns: Column<Provider>[] = [
    {
      id: 'name',
      header: 'Provider',
      render: (p) => (
        <div>
          <div className="flex items-center gap-2">
            <span className="font-medium text-slate-100">{p.name}</span>
            <span
              className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider ${roleBadge(p.role || p.metadata?.role).color}`}
            >
              {roleBadge(p.role || p.metadata?.role).label}
            </span>
          </div>
          <div className="font-mono text-[10px] uppercase tracking-wide text-slate-500">
            {p.slug} · {p.provider_type || 'custom'} · priority {p.priority}
          </div>
        </div>
      ),
    },
    {
      id: 'capabilities',
      header: 'Capabilities',
      render: (p) => (
        <div>
          <button
            type="button"
            className="text-xs text-slate-400 hover:text-slate-200 flex items-center gap-1"
            onClick={() => setExpandedCap(expandedCap === p.id ? null : p.id)}
          >
            {capsSummary(p.capabilities)}
            {expandedCap === p.id ? (
              <ChevronUp className="h-3 w-3" />
            ) : (
              <ChevronDown className="h-3 w-3" />
            )}
          </button>
          {expandedCap === p.id && p.capabilities && (
            <div className="mt-1 grid grid-cols-2 gap-x-3 gap-y-0.5 text-[10px]">
              {Object.entries(p.capabilities).map(([method, level]) => (
                <div key={method} className="flex items-center gap-1">
                  <span
                    className={
                      level === 'full'
                        ? 'text-emerald-400'
                        : level === 'limited'
                        ? 'text-amber-400'
                        : 'text-slate-600'
                    }
                  >
                    {level === 'full' ? '●' : level === 'limited' ? '◐' : '○'}
                  </span>
                  <span className={level === 'unsupported' ? 'text-slate-600' : 'text-slate-400'}>
                    {method}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      ),
    },
    {
      id: 'health',
      header: 'Health',
      render: (p) => (
        <div className="flex flex-col gap-1">
          <StatusBadge status={healthVariant(p.live_health_state || p.health_status)} />
          {p.config_reason && (
            <span className="text-[10px] text-amber-400">{p.config_reason}</span>
          )}
        </div>
      ),
    },
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
              <Button
                size="sm"
                variant="ghost"
                icon={<ArrowUp className="h-3.5 w-3.5" />}
                onClick={() => movePriority(p, 'up')}
                title="Move up"
              />
              <Button
                size="sm"
                variant="ghost"
                icon={<ArrowDown className="h-3.5 w-3.5" />}
                onClick={() => movePriority(p, 'down')}
                title="Move down"
              />
              <Button
                size="sm"
                variant="ghost"
                icon={<Star className="h-3.5 w-3.5" />}
                onClick={() => setPrimary(p)}
                title="Make default (primary)"
              >
                Default
              </Button>
              <Button
                size="sm"
                variant="ghost"
                icon={<Activity className="h-3.5 w-3.5" />}
                onClick={() => test(p)}
              >
                Test
              </Button>
              <Button
                size="sm"
                variant="ghost"
                icon={<RefreshCw className="h-3.5 w-3.5" />}
                onClick={() => resetHealth(p)}
              >
                Health
              </Button>
              <Button
                size="sm"
                variant="ghost"
                icon={<KeyRound className="h-3.5 w-3.5" />}
                onClick={() => setKeysFor(p)}
              >
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
            <Button
              variant="secondary"
              icon={<RefreshCw className="h-4 w-4" />}
              onClick={reload}
              loading={loading}
            >
              Refresh
            </Button>
            {perms.can('providers.write') && (
              <Button
                variant="secondary"
                icon={<RefreshCw className="h-4 w-4" />}
                onClick={refreshAllHealth}
              >
                Refresh health
              </Button>
            )}
            {perms.can('providers.write') && (
              <Button
                variant="secondary"
                icon={<Activity className="h-4 w-4" />}
                onClick={() => setShowTestFetch(true)}
              >
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
        key={showForm ? editing?.id ?? 'new' : 'closed'}
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

      <ProviderKeysDialog
        provider={keysFor}
        onClose={() => setKeysFor(null)}
        canWrite={perms.can('providers.write')}
      />

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
  const [toRevoke, setToRevoke] = useState<{ id: number; label: string } | null>(
    null,
  );

  // The backend deliberately never returns key_value — only key metadata.
  const keys = (data?.data || []) as Array<{
    id: number;
    label: string;
    created_at?: string;
    notes?: string;
  }>;

  async function add() {
    if (!provider) return;
    if (!label.trim() || !keyValue.trim()) {
      toast.error('Label and API key are required');
      return;
    }
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
    <>
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
            <Input
              value={label}
              onChange={(e) => setLabel(e.target.value)}
              placeholder="Primary"
            />
          </Field>
          <Field label="API key">
            <Input
              value={keyValue}
              onChange={(e) => setKeyValue(e.target.value)}
              placeholder="sk_live_…"
            />
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
            <Button onClick={add} loading={submitting}>
              Add key
            </Button>
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
            <li
              key={k.id}
              className="flex items-center justify-between gap-3 rounded-lg border border-line bg-white/[0.03] px-3 py-2"
            >
              <div>
                <div className="font-medium text-slate-100">{k.label}</div>
                <div className="font-mono text-xs text-slate-400">••••••••</div>
                {k.notes && <div className="mt-1 text-xs text-slate-500">{k.notes}</div>}
              </div>
              {canWrite && (
                <Button
                  size="sm"
                  variant="danger"
                  onClick={() => setToRevoke({ id: k.id, label: k.label })}
                  icon={<Trash2 className="h-3.5 w-3.5" />}
                >
                  Revoke
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}
    </Modal>
    <ConfirmDialog
      open={!!toRevoke}
      onClose={() => setToRevoke(null)}
      onConfirm={async () => {
        if (toRevoke) await remove(toRevoke.id);
      }}
      title="Revoke key"
      description={`This permanently deletes the key "${toRevoke?.label ?? ''}". Anything still using it will stop working. This cannot be undone.`}
      destructive
      confirmLabel="Revoke key"
    />
    </>
  );
}

function ProviderTestFetchDialog({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
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
        kind === 'player'
          ? providersApi.testPlayer
          : kind === 'team'
          ? providersApi.testTeam
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
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault();
                run();
              }
            }}
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
            Answered by:{' '}
            <span className="text-cyan-300">{result.provider || 'unknown'}</span>
          </div>
          <pre className="max-h-80 overflow-auto rounded-xl border border-line bg-black/40 p-3 text-xs text-slate-200">
            {JSON.stringify(result.data, null, 2)}
          </pre>
        </div>
      )}
    </Modal>
  );
}
