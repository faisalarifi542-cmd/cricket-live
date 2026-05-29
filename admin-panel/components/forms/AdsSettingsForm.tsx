'use client';

import { useEffect, useState } from 'react';
import { toast } from 'sonner';
import { Save } from 'lucide-react';
import { adsApi } from '@/lib/api';
import { adsSchema, type AdsInput } from '@/lib/validators';
import { Button } from '@/components/ui/Button';
import { Field, Input } from '@/components/ui/Input';
import { Switch } from '@/components/ui/Switch';
import { LoadingSkeleton } from '@/components/ui/LoadingSkeleton';
import { useResource } from '@/lib/hooks';

const TOGGLES: Array<{ key: keyof AdsInput; label: string; description?: string }> = [
  { key: 'show_ads', label: 'Show ads', description: 'Master switch. When off, no ads render anywhere.' },
  { key: 'test_mode', label: 'Test mode', description: 'Serve test ads only. Use during QA.' },
  { key: 'banner_enabled', label: 'Banners' },
  { key: 'native_enabled', label: 'Native ads' },
  { key: 'interstitial_enabled', label: 'Interstitials' },
  { key: 'rewarded_enabled', label: 'Rewarded ads' },
];

const UNIT_FIELDS: Array<{ key: keyof AdsInput; label: string }> = [
  { key: 'android_banner_id', label: 'Android banner unit' },
  { key: 'android_interstitial_id', label: 'Android interstitial unit' },
  { key: 'android_native_id', label: 'Android native unit' },
  { key: 'android_rewarded_id', label: 'Android rewarded unit' },
  { key: 'ios_banner_id', label: 'iOS banner unit' },
  { key: 'ios_interstitial_id', label: 'iOS interstitial unit' },
  { key: 'ios_native_id', label: 'iOS native unit' },
  { key: 'ios_rewarded_id', label: 'iOS rewarded unit' },
];

export function AdsSettingsForm({ canWrite }: { canWrite: boolean }) {
  const { data, loading, reload } = useResource(() => adsApi.get(), []);
  const [form, setForm] = useState<Partial<AdsInput>>({});
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const incoming = (data?.data || []) as Array<{ setting_key: string; setting_value: unknown }>;
    const flat: Record<string, unknown> = {};
    for (const row of incoming) {
      let v: unknown = row.setting_value;
      if (typeof v === 'string') {
        try { v = JSON.parse(v); } catch { /* keep as string */ }
      }
      flat[row.setting_key] = v;
    }
    setForm(flat as Partial<AdsInput>);
  }, [data]);

  function update<K extends keyof AdsInput>(k: K, v: unknown) {
    setForm((p) => ({ ...p, [k]: v as AdsInput[K] }));
  }

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
      <section className="rounded-2xl border border-line bg-panel/40 p-4">
        <h2 className="mb-3 text-sm font-semibold text-slate-100">Toggles</h2>
        <div className="grid gap-3 md:grid-cols-2">
          {TOGGLES.map((t) => (
            <Switch
              key={String(t.key)}
              checked={Boolean(form[t.key])}
              onChange={(v) => update(t.key, v)}
              label={t.label}
              description={t.description}
              disabled={!canWrite}
            />
          ))}
        </div>
        <Field label="Frequency (minutes)" className="mt-4 max-w-xs" hint="Minimum minutes between interstitial impressions per user.">
          <Input
            type="number"
            min={0}
            value={form.frequency_minutes ?? 5}
            disabled={!canWrite}
            onChange={(e) => update('frequency_minutes', Number(e.target.value))}
          />
        </Field>
      </section>

      <section className="rounded-2xl border border-line bg-panel/40 p-4">
        <h2 className="mb-3 text-sm font-semibold text-slate-100">Ad unit IDs</h2>
        <div className="grid gap-4 md:grid-cols-2">
          {UNIT_FIELDS.map((u) => (
            <Field key={String(u.key)} label={u.label}>
              <Input
                value={(form[u.key] as string | undefined) ?? ''}
                disabled={!canWrite}
                onChange={(e) => update(u.key, e.target.value)}
                placeholder="ca-app-pub-…"
              />
            </Field>
          ))}
        </div>
      </section>

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
