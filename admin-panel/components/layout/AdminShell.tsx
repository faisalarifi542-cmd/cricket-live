'use client';

import { RequireAuth } from './RequireAuth';
import { AdminSidebar } from './AdminSidebar';
import { AdminTopbar } from './AdminTopbar';
import { AdminBreadcrumbs } from './AdminBreadcrumbs';

type AdminShellProps = {
  children: React.ReactNode;
  permission?: string;
};

export function AdminShell({ children, permission }: AdminShellProps) {
  return (
    <RequireAuth permission={permission}>
      {({ user, signOut }) => (
        <div className="min-h-screen">
          <AdminSidebar user={user} />
          <div className="lg:pl-72">
            <AdminTopbar user={user} onSignOut={signOut} />
            <main className="px-4 py-6 lg:px-8">
              <AdminBreadcrumbs />
              {children}
            </main>
          </div>
        </div>
      )}
    </RequireAuth>
  );
}
