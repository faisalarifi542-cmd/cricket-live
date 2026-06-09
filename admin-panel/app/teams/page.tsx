'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { Edit, ImagePlus, Plus, RefreshCw, Trash2, Upload } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { SearchInput } from '@/components/ui/SearchInput';
import { Button } from '@/components/ui/Button';
import { Field, Input } from '@/components/ui/Input';
import { Modal } from '@/components/ui/Modal';
import { teamsApi } from '@/lib/api';
import { useAuth, useDebouncedValue, usePermissions, useResource } from '@/lib/hooks';

type Team = {
  id?: number;
  team_id?: string | number;
  external_id?: string | number | null;
  name?: string;
  short_name?: string;
  country?: string | null;
  logo_url?: string | null;
  cricbuzz_logo_url?: string | null;
  team_type?: string | null;
  is_active?: boolean | number;
};

type TeamFormState = {
  name: string;
  short_name: string;
  external_id: string;
  country: string;
  team_type: string;
  logo_url: string;
  cricbuzz_logo_url: string;
  is_active: boolean;
};

const emptyForm: TeamFormState = {
  name: '',
  short_name: '',
  external_id: '',
  country: '',
  team_type: 'international',
  logo_url: '',
  cricbuzz_logo_url: '',
  is_active: true,
};

function teamId(team: Team) {
  return String(team.id ?? team.team_id ?? team.external_id ?? '');
}

function formFromTeam(team: Team | null): TeamFormState {
  if (!team) return emptyForm;
  return {
    name: team.name ?? '',
    short_name: team.short_name ?? '',
    external_id: String(team.external_id ?? ''),
    country: team.country ?? '',
    team_type: team.team_type ?? 'international',
    logo_url: team.logo_url ?? '',
    cricbuzz_logo_url: team.cricbuzz_logo_url ?? '',
    is_active: team.is_active !== false && team.is_active !== 0,
  };
}

export default function TeamsPage() {
  return (
    <AdminShell permission="teams.view">
      <TeamsInner />
    </AdminShell>
  );
}

function TeamsInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const [q, setQ] = useState('');
  const [savingSync, setSavingSync] = useState(false);
  const [formTeam, setFormTeam] = useState<Team | 'new' | null>(null);
  const [logoTeam, setLogoTeam] = useState<Team | null>(null);
  const debouncedQ = useDebouncedValue(q, 250);
  const { data, loading, error, reload } = useResource(() => teamsApi.list(), []);
  const all = (data?.data || []) as Team[];

  const rows = useMemo(() => {
    const needle = debouncedQ.toLowerCase();
    if (!needle) return all;
    return all.filter((t) =>
      `${t.name ?? ''} ${t.short_name ?? ''} ${t.country ?? ''} ${t.external_id ?? ''}`.toLowerCase().includes(needle),
    );
  }, [all, debouncedQ]);

  async function syncTeams() {
    setSavingSync(true);
    try {
      const res = await teamsApi.syncFromApi();
      toast.success(`Synced ${res.inserted} new, ${res.updated} updated`);
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Sync failed');
    } finally {
      setSavingSync(false);
    }
  }

  const columns: Column<Team>[] = [
    {
      id: 'team',
      header: 'Team',
      render: (t) => {
        const id = teamId(t);
        return (
          <Link href={`/teams/${encodeURIComponent(id)}`} className="flex items-center gap-3">
            <TeamLogoPreview team={t} size="sm" />
            <div>
              <div className="font-medium text-slate-100">{t.name ?? '-'}</div>
              <div className="text-[10px] uppercase tracking-wide text-slate-500">
                {t.short_name || t.country || t.external_id || '-'}
              </div>
            </div>
          </Link>
        );
      },
    },
    {
      id: 'type',
      header: 'Type',
      render: (t) => <span className="text-xs capitalize text-slate-300">{t.team_type || 'international'}</span>,
    },
    {
      id: 'logo',
      header: 'Admin logo',
      render: (t) => (
        <span className={t.logo_url ? 'text-xs text-emerald-400' : 'text-xs text-slate-500'}>
          {t.logo_url ? 'Set' : 'Not set'}
        </span>
      ),
    },
    {
      id: 'status',
      header: 'Status',
      render: (t) => (
        <span className={t.is_active === false || t.is_active === 0 ? 'text-xs text-rose-400' : 'text-xs text-emerald-400'}>
          {t.is_active === false || t.is_active === 0 ? 'Inactive' : 'Active'}
        </span>
      ),
    },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (t) => {
        const id = teamId(t);
        return (
          <div className="flex flex-wrap items-center justify-end gap-1">
            {perms.can('teams.write') && (
              <>
                <Button size="sm" variant="ghost" icon={<Edit className="h-3.5 w-3.5" />} onClick={() => setFormTeam(t)}>
                  Edit
                </Button>
                <Button size="sm" variant="ghost" icon={<ImagePlus className="h-3.5 w-3.5" />} onClick={() => setLogoTeam(t)}>
                  Logo
                </Button>
                <Button size="sm" variant="ghost" icon={<RefreshCw className="h-3.5 w-3.5" />} onClick={async () => { await teamsApi.refresh(id); toast.success('Team refreshed'); reload(); }}>
                  Refresh
                </Button>
                <Button size="sm" variant="ghost" icon={<Trash2 className="h-3.5 w-3.5" />} onClick={async () => { await teamsApi.delete(id); toast.success('Team disabled'); reload(); }}>
                  Disable
                </Button>
              </>
            )}
          </div>
        );
      },
    },
  ];

  return (
    <>
      <PageHeader
        title="Teams"
        description="Search and manage cricket teams. Add teams manually, sync from API data, and upload admin logos that the app uses before Cricbuzz or local fallbacks."
        right={
          <div className="flex flex-wrap gap-2">
            {perms.can('teams.write') && (
              <>
                <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={syncTeams} loading={savingSync}>
                  Sync Teams
                </Button>
                <Button icon={<Plus className="h-4 w-4" />} onClick={() => setFormTeam('new')}>
                  Add Team
                </Button>
              </>
            )}
            <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>
              Refresh
            </Button>
          </div>
        }
      />
      <SearchInput value={q} onChange={setQ} placeholder="Search teams..." className="mb-3 max-w-md" />
      {!loading && !error && all.length === 0 ? (
        <div className="rounded-2xl border border-line bg-panel p-8 text-center">
          <div className="mx-auto mb-3 grid h-12 w-12 place-items-center rounded-full bg-white/5 text-cyan">
            <Plus className="h-5 w-5" />
          </div>
          <h2 className="text-lg font-semibold text-slate-100">No teams found</h2>
          <p className="mx-auto mt-2 max-w-xl text-sm text-slate-400">
            Add a team manually or sync teams from live, upcoming, recent, and stored match data.
          </p>
          {perms.can('teams.write') && (
            <div className="mt-5 flex flex-wrap justify-center gap-2">
              <Button icon={<Plus className="h-4 w-4" />} onClick={() => setFormTeam('new')}>
                Add Team
              </Button>
              <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={syncTeams} loading={savingSync}>
                Sync Teams from API
              </Button>
            </div>
          )}
        </div>
      ) : (
        <DataTable loading={loading} error={error} onRetry={reload} rows={rows} columns={columns} rowKey={(t) => teamId(t) || String(t.name)} emptyTitle="No teams found" />
      )}
      <TeamFormDialog
        team={formTeam}
        onClose={() => setFormTeam(null)}
        onSaved={() => {
          setFormTeam(null);
          reload();
        }}
      />
      <TeamLogoDialog
        team={logoTeam}
        onClose={() => setLogoTeam(null)}
        onSaved={() => {
          setLogoTeam(null);
          reload();
        }}
      />
    </>
  );
}

function TeamLogoPreview({ team, size = 'lg' }: { team: Team; size?: 'sm' | 'lg' }) {
  const url = team.logo_url || team.cricbuzz_logo_url || '';
  const cls = size === 'sm' ? 'h-8 w-8 text-[10px]' : 'h-16 w-16 text-xs';
  if (url) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={url} alt={team.name ?? ''} className={`${cls} rounded-full border border-line object-cover bg-white/5`} />;
  }
  return (
    <div className={`${cls} grid place-items-center rounded-full border border-line bg-white/5 uppercase text-slate-400`}>
      {(team.short_name || team.name || '?').slice(0, 3)}
    </div>
  );
}

function TeamFormDialog({
  team,
  onClose,
  onSaved,
}: {
  team: Team | 'new' | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [form, setForm] = useState<TeamFormState>(emptyForm);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const isNew = team === 'new';
  const open = !!team;

  useEffect(() => {
    setForm(team && team !== 'new' ? formFromTeam(team) : emptyForm);
  }, [team]);

  function patch(values: Partial<TeamFormState>) {
    setForm((prev) => ({ ...prev, ...values }));
  }

  async function upload(file: File) {
    if (!file.type.startsWith('image/')) {
      toast.error('Please choose an image file');
      return;
    }
    setUploading(true);
    try {
      const dataUrl = await readFileAsDataUrl(file);
      const res = await teamsApi.uploadFlag(dataUrl, file.type);
      patch({ logo_url: res.url });
      toast.success('Logo uploaded');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = '';
    }
  }

  async function save() {
    if (!form.name.trim()) {
      toast.error('Team name is required');
      return;
    }
    setSaving(true);
    const body = {
      name: form.name.trim(),
      short_name: form.short_name.trim() || null,
      external_id: form.external_id.trim() || null,
      country: form.country.trim() || null,
      team_type: form.team_type.trim() || 'international',
      logo_url: form.logo_url.trim() || null,
      cricbuzz_logo_url: form.cricbuzz_logo_url.trim() || null,
      is_active: form.is_active,
    };
    try {
      if (isNew) {
        await teamsApi.create(body);
        toast.success('Team added');
      } else {
        const id = teamId(team as Team);
        await teamsApi.update(id, body);
        toast.success('Team updated');
      }
      onSaved();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to save team');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal
      open={open}
      onClose={saving ? () => {} : onClose}
      title={isNew ? 'Add Team' : `Edit Team - ${(team as Team)?.name ?? ''}`}
      description="Manage the team identity and admin logo used by the app."
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={saving}>Cancel</Button>
          <Button onClick={save} loading={saving}>Save Team</Button>
        </>
      }
    >
      <div className="grid gap-4 md:grid-cols-2">
        <Field label="Team name">
          <Input value={form.name} onChange={(e) => patch({ name: e.target.value })} placeholder="India" />
        </Field>
        <Field label="Short code">
          <Input value={form.short_name} onChange={(e) => patch({ short_name: e.target.value.toUpperCase() })} placeholder="IND" />
        </Field>
        <Field label="External / Cricbuzz ID">
          <Input value={form.external_id} onChange={(e) => patch({ external_id: e.target.value })} placeholder="2" />
        </Field>
        <Field label="Country">
          <Input value={form.country} onChange={(e) => patch({ country: e.target.value })} placeholder="India" />
        </Field>
        <Field label="Team type">
          <Input value={form.team_type} onChange={(e) => patch({ team_type: e.target.value })} placeholder="international" />
        </Field>
        <Field label="Active">
          <label className="flex h-10 items-center gap-2 rounded-xl border border-line bg-white/5 px-3 text-sm text-slate-200">
            <input type="checkbox" checked={form.is_active} onChange={(e) => patch({ is_active: e.target.checked })} />
            Active team
          </label>
        </Field>
        <Field label="Logo URL">
          <div className="flex gap-2">
            <Input value={form.logo_url} onChange={(e) => patch({ logo_url: e.target.value })} placeholder="Paste URL or upload" className="flex-1" />
            <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) upload(f); }} />
            <Button type="button" variant="secondary" icon={<Upload className="h-4 w-4" />} loading={uploading} onClick={() => fileRef.current?.click()}>
              Upload
            </Button>
          </div>
        </Field>
        <Field label="Cricbuzz logo URL">
          <Input value={form.cricbuzz_logo_url} onChange={(e) => patch({ cricbuzz_logo_url: e.target.value })} placeholder="Provider logo fallback" />
        </Field>
      </div>
    </Modal>
  );
}

function TeamLogoDialog({
  team,
  onClose,
  onSaved,
}: {
  team: Team | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [url, setUrl] = useState('');
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  const open = !!team;
  const key = String(team?.id ?? team?.team_id ?? '');
  useEffect(() => {
    if (team) setUrl(team.logo_url ?? '');
  }, [key, team]);

  async function handleUpload(file: File) {
    if (!file.type.startsWith('image/')) {
      toast.error('Please choose an image file');
      return;
    }
    setUploading(true);
    try {
      const dataUrl = await readFileAsDataUrl(file);
      const res = await teamsApi.uploadFlag(dataUrl, file.type);
      setUrl(res.url);
      toast.success('Logo uploaded');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = '';
    }
  }

  async function save() {
    if (!team) return;
    const id = teamId(team);
    if (!id) {
      toast.error('Missing team id');
      return;
    }
    setSaving(true);
    try {
      await teamsApi.update(id, { logo_url: url.trim() || null });
      toast.success('Team logo saved');
      onSaved();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal
      open={open}
      onClose={saving ? () => {} : onClose}
      title={`Team logo - ${team?.name ?? ''}`}
      description="Upload or paste a logo URL. The app uses this admin logo first, then Cricbuzz, then a local fallback."
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={saving}>Cancel</Button>
          <Button onClick={save} loading={saving}>Save</Button>
        </>
      }
    >
      <div className="flex items-center gap-4">
        <TeamLogoPreview team={{ ...(team || {}), logo_url: url }} />
        <div className="flex-1">
          <Field label="Logo URL">
            <div className="flex gap-2">
              <Input value={url} onChange={(e) => setUrl(e.target.value)} placeholder="Paste URL or upload" className="flex-1" />
              <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) handleUpload(f); }} />
              <Button type="button" variant="secondary" icon={<Upload className="h-4 w-4" />} loading={uploading} onClick={() => fileRef.current?.click()}>
                Upload
              </Button>
            </div>
          </Field>
        </div>
      </div>
    </Modal>
  );
}

function readFileAsDataUrl(file: File) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ''));
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(file);
  });
}
