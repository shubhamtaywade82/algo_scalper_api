# 01 — Current State & Gap Analysis

Verified against the codebase on branch `feat/frontend-architecture-setup` (July 2026). Every claim
below was checked against actual files; paths are repo-relative.

## 1. Inventory by layer

### Layer 1 — Data ingestion

| Component | Status | Where / gap |
| --- | --- | --- |
| WebSocket manager | `EXISTS` | `app/services/live/market_feed_hub.rb` (tick distribution, reconnect), `app/services/live/order_update_hub.rb` |
| Tick processing/cache | `EXISTS` | `app/services/live/redis_tick_cache.rb` (Redis hashes, 24h TTL), `app/services/tick_cache.rb` (memory), `app/services/live/tick_query.rb` (read boundary) |
| Historical loader | `EXISTS` | `app/models/concerns/candle_extension.rb` → DhanHQ `intraday_ohlc` on demand; `app/services/backtest/api_loader.rb` |
| Gap recovery / backfill | `EXISTS` | `app/services/live/historical_backfill_service.rb` — rate-limited (1 req/2s), circuit breaker, converts candles→synthetic ticks on reconnect |
| **OHLCV DB** | `MISSING` | **No `candles` table in `db/schema.rb`.** Candles are fetch-on-demand + Redis-ephemeral only → [03](03_data_layer.md) |
| Tick persistence | `MISSING` (by design) | No `ticks` table. Deliberate: persist finalized candles, not ticks (matches transcript recommendation; reaffirmed here) |

### Layer 2 — Market data processing

| Component | Status | Where / gap |
| --- | --- | --- |
| 1m candle builder (live) | `EXISTS` | `app/services/live/candle_series_cache.rb` (Redis-merged series, `append_tick` forms current bar, TTL 3600s); `app/services/options_buying/minute_bar_aggregator.rb` (per-strike 1m buckets from WS ticks) |
| Multi-TF aggregation | `PARTIAL` | Config declares regime 15m / structure 5m / execution 1m (`app/services/market_data/engine.rb`) but each TF is a separate broker fetch — no tick→multi-TF rollup pipeline → [03](03_data_layer.md) |
| Indicator engine | `EXISTS` | `app/services/indicators/` — Supertrend, ADX, RSI, MACD, EMA, ML-adaptive Supertrend, trend duration, holy grail. Batch `calculate_at(index)` model, not incremental streaming → [10](10_greeks_and_indicator_streaming.md) |
| Market structure engine | `EXISTS` | `app/services/smc/` (structure, liquidity, displacement, volume, zone, bias, MTF-bias engines, confluence, AVRZ), `app/services/market_state/`, `app/services/market_structure/engine.rb` — the most mature analytical layer |
| Candle model | `EXISTS` (PORO) | `app/models/candle.rb`, `app/models/candle_series.rb` — in-memory, `MAX_CANDLES = 200`, **not ActiveRecord** |

### Layer 3 — Market intelligence

| Component | Status | Where / gap |
| --- | --- | --- |
| Option chain engine | `EXISTS` | `app/services/options/chain_analyzer.rb`, `chain_watch_service.rb`, `flow_analyzer.rb`, `strike_qualification/`, `index_rules/`; adapter `app/services/adapters/option_chain/dhan_adapter.rb` (live even in paper mode) |
| Greeks engine | `MISSING` (deferred) | Greeks consumed from DhanHQ chain payload (`chain_analyzer.rb` reads `option_data['greeks']`). **No Black-Scholes / IV solver anywhere.** IV recorded via `iv_snapshots` table + `Options::IvRankTracker`. Decision: skip for v1 → D-10.1 |
| Strike selector | `EXISTS` | `app/services/options/strike_selector.rb`, `prop_strike_selector.rb`, qualification scoring |
| Event bus | `EXISTS` | `app/services/core/event_bus.rb` — in-process singleton, fixed `EVENTS` enum, mutex-guarded. Subscribers: entry_manager, bracket_placer, active_cache, exit_engine, pnl_updater, risk_manager, profit_lock_engine, pnl_tracker. **Not Redis pub/sub** — fine for single-process (D-02.1) |
| Durable event store | `EXISTS` | `smc_events` table + `app/services/event_store/publisher.rb` (schema-validated append-only) + `event_store/replay_engine.rb` |

### Layer 4 — Strategy runtime ⟵ the core gap

| Component | Status | Where / gap |
| --- | --- | --- |
| Strategy base class | `DEAD` | `app/services/strategy/base.rb` — `Strategy::Base#call(context:, market:, indicators:)`, no subclasses in use |
| Strategy registry | `DEAD` | `app/services/strategy/registry.rb` — maps day_type/session/regime → `Strategy::NiftyImpV1` / `Strategy::ExpiryBreakout`, **classes that do not exist anywhere** |
| Strategy orchestrator | `DEAD` | `app/services/strategy/orchestrator.rb` — no callers |
| Context builder | `DEAD` | `app/services/context/builder.rb` → `Domain::TradingContext` — consumed only by the dead orchestrator |
| Alt runner | `DEAD` | `app/services/orchestration/strategy_runner.rb` — full pipeline duplicate of `Signal::Engine`, zero callers |
| **Actual strategy** | `EXISTS` (hardcoded) | `app/services/signal/engine.rb` — `Signal::Engine.run_for`: Supertrend 1m flip → chop gate → quality/DTE gates → `Options::ChainAnalyzer` → `Entries::EntryGuard`. Driven by `app/services/signal/scheduler.rb` (30s thread loop). Parameterized via `AlgoConfig`, but the algorithm itself is not pluggable |
| Strategy persistence/versioning | `MISSING` | No `strategies` / `strategy_versions` tables. Only *config* is versioned (`algo_config_change_logs`) |

### Layers 5–7 — Decision/risk, execution, post-trade (LOCKED, reused as-is)

All `EXISTS`, healthy, and frozen by the `CLAUDE.md` change policy: `Entries::EntryGuard` +
10-guard pipeline, `Capital::Allocator`, `Live::RiskManagerService`, `Risk::CircuitBreaker`,
`Orders::Gateway{Live,Paper}` + `Orders::Placer`, `Live::OrderUpdateHandler`, `Live::ExitEngine`,
`Live::TrailingEngine`, `Live::UnifiedExitChecker`, `Live::ReconciliationService`,
`PositionTracker` + paper double-entry ledger (`app/services/ledger/`). The new runtime plugs in
**above** EntryGuard, exactly where `Signal::Engine.run_for` sits today (D-01.3).

### Platform services

| Component | Status | Where / gap |
| --- | --- | --- |
| Config system | `EXISTS` (mature) | `app/lib/algo_config.rb` (layered DB-doc → tier preset → env override, 30s cache, per-position pinning), `app/services/algo_config/document_store.rb`, `algo_config_change_logs` audit. **Model for the new variables store** |
| Scheduler | `EXISTS` | Solid Queue `config/recurring.yml` (many jobs) + `Signal::Scheduler` thread. No per-strategy scheduler (follows from strategy gap) |
| Logging | `PARTIAL` | `lib/observability/structured_log.rb`; `GET /api/logs` = file tail (last 50KB), poll-based. **No live streaming, no per-strategy logs** |
| ActionCable | `EXISTS` | `app/channels/`: dashboard, positions, funds, holdings, option_chain, alerts. No strategy status/log channels |
| Backtest / replay | `EXISTS` (headless) | `app/services/backtest/` — engine, market_replayer, data_loader, api_loader, option_trade_simulator, smc_replay_runner, metrics, report + rake tasks (`lib/tasks/backtest*.rake`). **No API endpoints** |
| Notifications | `EXISTS` | Telegram notifier, `Live::StatsNotifierService`, alert jobs |
| Supervisor | `PARTIAL` | `lib/trading_system/supervisor.rb` — registers ~20 services, `start_all`/`stop_all` only. **No per-service start/stop/restart, no crash detection or auto-restart**; `health_check` is a passive snapshot → [05](05_runtime_manager.md) |
| Metrics | `PARTIAL` | `lib/observability/entry_funnel_metrics.rb`, trade telemetry tables. No metrics export (deferred) |

## 2. Dead-code register (decisions)

- **D-01.1 — Delete and rebuild** (user-confirmed). The dead scaffold —
  `app/services/strategy/{base,registry,orchestrator}.rb`, `app/services/context/builder.rb`,
  `Domain::TradingContext`, `app/services/orchestration/strategy_runner.rb` — is removed in
  Phase 2 after harvesting ideas (context shape, registry keying). Rationale: its contract predates
  AlgoConfig pinning and the SMC context; reviving invites drift; a clean `Strategies::` (plural)
  namespace avoids collision with the legacy `Strategy::` constant during migration.
  `docs/NEW_ANALYTICS_AND_STRATEGY_LAYER.md` (which documents this scaffold as intended
  architecture) gets a superseded banner.
- **D-01.2 — `Backtest::*` is the replay foundation.** Reuse wholesale; the gap is API surface and
  a session model, not engine work → [06](06_platform_services.md).
- **D-01.3 — `Signal::Engine` is strategy #1 in disguise.** The whole project reframes as
  *extract it*: its Supertrend alpha logic becomes `strategies/supertrend_v1/`; its glue
  (scheduler loop, EntryGuard handoff) becomes platform runtime. `Signal::Engine`/`Signal::Scheduler`
  are migration-frozen during extraction, then **deleted** after replay parity (user-confirmed).
  Note: `signal/scheduler.rb` already contains large deprecated regions
  (`evaluate_supertrend_signal`, `evaluate_with_trend_scorer`, `evaluate_strategy` and the
  `engine_class` path) — dead weight that disappears with it.

## 3. Frontend ahead of backend

The dashboard (`dashboard/` — **SolidJS** + Vite + Tailwind; `solid-js`, `@solidjs/router`,
ActionCable client, axios) already ships views for platform features that have **no backend**:

| View | Current behavior | Needed backend |
| --- | --- | --- |
| `dashboard/src/views/Strategies.jsx` | Read-only config display from `DashboardContext` | Strategy CRUD/lifecycle API → [07](07_api_and_frontend_contract.md) |
| `dashboard/src/views/Backtester.jsx` | Client-side only | `POST /api/backtests` + progress channel |
| `dashboard/src/views/Replay.jsx` | Client-side only | `POST /api/replays` + results API |
| `dashboard/src/views/Logs.jsx` | Polls `GET /api/logs` (file tail) | Live stream channel + per-strategy logs |
| `dashboard/src/views/Scheduler.jsx` | `GET /api/scheduler/tasks` | Extends naturally to strategy schedules |

## 4. Database schema today (relevant subset)

Tables that exist: `settings` (holds `algo_config_document`), `algo_config_change_logs`,
`instruments`, `derivatives`, `iv_snapshots`, `market_holidays`, `watchlist_items`,
`trading_signals`, `options_buying_signal_events`, `smc_events`, `position_trackers`,
`position_meta_snapshots`, `trade_analytics`, `trade_telemetry`, ledger tables
(`ledger_accounts/journal_entries/postings`), paper tables (`paper_wallets/daily_wallets/orders/
positions/trades/fills_logs`), `alpha_signals`, `best_indicator_params`, `calibration_runs`,
`dhan_access_tokens`, `public_ip_logs`, Solid Queue tables.

**Missing for the platform:** `candles`, `strategies`, `strategy_versions`, `strategy_runs`,
`strategy_signals`, `platform_variables`, `replay_sessions`.

## 5. Gap matrix (summary)

| Capability | Status | Upgrade doc |
| --- | --- | --- |
| Durable candle store + multi-TF | `MISSING` | [03](03_data_layer.md) |
| Strategy plugin contract + context | `DEAD` scaffold → `NEW` | [04](04_strategy_plugin_system.md) |
| Strategy registry / versioning / deploy | `MISSING` | [04](04_strategy_plugin_system.md), [06](06_platform_services.md) |
| Variables store | `MISSING` (AlgoConfig is the pattern) | [06](06_platform_services.md) |
| Runtime manager (per-strategy lifecycle) | `MISSING` | [05](05_runtime_manager.md) |
| Security scanner | `MISSING` | [06](06_platform_services.md) |
| Live log streaming | `MISSING` | [06](06_platform_services.md) |
| Replay/backtest API | `MISSING` (engines exist) | [06](06_platform_services.md), [07](07_api_and_frontend_contract.md) |
| Strategy/replay frontend wiring | `MISSING` (views exist) | [07](07_api_and_frontend_contract.md) |
| Greeks engine | Deferred | [10](10_greeks_and_indicator_streaming.md) |
| Incremental indicators | Deferred | [10](10_greeks_and_indicator_streaming.md) |
