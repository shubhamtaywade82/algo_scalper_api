# 09 — Risks & Change Policy

## 1. CLAUDE.md LOCKED-layer carve-out (proposal)

The `CLAUDE.md` "Stable vs Alpha Layers" policy locks `lib/trading_system/` and the execution
plumbing. This program needs exactly one LOCKED edit, in Phase 4. Proposed CLAUDE.md amendment
(to be applied when Phase 4 starts, with user approval):

> **Named exception — Strategy Platform Phase 4 (docs/infra-strategy-setup/):**
>
> 1. `lib/trading_system/supervisor.rb` may gain `start_service(name)` / `stop_service(name)` /
>    `restart_service(name)` as a refactor of the existing `start_all`/`stop_all` loop bodies.
>    No changes to registration order, `health_check` semantics, or shutdown behavior.
> 2. `lib/trading_system/bootstrap.rb` may register `:strategy_manager`
>    (`Strategies::Manager`) and deregister `:signal_scheduler`.
> 3. `app/services/signal/engine.rb` and `app/services/signal/scheduler.rb` are reclassified
>    **migration-frozen** (no logic changes) from Phase 2, and **deleted** at the Phase-4
>    cutover after replay parity.
>
> Everything else in the LOCKED list — gateways, placer, market feed hubs, tick caches,
> position lifecycle, risk-manager plumbing, exit engines — remains locked and untouched by
> this program.

This is consistent with the policy's own Critical Scenario framing: the change is minimal,
preserves idempotency/order-uniqueness/linear position lifecycle, and all PnL/alpha iteration
stays in alpha layers (the plugins).

Also at program end: update CLAUDE.md's architecture/services tables (daemon service list,
trading-flow diagram) to reflect `Strategies::Manager` and the removal of `Signal::*`.

## 2. Safety invariants (non-negotiable, enforced by design + scanner + review)

1. **No eval-from-DB, ever.** Strategy code executes only from checksum-verified workspace release
   files (D-00.2).
2. **Plugins cannot reach execution.** No `Orders::`/`Entries::`/`Live::` access from strategy
   code; the only path to a trade is manager → `Entries::EntryGuard` (unchanged 10-guard
   pipeline) → gateway (D-02.2).
3. **Kill-switch supremacy.** `Risk::CircuitBreaker` trip pauses all strategy dispatch *and*
   EntryGuard still independently blocks — two layers, breaker wins (see
   [05](05_runtime_manager.md)).
4. **One strategy's failure never halts another** — and never disables platform-owned position
   monitoring/exits.
5. **Exit placement stays single-sourced** in `Live::ExitEngine`; plugin exit signals are advisory
   inputs, not order calls.
6. **Position sizing stays in `Capital::Allocator`** — plugins emit intent, never quantity.
7. **DB writes never happen on the tick path** — candle persistence is async (D-03.4).

## 3. Risk register

| # | Risk | Likelihood / impact | Mitigation |
| --- | --- | --- | --- |
| R1 | **Behavioral drift during `Signal::Engine` extraction** — subtle differences (candle source, rounding, gate ordering) change live trading behavior | Medium / High | Shadow mode + replay-parity gate on ≥3 sessions before cutover; engine frozen during migration; keep freeze tag for instant rollback ([08](08_migration_roadmap.md) Phase 2/4) |
| R2 | **Hot-reload while a position is open** — new version's exit expectations mismatch the position the old version opened | Medium / High | v1: reload deferred until flat ([05](05_runtime_manager.md)). Documented alternative if flat-only proves annoying: per-position version pinning, mirroring AlgoConfig's `position_snapshot` pattern |
| R3 | **Strategy thread crash corrupting shared state** | Low / High | Contexts are immutable per-invocation snapshots; plugins hold no platform references; crash policy isolates + backoff-restarts + error-limit stops (D-05.3) |
| R4 | **Candle persister lag/failure** → gaps in stored history | Medium / Low | Live trading unaffected (Redis path authoritative intraday); backfill service reconciles gaps; upsert idempotency; persister failure alerts |
| R5 | **Scanner false confidence** — AST denylist is not a sandbox; a determined mistake still runs | Medium / Medium | Documented honestly (D-06.2): scanner is a footgun-guard. The real boundaries are invariants 1–2 (no execution access exposed) + code review + git history |
| R6 | **Event-driven dispatch misses bars** (bus hiccup, slow strategy) | Low / Medium | Latest-wins queue policy (skip stale bars, never lag); heartbeats surface stalls; interval-mode fallback per manifest |
| R7 | **Web↔daemon reconciliation lag** — dashboard start/stop feels async | High / Low | By design (202 + channel confirm); Redis nudge keeps it ~sub-second; UI shows pending state |
| R8 | **Supervisor refactor regression** (the one LOCKED edit) | Low / High | Pure refactor of loop bodies; existing daemon boot/shutdown specs must pass unchanged; reviewed against carve-out text; done in isolation, not bundled with feature work |
| R9 | **Scope creep toward Dhan-Cloud features with no local value** (multi-runtime, containers, marketplace) | Medium / Medium | Non-goals pinned in [00](00_overview.md); revisit triggers documented per deferral |
| R10 | **`Hold` signal volume bloats `strategy_signals`** | Medium / Low | Sample holds (state-change + heartbeat only, [04](04_strategy_plugin_system.md)); retention job if needed |

## 4. Open questions (deliberately deferred, with defaults)

| Question | Default until revisited |
| --- | --- |
| Per-position strategy-version pinning (R2 alternative)? | No — flat-only reload |
| Persist option-strike candles for premium-accurate replay? | No — indices only (D-03.3); replay premiums via `Backtest::OptionTradeSimulator` model |
| Multi-runtime (Python) strategies? | No — Ruby only; contract kept runtime-agnostic |
| Prometheus/metrics export? | No — dashboard + status cache suffice |
| Strategy marketplace / import-export? | No — git is the sharing mechanism |
