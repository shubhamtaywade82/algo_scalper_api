# Frontend Real-Time Update Fixes — Design Spec

**Date:** 2026-03-23
**Status:** Approved

## Problem

The frontend dashboard shows no live tick-driven PnL updates. Root cause: the development ActionCable adapter is `async` (in-process only), but the `web` and `trading` processes are separate OS processes. Every `ActionCable.server.broadcast` call from `PnlUpdaterService` (in the `trading` process) is silently dropped — the `web` process WebSocket server never receives it.

Secondary issues also present: circuit breaker trips are not immediately pushed, PnlUpdater health is invisible, stale LTP causes positions to freeze with no user signal, and Redis tick keys have no TTL.

## Decisions

- Cable adapter: **Redis** for both development and production (same `REDIS_URL` env var, DB index `/0`)
- No new env vars; `solid_cable` gem stays in Gemfile but is no longer the cable adapter

## Fix 1 — Redis Cable Adapter (Root Cause)

**File:** `config/cable.yml`

Replace `async` (dev) and `solid_cable` (prod) with the Redis adapter in both environments.
Remove the `connects_to` and `polling_interval` stanzas — they are `solid_cable`-specific and must not remain.
The `cable` database entry in `config/database.yml` is harmless and can stay.

```yaml
development:
  adapter: redis
  url: <%= ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0") %>

test:
  adapter: test

production:
  adapter: redis
  url: <%= ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0") %>
```

**Why this fixes things:** Redis pub/sub is process-agnostic. The `trading` process publishes a message; the `web` process (subscribed via Redis) receives it immediately and pushes to connected WebSocket clients.

## Fix 2 — Circuit Breaker Immediate Push

**File:** `app/services/risk/circuit_breaker.rb`

In `trip!`: after `Rails.cache.write(...)`, call `status` (which returns the hash) and broadcast it.
In `reset!`: `reset!` currently returns `true` — it does NOT return a hash. After `Rails.cache.delete(...)`, call `status` explicitly to obtain the hash, then broadcast.

```ruby
# In trip!
current_status = status
ActionCable.server.broadcast("dashboard", { type: "circuit_breaker" }.merge(current_status))

# In reset!
Rails.cache.delete(TRIP_CACHE_KEY)
current_status = status  # reads fresh from cache → returns { tripped: false, reason: nil, at: nil }
ActionCable.server.broadcast("dashboard", { type: "circuit_breaker" }.merge(current_status))
```

**File:** `dashboard/src/composables/useDashboard.js`

Add a `circuit_breaker` branch in `received(data)`:

```js
} else if (data.type === 'circuit_breaker') {
  circuitBreaker.value = { tripped: data.tripped, reason: data.reason, at: data.at }
}
```

This updates state in <250ms on a trip/reset rather than waiting for the next 1s heartbeat.

## Fix 3 — PnlUpdater Health Monitoring

**File:** `app/services/live/pnl_updater_service.rb` — `build_dashboard_stats`

Add `pnl_updater_running: running?` to the `system:` sub-hash:

```ruby
system: Live::SystemStatusCache.instance.all_statuses.merge(
  pnl_updater_running: running?
)
```

Note: the `stats` WebSocket broadcast intentionally omits `ws_order_update` (not available from inside PnlUpdaterService). The REST endpoint (below) includes it.

**File:** `app/controllers/api/dashboard_controller.rb`

Add `pnl_updater_running` to the existing `.merge(...)` in the `system:` value:

```ruby
system: Live::SystemStatusCache.instance.all_statuses.merge(
  ws_order_update: Live::OrderUpdateHub.instance.running?,
  pnl_updater_running: Live::PnlUpdaterService.instance.running?
)
```

No frontend changes needed — the existing `system` ref already renders whatever keys arrive.

## Fix 4 — Stale LTP Indicator

**File:** `app/services/live/pnl_updater_service.rb` — `flush!`

When a position is skipped because `tick_ltp` is nil/zero, broadcast a stale signal:

```ruby
ActionCable.server.broadcast("positions", { type: "pnl_stale", id: tracker_id })
```

Also add `ltp_stale: false` to the `broadcast_pnl_update` payload so a fresh update always clears
the stale flag on the frontend — the spread in `applyPnlUpdate` does not set fields to `false`
unless they are explicitly present in the incoming message:

```ruby
ActionCable.server.broadcast("positions", {
  type: "pnl_update",
  id: tracker_id,
  ltp: ltp_f.round(2),
  pnl: pnl.to_f.round(2),
  pnl_pct: pnl_pct,
  hwm_pnl: hwm.to_f.round(2),
  ltp_stale: false
})
```

**File:** `dashboard/src/composables/usePositions.js`

In the `received(data)` handler, add:

```js
} else if (data.type === 'pnl_stale') {
  const idx = open.value.findIndex(p => p.id === data.id)
  if (idx !== -1) open.value[idx] = { ...open.value[idx], ltp_stale: true }
}
```

The `pnl_update` path already calls `applyPnlUpdate` which spreads the update (including `ltp_stale: false`)
over the existing object, clearing the stale flag.

## Fix 5 — Redis TTL on Tick Keys

**File:** `app/services/live/redis_tick_cache.rb` — `store_tick`

After the `hmset` call, add:

```ruby
redis.expire(key, 3600)
```

1-hour TTL ensures keys do not persist indefinitely if `prune_stale` misses them.
The TTL is reset on every tick update, so active instruments are never pruned early.
`prune_stale` uses its own timestamp-field logic and continues to operate independently;
the two mechanisms coexist without conflict.

## Files Changed

| File | Change |
|------|--------|
| `config/cable.yml` | Switch dev + prod to redis adapter; remove solid_cable stanzas |
| `app/services/risk/circuit_breaker.rb` | Broadcast on `trip!` and `reset!` (call `status` explicitly in `reset!`) |
| `app/services/live/pnl_updater_service.rb` | Add health to stats broadcast; broadcast `pnl_stale`; add `ltp_stale: false` to `pnl_update` |
| `app/controllers/api/dashboard_controller.rb` | Add `pnl_updater_running` to system merge |
| `app/services/live/redis_tick_cache.rb` | Add `expire` after `hmset` |
| `dashboard/src/composables/usePositions.js` | Handle `pnl_stale` message type |
| `dashboard/src/composables/useDashboard.js` | Handle `type: "circuit_breaker"` message |

## Out of Scope

- Changing `PositionRow.vue` styling (only `ltp_stale` flag is added to data; UI styling is a separate concern)
- Removing `solid_cable` gem
- Any changes to LOCKED infra layers (gateway, order plumbing, position lifecycle)
