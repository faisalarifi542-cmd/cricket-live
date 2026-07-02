'use client';

import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { toast } from 'sonner';
import { Eye, Pencil, Plus, RefreshCw, Radio } from 'lucide-react';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { EmptyState } from '@/components/ui/EmptyState';
import { LoadingSkeleton } from '@/components/ui/LoadingSkeleton';
import { streamsApi, type StreamSyncMatch, type StreamSyncResult } from '@/lib/api';

type Props = {
  open: boolean;
  onClose: () => void;
  canWrite: boolean;
  onAddStream: (match: StreamSyncMatch) => void;
  onEditStream: (streamId: number, match: StreamSyncMatch) => void;
};

function browserTimezone() {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  } catch {
    return 'UTC';
  }
}

export function SyncMatchesModal({ open, onClose, canWrite, onAddStream, onEditStream }: Props) {
  const router = useRouter();
  const [data, setData] = useState<StreamSyncResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const runSync = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await streamsApi.sync(browserTimezone());
      setData(res.data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sync failed');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (open) runSync();
  }, [open, runSync]);

  const matches = data?.matches || [];

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Sync Live & Upcoming Matches"
      description="Live now + matches starting today or tomorrow, straight from the provider. Pick a match to add its stream — details auto-fill."
      size="xl"
      footer={
        <>
          {data && (
            <span className="mr-auto text-xs text-slate-400">
              {data.counts.total} match{data.counts.total === 1 ? '' : 'es'} · {data.counts.live} live ·{' '}
              {data.counts.upcoming} upcoming · synced {new Date(data.syncedAt).toLocaleTimeString()} ({data.timezone})
            </span>
          )}
          <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={runSync} loading={loading}>
            Re-sync
          </Button>
          <Button variant="ghost" onClick={onClose}>
            Close
          </Button>
        </>
      }
    >
      {loading && !data ? (
        <LoadingSkeleton lines={6} />
      ) : error ? (
        <EmptyState
          title="Sync failed"
          description={error}
          action={<Button onClick={runSync} icon={<RefreshCw className="h-4 w-4" />}>Try again</Button>}
        />
      ) : matches.length === 0 ? (
        <EmptyState
          icon={<Radio className="h-5 w-5" />}
          title="No live or upcoming matches"
          description="There are no live matches and nothing scheduled for today or tomorrow. Try again closer to match time."
        />
      ) : (
        <div className="space-y-2">
          {data?.errors && data.errors.length > 0 && (
            <div className="rounded-lg border border-amber-400/30 bg-amber-400/10 px-3 py-2 text-xs text-amber-200">
              Some feeds were unavailable: {data.errors.join('; ')}
            </div>
          )}
          {matches.map((m) => (
            <div
              key={m.match_id}
              className="flex flex-col gap-3 rounded-xl border border-line bg-white/[0.03] p-3 sm:flex-row sm:items-center sm:justify-between"
            >
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <StatusBadge tone={m.phase === 'live' ? 'success' : 'info'}>
                    {m.phase === 'live' ? 'LIVE' : 'UPCOMING'}
                  </StatusBadge>
                  <span className="truncate font-semibold text-white">{m.matchup}</span>
                  <StreamStateBadge match={m} />
                </div>
                <div className="mt-1 truncate text-xs text-slate-400">
                  {[m.series_name, m.venue, m.start_time ? new Date(m.start_time).toLocaleString() : null]
                    .filter(Boolean)
                    .join(' · ')}
                </div>
                {m.status_text && <div className="mt-0.5 truncate text-[11px] text-slate-500">{m.status_text}</div>}
              </div>

              <div className="flex shrink-0 items-center gap-1.5">
                {m.has_stream && m.streams[0] && (
                  <>
                    <Button
                      size="sm"
                      variant="ghost"
                      icon={<Eye className="h-3.5 w-3.5" />}
                      onClick={() => router.push(`/streams/${m.streams[0].id}`)}
                    >
                      View
                    </Button>
                    {canWrite && (
                      <Button
                        size="sm"
                        variant="secondary"
                        icon={<Pencil className="h-3.5 w-3.5" />}
                        onClick={() => onEditStream(m.streams[0].id, m)}
                      >
                        Edit Stream
                      </Button>
                    )}
                  </>
                )}
                {!m.has_stream && canWrite && (
                  <Button size="sm" icon={<Plus className="h-3.5 w-3.5" />} onClick={() => onAddStream(m)}>
                    Add Stream
                  </Button>
                )}
                {!canWrite && !m.has_stream && (
                  <span className="text-xs text-slate-500">No stream</span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </Modal>
  );
}

function StreamStateBadge({ match }: { match: StreamSyncMatch }) {
  if (match.stream_status === 'published') {
    return <StatusBadge tone="success">Published</StatusBadge>;
  }
  if (match.stream_status === 'draft') {
    return <StatusBadge tone="warning">Stream Added</StatusBadge>;
  }
  return <StatusBadge tone="muted">No stream</StatusBadge>;
}
