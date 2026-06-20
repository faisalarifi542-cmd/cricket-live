'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import {
  Plus,
  RefreshCw,
  ShieldOff,
  Trash2,
  KeyRound,
  ShieldAlert,
  ShieldCheck,
  Copy,
} from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { Tabs } from '@/components/ui/Tabs';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { Button } from '@/components/ui/Button';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { Modal } from '@/components/ui/Modal';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { Switch } from '@/components/ui/Switch';
import { Field, Input, Select, Textarea } from '@/components/ui/Input';
import { apiSecurityApi } from '@/lib/api';
import { useAuth, usePermissions, useResource } from '@/lib/hooks';
import { formatDateTime, formatRelative } from '@/lib/utils';

const ENDPOINT_GROUPS = [
  'health', 'app_config', 'matches', 'match_details', 'commentary', 'scorecard',
  'series', 'players', 'teams', 'streams', 'news', 'rankings', 'schedule',
  'notifications_device_register', 'admin', 'default',
];
const CLIENT_TYPES = ['android', 'ios', 'web', 'server', 'admin'];
const BLOCK_TYPES = ['ip', 'cidr', 'origin', 'domain', 'user_agent', 'client'];

const TABS = [
  { id: 'dashboard', label: 'Dashboard' },
  { id: 'clients', label: 'API Clients' },
  { id: 'origins', label: 'Allowed Domains' },
  { id: 'rules', label: 'Endpoint Rules' },
  { id: 'blocklist', label: 'Blocklist' },
  { id: 'logs', label: 'Request Logs' },
];

export default function ApiSecurityPage() {
  return (
    <AdminShell permission="apiSecurity.view">
      <ApiSecurityInner />
    </AdminShell>
  );
}

function ApiSecurityInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const canWrite = perms.can('apiSecurity.write');
  const [tab, setTab] = useState('dashboard');

  return (
    <>
      <PageHeader
        title="API Security"
        description="Control who can access the public API: approved apps, websites, domains, keys, endpoint rules, rate limits, and blocklists. No public access is allowed without permission."
        right={<ModeControl canWrite={canWrite} />}
      />

      <Tabs tabs={TABS} value={tab} onChange={setTab} className="mb-5" />

      {tab === 'dashboard' && <DashboardTab />}
      {tab === 'clients' && <ClientsTab canWrite={canWrite} />}
      {tab === 'origins' && <OriginsTab canWrite={canWrite} />}
      {tab === 'rules' && <RulesTab canWrite={canWrite} />}
      {tab === 'blocklist' && <BlocklistTab canWrite={canWrite} />}
      {tab === 'logs' && <LogsTab />}
    </>
  );
}

// =====================================================
// Mode control (enforce | monitor | off)
// =====================================================
function ModeControl({ canWrite }: { canWrite: boolean }) {
  const { data, loading, reload } = useResource(() => apiSecurityApi.getMode(), []);
  const [saving, setSaving] = useState(false);
  const mode = data?.data.mode || 'enforce';

  const change = async (next: string) => {
    setSaving(true);
    try {
      await apiSecurityApi.setMode(next);
      toast.success(`Security mode set to ${next}`);
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to change mode');
    } finally {
      setSaving(false);
    }
  };

  const tone = mode === 'enforce' ? 'success' : mode === 'monitor' ? 'warning' : 'danger';
  const Icon = mode === 'enforce' ? ShieldCheck : ShieldAlert;

  return (
    <div className="flex items-center gap-2">
      <StatusBadge tone={tone as any} className="gap-1">
        <Icon className="h-3 w-3" /> {mode}
      </StatusBadge>
      <Select
        value={mode}
        disabled={!canWrite || saving || loading}
        onChange={(e) => change(e.target.value)}
        className="h-9 w-40"
      >
        <option value="enforce">Enforce (block)</option>
        <option value="monitor">Monitor (log only)</option>
        <option value="off">Off</option>
      </Select>
    </div>
  );
}

// =====================================================
// Dashboard tab
// =====================================================
function DashboardTab() {
  const { data, loading, error, reload } = useResource(() => apiSecurityApi.dashboard(), []);
  const d = data?.data;

  if (loading && !d) return <div className="text-sm text-slate-400">Loading security dashboard…</div>;
  if (error) return <div className="text-sm text-red-300">{error}</div>;

  const cards = [
    { label: 'Requests today', value: d?.totalRequestsToday ?? 0, tone: 'text-cyan-200' },
    { label: 'Blocked today', value: d?.blockedRequestsToday ?? 0, tone: 'text-red-300' },
    { label: 'Rate-limit hits', value: d?.rateLimitHitsToday ?? 0, tone: 'text-amber-200' },
    { label: 'Disabled-endpoint hits', value: d?.disabledEndpointHitsToday ?? 0, tone: 'text-amber-200' },
  ];

  return (
    <div className="space-y-5">
      <div className="flex justify-end">
        <Button variant="secondary" size="sm" icon={<RefreshCw className="h-3.5 w-3.5" />} onClick={reload}>
          Refresh
        </Button>
      </div>
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {cards.map((c) => (
          <div key={c.label} className="rounded-xl border border-line bg-panel/40 p-4">
            <div className="text-xs uppercase tracking-wide text-slate-500">{c.label}</div>
            <div className={`mt-1 text-2xl font-semibold ${c.tone}`}>{c.value}</div>
          </div>
        ))}
      </div>
      <div className="grid gap-4 lg:grid-cols-2">
        <MiniTable title="Top clients" rows={d?.topClients} cols={[['name', 'Client'], ['hits', 'Hits']]} fallback="No client traffic yet" />
        <MiniTable title="Top blocked IPs" rows={d?.topBlockedIps} cols={[['ip', 'IP'], ['hits', 'Blocks']]} fallback="No blocked IPs" />
        <MiniTable title="Top endpoints" rows={d?.topEndpoints} cols={[['endpoint_group', 'Group'], ['hits', 'Hits']]} fallback="No traffic yet" />
        <MiniTable title="Suspicious origins" rows={d?.suspiciousOrigins} cols={[['origin', 'Origin'], ['hits', 'Blocks']]} fallback="No suspicious origins" />
      </div>
    </div>
  );
}

function MiniTable({ title, rows, cols, fallback }: { title: string; rows?: any[]; cols: [string, string][]; fallback: string }) {
  return (
    <div className="rounded-xl border border-line bg-panel/40 p-4">
      <div className="mb-2 text-sm font-medium text-slate-200">{title}</div>
      {!rows?.length ? (
        <div className="text-xs text-slate-500">{fallback}</div>
      ) : (
        <table className="w-full text-sm">
          <tbody>
            {rows.map((r, i) => (
              <tr key={i} className="border-t border-line/50">
                <td className="py-1.5 text-slate-300">{r[cols[0][0]] ?? '—'}</td>
                <td className="py-1.5 text-right font-mono text-slate-200">{r[cols[1][0]] ?? 0}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

// =====================================================
// Clients tab
// =====================================================
function ClientsTab({ canWrite }: { canWrite: boolean }) {
  const { data, loading, error, reload } = useResource(() => apiSecurityApi.listClients(), []);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<any | null>(null);
  const [toRevoke, setToRevoke] = useState<any | null>(null);
  const [newKey, setNewKey] = useState<{ key: string; warning: string } | null>(null);
  const clients = data?.data || [];

  const regenerate = async (c: any) => {
    try {
      const res = await apiSecurityApi.regenerateClientKey(c.id);
      setNewKey({ key: res.api_key, warning: res.warning });
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  };

  const columns: Column<any>[] = [
    {
      id: 'name',
      header: 'Client',
      render: (c) => (
        <div>
          <div className="font-medium text-slate-100">{c.name}</div>
          <div className="text-xs text-slate-500">{c.notes || '—'}</div>
        </div>
      ),
    },
    { id: 'type', header: 'Type', render: (c) => <span className="rounded-md bg-white/5 px-2 py-0.5 text-[10px] uppercase">{c.client_type}</span> },
    { id: 'key', header: 'Key', render: (c) => <code className="font-mono text-xs text-cyan-200">{c.api_key_masked}</code> },
    { id: 'rate', header: 'Rate/min', render: (c) => c.rate_limit_per_minute ?? '—' },
    { id: 'scopes', header: 'Scopes', render: (c) => <span className="text-xs text-slate-400">{(c.scopes || []).length || 'all'}</span> },
    { id: 'last', header: 'Last used', render: (c) => (c.last_used_at ? formatRelative(c.last_used_at) : '—') },
    { id: 'status', header: 'Status', render: (c) => <StatusBadge status={c.status} /> },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (c) =>
        canWrite ? (
          <div className="flex items-center justify-end gap-1">
            <Button size="sm" variant="ghost" onClick={() => { setEditing(c); setShowForm(true); }}>Edit</Button>
            <Button size="sm" variant="ghost" icon={<KeyRound className="h-3.5 w-3.5" />} onClick={() => regenerate(c)}>Regen</Button>
            {c.status !== 'revoked' && (
              <Button size="sm" variant="ghost" icon={<ShieldOff className="h-3.5 w-3.5" />} onClick={() => setToRevoke(c)}>Revoke</Button>
            )}
          </div>
        ) : null,
    },
  ];

  return (
    <>
      <div className="mb-3 flex justify-end gap-2">
        <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>Refresh</Button>
        {canWrite && <Button icon={<Plus className="h-4 w-4" />} onClick={() => { setEditing(null); setShowForm(true); }}>New client</Button>}
      </div>

      <DataTable
        loading={loading}
        error={error}
        onRetry={reload}
        rows={clients}
        columns={columns}
        rowKey={(c) => c.id}
        emptyTitle="No API clients"
        emptyDescription="Create an API client to issue a key for an app or website."
      />

      <ClientForm
        open={showForm}
        client={editing}
        onClose={() => setShowForm(false)}
        onSaved={reload}
        onCreatedKey={(key, warning) => setNewKey({ key, warning })}
      />

      <ShowKeyModal data={newKey} onClose={() => setNewKey(null)} />

      <ConfirmDialog
        open={!!toRevoke}
        onClose={() => setToRevoke(null)}
        onConfirm={async () => {
          if (toRevoke) {
            await apiSecurityApi.revokeClient(toRevoke.id);
            toast.success('Client revoked');
            reload();
          }
        }}
        title="Revoke client"
        description="The client's key stops working immediately."
        confirmLabel="Revoke"
        destructive
      />
    </>
  );
}

function ShowKeyModal({ data, onClose }: { data: { key: string; warning: string } | null; onClose: () => void }) {
  return (
    <Modal open={!!data} onClose={onClose} title="API key created" size="md"
      footer={<Button onClick={onClose}>Done</Button>}>
      <p className="mb-3 text-sm text-amber-300">{data?.warning}</p>
      <div className="flex items-center gap-2 rounded-lg border border-line bg-white/5 p-3">
        <code className="flex-1 break-all font-mono text-xs text-cyan-200">{data?.key}</code>
        <Button
          size="sm"
          variant="secondary"
          icon={<Copy className="h-3.5 w-3.5" />}
          onClick={() => {
            if (data?.key) {
              navigator.clipboard?.writeText(data.key);
              toast.success('Copied');
            }
          }}
        >
          Copy
        </Button>
      </div>
    </Modal>
  );
}

function ClientForm({
  open, client, onClose, onSaved, onCreatedKey,
}: {
  open: boolean;
  client: any | null;
  onClose: () => void;
  onSaved: () => void;
  onCreatedKey: (key: string, warning: string) => void;
}) {
  const isEdit = !!client;
  const [name, setName] = useState('');
  const [clientType, setClientType] = useState('android');
  const [scopes, setScopes] = useState<string[]>([]);
  const [origins, setOrigins] = useState('');
  const [packages, setPackages] = useState('');
  const [bundles, setBundles] = useState('');
  const [rpm, setRpm] = useState('120');
  const [rph, setRph] = useState('5000');
  const [rpd, setRpd] = useState('100000');
  const [status, setStatus] = useState('active');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);

  // Reset form when opening
  useMemo(() => {
    if (open) {
      setName(client?.name || '');
      setClientType(client?.client_type || 'android');
      setScopes(client?.scopes || []);
      setOrigins((client?.allowed_origins || []).join(', '));
      setPackages((client?.allowed_package_names || []).join(', '));
      setBundles((client?.allowed_bundle_ids || []).join(', '));
      setRpm(String(client?.rate_limit_per_minute ?? 120));
      setRph(String(client?.rate_limit_per_hour ?? 5000));
      setRpd(String(client?.rate_limit_per_day ?? 100000));
      setStatus(client?.status || 'active');
      setNotes(client?.notes || '');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const toggleScope = (s: string) =>
    setScopes((prev) => (prev.includes(s) ? prev.filter((x) => x !== s) : [...prev, s]));

  const submit = async () => {
    if (!name || name.trim().length < 3) {
      toast.error('Name must be at least 3 characters');
      return;
    }
    setSaving(true);
    const body = {
      name: name.trim(),
      client_type: clientType,
      scopes,
      allowed_origins: origins,
      allowed_package_names: packages,
      allowed_bundle_ids: bundles,
      rate_limit_per_minute: Number(rpm) || 0,
      rate_limit_per_hour: Number(rph) || 0,
      rate_limit_per_day: Number(rpd) || 0,
      status,
      notes,
    };
    try {
      if (isEdit) {
        await apiSecurityApi.updateClient(client.id, body);
        toast.success('Client updated');
      } else {
        const res = await apiSecurityApi.createClient(body);
        onCreatedKey(res.api_key, res.warning);
        toast.success('Client created');
      }
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEdit ? 'Edit API client' : 'New API client'}
      description={isEdit ? undefined : 'A key is generated on save and shown only once.'}
      size="lg"
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button onClick={submit} loading={saving}>{isEdit ? 'Save' : 'Create & generate key'}</Button>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Client name" required>
          <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="CricPro Android" />
        </Field>
        <Field label="Client type">
          <Select value={clientType} onChange={(e) => setClientType(e.target.value)}>
            {CLIENT_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
          </Select>
        </Field>
        <Field label="Status">
          <Select value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="active">active</option>
            <option value="disabled">disabled</option>
            <option value="revoked">revoked</option>
          </Select>
        </Field>
        <Field label="Rate / minute"><Input type="number" value={rpm} onChange={(e) => setRpm(e.target.value)} /></Field>
        <Field label="Rate / hour"><Input type="number" value={rph} onChange={(e) => setRph(e.target.value)} /></Field>
        <Field label="Rate / day"><Input type="number" value={rpd} onChange={(e) => setRpd(e.target.value)} /></Field>
      </div>

      <Field label="Allowed endpoint groups (scopes)" hint="Leave all unchecked to allow every group" className="mt-4">
        <div className="flex flex-wrap gap-2">
          {ENDPOINT_GROUPS.filter((g) => g !== 'admin' && g !== 'default').map((g) => (
            <button
              key={g}
              type="button"
              onClick={() => toggleScope(g)}
              className={`rounded-md border px-2 py-1 text-[11px] ${scopes.includes(g) ? 'border-cyan-300/40 bg-cyan-400/15 text-cyan-100' : 'border-line bg-white/5 text-slate-300'}`}
            >
              {g}
            </button>
          ))}
        </div>
      </Field>

      <div className="mt-4 grid gap-4 sm:grid-cols-1">
        <Field label="Allowed origins (web, comma-separated)" hint="e.g. https://webcrichd.co">
          <Input value={origins} onChange={(e) => setOrigins(e.target.value)} placeholder="https://webcrichd.co" />
        </Field>
        <Field label="Allowed package names (Android, comma-separated)">
          <Input value={packages} onChange={(e) => setPackages(e.target.value)} placeholder="com.cricpro.app" />
        </Field>
        <Field label="Allowed bundle IDs (iOS, comma-separated)">
          <Input value={bundles} onChange={(e) => setBundles(e.target.value)} placeholder="com.cricpro.app" />
        </Field>
        <Field label="Notes">
          <Textarea value={notes} onChange={(e) => setNotes(e.target.value)} />
        </Field>
      </div>
    </Modal>
  );
}

// =====================================================
// Allowed Domains / Origins tab
// =====================================================
function OriginsTab({ canWrite }: { canWrite: boolean }) {
  const { data, loading, error, reload } = useResource(() => apiSecurityApi.listOrigins(), []);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<any | null>(null);
  const [toDelete, setToDelete] = useState<any | null>(null);
  const rows = data?.data || [];

  const columns: Column<any>[] = [
    { id: 'origin', header: 'Origin', render: (r) => <code className="font-mono text-xs text-cyan-200">{r.origin || '—'}</code> },
    { id: 'domain', header: 'Domain', render: (r) => r.domain || '—' },
    { id: 'groups', header: 'Endpoint groups', render: (r) => <span className="text-xs text-slate-400">{(r.allowed_endpoint_groups || []).length ? (r.allowed_endpoint_groups || []).join(', ') : 'all'}</span> },
    { id: 'rate', header: 'Rate/min', render: (r) => r.rate_limit_per_minute ?? '—' },
    { id: 'status', header: 'Status', render: (r) => <StatusBadge status={r.status === 'active' ? 'active' : 'inactive'} /> },
    {
      id: 'actions', header: '', className: 'text-right',
      render: (r) => canWrite ? (
        <div className="flex items-center justify-end gap-1">
          <Button size="sm" variant="ghost" onClick={() => { setEditing(r); setShowForm(true); }}>Edit</Button>
          <Button size="sm" variant="danger" icon={<Trash2 className="h-3.5 w-3.5" />} onClick={() => setToDelete(r)} />
        </div>
      ) : null,
    },
  ];

  return (
    <>
      <div className="mb-3 flex justify-end gap-2">
        <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>Refresh</Button>
        {canWrite && <Button icon={<Plus className="h-4 w-4" />} onClick={() => { setEditing(null); setShowForm(true); }}>Add domain</Button>}
      </div>
      <DataTable
        loading={loading} error={error} onRetry={reload} rows={rows} columns={columns} rowKey={(r) => r.id}
        emptyTitle="No allowed domains" emptyDescription="Add an origin or domain to allow browser/website access (drives CORS)."
      />
      <OriginForm open={showForm} origin={editing} onClose={() => setShowForm(false)} onSaved={reload} />
      <ConfirmDialog
        open={!!toDelete} onClose={() => setToDelete(null)}
        onConfirm={async () => { if (toDelete) { await apiSecurityApi.deleteOrigin(toDelete.id); toast.success('Removed'); reload(); } }}
        title="Remove domain" description="Browsers on this origin will be blocked by CORS." confirmLabel="Remove" destructive
      />
    </>
  );
}

function OriginForm({ open, origin, onClose, onSaved }: { open: boolean; origin: any | null; onClose: () => void; onSaved: () => void }) {
  const isEdit = !!origin;
  const [originVal, setOriginVal] = useState('');
  const [domain, setDomain] = useState('');
  const [groups, setGroups] = useState<string[]>([]);
  const [rpm, setRpm] = useState('120');
  const [active, setActive] = useState(true);
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);

  useMemo(() => {
    if (open) {
      setOriginVal(origin?.origin || '');
      setDomain(origin?.domain || '');
      setGroups(origin?.allowed_endpoint_groups || []);
      setRpm(String(origin?.rate_limit_per_minute ?? 120));
      setActive(origin ? origin.status === 'active' : true);
      setNotes(origin?.notes || '');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const toggleGroup = (g: string) => setGroups((p) => (p.includes(g) ? p.filter((x) => x !== g) : [...p, g]));

  const submit = async () => {
    if (!originVal && !domain) { toast.error('Provide an origin or domain'); return; }
    setSaving(true);
    const body = { origin: originVal || null, domain: domain || null, allowed_endpoint_groups: groups, rate_limit_per_minute: Number(rpm) || 0, status: active ? 'active' : 'inactive', notes };
    try {
      if (isEdit) { await apiSecurityApi.updateOrigin(origin.id, body); toast.success('Updated'); }
      else { await apiSecurityApi.createOrigin(body); toast.success('Added'); }
      onSaved(); onClose();
    } catch (err) { toast.error(err instanceof Error ? err.message : 'Failed'); }
    finally { setSaving(false); }
  };

  return (
    <Modal open={open} onClose={onClose} title={isEdit ? 'Edit domain' : 'Add allowed domain'} size="lg"
      footer={<><Button variant="ghost" onClick={onClose}>Cancel</Button><Button onClick={submit} loading={saving}>Save</Button></>}>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Origin" hint="Full origin incl. scheme"><Input value={originVal} onChange={(e) => setOriginVal(e.target.value)} placeholder="https://webcrichd.co" /></Field>
        <Field label="Domain" hint="Hostname only (optional)"><Input value={domain} onChange={(e) => setDomain(e.target.value)} placeholder="webcrichd.co" /></Field>
        <Field label="Rate / minute"><Input type="number" value={rpm} onChange={(e) => setRpm(e.target.value)} /></Field>
        <Field label="Active"><div className="pt-2"><Switch checked={active} onChange={setActive} /></div></Field>
      </div>
      <Field label="Allowed endpoint groups" hint="Leave empty to allow all groups" className="mt-4">
        <div className="flex flex-wrap gap-2">
          {ENDPOINT_GROUPS.filter((g) => g !== 'admin').map((g) => (
            <button key={g} type="button" onClick={() => toggleGroup(g)}
              className={`rounded-md border px-2 py-1 text-[11px] ${groups.includes(g) ? 'border-cyan-300/40 bg-cyan-400/15 text-cyan-100' : 'border-line bg-white/5 text-slate-300'}`}>{g}</button>
          ))}
        </div>
      </Field>
      <Field label="Notes" className="mt-4"><Textarea value={notes} onChange={(e) => setNotes(e.target.value)} /></Field>
    </Modal>
  );
}

// =====================================================
// Endpoint Rules tab
// =====================================================
function RulesTab({ canWrite }: { canWrite: boolean }) {
  const { data, loading, error, reload } = useResource(() => apiSecurityApi.listEndpointRules(), []);
  const [editing, setEditing] = useState<any | null>(null);
  const rows = data?.data || [];

  const toggleEnabled = async (r: any) => {
    try { await apiSecurityApi.updateEndpointRule(r.id, { enabled: !r.enabled }); reload(); }
    catch (err) { toast.error(err instanceof Error ? err.message : 'Failed'); }
  };

  const columns: Column<any>[] = [
    { id: 'group', header: 'Group', render: (r) => <span className="font-medium text-slate-100">{r.group_name}</span> },
    { id: 'pattern', header: 'Pattern', render: (r) => <code className="font-mono text-xs text-slate-400">{r.path_pattern || '—'}</code> },
    { id: 'auth', header: 'Auth', render: (r) => <span className="rounded-md bg-white/5 px-2 py-0.5 text-[10px] uppercase">{r.auth_required}</span> },
    { id: 'types', header: 'Client types', render: (r) => <span className="text-xs text-slate-400">{(r.allowed_client_types || []).join(', ') || 'all'}</span> },
    { id: 'rate', header: 'Rate/min', render: (r) => r.rate_limit_per_minute ?? '—' },
    { id: 'enabled', header: 'Enabled', render: (r) => <Switch checked={!!r.enabled} onChange={() => toggleEnabled(r)} disabled={!canWrite} /> },
    { id: 'actions', header: '', className: 'text-right', render: (r) => canWrite ? <Button size="sm" variant="ghost" onClick={() => setEditing(r)}>Edit</Button> : null },
  ];

  return (
    <>
      <div className="mb-3 flex justify-end">
        <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>Refresh</Button>
      </div>
      <DataTable loading={loading} error={error} onRetry={reload} rows={rows} columns={columns} rowKey={(r) => r.id}
        emptyTitle="No endpoint rules" emptyDescription="Default rules are seeded by the migration." />
      <RuleForm open={!!editing} rule={editing} onClose={() => setEditing(null)} onSaved={reload} />
    </>
  );
}

function RuleForm({ open, rule, onClose, onSaved }: { open: boolean; rule: any | null; onClose: () => void; onSaved: () => void }) {
  const [auth, setAuth] = useState('api_key');
  const [types, setTypes] = useState<string[]>([]);
  const [rpm, setRpm] = useState('120');
  const [rph, setRph] = useState('0');
  const [ttl, setTtl] = useState('0');
  const [enabled, setEnabled] = useState(true);
  const [logging, setLogging] = useState(true);
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);

  useMemo(() => {
    if (open && rule) {
      setAuth(rule.auth_required || 'api_key');
      setTypes(rule.allowed_client_types || []);
      setRpm(String(rule.rate_limit_per_minute ?? 120));
      setRph(String(rule.rate_limit_per_hour ?? 0));
      setTtl(String(rule.cache_ttl_seconds ?? 0));
      setEnabled(!!rule.enabled);
      setLogging(!!rule.logging_enabled);
      setNotes(rule.notes || '');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const toggleType = (t: string) => setTypes((p) => (p.includes(t) ? p.filter((x) => x !== t) : [...p, t]));

  const submit = async () => {
    setSaving(true);
    try {
      await apiSecurityApi.updateEndpointRule(rule.id, {
        auth_required: auth, allowed_client_types: types,
        rate_limit_per_minute: Number(rpm) || 0, rate_limit_per_hour: Number(rph) || 0,
        cache_ttl_seconds: Number(ttl) || 0, enabled, logging_enabled: logging, notes,
      });
      toast.success('Rule updated'); onSaved(); onClose();
    } catch (err) { toast.error(err instanceof Error ? err.message : 'Failed'); }
    finally { setSaving(false); }
  };

  return (
    <Modal open={open} onClose={onClose} title={`Endpoint rule — ${rule?.group_name || ''}`} size="lg"
      footer={<><Button variant="ghost" onClick={onClose}>Cancel</Button><Button onClick={submit} loading={saving}>Save</Button></>}>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Auth required">
          <Select value={auth} onChange={(e) => setAuth(e.target.value)}>
            <option value="none">none (public)</option>
            <option value="api_key">api_key</option>
            <option value="admin_jwt">admin_jwt</option>
          </Select>
        </Field>
        <Field label="Cache TTL (seconds)"><Input type="number" value={ttl} onChange={(e) => setTtl(e.target.value)} /></Field>
        <Field label="Rate / minute"><Input type="number" value={rpm} onChange={(e) => setRpm(e.target.value)} /></Field>
        <Field label="Rate / hour"><Input type="number" value={rph} onChange={(e) => setRph(e.target.value)} /></Field>
      </div>
      <Field label="Allowed client types" hint="Leave empty to allow all types" className="mt-4">
        <div className="flex flex-wrap gap-2">
          {CLIENT_TYPES.map((t) => (
            <button key={t} type="button" onClick={() => toggleType(t)}
              className={`rounded-md border px-2 py-1 text-[11px] ${types.includes(t) ? 'border-cyan-300/40 bg-cyan-400/15 text-cyan-100' : 'border-line bg-white/5 text-slate-300'}`}>{t}</button>
          ))}
        </div>
      </Field>
      <div className="mt-4 flex gap-6">
        <Switch checked={enabled} onChange={setEnabled} label="Enabled" />
        <Switch checked={logging} onChange={setLogging} label="Logging" />
      </div>
      <Field label="Notes" className="mt-4"><Textarea value={notes} onChange={(e) => setNotes(e.target.value)} /></Field>
    </Modal>
  );
}

// =====================================================
// Blocklist tab
// =====================================================
function BlocklistTab({ canWrite }: { canWrite: boolean }) {
  const { data, loading, error, reload } = useResource(() => apiSecurityApi.listBlocklist(), []);
  const [showForm, setShowForm] = useState(false);
  const [toDelete, setToDelete] = useState<any | null>(null);
  const rows = data?.data || [];

  const toggle = async (r: any) => {
    try { await apiSecurityApi.updateBlock(r.id, { enabled: !r.enabled }); reload(); }
    catch (err) { toast.error(err instanceof Error ? err.message : 'Failed'); }
  };

  const columns: Column<any>[] = [
    { id: 'type', header: 'Type', render: (r) => <span className="rounded-md bg-white/5 px-2 py-0.5 text-[10px] uppercase">{r.type}</span> },
    { id: 'value', header: 'Value', render: (r) => <code className="font-mono text-xs text-slate-200">{r.value}</code> },
    { id: 'reason', header: 'Reason', render: (r) => <span className="text-xs text-slate-400">{r.reason || '—'}</span> },
    { id: 'expires', header: 'Expires', render: (r) => (r.expires_at ? formatDateTime(r.expires_at) : 'never') },
    { id: 'enabled', header: 'Enabled', render: (r) => <Switch checked={!!r.enabled} onChange={() => toggle(r)} disabled={!canWrite} /> },
    { id: 'actions', header: '', className: 'text-right', render: (r) => canWrite ? <Button size="sm" variant="danger" icon={<Trash2 className="h-3.5 w-3.5" />} onClick={() => setToDelete(r)} /> : null },
  ];

  return (
    <>
      <div className="mb-3 flex justify-end gap-2">
        <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>Refresh</Button>
        {canWrite && <Button icon={<Plus className="h-4 w-4" />} onClick={() => setShowForm(true)}>Add block</Button>}
      </div>
      <DataTable loading={loading} error={error} onRetry={reload} rows={rows} columns={columns} rowKey={(r) => r.id}
        emptyTitle="Blocklist is empty" emptyDescription="Block an IP, CIDR range, origin, domain, user agent, or client." />
      <BlockForm open={showForm} onClose={() => setShowForm(false)} onSaved={reload} />
      <ConfirmDialog
        open={!!toDelete} onClose={() => setToDelete(null)}
        onConfirm={async () => { if (toDelete) { await apiSecurityApi.deleteBlock(toDelete.id); toast.success('Removed'); reload(); } }}
        title="Remove block" description="This entry will no longer be blocked." confirmLabel="Remove" destructive
      />
    </>
  );
}

function BlockForm({ open, onClose, onSaved }: { open: boolean; onClose: () => void; onSaved: () => void }) {
  const [type, setType] = useState('ip');
  const [value, setValue] = useState('');
  const [reason, setReason] = useState('');
  const [expiresAt, setExpiresAt] = useState('');
  const [saving, setSaving] = useState(false);

  useMemo(() => {
    if (open) { setType('ip'); setValue(''); setReason(''); setExpiresAt(''); }
  }, [open]);

  const submit = async () => {
    if (!value.trim()) { toast.error('Value required'); return; }
    setSaving(true);
    try {
      await apiSecurityApi.createBlock({ type, value: value.trim(), reason, expires_at: expiresAt || null });
      toast.success('Block added'); onSaved(); onClose();
    } catch (err) { toast.error(err instanceof Error ? err.message : 'Failed'); }
    finally { setSaving(false); }
  };

  return (
    <Modal open={open} onClose={onClose} title="Add blocklist entry" size="md"
      footer={<><Button variant="ghost" onClick={onClose}>Cancel</Button><Button variant="danger" onClick={submit} loading={saving}>Block</Button></>}>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Type">
          <Select value={type} onChange={(e) => setType(e.target.value)}>
            {BLOCK_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
          </Select>
        </Field>
        <Field label="Expires at (optional)"><Input type="datetime-local" value={expiresAt} onChange={(e) => setExpiresAt(e.target.value)} /></Field>
      </div>
      <Field label="Value" required hint="IP, CIDR (1.2.3.0/24), origin, domain, user-agent substring, or client id" className="mt-4">
        <Input value={value} onChange={(e) => setValue(e.target.value)} placeholder="1.2.3.4" />
      </Field>
      <Field label="Reason" className="mt-4"><Textarea value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
    </Modal>
  );
}

// =====================================================
// Request Logs tab
// =====================================================
function LogsTab() {
  const [blockedOnly, setBlockedOnly] = useState(false);
  const [group, setGroup] = useState('');
  const [ip, setIp] = useState('');
  const [statusCode, setStatusCode] = useState('');
  const [page, setPage] = useState(1);

  const params = useMemo(() => ({
    blocked: blockedOnly ? 'true' : undefined,
    group: group || undefined,
    ip: ip || undefined,
    status_code: statusCode || undefined,
    page,
    limit: 100,
  }), [blockedOnly, group, ip, statusCode, page]);

  const { data, loading, error, reload } = useResource(() => apiSecurityApi.listLogs(params), [params]);
  const rows = data?.data || [];
  const total = data?.pagination.total || 0;

  const columns: Column<any>[] = [
    { id: 'time', header: 'Time', render: (r) => <span className="text-xs text-slate-400">{formatDateTime(r.created_at)}</span> },
    { id: 'method', header: 'Method', render: (r) => <span className="font-mono text-xs">{r.method}</span> },
    { id: 'path', header: 'Path', render: (r) => <code className="font-mono text-xs text-slate-300">{r.path}</code> },
    { id: 'group', header: 'Group', render: (r) => <span className="text-xs text-slate-400">{r.endpoint_group}</span> },
    { id: 'status', header: 'Status', render: (r) => <span className="font-mono text-xs">{r.status_code}</span> },
    { id: 'ip', header: 'IP', render: (r) => <span className="font-mono text-xs text-slate-400">{r.ip}</span> },
    { id: 'client', header: 'Client', render: (r) => <span className="text-xs text-slate-400">{r.api_key_prefix || '—'}</span> },
    { id: 'allowed', header: 'Result', render: (r) => (r.allowed ? <StatusBadge tone="success">allowed</StatusBadge> : <StatusBadge tone="danger">{r.blocked_reason || 'blocked'}</StatusBadge>) },
    { id: 'rt', header: 'ms', render: (r) => r.response_time_ms ?? '—' },
  ];

  return (
    <>
      <div className="mb-3 flex flex-wrap items-end gap-3">
        <Field label="Endpoint group" className="w-44">
          <Select value={group} onChange={(e) => { setGroup(e.target.value); setPage(1); }}>
            <option value="">All</option>
            {ENDPOINT_GROUPS.map((g) => <option key={g} value={g}>{g}</option>)}
          </Select>
        </Field>
        <Field label="IP" className="w-40"><Input value={ip} onChange={(e) => { setIp(e.target.value); setPage(1); }} placeholder="1.2.3.4" /></Field>
        <Field label="Status code" className="w-32"><Input value={statusCode} onChange={(e) => { setStatusCode(e.target.value); setPage(1); }} placeholder="403" /></Field>
        <div className="pb-1"><Switch checked={blockedOnly} onChange={(v) => { setBlockedOnly(v); setPage(1); }} label="Blocked only" /></div>
        <div className="ml-auto pb-1">
          <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>Refresh</Button>
        </div>
      </div>
      <DataTable loading={loading} error={error} onRetry={reload} rows={rows} columns={columns} rowKey={(r) => r.id}
        emptyTitle="No request logs" emptyDescription="Logs appear here as the API receives traffic." />
      <div className="mt-3 flex items-center justify-between text-xs text-slate-400">
        <span>{total} total · page {page}</span>
        <div className="flex gap-2">
          <Button size="sm" variant="secondary" disabled={page <= 1} onClick={() => setPage((p) => Math.max(1, p - 1))}>Prev</Button>
          <Button size="sm" variant="secondary" disabled={rows.length < 100} onClick={() => setPage((p) => p + 1)}>Next</Button>
        </div>
      </div>
    </>
  );
}
