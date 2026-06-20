# Analytics Accuracy Fix Report

Date: 2026-06-17
Scope: CricPro analytics pipeline (Flutter app → Fastify backend → MySQL → Next.js admin dashboard).
Constraint honored: no release APK / appbundle built. Live score polling, stream player, ads playback, notification sending, floating overlay, and Home UI left untouched.

---

## 1. Current root cause

The original premise — "every app open counts as a new user and inflates active users" — was only **partly** accurate. The audit (reading the actual code, not assumptions) found:

**Already correct before this fix:**
- The Flutter analytics `device_id` is generated once and persisted in `SharedPreferences` (`analytics_device_id`). It is **not** regenerated per launch.
- `app_open` / `session_start` were guarded by an `_initialized` flag, firing once per cold start.
- The backend upserts `analytics_devices` on PK `device_id` with `ON DUPLICATE KEY UPDATE`; `first_seen` is only set on insert.
- DAU/WAU/MAU already used `COUNT(DISTINCT device_id)`.

So repeated opens did **not** create new analytics users. The two early agent hypotheses ("Flutter regenerates device_id" and "OneSignal subscriptionId desync breaks analytics") were both wrong for the analytics path.

**What was genuinely broken / inflating numbers:**

1. **Sessions over-counted.** No session timeout existed. Android frequently kills and cold-restarts the process, so each cold start fired a fresh `session_start` with a brand-new random `session_id`, and sessions were counted as raw `SUM(event_name='session_start')` event rows. Repeated opens → inflated session count.
2. **DAU/MAU used a rolling window, not a calendar day.** `NOW() - INTERVAL 1 DAY` (rolling 24h) and `- INTERVAL 30 DAY` (rolling 30d) instead of "today" / "this month". Counts drift continuously and never match a calendar-day definition.
3. **No `first_seen`-based "new users today".** The dashboard only had `firstOpensApproxInstalls.newInRange` (new in the selected filter range), with no calendar-day "new users today", no "total users", and no "returning users".
4. **Phantom user from null device_id.** Events queued before `initialize()` finished carried `device_id = null`; `COUNT(DISTINCT device_id)` counted the NULL bucket as activity. (Now excluded with `WHERE device_id IS NOT NULL`.)
5. **Separate `app_devices` double-count risk (notifications table).** Device registration keyed only on the OneSignal `subscription_id`, which rotates when the OS refreshes the push token → the same install could create multiple `app_devices` rows. This is the table the original complaint most plausibly refers to.
6. **Misleading labels.** "Sessions" (raw event count) sat beside user cards and read like a user metric; "First opens / approx installs" was ambiguous.

---

## 2. Files inspected

Backend:
- `cricket-api/src/routes/analytics.js` (event ingest)
- `cricket-api/src/routes/app.js` (device register/update)
- `cricket-api/src/admin/routes/analytics.routes.js` (dashboard summary/timeseries/breakdown)
- `cricket-api/src/db/migrate.js` (schema + compatibility migrations)
- `cricket-api/src/lib/redis.js` (confirmed: Redis not used for analytics)

Flutter:
- `lib/main.dart` (startup + lifecycle)
- `lib/services/analytics_service.dart`
- `lib/services/notification_service.dart`
- `lib/core/api/api_config.dart`

Admin:
- `admin-panel/app/analytics/page.tsx`
- `admin-panel/lib/api.ts`

---

## 3. Files changed

Backend:
- `cricket-api/src/db/migrate.js` — added `analytics_sessions` table (in both the `TABLES` list and the compatibility migration), `install_id` column + unique index on `app_devices`, `first_seen` index on `analytics_devices`, and new `indexExists` / `addIndexIfMissing` helpers.
- `cricket-api/src/routes/analytics.js` — added `session_heartbeat` to valid events; upsert into `analytics_sessions` keyed on `session_id` (dedupe); accept passthrough.
- `cricket-api/src/routes/app.js` — `/app/device/register` now dedupes on `install_id` first (updates the existing row even when the subscription id rotated), falling back to the legacy subscription-id upsert.
- `cricket-api/src/admin/routes/analytics.routes.js` — calendar-day DAU + calendar-month MAU, `newUsers.today` / `inRange`, `totalUsers`, `returningUsersToday`, `appOpens`, sessions sourced from the deduped `analytics_sessions` table; null device ids excluded; timeseries `sessions` reads the sessions table and a new `app_opens` metric added.

Flutter:
- `lib/services/analytics_service.dart` — stable persisted `installId`; persisted session id + last-seen timestamp with a 30-minute inactivity timeout; `onAppForeground()`; session touched on every event; `initialize()` stays idempotent.
- `lib/main.dart` — `AppLifecycleState.resumed` now calls `AnalyticsService.onAppForeground()`.
- `lib/services/notification_service.dart` — sends `installId` with device registration.

Admin:
- `admin-panel/lib/api.ts` — extended `AnalyticsSummary` type (`newUsers`, `totalUsers`, `returningUsersToday`, `sessionsToday`, `appOpens`; kept `firstOpensApproxInstalls` for compatibility).
- `admin-panel/app/analytics/page.tsx` — relabeled/added cards: New users (today), Total users, Active users (today / 7d / 30d-MAU), Returning users (today), Sessions (with today + 30-min hint), App opens.

New file:
- `ANALYTICS_ACCURACY_FIX_REPORT.md` (this report).

---

## 4. Correct metric definitions (as implemented)

- **New users (today):** `COUNT` of `analytics_devices` rows whose `first_seen >= DATE(NOW())`. Once per install identity.
- **Total users:** `COUNT(*)` of `analytics_devices`.
- **Active users — DAU:** `COUNT(DISTINCT device_id)` in `analytics_events` where `created_at >= DATE(NOW())` (calendar day) and `device_id IS NOT NULL`.
- **Active users — WAU:** distinct devices over rolling 7 days.
- **Active users — MAU:** distinct devices where `created_at >= DATE_FORMAT(NOW(), '%Y-%m-01')` (calendar month).
- **Returning users (today):** devices with `last_seen >= DATE(NOW())` AND `first_seen < DATE(NOW())`.
- **Sessions:** distinct `session_id` in `analytics_sessions` (today + selected range), NOT raw event rows.
- **App opens:** `SUM(event_name='app_open')` — every open/resume, a deliberately separate metric from users and sessions.

---

## 5. Install / device identity strategy

- **Analytics identity:** anonymous random `analytics_device_id` (existing), persisted once. Used for DAU/MAU/new-user dedupe.
- **Install identity:** new anonymous random `analytics_install_id`, persisted once, also surfaced to device registration. Decouples the device row from the rotating OneSignal `subscription_id`.
- Backend `app_devices` now dedupes on `install_id` (unique index, NULL-tolerant for legacy rows) before falling back to `subscription_id`.
- No hardware identifiers, no PII, no IP-based identity. Clearing app data / reinstalling produces a new install id (expected — that is a real new install).

---

## 6. Backend dedupe / upsert logic

- `analytics_devices`: unchanged upsert on PK `device_id`; `first_seen` preserved.
- `analytics_sessions`: **new** upsert on PK `session_id`. Repeated `session_start` / `session_heartbeat` for the same session only bump `last_seen`; `started_at` is set once. Duplicate startup calls cannot create extra sessions.
- `app_devices`: install-id-keyed update path + `ON DUPLICATE KEY UPDATE` fallback; rotated subscription ids update the existing install row.
- All analytics writes remain best-effort (`.catch`) so ingest never fails loudly.

---

## 7. Session tracking logic

- Session id + last-activity timestamp persisted in `SharedPreferences`.
- On `initialize()` and on `resumed`: continue the stored session if the last activity was within 30 minutes; otherwise begin a new session and emit `session_start`.
- Any tracked event refreshes the session's last-seen clock.
- Backend dedupes on `session_id`, so client retries / duplicate batches are safe.

---

## 8. Admin dashboard formula changes

- DAU/MAU switched from rolling windows to calendar day / month.
- Sessions now read the deduped `analytics_sessions` table instead of counting `session_start` event rows.
- Added `newUsers.today`, `totalUsers`, `returningUsersToday`, `appOpens`, `sessionsToday`.
- NULL device ids excluded from active-user counts.
- Cards relabeled for clarity; `firstOpensApproxInstalls` retained in the payload for backward compatibility.

---

## 9. Migration changes

All additive and idempotent — no data dropped, old devices keep working:
- `CREATE TABLE analytics_sessions` (in `TABLES` and the compatibility path).
- `ALTER TABLE app_devices ADD COLUMN install_id VARCHAR(64) NULL` + `UNIQUE INDEX uniq_app_devices_install` (NULL-tolerant).
- `ADD INDEX idx_analytics_devices_first (first_seen)`.
- New helpers `indexExists` / `addIndexIfMissing` (swallow duplicate-index races).

Timezone note: `DATE(NOW())` uses the DB session timezone, the same clock that writes `created_at`, so reads and writes stay in sync. To run the dashboard in a specific timezone, set the MySQL session/global `time_zone`; both sides move together. (A hand-rolled UTC offset was deliberately rejected because it would desync from how rows are stored.)

---

## 10. Test / verification steps (manual QA)

Fresh install / cleared data:
1. Open app → New users (today) +1, Active users (today) +1, Sessions +1, App opens +1.

Re-open same day, within 30 min:
2. New users (today) unchanged; Active users (today) unchanged; Sessions unchanged; App opens +1.

Background then resume after >30 min:
3. New session starts (Sessions +1); New/Active users unchanged.

Background/resume quickly (<30 min):
4. No new user, no new session; App opens +1.

Second device/install:
5. New users +1, Active users +1.

Backend SQL spot-checks:
```sql
-- distinct installs vs raw device rows (should be equal; no dupes)
SELECT COUNT(*) AS rows_, COUNT(DISTINCT device_id) AS distinct_ FROM analytics_devices;
-- sessions never exceed (app_opens) and are deduped
SELECT COUNT(*) AS session_rows, COUNT(DISTINCT session_id) AS distinct_sessions FROM analytics_sessions;
-- one install, many opens → still one app_devices row keyed by install_id
SELECT install_id, COUNT(*) FROM app_devices WHERE install_id IS NOT NULL GROUP BY install_id HAVING COUNT(*) > 1;
```
(The third query returning zero rows confirms install-id dedupe.)

---

## 11. Checks run

- `node --check` on all four changed backend files → **all OK**.
- `flutter analyze lib/` → **No issues found**.
- `npx tsc --noEmit` (admin-panel) → **exit 0**.

Not run (per instructions): release APK, appbundle. No runtime DB migration executed here — it runs on the next backend boot via the idempotent migration path.

---

## 12. Intentionally left unchanged

- Live score polling, stream player, ads playback, notification **sending**, floating overlay, Home UI.
- `analytics_devices` PK and existing upsert semantics.
- `/app/device/update` (permission sync) — still subscription-id keyed; low risk, out of scope.
- The `firstOpensApproxInstalls` field is retained for backward compatibility rather than removed.

---

## 13. Remaining manual QA checklist

- [ ] Boot backend once so the migration adds `analytics_sessions`, `app_devices.install_id`, and indexes; confirm logs show the additions.
- [ ] Run the three SQL spot-checks above on staging after some traffic.
- [ ] Install the debug build on two devices; verify New/Active/Sessions/App-opens behave per the matrix in §10.
- [ ] Verify resume after >30 min increments Sessions but not users.
- [ ] Confirm the admin Analytics page renders all new cards with sane numbers.
- [ ] If a non-UTC reporting day is desired, set MySQL `time_zone` and re-verify "today" boundaries.
- [ ] (Optional) Backfill `app_devices.install_id` for legacy rows — not required; legacy rows continue to dedupe on subscription id.
