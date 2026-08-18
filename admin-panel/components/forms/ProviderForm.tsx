'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { providersApi } from '@/lib/api';
import { providerSchema, type ProviderInput } from '@/lib/validators';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { Field, Input, Textarea } from '@/components/ui/Input';
import { Switch } from '@/components/ui/Switch';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type ProviderValue = Record<string, any> & { id?: number };

export function ProviderForm({
  open,
  onClose,
  initial,
  onSaved,
}: {
  open: boolean;
  onClose: () => void;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  initial?: Record<string, any> | null;
  onSaved: () => void;
}) {
  const isEdit = !!initial?.id;
  const [form, setForm] = useState<ProviderValue>(() => ({
    slug: initial?.slug ?? '',
    name: initial?.name ?? '',
    provider_type: initial?.provider_type ?? 'custom',
    base_url: initial?.base_url ?? '',
    description: initial?.description ?? '',
    priority: initial?.priority ?? 100,
    timeout_ms: initial?.timeout_ms ?? 8000,
    rate_limit_per_minute: initial?.rate_limit_per_minute ?? 60,
    is_active: initial?.is_active ?? true,
    role: (initial?.role || initial?.metadata?.role || 'fallback') as 'primary' | 'fallback',
  }));
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(false);

  function update<K extends keyof ProviderValue>(k: K, v: ProviderValue[K]) {
    setForm((f) => ({ ...f, [k]: v }));
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const parsed = providerSchema.safeParse(form);
    if (!parsed.success) {
      setErrors(
        Object.fromEntries(
          Object.entries(parsed.error.flatten().fieldErrors)
            .filter(([, v]) => Array.isArray(v) && v.length)
            .map(([k, v]) => [k, (v as string[])[0]]),
        ),
      );
      return;
    }
    setErrors({});
    setLoading(true);
    try {
      if (isEdit && initial?.id) {
        await providersApi.update(initial.id, parsed.data as Record<string, unknown>);
        toast.success('Provider updated');
      } else {
        await providersApi.create(parsed.data as Record<string, unknown>);
        toast.success('Provider created');
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
      title={isEdit ? 'Edit provider' : 'Add provider'}
      description="Providers feed live scores, schedule, and news to the public API. Add multiple to enable failover."
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={loading}>
            Cancel
          </Button>
          <Button onClick={submit} loading={loading}>
            {isEdit ? 'Save changes' : 'Create provider'}
          </Button>
        </>
      }
    >
      <form onSubmit={submit} className="grid gap-4 md:grid-cols-2">
        <Field label="Slug" required error={errors.slug}>
          <Input
            value={form.slug ?? ''}
            onChange={(e) => update('slug', e.target.value)}
            placeholder="cricbuzz"
            readOnly={isEdit}
          />
        </Field>
        <Field label="Name" required error={errors.name}>
          <Input
            value={form.name ?? ''}
            onChange={(e) => update('name', e.target.value)}
            placeholder="Cricbuzz"
          />
        </Field>
        <Field label="Type" error={errors.provider_type}>
          <Input
            value={(form.provider_type ?? '') as string}
            onChange={(e) => update('provider_type', e.target.value)}
            placeholder="cricbuzz"
          />
        </Field>
        <div className="md:col-span-2">
          <Field
            label="Base URL"
            error={errors.base_url}
            hint="Optional for built-in providers; required to test custom providers"
          >
            <Input
              value={(form.base_url ?? '') as string}
              onChange={(e) => update('base_url', e.target.value)}
              placeholder="https://api.example.com"
            />
          </Field>
        </div>
        <div className="md:col-span-2">
          <Field label="Description" error={errors.description}>
            <Textarea
              value={(form.description ?? '') as string}
              onChange={(e) => update('description', e.target.value)}
              placeholder="Notes for other admins"
            />
          </Field>
        </div>
        <Field label="Priority" error={errors.priority} hint="Lower numbers tried first">
          <Input
            type="number"
            value={Number.isFinite(form.priority) ? form.priority : ''}
            onChange={(e) =>
              update('priority', e.target.value === '' ? NaN : Number(e.target.value))
            }
          />
        </Field>
        <Field label="Timeout (ms)" error={errors.timeout_ms}>
          <Input
            type="number"
            value={Number.isFinite(form.timeout_ms) ? form.timeout_ms : ''}
            onChange={(e) =>
              update('timeout_ms', e.target.value === '' ? NaN : Number(e.target.value))
            }
          />
        </Field>
        <Field label="Rate limit / min" error={errors.rate_limit_per_minute}>
          <Input
            type="number"
            value={
              Number.isFinite(form.rate_limit_per_minute)
                ? form.rate_limit_per_minute
                : ''
            }
            onChange={(e) =>
              update(
                'rate_limit_per_minute',
                e.target.value === '' ? NaN : Number(e.target.value),
              )
            }
          />
        </Field>
        <Field label="Role" error={errors.role}>
          <select
            value={(form.role as string) ?? 'fallback'}
            onChange={(e) => update('role', e.target.value as 'primary' | 'fallback')}
            className="h-10 w-full rounded-xl border border-line bg-white/5 px-3 text-sm text-slate-100"
          >
            <option value="primary">Primary</option>
            <option value="fallback">Fallback</option>
          </select>
        </Field>
        <div className="self-end">
          <Switch
            label="Active"
            description="Available for use in failover chain"
            checked={!!form.is_active}
            onChange={(v) => update('is_active', v)}
          />
        </div>
      </form>
    </Modal>
  );
}
