# Performance Improvements

> Last updated: 2026-07-17
> Legend: 🔴 P0=Critical 🟠 P1=High 🟡 P2=Medium 🟢 P3=Low

## Summary

| Status | Count |
|--------|-------|
| ✅ Done | 0 |
| 🔄 In Progress | 0 |
| ⬜ Pending | 11 |
| **Total** | **11** |

---

## 🔴 P0 — Critical

### ⬜ 1. Synchronous EventBus on tick hot path

| Field | Value |
|-------|-------|
| **Category** | Backend — Event Bus / Tick Processing |
| **Files** | `app/services/live/market_feed_hub.rb:481-484`, `app/services/core/event_bus.rb:70-89`, `app/services/live/pnl_updater_service.rb:288` |
| **Problem** | Every incoming WebSocket tick synchronously iterates all registered callbacks (`notify_subscribers!`), and `PnlUpdaterService` publishes back to `EventBus` (`:ltp`) which synchronously invokes `RiskManagerService#handle_pnl_event`. A single tick triggers a chain of synchronous work — PnL calculation, DB sync, Redis writes, ActionCable broadcasts, Telegram checks, risk evaluation — before the next tick can be processed. Under high tick volume this creates a cascade of blocking I/O on the WebSocket reactor thread. |
| **Solution** | Make callback invocation asynchronous via a bounded `Concurrent::ThreadPoolExecutor`. Decouple the `EventBus` publish from `PnlUpdaterService.cache_intermediate_pnl` so it doesn't block the tick path. |
| **Effort** | ~4h |
| **Risk** | Medium — threading changes in the hot path need careful testing under load |
| **Status** | ⬜ Pending |

---

### ⬜ 2. Redis connection proliferation

| Field | Value |
|-------|-------|
| **Category** | Backend — Redis / Infrastructure |
| **Files** | `app/services/positions/active_cache.rb:137`, `app/services/live/position_runtime_cache.rb:20`, `app/services/live/redis_pnl_cache.rb:14`, `app/services/live/redis_tick_cache.rb:255`, `app/services/live/redis_tick_cache.rb:96` |
| **Problem** | Each service opens its own `Redis.new()` connection. At 11+ trading daemon threads, each potentially using multiple Redis connections, this can exhaust the default Redis `maxclients` limit or cause connection storms on reconnect. The `self.delete` class method in `redis_tick_cache.rb` creates and tears down a connection on every call. |
| **Solution** | Centralize through a `connection_pool` gem (already in Gemfile) with a shared pool. Create a `RedisConnection` module with a pooled `POOL` constant. Replace all `Redis.new(...)` calls with `RedisConnection.with { |r| ... }`. |
| **Effort** | ~2h |
| **Risk** | Low — well-understood pattern, no behavior change |
| **Status** | ⬜ Pending |

---

## 🟠 P1 — High

### ⬜ 3. Repeated `PositionTracker.active` queries bypassing cache

| Field | Value |
|-------|-------|
| **Category** | Backend — DB / Caching |
| **Files** | `app/services/positions/active_positions_cache.rb:25-34`, `app/services/live/redis_tick_cache.rb:200-249` |
| **Problem** | `ActivePositionsCache` loads `PositionTracker.active.includes(:instrument).to_a` every 5s for ALL trackers even when only one is needed. `redis_tick_cache.rb` issues separate `PositionTracker.active.pluck(...)` queries on every `prune_stale` call, bypassing the cache entirely. `active_tracker_ids` uses `.map(&:id)` instead of `.pluck(:id)`. The `includes(:instrument)` loads all columns. |
| **Solution** | Add `pluck(:id)` shortcut to cache. Make `redis_tick_cache.rb` use `ActivePositionsCache.instance.active_tracker_ids` instead of raw DB queries. Limit `includes(:instrument)` to a `select(:id, :security_id, ...)`. |
| **Effort** | ~1h |
| **Risk** | Low — cache semantics unchanged, just better usage |
| **Status** | ⬜ Pending |

---

### ⬜ 4. `Instrument.find_by_sid_and_segment` per index tick

| Field | Value |
|-------|-------|
| **Category** | Backend — DB / Caching |
| **Files** | `app/services/live/market_feed_hub.rb:464`, `app/models/instrument.rb:111-128` |
| **Problem** | `Instrument.find_by_sid_and_segment` loops through multiple segment key mappings and issues multiple `find_by` queries per attempt. Called on every tick for index instruments (NIFTY, BANKNIFTY, SENSEX) at ~250ms intervals — ~4 queries/second to `instruments` table with no caching. |
| **Solution** | Cache resolved index instruments in a `Concurrent::Map` keyed by `security_id`. Result only changes on corporate actions. Alternatively use `Rails.cache` with a long TTL (hours). |
| **Effort** | ~1h |
| **Risk** | Low — pure read cache, stale data risk is near-zero (instruments rarely change) |
| **Status** | ⬜ Pending |

---

### ⬜ 5. Regex-based `numeric?` on every tick field

| Field | Value |
|-------|-------|
| **Category** | Backend — Memory / GC Pressure |
| **Files** | `app/services/live/redis_tick_cache.rb:215-222` |
| **Problem** | `numeric?` method uses regex (`/\A-?\d+(\.\d+)?\z/`) on every field of every tick for every write AND read. At thousands of ticks/second this creates significant GC pressure from short-lived hash allocations and regex MatchData objects. |
| **Solution** | Replace with known schema: define `NUMERIC_FIELDS = %i[ltp high low ...]` and use `v.to_f` only for those. Or use `Float(v)` with rescue instead of regex. |
| **Effort** | ~30min |
| **Risk** | Low — pure refactor, same observable behavior |
| **Status** | ⬜ Pending |

---

## 🟡 P2 — Medium

### ⬜ 6. `build_dashboard_stats` called every 1s

| Field | Value |
|-------|-------|
| **Category** | Backend — Heartbeat / Aggregation |
| **Files** | `app/services/live/pnl_updater_service.rb:467-517` |
| **Problem** | Called from `maybe_broadcast_heartbeat` every 1 second. Does: `AlgoConfig.mode` (YAML + DB), `PositionTracker.trading_stats_with_pct` (DB aggregate), 6x `TickCache.ltp`, 3x `build_options_buying_state` (multiple service calls), CircuitBreaker check, SystemStatusCache call. ~50-100ms CPU per second even when idle. |
| **Solution** | De-duplicate tick fetches (combine into single `fetch_all`). Cache stats with 1s TTL. Move aggregation to a dedicated thread so it doesn't block the PnL flush loop. |
| **Effort** | ~3h |
| **Risk** | Medium — dashboard stats must remain fresh, cache invalidation timing matters |
| **Status** | ⬜ Pending |

---

### ⬜ 7. Sequential WebSocket subscribe on reconnect

| Field | Value |
|-------|-------|
| **Category** | Backend — WebSocket / Recovery |
| **Files** | `app/services/live/market_feed_hub.rb:756-771` |
| **Problem** | On reconnect, iterates over each active tracker and calls `subscribe(segment:, security_id:)` individually — up to 50+ sequential subscribe calls. Takes many seconds, during which ticks for later-tracked positions are missed. |
| **Solution** | Batch all active position security IDs and call `subscribe_many` once, deduplicating with watchlist. |
| **Effort** | ~1h |
| **Risk** | Low — `subscribe_many` already exists and is used elsewhere |
| **Status** | ⬜ Pending |

---

### ⬜ 8. Missing partial DB indexes on hot query patterns

| Field | Value |
|-------|-------|
| **Category** | Database — Indexes |
| **Files** | `db/schema.rb` |
| **Problem** | Missing indexes on frequently queried columns and composite patterns: |
| | - `position_trackers`: missing partial index `WHERE status = 'active' ON (security_id, segment)` |
| | - `instruments`: missing composite index on `(security_id, segment)` |
| | - `candles`: missing index on `instrument_key` alone, missing index on `security_id` |
| | - `derivatives`: missing index on `security_id` |
| | - `smc_events`: missing index on `event_type` |
| **Solution** | Generate migrations for each missing index. The `position_trackers` partial index is the most impactful — speeds up the most frequent query in the system. |
| **Effort** | ~1h |
| **Risk** | Low — read-only indexes, no schema changes to column types |
| **Status** | ⬜ Pending |

---

## 🟢 P3 — Low

### ⬜ 9. `BigDecimal` creation in PnL hot path

| Field | Value |
|-------|-------|
| **Category** | Backend — Object Allocation |
| **Files** | `app/services/live/pnl_updater_service.rb:55-62` |
| **Problem** | `safe_decimal` calls `BigDecimal(s)` on every PnL batch. `BigDecimal` is significantly slower than `Float` for creation. These values are ultimately stored as `to_f` in Redis anyway, so decimal precision is not preserved. |
| **Solution** | Use `Float(s)` instead of `BigDecimal(s)` in the PnL hot path (keep `BigDecimal` only for entry/exit price tracking where monetary precision matters). |
| **Effort** | ~30min |
| **Risk** | Medium — verify no downstream code depends on `BigDecimal` precision from these values |
| **Status** | ⬜ Pending |

---

### ⬜ 10. `rescue StandardError` swallowing real errors

| Field | Value |
|-------|-------|
| **Category** | Backend — Error Handling |
| **Files** | `app/services/live/market_feed_hub.rb:447`, `app/services/live/pnl_updater_service.rb:421-430`, `app/services/live/redis_pnl_cache.rb:55-64` |
| **Problem** | Multiple locations use `rescue StandardError => e; nil` as normal flow control. This hides real errors like `NoMethodError` or `NameError` and makes debugging production issues difficult. |
| **Solution** | Use specific exception classes, or at minimum log the error with `Rails.logger.warn` before swallowing. |
| **Effort** | ~1h |
| **Risk** | Low — logging-only change, no behavior change |
| **Status** | ⬜ Pending |

---

### ⬜ 11. TypeScript: ActionCable leaks, missing render optimizations

| Field | Value |
|-------|-------|
| **Category** | Frontend — TypeScript / React |
| **Files** | Dashboard views: `TrailEngine.jsx`, `OptionChain.jsx`, `Reports.jsx`, `PriceChart.jsx` |
| **Problem** | 1) ActionCable subscriptions likely leak on unmount — components subscribing in `useEffect` without returning an unsubscribe function will keep receiving messages after navigation. 2) Missing `React.memo`/`useMemo` on large views receiving WebSocket data — every tick triggers full re-render of the entire view tree. 3) `PriceChart.jsx` (932 lines) likely re-renders entire chart on every LTP update without throttling. 4) Large lists (option chain strikes, positions) rendered without virtualization. |
| **Solution** | Add unsubscribe cleanup in `useEffect` returns. Add `React.memo` on expensive child components. Add 200ms throttle on chart data updates. Use `react-window` for virtualized lists. |
| **Effort** | ~3h |
| **Risk** | Medium — behavioral changes to real-time UI; test for stale data after throttle |
| **Status** | ⬜ Pending |

---

## Quick Wins (estimated 1-2h total)

These items can be implemented independently and carry minimal risk:

1. **#3** — Add `pluck(:id)` to `ActivePositionsCache` and use it from `redis_tick_cache.rb`
2. **#5** — Replace `numeric?` regex with `rescue Float()` approach
3. **#7** — Batch reconnect subscription to use `subscribe_many`
4. **#8** — Add partial index migration for `position_trackers`
5. **#4** — Cache `Instrument.find_by_sid_and_segment` results in `Concurrent::Map`
6. **#10** — Add error logging before `rescue nil` patterns
7. **#2** — Centralize Redis connections through a shared pool
