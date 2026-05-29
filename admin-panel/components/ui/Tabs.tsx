'use client';

import { cn } from '@/lib/utils';

type Tab = { id: string; label: string; badge?: string | number };

type Props = {
  tabs: Tab[] | ReadonlyArray<Tab>;
  value: string;
  onChange: (id: string) => void;
  className?: string;
};

export function Tabs({ tabs, value, onChange, className }: Props) {
  return (
    <div
      className={cn(
        'inline-flex rounded-xl border border-line bg-white/5 p-1 text-sm',
        className,
      )}
    >
      {tabs.map((tab) => (
        <button
          key={tab.id}
          onClick={() => onChange(tab.id)}
          className={cn(
            'flex items-center gap-2 rounded-lg px-3 py-1.5 transition',
            tab.id === value
              ? 'bg-cyan-400/15 text-cyan-100 shadow-inner ring-1 ring-cyan-300/20'
              : 'text-slate-300 hover:bg-white/5 hover:text-white',
          )}
        >
          {tab.label}
          {tab.badge != null && tab.badge !== '' && (
            <span
              className={cn(
                'rounded-md px-1.5 py-0.5 text-[10px] font-semibold',
                tab.id === value
                  ? 'bg-cyan-300/30 text-cyan-50'
                  : 'bg-white/10 text-slate-300',
              )}
            >
              {tab.badge}
            </span>
          )}
        </button>
      ))}
    </div>
  );
}
