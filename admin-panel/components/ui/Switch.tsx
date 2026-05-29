'use client';

import { cn } from '@/lib/utils';

type Props = {
  checked: boolean;
  onChange: (next: boolean) => void;
  disabled?: boolean;
  label?: string;
  description?: string;
};

export function Switch({ checked, onChange, disabled, label, description }: Props) {
  return (
    <label
      className={cn(
        'flex items-start gap-3',
        disabled ? 'cursor-not-allowed opacity-60' : 'cursor-pointer',
      )}
    >
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={cn(
          'relative mt-0.5 h-5 w-9 shrink-0 rounded-full border border-line transition',
          checked ? 'bg-cyan-400/80' : 'bg-white/10',
        )}
      >
        <span
          className={cn(
            'absolute top-0.5 h-4 w-4 rounded-full bg-white shadow transition',
            checked ? 'left-4' : 'left-0.5',
          )}
        />
      </button>
      {(label || description) && (
        <div className="flex-1">
          {label && (
            <div className="text-sm font-medium text-slate-200">{label}</div>
          )}
          {description && (
            <div className="text-xs text-slate-500">{description}</div>
          )}
        </div>
      )}
    </label>
  );
}
