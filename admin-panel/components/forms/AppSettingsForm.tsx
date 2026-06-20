'use client';

import { useEffect, useMemo, useState } from 'react';
import { toast } from 'sonner';
import { Save } from 'lucide-react';
import { settingsApi } from '@/lib/api';
import { Button } from '@/components/ui/Button';
import { Field, Input, Textarea } from '@/components/ui/Input';
import { Switch } from '@/components/ui/Switch';
import { LoadingSkeleton } from '@/components/ui/LoadingSkeleton';
import { useResource } from '@/lib/hooks';
import { titleCase } from '@/lib/utils';

type Setting = {
  setting_key: string;
  setting_value: unknown;
  setting_group?: string;
  description?: string;
  is_public?: boolean | number;
};

export function AppSettingsForm({ group, canWrite }: { group: string; canWrite: boolean }) {
  const { data, loading, reload } = useResource(() => settingsApi.list(group), [group]);
  const settings = useMemo(() => (data?.data || []) as Setting[], [data]);
  const [values, setValues] = useState<Record<string, unknown>>({});
  const [saving, setSaving] = useState<string | null>(null);

  useEffect(() => {
    setValues(Object.fromEntries(settings.map((s) => [s.setting_key, parse(s.setting_value)])));
  }, [settings]);

  async function save(setting: Setting) {
    setSaving(setting.setting_key);
    try {
      await settingsApi.update(setting.setting_key, {
        setting_value: values[setting.setting_key],
        setting_group: setting.setting_group,
        description: setting.description,
      });
      toast.success(`${titleCase(setting.setting_key)} saved`);
      reload();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    } finally {
      setSaving(null);
    }
  }

  if (loading) return <LoadingSkeleton lines={6} />;
  if (!settings.length) {
    return (
      <div className="rounded-xl border border-line bg-panel/40 p-6 text-center text-sm text-slate-400">
        No settings in this group yet.
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {settings.map((s) => {
        const v = values[s.setting_key];
        const isBoolean = typeof v === 'boolean';
        const isObject = v !== null && (Array.isArray(v) || typeof v === 'object');
        return (
          <div
            key={s.setting_key}
            className="rounded-xl border border-line bg-panel/40 p-4"
          >
            <div className="mb-2 flex items-start justify-between gap-3">
              <div>
                <div className="font-medium text-slate-100">
                  {titleCase(s.setting_key)}
                </div>
                {s.description && (
                  <div className="text-xs text-slate-500">{s.description}</div>
                )}
              </div>
              {canWrite && (
                <Button
                  size="sm"
                  icon={<Save className="h-3.5 w-3.5" />}
                  loading={saving === s.setting_key}
                  onClick={() => save(s)}
                >
                  Save
                </Button>
              )}
            </div>
            {isBoolean ? (
              <Switch
                checked={Boolean(v)}
                onChange={(next) =>
                  setValues((p) => ({ ...p, [s.setting_key]: next }))
                }
                disabled={!canWrite}
              />
            ) : isObject ? (
              <Field>
                <Textarea
                  rows={6}
                  className="font-mono text-xs"
                  value={JSON.stringify(v, null, 2)}
                  disabled={!canWrite}
                  onChange={(e) => {
                    try {
                      setValues((p) => ({
                        ...p,
                        [s.setting_key]: JSON.parse(e.target.value || 'null'),
                      }));
                    } catch {
                      // ignore parse errors mid-typing
                    }
                  }}
                />
              </Field>
            ) : (
              <Field>
                <Input
                  value={(v as string | number | null | undefined) ?? ''}
                  disabled={!canWrite}
                  onChange={(e) =>
                    setValues((p) => ({ ...p, [s.setting_key]: e.target.value }))
                  }
                />
              </Field>
            )}
          </div>
        );
      })}
    </div>
  );
}

function parse(value: unknown): unknown {
  if (typeof value !== 'string') return value;
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}
