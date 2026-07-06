# 05 — Runtime Manager

`Strategies::Manager` — the platform component that gives strategies a lifecycle. Replaces the role
`Signal::Scheduler` plays today (one hardcoded 30s loop) with per-strategy start / stop / restart /
reload / health, running inside the existing trading daemon.

## Position in the process tree

```text
TradingSystem::Daemon
  └── TradingSystem::Supervisor            (existing, LOCKED — minimal carve-out below)
        ├── :market_feed, :risk_manager, :exit_manager, … (existing ~20 services, unchanged)
        └── :strategy_manager  → Strategies::Manager      (NEW supervised service)
              ├── control loop thread (reconcile desired vs actual, heartbeats)
              ├── runner thread — supertrend_v1
              ├── runner thread — <strategy B>
              └── …
```

- **D-05.1 — Manager is a new supervised service, not a Supervisor rewrite.** It implements the
  existing informal service interface (`start` / `stop` / `healthy?`) and registers in
  `lib/trading_system/bootstrap.rb`. Strategy-level lifecycle lives entirely inside the manager.
  The Supervisor itself gains only three generic methods —
  `start_service(name)` / `stop_service(name)` / `restart_service(name)` — refactoring the loop
  bodies of the existing `start_all` / `stop_all`. That is the **single LOCKED edit** of the whole
  program (Phase 4 carve-out, [09](09_risks_and_change_policy.md)). No changes to registration
  order, `health_check`, or shutdown semantics.

## Threading model

- **D-05.2 — One runner thread per running strategy.** GIL contention is acceptable: strategy
  logic is bursty (fires on candle close), CPU-light, and reads in-memory snapshots. Contract:
  each invocation receives its own immutable `StrategyContext`; plugins never share mutable state
  with the platform. Thread names: `strategy-<slug>` (consistent with existing
  `signal-scheduler` / `paper-pnl-refresher` naming).
- Runner loop is **event-driven**: blocks on a per-strategy queue fed by the manager's
  `Core::EventBus` `:candle_closed` subscription, filtered by the strategy's declared
  `timeframes` × `instruments`. A configurable **interval mode** (fire every N seconds, like
  today's 30s cadence) exists as a compatibility/fallback option per strategy manifest.
- Queue policy: if a strategy is still evaluating when its next candle event arrives, the stale
  event is dropped (latest-wins) — a slow strategy skips bars rather than lagging reality.

## Lifecycle & reconciliation

States (mirrors `strategies.status`): `draft → deployed → running ⇄ stopped`, plus `errored`,
`archived`.

Control loop (every ~2s):

1. Read `strategies.desired_status` (set by API/dashboard, D-02.4) + Redis nudge key for low latency.
2. Reconcile: desired `running` & not running → load version (checksum-verified) → `on_start` →
   spawn runner → insert `strategy_runs` row. Desired `stopped` & running → signal runner →
   `on_stop` → join (timeout → kill) → close run row with `stop_reason`.
3. Heartbeat each runner (`strategy_runs.stats.last_heartbeat`, Redis mirror for the dashboard).
4. Market-close handling: at session end (`TradingSession::Service.should_force_exit?` /
   market close), all runners get `on_stop`; runs close with `stop_reason: "market_close"`.
   Next session, desired-`running` strategies restart automatically.

## Crash policy — D-05.3

- Runner exception → log (per-strategy log, [06](06_platform_services.md)), increment error count,
  publish `:strategy_error` on the bus, restart with **capped exponential backoff**
  (1s → 2s → 4s → … cap 60s).
- **N errors in M minutes (default 5 in 10) → auto-stop that strategy** (`status: errored`,
  `stop_reason: "error_limit"`) + Telegram alert via the existing notifier. Other strategies are
  never halted by one strategy's failure.
- A crashed strategy's open position is **not** orphaned: position monitoring/exits are
  platform-owned (`Live::RiskManagerService`, `Live::ExitEngine`) and keep running regardless.

## Kill-switch supremacy

`Risk::CircuitBreaker` tripped ⇒ the manager stops dispatching candle events to all runners
(strategies effectively paused; positions handled by RiskManager's force-close, unchanged).
Reset ⇒ dispatch resumes. The manager subscribes to the breaker state in its control loop — same
cache-backed pattern EntryGuard already uses. EntryGuard remains the authoritative gate; the
manager's pause is defense-in-depth, not the safety boundary.

## Hot reload

`POST /:slug/deploy` on a running strategy sets a pending-reload flag. The manager applies it only
when the strategy is **flat** (no open `PositionTracker` attributed to it); until then the old
version keeps running and the dashboard shows "reload pending". Rationale + alternative
(per-position version pinning, mirroring AlgoConfig pinning) recorded in
[09](09_risks_and_change_policy.md) risk register — flat-only chosen for v1 (simpler, safer).

## Health surface

`Strategies::Manager#healthy?` (Supervisor probe) = control loop alive. Per-strategy health
(status, last heartbeat, error count, current version, last signal) is exposed via:

- `GET /api/strategies` (+ `/:slug`) — [07](07_api_and_frontend_contract.md)
- `StrategyStatusChannel` broadcasts on every state transition + periodic heartbeat
- `Live::SystemStatusCache` entry (consistent with existing service heartbeats)

## What happens to `Signal::Scheduler`

Phase 2: frozen (no logic changes), runs alongside shadow-mode plugin.
Phase 4: `:signal_scheduler` deregistered from `bootstrap.rb`, `Signal::Scheduler` and
`Signal::Engine` deleted (D-01.3). Supporting pure-analysis classes they call
(`Signal::Validator`, `TrendScorer`, etc.) survive wherever the extracted plugin/context uses them.
