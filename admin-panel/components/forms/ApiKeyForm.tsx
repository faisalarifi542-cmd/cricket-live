'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Copy } from 'lucide-react';
import { apiKeysApi } from '@/lib/api';
import { apiKeySchema, type ApiKeyInput } from '@/lib/validators';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { Field, Input, Select } from '@/components/ui/Input';
import { API_KEY_TIERS } from '@/lib/constants';

export function ApiKeyForm({
  open,
  onClose,
  onSaved,
}: {
  open: boolean;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [form, setForm] = useState<Partial<ApiKeyInput>>({
    name: '',
    email: '',
    tier: 'standard',
    rate_limit: 100,
    expires_in_days: 365,
  });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(false);
  const [generated, setGenerated] = useState<{ api_key: string; tier: string } | null>(null);

  function update<K extends keyof ApiKeyInput>(k: K, v: unknown) {
    setForm((f) => ({ ...f, [k]: v as ApiKeyInput[K] }));
  }

  async function submit() {
    const parsed = apiKeySchema.safeParse(form);
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
      const res = await apiKeysApi.create(parsed.data);
      setGenerated({ api_key: res.api_key, tier: res.tier });
      onSaved();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    } finally {
      setLoading(false);
    }
  }

  function close() {
    setGenerated(null);
    setForm({ name: '', email: '', tier: 'standard', rate_limit: 100, expires_in_days: 365 });
    onClose();
  }

  return (
    <Modal
      open={open}
      onClose={loading ? () => {} : close}
      title={generated ? 'Save this key now' : 'Create API key'}
      description={
        generated
          ? 'This key is shown only once. Copy it now — you will not be able to see it again.'
          : 'Issue an API key for a public client. Stored hashed; the raw key is shown only at creation.'
      }
      footer={
        generated ? (
          <Button onClick={close}>Done</Button>
        ) : (
          <>
            <Button variant="ghost" onClick={close} disabled={loading}>
              Cancel
            </Button>
            <Button onClick={submit} loading={loading}>
              Generate key
            </Button>
          </>
        )
      }
    >
      {generated ? (
        <div className="rounded-xl border border-cyan-300/30 bg-cyan-300/10 p-4">
          <div className="text-[10px] uppercase tracking-wide text-cyan-200">Tier · {generated.tier}</div>
          <div className="mt-2 break-all font-mono text-sm text-cyan-50">{generated.api_key}</div>
          <Button
            variant="secondary"
            size="sm"
            className="mt-3"
            icon={<Copy className="h-3.5 w-3.5" />}
            onClick={() => {
              navigator.clipboard.writeText(generated.api_key);
              toast.success('Copied');
            }}
          >
            Copy to clipboard
          </Button>
        </div>
      ) : (
        <div className="grid gap-4 md:grid-cols-2">
          <Field label="Name" required error={errors.name}>
            <Input value={form.name ?? ''} onChange={(e) => update('name', e.target.value)} />
          </Field>
          <Field label="Email" error={errors.email}>
            <Input
              type="email"
              value={(form.email ?? '') as string}
              onChange={(e) => update('email', e.target.value)}
            />
          </Field>
          <Field label="Tier">
            <Select value={form.tier ?? 'standard'} onChange={(e) => update('tier', e.target.value)}>
              {API_KEY_TIERS.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Rate limit (per minute)" error={errors.rate_limit}>
            <Input
              type="number"
              value={form.rate_limit ?? 100}
              onChange={(e) => update('rate_limit', Number(e.target.value))}
            />
          </Field>
          <Field label="Expires in (days)" error={errors.expires_in_days}>
            <Input
              type="number"
              value={form.expires_in_days ?? 365}
              onChange={(e) => update('expires_in_days', Number(e.target.value))}
            />
          </Field>
        </div>
      )}
    </Modal>
  );
}
