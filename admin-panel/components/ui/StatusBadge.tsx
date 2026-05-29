'use client';

import { cn } from '@/lib/utils';

const tones: Record<string, string> = {
  success: 'border-emerald-400/30 bg-emerald-400/10 text-emerald-200',
  warning: 'border-amber-400/30 bg-amber-400/10 text-amber-200',
  danger: 'border-red-400/30 bg-red-400/10 text-red-200',
  info: 'border-cyan-300/30 bg-cyan-300/10 text-cyan-200',
  muted: 'border-line bg-white/5 text-slate-300',
};

type Tone = keyof typeof tones;

const STATUS_MAP: Record<string, Tone> = {
  working: 'success',
  ok: 'success',
  healthy: 'success',
  active: 'success',
  live: 'success',
  in_progress: 'success',
  innings_break: 'info',
  upcoming: 'info',
  scheduled: 'info',
  draft: 'muted',
  unknown: 'muted',
  inactive: 'muted',
  hidden: 'muted',
  sent: 'success',
  finished: 'muted',
  complete: 'muted',
  completed: 'muted',
  abandoned: 'warning',
  slow: 'warning',
  degraded: 'warning',
  down: 'danger',
  error: 'danger',
  revoked: 'danger',
  failed: 'danger',
};

export function StatusBadge({
  status,
  tone,
  className,
  children,
}: {
  status?: string | null;
  tone?: Tone;
  className?: string;
  children?: React.ReactNode;
}) {
  const resolved = tone || (status && STATUS_MAP[status.toLowerCase?.() ?? '']) || 'muted';
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide',
        tones[resolved],
        className,
      )}
    >
      {children || status || '—'}
    </span>
  );
}
