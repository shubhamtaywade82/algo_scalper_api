# Resilience / self-healing audit

Date: 2026-08-05

## Context

Sub-project 2 of 6 (decomposed during the DhanHQ-review brainstorming
session): DhanHQ gem upgrade (done) → **self-healing/resilience** →
backend services audit → jobs/workers audit → frontend/dashboard review →
MCP/agent skills integration.

A full sweep across all 11 daemon services (`lib/trading_system/bootstrap.rb`
registrations), the tick/PnL caching layer, the WebSocket layer, position
reconciliation, the circuit breaker, order-update idempotency, and entry
concurrency turned up 6 verified, concrete gaps. Most services already
follow a solid per-iteration-rescue pattern inside their run loops
(`PositionHeartbeat`, `Smc::Scanner`, `PaperPnlRefresher`,
`StatsNotifierService`, `OrderRouter` all checked clean); order-update
handling is idempotent by construction (sets absolute state via
`mark_exited!`/`mark_active!`, guarded by `tracker.with_lock`); the circuit
breaker fails open deliberately and correctly. The 6 gaps below are the
real, verified surface.

## Goals

1. **Daemon/Supervisor auto-restart** — `Supervisor#health_check` exists
   but has zero callers; `Daemon#keep_process_alive!` only watches for
   shutdown signals. If any of the 11 service threads dies mid-run
   (unhandled exception past its inner rescue, or a service's outer fatal
   handler setting `@running = false`), nothing notices or restarts it —
   the daemon process looks alive while a critical service is silently
   gone. Fix: periodic health check + auto-restart + alert.
2. **`daemon.rb` duplicate method bug** — `start_market_open_poller!` is
   defined twice (once calling `start_full_trading_services!`, which
   includes `TradingSystem::Bootstrap.boot_market_gates!`; once inlining
   `@supervisor.start_all` + `subscribe_active_positions!` without it).
   Ruby silently uses the second definition, so `boot_market_gates!` never
   runs when the daemon starts while the market is closed and later opens.
3. **`TickCache#fetch`'s in-memory fast path is commented out**
   (`app/services/tick_cache.rb:69-70`) — every read round-trips to Redis
   even inside the trading daemon process that just wrote the tick. Worse,
   this codebase runs `web` and `trading` as separate OS processes sharing
   only Postgres/Redis (no shared memory) — a blind "always trust memory"
   fix would make the `web` process return a stale price forever after its
   first read. Needs a fix that's safe for both process shapes.
4. **WS lifecycle hooks unused in `market_feed_hub.rb`** — the file's own
   comment says "DhanHQ WebSocket client only supports :tick events,"
   which was true in an older gem version but is false as of the
   currently-installed 3.2.0+ (`on(:open/:reconnect/:close/:error)`,
   `healthy?(stale_after:)`, `last_message_at`, `reconnect_count` all
   exist). The hub infers reconnect/health from time-since-last-tick,
   which can't distinguish "market is quiet" from "connection actually
   died."
5. **`ReconciliationService#fix_stuck_exit`'s fallback lies about state**
   — when `exit_engine` isn't reachable from the supervisor, it falls back
   to `tracker.mark_exited!` directly: the DB says closed, the broker was
   never asked to close anything. Rare trigger, bad failure mode.
6. **`Entries::AdvisoryLock.with_index_lock` is built but never wired in**
   — its own doc comment describes exactly the TOCTOU race
   (`EntryGuard.try_enter` has 7 independent call sites — `strategies/
   manager.rb`, `entry_manager.rb`, `signal/engine.rb` ×2, `signal/
   scheduler.rb`, `bos_entry_engine.rb`, `agents/trading_orchestrator.rb`
   — any two of which firing near-simultaneously for the same index could
   both pass exposure/max-concurrent/daily-limit checks before either
   commits, producing a double entry) but the lock has zero callers.

## Non-goals

- No changes to `EntryGuard`'s guard *logic* (cooldowns, exposure limits,
  etc.) — only wrapping the existing decision + tracker-creation sequence
  in the advisory lock.
- No changes to `Risk::CircuitBreaker` or order-update handling — both
  verified already correct.
- No dashboard/health-endpoint UI work — `Supervisor#health_check`'s
  output format stays as-is; this sub-project only makes something call it
  periodically and act on the result.
- No configurable TTL/interval knobs added to `AlgoConfig` for the new
  constants (memory-cache TTL, health-check interval) unless the
  implementation plan finds a concrete reason one's needed — hardcoded
  constants per YAGNI.

## Design

### 1. Daemon/Supervisor auto-restart

- `lib/trading_system/daemon.rb`: delete the second (duplicate, no
  `boot_market_gates!`) `start_market_open_poller!` definition; keep the
  first.
- `lib/trading_system/supervisor.rb`: make `health_check` public (currently
  under `private`).
- `Daemon#keep_process_alive!`: extend the existing 1-second loop with a
  30-second-interval check (simple counter, no new thread) that calls
  `@supervisor.health_check`, and for any `name => false` entry calls
  `@supervisor.restart_service(name)` plus
  `Notifications::TelegramNotifier.instance.notify_error(...)` with the
  service name. Single-check triggers restart — no consecutive-failure
  counter, since `healthy?`/`running?` only flip on genuine thread death,
  not transient conditions.

### 2. TickCache TTL-gated memory read

- `app/services/tick_cache.rb`: add a `:cached_at` field to the hash
  stored in `@map`, set in both `put()` (when the tick is written) and in
  `fetch()`'s Redis-hydration step (when a Redis value is read back into
  memory).
- `fetch()`: if `@map[key]` exists and `Time.current - @map[key][:cached_at]
  < MEMORY_TTL` (1.5 seconds), return it directly — no Redis call.
  Otherwise, fall through to today's Redis fetch + re-hydrate.
- This needs no per-process branching: the trading daemon's memory is
  always fresh (it just called `put()`), so it always wins the TTL check.
  The web process's hydrated copy ages past 1.5s almost immediately and
  falls through to Redis on the next read, same as today.

### 3. WS lifecycle hooks in `market_feed_hub.rb`

- Wire `@ws_client.on(:reconnect)` to call `resubscribe_active_positions_after_reconnect`
  directly, replacing the current inferred-from-tick-gap trigger.
- Wire `on(:open)` / `on(:close)` / `on(:error)` for logging.
- Replace the hub's own `connected?`/health inference with a delegation to
  `@ws_client.healthy?(stale_after: ...)` where it currently guesses from
  time-since-last-tick. This also gives part 1's watchdog an accurate
  signal for the `:market_feed` service specifically.
- Delete the stale "only supports :tick events" comment block.

### 4. `ReconciliationService#fix_stuck_exit` fallback fix

- When `exit_engine` is nil, replace the `tracker.mark_exited!` fallback
  with a `Notifications::TelegramNotifier.instance.notify_error` call
  (CRITICAL-level framing: "exit_manager unreachable, position
  #{tracker.order_no} stuck") and return without touching the tracker.
  The next reconciliation cycle (30s later) will retry `fix_stuck_exit`
  naturally since `stuck_in_exit?` remains true.

### 5. Wire `AdvisoryLock` into `EntryGuard.try_enter`

- Wrap the guard-pipeline checks through `PositionTracker` creation in
  `Entries::AdvisoryLock.with_index_lock(index_cfg[:key]) { ... }`.
- Order placement (the broker HTTP call via `Orders::Placer`/
  `Orders::GatewayLive`) stays **outside** the lock block — the lock
  should serialize the DB-side decision, not hold a Postgres session lock
  across a slow network call.
- Exact line boundaries (where the lock block starts/ends inside the
  ~250-line `try_enter` method) get pinned during the implementation plan
  after re-reading the method in full.

## Testing

- Task 1: spec for `Supervisor#health_check` being called periodically and
  triggering `restart_service` + alert on an unhealthy service (mock a
  service whose `running?` returns false).
- Task 2: spec proving `TickCache#fetch` returns the memory copy within
  the TTL window and falls through to Redis after it expires — covers both
  the "just wrote it" (daemon) and "stale after 1.5s" (web-process-like)
  cases.
- Task 3: spec confirming `on(:reconnect)` triggers
  `resubscribe_active_positions_after_reconnect` without waiting for a
  tick-gap timeout.
- Task 4: spec confirming `fix_stuck_exit` with `exit_engine: nil` alerts
  and leaves the tracker untouched (not marked exited).
- Task 5: spec confirming two concurrent `try_enter` calls for the same
  index serialize (second call sees the first's committed state before
  making its own exposure/limit decision) — likely via two threads and a
  shared counter/barrier, matching how Postgres advisory locks are
  normally tested.

## Handoff

None — this is the last sub-project touching the daemon/services layer
directly. Sub-project 3 (backend services audit) picks up signal/entry/
exit/risk *logic* correctness, building on a daemon that's now actually
self-healing.
