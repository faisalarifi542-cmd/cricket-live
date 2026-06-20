'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Check, Copy, ImageIcon, Pencil, RefreshCw, Trash2, Upload } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { Button } from '@/components/ui/Button';
import { Switch } from '@/components/ui/Switch';
import { Modal } from '@/components/ui/Modal';
import { Field, Input } from '@/components/ui/Input';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { assetsApi, type AppAssetRow } from '@/lib/api';
import { useAuth, usePermissions, useResource } from '@/lib/hooks';

export default function AssetsPage() {
  return (
    <AdminShell permission="settings.view">
      <AssetsInner />
    </AdminShell>
  );
}

const THEME_BADGE: Record<string, string> = {
  dark: 'bg-slate-700 text-slate-200',
  light: 'bg-amber-200/20 text-amber-200',
  both: 'bg-cyan-400/15 text-cyan-200',
};

const THEME_LABEL: Record<string, string> = {
  dark: 'Dark only',
  light: 'Light only',
  both: 'Universal / Both',
};

function AssetsInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const canWrite = perms.can('settings.write');
  const { data, loading, error, reload } = useResource(() => assetsApi.list(), []);
  const assets = (data?.data || []) as AppAssetRow[];
  const guidance = data?.guidance;

  const [editing, setEditing] = useState<AppAssetRow | null>(null);
  const [toDelete, setToDelete] = useState<AppAssetRow | null>(null);
  const [copiedKey, setCopiedKey] = useState<string | null>(null);

  async function copyKey(key: string) {
    try {
      await navigator.clipboard.writeText(key);
      setCopiedKey(key);
      setTimeout(() => setCopiedKey((k) => (k === key ? null : k)), 1500);
    } catch {
      toast.error('Copy failed');
    }
  }

  // Group catalog rows by category, preserving first-seen order.
  const grouped: { category: string; rows: AppAssetRow[] }[] = [];
  for (const a of assets) {
    const cat = a.category || 'Other';
    let g = grouped.find((x) => x.category === cat);
    if (!g) {
      g = { category: cat, rows: [] };
      grouped.push(g);
    }
    g.rows.push(a);
  }

  async function toggle(a: AppAssetRow) {
    try {
      if (!a.configured) {
        toast.error('Set a URL first before activating.');
        return;
      }
      await assetsApi.toggle(a.key, a.theme, !a.is_active);
      toast.success(`${a.label} ${a.is_active ? 'disabled' : 'enabled'}`);
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Toggle failed');
    }
  }

  async function remove(a: AppAssetRow) {
    try {
      await assetsApi.remove(a.key, a.theme);
      toast.success(`${a.label} reverted to bundled fallback`);
      setToDelete(null);
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Delete failed');
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="App Assets"
        description="Admin-managed decorative images served to the app at runtime. The app always ships a bundled fallback, so an empty or disabled asset is safe."
        right={
          <Button variant="ghost" size="sm" onClick={reload}>
            <RefreshCw className="h-4 w-4" /> Refresh
          </Button>
        }
      />

      {error && (
        <div className="rounded-lg border border-rose-500/30 bg-rose-500/10 p-4 text-sm text-rose-200">
          {error}
        </div>
      )}

      {guidance && (
        <div className="rounded-lg border border-cyan-500/20 bg-cyan-500/5 p-4 text-xs text-slate-300">
          <p className="mb-1 font-semibold text-cyan-200">Image upload guidance</p>
          <ul className="list-disc space-y-0.5 pl-4">
            {guidance.notes.map((n) => (
              <li key={n}>{n}</li>
            ))}
          </ul>
        </div>
      )}

      {loading ? (
        <div className="p-8 text-center text-sm text-slate-400">Loading assets…</div>
      ) : (
        <div className="space-y-8">
          {grouped.map((group) => (
            <section key={group.category} className="space-y-3">
              <h2 className="text-sm font-bold uppercase tracking-wide text-slate-300">
                {group.category}
                <span className="ml-2 text-xs font-normal text-slate-500">{group.rows.length}</span>
              </h2>
              <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {group.rows.map((a) => (
                  <div
                    key={`${a.key}:${a.theme}`}
                    className="flex flex-col gap-3 rounded-xl border border-white/10 bg-white/5 p-4"
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <p className="truncate text-sm font-semibold text-slate-100">{a.label}</p>
                        <button
                          type="button"
                          onClick={() => copyKey(a.key)}
                          title="Copy key"
                          className="mt-0.5 flex max-w-full items-center gap-1 font-mono text-xs text-slate-500 hover:text-cyan-300"
                        >
                          <span className="truncate">{a.key}</span>
                          {copiedKey === a.key ? (
                            <Check className="h-3 w-3 shrink-0 text-emerald-400" />
                          ) : (
                            <Copy className="h-3 w-3 shrink-0" />
                          )}
                        </button>
                      </div>
                      <div className="flex shrink-0 flex-col items-end gap-1">
                        <span className={`rounded px-2 py-0.5 text-[10px] font-bold uppercase ${THEME_BADGE[a.theme] || THEME_BADGE.both}`}>
                          {a.theme === 'both' && a.themed && !a.universalSafe
                            ? 'Both · dark-only'
                            : THEME_LABEL[a.theme] || a.theme}
                        </span>
                        {a.wired === false ? (
                          <span className="rounded bg-amber-500/15 px-2 py-0.5 text-[9px] font-semibold uppercase text-amber-300" title="Catalog key reserved but not yet consumed by the app">
                            Not wired
                          </span>
                        ) : (
                          <span className="rounded bg-emerald-500/15 px-2 py-0.5 text-[9px] font-semibold uppercase text-emerald-300" title="App renders this remote key with a bundled fallback">
                            Wired
                          </span>
                        )}
                        {a.large && (
                          <span className="rounded bg-fuchsia-500/15 px-2 py-0.5 text-[9px] font-semibold uppercase text-fuchsia-300" title="Large bundled original — best APK-size win">
                            Large
                          </span>
                        )}
                      </div>
                    </div>

                    <div className="flex aspect-video items-center justify-center overflow-hidden rounded-lg border border-white/10 bg-slate-900/50">
                      {a.url ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={a.url} alt={a.label} className="h-full w-full object-cover" />
                      ) : (
                        <div className="flex flex-col items-center gap-1 text-slate-600">
                          <ImageIcon className="h-8 w-8" />
                          <span className="text-[11px]">No remote asset — using bundled fallback</span>
                        </div>
                      )}
                    </div>

                    {a.where && (
                      <p className="text-[11px] leading-snug text-slate-400">
                        <span className="text-slate-500">Where: </span>{a.where}
                      </p>
                    )}

                    {a.themed && (
                      <p className="rounded border border-amber-500/20 bg-amber-500/5 px-2 py-1 text-[10px] leading-snug text-amber-200/90">
                        {a.theme === 'both'
                          ? 'A “Both” upload here shows in DARK mode only. Light mode uses the bundled fallback until a Light asset is uploaded.'
                          : a.theme === 'light'
                            ? 'Upload a bright light-mode image. Shown only in Light Mode.'
                            : 'Upload the dark-mode image. Shown only in Dark Mode.'}
                        {' '}Recommended: upload separate Light and Dark versions for cards & panels.
                      </p>
                    )}

                    <div className="flex items-center justify-between text-xs text-slate-400">
                      <span>{a.dimensions ? `Rec: ${a.dimensions}` : 'Custom key'}</span>
                      {a.wired && (
                        <span className="text-emerald-400/80" title="Has bundled fallback — safe to upload">Safe to upload</span>
                      )}
                      {a.version && <span className="font-mono">v{a.version}</span>}
                    </div>

                    <div className="flex items-center justify-between gap-2 border-t border-white/5 pt-3">
                      <Switch
                        checked={a.is_active}
                        onChange={() => toggle(a)}
                        disabled={!canWrite}
                        label={a.is_active ? 'Active' : 'Inactive'}
                      />
                      <div className="flex gap-1">
                        <Button variant="ghost" size="sm" onClick={() => setEditing(a)} disabled={!canWrite}>
                          <Pencil className="h-4 w-4" />
                        </Button>
                        {a.configured && (
                          <Button variant="ghost" size="sm" onClick={() => setToDelete(a)} disabled={!canWrite}>
                            <Trash2 className="h-4 w-4 text-rose-300" />
                          </Button>
                        )}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </section>
          ))}
        </div>
      )}

      {editing && (
        <AssetEditModal
          asset={editing}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            reload();
          }}
        />
      )}

      <ConfirmDialog
        open={!!toDelete}
        title="Revert to bundled asset?"
        description={`This removes the remote URL for "${toDelete?.label}". The app will fall back to the asset bundled in the build.`}
        confirmLabel="Revert"
        destructive
        onClose={() => setToDelete(null)}
        onConfirm={() => {
          if (toDelete) return remove(toDelete);
        }}
      />
    </div>
  );
}

function AssetEditModal({
  asset,
  onClose,
  onSaved,
}: {
  asset: AppAssetRow;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [url, setUrl] = useState(asset.url || '');
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);

  async function onFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 2 * 1024 * 1024) {
      toast.error('Image must be under 2MB.');
      return;
    }
    setUploading(true);
    try {
      const dataUrl = await new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result));
        reader.onerror = reject;
        reader.readAsDataURL(file);
      });
      const res = await assetsApi.uploadImage(dataUrl, file.type);
      setUrl(res.url);
      toast.success('Uploaded. Remember to Save.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setUploading(false);
    }
  }

  async function save() {
    setSaving(true);
    try {
      await assetsApi.upsert(asset.key, asset.theme, { url: url.trim() || null, is_active: true });
      toast.success(`${asset.label} saved`);
      onSaved();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Save failed');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal
      open
      onClose={onClose}
      title={asset.label}
      description={`Key: ${asset.key} · Theme: ${asset.theme}${asset.dimensions ? ` · Recommended ${asset.dimensions}` : ''}`}
      footer={
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button onClick={save} disabled={saving}>{saving ? 'Saving…' : 'Save'}</Button>
        </div>
      }
    >
      <div className="space-y-4">
        {asset.theme === 'both' && (
          <div className="rounded-lg border border-amber-500/30 bg-amber-500/10 p-3 text-xs text-amber-200">
            ⚠ Only use <strong>Both</strong> if this image looks correct in both Dark and Light Mode.
            A dark image uploaded here will NOT be shown in Light Mode — it stays dark-only and Light
            Mode falls back to the bundled design. For cards & panels, upload separate Light and Dark
            versions instead.
          </div>
        )}

        <Field label="Asset URL">
          <Input
            value={url}
            onChange={(e) => setUrl(e.target.value)}
            placeholder="https://cdn.example.com/asset.png"
          />
        </Field>

        <div className="flex items-center gap-3">
          <label className="inline-flex cursor-pointer items-center gap-2 rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-slate-200 hover:bg-white/10">
            <Upload className="h-4 w-4" />
            {uploading ? 'Uploading…' : 'Upload image'}
            <input type="file" accept="image/*" className="hidden" onChange={onFile} disabled={uploading} />
          </label>
          <span className="text-xs text-slate-500">PNG/JPG/WebP, under 2MB</span>
        </div>

        {url && (
          <div className="overflow-hidden rounded-lg border border-white/10 bg-slate-900/50">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={url} alt="preview" className="max-h-48 w-full object-contain" />
          </div>
        )}
      </div>
    </Modal>
  );
}
