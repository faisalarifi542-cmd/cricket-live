'use client';

import { cn } from '@/lib/utils';
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
  emptyTitle?: string;
  emptyDescription?: string;
  rowKey: (row: T) => string | number;
  onRowClick?: (row: T) => void;
};

export function DataTable<T>({
  rows,
  columns,
  loading,
  emptyTitle = 'Nothing here yet',
  emptyDescription,
  rowKey,
  onRowClick,
}: Props<T>) {
  if (loading) return <LoadingSkeleton lines={6} />;
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
