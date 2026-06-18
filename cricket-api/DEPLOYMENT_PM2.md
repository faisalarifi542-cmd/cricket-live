# CricPro Backend — PM2 Cluster Deployment (Phase 4)

PM2 process model, deploy, verification, and rollback for the `cricket-api`
backend. Phase 4 only — no compression / rate-limit / WS / Flutter changes.

## Process model

| Process | Script | Mode | Instances | Purpose |
|---|---|---|---|---|
| `cricket-api` | `src/server.js` | **cluster** | `max` (or `PM2_API_INSTANCES`) | Public API + Phase 1b in-process warmers |
| `cricket-workers` | `src/workers/index.js` | **fork** | **1** | BullMQ provider-polling workers |

- The API is clustered: Node round-robins one shared port across all instances.
- The workers are **never** clustered. They are already distributed-single-flight
  via Redis-backed BullMQ jobId schedulers; one fork process is correct. Do not
  raise `cricket-workers` instances.
- Phase 1b warmers run inside **every** API instance, but each warmer tick first
  takes the Redis leader lock `lock:cache:warmer:{name}`, so **only one instance
  fetches per tick**. The per-key Phase 1a lock `lock:cache:{key}` is a second
  layer that collapses any residual race to one provider call cluster-wide.

## Production env values

Set these in the production `.env` (gitignored — not deployed from the repo) or
rely on the values baked into `ecosystem.config.cjs`. Conservative first-deploy:

```env
NODE_ENV=production
PUBLIC_BASE_URL=https://api.webcrichd.co
ENABLE_PHASE1B_WARMING=true
MAX_WARM_LIVE_MATCHES=5
ENABLE_APP_HOME_WARMER=true
ENABLE_APP_CONFIG_WARMER=true
ENABLE_LIVEFAST_WARMER=true
ENABLE_LIVECOMM_WARMER=true
ENABLE_MATCH_DETAIL_WARMER=false
```

- **Start at `MAX_WARM_LIVE_MATCHES=5`.** Do not raise to 12 until logs confirm
  provider load is safe and the raise is explicitly approved.
- Keep `ENABLE_MATCH_DETAIL_WARMER=false` until explicitly approved.
- **All env changes require a PM2 restart with `--update-env` to take effect** —
  config is read once at process start (`dotenv/config` + `Object.freeze`); there
  is no live runtime toggle.

## Deploy

```bash
cd /path/to/cricket-api

# Install PM2 once (global):
npm i -g pm2

# Start the API in cluster mode:
pm2 start ecosystem.config.cjs --only cricket-api

# Start the BullMQ workers (separate fork process):
pm2 start ecosystem.config.cjs --only cricket-workers

# Or both at once:
pm2 start ecosystem.config.cjs

# Persist the process list so it survives a reboot:
pm2 save
pm2 startup   # then run the command it prints (systemd integration)
```

On a small/shared VPS, cap instances instead of using all cores:

```bash
PM2_API_INSTANCES=2 pm2 start ecosystem.config.cjs --only cricket-api --update-env
```

## Verification (run on the deploy host after start)

```bash
# 1. API is in cluster mode with N online instances; workers show "fork".
pm2 status

# 2. Workers are NOT clustered (mode = fork, single instance).
pm2 describe cricket-workers | grep -E "exec mode|instances"

# 3. API health (Redis + MySQL connectivity reported in checks).
curl -s http://localhost:5000/health | jq .
#    expect: status "healthy", checks.redis.status "ok", checks.mysql.status "ok"

# 4/5. Redis + MySQL: covered by the /health output above.

# 6. PUBLIC_BASE_URL visible to the fresh process.
pm2 env 0 | grep PUBLIC_BASE_URL        # 0 = first cricket-api instance id

# 7. Home warmer no longer skips (absence of the skip line + presence of warm log):
pm2 logs cricket-api --lines 200 --nostream | grep -i "PUBLIC_BASE_URL not set"   # expect: no matches
pm2 logs cricket-api --lines 200 --nostream | grep "phase1b-warmers started"

# 8. Only ONE instance leads each warmer per tick (grep one tick window):
pm2 logs cricket-api --lines 300 --nostream | grep "phase1b-warmer" 
#    each warmer name (app-home/app-config/livefast/livecomm) should log once per
#    interval, not once-per-instance.

# 9. Provider fallback stays low (these are the user-facing fallbacks):
pm2 logs cricket-api --lines 500 --nostream | grep "provider-fallback" | wc -l

# 10. Warmer discovered/warmed/skipped counts:
pm2 logs cricket-api --lines 300 --nostream | grep -E "warmer.*(discovered|warmed|skipped)"
```

Optional cross-instance leader check via Redis directly:

```bash
redis-cli keys "lock:cache:warmer:*"   # at most one holder key per warmer name
```

## Emergency: disable Phase 1b warmers (no data loss)

```bash
# Set in the env (or the API app block of ecosystem.config.cjs):
ENABLE_PHASE1B_WARMING=false

pm2 restart cricket-api --update-env
```

Result: warmers stop scheduling/fetching; **existing Redis cached data is not
deleted** (warmers only ever write/refresh); public routes keep serving through
the Phase 1a protected cache-miss/stale fallback path. A clear log line is
emitted: `phase1b-warmers not started ... ENABLE_PHASE1B_WARMING=false`.

Per-warmer disable (master stays on) works the same way, e.g.:

```bash
ENABLE_LIVECOMM_WARMER=false
pm2 restart cricket-api --update-env
```

## Rollback: cluster → single instance

Fastest (keeps cluster mode, one instance):

```bash
PM2_API_INSTANCES=1 pm2 restart cricket-api --update-env
```

True fork/single-instance (edit `ecosystem.config.cjs` cricket-api block):

```js
exec_mode: 'fork',
instances: 1,
```

then:

```bash
pm2 restart cricket-api --update-env
```

Single-instance behavior is identical to pre-cluster: the Redis locks are simply
always acquired uncontended.

## Restart all services safely

```bash
pm2 reload cricket-api --update-env     # zero-downtime rolling reload (cluster)
pm2 restart cricket-workers --update-env
pm2 save
pm2 status
pm2 logs cricket-api --lines 100
```

`reload` does a rolling restart across cluster instances (no dropped
connections); `restart` is a hard restart (use for the fork workers).

## Notes / guardrails

- No video proxying: stream routes still return m3u8 metadata only; clustering
  does not change the stream flow. The VPS never touches video bytes.
- No endpoint/response-shape changes in this phase.
- The standalone metrics port (`METRICS_PORT`, default 9090) is configured but
  unused — metrics are served via the `/metrics` route on the main API port, so
  there is no second-port `EADDRINUSE` risk under cluster mode.
