'use client';

import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import { useState } from 'react';
import { toast } from 'sonner';
import {
  ChevronLeft,
  EyeOff,
  Plus,
  RefreshCw,
  Star,
} from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { Button } from '@/components/ui/Button';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { LoadingSkeleton } from '@/components/ui/LoadingSkeleton';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { Modal } from '@/components/ui/Modal';
import { Field, Input, Textarea } from '@/components/ui/Input';
import { Switch } from '@/components/ui/Switch';
import { StreamForm } from '@/components/forms/StreamForm';
import { matchesApi, streamsApi, type StreamRow } from '@/lib/api';
import { useAuth, usePermissions, useResource } from '@/lib/hooks';
import { formatDateTime } from '@/lib/utils';

export default function MatchDetailPage() {
  return (
    <AdminShell permission="matches.view">
      <MatchDetail />
    </AdminShell>
  );
}

function MatchDetail() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const id = decodeURIComponent(params.id);
  const { user } = useAuth();
  const perms = usePermissions(user);
  const match = useResource(() => matchesApi.get(id), [id]);
  const streams = useResource(() => streamsApi.list({ match_external_id: id }), [id]);

  const [showOverride, setShowOverride] = useState(false);
  const [showStream, setShowStream] = useState(false);
  const [overrideForm, setOverrideForm] = useState({
    display_label: '',
    admin_note: '',
    is_featured: false,
    is_hidden: false,
  });

  const data = match.data?.data as
    | (Record<string, unknown> & {
        match?: Record<string, unknown>;
        override?: Record<string, unknown>;
      })
    | undefined;

  const m = (data?.match || data) as Record<string, unknown> | undefined;
  const override = data?.override as Record<string, unknown> | undefined;

  function openOverride() {
    setOverrideForm({
      display_label: String(override?.display_label ?? ''),
      admin_note: String(override?.admin_note ?? ''),
      is_featured: !!override?.is_featured,
      is_hidden: !!override?.is_hidden,
    });
    setShowOverride(true);
  }

  async function saveOverride() {
    await matchesApi.override(id, overrideForm);
    toast.success('Override saved');
    setShowOverride(false);
    match.reload();
  }

  async function refresh() {
    await matchesApi.refresh(id);
    toast.success('Match refreshed');
    match.reload();
    streams.reload();
  }

  if (match.loading) return <LoadingSkeleton lines={8} />;

  const streamRows = (streams.data?.data || []) as StreamRow[];
  const streamCols: Column<StreamRow>[] = [
    {
      id: 'server',
      header: 'Server',
      render: (r) => (
        <Link href={`/streams/${r.id}`} className="text-cyan-200 hover:underline">
          {r.server_name || r.label || `Stream #${r.id}`}
        </Link>
      ),
    },
    { id: 'type', header: 'Type', render: (r) => r.stream_type.toUpperCase() },
    { id: 'quality', header: 'Quality', render: (r) => r.quality },
    { id: 'status', header: 'Status', render: (r) => <StatusBadge status={r.status} /> },
    {
      id: 'flags',
      header: '',
      render: (r) => (
        <div className="flex gap-1">
          {r.is_active ? <StatusBadge tone="success">ON</StatusBadge> : <StatusBadge tone="muted">OFF</StatusBadge>}
          {r.is_premium && <StatusBadge tone="info">PREMIUM</StatusBadge>}
        </div>
      ),
    },
  ];

  return (
    <>
      <PageHeader
        title={(m?.team1 ?? m?.team_a) ? `${m?.team1 || m?.team_a} vs ${m?.team2 || m?.team_b}` : `Match ${id}`}
        description={String(m?.series_name ?? id)}
        right={
          <>
            <Button
              variant="ghost"
              icon={<ChevronLeft className="h-4 w-4" />}
              onClick={() => router.push('/matches')}
            >
              Back
            </Button>
            {perms.can('matches.write') && (
              <>
                <Button
                  variant="secondary"
                  icon={<Star className="h-4 w-4" />}
                  onClick={async () => {
                    await matchesApi.feature(id);
                    toast.success('Featured');
                    match.reload();
                  }}
                >
                  Feature
                </Button>
                <Button
                  variant="secondary"
                  icon={<EyeOff className="h-4 w-4" />}
                  onClick={async () => {
                    await matchesApi.hide(id, !override?.is_hidden);
                    toast.success(override?.is_hidden ? 'Unhidden' : 'Hidden');
                    match.reload();
                  }}
                >
                  {override?.is_hidden ? 'Unhide' : 'Hide'}
                </Button>
                <Button onClick={openOverride}>Manage override</Button>
              </>
            )}
            {perms.can('matches.refresh') && (
              <Button
                variant="secondary"
                icon={<RefreshCw className="h-4 w-4" />}
                onClick={refresh}
              >
                Refresh
              </Button>
            )}
          </>
        }
      />

      <div className="grid gap-4 md:grid-cols-3">
        <section className="md:col-span-2 rounded-2xl border border-line bg-panel/40 p-4">
          <h2 className="mb-3 text-sm font-semibold text-slate-100">Match info</h2>
          <dl className="grid grid-cols-2 gap-x-6 gap-y-3 text-sm">
            {[
              ['Match ID', id],
              ['Status', <StatusBadge key="s" status={String(m?.status ?? '')} />],
              ['Status text', String(m?.status_text ?? '—')],
              ['Start', formatDateTime(m?.start_time as string)],
              ['Venue', String(m?.venue ?? '—')],
              ['Series', String(m?.series_name ?? '—')],
              ['Featured', override?.is_featured ? 'Yes' : 'No'],
              ['Hidden', override?.is_hidden ? 'Yes' : 'No'],
            ].map(([k, v]) => (
              <div key={String(k)}>
                <dt className="text-[10px] uppercase tracking-wide text-slate-500">{k}</dt>
                <dd className="mt-0.5 text-slate-100">{v as React.ReactNode}</dd>
              </div>
            ))}
          </dl>
          {override?.display_label ? (
            <div className="mt-3 rounded-lg border border-cyan-300/20 bg-cyan-300/5 p-3 text-xs text-cyan-100">
              <div className="font-semibold">Display override</div>
              <div>{String(override.display_label)}</div>
              {override.admin_note ? (
                <div className="mt-1 text-cyan-200/70">{String(override.admin_note)}</div>
              ) : null}
            </div>
          ) : null}
        </section>

        <section className="rounded-2xl border border-line bg-panel/40 p-4">
          <div className="mb-3 flex items-center justify-between">
            <h2 className="text-sm font-semibold text-slate-100">Streams</h2>
            {perms.can('streams.write') && (
              <Button
                size="sm"
                icon={<Plus className="h-3.5 w-3.5" />}
                onClick={() => setShowStream(true)}
              >
                Add
              </Button>
            )}
          </div>
          <DataTable
            rows={streamRows}
            loading={streams.loading}
            columns={streamCols}
            rowKey={(r) => r.id}
            emptyTitle="No streams"
            emptyDescription="Add a stream URL to make this match playable."
          />
        </section>
      </div>

      <Modal
        open={showOverride}
        onClose={() => setShowOverride(false)}
        title="Match display override"
        description="These fields are stored separately from real cricket scores — never overwriting upstream data."
        size="lg"
        footer={
          <>
            <Button variant="ghost" onClick={() => setShowOverride(false)}>
              Cancel
            </Button>
            <Button onClick={saveOverride}>Save override</Button>
          </>
        }
      >
        <div className="grid gap-4 md:grid-cols-2">
          <Field label="Display label">
            <Input
              value={overrideForm.display_label}
              onChange={(e) => setOverrideForm((f) => ({ ...f, display_label: e.target.value }))}
              placeholder="Optional custom title shown in the app"
            />
          </Field>
          <div className="md:col-span-2">
            <Field label="Admin note">
              <Textarea
                value={overrideForm.admin_note}
                onChange={(e) => setOverrideForm((f) => ({ ...f, admin_note: e.target.value }))}
                placeholder="Internal-only note for other admins"
              />
            </Field>
          </div>
          <Switch
            label="Featured"
            description="Pin this match on the homepage"
            checked={overrideForm.is_featured}
            onChange={(v) => setOverrideForm((f) => ({ ...f, is_featured: v }))}
          />
          <Switch
            label="Hidden"
            description="Hide from public feeds"
            checked={overrideForm.is_hidden}
            onChange={(v) => setOverrideForm((f) => ({ ...f, is_hidden: v }))}
          />
        </div>
      </Modal>

      <StreamForm
        open={showStream}
        onClose={() => setShowStream(false)}
        defaultMatchId={id}
        onSaved={streams.reload}
      />
    </>
  );
}
