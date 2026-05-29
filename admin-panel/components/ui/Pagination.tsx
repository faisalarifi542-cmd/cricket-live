'use client';

import { ChevronLeft, ChevronRight } from 'lucide-react';
import { Button } from './Button';

type Props = {
  page: number;
  pageCount: number;
  onChange: (page: number) => void;
  totalLabel?: string;
};

export function Pagination({ page, pageCount, onChange, totalLabel }: Props) {
  if (pageCount <= 1) return null;
  return (
    <div className="mt-4 flex items-center justify-between gap-3">
      <span className="text-xs text-slate-500">
        {totalLabel || `Page ${page} of ${pageCount}`}
      </span>
      <div className="flex items-center gap-2">
        <Button
          variant="secondary"
          size="sm"
          disabled={page <= 1}
          onClick={() => onChange(page - 1)}
          icon={<ChevronLeft className="h-3.5 w-3.5" />}
        >
          Previous
        </Button>
        <Button
          variant="secondary"
          size="sm"
          disabled={page >= pageCount}
          onClick={() => onChange(page + 1)}
        >
          Next
          <ChevronRight className="h-3.5 w-3.5" />
        </Button>
      </div>
    </div>
  );
}
