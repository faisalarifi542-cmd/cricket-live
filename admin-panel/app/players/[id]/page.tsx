'use client';

import { useParams, useRouter } from 'next/navigation';
import { toast } from 'sonner';
import { ChevronLeft, RefreshCw, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { Button } from '@/components/ui/Button';
import { LoadingSkeleton } from '@/components/ui/LoadingSkeleton';
import { playersApi } from '@/lib/api';
import { useAuth, usePermissions, useResource } from '@/lib/hooks';

export default function PlayerDetailPage() {
  return (
    <AdminShell permission="players.view">
      <Detail />
    </AdminShell>
  );
}

function Detail() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const id = decodeURIComponent(params.id);
  const { user } = useAuth();
  const perms = usePermissions(user);
  const { data, loading, reload } = useResource(() => playersApi.get(id), [id]);
  const player = data?.data as Record<string, unknown> | undefined;

  if (loading) return <LoadingSkeleton lines={6} />;
  if (!player) return <div className="rounded-xl border border-line bg-panel/40 p-6 text-sm text-slate-400">Player not found.</div>;

  return (
    <>
      <PageHeader
        title={String(player.name ?? `Player ${id}`)}
        description={`Player ID ${id}`}
        right={
          <>
            <Button variant="ghost" icon={<ChevronLeft className="h-4 w-4" />} onClick={() => router.push('/players')}>
              Back
            </Button>
            {perms.can('players.write') && (
              <>
                <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={async () => { await playersApi.refresh(id); toast.success('Refreshed'); reload(); }}>
                  Refresh
                </Button>
                <Button variant="ghost" icon={<Trash2 className="h-4 w-4" />} onClick={async () => { await playersApi.cacheClear(id); toast.success('Cache cleared'); }}>
                  Clear cache
                </Button>
              </>
            )}
          </>
        }
      />
      <section className="rounded-2xl border border-line bg-panel/40 p-4">
        <h2 className="mb-3 text-sm font-semibold text-slate-100">Profile</h2>
        <dl className="grid grid-cols-2 gap-x-6 gap-y-3 text-sm">
          {Object.entries(player).map(([k, v]) => (
            <div key={k}>
              <dt className="text-[10px] uppercase tracking-wide text-slate-500">{k.replace(/_/g, ' ')}</dt>
              <dd className="mt-0.5 text-slate-100">
                {typeof v === 'object' ? <code className="font-mono text-xs">{JSON.stringify(v)}</code> : String(v ?? '—')}
              </dd>
            </div>
          ))}
        </dl>
      </section>
    </>
  );
}
