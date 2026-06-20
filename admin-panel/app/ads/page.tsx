'use client';

import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { AdsSettingsForm } from '@/components/forms/AdsSettingsForm';
import { useAuth, usePermissions } from '@/lib/hooks';

export default function AdsPage() {
  return (
    <AdminShell permission="ads.view">
      <Inner />
    </AdminShell>
  );
}

function Inner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  return (
    <>
      <PageHeader
        title="Ads"
        description="Global toggle, primary network + fallback waterfall, per-network (AdMob / Unity / Meta) settings, placement and frequency controls, and consent."
      />
      <AdsSettingsForm canWrite={perms.can('ads.write')} />
    </>
  );
}
