'use client';

import { useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Save, AlertTriangle, FlaskConical } from 'lucide-react';
import { adsApi } from '@/lib/api';
import { adsSchema, type AdsInput } from '@/lib/validators';
import { Button } from '@/components/ui/Button';
import { Field, Input, Select } from '@/components/ui/Input';
import { Switch } from '@/components/ui/Switch';
import { LoadingSkeleton } from '@/components/ui/LoadingSkeleton';
import { useResource } from '@/lib/hooks';

type Network = 'admob' | 'unity' | 'meta';

// Google-provided sample/test unit IDs. Safe to use during QA — they never
// generate real revenue and never risk a policy strike.
const ADMOB_TEST_IDS = {
  android_banner_id: 'ca-app-pub-3940256099942544/6300978111',
  android_interstitial_id: 'ca-app-pub-3940256099942544/1033173712',
  android_native_id: 'ca-app-pub-3940256099942544/2247696110',
  android_rewarded_id: 'ca-app-pub-3940256099942544/5224354917',
  ios_banner_id: 'ca-app-pub-3940256099942544/2934735716',
  ios_interstitial_id: 'ca-app-pub-3940256099942544/4411468910',
  ios_native_id: 'ca-app-pub-3940256099942544/3986624511',
  ios_rewarded_id: 'ca-app-pub-3940256099942544/1712485313',
} satisfies Partial<Record<keyof AdsInput, string>>;

const GLOBAL_TOGGLES: Array<{ key: keyof AdsInput; label: string; description?: string }> = [
  { key: 'show_ads', label: 'Global ads enabled', description: 'Master switch. When off, no ads render anywhere.' },
  { key: 'test_mode', label: 'Test mode', description: 'Serve test ads only. Use during QA.' },
  { key: 'consent_required', label: 'Consent / GDPR required', description: 'Request user consent (UMP) before personalized ads where required.' },
];

const FORMAT_TOGGLES: Array<{ key: keyof AdsInput; label: string; description?: string }> = [
  { key: 'banner_enabled', label: 'Banners' },
  { key: 'native_enabled', label: 'Native ads', description: 'Requires native ad factories; kept off until factories are added.' },
  { key: 'interstitial_enabled', label: 'Interstitials' },
  { key: 'rewarded_enabled', label: 'Rewarded ads' },
  { key: 'rewarded_required_for_premium_streams', label: 'Rewarded required for premium streams' },
];

const NETWORK_TOGGLES: Array<{ key: keyof AdsInput; label: string }> = [
  { key: 'admob_enabled', label: 'AdMob' },
  { key: 'unity_enabled', label: 'Unity Ads' },
  { key: 'meta_enabled', label: 'Meta / Facebook Audience Network' },
];

const PLACEMENT_TOGGLES: Array<{ key: keyof AdsInput; label: string }> = [
  { key: 'home_banner_enabled', label: 'Home banner' },
  { key: 'home_native_enabled', label: 'Home native' },
  { key: 'matches_banner_enabled', label: 'Matches banner' },
  { key: 'matches_native_enabled', label: 'Matches native' },
  { key: 'schedule_banner_enabled', label: 'Schedule banner' },
  { key: 'match_details_banner_enabled', label: 'Match details banner' },
  { key: 'match_details_native_enabled', label: 'Match details native' },
  { key: 'news_banner_enabled', label: 'News banner' },
  { key: 'news_native_enabled', label: 'News native' },
  { key: 'series_banner_enabled', label: 'Series banner' },
  { key: 'series_native_enabled', label: 'Series native' },
  { key: 'more_banner_enabled', label: 'More banner' },
  { key: 'live_player_banner_enabled', label: 'Live player banner' },
];

const INTERSTITIAL_TOGGLES: Array<{ key: keyof AdsInput; label: string }> = [
  { key: 'match_details_interstitial_enabled', label: 'Match Details open interstitial' },
  { key: 'news_interstitial_enabled', label: 'News article open interstitial' },
  { key: 'series_interstitial_enabled', label: 'Series detail open interstitial' },
  { key: 'after_player_interstitial_enabled', label: 'After leaving player interstitial' },
];

const REWARDED_TOGGLES: Array<{ key: keyof AdsInput; label: string }> = [
  { key: 'premium_stream_rewarded_enabled', label: 'Premium stream rewarded video' },
  { key: 'premium_stream_rewarded_interstitial_enabled', label: 'Premium stream rewarded interstitial' },
];

const PRE_ROLL_TOGGLES: Array<{ key: keyof AdsInput; label: string; description?: string }> = [
  { key: 'pre_roll_free_streams', label: 'Pre-roll ads for free streams' },
  { key: 'pre_roll_premium_streams', label: 'Pre-roll ads for premium streams' },
  { key: 'pre_roll_allow_fallback', label: 'Allow fallback to interstitial', description: 'If the selected rewarded type is unavailable, fall back to interstitial. Off = never substitute.' },
];

const APP_OPEN_TOGGLES: Array<{ key: keyof AdsInput; label: string; description?: string }> = [
  { key: 'app_open_enabled', label: 'App Open ads enabled' },
  { key: 'app_open_cold_start', label: 'Show on cold start' },
  { key: 'app_open_resume', label: 'Show on app resume' },
];

const ADMOB_FIELDS: Array<{ key: keyof AdsInput; label: string }> = [
  { key: 'admob_android_app_id', label: 'Android app ID' },
  { key: 'admob_ios_app_id', label: 'iOS app ID' },
  { key: 'android_banner_id', label: 'Android banner unit' },
  { key: 'android_interstitial_id', label: 'Android interstitial unit' },
  { key: 'android_native_id', label: 'Android native unit' },
  { key: 'android_rewarded_id', label: 'Android rewarded unit' },
  { key: 'android_rewarded_interstitial_id', label: 'Android rewarded interstitial unit' },
  { key: 'android_app_open_id', label: 'Android app open unit' },
  { key: 'ios_banner_id', label: 'iOS banner unit' },
  { key: 'ios_interstitial_id', label: 'iOS interstitial unit' },
  { key: 'ios_native_id', label: 'iOS native unit' },
  { key: 'ios_rewarded_id', label: 'iOS rewarded unit' },
  { key: 'ios_rewarded_interstitial_id', label: 'iOS rewarded interstitial unit' },
  { key: 'ios_app_open_id', label: 'iOS app open unit' },
];

const UNITY_FIELDS: Array<{ key: keyof AdsInput; label: string }> = [
  { key: 'unity_android_game_id', label: 'Android game ID' },
  { key: 'unity_ios_game_id', label: 'iOS game ID' },
  { key: 'unity_android_banner_id', label: 'Android banner placement' },
  { key: 'unity_android_interstitial_id', label: 'Android interstitial placement' },
  { key: 'unity_android_rewarded_id', label: 'Android rewarded placement' },
  { key: 'unity_ios_banner_id', label: 'iOS banner placement' },
  { key: 'unity_ios_interstitial_id', label: 'iOS interstitial placement' },
  { key: 'unity_ios_rewarded_id', label: 'iOS rewarded placement' },
];

const META_FIELDS: Array<{ key: keyof AdsInput; label: string }> = [
  { key: 'meta_android_app_id', label: 'Android app ID' },
  { key: 'meta_ios_app_id', label: 'iOS app ID' },
  { key: 'meta_android_banner_id', label: 'Android banner placement' },
  { key: 'meta_android_native_id', label: 'Android native placement' },
  { key: 'meta_android_interstitial_id', label: 'Android interstitial placement' },
  { key: 'meta_android_rewarded_id', label: 'Android rewarded placement' },
  { key: 'meta_ios_banner_id', label: 'iOS banner placement' },
  { key: 'meta_ios_native_id', label: 'iOS native placement' },
  { key: 'meta_ios_interstitial_id', label: 'iOS interstitial placement' },
  { key: 'meta_ios_rewarded_id', label: 'iOS rewarded placement' },
];

function defaults(): AdsInput {
  return adsSchema.parse({});
}

export function AdsSettingsForm({ canWrite }: { canWrite: boolean }) {
  const { data, loading, reload } = useResource(() => adsApi.get(), []);
  const [form, setForm] = useState<AdsInput>(defaults());
  const [saving, setSaving] = useState(false);
  const [updatedAt, setUpdatedAt] = useState<string | null>(null);

  useEffect(() => {
    const incoming = (data?.data || []) as Array<{ setting_key: string; setting_value: unknown }>;
    const flat: Record<string, unknown> = {};
    for (const row of incoming) {
      let v: unknown = row.setting_value;
      if (typeof v === 'string') {
        try { v = JSON.parse(v); } catch { /* keep as string */ }
      }
      if (row.setting_key === 'ads_config' && v && typeof v === 'object' && !Array.isArray(v)) {
        Object.assign(flat, v);
        continue;
      }
      flat[row.setting_key] = v;
    }
    setUpdatedAt(typeof flat.updated_at === 'string' ? flat.updated_at : null);
    // Merge saved values over schema defaults so partial configs always show a
    // complete, correct form (never silently blanks toggles to OFF).
    const merged = adsSchema.safeParse({ ...defaults(), ...flat });
    setForm(merged.success ? merged.data : { ...defaults(), ...(flat as Partial<AdsInput>) } as AdsInput);
  }, [data]);

  function update<K extends keyof AdsInput>(k: K, v: AdsInput[K]) {
    setForm((p) => ({ ...p, [k]: v }));
  }

  function moveFallback(index: number, dir: -1 | 1) {
    setForm((p) => {
      const order = [...p.fallback_order];
      const next = index + dir;
      if (next < 0 || next >= order.length) return p;
      [order[index], order[next]] = [order[next], order[index]];
      return { ...p, fallback_order: order };
    });
  }

  function applyAdmobTestIds() {
    setForm((p) => ({ ...p, ...ADMOB_TEST_IDS }));
    toast.success('Filled AdMob test unit IDs');
  }

  // ---- Validation warnings (non-blocking, surfaced to the admin) ----
  const warnings = useMemo(() => {
    const w: string[] = [];
    if (form.show_ads && !form.admob_enabled && !form.unity_enabled && !form.meta_enabled) {
      w.push('Global ads are ON but no ad network is enabled. No ads will show.');
    }
    if (form.show_ads && !form.test_mode) {
      if (form.admob_enabled && !form.android_banner_id && !form.ios_banner_id) {
        w.push('AdMob is enabled in production but no banner unit IDs are set.');
      }
      if (form.unity_enabled && !form.unity_android_game_id && !form.unity_ios_game_id) {
        w.push('Unity is enabled in production but no game IDs are set.');
      }
      if (form.meta_enabled && !form.meta_android_banner_id && !form.meta_ios_banner_id) {
        w.push('Meta is enabled in production but no placement IDs are set.');
      }
    }
    const primaryEnabled =
      (form.primary_network === 'admob' && form.admob_enabled) ||
      (form.primary_network === 'unity' && form.unity_enabled) ||
      (form.primary_network === 'meta' && form.meta_enabled);
    if (form.show_ads && !primaryEnabled) {
      w.push(`Primary network "${form.primary_network}" is not enabled.`);
    }
    if (form.meta_enabled) {
      w.push('Meta/Facebook is stored for mediation/config only. Direct Meta ads are not active in the app yet.');
    }
    return w;
  }, [form]);

  async function save() {
    const parsed = adsSchema.safeParse(form);
    if (!parsed.success) {
      toast.error(Object.values(parsed.error.flatten().fieldErrors).flat()[0] || 'Invalid');
      return;
    }
    setSaving(true);
    try {
      await adsApi.update(parsed.data);
      toast.success('Ads settings saved');
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    } finally {
      setSaving(false);
    }
  }

  if (loading) return <LoadingSkeleton lines={8} />;

  return (
    <div className="space-y-6">
      {warnings.length > 0 && (
        <section className="rounded-2xl border border-amber-400/30 bg-amber-400/5 p-4">
          <div className="mb-2 flex items-center gap-2 text-sm font-semibold text-amber-300">
            <AlertTriangle className="h-4 w-4" /> Configuration warnings
          </div>
          <ul className="list-disc space-y-1 pl-5 text-xs text-amber-200/80">
            {warnings.map((w) => (
              <li key={w}>{w}</li>
            ))}
          </ul>
        </section>
      )}

      <section className="rounded-2xl border border-line bg-panel/40 p-4">
        <h2 className="mb-2 text-sm font-semibold text-slate-100">Network status</h2>
        <div className="flex flex-wrap gap-2 text-[11px]">
          <span className="rounded-full bg-emerald-400/15 px-2.5 py-1 font-semibold text-emerald-300">
            AdMob: active (direct)
          </span>
          <span className="rounded-full bg-amber-400/15 px-2.5 py-1 font-semibold text-amber-300">
            Unity: pending (config only)
          </span>
          <span className="rounded-full bg-amber-400/15 px-2.5 py-1 font-semibold text-amber-300">
            Meta: pending (config only)
          </span>
        </div>
        <p className="mt-2 text-[11px] text-slate-500">
          Only AdMob serves ads in the app today. Unity/Meta IDs are stored for
          later; the app will not attempt to load them until their adapters ship.
        </p>
      </section>

      <section className="rounded-2xl border border-line bg-panel/40 p-4">
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-sm font-semibold text-slate-100">Global</h2>
          {updatedAt && (
            <span className="text-[11px] text-slate-500">
              Last saved {new Date(updatedAt).toLocaleString()}
            </span>
          )}
        </div>
        <div className="grid gap-3 md:grid-cols-2">
          {GLOBAL_TOGGLES.map((t) => (
            <Switch
              key={String(t.key)}
              checked={Boolean(form[t.key])}
              onChange={(v) => update(t.key, v as never)}
              label={t.label}
              description={t.description}
              disabled={!canWrite}
            />
          ))}
        </div>
        <div className="mt-4 grid gap-4 md:grid-cols-2">
          <Field label="Primary ad network" hint="Tried first for every placement.">
            <Select
              value={form.primary_network}
              disabled={!canWrite}
              onChange={(e) => update('primary_network', e.target.value as Network)}
            >
              <option value="admob">AdMob</option>
              <option value="unity">Unity Ads</option>
              <option value="meta">Meta / Facebook</option>
            </Select>
          </Field>
          <Field label="Fallback / waterfall order" hint="If a network has no fill, the next enabled one is tried.">
            <div className="space-y-2">
              {form.fallback_order.map((n, i) => (
                <div key={n} className="flex items-center gap-2 rounded-lg border border-line bg-white/5 px-3 py-1.5">
                  <span className="flex-1 text-sm capitalize text-slate-200">{i + 1}. {n}</span>
                  <button
                    type="button"
                    disabled={!canWrite || i === 0}
                    onClick={() => moveFallback(i, -1)}
                    className="rounded px-2 text-slate-400 hover:text-slate-100 disabled:opacity-30"
                  >
                    ↑
                  </button>
                  <button
                    type="button"
                    disabled={!canWrite || i === form.fallback_order.length - 1}
                    onClick={() => moveFallback(i, 1)}
                    className="rounded px-2 text-slate-400 hover:text-slate-100 disabled:opacity-30"
                  >
                    ↓
                  </button>
                </div>
              ))}
            </div>
          </Field>
        </div>
      </section>

      <section className="rounded-2xl border border-line bg-panel/40 p-4">
        <h2 className="mb-3 text-sm font-semibold text-slate-100">Ad networks</h2>
        <div className="grid gap-3 md:grid-cols-3">
          {NETWORK_TOGGLES.map((t) => (
            <Switch
              key={String(t.key)}
              checked={Boolean(form[t.key])}
              onChange={(v) => update(t.key, v as never)}
              label={t.label}
              disabled={!canWrite}
            />
          ))}
        </div>
      </section>

      <section className="rounded-2xl border border-line bg-panel/40 p-4">
        <h2 className="mb-3 text-sm font-semibold text-slate-100">Ad formats</h2>
        <div className="grid gap-3 md:grid-cols-2">
          {FORMAT_TOGGLES.map((t) => (
            <Switch
              key={String(t.key)}
              checked={Boolean(form[t.key])}
              onChange={(v) => update(t.key, v as never)}
              label={t.label}
              description={t.description}
              disabled={!canWrite}
            />
          ))}
        </div>
      </section>

      <section className="rounded-2xl border border-line bg-panel/40 p-4">
        <h2 className="mb-3 text-sm font-semibold text-slate-100">Frequency caps</h2>
        <div className="grid gap-4 md:grid-cols-3">
          <Field label="Frequency (minutes)" hint="Minimum minutes between interstitials.">
            <Input
              type="number"
              min={0}
              value={form.frequency_minutes ?? 5}
              disabled={!canWrite}
              onChange={(e) => update('frequency_minutes', Number(e.target.value))}
            />
          </Field>
          <Field label="Interstitial frequency cap" hint="Max interstitials per session.">
            <Input
              type="number"
              min={0}
              value={form.interstitial_frequency_cap ?? 1}
              disabled={!canWrite}
              onChange={(e) => update('interstitial_frequency_cap', Number(e.target.value))}
            />
          </Field>
          <Field label="Min seconds between interstitials">
            <Input
              type="number"
              min={0}
              value={form.minimum_seconds_between_interstitials ?? 300}
              disabled={!canWrite}
              onChange={(e) => update('minimum_seconds_between_interstitials', Number(e.target.value))}
            />
          </Field>
          <Field
            label="Min seconds between ANY full-screen ads"
            hint="Cross-format cooldown. Prevents e.g. interstitial then App Open back-to-back."
          >
            <Input
              type="number"
              min={0}
              value={form.minimum_seconds_between_full_screen_ads ?? 90}
              disabled={!canWrite}
              onChange={(e) =>
                update('minimum_seconds_between_full_screen_ads', Number(e.target.value))
              }
            />
          </Field>
        </div>
      </section>

      <section className="rounded-2xl border border-line bg-panel/40 p-4">
        <h2 className="mb-3 text-sm font-semibold text-slate-100">Placements (banners / native)</h2>
        <div className="grid gap-3 md:grid-cols-2">
          {PLACEMENT_TOGGLES.map((t) => (
            <Switch
              key={String(t.key)}
              checked={Boolean(form[t.key])}
              onChange={(v) => update(t.key, v as never)}
              label={t.label}
              disabled={!canWrite}
            />
          ))}
        </div>
      </section>

      <section className="rounded-2xl border border-line bg-panel/40 p-4">
        <h2 className="mb-3 text-sm font-semibold text-slate-100">Interstitial placements</h2>
        <div className="grid gap-3 md:grid-cols-2">
          {INTERSTITIAL_TOGGLES.map((t) => (
            <Switch
              key={String(t.key)}
              checked={Boolean(form[t.key])}
              onChange={(v) => update(t.key, v as never)}
              label={t.label}
              disabled={!canWrite}
            />
          ))}
        </div>
      </section>

      <section className="rounded-2xl border border-line bg-panel/40 p-4">
        <h2 className="mb-3 text-sm font-semibold text-slate-100">Live stream pre-roll</h2>
        <Field
          label="Pre-roll ad type (Watch Live → ad → stream)"
          hint="Shown once between tapping Watch Live and opening the stream."
          className="max-w-sm"
        >
          <Select
            value={form.live_stream_pre_roll_ad_type}
            disabled={!canWrite}
            onChange={(e) =>
              update('live_stream_pre_roll_ad_type', e.target.value as never)
            }
          >
            <option value="none">None</option>
            <option value="interstitial">Interstitial</option>
            <option value="rewarded_interstitial">Rewarded Interstitial</option>
            <option value="rewarded_video">Rewarded Video</option>
          </Select>
        </Field>
        <div className="mt-4 grid gap-3 md:grid-cols-2">
          {PRE_ROLL_TOGGLES.map((t) => (
            <Switch
              key={String(t.key)}
              checked={Boolean(form[t.key])}
              onChange={(v) => update(t.key, v as never)}
              label={t.label}
              description={t.description}
              disabled={!canWrite}
            />
          ))}
        </div>
        <p className="mt-3 text-[11px] text-slate-500">
          Rewarded types are only used for premium streams with
          “requiresRewardAd”. Free streams never force a reward.
        </p>
      </section>

      <section className="rounded-2xl border border-line bg-panel/40 p-4">
        <h2 className="mb-3 text-sm font-semibold text-slate-100">Rewarded placements</h2>
        <div className="grid gap-3 md:grid-cols-2">
          {REWARDED_TOGGLES.map((t) => (
            <Switch
              key={String(t.key)}
              checked={Boolean(form[t.key])}
              onChange={(v) => update(t.key, v as never)}
              label={t.label}
              disabled={!canWrite}
            />
          ))}
        </div>
        <p className="mt-3 text-[11px] text-slate-500">
          Rewarded unlock for premium streams also requires either the global
          “Rewarded ads” toggle OR “Rewarded required for premium streams”.
        </p>
      </section>

      <section className="rounded-2xl border border-line bg-panel/40 p-4">
        <h2 className="mb-3 text-sm font-semibold text-slate-100">App Open ads</h2>
        <div className="grid gap-3 md:grid-cols-2">
          {APP_OPEN_TOGGLES.map((t) => (
            <Switch
              key={String(t.key)}
              checked={Boolean(form[t.key])}
              onChange={(v) => update(t.key, v as never)}
              label={t.label}
              description={t.description}
              disabled={!canWrite}
            />
          ))}
        </div>
        <div className="mt-4 grid gap-4 md:grid-cols-2">
          <Field label="Min minutes between app open ads (cooldown)">
            <Input
              type="number"
              min={0}
              value={form.app_open_min_interval_minutes ?? 240}
              disabled={!canWrite}
              onChange={(e) =>
                update('app_open_min_interval_minutes', Number(e.target.value))
              }
            />
            <p className="mt-1 text-xs text-slate-400">
              AdMob best practice. Default 240 (4 hours). Prevents app-open ads
              spamming on every foreground.
            </p>
          </Field>
          <Field label="Min background seconds before resume ad">
            <Input
              type="number"
              min={0}
              value={form.app_open_min_background_seconds ?? 30}
              disabled={!canWrite}
              onChange={(e) =>
                update('app_open_min_background_seconds', Number(e.target.value))
              }
            />
            <p className="mt-1 text-xs text-slate-400">
              App must stay backgrounded at least this long before an app-open
              shows on resume. Blocks notification-shade / screen-unlock quick
              resumes.
            </p>
          </Field>
          <Field label="Min seconds between app open ads (legacy floor)">
            <Input
              type="number"
              min={0}
              value={form.minimum_seconds_between_app_open_ads ?? 120}
              disabled={!canWrite}
              onChange={(e) =>
                update('minimum_seconds_between_app_open_ads', Number(e.target.value))
              }
            />
          </Field>
          <Field label="Max app open ads per session">
            <Input
              type="number"
              min={0}
              value={form.max_app_open_ads_per_session ?? 4}
              disabled={!canWrite}
              onChange={(e) =>
                update('max_app_open_ads_per_session', Number(e.target.value))
              }
            />
          </Field>
        </div>
      </section>

      <NetworkSection
        title="AdMob (direct)"
        badge="Direct"
        fields={ADMOB_FIELDS}
        form={form}
        update={update}
        canWrite={canWrite}
        extra={
          canWrite ? (
            <Button variant="ghost" icon={<FlaskConical className="h-4 w-4" />} onClick={applyAdmobTestIds}>
              Use AdMob test IDs
            </Button>
          ) : null
        }
      />

      <NetworkSection
        title="Unity Ads"
        badge="Pending — config stored, not active in app"
        fields={UNITY_FIELDS}
        form={form}
        update={update}
        canWrite={canWrite}
        extra={
          <Switch
            checked={Boolean(form.unity_test_mode)}
            onChange={(v) => update('unity_test_mode', v)}
            label="Unity test mode"
            disabled={!canWrite}
          />
        }
      />

      <NetworkSection
        title="Meta / Facebook Audience Network"
        badge="Pending — config stored, not active in app"
        fields={META_FIELDS}
        form={form}
        update={update}
        canWrite={canWrite}
        extra={
          <Switch
            checked={Boolean(form.meta_test_mode)}
            onChange={(v) => update('meta_test_mode', v)}
            label="Meta test mode"
            disabled={!canWrite}
          />
        }
      />

      {canWrite && (
        <div className="flex justify-end">
          <Button icon={<Save className="h-4 w-4" />} onClick={save} loading={saving}>
            Save ads settings
          </Button>
        </div>
      )}
    </div>
  );
}

function NetworkSection({
  title,
  badge,
  fields,
  form,
  update,
  canWrite,
  extra,
}: {
  title: string;
  badge: string;
  fields: Array<{ key: keyof AdsInput; label: string }>;
  form: AdsInput;
  update: <K extends keyof AdsInput>(k: K, v: AdsInput[K]) => void;
  canWrite: boolean;
  extra?: React.ReactNode;
}) {
  return (
    <section className="rounded-2xl border border-line bg-panel/40 p-4">
      <div className="mb-3 flex items-center justify-between gap-2">
        <h2 className="text-sm font-semibold text-slate-100">{title}</h2>
        <span className="rounded-full border border-line px-2 py-0.5 text-[10px] uppercase tracking-wide text-slate-400">
          {badge}
        </span>
      </div>
      {extra && <div className="mb-3">{extra}</div>}
      <div className="grid gap-4 md:grid-cols-2">
        {fields.map((u) => (
          <Field key={String(u.key)} label={u.label}>
            <Input
              value={(form[u.key] as string | undefined) ?? ''}
              disabled={!canWrite}
              onChange={(e) => update(u.key, e.target.value as never)}
              placeholder="…"
            />
          </Field>
        ))}
      </div>
    </section>
  );
}
