'use client';

import { cn } from '@/lib/utils';

type SelectFilter = {
  type: 'select';
  id: string;
  label: string;
  value: string;
  options: { id: string; label: string }[] | ReadonlyArray<{ id: string; label: string }>;
  onChange: (value: string) => void;
};

type Filter = SelectFilter;

export function FilterBar({
  filters,
  right,
  className,
}: {
  filters: Filter[];
  right?: React.ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        'mb-4 flex flex-wrap items-end gap-3 rounded-xl border border-line bg-white/[0.04] p-3',
        className,
      )}
    >
      {filters.map((f) => (
        <label key={f.id} className="flex flex-col gap-1 text-xs">
          <span className="text-[10px] font-semibold uppercase tracking-wider text-slate-500">
            {f.label}
          </span>
          <select
            value={f.value}
            onChange={(e) => f.onChange(e.target.value)}
            className="h-9 rounded-lg border border-line bg-white/5 px-2 text-sm text-slate-100 outline-none focus:ring-2 focus:ring-cyan-300/30"
          >
            {f.options.map((opt) => (
              <option key={opt.id} value={opt.id} className="bg-slate-900">
                {opt.label}
              </option>
            ))}
          </select>
        </label>
      ))}
      {right && <div className="ml-auto flex items-center gap-2">{right}</div>}
    </div>
  );
}
