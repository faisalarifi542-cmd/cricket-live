'use client';

import { useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Eye, EyeOff, Plus, RefreshCw, Star, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { SearchInput } from '@/components/ui/SearchInput';
import { FilterBar } from '@/components/ui/FilterBar';
import { Button } from '@/components/ui/Button';
import { StatusBadge } from '@/components/ui/StatusBadge';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { NewsForm } from '@/components/forms/NewsForm';
import { newsApi } from '@/lib/api';
import { useAuth, useDebouncedValue, usePermissions, useResource } from '@/lib/hooks';
import { formatDateTime } from '@/lib/utils';

type NewsRow = {
  id: number;
  headline: string;
  story_type?: string;
  source?: string;
  image_url?: string;
  is_featured?: number | boolean;
  is_hidden?: number | boolean;
  published_at?: string;
  created_at?: string;
};

export default function NewsPage() {
  return (
    <AdminShell permission="news.view">
      <Inner />
    </AdminShell>
  );
}

function Inner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const canWrite = perms.can('news.write');
  const [q, setQ] = useState('');
  const debouncedQ = useDebouncedValue(q, 250);
  const [type, setType] = useState('all');
  const [visibility, setVisibility] = useState('all');
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<NewsRow | null>(null);
  const [toDelete, setToDelete] = useState<NewsRow | null>(null);

  const { data, loading, reload } = useResource(() => newsApi.list(), []);
  const all = (data?.data || []) as NewsRow[];

  const types = useMemo(() => Array.from(new Set(all.map((n) => n.story_type).filter(Boolean))) as string[], [all]);

  const rows = useMemo(() => {
    const needle = debouncedQ.toLowerCase();
    return all.filter((n) => {
      if (type !== 'all' && n.story_type !== type) return false;
      if (visibility === 'visible' && n.is_hidden) return false;
      if (visibility === 'hidden' && !n.is_hidden) return false;
      if (visibility === 'featured' && !n.is_featured) return false;
      if (needle && !`${n.headline} ${n.source ?? ''}`.toLowerCase().includes(needle)) return false;
      return true;
    });
  }, [all, debouncedQ, type, visibility]);

  const columns: Column<NewsRow>[] = [
    {
      id: 'story',
      header: 'Story',
      render: (n) => (
        <div className="flex items-start gap-3">
          {n.image_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={n.image_url} alt="" className="h-10 w-16 rounded object-cover bg-white/5" />
          ) : null}
          <div>
            <div className="font-medium text-slate-100">{n.headline}</div>
            <div className="text-[10px] uppercase tracking-wide text-slate-500">{n.source ?? '—'} · {n.story_type ?? '—'}</div>
          </div>
        </div>
      ),
    },
    {
      id: 'flags',
      header: 'Flags',
      render: (n) => (
        <div className="flex gap-1">
          {n.is_featured ? <StatusBadge tone="info">Featured</StatusBadge> : null}
          {n.is_hidden ? <StatusBadge tone="muted">Hidden</StatusBadge> : null}
        </div>
      ),
    },
    { id: 'published', header: 'Published', render: (n) => formatDateTime(n.published_at || n.created_at) },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (n) =>
        canWrite ? (
          <div className="flex justify-end gap-1">
            <Button size="sm" variant="ghost" icon={<Star className="h-3.5 w-3.5" />} onClick={async () => { await newsApi.feature(n.id); toast.success('Toggled featured'); reload(); }} />
            <Button size="sm" variant="ghost" icon={n.is_hidden ? <Eye className="h-3.5 w-3.5" /> : <EyeOff className="h-3.5 w-3.5" />} onClick={async () => { await newsApi.hide(n.id); toast.success('Toggled hidden'); reload(); }} />
            <Button size="sm" variant="ghost" onClick={() => { setEditing(n); setShowForm(true); }}>Edit</Button>
            <Button size="sm" variant="danger" icon={<Trash2 className="h-3.5 w-3.5" />} onClick={() => setToDelete(n)} />
          </div>
        ) : null,
    },
  ];

  return (
    <>
      <PageHeader
        title="News"
        description="Manage cricket news — promote, hide, edit custom CricPro stories, and clear the public news cache."
        right={
          <>
            {canWrite && (
              <>
                <Button variant="secondary" onClick={async () => { await newsApi.cacheClear(); toast.success('News cache cleared'); }}>
                  Clear cache
                </Button>
                <Button icon={<Plus className="h-4 w-4" />} onClick={() => { setEditing(null); setShowForm(true); }}>
                  New story
                </Button>
              </>
            )}
          </>
        }
      />
      <SearchInput value={q} onChange={setQ} placeholder="Search headlines…" className="mb-3 max-w-md" />
      <FilterBar
        filters={[
          {
            type: 'select',
            id: 'type',
            label: 'Type',
            value: type,
            options: [{ id: 'all', label: 'All' }, ...types.map((t) => ({ id: t, label: t }))],
            onChange: setType,
          },
          {
            type: 'select',
            id: 'visibility',
            label: 'Visibility',
            value: visibility,
            options: [
              { id: 'all', label: 'All' },
              { id: 'visible', label: 'Visible' },
              { id: 'featured', label: 'Featured' },
              { id: 'hidden', label: 'Hidden' },
            ],
            onChange: setVisibility,
          },
        ]}
      />
      <DataTable loading={loading} rows={rows} columns={columns} rowKey={(n) => n.id} emptyTitle="No news stories" />

      <NewsForm
        open={showForm}
        onClose={() => setShowForm(false)}
        initial={editing ? { ...editing, is_featured: Boolean(editing.is_featured), is_hidden: Boolean(editing.is_hidden) } : null}
        onSaved={reload}
      />

      <ConfirmDialog
        open={!!toDelete}
        onClose={() => setToDelete(null)}
        onConfirm={async () => {
          if (toDelete) {
            await newsApi.delete(toDelete.id);
            toast.success('Deleted');
            reload();
          }
        }}
        title="Delete story?"
        description="This permanently removes the story."
        destructive
      />
    </>
  );
}
