'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Plus, RefreshCw, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { Tabs } from '@/components/ui/Tabs';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { Button } from '@/components/ui/Button';
import { Field, Input } from '@/components/ui/Input';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { HomeSectionForm } from '@/components/forms/HomeSectionForm';
import { homeApi } from '@/lib/api';
import { useAuth, usePermissions, useResource } from '@/lib/hooks';
import { formatDateTime } from '@/lib/utils';

type Section = {
  id: number;
  slug: string;
  title: string;
  section_type: string;
  sort_order: number;
  is_active: number | boolean;
  starts_at?: string;
  ends_at?: string;
};

type Featured = { id: number; external_id?: string; title?: string; sort_order?: number };
type Banner = {
  id: number;
  placement: string;
  title?: string;
  image_url?: string;
  cta_url?: string;
  is_active?: number | boolean;
  sort_order?: number;
};

const TABS = [
  { id: 'sections', label: 'Sections' },
  { id: 'featured-matches', label: 'Featured matches' },
  { id: 'featured-series', label: 'Featured series' },
  { id: 'featured-news', label: 'Featured news' },
  { id: 'banners', label: 'Banners' },
] as const;

type TabId = (typeof TABS)[number]['id'];

export default function HomePage() {
  return (
    <AdminShell permission="home.view">
      <Inner />
    </AdminShell>
  );
}

function Inner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const canWrite = perms.can('home.write');
  const [tab, setTab] = useState<TabId>('sections');

  return (
    <>
      <PageHeader
        title="Home configuration"
        description="Configure the sections, featured matches/series/news, and promotional banners shown on the Flutter app home screen."
      />
      <div className="mb-4">
        <Tabs tabs={TABS} value={tab} onChange={(id) => setTab(id as TabId)} />
      </div>
      {tab === 'sections' && <SectionsTab canWrite={canWrite} />}
      {tab === 'featured-matches' && <FeaturedTab kind="featured-matches" placeholder="match external id" canWrite={canWrite} />}
      {tab === 'featured-series' && <FeaturedTab kind="featured-series" placeholder="series id" canWrite={canWrite} />}
      {tab === 'featured-news' && <FeaturedTab kind="featured-news" placeholder="news id" canWrite={canWrite} />}
      {tab === 'banners' && <BannersTab canWrite={canWrite} />}
    </>
  );
}

function SectionsTab({ canWrite }: { canWrite: boolean }) {
  const { data, loading, reload } = useResource(() => homeApi.listSections(), []);
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<Section | null>(null);
  const [toDelete, setToDelete] = useState<Section | null>(null);

  const rows = (data?.data || []) as Section[];

  const columns: Column<Section>[] = [
    { id: 'sort', header: '#', render: (s) => s.sort_order, width: '60px' },
    {
      id: 'name',
      header: 'Section',
      render: (s) => (
        <div>
          <div className="font-medium text-slate-100">{s.title}</div>
          <div className="text-[10px] uppercase tracking-wide text-slate-500">{s.slug} · {s.section_type}</div>
        </div>
      ),
    },
    { id: 'active', header: 'Active', render: (s) => (s.is_active ? 'Yes' : 'No') },
    { id: 'window', header: 'Window', render: (s) => `${s.starts_at ? formatDateTime(s.starts_at) : '—'} → ${s.ends_at ? formatDateTime(s.ends_at) : '—'}` },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (s) => (
        <div className="flex justify-end gap-1">
          {canWrite && (
            <>
              <Button size="sm" variant="ghost" onClick={() => { setEditing(s); setShowForm(true); }}>Edit</Button>
              <Button size="sm" variant="danger" icon={<Trash2 className="h-3.5 w-3.5" />} onClick={() => setToDelete(s)} />
            </>
          )}
        </div>
      ),
    },
  ];

  return (
    <>
      <div className="mb-3 flex justify-between">
        <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>Refresh</Button>
        {canWrite && (
          <Button icon={<Plus className="h-4 w-4" />} onClick={() => { setEditing(null); setShowForm(true); }}>Add section</Button>
        )}
      </div>
      <DataTable loading={loading} rows={rows} columns={columns} rowKey={(s) => s.id} emptyTitle="No sections configured" />
      <HomeSectionForm
        open={showForm}
        onClose={() => setShowForm(false)}
        initial={editing ? { ...editing, is_active: Boolean(editing.is_active) } : null}
        onSaved={reload}
      />
      <ConfirmDialog
        open={!!toDelete}
        onClose={() => setToDelete(null)}
        onConfirm={async () => {
          if (toDelete) {
            await homeApi.deleteSection(toDelete.id);
            toast.success('Section deleted');
            reload();
          }
        }}
        title="Delete section?"
        description="This removes the section from the home feed for all clients."
        destructive
        confirmLabel="Delete"
      />
    </>
  );
}

function FeaturedTab({
  kind,
  placeholder,
  canWrite,
}: {
  kind: 'featured-matches' | 'featured-series' | 'featured-news';
  placeholder: string;
  canWrite: boolean;
}) {
  const { data, loading, reload } = useResource(() => homeApi.listFeatured(kind), [kind]);
  const rows = (data?.data || []) as Featured[];
  const [externalId, setExternalId] = useState('');
  const [sortOrder, setSortOrder] = useState(100);
  const [toDelete, setToDelete] = useState<Featured | null>(null);

  async function add() {
    if (!externalId) return;
    await homeApi.addFeatured(kind, { external_id: externalId, sort_order: sortOrder });
    setExternalId('');
    toast.success('Added');
    reload();
  }

  const columns: Column<Featured>[] = [
    { id: 'sort', header: '#', render: (f) => f.sort_order ?? 100, width: '60px' },
    { id: 'id', header: 'External ID', render: (f) => f.external_id ?? '—' },
    { id: 'title', header: 'Title', render: (f) => f.title ?? '—' },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (f) =>
        canWrite ? (
          <Button size="sm" variant="danger" icon={<Trash2 className="h-3.5 w-3.5" />} onClick={() => setToDelete(f)} />
        ) : null,
    },
  ];

  return (
    <>
      {canWrite && (
        <div className="mb-3 flex flex-wrap items-end gap-3 rounded-xl border border-line bg-white/[0.04] p-3">
          <Field label="External ID">
            <Input value={externalId} onChange={(e) => setExternalId(e.target.value)} placeholder={placeholder} />
          </Field>
          <Field label="Sort">
            <Input type="number" value={sortOrder} onChange={(e) => setSortOrder(Number(e.target.value))} />
          </Field>
          <Button icon={<Plus className="h-4 w-4" />} onClick={add} disabled={!externalId}>Add</Button>
        </div>
      )}
      <DataTable loading={loading} rows={rows} columns={columns} rowKey={(f) => f.id} emptyTitle="Nothing featured yet" />
      <ConfirmDialog
        open={!!toDelete}
        onClose={() => setToDelete(null)}
        onConfirm={async () => {
          if (toDelete) {
            await homeApi.deleteFeatured(kind, toDelete.id);
            toast.success('Removed');
            reload();
          }
        }}
        title="Remove from featured?"
        destructive
      />
    </>
  );
}

function BannersTab({ canWrite }: { canWrite: boolean }) {
  const { data, loading, reload } = useResource(() => homeApi.listBanners(), []);
  const rows = (data?.data || []) as Banner[];
  const [form, setForm] = useState({ placement: 'home_top', title: '', image_url: '', cta_url: '', sort_order: 100 });
  const [toDelete, setToDelete] = useState<Banner | null>(null);

  async function add() {
    if (!form.image_url) {
      toast.error('Image URL required');
      return;
    }
    await homeApi.createBanner({ ...form, is_active: true });
    setForm({ placement: 'home_top', title: '', image_url: '', cta_url: '', sort_order: 100 });
    toast.success('Banner created');
    reload();
  }

  const columns: Column<Banner>[] = [
    {
      id: 'banner',
      header: 'Banner',
      render: (b) => (
        <div className="flex items-center gap-3">
          {b.image_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={b.image_url} alt={b.title ?? ''} className="h-10 w-16 rounded object-cover bg-white/5" />
          ) : null}
          <div>
            <div className="font-medium text-slate-100">{b.title || b.placement}</div>
            <div className="text-[10px] uppercase tracking-wide text-slate-500">{b.placement}</div>
          </div>
        </div>
      ),
    },
    { id: 'cta', header: 'CTA', render: (b) => b.cta_url ?? '—' },
    { id: 'sort', header: '#', render: (b) => b.sort_order ?? 100 },
    { id: 'active', header: 'Active', render: (b) => (b.is_active ? 'Yes' : 'No') },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (b) =>
        canWrite ? (
          <Button size="sm" variant="danger" icon={<Trash2 className="h-3.5 w-3.5" />} onClick={() => setToDelete(b)} />
        ) : null,
    },
  ];

  return (
    <>
      {canWrite && (
        <div className="mb-3 grid gap-3 rounded-xl border border-line bg-white/[0.04] p-3 md:grid-cols-5">
          <Field label="Placement">
            <Input value={form.placement} onChange={(e) => setForm((p) => ({ ...p, placement: e.target.value }))} />
          </Field>
          <Field label="Title">
            <Input value={form.title} onChange={(e) => setForm((p) => ({ ...p, title: e.target.value }))} />
          </Field>
          <Field label="Image URL">
            <Input value={form.image_url} onChange={(e) => setForm((p) => ({ ...p, image_url: e.target.value }))} />
          </Field>
          <Field label="CTA URL">
            <Input value={form.cta_url} onChange={(e) => setForm((p) => ({ ...p, cta_url: e.target.value }))} />
          </Field>
          <Field label="Sort">
            <Input type="number" value={form.sort_order} onChange={(e) => setForm((p) => ({ ...p, sort_order: Number(e.target.value) }))} />
          </Field>
          <div className="md:col-span-5">
            <Button icon={<Plus className="h-4 w-4" />} onClick={add}>Add banner</Button>
          </div>
        </div>
      )}
      <DataTable loading={loading} rows={rows} columns={columns} rowKey={(b) => b.id} emptyTitle="No banners" />
      <ConfirmDialog
        open={!!toDelete}
        onClose={() => setToDelete(null)}
        onConfirm={async () => {
          if (toDelete) {
            await homeApi.deleteBanner(toDelete.id);
            toast.success('Banner removed');
            reload();
          }
        }}
        title="Delete banner?"
        destructive
      />
    </>
  );
}
