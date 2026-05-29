'use client';

import { AlertTriangle, RefreshCw } from 'lucide-react';
import { cn } from '@/lib/utils';
import { Button } from './Button';
import { EmptyState } from './EmptyState';
import { LoadingSkeleton } from './LoadingSkeleton';

export type Column<T> = {
  id: string;
  header: string;
  className?: string;
  render: (row: T) => React.ReactNode;
  width?: string;
};

type Props<T> = {
  rows: T[];
  columns: Column<T>[];
  loading?: boolean;
  error?: string | null;
  onRetry?: () => void;
  emptyTitle?: string;
  emptyDescription?: string;
  rowKey: (row: T) => string | number;
  onRowClick?: (row: T) => void;
};

export function DataTable<T>({
  rows,
  columns,
  loading,
  error,
  onRetry,
  emptyTitle = 'Nothing here yet',
  emptyDescription,
  rowKey,
  onRowClick,
}: Props<T>) {
  if (loading && !rows.length) return <LoadingSkeleton lines={6} />;
  if (error && !rows.length) {
    return (
      <div className="flex flex-col items-center justify-center gap-3 rounded-xl border border-red-500/30 bg-red-500/[0.06] px-6 py-12 text-center">
        <div className="grid h-10 w-10 place-items-center rounded-xl bg-red-500/15 text-red-300">
          <AlertTriangle className="h-5 w-5" />
        </div>
        <div>
          <h3 className="text-sm font-semibold text-red-100">Couldn&apos;t load data</h3>
          <p className="mt-1 max-w-md text-xs text-red-200/80">{error}</p>
        </div>
        {onRetry && (
          <Button variant="secondary" size="sm" icon={<RefreshCw className="h-3.5 w-3.5" />} onClick={onRetry}>
            Try again
          </Button>
        )}
      </div>
    );
  }
  if (!rows.length)
    return <EmptyState title={emptyTitle} description={emptyDescription} />;

  return (
    <div className="overflow-x-auto rounded-xl border border-line">
      <table className="min-w-full divide-y divide-line text-sm">
        <thead className="bg-white/[0.04]">
          <tr>
            {columns.map((c) => (
              <th
                key={c.id}
                style={c.width ? { width: c.width } : undefined}
                className={cn(
                  'px-3 py-2.5 text-left text-[10px] font-semibold uppercase tracking-wider text-slate-400',
                  c.className,
                )}
              >
                {c.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-line/60 bg-panel/30">
          {rows.map((row) => (
            <tr
              key={rowKey(row)}
              onClick={onRowClick ? () => onRowClick(row) : undefined}
              className={cn(
                'transition hover:bg-cyan-300/[0.04]',
                onRowClick && 'cursor-pointer',
              )}
            >
              {columns.map((c) => (
                <td
                  key={c.id}
                  className={cn(
                    'px-3 py-2.5 text-slate-200 align-middle',
                    c.className,
                  )}
                >
                  {c.render(row)}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
