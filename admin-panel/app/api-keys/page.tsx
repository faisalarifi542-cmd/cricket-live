'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Plus, RefreshCw, ShieldOff, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { SearchInput } from '@/components/ui/SearchInput';
import { FilterBar } from '@/components/ui/FilterBar';
import { Button } from '@/components/ui/Button';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { ApiKeyForm } from '@/components/forms/ApiKeyForm';
import { apiKeysApi } from '@/lib/api';
import { useAuth, useDebouncedValue, usePermissions, useResource } from '@/lib/hooks';
import { API_KEY_TIERS } from '@/lib/constants';
import { formatDateTime, formatRelative, maskKey } from '@/lib/utils';

type ApiKey = {
  id: number;
  name: string;
  email?: string;
  tier: string;
  api_key?: string;
  api_key_preview?: string;
  rate_limit: number;
  usage_count?: number;
  last_used_at?: string;
  expires_at?: string;
  is_active?: boolean | number;
  revoked?: boolean | number;
  created_at: string;
};

export default function ApiKeysPage() {
  return (
    <AdminShell permission="apiKeys.view">
      <ApiKeysInner />
    </AdminShell>
  );
}

function ApiKeysInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const [q, setQ] = useState('');
  const debouncedQ = useDebouncedValue(q, 250);
  const [tier, setTier] = useState('all');
  const [status, setStatus] = useState('all');
  const [showForm, setShowForm] = useState(false);
  const [toDelete, setToDelete] = useState<ApiKey | null>(null);
  const [toRevoke, setToRevoke] = useState<ApiKey | null>(null);

  const { data, loading, error, reload } = useResource(() => apiKeysApi.list(), []);
  const keys = (data?.data || []) as ApiKey[];

  const filtered = useMemo(() => {
    return keys.filter((k) => {
      if (tier !== 'all' && k.tier !== tier) return false;
      if (status === 'active' && (k.revoked || !k.is_active)) return false;
      if (status === 'revoked' && !k.revoked) return false;
      if (debouncedQ) {
        const haystack = `${k.name} ${k.email ?? ''} ${k.api_key_preview ?? ''}`.toLowerCase();
        if (!haystack.includes(debouncedQ.toLowerCase())) return false;
      }
      return true;
    });
  }, [keys, debouncedQ, tier, status]);

  const columns: Column<ApiKey>[] = [
    {
      id: 'name',
      header: 'Name',
      render: (k) => (
        <div>
          <div className="font-medium text-slate-100">{k.name}</div>
          <div className="text-xs text-slate-500">{k.email || '—'}</div>
        </div>
      ),
    },
    {
      id: 'key',
      header: 'Key',
      render: (k) => (
        <code className="font-mono text-xs text-cyan-200">
          {k.api_key_preview || maskKey(k.api_key)}
        </code>
      ),
    },
    {
      id: 'tier',
      header: 'Tier',
      render: (k) => (
        <span className="rounded-md bg-white/5 px-2 py-0.5 text-[10px] uppercase text-slate-200">
          {k.tier}
        </span>
      ),
    },
    { id: 'rate', header: 'Rate / min', render: (k) => k.rate_limit ?? '—' },
    { id: 'usage', header: 'Usage', render: (k) => k.usage_count ?? 0 },
    {
      id: 'last_used',
      header: 'Last used',
      render: (k) => (k.last_used_at ? formatRelative(k.last_used_at) : '—'),
    },
    {
      id: 'expires',
      header: 'Expires',
      render: (k) => (k.expires_at ? formatDateTime(k.expires_at) : '—'),
    },
    {
      id: 'status',
      header: 'Status',
      render: (k) => <StatusBadge status={k.revoked ? 'revoked' : k.is_active ? 'active' : 'inactive'} />,
    },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (k) => (
        <div className="flex items-center justify-end gap-1">
          {perms.can('apiKeys.write') && !k.revoked && (
            <Button
              size="sm"
              variant="ghost"
              icon={<ShieldOff className="h-3.5 w-3.5" />}
              onClick={() => setToRevoke(k)}
            >
              Revoke
            </Button>
          )}
          {perms.can('apiKeys.write') && (
            <Button
              size="sm"
              variant="danger"
              icon={<Trash2 className="h-3.5 w-3.5" />}
              onClick={() => setToDelete(k)}
            />
          )}
        </div>
      ),
    },
  ];

  return (
    <>
      <PageHeader
        title="API keys"
        description="Issue, view, and revoke public API keys for partner apps. The raw key is shown only once at creation."
        right={
          <>
            <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>
              Refresh
            </Button>
            {perms.can('apiKeys.write') && (
              <Button icon={<Plus className="h-4 w-4" />} onClick={() => setShowForm(true)}>
                Issue key
              </Button>
            )}
          </>
        }
      />

      <SearchInput value={q} onChange={setQ} placeholder="Search by name, email, or key prefix…" className="mb-3 max-w-md" />

      <FilterBar
        filters={[
          {
            type: 'select',
            id: 'tier',
            label: 'Tier',
            value: tier,
            options: [{ id: 'all', label: 'All' }, ...API_KEY_TIERS.map((t) => ({ id: t, label: t }))],
            onChange: setTier,
          },
          {
            type: 'select',
            id: 'status',
            label: 'Status',
            value: status,
            options: [
              { id: 'all', label: 'All' },
              { id: 'active', label: 'Active' },
              { id: 'revoked', label: 'Revoked' },
            ],
            onChange: setStatus,
          },
        ]}
      />

      <DataTable
        loading={loading}
        error={error}
        onRetry={reload}
        rows={filtered}
        columns={columns}
        rowKey={(k) => k.id}
        emptyTitle="No API keys"
        emptyDescription="Issue an API key to expose the public cricket API."
      />

      <ApiKeyForm open={showForm} onClose={() => setShowForm(false)} onSaved={reload} />

      <ConfirmDialog
        open={!!toRevoke}
        onClose={() => setToRevoke(null)}
        onConfirm={async () => {
          if (toRevoke) {
            await apiKeysApi.revoke(toRevoke.id);
            toast.success('Key revoked');
            reload();
          }
        }}
        title="Revoke API key"
        description="Existing clients will start receiving 401 immediately."
        confirmLabel="Revoke key"
        destructive
      />

      <ConfirmDialog
        open={!!toDelete}
        onClose={() => setToDelete(null)}
        onConfirm={async () => {
          if (toDelete) {
            await apiKeysApi.delete(toDelete.id);
            toast.success('Key deleted');
            reload();
          }
        }}
        title="Delete API key"
        description="This permanently removes the key. Prefer Revoke to keep audit history."
        confirmLabel="Delete key"
        destructive
      />
    </>
  );
}
