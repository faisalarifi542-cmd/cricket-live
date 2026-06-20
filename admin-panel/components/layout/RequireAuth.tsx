'use client';

import { useRouter, usePathname } from 'next/navigation';
import { useEffect } from 'react';
import { Loader2 } from 'lucide-react';
import { useAuth } from '@/lib/hooks';
import type { StoredAdminUser } from '@/lib/auth';

type Props = {
  children: (auth: { user: StoredAdminUser; signOut: () => Promise<void> }) => React.ReactNode;
  permission?: string;
};

export function RequireAuth({ children, permission }: Props) {
  const router = useRouter();
  const pathname = usePathname();
  const { user, loading, signOut } = useAuth();

  useEffect(() => {
    if (!loading && !user) {
      const next = pathname ? `?next=${encodeURIComponent(pathname)}` : '';
      router.replace(`/login${next}`);
    }
  }, [loading, user, pathname, router]);

  if (loading) {
    return (
      <div className="grid min-h-screen place-items-center text-slate-400">
        <div className="flex items-center gap-2 text-sm">
          <Loader2 className="h-4 w-4 animate-spin text-cyan-300" />
          Loading session…
        </div>
      </div>
    );
  }

  if (!user) return null;

  if (permission && !user.permissions?.includes(permission)) {
    return (
      <div className="grid min-h-[60vh] place-items-center px-6 text-center">
        <div className="max-w-md">
          <h2 className="text-xl font-semibold text-slate-100">Access denied</h2>
          <p className="mt-2 text-sm text-slate-400">
            Your role does not have <code className="text-cyan-300">{permission}</code>. Ask
            a Super Admin to grant access if you need this view.
          </p>
        </div>
      </div>
    );
  }

  return <>{children({ user, signOut })}</>;
}
