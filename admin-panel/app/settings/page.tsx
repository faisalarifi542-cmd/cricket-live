'use client';

import { useState } from 'react';
import { AdminShell } from '@/components/layout/AdminShell';
import { PageHeader } from '@/components/ui/PageHeader';
import { Tabs } from '@/components/ui/Tabs';
import { AppSettingsForm } from '@/components/forms/AppSettingsForm';
import { SETTING_GROUPS } from '@/lib/constants';
import { useAuth, usePermissions } from '@/lib/hooks';
import { titleCase } from '@/lib/utils';

export default function SettingsPage() {
  return (
    <AdminShell permission="settings.view">
      <SettingsInner />
    </AdminShell>
  );
}

function SettingsInner() {
  const { user } = useAuth();
  const perms = usePermissions(user);
  const [group, setGroup] = useState<string>(SETTING_GROUPS[0]);

  return (
    <>
      <PageHeader
        title="App settings"
        description="Global controls — maintenance mode, force update, feature toggles, stream defaults, refresh intervals, error messages, and UI theme."
      />
      <div className="mb-4">
        <Tabs
          tabs={SETTING_GROUPS.map((g) => ({ id: g, label: titleCase(g) }))}
          value={group}
          onChange={setGroup}
        />
      </div>
      <AppSettingsForm group={group} canWrite={perms.can('settings.write')} />
    </>
  );
}
