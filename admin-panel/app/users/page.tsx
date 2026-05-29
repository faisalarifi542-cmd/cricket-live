'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Plus, RefreshCw, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { SearchInput } from '@/components/ui/SearchInput';
import { Button } from '@/components/ui/Button';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { UserForm } from '@/components/forms/UserForm';
import { rolesApi, usersApi } from '@/lib/api';
import { useAuth, useDebouncedValue, usePermissions, useResource } from '@/lib/hooks';
import { formatRelative } from '@/lib/utils';

type User = {
  id: number;
  name: string;
  email: string;
  is_active?: number | boolean;
  last_login_at?: string;
  roles?: string[];
};

export default function UsersPage() {
  return (
    <AdminShell permission="adminUsers.view">
      <Inner />
    </AdminShell>
  );
}

function Inner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const canWrite = perms.can('adminUsers.write');
  const [q, setQ] = useState('');
  const debouncedQ = useDebouncedValue(q, 250);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<User | null>(null);
  const [toDelete, setToDelete] = useState<User | null>(null);

  const users = useResource(() => usersApi.list(), []);
  const rolesRes = useResource(() => rolesApi.list(), []);
  const all = (users.data?.data || []) as User[];
  const availableRoles = (rolesRes.data?.data || []) as { slug: string; name: string }[];

  const rows = useMemo(() => {
    const needle = debouncedQ.toLowerCase();
    if (!needle) return all;
    return all.filter((u) => `${u.name} ${u.email}`.toLowerCase().includes(needle));
  }, [all, debouncedQ]);

  const columns: Column<User>[] = [
    {
      id: 'user',
      header: 'User',
      render: (u) => (
        <div>
          <div className="font-medium text-slate-100">{u.name}</div>
          <div className="text-xs text-slate-500">{u.email}</div>
        </div>
      ),
    },
    {
      id: 'roles',
      header: 'Roles',
      render: (u) => (
        <div className="flex flex-wrap gap-1">
          {(u.roles ?? []).length ? u.roles!.map((r) => <StatusBadge key={r} tone="info">{r}</StatusBadge>) : '—'}
        </div>
      ),
    },
    { id: 'status', header: 'Status', render: (u) => <StatusBadge status={u.is_active ? 'active' : 'inactive'} /> },
    { id: 'last', header: 'Last login', render: (u) => (u.last_login_at ? formatRelative(u.last_login_at) : 'Never') },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (u) =>
        canWrite ? (
          <div className="flex justify-end gap-1">
            <Button size="sm" variant="ghost" onClick={() => { setEditing(u); setShowForm(true); }}>Edit</Button>
            <Button size="sm" variant="danger" icon={<Trash2 className="h-3.5 w-3.5" />} onClick={() => setToDelete(u)} />
          </div>
        ) : null,
    },
  ];

  return (
    <>
      <PageHeader
        title="Admin users"
        description="Invite admins, assign roles, reset passwords, and deactivate access. Last login shows the latest successful sign-in."
        right={
          <>
            <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={users.reload} loading={users.loading}>Refresh</Button>
            {canWrite && (
              <Button icon={<Plus className="h-4 w-4" />} onClick={() => { setEditing(null); setShowForm(true); }}>
                Add user
              </Button>
            )}
          </>
        }
      />
      <SearchInput value={q} onChange={setQ} placeholder="Search by name or email…" className="mb-3 max-w-md" />
      <DataTable loading={users.loading} rows={rows} columns={columns} rowKey={(u) => u.id} emptyTitle="No admin users" />

      <UserForm
        open={showForm}
        onClose={() => setShowForm(false)}
        initial={editing ? { ...editing, is_active: Boolean(editing.is_active) } : null}
        availableRoles={availableRoles}
        onSaved={users.reload}
      />

      <ConfirmDialog
        open={!!toDelete}
        onClose={() => setToDelete(null)}
        onConfirm={async () => {
          if (toDelete) {
            await usersApi.delete(toDelete.id);
            toast.success('User deleted');
            users.reload();
          }
        }}
        title="Delete admin user?"
        description="They will immediately lose access."
        destructive
      />
    </>
  );
}
