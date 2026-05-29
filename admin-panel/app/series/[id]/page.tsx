'use client';

import { useParams, useRouter } from 'next/navigation';
import { toast } from 'sonner';
import { ChevronLeft, RefreshCw, Star, EyeOff, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { Button } from '@/components/ui/Button';
import { LoadingSkeleton } from '@/components/ui/LoadingSkeleton';
import { seriesApi } from '@/lib/api';
import { useAuth, usePermissions, useResource } from '@/lib/hooks';
import { formatDate } from '@/lib/utils';

export default function SeriesDetailPage() {
  return (
    <AdminShell permission="series.view">
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
  const { data, loading, reload } = useResource(() => seriesApi.get(id), [id]);
  const series = data?.data as Record<string, unknown> | undefined;

  if (loading) return <LoadingSkeleton lines={6} />;
  if (!series) {
    return (
      <div className="rounded-xl border border-line bg-panel/40 p-6 text-sm text-slate-400">
        Series not found.
      </div>
    );
  }

  return (
    <>
      <PageHeader
        title={String(series.name ?? series.series_name ?? `Series ${id}`)}
        description={`Series ID ${id}`}
        right={
          <>
            <Button variant="ghost" icon={<ChevronLeft className="h-4 w-4" />} onClick={() => router.push('/series')}>
              Back
            </Button>
            {perms.can('series.write') && (
              <>
                <Button
                  variant="secondary"
                  icon={<Star className="h-4 w-4" />}
                  onClick={async () => {
                    await seriesApi.feature(id);
                    toast.success('Featured');
                    reload();
                  }}
                >
                  Feature
                </Button>
                <Button
                  variant="secondary"
                  icon={<EyeOff className="h-4 w-4" />}
                  onClick={async () => {
                    await seriesApi.hide(id, !series.is_hidden);
                    toast.success(series.is_hidden ? 'Unhidden' : 'Hidden');
                    reload();
                  }}
                >
                  {series.is_hidden ? 'Unhide' : 'Hide'}
                </Button>
                <Button
                  variant="secondary"
                  icon={<RefreshCw className="h-4 w-4" />}
                  onClick={async () => {
                    await seriesApi.refresh(id);
                    toast.success('Refreshed');
                    reload();
                  }}
                >
                  Refresh
                </Button>
                <Button
                  variant="ghost"
                  icon={<Trash2 className="h-4 w-4" />}
                  onClick={async () => {
                    await seriesApi.cacheClear(id);
                    toast.success('Cache cleared');
                  }}
                >
                  Clear cache
                </Button>
              </>
            )}
          </>
        }
      />

      <section className="rounded-2xl border border-line bg-panel/40 p-4">
        <h2 className="mb-3 text-sm font-semibold text-slate-100">Details</h2>
        <dl className="grid grid-cols-2 gap-x-6 gap-y-3 text-sm">
          {Object.entries(series).map(([k, v]) => (
            <div key={k}>
              <dt className="text-[10px] uppercase tracking-wide text-slate-500">{k.replace(/_/g, ' ')}</dt>
              <dd className="mt-0.5 text-slate-100">
                {typeof v === 'object' ? <code className="font-mono text-xs">{JSON.stringify(v)}</code> : String(formatMaybeDate(k, v))}
              </dd>
            </div>
          ))}
        </dl>
      </section>
    </>
  );
}

function formatMaybeDate(key: string, value: unknown) {
  if (typeof value === 'string' && /(_at|_date|_time)$/.test(key)) {
    return formatDate(value);
  }
  return value ?? '—';
}
