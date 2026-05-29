'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { streamsApi } from '@/lib/api';
import { streamSchema, type StreamInput } from '@/lib/validators';
import { STREAM_QUALITIES, STREAM_TYPES } from '@/lib/constants';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { Field, Input, Select, Textarea } from '@/components/ui/Input';
import { Switch } from '@/components/ui/Switch';

export type StreamFormValue = Partial<StreamInput> & { id?: number };

type Props = {
  open: boolean;
  onClose: () => void;
  initial?: StreamFormValue | null;
  defaultMatchId?: string;
  onSaved: () => void;
};

function dtLocal(v?: string | null) {
  if (!v) return '';
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return '';
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function StreamForm({ open, onClose, initial, defaultMatchId, onSaved }: Props) {
  const isEdit = !!initial?.id;
  const [form, setForm] = useState<StreamFormValue>(() => ({
    match_external_id: initial?.match_external_id ?? defaultMatchId ?? '',
    title: initial?.title ?? '',
    label: initial?.label ?? '',
    language: initial?.language ?? '',
    server_name: initial?.server_name ?? '',
    quality: initial?.quality ?? 'AUTO',
    stream_type: initial?.stream_type ?? 'hls',
    stream_url: initial?.stream_url ?? '',
    is_active: initial?.is_active ?? true,
    is_premium: initial?.is_premium ?? false,
    priority: initial?.priority ?? 100,
    starts_at: dtLocal(initial?.starts_at as string | undefined),
    ends_at: dtLocal(initial?.ends_at as string | undefined),
    user_agent_header: initial?.user_agent_header ?? '',
    referer_header: initial?.referer_header ?? '',
    drm_enabled: initial?.drm_enabled ?? false,
    notes: initial?.notes ?? '',
  }));
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(false);

  function update<K extends keyof StreamFormValue>(key: K, value: StreamFormValue[K]) {
    setForm((f) => ({ ...f, [key]: value }));
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const parsed = streamSchema.safeParse({
      ...form,
      starts_at: form.starts_at ? new Date(form.starts_at).toISOString() : null,
      ends_at: form.ends_at ? new Date(form.ends_at).toISOString() : null,
    });
    if (!parsed.success) {
      const flat = parsed.error.flatten().fieldErrors;
      setErrors(
        Object.fromEntries(
          Object.entries(flat)
            .filter(([, v]) => Array.isArray(v) && v.length)
            .map(([k, v]) => [k, (v as string[])[0]]),
        ),
      );
      return;
    }
    setErrors({});
    setLoading(true);
    try {
      const payload = {
        ...parsed.data,
        // backend expects 0/1 ints; api layer doesn't transform — backend normalises booleans
      };
      if (isEdit && initial?.id) {
        await streamsApi.update(initial.id, payload as Record<string, unknown>);
        toast.success('Stream updated');
      } else {
        await streamsApi.create(payload as Record<string, unknown>);
        toast.success('Stream created');
      }
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to save');
    } finally {
      setLoading(false);
    }
  }

  return (
    <Modal
      open={open}
      onClose={loading ? () => {} : onClose}
      title={isEdit ? 'Edit live stream' : 'Add live stream'}
      description="Streams are matched to live cricket matches by their external match ID."
      size="lg"
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={loading}>
            Cancel
          </Button>
          <Button onClick={submit} loading={loading}>
            {isEdit ? 'Save changes' : 'Create stream'}
          </Button>
        </>
      }
    >
      <form onSubmit={submit} className="grid grid-cols-1 gap-4 md:grid-cols-2">
        <Field label="Match external ID" required error={errors.match_external_id}>
          <Input
            value={form.match_external_id ?? ''}
            onChange={(e) => update('match_external_id', e.target.value)}
            placeholder="e.g. 12345"
            invalid={!!errors.match_external_id}
          />
        </Field>

        <Field label="Stream URL" required error={errors.stream_url}>
          <Input
            value={form.stream_url ?? ''}
            onChange={(e) => update('stream_url', e.target.value)}
            placeholder="https://example.com/live/playlist.m3u8"
            invalid={!!errors.stream_url}
          />
        </Field>

        <Field label="Title" error={errors.title}>
          <Input
            value={form.title ?? ''}
            onChange={(e) => update('title', e.target.value)}
            placeholder="Premium HD"
          />
        </Field>

        <Field label="Label" error={errors.label}>
          <Input
            value={form.label ?? ''}
            onChange={(e) => update('label', e.target.value)}
            placeholder="HD-1"
          />
        </Field>

        <Field label="Quality" required error={errors.quality}>
          <Select
            value={form.quality}
            onChange={(e) => update('quality', e.target.value as StreamFormValue['quality'])}
          >
            {STREAM_QUALITIES.map((q) => (
              <option key={q} value={q} className="bg-slate-900">
                {q}
              </option>
            ))}
          </Select>
        </Field>

        <Field label="Stream type" required error={errors.stream_type}>
          <Select
            value={form.stream_type}
            onChange={(e) =>
              update('stream_type', e.target.value as StreamFormValue['stream_type'])
            }
          >
            {STREAM_TYPES.map((t) => (
              <option key={t} value={t} className="bg-slate-900">
                {t.toUpperCase()}
              </option>
            ))}
          </Select>
        </Field>

        <Field label="Server name" error={errors.server_name}>
          <Input
            value={form.server_name ?? ''}
            onChange={(e) => update('server_name', e.target.value)}
            placeholder="Akamai EU"
          />
        </Field>

        <Field label="Language" error={errors.language}>
          <Input
            value={form.language ?? ''}
            onChange={(e) => update('language', e.target.value)}
            placeholder="English"
          />
        </Field>

        <Field label="Priority" required error={errors.priority} hint="Lower numbers are higher priority">
          <Input
            type="number"
            value={form.priority ?? 100}
            onChange={(e) => update('priority', Number(e.target.value) as StreamFormValue['priority'])}
            invalid={!!errors.priority}
          />
        </Field>

        <Field label="Starts at" error={errors.starts_at}>
          <Input
            type="datetime-local"
            value={form.starts_at ?? ''}
            onChange={(e) => update('starts_at', e.target.value)}
          />
        </Field>

        <Field label="Ends at" error={errors.ends_at}>
          <Input
            type="datetime-local"
            value={form.ends_at ?? ''}
            onChange={(e) => update('ends_at', e.target.value)}
          />
        </Field>

        <Field label="Custom User-Agent" error={errors.user_agent_header}>
          <Input
            value={form.user_agent_header ?? ''}
            onChange={(e) => update('user_agent_header', e.target.value)}
            placeholder="Optional override sent on health checks"
          />
        </Field>

        <Field label="Custom Referer" error={errors.referer_header}>
          <Input
            value={form.referer_header ?? ''}
            onChange={(e) => update('referer_header', e.target.value)}
            placeholder="Optional referer header"
          />
        </Field>

        <div className="md:col-span-2">
          <Field label="Notes" error={errors.notes}>
            <Textarea
              value={form.notes ?? ''}
              onChange={(e) => update('notes', e.target.value)}
              placeholder="Internal notes about this stream"
              rows={2}
            />
          </Field>
        </div>

        <div className="md:col-span-2 grid gap-3 rounded-xl border border-line bg-white/[0.04] p-3 md:grid-cols-3">
          <Switch
            label="Active"
            description="Visible to clients"
            checked={!!form.is_active}
            onChange={(v) => update('is_active', v)}
          />
          <Switch
            label="Premium"
            description="Restricted to premium users"
            checked={!!form.is_premium}
            onChange={(v) => update('is_premium', v)}
          />
          <Switch
            label="DRM"
            description="Stream is DRM protected"
            checked={!!form.drm_enabled}
            onChange={(v) => update('drm_enabled', v)}
          />
        </div>
      </form>
    </Modal>
  );
}
