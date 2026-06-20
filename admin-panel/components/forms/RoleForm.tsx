'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { rolesApi } from '@/lib/api';
import { roleSchema, type RoleInput } from '@/lib/validators';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { Field, Input, Textarea } from '@/components/ui/Input';
import { PERMISSION_GROUPS, PERMISSION_LABELS } from '@/lib/permissions';

type FormValue = Partial<RoleInput> & { slug?: string };

export function RoleForm({
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
  const isEdit = !!initial?.slug;
  const [form, setForm] = useState<FormValue>(() => ({
    slug: initial?.slug ?? '',
    name: initial?.name ?? '',
    description: initial?.description ?? '',
    permissions: initial?.permissions ?? [],
  }));
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(false);

  function toggle(p: string) {
    setForm((prev) => {
      const set = new Set(prev.permissions ?? []);
      if (set.has(p)) set.delete(p);
      else set.add(p);
      return { ...prev, permissions: Array.from(set) };
    });
  }

  function toggleGroup(perms: string[]) {
    setForm((prev) => {
      const current = new Set(prev.permissions ?? []);
      const allOn = perms.every((p) => current.has(p));
      if (allOn) perms.forEach((p) => current.delete(p));
      else perms.forEach((p) => current.add(p));
      return { ...prev, permissions: Array.from(current) };
    });
  }

  async function submit() {
    const parsed = roleSchema.safeParse(form);
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
      if (isEdit && initial?.slug) {
        await rolesApi.update(initial.slug, {
          name: parsed.data.name,
          description: parsed.data.description,
          permissions: parsed.data.permissions,
        });
        toast.success('Role updated');
      } else {
        await rolesApi.create({
          slug: parsed.data.slug,
          name: parsed.data.name,
          description: parsed.data.description ?? undefined,
          permissions: parsed.data.permissions,
        });
        toast.success('Role created');
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
      title={isEdit ? `Edit role: ${initial?.slug}` : 'New role'}
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
          <Input value={form.slug ?? ''} onChange={(e) => setForm((p) => ({ ...p, slug: e.target.value }))} disabled={isEdit} />
        </Field>
        <Field label="Name" required error={errors.name}>
          <Input value={form.name ?? ''} onChange={(e) => setForm((p) => ({ ...p, name: e.target.value }))} />
        </Field>
        <Field label="Description" className="md:col-span-2">
          <Textarea rows={2} value={(form.description as string | undefined) ?? ''} onChange={(e) => setForm((p) => ({ ...p, description: e.target.value }))} />
        </Field>
      </div>
      <div className="mt-5">
        <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400">Permissions</div>
        <div className="grid gap-3 md:grid-cols-2">
          {PERMISSION_GROUPS.map((g) => {
            const allOn = g.permissions.every((p) => (form.permissions ?? []).includes(p));
            const anyOn = g.permissions.some((p) => (form.permissions ?? []).includes(p));
            return (
              <div key={g.label} className="rounded-xl border border-line bg-white/5 p-3">
                <div className="mb-2 flex items-center justify-between">
                  <div className="text-sm font-semibold text-slate-100">{g.label}</div>
                  <button
                    type="button"
                    onClick={() => toggleGroup(g.permissions)}
                    className="text-[10px] uppercase tracking-wide text-cyan-200 hover:text-cyan-100"
                  >
                    {allOn ? 'Disable all' : anyOn ? 'Enable all' : 'Enable all'}
                  </button>
                </div>
                <div className="space-y-1">
                  {g.permissions.map((p) => {
                    const checked = (form.permissions ?? []).includes(p);
                    return (
                      <label key={p} className="flex items-center gap-2 text-xs text-slate-300">
                        <input type="checkbox" checked={checked} onChange={() => toggle(p)} className="accent-cyan-400" />
                        <span>{PERMISSION_LABELS[p] ?? p}</span>
                      </label>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </Modal>
  );
}
