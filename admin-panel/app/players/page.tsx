'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { RefreshCw, Trash2, Image as ImageIcon, Upload, Wand2, Eraser, Plus, Pencil } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { DataTable, type Column } from '@/components/ui/DataTable';
import { SearchInput } from '@/components/ui/SearchInput';
import { FilterBar } from '@/components/ui/FilterBar';
import { Button } from '@/components/ui/Button';
import { Modal } from '@/components/ui/Modal';
import { Field, Input, Select } from '@/components/ui/Input';
import { playersApi, PLAYER_IMAGE_MODES, type PlayerImageMode } from '@/lib/api';
import { useAuth, useDebouncedValue, usePermissions, useResource } from '@/lib/hooks';

type Player = {
  id?: number;
  player_id?: string | number;
  external_id?: string;
  player_external_id?: string;
  name?: string;
  full_name?: string;
  role?: string;
  country?: string;
  batting_style?: string;
  bowling_style?: string;
  team_id?: number | null;
  image_url?: string;
  admin_image_url?: string;
  provider_image_url?: string;
  resolved_image_url?: string | null;
  image_mode?: string | null;
  is_image_active?: boolean;
  is_active?: boolean;
};

const MODE_LABELS: Record<string, string> = {
  admin_first: 'Admin first → Cricbuzz → Initials',
  cricbuzz_first: 'Cricbuzz first → Admin → Initials',
  admin_only: 'Admin only → Initials',
  cricbuzz_only: 'Cricbuzz only → Initials',
  initials_only: 'Initials only',
};

export default function PlayersPage() {
  return (
    <AdminShell permission="players.view">
      <PlayersInner />
    </AdminShell>
  );
}

function PlayersInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const canWrite = perms.can('players.write');
  const [q, setQ] = useState('');
  const debouncedQ = useDebouncedValue(q, 250);
  const [role, setRole] = useState('all');
  const [country, setCountry] = useState('all');
  const [editing, setEditing] = useState<Player | null>(null);
  const [formPlayer, setFormPlayer] = useState<Player | 'new' | null>(null);
  const [deleting, setDeleting] = useState<Player | null>(null);
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [globalMode, setGlobalMode] = useState<PlayerImageMode>('admin_first');
  const [savingMode, setSavingMode] = useState(false);
  const [busyTool, setBusyTool] = useState<string | null>(null);

  const { data, loading, error, reload } = useResource(() => playersApi.list(), []);
  const all = (data?.data || []) as Player[];

  useEffect(() => {
    const gm = data?.globalMode;
    if (gm && (PLAYER_IMAGE_MODES as readonly string[]).includes(gm)) {
      setGlobalMode(gm as PlayerImageMode);
    }
  }, [data?.globalMode]);

  const countries = useMemo(
    () => Array.from(new Set(all.map((p) => p.country).filter(Boolean))) as string[],
    [all],
  );
  const roles = useMemo(
    () => Array.from(new Set(all.map((p) => p.role).filter(Boolean))) as string[],
    [all],
  );

  const rows = useMemo(() => {
    const needle = debouncedQ.toLowerCase();
    return all.filter((p) => {
      if (role !== 'all' && p.role !== role) return false;
      if (country !== 'all' && p.country !== country) return false;
      if (needle && !`${p.name ?? ''} ${p.country ?? ''} ${p.role ?? ''}`.toLowerCase().includes(needle)) return false;
      return true;
    });
  }, [all, debouncedQ, role, country]);

  async function saveGlobalMode(mode: PlayerImageMode) {
    setGlobalMode(mode);
    setSavingMode(true);
    try {
      await playersApi.setImageMode(mode);
      toast.success('Global image mode saved');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to save mode');
    } finally {
      setSavingMode(false);
    }
  }

  async function runTool(name: string, fn: () => Promise<unknown>, success: string) {
    setBusyTool(name);
    try {
      await fn();
      toast.success(success);
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Action failed');
    } finally {
      setBusyTool(null);
    }
  }

  const columns: Column<Player>[] = [
    {
      id: 'player',
      header: 'Player',
      render: (p) => {
        const id = String(p.player_id ?? p.id ?? '');
        const img = p.resolved_image_url ?? p.admin_image_url ?? p.provider_image_url ?? p.image_url;
        return (
          <Link href={`/players/${encodeURIComponent(id)}`} className="flex items-center gap-3">
            <PlayerThumb url={img} name={p.name} />
            <div>
              <div className="font-medium text-slate-100">{p.name ?? '—'}</div>
              <div className="text-[10px] uppercase tracking-wide text-slate-500">{p.role ?? '—'}</div>
            </div>
          </Link>
        );
      },
    },
    { id: 'country', header: 'Country', render: (p) => p.country ?? '—' },
    {
      id: 'image',
      header: 'Image source',
      render: (p) => {
        const tags: { label: string; tone: string }[] = [];
        if (p.admin_image_url) tags.push({ label: 'Admin', tone: 'bg-cyan-500/15 text-cyan-300' });
        if (p.provider_image_url || p.image_url) tags.push({ label: 'Cricbuzz', tone: 'bg-amber-500/15 text-amber-300' });
        if (!tags.length) tags.push({ label: 'Initials', tone: 'bg-white/5 text-slate-400' });
        return (
          <div className="flex flex-wrap items-center gap-1.5">
            {tags.map((t) => (
              <span key={t.label} className={`rounded-full px-2 py-0.5 text-[10px] font-medium ${t.tone}`}>
                {t.label}
              </span>
            ))}
            {p.image_mode && (
              <span className="rounded-full bg-violet-500/15 px-2 py-0.5 text-[10px] font-medium text-violet-300" title="Per-player override">
                Override: {p.image_mode}
              </span>
            )}
          </div>
        );
      },
    },
    {
      id: 'actions',
      header: '',
      className: 'text-right',
      render: (p) => {
        const id = String(p.player_id ?? p.id ?? '');
        return (
          <div className="flex items-center justify-end gap-1">
            {canWrite && (
              <>
                <Button size="sm" variant="secondary" icon={<ImageIcon className="h-3.5 w-3.5" />} onClick={() => setEditing(p)}>
                  Image
                </Button>
                <Button size="sm" variant="ghost" icon={<Pencil className="h-3.5 w-3.5" />} onClick={() => setFormPlayer(p)}>
                  Edit
                </Button>
                <Button size="sm" variant="ghost" icon={<RefreshCw className="h-3.5 w-3.5" />} onClick={async () => { await playersApi.refresh(id); toast.success('Refreshed'); reload(); }}>
                  Refresh
                </Button>
                <Button size="sm" variant="ghost" icon={<Trash2 className="h-3.5 w-3.5 text-red-300" />} onClick={() => setDeleting(p)}>
                  Delete
                </Button>
              </>
            )}
          </div>
        );
      },
    },
  ];

  async function confirmDelete() {
    if (!deleting) return;
    const id = String(deleting.id ?? deleting.player_id ?? deleting.external_id ?? '');
    if (!id) {
      toast.error('Missing player id');
      return;
    }
    setDeleteBusy(true);
    try {
      await playersApi.delete(id);
      toast.success('Player deleted');
      setDeleting(null);
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to delete player');
    } finally {
      setDeleteBusy(false);
    }
  }

  return (
    <>
      <PageHeader
        title="Players"
        description="Manage player photos shown across the app. Upload admin images, set provider URLs, and control the resolution priority."
        right={
          <div className="flex gap-2">
            <Button variant="secondary" icon={<RefreshCw className="h-4 w-4" />} onClick={reload} loading={loading}>
              Refresh
            </Button>
            {canWrite && (
              <Button icon={<Plus className="h-4 w-4" />} onClick={() => setFormPlayer('new')}>
                Add Player
              </Button>
            )}
          </div>
        }
      />

      {canWrite && (
        <div className="mb-4 rounded-2xl border border-line bg-white/[0.03] p-4">
          <div className="grid gap-4 md:grid-cols-[minmax(0,1fr)_auto] md:items-end">
            <Field label="Global player image mode" hint="Applied everywhere unless a player has an active override.">
              <Select value={globalMode} onChange={(e) => saveGlobalMode(e.target.value as PlayerImageMode)} disabled={savingMode}>
                {PLAYER_IMAGE_MODES.map((m) => (
                  <option key={m} value={m}>{MODE_LABELS[m] ?? m}</option>
                ))}
              </Select>
            </Field>
            <div className="flex flex-wrap gap-2">
              <Button
                variant="secondary"
                icon={<RefreshCw className="h-4 w-4" />}
                loading={busyTool === 'refresh-images'}
                onClick={() => runTool('refresh-images', () => playersApi.refreshImages(true), 'Provider images refreshed')}
              >
                Fetch missing Cricbuzz images
              </Button>
              <Button
                variant="secondary"
                icon={<Wand2 className="h-4 w-4" />}
                loading={busyTool === 'apply-global'}
                onClick={() => runTool('apply-global', () => playersApi.applyGlobalMode(), 'Per-player overrides cleared')}
              >
                Apply global mode to all
              </Button>
              <Button
                variant="ghost"
                icon={<Eraser className="h-4 w-4" />}
                loading={busyTool === 'clear-admin'}
                onClick={() => {
                  if (!window.confirm('Clear ALL admin-uploaded player images? Provider images are kept. This cannot be undone.')) return;
                  runTool('clear-admin', () => playersApi.clearAdminImages(), 'All admin images cleared');
                }}
              >
                Clear all admin overrides
              </Button>
            </div>
          </div>
        </div>
      )}

      <SearchInput value={q} onChange={setQ} placeholder="Search players…" className="mb-3 max-w-md" />
      <FilterBar
        filters={[
          {
            type: 'select',
            id: 'role',
            label: 'Role',
            value: role,
            options: [{ id: 'all', label: 'All' }, ...roles.map((r) => ({ id: r, label: r }))],
            onChange: setRole,
          },
          {
            type: 'select',
            id: 'country',
            label: 'Country',
            value: country,
            options: [{ id: 'all', label: 'All' }, ...countries.map((c) => ({ id: c, label: c }))],
            onChange: setCountry,
          },
        ]}
      />
      <DataTable
        loading={loading}
        error={error}
        onRetry={reload}
        rows={rows}
        columns={columns}
        rowKey={(p) => String(p.id ?? p.player_id ?? Math.random())}
        emptyTitle="No players found"
      />

      <PlayerImageDialog player={editing} onClose={() => setEditing(null)} onSaved={() => { setEditing(null); reload(); }} />

      <PlayerFormDialog
        player={formPlayer}
        onClose={() => setFormPlayer(null)}
        onSaved={() => { setFormPlayer(null); reload(); }}
      />

      <Modal
        open={!!deleting}
        onClose={deleteBusy ? () => {} : () => setDeleting(null)}
        title="Delete player"
        description={`Permanently delete ${deleting?.name ?? 'this player'}? This cannot be undone.`}
        size="sm"
        footer={
          <>
            <Button variant="ghost" onClick={() => setDeleting(null)} disabled={deleteBusy}>Cancel</Button>
            <Button variant="danger" onClick={confirmDelete} loading={deleteBusy}>Delete</Button>
          </>
        }
      >
        <p className="text-sm text-slate-300">
          Any match/scorecard references to this player are kept (their link is simply cleared).
          The player will no longer appear in the admin list.
        </p>
      </Modal>
    </>
  );
}

function PlayerThumb({ url, name }: { url?: string | null; name?: string }) {
  if (url) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={url} alt={name ?? ''} className="h-9 w-9 rounded-full object-cover bg-white/5" />;
  }
  return (
    <div className="grid h-9 w-9 place-items-center rounded-full bg-white/5 text-[10px] uppercase text-slate-400">
      {(name || '?').slice(0, 2)}
    </div>
  );
}

type ImageForm = {
  admin_image_url: string;
  provider_image_url: string;
  image_mode: string; // '' = inherit global
  is_image_active: boolean;
};

function PlayerImageDialog({
  player,
  onClose,
  onSaved,
}: {
  player: Player | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [form, setForm] = useState<ImageForm>({
    admin_image_url: '',
    provider_image_url: '',
    image_mode: '',
    is_image_active: true,
  });
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const open = !!player;

  useEffect(() => {
    if (player) {
      setForm({
        admin_image_url: player.admin_image_url ?? '',
        provider_image_url: player.provider_image_url ?? player.image_url ?? '',
        image_mode: player.image_mode ?? '',
        is_image_active: player.is_image_active ?? true,
      });
    }
  }, [player]);

  function patch(values: Partial<ImageForm>) {
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
      const res = await playersApi.uploadImage(dataUrl, file.type);
      patch({ admin_image_url: res.url });
      toast.success('Image uploaded');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = '';
    }
  }

  function playerId(p: Player) {
    return String(p.id ?? p.player_id ?? p.external_id ?? '');
  }

  async function save() {
    if (!player) return;
    const id = playerId(player);
    if (!id) {
      toast.error('Missing player id');
      return;
    }
    setSaving(true);
    try {
      await playersApi.updateImage(id, {
        admin_image_url: form.admin_image_url.trim() || null,
        provider_image_url: form.provider_image_url.trim() || null,
        image_mode: form.image_mode || null,
        is_image_active: form.is_image_active,
      });
      toast.success('Player image saved');
      onSaved();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  }

  async function removeAdminImage() {
    if (!player) return;
    const id = playerId(player);
    try {
      await playersApi.removeImage(id);
      patch({ admin_image_url: '' });
      toast.success('Admin image removed');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to remove');
    }
  }

  const preview = form.admin_image_url || form.provider_image_url;

  return (
    <Modal
      open={open}
      onClose={saving ? () => {} : onClose}
      title={`Player image — ${player?.name ?? ''}`}
      description="Upload an admin photo, set a provider URL, and optionally override the resolution mode for this player."
      size="lg"
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={saving}>Cancel</Button>
          <Button onClick={save} loading={saving}>Save</Button>
        </>
      }
    >
      <div className="flex items-start gap-4">
        <PlayerThumbLarge url={preview} name={player?.name} />
        <div className="grid flex-1 gap-4">
          <Field label="Admin uploaded image">
            <div className="flex gap-2">
              <Input value={form.admin_image_url} onChange={(e) => patch({ admin_image_url: e.target.value })} placeholder="Paste URL or upload" className="flex-1" />
              <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) upload(f); }} />
              <Button type="button" variant="secondary" icon={<Upload className="h-4 w-4" />} loading={uploading} onClick={() => fileRef.current?.click()}>
                Upload
              </Button>
              {form.admin_image_url && (
                <Button type="button" variant="ghost" icon={<Trash2 className="h-4 w-4" />} onClick={removeAdminImage}>
                  Remove
                </Button>
              )}
            </div>
          </Field>
          <Field label="Cricbuzz / provider image URL">
            <Input value={form.provider_image_url} onChange={(e) => patch({ provider_image_url: e.target.value })} placeholder="https://static.cricbuzz.com/..." />
          </Field>
          <Field label="Image mode override" hint="Leave on Inherit to use the global mode.">
            <Select value={form.image_mode} onChange={(e) => patch({ image_mode: e.target.value })}>
              <option value="">Inherit global mode</option>
              {PLAYER_IMAGE_MODES.map((m) => (
                <option key={m} value={m}>{MODE_LABELS[m] ?? m}</option>
              ))}
            </Select>
          </Field>
          <Field label="Override active">
            <label className="flex h-10 items-center gap-2 rounded-xl border border-line bg-white/5 px-3 text-sm text-slate-200">
              <input type="checkbox" checked={form.is_image_active} onChange={(e) => patch({ is_image_active: e.target.checked })} />
              Apply this player&apos;s override
            </label>
          </Field>
        </div>
      </div>
    </Modal>
  );
}

function PlayerThumbLarge({ url, name }: { url?: string | null; name?: string }) {
  if (url) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={url} alt={name ?? ''} className="h-24 w-24 rounded-full object-cover bg-white/5 ring-1 ring-line" />;
  }
  return (
    <div className="grid h-24 w-24 place-items-center rounded-full bg-white/5 text-xl uppercase text-slate-400 ring-1 ring-line">
      {(name || '?').slice(0, 2)}
    </div>
  );
}

type ProfileForm = {
  name: string;
  full_name: string;
  country: string;
  role: string;
  batting_style: string;
  bowling_style: string;
  external_id: string;
  player_external_id: string;
  admin_image_url: string;
  provider_image_url: string;
  image_mode: string;
  is_active: boolean;
};

const emptyProfile: ProfileForm = {
  name: '',
  full_name: '',
  country: '',
  role: '',
  batting_style: '',
  bowling_style: '',
  external_id: '',
  player_external_id: '',
  admin_image_url: '',
  provider_image_url: '',
  image_mode: '',
  is_active: true,
};

function profileFromPlayer(p: Player): ProfileForm {
  return {
    name: p.name ?? '',
    full_name: p.full_name ?? '',
    country: p.country ?? '',
    role: p.role ?? '',
    batting_style: p.batting_style ?? '',
    bowling_style: p.bowling_style ?? '',
    external_id: p.external_id ?? '',
    player_external_id: p.player_external_id ?? '',
    admin_image_url: p.admin_image_url ?? '',
    provider_image_url: p.provider_image_url ?? p.image_url ?? '',
    image_mode: p.image_mode ?? '',
    is_active: p.is_active ?? true,
  };
}

function PlayerFormDialog({
  player,
  onClose,
  onSaved,
}: {
  player: Player | 'new' | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [form, setForm] = useState<ProfileForm>(emptyProfile);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const isNew = player === 'new';
  const open = !!player;

  useEffect(() => {
    setForm(player && player !== 'new' ? profileFromPlayer(player) : emptyProfile);
  }, [player]);

  function patch(values: Partial<ProfileForm>) {
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
      const res = await playersApi.uploadImage(dataUrl, file.type);
      patch({ admin_image_url: res.url });
      toast.success('Image uploaded');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = '';
    }
  }

  async function save() {
    if (!form.name.trim()) {
      toast.error('Player name is required');
      return;
    }
    setSaving(true);
    const body = {
      name: form.name.trim(),
      full_name: form.full_name.trim() || null,
      country: form.country.trim() || null,
      role: form.role.trim() || null,
      batting_style: form.batting_style.trim() || null,
      bowling_style: form.bowling_style.trim() || null,
      external_id: form.external_id.trim() || null,
      player_external_id: form.player_external_id.trim() || form.external_id.trim() || null,
      admin_image_url: form.admin_image_url.trim() || null,
      provider_image_url: form.provider_image_url.trim() || null,
      image_mode: form.image_mode || null,
      is_active: form.is_active,
    };
    try {
      if (isNew) {
        await playersApi.create(body);
        toast.success('Player added');
      } else {
        const p = player as Player;
        const id = String(p.id ?? p.player_id ?? p.external_id ?? '');
        await playersApi.update(id, body);
        toast.success('Player updated');
      }
      onSaved();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to save player');
    } finally {
      setSaving(false);
    }
  }

  const preview = form.admin_image_url || form.provider_image_url;

  return (
    <Modal
      open={open}
      onClose={saving ? () => {} : onClose}
      title={isNew ? 'Add Player' : `Edit Player — ${(player as Player)?.name ?? ''}`}
      description="Manage the player profile and the images shown across the app."
      size="lg"
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={saving}>Cancel</Button>
          <Button onClick={save} loading={saving}>{isNew ? 'Add Player' : 'Save Player'}</Button>
        </>
      }
    >
      <div className="grid gap-4 md:grid-cols-2">
        <Field label="Name" required>
          <Input value={form.name} onChange={(e) => patch({ name: e.target.value })} placeholder="Virat Kohli" />
        </Field>
        <Field label="Full name">
          <Input value={form.full_name} onChange={(e) => patch({ full_name: e.target.value })} placeholder="Virat Kohli" />
        </Field>
        <Field label="Country / Team">
          <Input value={form.country} onChange={(e) => patch({ country: e.target.value })} placeholder="India" />
        </Field>
        <Field label="Role">
          <Input value={form.role} onChange={(e) => patch({ role: e.target.value })} placeholder="Batter" />
        </Field>
        <Field label="Batting style">
          <Input value={form.batting_style} onChange={(e) => patch({ batting_style: e.target.value })} placeholder="Right Handed" />
        </Field>
        <Field label="Bowling style">
          <Input value={form.bowling_style} onChange={(e) => patch({ bowling_style: e.target.value })} placeholder="Right-arm medium" />
        </Field>
        <Field label="External / Provider ID" hint="Cricbuzz player id used to match provider images.">
          <Input value={form.external_id} onChange={(e) => patch({ external_id: e.target.value })} placeholder="1413" />
        </Field>
        <Field label="Active">
          <label className="flex h-10 items-center gap-2 rounded-xl border border-line bg-white/5 px-3 text-sm text-slate-200">
            <input type="checkbox" checked={form.is_active} onChange={(e) => patch({ is_active: e.target.checked })} />
            Active player
          </label>
        </Field>
      </div>

      <div className="mt-4 flex items-start gap-4 rounded-xl border border-line bg-white/[0.02] p-4">
        <PlayerThumbLarge url={preview} name={form.name} />
        <div className="grid flex-1 gap-4">
          <Field label="Admin image (upload or URL)">
            <div className="flex gap-2">
              <Input value={form.admin_image_url} onChange={(e) => patch({ admin_image_url: e.target.value })} placeholder="Paste URL or upload" className="flex-1" />
              <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) upload(f); }} />
              <Button type="button" variant="secondary" icon={<Upload className="h-4 w-4" />} loading={uploading} onClick={() => fileRef.current?.click()}>
                Upload
              </Button>
              {form.admin_image_url && (
                <Button type="button" variant="ghost" icon={<Trash2 className="h-4 w-4" />} onClick={() => patch({ admin_image_url: '' })}>
                  Clear
                </Button>
              )}
            </div>
          </Field>
          <Field label="Cricbuzz / provider image URL">
            <Input value={form.provider_image_url} onChange={(e) => patch({ provider_image_url: e.target.value })} placeholder="https://static.cricbuzz.com/..." />
          </Field>
          <Field label="Image mode override" hint="Leave on Inherit to use the global mode.">
            <Select value={form.image_mode} onChange={(e) => patch({ image_mode: e.target.value })}>
              <option value="">Inherit global mode</option>
              {PLAYER_IMAGE_MODES.map((m) => (
                <option key={m} value={m}>{MODE_LABELS[m] ?? m}</option>
              ))}
            </Select>
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
