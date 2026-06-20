'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { usersApi } from '@/lib/api';
import { userSchema, type UserInput } from '@/lib/validators';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { Field, Input } from '@/components/ui/Input';
import { Switch } from '@/components/ui/Switch';

type FormValue = Partial<UserInput> & { id?: number };

export function UserForm({
  open,
  onClose,
  initial,
  availableRoles,
  onSaved,
}: {
  open: boolean;
  onClose: () => void;
  initial?: FormValue | null;
  availableRoles: { slug: string; name: string }[];
  onSaved: () => void;
}) {
  const isEdit = !!initial?.id;
  const [form, setForm] = useState<FormValue>(() => ({
    name: initial?.name ?? '',
    email: initial?.email ?? '',
    password: '',
    is_active: initial?.is_active ?? true,
    roles: initial?.roles ?? [],
  }));
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(false);

  function toggleRole(slug: string) {
    setForm((p) => {
      const current = new Set(p.roles ?? []);
      if (current.has(slug)) current.delete(slug);
      else current.add(slug);
      return { ...p, roles: Array.from(current) };
    });
  }

  async function submit() {
    const parsed = userSchema.safeParse(form);
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
    if (!isEdit && !parsed.data.password) {
      setErrors({ password: 'Password required for new users' });
      return;
    }
    setErrors({});
    setLoading(true);
    try {
      const body: Record<string, unknown> = {
        name: parsed.data.name,
        email: parsed.data.email,
        is_active: parsed.data.is_active,
      };
      if (isEdit && initial?.id) {
        await usersApi.update(initial.id, body);
        if (parsed.data.password) {
          await usersApi.resetPassword(initial.id, parsed.data.password);
        }
        await usersApi.setRoles(initial.id, parsed.data.roles ?? []);
        toast.success('User updated');
      } else {
        const r = await usersApi.create({
          name: parsed.data.name,
          email: parsed.data.email,
          password: parsed.data.password || '',
        });
        if (r.id) {
          await usersApi.setRoles(r.id, parsed.data.roles ?? []);
        }
        toast.success('User created');
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
      title={isEdit ? 'Edit admin user' : 'Add admin user'}
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={loading}>Cancel</Button>
          <Button onClick={submit} loading={loading}>{isEdit ? 'Save' : 'Create'}</Button>
        </>
      }
    >
      <div className="grid gap-4 md:grid-cols-2">
        <Field label="Name" required error={errors.name}>
          <Input value={form.name ?? ''} onChange={(e) => setForm((p) => ({ ...p, name: e.target.value }))} />
        </Field>
        <Field label="Email" required error={errors.email}>
          <Input type="email" value={form.email ?? ''} onChange={(e) => setForm((p) => ({ ...p, email: e.target.value }))} />
        </Field>
        <Field label={isEdit ? 'New password (leave blank to keep)' : 'Password'} error={errors.password} className="md:col-span-2">
          <Input type="password" value={(form.password as string | undefined) ?? ''} onChange={(e) => setForm((p) => ({ ...p, password: e.target.value }))} />
        </Field>
      </div>
      <div className="mt-3">
        <Switch checked={Boolean(form.is_active)} onChange={(v) => setForm((p) => ({ ...p, is_active: v }))} label="Active" description="Inactive users cannot log in." />
      </div>
      <div className="mt-5">
        <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-400">Roles</div>
        <div className="flex flex-wrap gap-2">
          {availableRoles.map((r) => {
            const on = (form.roles ?? []).includes(r.slug);
            return (
              <button
                key={r.slug}
                type="button"
                onClick={() => toggleRole(r.slug)}
                className={`rounded-lg border px-3 py-1.5 text-xs transition ${on ? 'border-cyan-300/40 bg-cyan-300/15 text-cyan-100' : 'border-line bg-white/5 text-slate-300 hover:bg-white/10'}`}
              >
                {r.name}
              </button>
            );
          })}
        </div>
      </div>
    </Modal>
  );
}
