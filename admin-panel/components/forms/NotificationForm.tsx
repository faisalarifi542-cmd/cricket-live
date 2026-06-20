'use client';

import { useEffect, useState } from 'react';
import { toast } from 'sonner';
import { notificationsApi } from '@/lib/api';
import { notificationSchema, type NotificationInput } from '@/lib/validators';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { Field, Input, Select, Textarea } from '@/components/ui/Input';
import { NOTIFICATION_CATEGORIES, NOTIFICATION_DEEP_LINKS, NOTIFICATION_TARGETS, FAVORITE_COUNTRIES } from '@/lib/constants';

type FormValue = Partial<NotificationInput> & { id?: number };

export function NotificationForm({
  open,
  onClose,
  initial,
  onSaved,
}: {
  open: boolean;
  onClose: () => void;
  initial?: FormValue | null;
  onSaved: () => void;
}) {
  const isEdit = !!initial?.id;
  const [form, setForm] = useState<FormValue>(() => ({
    title: initial?.title ?? '',
    body: initial?.body ?? '',
    image_url: initial?.image_url ?? '',
    target_type: initial?.target_type ?? 'all',
    target_value: initial?.target_value ?? '',
    deep_link_type: initial?.deep_link_type ?? '',
    deep_link_value: initial?.deep_link_value ?? '',
    scheduled_at: initial?.scheduled_at ?? '',
    status: initial?.status ?? 'draft',
  }));
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!open) return;
    setForm({
      title: initial?.title ?? '',
      body: initial?.body ?? '',
      image_url: initial?.image_url ?? '',
      target_type: initial?.target_type ?? 'all',
      target_value: initial?.target_value ?? '',
      deep_link_type: initial?.deep_link_type ?? '',
      deep_link_value: initial?.deep_link_value ?? '',
      scheduled_at: initial?.scheduled_at ?? '',
      status: initial?.status ?? 'draft',
    });
    setErrors({});
  }, [initial, open]);

  function update<K extends keyof NotificationInput>(k: K, v: unknown) {
    setForm((p) => ({ ...p, [k]: v as NotificationInput[K] }));
  }

  async function save(status: 'draft' | 'scheduled' | 'sent' = 'draft', send = false) {
    const parsed = notificationSchema.safeParse({ ...form, status });
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
      let id = initial?.id;
      if (isEdit && id) {
        await notificationsApi.update(id, parsed.data);
      } else {
        const r = await notificationsApi.create(parsed.data);
        id = r.id;
      }
      if (send && id) {
        await notificationsApi.send(id);
        toast.success('Notification sent');
      } else {
        toast.success(status === 'draft' ? 'Saved as draft' : 'Scheduled');
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
      title={isEdit ? 'Edit notification' : 'New notification'}
      description="Compose a push notification. Save as draft, schedule, or send now."
      size="lg"
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={loading}>Cancel</Button>
          <Button variant="secondary" onClick={() => save('draft')} loading={loading}>Save draft</Button>
          {form.scheduled_at && (
            <Button variant="secondary" onClick={() => save('scheduled')} loading={loading}>Schedule</Button>
          )}
          <Button onClick={() => save('sent', true)} loading={loading}>Send now</Button>
        </>
      }
    >
      <div className="grid gap-4 md:grid-cols-2">
        <Field label="Title" required error={errors.title} className="md:col-span-2">
          <Input value={form.title ?? ''} onChange={(e) => update('title', e.target.value)} />
        </Field>
        <Field label="Body" required error={errors.body} className="md:col-span-2">
          <Textarea rows={3} value={form.body ?? ''} onChange={(e) => update('body', e.target.value)} />
        </Field>
        <Field label="Image URL" error={errors.image_url} className="md:col-span-2">
          <Input value={(form.image_url as string | undefined) ?? ''} onChange={(e) => update('image_url', e.target.value)} />
        </Field>
        <Field label="Target">
          <Select value={form.target_type ?? 'all'} onChange={(e) => update('target_type', e.target.value)}>
            {NOTIFICATION_TARGETS.map((t) => (
              <option key={t.id} value={t.id}>{t.label}</option>
            ))}
          </Select>
        </Field>
        {form.target_type === 'category' ? (
          <Field label="Category" error={errors.target_value}>
            <Select value={(form.target_value as string | undefined) ?? ''} onChange={(e) => update('target_value', e.target.value)}>
              <option value="">— select category —</option>
              {NOTIFICATION_CATEGORIES.map((cat) => (
                <option key={cat.id} value={cat.id}>{cat.label}</option>
              ))}
            </Select>
          </Field>
        ) : form.target_type === 'favorite' ? (
          <FavoriteTargetFields
            value={(form.target_value as string | undefined) ?? ''}
            error={errors.target_value}
            onChange={(v) => update('target_value', v)}
          />
        ) : (
          <Field label="Target value (topic / user id)">
            <Input value={(form.target_value as string | undefined) ?? ''} onChange={(e) => update('target_value', e.target.value)} />
          </Field>
        )}
        <Field label="Deep link type">
          <Select value={(form.deep_link_type as string | undefined) ?? ''} onChange={(e) => update('deep_link_type', e.target.value)}>
            <option value="">— none —</option>
            {NOTIFICATION_DEEP_LINKS.map((d) => (
              <option key={d.id} value={d.id}>{d.label}</option>
            ))}
          </Select>
        </Field>
        <Field label="Deep link value">
          <Input value={(form.deep_link_value as string | undefined) ?? ''} onChange={(e) => update('deep_link_value', e.target.value)} placeholder="match external id / series id / news id…" />
        </Field>
        <Field label="Schedule for" className="md:col-span-2">
          <Input type="datetime-local" value={(form.scheduled_at as string | undefined) ?? ''} onChange={(e) => update('scheduled_at', e.target.value)} />
        </Field>
      </div>
    </Modal>
  );
}

/// Favourite-country target composer. Emits a `target_value` of the exact form
/// the backend expects: "<categoryKey>:<CODE,CODE,...>". The category gates the
/// opt-in (defaults to favorite_team) and the codes restrict to followed teams.
function FavoriteTargetFields({
  value,
  error,
  onChange,
}: {
  value: string;
  error?: string;
  onChange: (v: string) => void;
}) {
  const [rawCategory, rawCodes] = value.includes(':')
    ? [value.slice(0, value.indexOf(':')), value.slice(value.indexOf(':') + 1)]
    : ['favorite_team', value];
  const category = rawCategory || 'favorite_team';
  const codes = rawCodes
    .split(',')
    .map((c) => c.trim().toUpperCase())
    .filter(Boolean);

  function compose(nextCategory: string, nextCodes: string[]) {
    onChange(`${nextCategory}:${nextCodes.join(',')}`);
  }

  function toggleCode(code: string) {
    const next = codes.includes(code)
      ? codes.filter((c) => c !== code)
      : [...codes, code];
    compose(category, next);
  }

  return (
    <>
      <Field label="Category gate" error={error}>
        <Select value={category} onChange={(e) => compose(e.target.value, codes)}>
          {NOTIFICATION_CATEGORIES.map((cat) => (
            <option key={cat.id} value={cat.id}>{cat.label}</option>
          ))}
        </Select>
      </Field>
      <Field label="Favourite countries" className="md:col-span-2">
        <div className="flex flex-wrap gap-2">
          {FAVORITE_COUNTRIES.map((country) => {
            const active = codes.includes(country.code);
            return (
              <button
                key={country.code}
                type="button"
                onClick={() => toggleCode(country.code)}
                className={`rounded-full border px-3 py-1 text-sm transition ${
                  active
                    ? 'border-cyan-400 bg-cyan-400/15 text-cyan-200'
                    : 'border-white/15 text-white/70 hover:border-white/30'
                }`}
              >
                {country.code}
              </button>
            );
          })}
        </div>
        <p className="mt-2 text-xs text-white/40">
          Reaches users who follow {codes.length ? codes.join(', ') : 'any selected country'} and
          left this category on. Leave empty to target all favourite-team followers.
        </p>
      </Field>
    </>
  );
}
