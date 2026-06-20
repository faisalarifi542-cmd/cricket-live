'use client';

import { Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'success';
type Size = 'sm' | 'md';

const variantClass: Record<Variant, string> = {
  primary:
    'bg-cyan-400 text-slate-950 hover:bg-cyan-300 disabled:bg-cyan-400/40 disabled:text-slate-700',
  secondary:
    'border border-line bg-white/5 text-slate-100 hover:bg-white/10 disabled:opacity-50',
  ghost:
    'text-slate-300 hover:bg-white/5 hover:text-white disabled:opacity-50',
  danger:
    'bg-red-500 text-white hover:bg-red-400 disabled:bg-red-500/40',
  success:
    'bg-emerald-500 text-white hover:bg-emerald-400 disabled:bg-emerald-500/40',
};

const sizeClass: Record<Size, string> = {
  sm: 'h-8 px-3 text-xs',
  md: 'h-10 px-4 text-sm',
};

type Props = React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: Variant;
  size?: Size;
  loading?: boolean;
  icon?: React.ReactNode;
};

export function Button({
  variant = 'primary',
  size = 'md',
  loading,
  icon,
  className,
  disabled,
  children,
  ...rest
}: Props) {
  return (
    <button
      {...rest}
      disabled={disabled || loading}
      className={cn(
        'inline-flex items-center justify-center gap-2 rounded-lg font-medium transition',
        variantClass[variant],
        sizeClass[size],
        loading && 'cursor-progress',
        className,
      )}
    >
      {loading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : icon}
      {children}
    </button>
  );
}
