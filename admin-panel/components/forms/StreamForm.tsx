'use client';

import { useEffect, useState } from 'react';
import { toast } from 'sonner';
import { ChevronDown, ChevronRight, Lock } from 'lucide-react';
import { streamsApi, type StreamNotificationStatus } from '@/lib/api';
import { streamSchema, type StreamInput } from '@/lib/validators';
import { DRM_TYPES, STREAM_QUALITIES, STREAM_STATUSES } from '@/lib/constants';
import { Modal } from '@/components/ui/Modal';
import { Button } from '@/components/ui/Button';
import { Field, Input, Select, Textarea } from '@/components/ui/Input';
import { Switch } from '@/components/ui/Switch';

export type StreamFormValue = Partial<StreamInput> & { id?: number; send_push_now?: boolean; notify_on_publish?: boolean };

// Read-only match context shown when a stream is created from a synced match.
// The editor never types these — they come from real provider data.
export type StreamMatchMeta = {
  match_external_id?: string;
  matchup?: string;
  series_name?: string;
  venue?: string;
  start_time?: string | null;
  status_text?: string;
  phase?: 'live' | 'upcoming';
};

type Props = {
  open: boolean;
  onClose: () => void;
  initial?: StreamFormValue | null;
  defaultMatchId?: string;
  /** Real match metadata to auto-fill + lock (from the Sync flow). */
  matchMeta?: StreamMatchMeta | null;
  /** When true the match fields are read-only (auto-filled from real data). */
  lockMatch?: boolean;
  onSaved: () => void;
};

// Simplified stream types for non-technical editors. Maps the friendly label to
// the backend stream_type value. "Other" keeps DASH support available.
const SIMPLE_STREAM_TYPES: { value: string; label: string }[] = [
  { value: 'hls', label: 'HLS / M3U8' },
  { value: 'iframe', label: 'Embed (iframe)' },
  { value: 'external', label: 'External link' },
  { value: 'dash', label: 'Other (DASH/MPD)' },
];

function dtLocal(v?: string | null) {
  if (!v) return '';
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return '';
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function buildInitial(initial?: StreamFormValue | null, defaultMatchId?: string): StreamFormValue {
  return {
    match_external_id: initial?.match_external_id ?? defaultMatchId ?? '',
    match_title: initial?.match_title ?? '',
    title: initial?.title ?? '',
    team_a: initial?.team_a ?? '',
    team_b: initial?.team_b ?? '',
    label: initial?.label ?? '',
    language: initial?.language ?? '',
    server_name: initial?.server_name ?? '',
    quality: initial?.quality ?? 'AUTO',
    stream_type: initial?.stream_type ?? 'hls',
    stream_url: initial?.stream_url ?? '',
    backup_stream_url: initial?.backup_stream_url ?? '',
    status: initial?.status ?? 'unknown',
    is_active: initial?.is_active ?? true,
    is_premium: initial?.is_premium ?? false,
    requires_reward_ad: initial?.requires_reward_ad ?? false,
    requires_login: initial?.requires_login ?? false,
    priority: initial?.priority ?? 100,
    starts_at: dtLocal(initial?.starts_at as string | undefined),
    ends_at: dtLocal(initial?.ends_at as string | undefined),
    lifecycle_state: initial?.lifecycle_state ?? 'scheduled',
    timezone: initial?.timezone ?? (typeof Intl !== 'undefined' ? Intl.DateTimeFormat().resolvedOptions().timeZone : ''),
    early_show_minutes: initial?.early_show_minutes ?? 0,
    auto_hide_after_end: initial?.auto_hide_after_end ?? true,
    headers_json: typeof initial?.headers_json === 'string' ? initial.headers_json : initial?.headers_json ? JSON.stringify(initial.headers_json, null, 2) : '',
    user_agent_header: initial?.user_agent_header ?? '',
    referer_header: initial?.referer_header ?? '',
    origin_header: initial?.origin_header ?? '',
    drm_enabled: initial?.drm_enabled ?? false,
    drm_type: initial?.drm_type ?? 'none',
    drm_license_url: initial?.drm_license_url ?? '',
    drm_headers: typeof initial?.drm_headers === 'string' ? initial.drm_headers : initial?.drm_headers ? JSON.stringify(initial.drm_headers, null, 2) : '',
    clear_key_key_id: initial?.clear_key_key_id ?? '',
    clear_key_key: initial?.clear_key_key ?? '',
    // "Send notification on publish" defaults ON (matches backend). Existing
    // records that never set it also default ON so the toggle reflects intent.
    notify_on_publish: initial?.notify_on_publish ?? true,
    send_push_now: false,
    notes: initial?.notes ?? '',
  };
}

// Draft vs Published is the single primary status the editor manages. Published
// means active + not draft/disabled (mirrors the backend isStreamPublished).
function isPublished(form: StreamFormValue) {
  const state = String(form.lifecycle_state ?? 'scheduled').toLowerCase();
  return !!form.is_active && state !== 'draft' && state !== 'disabled';
}

export function StreamForm({ open, onClose, initial, defaultMatchId, matchMeta, lockMatch, onSaved }: Props) {
  const isEdit = !!initial?.id;
  const [form, setForm] = useState<StreamFormValue>(() => buildInitial(initial, defaultMatchId));
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);

  // CRITICAL: the modal stays mounted (open toggles), so re-seed the form every
  // time it opens or the target record changes — otherwise an Edit shows stale
  // / blank values (the previous "edit form is empty" bug). Never blank an edit.
  useEffect(() => {
    if (!open) return;
    setForm(buildInitial(initial, defaultMatchId));
    setErrors({});
    setShowAdvanced(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, initial, defaultMatchId]);

  function update<K extends keyof StreamFormValue>(key: K, value: StreamFormValue[K]) {
    setForm((f) => ({ ...f, [key]: value }));
  }

  function setPublishStatus(status: 'draft' | 'published') {
    setForm((f) => ({
      ...f,
      is_active: status === 'published',
      lifecycle_state: status === 'published' ? 'active' : 'draft',
    }));
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const parsed = streamSchema.safeParse({
      ...form,
      starts_at: form.starts_at ? new Date(form.starts_at).toISOString() : null,
      ends_at: form.ends_at ? new Date(form.ends_at).toISOString() : null,
    });
    if (!parsed.success) {
      const flat = parsed.error.flatten().fieldErrors;
      setErrors(
        Object.fromEntries(
          Object.entries(flat)
            .filter(([, v]) => Array.isArray(v) && v.length)
            .map(([k, v]) => [k, (v as string[])[0]]),
        ),
      );
      // If the only errors are in advanced fields, reveal them.
      setShowAdvanced(true);
      return;
    }
    setErrors({});
    setLoading(true);
    try {
      const payload = {
        ...parsed.data,
        headers_json: parsed.data.headers_json?.trim() || null,
        drm_headers: parsed.data.drm_headers?.trim() || null,
        backup_stream_url: parsed.data.backup_stream_url?.trim() || null,
        drm_license_url: parsed.data.drm_license_url?.trim() || null,
        starts_at: parsed.data.starts_at || null,
        ends_at: parsed.data.ends_at || null,
        lifecycle_state: parsed.data.lifecycle_state,
        timezone: parsed.data.timezone?.trim() || null,
        early_show_minutes: parsed.data.early_show_minutes ?? 0,
        auto_hide_after_end: parsed.data.auto_hide_after_end,
      };
      const res = isEdit && initial?.id
        ? await streamsApi.update(initial.id, payload as Record<string, unknown>)
        : await streamsApi.create(payload as Record<string, unknown>);
      toast.success(isEdit ? 'Stream updated' : 'Stream created');
      reportNotification(res.notification);
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to save');
    } finally {
      setLoading(false);
    }
  }

  const published = isPublished(form);

  return (
    <Modal
      open={open}
      onClose={loading ? () => {} : onClose}
      title={isEdit ? 'Edit live stream' : 'Add live stream'}
      description="Add the stream link and options. Match details are filled from real data — you never type them."
      size="lg"
      footer={
        <>
          <Button variant="ghost" onClick={onClose} disabled={loading}>
            Cancel
          </Button>
          <Button onClick={submit} loading={loading}>
            {isEdit ? 'Save changes' : 'Create stream'}
          </Button>
        </>
      }
    >
      <form onSubmit={submit} className="space-y-5">
        {/* ---- Match (read-only when synced) ---- */}
        {lockMatch ? (
          <ReadOnlyMatchCard form={form} matchMeta={matchMeta} />
        ) : (
          <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
            <Field label="Match external ID" required error={errors.match_external_id}>
              <Input
                value={form.match_external_id ?? ''}
                onChange={(e) => update('match_external_id', e.target.value)}
                placeholder="e.g. 12345"
                invalid={!!errors.match_external_id}
              />
            </Field>
            <Field label="Match title" error={errors.match_title}>
              <Input
                value={form.match_title ?? ''}
                onChange={(e) => update('match_title', e.target.value)}
                placeholder="India vs Australia"
              />
            </Field>
            <Field label="Team A" error={errors.team_a}>
              <Input value={form.team_a ?? ''} onChange={(e) => update('team_a', e.target.value)} placeholder="India" />
            </Field>
            <Field label="Team B" error={errors.team_b}>
              <Input value={form.team_b ?? ''} onChange={(e) => update('team_b', e.target.value)} placeholder="Australia" />
            </Field>
          </div>
        )}

        {/* ---- Core stream fields (simplified) ---- */}
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div className="md:col-span-2">
            <Field label="Stream title / label" error={errors.title}>
              <Input
                value={form.title ?? ''}
                onChange={(e) => update('title', e.target.value)}
                placeholder="e.g. Main HD"
              />
            </Field>
          </div>

          <div className="md:col-span-2">
            <Field label="Stream URL" required error={errors.stream_url}>
              <Input
                value={form.stream_url ?? ''}
                onChange={(e) => update('stream_url', e.target.value)}
                placeholder="https://example.com/live/playlist.m3u8"
                invalid={!!errors.stream_url}
              />
            </Field>
          </div>

          <Field label="Stream type" required error={errors.stream_type}>
            <Select
              value={form.stream_type}
              onChange={(e) => update('stream_type', e.target.value as StreamFormValue['stream_type'])}
            >
              {SIMPLE_STREAM_TYPES.map((t) => (
                <option key={t.value} value={t.value} className="bg-slate-900">
                  {t.label}
                </option>
              ))}
            </Select>
          </Field>

          <Field label="Quality" required error={errors.quality}>
            <Select value={form.quality} onChange={(e) => update('quality', e.target.value as StreamFormValue['quality'])}>
              {STREAM_QUALITIES.map((q) => (
                <option key={q} value={q} className="bg-slate-900">
                  {q}
                </option>
              ))}
            </Select>
          </Field>

          <Field label="Status" required hint="Published = visible & active on the app.">
            <Select
              value={published ? 'published' : 'draft'}
              onChange={(e) => setPublishStatus(e.target.value as 'draft' | 'published')}
            >
              <option value="draft" className="bg-slate-900">Draft (hidden)</option>
              <option value="published" className="bg-slate-900">Published (live)</option>
            </Select>
          </Field>

          <Field label="Priority / order" error={errors.priority} hint="Lower number shows first">
            <Input
              type="number"
              value={form.priority ?? 100}
              onChange={(e) => update('priority', Number(e.target.value) as StreamFormValue['priority'])}
              invalid={!!errors.priority}
            />
          </Field>

          <Field label="Language" error={errors.language}>
            <Input value={form.language ?? ''} onChange={(e) => update('language', e.target.value)} placeholder="English" />
          </Field>
        </div>

        {/* ---- Toggles editors should manage ---- */}
        <div className="grid gap-3 rounded-xl border border-line bg-white/[0.04] p-3 md:grid-cols-2">
          <Switch
            label="Premium / rewarded stream"
            description="Requires premium or a rewarded ad"
            checked={!!form.is_premium}
            onChange={(v) => update('is_premium', v)}
          />
          <Switch
            label="Rewarded ad before play"
            description="Show a rewarded ad before playback"
            checked={!!form.requires_reward_ad}
            onChange={(v) => update('requires_reward_ad', v)}
          />
          <Switch
            label="Send notification on publish"
            description="Notify users once when this becomes Published"
            checked={form.notify_on_publish ?? true}
            onChange={(v) => update('notify_on_publish', v)}
          />
          <Switch
            label="Active on app"
            description="Master visibility for this stream"
            checked={!!form.is_active}
            onChange={(v) => update('is_active', v)}
          />
        </div>

        <Field label="Internal note" error={errors.notes}>
          <Textarea
            value={form.notes ?? ''}
            onChange={(e) => update('notes', e.target.value)}
            placeholder="Internal notes about this stream (not shown to users)"
            rows={2}
          />
        </Field>

        {/* ---- Advanced (power-user) section ---- */}
        <button
          type="button"
          onClick={() => setShowAdvanced((s) => !s)}
          className="flex items-center gap-1.5 text-sm font-medium text-cyan-200 hover:text-cyan-100"
        >
          {showAdvanced ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
          Advanced (scheduling, headers, DRM)
        </button>

        {showAdvanced && (
          <div className="space-y-4 rounded-xl border border-line bg-white/[0.02] p-4">
            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
              <Field label="Label" error={errors.label}>
                <Input value={form.label ?? ''} onChange={(e) => update('label', e.target.value)} placeholder="HD-1" />
              </Field>
              <Field label="Server name" error={errors.server_name}>
                <Input value={form.server_name ?? ''} onChange={(e) => update('server_name', e.target.value)} placeholder="Akamai EU" />
              </Field>
              <div className="md:col-span-2">
                <Field label="Backup stream URL" error={errors.backup_stream_url}>
                  <Input
                    value={form.backup_stream_url ?? ''}
                    onChange={(e) => update('backup_stream_url', e.target.value)}
                    placeholder="https://example.com/live/backup.m3u8"
                    invalid={!!errors.backup_stream_url}
                  />
                </Field>
              </div>
              <Field label="Health status" error={errors.status}>
                <Select value={form.status} onChange={(e) => update('status', e.target.value as StreamFormValue['status'])}>
                  {STREAM_STATUSES.map((status) => (
                    <option key={status} value={status} className="bg-slate-900">{status.toUpperCase()}</option>
                  ))}
                </Select>
              </Field>
              <Field label="Schedule state" hint="draft/disabled always hide Watch Live.">
                <Select value={form.lifecycle_state ?? 'scheduled'} onChange={(e) => update('lifecycle_state', e.target.value as StreamFormValue['lifecycle_state'])}>
                  {['draft', 'scheduled', 'active', 'disabled', 'expired'].map((s) => (
                    <option key={s} value={s} className="bg-slate-900">{s.toUpperCase()}</option>
                  ))}
                </Select>
              </Field>
              <Field label="Starts at" error={errors.starts_at}>
                <Input type="datetime-local" value={form.starts_at ?? ''} onChange={(e) => update('starts_at', e.target.value)} />
              </Field>
              <Field label="Ends at" error={errors.ends_at}>
                <Input type="datetime-local" value={form.ends_at ?? ''} onChange={(e) => update('ends_at', e.target.value)} />
              </Field>
              <Field label="Early show (minutes)" hint="Reveal Watch Live this many minutes before start.">
                <Input type="number" min={0} value={form.early_show_minutes ?? 0} onChange={(e) => update('early_show_minutes', Number(e.target.value) as StreamFormValue['early_show_minutes'])} />
              </Field>
              <Field label="Timezone" hint="IANA tz used to interpret start/end.">
                <Input value={form.timezone ?? ''} onChange={(e) => update('timezone', e.target.value)} placeholder="Asia/Kolkata" />
              </Field>
            </div>

            <div className="flex flex-wrap gap-4">
              <Switch label="Auto-hide after end" checked={form.auto_hide_after_end ?? true} onChange={(v) => update('auto_hide_after_end', v)} />
              <Switch label="Login required" checked={!!form.requires_login} onChange={(v) => update('requires_login', v)} />
              <Switch label="Force resend now" description="Manually re-send the publish push (still deduped)" checked={!!form.send_push_now} onChange={(v) => update('send_push_now', v)} />
            </div>

            <WatchLiveScheduleHint form={form} />

            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
              <Field label="Custom User-Agent" error={errors.user_agent_header}>
                <Input value={form.user_agent_header ?? ''} onChange={(e) => update('user_agent_header', e.target.value)} placeholder="Optional override" />
              </Field>
              <Field label="Custom Referer" error={errors.referer_header}>
                <Input value={form.referer_header ?? ''} onChange={(e) => update('referer_header', e.target.value)} placeholder="Optional referer header" />
              </Field>
              <Field label="Custom Origin" error={errors.origin_header}>
                <Input value={form.origin_header ?? ''} onChange={(e) => update('origin_header', e.target.value)} placeholder="https://example.com" />
              </Field>
              <div className="md:col-span-2">
                <Field label="Headers JSON" error={errors.headers_json}>
                  <Textarea value={form.headers_json ?? ''} onChange={(e) => update('headers_json', e.target.value)} placeholder='{"X-Playback-Token":"..."}' rows={3} invalid={!!errors.headers_json} />
                </Field>
              </div>
            </div>

            <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
              <Field label="DRM type" error={errors.drm_type}>
                <Select value={form.drm_type} onChange={(e) => update('drm_type', e.target.value as StreamFormValue['drm_type'])}>
                  {DRM_TYPES.map((type) => (
                    <option key={type} value={type} className="bg-slate-900">{type.toUpperCase()}</option>
                  ))}
                </Select>
              </Field>
              <Field label="DRM license URL" error={errors.drm_license_url}>
                <Input value={form.drm_license_url ?? ''} onChange={(e) => update('drm_license_url', e.target.value)} placeholder="https://license.example.com/widevine" invalid={!!errors.drm_license_url} />
              </Field>
              <div className="md:col-span-2">
                <Field label="DRM headers JSON" error={errors.drm_headers}>
                  <Textarea value={form.drm_headers ?? ''} onChange={(e) => update('drm_headers', e.target.value)} placeholder='{"Authorization":"Bearer ..."}' rows={3} invalid={!!errors.drm_headers} />
                </Field>
              </div>
              <Field label="ClearKey key ID" error={errors.clear_key_key_id}>
                <Input value={form.clear_key_key_id ?? ''} onChange={(e) => update('clear_key_key_id', e.target.value)} placeholder="Base64 or hex key ID" />
              </Field>
              <Field label="ClearKey key" error={errors.clear_key_key}>
                <Input value={form.clear_key_key ?? ''} onChange={(e) => update('clear_key_key', e.target.value)} placeholder="Base64 or hex key" />
              </Field>
              <div className="md:col-span-2">
                <Switch label="DRM protected" checked={!!form.drm_enabled} onChange={(v) => update('drm_enabled', v)} />
              </div>
            </div>
          </div>
        )}
      </form>
    </Modal>
  );
}

// Toast feedback for the publish-notification result returned by the backend.
function reportNotification(n?: StreamNotificationStatus) {
  if (!n) return;
  if (n.status === 'sent') toast.success('Publish notification sent');
  else if (n.status === 'already_sent') toast.message('Publish notification already sent (deduped)');
  else if (n.status === 'failed') toast.error(`Publish notification failed: ${n.reason || 'unknown'}`);
  // 'skipped' (not published / opted out) is silent — no user-facing noise.
}

function ReadOnlyMatchCard({ form, matchMeta }: { form: StreamFormValue; matchMeta?: StreamMatchMeta | null }) {
  const matchup = matchMeta?.matchup || form.match_title || `${form.team_a || ''} vs ${form.team_b || ''}`;
  const rows: [string, string | null | undefined][] = [
    ['Match ID', matchMeta?.match_external_id || form.match_external_id],
    ['Series', matchMeta?.series_name],
    ['Venue', matchMeta?.venue],
    ['Start', matchMeta?.start_time ? new Date(matchMeta.start_time).toLocaleString() : null],
    ['Status', matchMeta?.status_text || matchMeta?.phase],
  ];
  return (
    <div className="rounded-xl border border-cyan-400/20 bg-cyan-300/[0.06] p-4">
      <div className="mb-2 flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-cyan-200">
        <Lock className="h-3.5 w-3.5" />
        Match details (from live data — read only)
      </div>
      <div className="text-base font-semibold text-white">{matchup}</div>
      <dl className="mt-2 grid grid-cols-1 gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
        {rows
          .filter(([, v]) => v)
          .map(([k, v]) => (
            <div key={k} className="flex justify-between gap-3">
              <dt className="text-slate-400">{k}</dt>
              <dd className="text-right text-slate-200">{v}</dd>
            </div>
          ))}
      </dl>
    </div>
  );
}

// Live, client-side explanation of exactly when "Watch Live" will be visible
// for the current form values. Mirrors the backend streamLifecycleStatus rules.
function WatchLiveScheduleHint({ form }: { form: StreamFormValue }) {
  const state = String(form.lifecycle_state ?? 'scheduled').toLowerCase();
  const active = form.is_active ?? true;
  const early = Math.max(0, Number(form.early_show_minutes || 0));
  const autoHide = form.auto_hide_after_end ?? true;
  const startsAt = form.starts_at ? new Date(form.starts_at) : null;
  const endsAt = form.ends_at ? new Date(form.ends_at) : null;
  const now = new Date();

  let tone = 'border-amber-500/30 bg-amber-500/10 text-amber-200';
  let message = '';

  if (!active || state === 'draft' || state === 'disabled') {
    tone = 'border-slate-500/30 bg-slate-500/10 text-slate-300';
    message = `Watch Live is HIDDEN (${!active ? 'inactive' : state}). It will not appear until you enable it.`;
  } else if (endsAt && autoHide && endsAt.getTime() < now.getTime()) {
    tone = 'border-slate-500/30 bg-slate-500/10 text-slate-300';
    message = 'Watch Live is HIDDEN — the end time has passed (auto-hide on).';
  } else if (startsAt) {
    const visibleFrom = new Date(startsAt.getTime() - early * 60 * 1000);
    if (visibleFrom.getTime() > now.getTime()) {
      message = `Watch Live will appear at ${visibleFrom.toLocaleString()}${early ? ` (${early} min before start)` : ''}.`;
    } else {
      tone = 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200';
      message = 'Watch Live is VISIBLE now.';
    }
  } else {
    tone = 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200';
    message = 'Watch Live is VISIBLE now (no start time set).';
  }

  return (
    <div className={`rounded-xl border p-3 text-sm ${tone}`}>
      <span className="font-medium">Watch Live status: </span>
      {message}
    </div>
  );
}
