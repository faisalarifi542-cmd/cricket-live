'use client';

import { useParams, useRouter } from 'next/navigation';
import { useState } from 'react';
import { toast } from 'sonner';
import {
  ChevronLeft,
  HeartPulse,
  Pencil,
  RefreshCw,
  Trash2,
} from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { Button } from '@/components/ui/Button';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { LoadingSkeleton } from '@/components/ui/LoadingSkeleton';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { StreamForm } from '@/components/forms/StreamForm';
import { streamsApi, type StreamRow } from '@/lib/api';
import { useAuth, usePermissions, useResource } from '@/lib/hooks';
import { formatDateTime, formatRelative } from '@/lib/utils';

export default function StreamDetailPage() {
  return (
    <AdminShell permission="streams.view">
      <StreamDetail />
    </AdminShell>
  );
}

function StreamDetail() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const id = params.id;
  const { user } = useAuth();
  const perms = usePermissions(user);

  const stream = useResource(() => streamsApi.get(id), [id]);
  const health = useResource(() => streamsApi.health(id), [id]);

  const [showEdit, setShowEdit] = useState(false);
  const [toDelete, setToDelete] = useState(false);

  if (stream.loading) {
    return <LoadingSkeleton lines={8} />;
  }
  const data = stream.data?.data as StreamRow | undefined;
  if (!data) {
    return (
      <div className="rounded-xl border border-line bg-panel/40 p-6 text-center text-sm text-slate-400">
        Stream not found.
      </div>
    );
  }

  async function test() {
    const t = toast.loading('Testing…');
    try {
      const res = await streamsApi.test(id);
      toast.dismiss(t);
      toast[res.status === 'working' ? 'success' : 'error'](
        `Stream test: ${res.status} (${res.latency_ms ?? '—'}ms)`,
      );
      stream.reload();
      health.reload();
    } catch (err) {
      toast.dismiss(t);
      toast.error(err instanceof Error ? err.message : 'Failed');
    }
  }

  return (
    <>
      <PageHeader
        title={data.title || `Stream #${data.id}`}
        description={`Match ${data.match_external_id} · ${data.stream_type.toUpperCase()} · ${data.quality}`}
        right={
          <>
            <Button
              variant="ghost"
              icon={<ChevronLeft className="h-4 w-4" />}
              onClick={() => router.push('/streams')}
            >
              Back
            </Button>
            <Button
              variant="secondary"
              icon={<RefreshCw className="h-4 w-4" />}
              onClick={() => {
                stream.reload();
                health.reload();
              }}
            >
              Reload
            </Button>
            {perms.can('streams.test') && (
              <Button
                variant="secondary"
                icon={<HeartPulse className="h-4 w-4" />}
                onClick={test}
              >
                Run health test
              </Button>
            )}
            {perms.can('streams.write') && (
              <>
                <Button
                  icon={<Pencil className="h-4 w-4" />}
                  onClick={() => setShowEdit(true)}
                >
                  Edit
                </Button>
                <Button
                  variant="danger"
                  icon={<Trash2 className="h-4 w-4" />}
                  onClick={() => setToDelete(true)}
                >
                  Delete
                </Button>
              </>
            )}
          </>
        }
      />

      <div className="grid gap-4 md:grid-cols-3">
        <div className="md:col-span-2 space-y-4">
          <section className="rounded-2xl border border-line bg-panel/40 p-4">
            <h2 className="mb-3 text-sm font-semibold text-slate-100">Stream details</h2>
            <dl className="grid grid-cols-2 gap-x-6 gap-y-3 text-sm">
              {[
                ['Status', <StatusBadge key="status" status={data.status} />],
                ['Active', data.is_active ? 'Yes' : 'No'],
                ['Premium', data.is_premium ? 'Yes' : 'No'],
                ['DRM', (data as Record<string, unknown>).drm_enabled ? 'Yes' : 'No'],
                ['Priority', data.priority ?? '—'],
                ['Server', data.server_name || '—'],
                ['Label', data.label || '—'],
                ['Language', data.language || '—'],
                ['Starts at', formatDateTime((data as Record<string, unknown>).starts_at as string)],
                ['Ends at', formatDateTime((data as Record<string, unknown>).ends_at as string)],
                ['Updated', formatRelative(data.updated_at || data.created_at)],
              ].map(([k, v]) => (
                <div key={String(k)}>
                  <dt className="text-[10px] uppercase tracking-wide text-slate-500">{k}</dt>
                  <dd className="mt-0.5 text-slate-100">{v as React.ReactNode}</dd>
                </div>
              ))}
            </dl>
            <div className="mt-4 rounded-lg border border-line bg-slate-950/40 p-3">
              <div className="text-[10px] uppercase tracking-wide text-slate-500">Stream URL</div>
              <div className="mt-1 break-all font-mono text-xs text-cyan-200">{data.stream_url}</div>
            </div>
            <div className="mt-3 rounded-lg border border-line bg-white/[0.03] p-3">
              <div className="mb-1 flex items-center justify-between">
                <div className="text-[10px] uppercase tracking-wide text-slate-500">Publish notification</div>
                <PublishNotificationBadge data={data} />
              </div>
              <p className="text-xs text-slate-400">{publishNotificationHint(data)}</p>
            </div>
            {(data as Record<string, unknown>).notes ? (
              <div className="mt-3 rounded-lg border border-line bg-white/[0.04] p-3 text-xs text-slate-300">
                {String((data as Record<string, unknown>).notes)}
              </div>
            ) : null}
          </section>
        </div>

        <section className="rounded-2xl border border-line bg-panel/40 p-4">
          <h2 className="mb-3 text-sm font-semibold text-slate-100">Recent health checks</h2>
          {health.loading ? (
            <LoadingSkeleton lines={4} />
          ) : !health.data?.data?.length ? (
            <p className="text-xs text-slate-500">
              No health checks yet — run a test to populate this list.
            </p>
          ) : (
            <ul className="space-y-2 text-xs">
              {(health.data.data as Array<Record<string, unknown>>).slice(0, 12).map((h, i) => (
                <li
                  key={i}
                  className="flex items-center justify-between gap-2 rounded-lg border border-line bg-white/[0.03] px-3 py-2"
                >
                  <StatusBadge status={String(h.status)} />
                  <span className="text-slate-300">{String(h.latency_ms ?? '—')}ms</span>
                  <span className="text-slate-500">
                    {formatRelative(h.created_at as string)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>

      <StreamForm
        open={showEdit}
        onClose={() => setShowEdit(false)}
        initial={data as unknown as Parameters<typeof StreamForm>[0]['initial']}
        onSaved={stream.reload}
      />
      <ConfirmDialog
        open={toDelete}
        onClose={() => setToDelete(false)}
        onConfirm={async () => {
          await streamsApi.delete(id);
          toast.success('Stream deleted');
          router.push('/streams');
        }}
        title="Delete stream"
        description="This will permanently remove the stream URL and its health history."
        confirmLabel="Delete"
        destructive
      />
    </>
  );
}

function PublishNotificationBadge({ data }: { data: StreamRow }) {
  const n = data.publish_notification;
  if (!n) return <StatusBadge tone="muted">Not sent yet</StatusBadge>;
  if (n.status === 'sent') return <StatusBadge tone="success">Sent</StatusBadge>;
  if (n.status === 'failed') return <StatusBadge tone="danger">Failed</StatusBadge>;
  if (n.status === 'already_sent') return <StatusBadge tone="info">Already sent</StatusBadge>;
  return <StatusBadge tone="muted">Skipped</StatusBadge>;
}

function publishNotificationHint(data: StreamRow): string {
  const n = data.publish_notification;
  if (!n) {
    return data.published
      ? 'Published — a notification will be sent once on the first publish.'
      : 'No publish notification sent. It fires once when the stream becomes Published.';
  }
  if (n.status === 'sent') {
    return `Sent${n.sent_at ? ` at ${formatDateTime(n.sent_at)}` : ''}. It will not be re-sent for this stream.`;
  }
  if (n.status === 'failed') {
    return `Last attempt failed: ${n.error || 'unknown error'}.`;
  }
  if (n.status === 'already_sent') {
    return 'Already sent for this stream (deduplicated) — re-saving will not notify again.';
  }
  return 'Skipped — the stream is not Published or notifications are turned off.';
}
