# Event-Based SMC — Codebase Alignment

This document describes how **Smart Money Concepts (SMC)** and related
structure logic are implemented in `algo_scalper_api`, and how that compares
to an “event-driven” mental model.

## Terminology

- **Event-driven SMC (actor model, candle-close bus)** — **Not implemented.**
  There is no dedicated pub/sub or per-instrument actor thread for SMC.
- **`Smc::SignalEvent`** — A **value object** for alerts (call/put/no_trade and
  reasons), not a domain event bus.
- **Structure state in Redis** — `Smc::StructureStore` writes JSON from
  `Smc::Analyzer#run` (key `smc:state:{symbol}:{interval}`). Updated when
  `Smc::Context` runs the analyzer; **not** a standalone recovery/replay engine.

**Integration style:** SMC is computed **on demand** when callers fetch candles
and build `Smc::Context`, plus **periodic** scans (Solid Queue job and optional
trading-daemon thread).

---

## Module Layout (`app/services/smc/`)

- **`bias_engine.rb`** — Multi-timeframe bias: HTF 60m, MTF 15m, LTF 5m.
  Produces `:call`, `:put`, or `:no_trade`. Enqueues Telegram alert job on
  signal or optional AI-backed `:no_trade` analysis.
- **`context.rb`** — Single timeframe: swing/internal structure, liquidity, OB,
  FVG, premium/discount; runs `Analyzer` for `phase`.
- **`analyzer.rb`** — Runs detectors, derives `phase` (trap / expansion / trend
  / neutral), updates `StructureStore`.
- **`structure_store.rb`** — Redis persistence of last analysis snapshot per
  symbol/interval.
- **`smc_permission_resolver.rb`** — Maps normalized SMC + AVRZ hashes to
  `:blocked`, `:execution_only`, `:scale_ready`, `:full_deploy`.
- **`signal_event.rb`** — Payload for notifications.
- **`scanner.rb`** — Long-running thread (when started by trading supervisor):
  periodic `BiasEngine` per index.
- **`ai_analyzer.rb`** — Optional LLM narrative over SMC/AVRZ context.

### Detectors (`app/services/smc/detectors/`)

- **`structure.rb`** — Swing-level BOS/CHoCH-style structure (exposed as
  `structure` on `Context`).
- **`internal_structure.rb`** — Internal structure snapshot.
- **`swing_structure.rb`** — Swing trend / swings.
- **`liquidity.rb`** — Sweeps, equal highs/lows, side-taken flags.
- **`order_blocks.rb`** — Order block detection output.
- **`fvg.rb`** — Fair value gaps (active / all_gaps).
- **`premium_discount.rb`** — Premium vs discount for HTF bias in
  `BiasEngine`.

---

## Related Code Outside `smc/`

- **`app/services/trading/permission_resolver.rb`** — Builds `smc_result` from
  three `Smc::Context` runs (HTF/MTF/LTF) plus `Avrz` heuristics, then calls
  `Smc::SmcPermissionResolver.resolve`.
- **`app/services/signal/engine.rb`** — After `EntryFilterEngine`, calls
  `Trading::PermissionResolver.resolve`. Optionally aligns Supertrend direction
  with `Smc::BiasEngine#decision` via `get_smc_decision`.
- **`app/services/entries/bos_entry_engine.rb`** — Separate **BOS pullback**
  state machine (`Entries::BosExtractor`, Redis-backed state). Complements SMC
  detectors but is **not** the same class tree as `Smc::Detectors::Structure`.
- **`app/jobs/smc_scanner_job.rb`** — Solid Queue: scans configured indices with
  `BiasEngine` (rate-limit friendly delays, optional AI Telegram).
- **`app/jobs/notifications/telegram/send_smc_alert_job.rb`** — Async alerts
  from `BiasEngine#notify`.
- **`app/services/notifications/telegram/smc_alert.rb`** — Telegram formatting.
- **`app/controllers/smc_controller.rb`** — HTTP entry for debugging
  (`decision`, optional `details=1`, `ai=1`).
- **`lib/console/smc_example.rb`**, **`lib/console/smc_helpers.rb`** — Console
  helpers.
- **`spec/services/smc/**/*_spec.rb`** — Unit specs for the SMC layer.

---

## Runtime and Scheduling

1. **Signal pipeline (`Signal::Scheduler` → `Signal::Engine`)** — On each cycle,
   permission tier comes from `Trading::PermissionResolver` (SMC + AVRZ).
   Optional SMC **direction** check uses `Smc::BiasEngine` when
   `enable_smc_decision_alignment` is true.

2. **Solid Queue (`SmcScannerJob`)** — Recurring job (see `config/recurring.yml`)
   runs `BiasEngine` per index for alerts/diagnostics—not the primary live entry
   path.

3. **Trading daemon (`Smc::Scanner`)** — Optional thread started by
   `TradingSystem::Supervisor` (see `CLAUDE.md`): same idea as the job, on a
   configurable period (default 300s), market-gated.

---

## Configuration (`config/algo.yml` — `signals`)

Relevant keys (defaults may vary by profile):

- **`enable_smc_avrz_permission`** — If false, `PermissionResolver` skips
  SMC+AVRZ and returns `:scale_ready` (see resolver implementation).
- **`enable_smc_decision_alignment`** — Gates `BiasEngine` alignment in
  `Signal::Engine`.
- **`permission_mode`** — `strict`, `lenient`, or `bypass` (passed to
  `Smc::SmcPermissionResolver`).
- **`smc_alert_cooldown_minutes`**, **`smc_max_alerts_per_session`** — Alert
  throttling.

---

## HTTP API Note

`GET /smc/decision` is routed in `config/routes.rb` on the **root** router (not
under `namespace :api`). Other REST APIs use `/api/*` per project standards.

---

## `Smc::BiasEngine` vs `Signal::Engine`

- **BiasEngine** — HTF premium/discount, MTF trend/CHoCH alignment, then LTF
  phase/trap/sweep rules (`ltf_entry`).
- **Signal::Engine** — `get_smc_decision` calls `BiasEngine#decision`. If the
  engine returns `:no_trade`, the signal layer **substitutes** call/put from the
  Supertrend direction (permissive path—see `get_smc_decision`). Alignment only
  blocks when SMC returns the **opposite** call/put.

---

## Gap Summary (Design vs Current)

- **Candle-close event bus, actor per symbol** — **Current:** polling
  (scheduler, jobs, on-demand `Context` creation).
- **Single SMC event vocabulary (`BOS`, `MitigationTouched`, …)** — **Current:**
  phase + detector hashes; no shared event registry.
- **Redis as authoritative OB/FVG live book** — **Current:** `StructureStore`
  holds last analyzer JSON; full “unmitigated zone” lifecycle is not isolated as
  its own service.

Use this file as the **source of truth** for file paths and behavior until a
dedicated event layer is added.
