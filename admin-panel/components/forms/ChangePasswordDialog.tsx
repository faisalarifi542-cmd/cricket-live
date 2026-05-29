'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { authApi } from '@/lib/api';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { Field, Input } from '@/components/ui/Input';

type Props = { open: boolean; onOpenChange: (v: boolean) => void };

export function ChangePasswordDialog({ open, onOpenChange }: Props) {
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [loading, setLoading] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (next.length < 8) return toast.error('Password must be at least 8 characters');
    if (next !== confirm) return toast.error('Passwords do not match');
    setLoading(true);
    try {
      await authApi.changePassword(current, next);
      toast.success('Password updated. Please sign in again.');
      setCurrent('');
      setNext('');
      setConfirm('');
      onOpenChange(false);
      setTimeout(() => {
        window.location.href = '/login';
      }, 600);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed');
    } finally {
      setLoading(false);
    }
  }

  return (
    <Modal
      open={open}
      onClose={() => onOpenChange(false)}
      title="Change password"
      description="You'll be signed out and need to log in with the new password."
      size="sm"
    >
      <form onSubmit={submit} className="space-y-4">
        <Field label="Current password" required>
          <Input
            type="password"
            value={current}
            onChange={(e) => setCurrent(e.target.value)}
            autoComplete="current-password"
          />
        </Field>
        <Field label="New password" required hint="At least 8 characters">
          <Input
            type="password"
            value={next}
            onChange={(e) => setNext(e.target.value)}
            autoComplete="new-password"
          />
        </Field>
        <Field label="Confirm new password" required>
          <Input
            type="password"
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            autoComplete="new-password"
          />
        </Field>
        <div className="flex justify-end gap-2">
          <Button
            type="button"
            variant="ghost"
            onClick={() => onOpenChange(false)}
            disabled={loading}
          >
            Cancel
          </Button>
          <Button type="submit" loading={loading}>
            Update password
          </Button>
        </div>
      </form>
    </Modal>
  );
}
