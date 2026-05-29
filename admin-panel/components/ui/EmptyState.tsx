'use client';

import { Inbox } from 'lucide-react';

type Props = {
  title?: string;
  description?: string;
  icon?: React.ReactNode;
  action?: React.ReactNode;
};

export function EmptyState({ title = 'Nothing here yet', description, icon, action }: Props) {
  return (
    <div className="flex flex-col items-center justify-center rounded-xl border border-dashed border-line/80 bg-white/[0.02] px-6 py-12 text-center">
      <div className="grid h-10 w-10 place-items-center rounded-xl bg-white/5 text-slate-400">
        {icon || <Inbox className="h-5 w-5" />}
      </div>
      <h3 className="mt-4 text-sm font-semibold text-slate-100">{title}</h3>
      {description && (
        <p className="mt-1 max-w-md text-xs text-slate-400">{description}</p>
      )}
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
}
