'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { navigation, navigationGroups } from '@/lib/constants';
import { cn } from '@/lib/utils';
import { hasPermission } from '@/lib/permissions';
import type { StoredAdminUser } from '@/lib/auth';

export function AdminSidebar({ user }: { user: StoredAdminUser }) {
  const pathname = usePathname();
  return (
    <aside className="fixed inset-y-0 left-0 z-30 hidden w-72 flex-col border-r border-line bg-ink/95 px-4 py-5 backdrop-blur-xl lg:flex">
      <Link href="/dashboard" className="mb-7 flex items-center gap-3 px-2">
        <div className="grid h-11 w-11 place-items-center rounded-xl bg-gradient-to-br from-cyan-300 to-cyan-500 text-slate-950 shadow-glow">
          <span className="text-base font-black">CP</span>
        </div>
        <div>
          <div className="text-base font-semibold leading-tight text-slate-100">
            CricPro Admin
          </div>
          <div className="text-xs text-cyan-200/70">Live cricket operations</div>
        </div>
      </Link>
      <nav className="flex-1 space-y-5 overflow-y-auto pr-1">
        {navigationGroups.map((group) => {
          const items = navigation.filter(
            (n) =>
              n.group === group.id &&
              (!n.permission || hasPermission(user.permissions, n.permission)),
          );
          if (!items.length) return null;
          return (
            <div key={group.id}>
              <div className="px-3 pb-2 text-[10px] font-semibold uppercase tracking-wider text-slate-500">
                {group.label}
              </div>
              <div className="space-y-1">
                {items.map((item) => {
                  const active =
                    pathname === item.href ||
                    pathname.startsWith(`${item.href}/`);
                  const Icon = item.icon;
                  return (
                    <Link
                      key={item.href}
                      href={item.href}
                      className={cn(
                        'flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm text-slate-300 transition hover:bg-cyan-400/10 hover:text-white',
                        active &&
                          'bg-cyan-400/15 text-cyan-100 ring-1 ring-cyan-300/20',
                      )}
                    >
                      <Icon className="h-4 w-4" />
                      {item.label}
                    </Link>
                  );
                })}
              </div>
            </div>
          );
        })}
      </nav>
    </aside>
  );
}
