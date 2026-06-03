'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Activity, Plus, RefreshCw, Send, Trash2 } from 'lucide-react';
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
  target_value?: string;
  image_url?: string;
  deep_link_type?: string;
  deep_link_value?: string;
  scheduled_at?: string;
  sent_at?: string;
  created_at?: string;
};

type NotificationPreset = Omit<Notification, 'id'> & { id?: never };

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
  const [editing, setEditing] = useState<Notification | NotificationPreset | null>(null);
  const [toDelete, setToDelete] = useState<Notification | null>(null);
  const [toSend, setToSend] = useState<Notification | null>(null);

  const { data, loading, error, reload } = useResource(() => notificationsApi.list(), []);
  const { data: historyData, reload: reloadHistory } = useResource(() => notificationsApi.history(), []);
  const all = (data?.data || []) as Notification[];
  const history = (historyData?.data || []) as any[];

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
              <Button
                variant="secondary"
                icon={<Activity className="h-4 w-4" />}
                onClick={async () => {
                  await notificationsApi.test({});
                  toast.success('Test notification sent');
                  reloadHistory();
                }}
              >
                Send test
              </Button>
            )}
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
      <DataTable loading={loading} error={error} onRetry={reload} rows={rows} columns={columns} rowKey={(n) => n.id} emptyTitle="No notifications" />

      {canWrite && (
        <div className="my-4 grid gap-3 rounded-2xl border border-line bg-panel/40 p-4 md:grid-cols-4">
          <Button
            variant="secondary"
            onClick={async () => {
              await notificationsApi.sendDirect({
                title: 'CricPro update',
                body: 'Latest cricket updates are available now.',
                target_type: 'all',
                payload: { type: 'home' },
              });
              toast.success('Sent to all users');
              reloadHistory();
            }}
          >
            Send to all
          </Button>
          <Button
            variant="secondary"
            onClick={async () => {
              await notificationsApi.sendDirect({
                title: 'CricPro Android update',
                body: 'Latest cricket updates are available now.',
                target_type: 'android',
                payload: { type: 'home' },
              });
              toast.success('Sent to Android users');
              reloadHistory();
            }}
          >
            Send Android
          </Button>
          <Button
            variant="secondary"
            onClick={async () => {
              await notificationsApi.sendDirect({
                title: 'CricPro iOS update',
                body: 'Latest cricket updates are available now.',
                target_type: 'ios',
                payload: { type: 'home' },
              });
              toast.success('Sent to iOS users');
              reloadHistory();
            }}
          >
            Send iOS
          </Button>
          <Button
            variant="secondary"
            onClick={() => {
              setEditing({
                title: 'Live stream is available',
                body: 'Watch the live cricket stream now on CricPro.',
                status: 'draft',
                target_type: 'all',
                deep_link_type: 'live_stream',
                deep_link_value: '',
              });
              setShowForm(true);
            }}
          >
            Live stream push
          </Button>
        </div>
      )}

      <div className="mt-6">
        <PageHeader
          title="Notification History"
          description="Recent OneSignal send attempts, delivery status, and target metadata."
          right={<Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reloadHistory}>Refresh history</Button>}
        />
        <DataTable
          rows={history}
          columns={[
            { id: 'title', header: 'Title', render: (h) => h.title || '—' },
            { id: 'target', header: 'Target', render: (h) => `${h.target_type || 'all'}${h.target_value ? `: ${h.target_value}` : ''}` },
            { id: 'status', header: 'Status', render: (h) => <StatusBadge status={h.status || 'pending'} /> },
            { id: 'created', header: 'Created', render: (h) => (h.created_at ? formatDateTime(h.created_at) : '—') },
          ]}
          rowKey={(h) => h.id}
          emptyTitle="No notification history"
        />
      </div>

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
