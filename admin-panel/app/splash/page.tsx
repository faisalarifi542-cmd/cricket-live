'use client';

import { useEffect, useState } from 'react';
import { toast } from 'sonner';
import { RefreshCw, Upload, Trash2, Sparkles } from 'lucide-react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { Button } from '@/components/ui/Button';
import { Switch } from '@/components/ui/Switch';
import { Field, Input } from '@/components/ui/Input';
import { splashApi, type SplashSettings, type SplashAssetSlot } from '@/lib/api';
import { useAuth, usePermissions } from '@/lib/hooks';

export default function SplashPage() {
  return (
    <AdminShell permission="settings.view">
      <SplashInner />
    </AdminShell>
  );
}

const EMPTY: SplashSettings = {
  splash_enabled: true,
  splash_duration_ms: 3000,
  splash_skip_after_first_launch: false,
  splash_stadium_background_url: '',
  splash_cp_logo_url: '',
  splash_wordmark_panel_url: '',
  splash_orbit_trail_url: '',
  splash_pitch_wickets_url: '',
};

// Local mirror of the backend's SPLASH_ASSET_SLOTS (cricket-api/src/lib/
// splash-config.js). Used so the 5 asset fields always render even if the
// /admin/splash-settings route is unreachable (e.g. backend not yet redeployed)
// — the page stays usable and Save still targets the live API.
const DEFAULT_SLOTS: SplashAssetSlot[] = [
  {
    settingKey: 'splash_stadium_background_url',
    field: 'stadiumBackground',
    label: 'Stadium background',
    hint: 'Full-screen blue-lit stadium at night. Source: blue_lit_sports_stadium_at_night.png',
    dimensions: '1080x1920',
  },
  {
    settingKey: 'splash_cp_logo_url',
    field: 'cpLogo',
    label: 'CP logo',
    hint: 'Centered glowing CP logo. Source: futuristic_glowing_cp_logo.png',
    dimensions: '600x600',
  },
  {
    settingKey: 'splash_wordmark_panel_url',
    field: 'wordmarkPanel',
    label: 'CRICPRO wordmark panel',
    hint: 'Neon CRICPRO wordmark below the logo. Source: glowing_cricpro_logo_in_neon_blue.png',
    dimensions: '900x300',
  },
  {
    settingKey: 'splash_orbit_trail_url',
    field: 'orbitTrail',
    label: 'Neon orbit trail',
    hint: 'Energy ribbon that sweeps around the logo. Source: neon_energy_ribbon_in_dark_space.png',
    dimensions: '900x900',
  },
  {
    settingKey: 'splash_pitch_wickets_url',
    field: 'pitchWickets',
    label: 'Pitch / wickets foreground',
    hint: 'Glowing cricket pitch + wickets at the bottom. Source: neon_cricket_court_in_darkness.png',
    dimensions: '1080x720',
  },
];

function SplashInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const canWrite = perms.can('settings.write');

  const [settings, setSettings] = useState<SplashSettings>(EMPTY);
  // Seed with local defaults so the asset fields render immediately, even
  // before (or without) a successful backend fetch.
  const [slots, setSlots] = useState<SplashAssetSlot[]>(DEFAULT_SLOTS);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    setError(null);
    try {
      const res = await splashApi.get();
      setSettings({ ...EMPTY, ...res.data.settings });
      setSlots(res.data.slots?.length ? res.data.slots : DEFAULT_SLOTS);
    } catch (err) {
      // Non-fatal: keep the default slots so the page stays usable. This is the
      // expected state when the backend /admin/splash-settings route has not
      // been deployed/restarted yet — Save will start working once it is.
      setSlots(DEFAULT_SLOTS);
      setError(
        (err instanceof Error ? err.message : 'Failed to load splash settings') +
          ' — showing defaults. If this says “Route not found”, redeploy & restart the cricket-api backend so /admin/splash-settings is live.',
      );
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, []);

  function patch(p: Partial<SplashSettings>) {
    setSettings((s) => ({ ...s, ...p }));
  }

  async function save() {
    setSaving(true);
    try {
      const res = await splashApi.save(settings);
      setSettings({ ...EMPTY, ...res.data.settings });
      toast.success('Splash settings saved');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Save failed');
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Splash Screen"
        description="Manage the premium animated splash screen shown at app launch. The app always ships bundled fallback art, so an empty URL is safe — it never crashes."
        right={
          <div className="flex gap-2">
            <Button variant="ghost" size="sm" onClick={load}>
              <RefreshCw className="h-4 w-4" /> Refresh
            </Button>
            <Button size="sm" onClick={save} disabled={!canWrite || saving || loading}>
              {saving ? 'Saving…' : 'Save changes'}
            </Button>
          </div>
        }
      />

      {error && (
        <div className="rounded-lg border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-200">
          {error}
        </div>
      )}

      {loading ? (
        <div className="p-8 text-center text-sm text-slate-400">Loading splash settings…</div>
      ) : (
        <div className="grid gap-6 lg:grid-cols-[1fr_360px]">
          {/* ---- Controls ---- */}
          <div className="space-y-6">
            <section className="space-y-4 rounded-xl border border-white/10 bg-white/5 p-5">
              <h2 className="flex items-center gap-2 text-sm font-bold uppercase tracking-wide text-slate-200">
                <Sparkles className="h-4 w-4 text-cyan-300" /> Behavior
              </h2>
              <div className="flex flex-wrap items-center gap-6">
                <Switch
                  checked={settings.splash_enabled}
                  onChange={(v) => patch({ splash_enabled: v })}
                  disabled={!canWrite}
                  label="Animated splash enabled"
                />
                <Switch
                  checked={settings.splash_skip_after_first_launch}
                  onChange={(v) => patch({ splash_skip_after_first_launch: v })}
                  disabled={!canWrite}
                  label="Skip after first launch"
                />
              </div>
              <Field label="Duration (milliseconds)" hint="Total animation time. 800–10000ms. Default 3000.">
                <Input
                  type="number"
                  min={800}
                  max={10000}
                  step={100}
                  value={settings.splash_duration_ms}
                  onChange={(e) =>
                    patch({ splash_duration_ms: Number(e.target.value) || 0 })
                  }
                  disabled={!canWrite}
                />
              </Field>
            </section>

            <section className="space-y-4 rounded-xl border border-white/10 bg-white/5 p-5">
              <h2 className="text-sm font-bold uppercase tracking-wide text-slate-200">
                Splash assets
              </h2>
              <p className="text-xs text-slate-400">
                Upload or paste a URL for each layer. Leave empty to use the app&apos;s bundled
                fallback. Prefer WebP/PNG, under 2MB.
              </p>
              {slots.map((slot) => (
                <AssetField
                  key={slot.settingKey}
                  slot={slot}
                  value={(settings as Record<string, unknown>)[slot.settingKey] as string}
                  canWrite={canWrite}
                  onChange={(url) => patch({ [slot.settingKey]: url } as Partial<SplashSettings>)}
                />
              ))}
            </section>
          </div>

          {/* ---- Live preview ---- */}
          <div className="space-y-2">
            <h2 className="text-sm font-bold uppercase tracking-wide text-slate-200">Preview</h2>
            <SplashPreview settings={settings} />
            <p className="text-[11px] leading-snug text-slate-500">
              Approximate composition only. Actual animation: stadium fades in → glow brightens →
              CP logo soft-bounce + cyan pulse → orbit sweep → wordmark slide-in → pitch glow +
              particle sparkles.
            </p>
          </div>
        </div>
      )}
    </div>
  );
}

function AssetField({
  slot,
  value,
  canWrite,
  onChange,
}: {
  slot: SplashAssetSlot;
  value: string;
  canWrite: boolean;
  onChange: (url: string) => void;
}) {
  const [uploading, setUploading] = useState(false);

  async function onFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    const ALLOWED = ['image/png', 'image/jpeg', 'image/jpg', 'image/webp'];
    const name = file.name.toLowerCase();
    const extOk = /\.(png|jpe?g|webp)$/.test(name);
    // Some browsers report an empty/odd MIME for webp; accept by extension too.
    if (!ALLOWED.includes(file.type) && !extOk) {
      toast.error('Only PNG, JPG, JPEG, or WEBP images under 2MB are allowed.');
      return;
    }
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
      // Fall back to a webp MIME hint when the browser leaves file.type empty.
      const mime =
        file.type || (name.endsWith('.webp') ? 'image/webp' : undefined);
      const res = await splashApi.uploadImage(dataUrl, mime);
      onChange(res.url);
      toast.success('Uploaded. Remember to Save.');
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Upload failed');
    } finally {
      setUploading(false);
      e.target.value = '';
    }
  }

  return (
    <div className="rounded-lg border border-white/10 bg-slate-900/40 p-3">
      <div className="flex items-start gap-3">
        <div className="flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden rounded-md border border-white/10 bg-slate-950">
          {value ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={value} alt={slot.label} className="h-full w-full object-cover" />
          ) : (
            <span className="text-[9px] text-slate-600">fallback</span>
          )}
        </div>
        <div className="min-w-0 flex-1 space-y-2">
          <div className="flex items-center justify-between gap-2">
            <p className="text-sm font-semibold text-slate-100">{slot.label}</p>
            <span className="font-mono text-[10px] text-slate-500">{slot.dimensions}</span>
          </div>
          <p className="text-[11px] leading-snug text-slate-400">{slot.hint}</p>
          <Input
            value={value || ''}
            onChange={(e) => onChange(e.target.value)}
            placeholder="https://cdn.example.com/asset.png"
            disabled={!canWrite}
          />
          <div className="flex items-center gap-2">
            <label className="inline-flex cursor-pointer items-center gap-1.5 rounded-md border border-white/10 bg-white/5 px-2.5 py-1.5 text-xs text-slate-200 hover:bg-white/10">
              <Upload className="h-3.5 w-3.5" />
              {uploading ? 'Uploading…' : 'Upload'}
              <input
                type="file"
                accept="image/png,image/jpeg,image/jpg,image/webp,.png,.jpg,.jpeg,.webp"
                className="hidden"
                onChange={onFile}
                disabled={!canWrite || uploading}
              />
            </label>
            {value && (
              <button
                type="button"
                onClick={() => onChange('')}
                disabled={!canWrite}
                className="inline-flex items-center gap-1 rounded-md px-2 py-1.5 text-xs text-rose-300 hover:bg-rose-500/10"
              >
                <Trash2 className="h-3.5 w-3.5" /> Clear
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function SplashPreview({ settings }: { settings: SplashSettings }) {
  const s = settings;
  return (
    <div
      className="relative mx-auto aspect-[9/19] w-full max-w-[300px] overflow-hidden rounded-2xl border border-white/10"
      style={{ background: 'radial-gradient(120% 80% at 50% 35%, #0b1830 0%, #060b18 70%, #03060f 100%)' }}
    >
      {/* Stadium background (cover) */}
      {s.splash_stadium_background_url && (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={s.splash_stadium_background_url}
          alt=""
          className="absolute inset-0 h-full w-full object-cover opacity-80"
        />
      )}
      {/* Floodlight glow pools (left + right) + central wash */}
      <div
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            'radial-gradient(28% 22% at 8% 24%, rgba(92,208,255,0.35), transparent 70%),' +
            'radial-gradient(28% 22% at 92% 24%, rgba(92,208,255,0.35), transparent 70%),' +
            'radial-gradient(46% 30% at 50% 40%, rgba(56,189,248,0.30), transparent 72%)',
        }}
      />

      {/* Painted neon orbit rings wrapping the logo (drawn, never a square) */}
      <div
        className="pointer-events-none absolute left-1/2 top-[40%] -translate-x-1/2 -translate-y-1/2 rounded-[50%] border-2 border-cyan-300/70"
        style={{
          width: '58%',
          height: '34%',
          transform: 'translate(-50%,-50%) rotate(-12deg)',
          boxShadow: '0 0 18px rgba(92,208,255,0.5), inset 0 0 12px rgba(92,208,255,0.25)',
        }}
      />
      <div
        className="pointer-events-none absolute left-1/2 top-[44%] -translate-x-1/2 -translate-y-1/2 rounded-[50%] border border-cyan-300/40"
        style={{
          width: '66%',
          height: '24%',
          transform: 'translate(-50%,-50%) rotate(8deg)',
          boxShadow: '0 0 14px rgba(92,208,255,0.35)',
        }}
      />

      {/* CP logo — large, upper-middle, cyan glow, no card behind it */}
      <div
        className="absolute left-1/2 top-[40%] -translate-x-1/2 -translate-y-1/2"
        style={{ width: '56%', height: '28%', filter: 'drop-shadow(0 0 22px rgba(92,208,255,0.55))' }}
      >
        {s.splash_cp_logo_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={s.splash_cp_logo_url} alt="CP" className="h-full w-full object-contain" />
        ) : (
          <div className="flex h-full w-full items-center justify-center rounded-full border-2 border-cyan-300/70 text-4xl font-black text-cyan-100">
            CP
          </div>
        )}
      </div>

      {/* CRICPRO wordmark inside a neon glass panel */}
      <div
        className="absolute left-1/2 top-[58%] flex -translate-x-1/2 items-center justify-center rounded-lg border border-cyan-300/60 px-3"
        style={{
          width: '70%',
          height: '7.5%',
          background: 'linear-gradient(180deg, rgba(10,26,46,0.8), rgba(4,10,20,0.9))',
          boxShadow: '0 0 20px rgba(92,208,255,0.3)',
        }}
      >
        {s.splash_wordmark_panel_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={s.splash_wordmark_panel_url} alt="CRICPRO" className="max-h-full w-full object-contain" />
        ) : (
          <p className="text-center text-sm font-black tracking-[0.32em] text-slate-100">CRICPRO</p>
        )}
      </div>

      {/* Pitch / wickets at bottom — screen-blended so the dark art vanishes */}
      {s.splash_pitch_wickets_url && (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={s.splash_pitch_wickets_url}
          alt=""
          className="absolute bottom-[3.5%] left-1/2 w-[90%] -translate-x-1/2 object-contain"
          style={{ height: '26%', mixBlendMode: 'screen' }}
        />
      )}
      {!s.splash_enabled && (
        <div className="absolute inset-0 flex items-center justify-center bg-black/60">
          <span className="rounded bg-black/70 px-3 py-1 text-xs font-semibold text-amber-200">
            Splash disabled
          </span>
        </div>
      )}
    </div>
  );
}
