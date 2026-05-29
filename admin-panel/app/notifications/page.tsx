'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Plus, RefreshCw, Send, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { SearchInput } from '@/components/ui/SearchInput';
import { FilterBar } from '@/components/ui/FilterBar';
import { Button } from '@/components/ui/Button';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { NotificationForm } from '@/components/forms/NotificationForm';
import { notificationsApi } from '@/lib/api';
import { useAuth, useDebouncedValue, usePermissions, useResource } from '@/lib/hooks';
import { formatDateTime } from '@/lib/utils';

type Notification = {
  id: number;
  title: string;
  body: string;
  status: 'draft' | 'scheduled' | 'sent';
  target_type?: string;
  scheduled_at?: string;
  sent_at?: string;
  created_at?: string;
};

export default function NotificationsPage() {
  return (
    <AdminShell permission="notifications.view">
      <Inner />
    </AdminShell>
  );
}

function Inner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const canWrite = perms.can('notifications.write');
  const [q, setQ] = useState('');
  const debouncedQ = useDebouncedValue(q, 250);
  const [status, setStatus] = useState('all');
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<Notification | null>(null);
  const [toDelete, setToDelete] = useState<Notification | null>(null);
  const [toSend, setToSend] = useState<Notification | null>(null);

  const { data, loading, reload } = useResource(() => notificationsApi.list(), []);
  const all = (data?.data || []) as Notification[];

  const rows = useMemo(() => {
    const needle = debouncedQ.toLowerCase();
    return all.filter((n) => {
      if (status !== 'all' && n.status !== status) return false;
      if (needle && !`${n.title} ${n.body}`.toLowerCase().includes(needle)) return false;
      return true;
    });
  }, [all, debouncedQ, status]);

  const columns: Column<Notification>[] = [
    {
      id: 'title',
      header: 'Notification',
      render: (n) => (
        <div>
          <div className="font-medium text-slate-100">{n.title}</div>
          <div className="line-clamp-1 text-xs text-slate-500">{n.body}</div>
        </div>
      ),
    },
    { id: 'status', header: 'Status', render: (n) => <StatusBadge status={n.status} /> },
    { id: 'target', header: 'Target', render: (n) => n.target_type ?? 'all' },
    { id: 'scheduled', header: 'Scheduled', render: (n) => (n.scheduled_at ? formatDateTime(n.scheduled_at) : '—') },
    { id: 'sent', header: 'Sent', render: (n) => (n.sent_at ? formatDateTime(n.sent_at) : '—') },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (n) =>
        canWrite ? (
          <div className="flex justify-end gap-1">
            {n.status !== 'sent' && (
              <Button size="sm" variant="ghost" icon={<Send className="h-3.5 w-3.5" />} onClick={() => setToSend(n)}>Send</Button>
            )}
            <Button size="sm" variant="ghost" onClick={() => { setEditing(n); setShowForm(true); }}>Edit</Button>
            <Button size="sm" variant="danger" icon={<Trash2 className="h-3.5 w-3.5" />} onClick={() => setToDelete(n)} />
          </div>
        ) : null,
    },
  ];

  return (
    <>
      <PageHeader
        title="Notifications"
        description="Compose, schedule, and send push notifications. Targets cover everyone, FCM topics, or specific user IDs. Deep links open relevant screens in the Flutter app."
        right={
          <>
            <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>Refresh</Button>
            {canWrite && (
              <Button icon={<Plus className="h-4 w-4" />} onClick={() => { setEditing(null); setShowForm(true); }}>
                New notification
              </Button>
            )}
          </>
        }
      />
      <SearchInput value={q} onChange={setQ} placeholder="Search notifications…" className="mb-3 max-w-md" />
      <FilterBar
        filters={[
          {
            type: 'select',
            id: 'status',
            label: 'Status',
            value: status,
            options: [
              { id: 'all', label: 'All' },
              { id: 'draft', label: 'Draft' },
              { id: 'scheduled', label: 'Scheduled' },
              { id: 'sent', label: 'Sent' },
            ],
            onChange: setStatus,
          },
        ]}
      />
      <DataTable loading={loading} rows={rows} columns={columns} rowKey={(n) => n.id} emptyTitle="No notifications" />

      <NotificationForm
        open={showForm}
        onClose={() => setShowForm(false)}
        initial={editing}
        onSaved={reload}
      />

      <ConfirmDialog
        open={!!toSend}
        onClose={() => setToSend(null)}
        onConfirm={async () => {
          if (toSend) {
            await notificationsApi.send(toSend.id);
            toast.success('Notification sent');
            reload();
          }
        }}
        title="Send notification now?"
        description="This delivers the push immediately to all matching users."
        confirmLabel="Send"
      />

      <ConfirmDialog
        open={!!toDelete}
        onClose={() => setToDelete(null)}
        onConfirm={async () => {
          if (toDelete) {
            await notificationsApi.delete(toDelete.id);
            toast.success('Deleted');
            reload();
          }
        }}
        title="Delete notification?"
        destructive
      />
    </>
  );
}
