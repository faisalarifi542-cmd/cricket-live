'use client';

import { useEffect, useRef, useState } from 'react';
import { ChevronDown, Key, LogOut, ShieldCheck, User } from 'lucide-react';
import type { StoredAdminUser } from '@/lib/auth';
import { cn } from '@/lib/utils';
import { ChangePasswordDialog } from '@/components/forms/ChangePasswordDialog';

type Props = {
  user: StoredAdminUser;
  onSignOut: () => Promise<void>;
};

export function AdminTopbar({ user, onSignOut }: Props) {
  const [open, setOpen] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function onClick(e: MouseEvent) {
      if (!menuRef.current?.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener('mousedown', onClick);
    return () => document.removeEventListener('mousedown', onClick);
  }, []);

  const initials = (user.name || user.email)
    .split(/[\s@]/)
    .filter(Boolean)
    .map((s) => s[0]?.toUpperCase())
    .slice(0, 2)
    .join('');

  return (
    <header className="sticky top-0 z-20 border-b border-line bg-ink/70 px-4 py-3 backdrop-blur-xl lg:px-8">
      <div className="flex items-center justify-between gap-3">
        <div className="hidden items-center gap-2 rounded-lg border border-emerald-400/20 bg-emerald-400/10 px-3 py-1.5 text-xs text-emerald-200 sm:flex">
          <ShieldCheck className="h-3.5 w-3.5" />
          Secure session
        </div>

        <div className="flex flex-1 items-center justify-end gap-3">
          <div className="hidden text-right text-xs leading-tight sm:block">
            <div className="font-medium text-slate-100">{user.name || user.email}</div>
            <div className="text-slate-500">
              {(user.roleNames || user.roles || []).join(', ') || 'Admin'}
            </div>
          </div>
          <div className="relative" ref={menuRef}>
            <button
              onClick={() => setOpen((o) => !o)}
              className={cn(
                'flex items-center gap-2 rounded-lg border border-line bg-white/5 px-2 py-1.5 text-sm text-slate-200 transition hover:bg-white/10',
                open && 'bg-white/10',
              )}
            >
              <span className="grid h-7 w-7 place-items-center rounded-md bg-cyan-400/20 text-xs font-semibold text-cyan-100">
                {initials || 'AD'}
              </span>
              <ChevronDown className="h-3.5 w-3.5 text-slate-400" />
            </button>
            {open && (
              <div className="absolute right-0 top-12 z-30 w-56 overflow-hidden rounded-xl border border-line bg-panel/95 text-sm shadow-xl backdrop-blur-xl">
                <div className="border-b border-line px-3 py-3">
                  <div className="flex items-center gap-2 text-slate-100">
                    <User className="h-3.5 w-3.5 text-cyan-300" />
                    <span className="font-medium">{user.name || 'Admin'}</span>
                  </div>
                  <div className="mt-1 text-xs text-slate-500">{user.email}</div>
                </div>
                <button
                  onClick={() => {
                    setOpen(false);
                    setShowPassword(true);
                  }}
                  className="flex w-full items-center gap-2 px-3 py-2.5 text-left text-slate-200 transition hover:bg-white/5"
                >
                  <Key className="h-3.5 w-3.5" />
                  Change password
                </button>
                <button
                  onClick={() => {
                    setOpen(false);
                    onSignOut();
                  }}
                  className="flex w-full items-center gap-2 border-t border-line px-3 py-2.5 text-left text-red-300 transition hover:bg-red-500/10"
                >
                  <LogOut className="h-3.5 w-3.5" />
                  Sign out
                </button>
              </div>
            )}
          </div>
        </div>
      </div>
      <ChangePasswordDialog open={showPassword} onOpenChange={setShowPassword} />
    </header>
  );
}
