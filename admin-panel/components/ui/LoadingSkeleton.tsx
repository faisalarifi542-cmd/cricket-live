'use client';

import { cn } from '@/lib/utils';

export function LoadingSkeleton({
  lines = 4,
  className,
}: {
  lines?: number;
  className?: string;
}) {
  return (
    <div className={cn('space-y-2', className)}>
      {Array.from({ length: lines }).map((_, i) => (
        <div
          key={i}
          className="h-9 w-full animate-pulse rounded-lg bg-white/[0.04]"
        />
      ))}
    </div>
  );
}
