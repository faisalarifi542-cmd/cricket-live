'use client';

import { usePathname } from 'next/navigation';
import { ChevronRight } from 'lucide-react';
import { titleCase } from '@/lib/utils';

export function AdminBreadcrumbs() {
  const parts = usePathname().split('/').filter(Boolean);
  if (!parts.length) return null;
  return (
    <nav className="mb-5 flex items-center gap-1 text-xs text-slate-400">
      <span className="text-slate-500">Admin</span>
      {parts.map((part) => (
        <span key={part} className="flex items-center gap-1">
          <ChevronRight className="h-3 w-3 text-slate-600" />
          <span className="text-slate-300">{titleCase(part)}</span>
        </span>
      ))}
    </nav>
  );
}
