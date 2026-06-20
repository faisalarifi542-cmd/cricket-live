'use client';

import { hasPermission } from '@/lib/permissions';
import { useAuth } from '@/lib/hooks';

type Props = {
  permission: string;
  children: React.ReactNode;
  fallback?: React.ReactNode;
};

export function PermissionGate({ permission, children, fallback = null }: Props) {
  const { user } = useAuth();
  if (!hasPermission(user?.permissions, permission)) return <>{fallback}</>;
  return <>{children}</>;
}
