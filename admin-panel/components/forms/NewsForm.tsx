'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { newsApi } from '@/lib/api';
import { newsSchema, type NewsInput } from '@/lib/validators';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { Field, Input, Textarea } from '@/components/ui/Input';
import { Switch } from '@/components/ui/Switch';

type FormValue = Partial<NewsInput> & { id?: number };

export function NewsForm({
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
    headline: initial?.headline ?? '',
    body: initial?.body ?? '',
    context: initial?.context ?? '',
    story_type: initial?.story_type ?? 'custom',
    image_url: initial?.image_url ?? '',
    source: initial?.source ?? 'CricPro',
    is_featured: initial?.is_featured ?? false,
    is_hidden: initial?.is_hidden ?? false,
    sort_order: initial?.sort_order ?? 100,
    published_at: initial?.published_at ?? '',
  }));
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(false);

  function update<K extends keyof NewsInput>(k: K, v: unknown) {
    setForm((p) => ({ ...p, [k]: v as NewsInput[K] }));
  }

  async function submit() {
    const parsed = newsSchema.safeParse(form);
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
        await newsApi.update(initial.id, parsed.data);
        toast.success('News updated');
      } else {
        await newsApi.create(parsed.data);
        toast.success('News created');
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
      title={isEdit ? 'Edit news story' : 'New news story'}
      size="lg"
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={loading}>Cancel</Button>
          <Button onClick={submit} loading={loading}>{isEdit ? 'Save' : 'Publish'}</Button>
        </>
      }
    >
      <div className="grid gap-4 md:grid-cols-2">
        <Field label="Headline" required error={errors.headline} className="md:col-span-2">
          <Input value={form.headline ?? ''} onChange={(e) => update('headline', e.target.value)} />
        </Field>
        <Field label="Context" className="md:col-span-2">
          <Input value={(form.context as string | undefined) ?? ''} onChange={(e) => update('context', e.target.value)} />
        </Field>
        <Field label="Body" className="md:col-span-2">
          <Textarea rows={6} value={(form.body as string | undefined) ?? ''} onChange={(e) => update('body', e.target.value)} />
        </Field>
        <Field label="Image URL" error={errors.image_url} className="md:col-span-2">
          <Input value={(form.image_url as string | undefined) ?? ''} onChange={(e) => update('image_url', e.target.value)} />
        </Field>
        <Field label="Source">
          <Input value={form.source ?? 'CricPro'} onChange={(e) => update('source', e.target.value)} />
        </Field>
        <Field label="Story type">
          <Input value={form.story_type ?? 'custom'} onChange={(e) => update('story_type', e.target.value)} />
        </Field>
        <Field label="Published at">
          <Input type="datetime-local" value={(form.published_at as string | undefined) ?? ''} onChange={(e) => update('published_at', e.target.value)} />
        </Field>
        <Field label="Sort order">
          <Input type="number" value={form.sort_order ?? 100} onChange={(e) => update('sort_order', Number(e.target.value))} />
        </Field>
      </div>
      <div className="mt-4 flex gap-4">
        <Switch checked={Boolean(form.is_featured)} onChange={(v) => update('is_featured', v)} label="Featured" />
        <Switch checked={Boolean(form.is_hidden)} onChange={(v) => update('is_hidden', v)} label="Hidden" />
      </div>
    </Modal>
  );
}
