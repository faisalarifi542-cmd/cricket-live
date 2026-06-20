'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Plus, RefreshCw, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { Button } from '@/components/ui/Button';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { RoleForm } from '@/components/forms/RoleForm';
import { rolesApi } from '@/lib/api';
import { useAuth, usePermissions, useResource } from '@/lib/hooks';

type Role = {
  slug: string;
  name: string;
  description?: string;
  permissions?: string[];
  user_count?: number;
};

export default function RolesPage() {
  return (
    <AdminShell permission="roles.view">
      <Inner />
    </AdminShell>
  );
}

function Inner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const canWrite = perms.can('roles.write');
  const { data, loading, error, reload } = useResource(() => rolesApi.list(), []);
  const rows = (data?.data || []) as Role[];
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<Role | null>(null);
  const [toDelete, setToDelete] = useState<Role | null>(null);

  const columns: Column<Role>[] = [
    {
      id: 'role',
      header: 'Role',
      render: (r) => (
        <div>
          <div className="font-medium text-slate-100">{r.name}</div>
          <div className="text-[10px] uppercase tracking-wide text-slate-500">{r.slug}</div>
        </div>
      ),
    },
    { id: 'desc', header: 'Description', render: (r) => r.description ?? '—' },
    { id: 'perms', header: 'Permissions', render: (r) => `${(r.permissions ?? []).length}` },
    { id: 'users', header: 'Users', render: (r) => r.user_count ?? 0 },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (r) =>
        canWrite ? (
          <div className="flex justify-end gap-1">
            <Button size="sm" variant="ghost" onClick={() => { setEditing(r); setShowForm(true); }}>Edit</Button>
            <Button size="sm" variant="danger" icon={<Trash2 className="h-3.5 w-3.5" />} onClick={() => setToDelete(r)} />
          </div>
        ) : null,
    },
  ];

  return (
    <>
      <PageHeader
        title="Roles & permissions"
        description="Define roles and the actions they grant. Built-in roles can be edited; deletion is blocked when users still hold the role."
        right={
          <>
            <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>Refresh</Button>
            {canWrite && (
              <Button icon={<Plus className="h-4 w-4" />} onClick={() => { setEditing(null); setShowForm(true); }}>
                New role
              </Button>
            )}
          </>
        }
      />
      <DataTable loading={loading} error={error} onRetry={reload} rows={rows} columns={columns} rowKey={(r) => r.slug} emptyTitle="No roles" />

      <RoleForm
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
            await rolesApi.delete(toDelete.slug);
            toast.success('Role deleted');
            reload();
          }
        }}
        title="Delete role?"
        description="Users assigned this role will lose its permissions."
        destructive
      />
    </>
  );
}
