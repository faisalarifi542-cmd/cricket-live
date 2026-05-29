'use client';

import { forwardRef } from 'react';
import { cn } from '@/lib/utils';

export type InputProps = React.InputHTMLAttributes<HTMLInputElement> & {
  invalid?: boolean;
};

export const Input = forwardRef<HTMLInputElement, InputProps>(
  ({ className, invalid, ...rest }, ref) => (
    <input
      ref={ref}
      {...rest}
      className={cn(
        'h-10 w-full rounded-lg border bg-white/5 px-3 text-sm text-slate-100 outline-none transition placeholder:text-slate-500 focus:ring-2 focus:ring-cyan-300/30',
        invalid ? 'border-red-400/60' : 'border-line',
        className,
      )}
    />
  ),
);
Input.displayName = 'Input';

export const Textarea = forwardRef<
  HTMLTextAreaElement,
  React.TextareaHTMLAttributes<HTMLTextAreaElement> & { invalid?: boolean }
>(({ className, invalid, rows = 3, ...rest }, ref) => (
  <textarea
    ref={ref}
    rows={rows}
    {...rest}
    className={cn(
      'w-full rounded-lg border bg-white/5 px-3 py-2 text-sm text-slate-100 outline-none transition placeholder:text-slate-500 focus:ring-2 focus:ring-cyan-300/30',
      invalid ? 'border-red-400/60' : 'border-line',
      className,
    )}
  />
));
Textarea.displayName = 'Textarea';

export const Select = forwardRef<
  HTMLSelectElement,
  React.SelectHTMLAttributes<HTMLSelectElement> & { invalid?: boolean }
>(({ className, invalid, children, ...rest }, ref) => (
  <select
    ref={ref}
    {...rest}
    className={cn(
      'h-10 w-full rounded-lg border bg-white/5 px-3 text-sm text-slate-100 outline-none transition focus:ring-2 focus:ring-cyan-300/30',
      invalid ? 'border-red-400/60' : 'border-line',
      className,
    )}
  >
    {children}
  </select>
));
Select.displayName = 'Select';

export function Label({
  htmlFor,
  required,
  children,
  className,
}: {
  htmlFor?: string;
  required?: boolean;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <label
      htmlFor={htmlFor}
      className={cn(
        'mb-1.5 block text-xs font-medium uppercase tracking-wide text-slate-400',
        className,
      )}
    >
      {children}
      {required && <span className="ml-0.5 text-red-300">*</span>}
    </label>
  );
}

export function FieldError({ message }: { message?: string }) {
  if (!message) return null;
  return <p className="mt-1 text-xs text-red-300">{message}</p>;
}

export function Field({
  label,
  required,
  error,
  hint,
  className,
  children,
}: {
  label?: string;
  required?: boolean;
  error?: string;
  hint?: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <div className={className}>
      {label && <Label required={required}>{label}</Label>}
      {children}
      {hint && !error && <p className="mt-1 text-[11px] text-slate-500">{hint}</p>}
      <FieldError message={error} />
    </div>
  );
}
