'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { homeApi } from '@/lib/api';
import { homeSectionSchema, type HomeSectionInput } from '@/lib/validators';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { Field, Input, Select, Textarea } from '@/components/ui/Input';
import { Switch } from '@/components/ui/Switch';

type FormValue = Partial<HomeSectionInput> & { id?: number };

export function HomeSectionForm({
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
    slug: initial?.slug ?? '',
    title: initial?.title ?? '',
    section_type: initial?.section_type ?? 'live_matches',
    sort_order: initial?.sort_order ?? 100,
    is_active: initial?.is_active ?? true,
    starts_at: initial?.starts_at ?? '',
    ends_at: initial?.ends_at ?? '',
    payload: initial?.payload ?? '',
  }));
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(false);

  function update<K extends keyof HomeSectionInput>(k: K, v: unknown) {
    setForm((p) => ({ ...p, [k]: v as HomeSectionInput[K] }));
  }

  async function submit() {
    const parsed = homeSectionSchema.safeParse(form);
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
        await homeApi.updateSection(initial.id, parsed.data);
        toast.success('Section updated');
      } else {
        await homeApi.createSection(parsed.data);
        toast.success('Section created');
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
      title={isEdit ? 'Edit home section' : 'New home section'}
      description="Home sections are rendered top-to-bottom by sort order."
      size="lg"
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={loading}>Cancel</Button>
          <Button onClick={submit} loading={loading}>{isEdit ? 'Save' : 'Create'}</Button>
        </>
      }
    >
      <div className="grid gap-4 md:grid-cols-2">
        <Field label="Slug" required error={errors.slug}>
          <Input value={form.slug ?? ''} onChange={(e) => update('slug', e.target.value)} disabled={isEdit} />
        </Field>
        <Field label="Title" required error={errors.title}>
          <Input value={form.title ?? ''} onChange={(e) => update('title', e.target.value)} />
        </Field>
        <Field label="Section type" required error={errors.section_type}>
          <Select value={form.section_type ?? 'live_matches'} onChange={(e) => update('section_type', e.target.value)}>
            <option value="live_matches">Live matches</option>
            <option value="upcoming_matches">Upcoming matches</option>
            <option value="finished_matches">Finished matches</option>
            <option value="featured_matches">Featured matches</option>
            <option value="featured_series">Featured series</option>
            <option value="featured_news">Featured news</option>
            <option value="banners">Banners</option>
            <option value="custom">Custom</option>
          </Select>
        </Field>
        <Field label="Sort order" error={errors.sort_order}>
          <Input type="number" value={form.sort_order ?? 100} onChange={(e) => update('sort_order', Number(e.target.value))} />
        </Field>
        <Field label="Starts at">
          <Input type="datetime-local" value={form.starts_at ?? ''} onChange={(e) => update('starts_at', e.target.value)} />
        </Field>
        <Field label="Ends at">
          <Input type="datetime-local" value={form.ends_at ?? ''} onChange={(e) => update('ends_at', e.target.value)} />
        </Field>
      </div>
      <Field label="Payload (JSON)" className="mt-4">
        <Textarea
          rows={4}
          className="font-mono text-xs"
          value={form.payload ?? ''}
          onChange={(e) => update('payload', e.target.value)}
          placeholder='{"limit": 8}'
        />
      </Field>
      <div className="mt-3">
        <Switch
          checked={Boolean(form.is_active)}
          onChange={(v) => update('is_active', v)}
          label="Active"
          description="Hidden sections are excluded from /home-config."
        />
      </div>
    </Modal>
  );
}
