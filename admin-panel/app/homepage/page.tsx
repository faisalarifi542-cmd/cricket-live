'use client';

import { useEffect, useState } from 'react';
import { toast } from 'sonner';
import { Plus, RefreshCw, Trash2 } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { Tabs } from '@/components/ui/Tabs';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { Button } from '@/components/ui/Button';
import { Field, Input, Select } from '@/components/ui/Input';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { Modal } from '@/components/ui/Modal';
import { Switch } from '@/components/ui/Switch';
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
type FeaturedSeries = {
  id: number;
  series_external_id?: string | null;
  title?: string | null;
  subtitle?: string | null;
  date_range?: string | null;
  location?: string | null;
  image_url?: string | null;
  cta_url?: string | null;
  sort_order?: number;
  is_active?: number | boolean;
};
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
  { id: 'layout', label: 'Layout' },
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
      {tab === 'layout' && <LayoutTab canWrite={canWrite} />}
      {tab === 'sections' && <SectionsTab canWrite={canWrite} />}
      {tab === 'featured-matches' && <FeaturedTab kind="featured-matches" placeholder="match external id" canWrite={canWrite} />}
      {tab === 'featured-series' && <FeaturedSeriesTab canWrite={canWrite} />}
      {tab === 'featured-news' && <FeaturedTab kind="featured-news" placeholder="news id" canWrite={canWrite} />}
      {tab === 'banners' && <BannersTab canWrite={canWrite} />}
    </>
  );
}

function LayoutTab({ canWrite }: { canWrite: boolean }) {
  const { data, loading, error, reload } = useResource(() => homeApi.getLayout(), []);
  const [cfg, setCfg] = useState<any>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (data?.data) setCfg(JSON.parse(JSON.stringify(data.data)));
  }, [data]);

  if (loading && !cfg) return <div className="text-slate-400">Loading layout…</div>;
  if (error && !cfg) {
    return (
      <div className="rounded-xl border border-line bg-white/[0.04] p-4 text-slate-300">
        Failed to load layout. <Button size="sm" variant="ghost" onClick={reload}>Retry</Button>
      </div>
    );
  }
  if (!cfg) return null;

  const s = cfg.sections;
  function setSection(key: string, patch: Record<string, unknown>) {
    setCfg((p: any) => ({ ...p, sections: { ...p.sections, [key]: { ...p.sections[key], ...patch } } }));
  }
  function moveSection(index: number, dir: -1 | 1) {
    setCfg((p: any) => {
      const order = [...p.sectionOrder];
      const j = index + dir;
      if (j < 0 || j >= order.length) return p;
      [order[index], order[j]] = [order[j], order[index]];
      return { ...p, sectionOrder: order };
    });
  }

  async function save() {
    setSaving(true);
    try {
      await homeApi.saveLayout(cfg);
      toast.success('Home layout saved');
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  }

  const labels: Record<string, string> = {
    topFeatured: 'Top Featured carousel',
    mainMatches: 'Main Match List',
    featuredMatches: 'Featured Matches',
    featuredSeries: 'Featured Series',
  };

  return (
    <div className="space-y-5">
      {/* Section order */}
      <div className="rounded-xl border border-line bg-white/[0.04] p-4">
        <div className="mb-3 text-sm font-semibold text-slate-100">Section order</div>
        <div className="space-y-2">
          {cfg.sectionOrder.map((key: string, i: number) => (
            <div key={key} className="flex items-center justify-between rounded-lg border border-line bg-white/[0.02] px-3 py-2">
              <span className="text-sm text-slate-200">{i + 1}. {labels[key] ?? key}</span>
              {canWrite && (
                <div className="flex gap-1">
                  <Button size="sm" variant="ghost" onClick={() => moveSection(i, -1)} disabled={i === 0}>↑</Button>
                  <Button size="sm" variant="ghost" onClick={() => moveSection(i, 1)} disabled={i === cfg.sectionOrder.length - 1}>↓</Button>
                </div>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Top Featured */}
      <SectionCard title={labels.topFeatured}>
        <Switch checked={!!s.topFeatured.enabled} onChange={(v) => setSection('topFeatured', { enabled: v })} label="Enabled" />
        <div className="grid gap-3 md:grid-cols-2">
          <Field label="Source">
            <Select value={s.topFeatured.source} onChange={(e) => setSection('topFeatured', { source: e.target.value })}>
              <option value="auto">Auto</option>
              <option value="manual">Manual</option>
            </Select>
          </Field>
          <Field label="Show only">
            <Select value={s.topFeatured.filter} onChange={(e) => setSection('topFeatured', { filter: e.target.value })}>
              <option value="mixed">Mixed</option>
              <option value="live">Live only</option>
              <option value="upcoming">Upcoming only</option>
            </Select>
          </Field>
          <Field label="Max items">
            <Input type="number" value={s.topFeatured.maxItems} onChange={(e) => setSection('topFeatured', { maxItems: Number(e.target.value) })} />
          </Field>
          {s.topFeatured.source === 'manual' && (
            <Field label="Manual match IDs (comma-separated)">
              <Input
                value={(s.topFeatured.manualMatchIds || []).join(', ')}
                onChange={(e) => setSection('topFeatured', { manualMatchIds: e.target.value.split(',').map((x: string) => x.trim()).filter(Boolean) })}
              />
            </Field>
          )}
        </div>
        <Switch checked={!!s.topFeatured.showDots} onChange={(v) => setSection('topFeatured', { showDots: v })} label="Show carousel dots" />
      </SectionCard>

      {/* Main Match List */}
      <SectionCard title={labels.mainMatches}>
        <Switch checked={!!s.mainMatches.enabled} onChange={(v) => setSection('mainMatches', { enabled: v })} label="Enabled" />
        <div className="grid gap-3 md:grid-cols-2">
          <Field label="Default tab">
            <Select value={s.mainMatches.defaultTab} onChange={(e) => setSection('mainMatches', { defaultTab: e.target.value })}>
              <option value="live">Live</option>
              <option value="upcoming">Upcoming</option>
              <option value="finished">Finished</option>
            </Select>
          </Field>
          <Field label="Default category">
            <Select value={s.mainMatches.defaultCategory} onChange={(e) => setSection('mainMatches', { defaultCategory: e.target.value })}>
              <option value="all">All</option>
              <option value="international">International</option>
              <option value="league">League</option>
              <option value="domestic">Domestic</option>
            </Select>
          </Field>
          <Field label="Max list count">
            <Input type="number" value={s.mainMatches.maxItems} onChange={(e) => setSection('mainMatches', { maxItems: Number(e.target.value) })} />
          </Field>
        </div>
        <div className="grid gap-2 md:grid-cols-2">
          <Switch checked={!!s.mainMatches.showStatusTabs} onChange={(v) => setSection('mainMatches', { showStatusTabs: v })} label="Show status tabs" />
          <Switch checked={!!s.mainMatches.showCategoryFilter} onChange={(v) => setSection('mainMatches', { showCategoryFilter: v })} label="Show category filters" />
          <Switch checked={!!s.mainMatches.showWatchLive} onChange={(v) => setSection('mainMatches', { showWatchLive: v })} label="Show Watch Live button" />
          <Switch checked={!!s.mainMatches.showViewMatch} onChange={(v) => setSection('mainMatches', { showViewMatch: v })} label="Show View Match button" />
        </div>
      </SectionCard>

      {/* Featured Matches */}
      <SectionCard title={labels.featuredMatches}>
        <Switch checked={!!s.featuredMatches.enabled} onChange={(v) => setSection('featuredMatches', { enabled: v })} label="Enabled" />
        <div className="grid gap-3 md:grid-cols-2">
          <Field label="Section title">
            <Input value={s.featuredMatches.title} onChange={(e) => setSection('featuredMatches', { title: e.target.value })} />
          </Field>
          <Field label="Source">
            <Select value={s.featuredMatches.source} onChange={(e) => setSection('featuredMatches', { source: e.target.value })}>
              <option value="auto">Auto</option>
              <option value="manual">Manual</option>
            </Select>
          </Field>
          <Field label="Max visible count">
            <Input type="number" value={s.featuredMatches.maxItems} onChange={(e) => setSection('featuredMatches', { maxItems: Number(e.target.value) })} />
          </Field>
          {s.featuredMatches.source === 'manual' && (
            <Field label="Manual match IDs (comma-separated)">
              <Input
                value={(s.featuredMatches.manualMatchIds || []).join(', ')}
                onChange={(e) => setSection('featuredMatches', { manualMatchIds: e.target.value.split(',').map((x: string) => x.trim()).filter(Boolean) })}
              />
            </Field>
          )}
        </div>
        <Switch checked={!!s.featuredMatches.showSeeAll} onChange={(v) => setSection('featuredMatches', { showSeeAll: v })} label="Show “See All”" />
      </SectionCard>

      {/* Featured Series */}
      <SectionCard title={labels.featuredSeries}>
        <Switch checked={!!s.featuredSeries.enabled} onChange={(v) => setSection('featuredSeries', { enabled: v })} label="Enabled" />
        <div className="grid gap-3 md:grid-cols-2">
          <Field label="Section title">
            <Input value={s.featuredSeries.title} onChange={(e) => setSection('featuredSeries', { title: e.target.value })} />
          </Field>
          <Field label="Source">
            <Select value={s.featuredSeries.source} onChange={(e) => setSection('featuredSeries', { source: e.target.value })}>
              <option value="manual">Manual</option>
              <option value="auto">Auto</option>
            </Select>
          </Field>
          <Field label="Max visible count">
            <Input type="number" value={s.featuredSeries.maxItems} onChange={(e) => setSection('featuredSeries', { maxItems: Number(e.target.value) })} />
          </Field>
        </div>
        <Switch checked={!!s.featuredSeries.showSeeAll} onChange={(v) => setSection('featuredSeries', { showSeeAll: v })} label="Show “See All”" />
        <p className="text-xs text-slate-500">Manage the actual series entries in the “Featured series” tab.</p>
      </SectionCard>

      {canWrite && (
        <div className="flex justify-end">
          <Button onClick={save} loading={saving}>Save layout</Button>
        </div>
      )}
    </div>
  );
}

function SectionCard({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-line bg-white/[0.04] p-4">
      <div className="mb-3 text-sm font-semibold text-slate-100">{title}</div>
      <div className="space-y-3">{children}</div>
    </div>
  );
}

function SectionsTab({ canWrite }: { canWrite: boolean }) {
  const { data, loading, error, reload } = useResource(() => homeApi.listSections(), []);
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
      <DataTable loading={loading} error={error} onRetry={reload} rows={rows} columns={columns} rowKey={(s) => s.id} emptyTitle="No sections configured" />
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
  const { data, loading, error, reload } = useResource(() => homeApi.listFeatured(kind), [kind]);
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
      <DataTable loading={loading} error={error} onRetry={reload} rows={rows} columns={columns} rowKey={(f) => f.id} emptyTitle="Nothing featured yet" />
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

function FeaturedSeriesTab({ canWrite }: { canWrite: boolean }) {
  const { data, loading, error, reload } = useResource(() => homeApi.listFeatured('featured-series'), []);
  const rows = (data?.data || []) as FeaturedSeries[];
  const [showForm, setShowForm] = useState(false);
  const [editing, setEditing] = useState<FeaturedSeries | null>(null);
  const [toDelete, setToDelete] = useState<FeaturedSeries | null>(null);

  const columns: Column<FeaturedSeries>[] = [
    { id: 'sort', header: '#', render: (s) => s.sort_order ?? 100, width: '60px' },
    {
      id: 'series',
      header: 'Series',
      render: (s) => (
        <div className="flex items-center gap-3">
          {s.image_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={s.image_url} alt={s.title ?? ''} className="h-10 w-16 rounded object-cover bg-white/5" />
          ) : null}
          <div>
            <div className="font-medium text-slate-100">{s.title || '—'}</div>
            <div className="text-[10px] uppercase tracking-wide text-slate-500">
              {s.date_range || '—'}{s.location ? ` · ${s.location}` : ''}
            </div>
          </div>
        </div>
      ),
    },
    { id: 'link', header: 'Series ID', render: (s) => s.series_external_id || '—' },
    { id: 'active', header: 'Active', render: (s) => (s.is_active ? 'Yes' : 'No') },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (s) =>
        canWrite ? (
          <div className="flex justify-end gap-1">
            <Button size="sm" variant="ghost" onClick={() => { setEditing(s); setShowForm(true); }}>Edit</Button>
            <Button size="sm" variant="danger" icon={<Trash2 className="h-3.5 w-3.5" />} onClick={() => setToDelete(s)} />
          </div>
        ) : null,
    },
  ];

  return (
    <>
      <div className="mb-3 flex justify-between">
        <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>Refresh</Button>
        {canWrite && (
          <Button icon={<Plus className="h-4 w-4" />} onClick={() => { setEditing(null); setShowForm(true); }}>Add featured series</Button>
        )}
      </div>
      <DataTable loading={loading} error={error} onRetry={reload} rows={rows} columns={columns} rowKey={(s) => s.id} emptyTitle="No featured series yet" emptyDescription="Add a series manually with a poster, name, date range and location." />
      <FeaturedSeriesForm
        open={showForm}
        onClose={() => setShowForm(false)}
        initial={editing}
        onSaved={reload}
      />
      <ConfirmDialog
        open={!!toDelete}
        onClose={() => setToDelete(null)}
        onConfirm={async () => {
          if (toDelete) {
            await homeApi.deleteFeatured('featured-series', toDelete.id);
            toast.success('Removed');
            reload();
          }
        }}
        title="Remove featured series?"
        destructive
      />
    </>
  );
}

function FeaturedSeriesForm({
  open,
  onClose,
  initial,
  onSaved,
}: {
  open: boolean;
  onClose: () => void;
  initial: FeaturedSeries | null;
  onSaved: () => void;
}) {
  const isEdit = !!initial?.id;
  const [form, setForm] = useState({
    title: '',
    series_external_id: '',
    date_range: '',
    location: '',
    image_url: '',
    cta_url: '',
    sort_order: 100,
    is_active: true,
  });
  const [loading, setLoading] = useState(false);

  // Re-seed when the modal opens for a different row.
  useEffect(() => {
    if (open) {
      setForm({
        title: initial?.title ?? '',
        series_external_id: initial?.series_external_id ?? '',
        date_range: initial?.date_range ?? '',
        location: initial?.location ?? '',
        image_url: initial?.image_url ?? '',
        cta_url: initial?.cta_url ?? '',
        sort_order: initial?.sort_order ?? 100,
        is_active: initial?.is_active != null ? Boolean(initial.is_active) : true,
      });
    }
  }, [open, initial]);

  function update<K extends keyof typeof form>(k: K, v: (typeof form)[K]) {
    setForm((p) => ({ ...p, [k]: v }));
  }

  async function submit() {
    if (!form.title.trim() && !form.series_external_id.trim()) {
      toast.error('Title or series ID required');
      return;
    }
    setLoading(true);
    try {
      const body = {
        title: form.title.trim() || null,
        series_external_id: form.series_external_id.trim() || null,
        date_range: form.date_range.trim() || null,
        location: form.location.trim() || null,
        image_url: form.image_url.trim() || null,
        cta_url: form.cta_url.trim() || null,
        sort_order: form.sort_order,
        is_active: form.is_active,
      };
      if (isEdit && initial?.id) {
        await homeApi.updateFeaturedSeries(initial.id, body);
        toast.success('Featured series updated');
      } else {
        await homeApi.addFeaturedSeries(body);
        toast.success('Featured series added');
      }
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    } finally {
      setLoading(false);
    }
  }

  return (
    <Modal
      open={open}
      onClose={loading ? () => {} : onClose}
      title={isEdit ? 'Edit featured series' : 'New featured series'}
      description="Manually showcase a series on the app home screen. Only the title (or a series ID) is required; everything else is optional."
      size="lg"
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={loading}>Cancel</Button>
          <Button onClick={submit} loading={loading}>{isEdit ? 'Save' : 'Add'}</Button>
        </>
      }
    >
      <div className="grid gap-4 md:grid-cols-2">
        <Field label="Series name / title" required>
          <Input value={form.title} onChange={(e) => update('title', e.target.value)} placeholder="ICC Men's T20 World Cup 2026" />
        </Field>
        <Field label="Date range">
          <Input value={form.date_range} onChange={(e) => update('date_range', e.target.value)} placeholder="Jun – Jul 2026" />
        </Field>
        <Field label="Location / country">
          <Input value={form.location} onChange={(e) => update('location', e.target.value)} placeholder="India & Sri Lanka" />
        </Field>
        <Field label="Series ID (optional, for deep link)">
          <Input value={form.series_external_id} onChange={(e) => update('series_external_id', e.target.value)} placeholder="e.g. 9237" />
        </Field>
        <Field label="Poster image URL" className="md:col-span-2">
          <Input value={form.image_url} onChange={(e) => update('image_url', e.target.value)} placeholder="https://…/poster.png" />
        </Field>
        <Field label="CTA URL (optional)">
          <Input value={form.cta_url} onChange={(e) => update('cta_url', e.target.value)} />
        </Field>
        <Field label="Sort order">
          <Input type="number" value={form.sort_order} onChange={(e) => update('sort_order', Number(e.target.value))} />
        </Field>
      </div>
      {form.image_url ? (
        <div className="mt-4">
          <div className="mb-1 text-xs text-slate-500">Preview</div>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={form.image_url} alt="preview" className="h-24 w-44 rounded-lg object-cover bg-white/5 border border-line" />
        </div>
      ) : null}
      <div className="mt-3">
        <Switch
          checked={form.is_active}
          onChange={(v) => update('is_active', v)}
          label="Active"
          description="Inactive series are hidden from the app home screen."
        />
      </div>
    </Modal>
  );
}

function BannersTab({ canWrite }: { canWrite: boolean }) {
  const { data, loading, error, reload } = useResource(() => homeApi.listBanners(), []);
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
      <DataTable loading={loading} error={error} onRetry={reload} rows={rows} columns={columns} rowKey={(b) => b.id} emptyTitle="No banners" />
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
