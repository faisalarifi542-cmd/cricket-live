'use client';

import { type LucideIcon } from 'lucide-react';
import { cn } from '@/lib/utils';

type Props = {
  label: string;
  value: number | string;
  icon?: LucideIcon;
  hint?: string;
  tone?: 'default' | 'positive' | 'warning' | 'danger';
};

const toneClass = {
  default: 'text-cyan-200 bg-cyan-300/10',
  positive: 'text-emerald-200 bg-emerald-400/10',
  warning: 'text-amber-200 bg-amber-400/10',
  danger: 'text-red-200 bg-red-400/10',
};

export function StatCard({ label, value, icon: Icon, hint, tone = 'default' }: Props) {
  return (
    <div className="rounded-xl border border-line bg-panel/40 p-4">
      <div className="flex items-center justify-between">
        <div className="text-xs uppercase tracking-wide text-slate-400">{label}</div>
        {Icon && (
          <div className={cn('grid h-7 w-7 place-items-center rounded-lg', toneClass[tone])}>
            <Icon className="h-3.5 w-3.5" />
          </div>
        )}
      </div>
      <div className="mt-1.5 text-2xl font-semibold text-slate-50">{value}</div>
      {hint && <div className="mt-1 text-xs text-slate-500">{hint}</div>}
    </div>
  );
}
