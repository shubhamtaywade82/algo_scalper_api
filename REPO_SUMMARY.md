# Algo Scalper API – Repository Summary

This document summarizes the structure and responsibilities of the `algo_scalper_api` repository, based strictly on the current codebase.

---

## 1. High-Level Purpose

Rails 8 API-only backend for **fully autonomous intraday options scalping** on Indian index markets (NIFTY, BANKNIFTY, SENSEX), built around:

- Signal generation (`app/services/signal`)
- Options analysis and strike selection (`app/services/options`)
- Capital allocation and position sizing (`app/services/capital`)
- Order execution (`app/services/orders`)
- Position tracking and PnL (`app/models/position_tracker.rb`, `app/services/positions`)
- Real-time risk and exit management (`app/services/live`, `app/services/risk`)

Two main processes:

- **Web API** (`bin/rails server`) – REST/JSON endpoints, dashboards, AI tools.
- **Trading daemon** (`ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon`) – runs all live trading services in threads, coordinated by `lib/trading_system/supervisor.rb`.

---

## 2. Key Directories and Responsibilities

### 2.1 `app/controllers/api`

- `health_controller.rb` – `/api/health` endpoint, includes MarketFeedHub / trading system health.
- `positions_controller.rb` – JSON representation of open/closed positions using `Positions::Serializer`.
- `dashboard_controller.rb` – aggregates PnL/statistics for the frontend.
- `analysis_controller.rb` – historical/analysis endpoints.
- `settings_controller.rb` – bulk update/read of typed settings via `AlgoSetting`.
- `circuit_breaker_controller.rb` – HTTP API around `Risk::CircuitBreaker` singleton (trip/reset).

### 2.2 `app/models`

- `position_tracker.rb` – central model for live and paper positions; owns:
  - lifecycle (active vs exited),
  - PnL aggregation,
  - integration with Redis PnL cache,
  - metadata for exits, strategies, and analytics.
- `instrument.rb` / `derivative.rb` – instruments and derivatives imported from DhanHQ CSVs.
- `candle_series.rb`, `candle.rb` – OHLC time series representation and indicator helpers.
- `trading_signal.rb` – persisted signals with accuracy and “avoid” logic.
- `watchlist_item.rb` – dynamic watchlist; connects to `Instrument`/`Derivative`.
- `algo_setting.rb` – typed façade over `Setting` table, with SCHEMA-based accessors.
- `dhan_access_token.rb` – persistent broker OAuth token (`expiry_time` based).

### 2.3 `app/services/live` (Trading Runtime)

Core runtime services wired in `lib/trading_system/bootstrap.rb`:

- `market_feed_hub.rb` – **DhanHQ WebSocket client singleton**:
  - Manages WS connection lifecycle (`start!`, `stop!`, `connected?`).
  - Subscriptions for watchlist and active positions (`subscribe`, `subscribe_many`, `unsubscribe`).
  - Distributes ticks to `TickCache`, `Positions::ActiveCache`, `RiskManagerService`, etc.
  - Resubscribe logic after reconnect (`resubscribe_active_positions_after_reconnect`).
- `risk_manager_service.rb` (+ `config.rb`, `runner.rb`, `exit_enforcement.rb`, `exit_execution.rb`, `pnl_cache.rb`) – enforces:
  - global and per-position risk limits,
  - time-based exits,
  - premium momentum failure, drawdown rules, trailing/secured profit transitions.
- `exit_engine.rb` / `orders/exit_engine.rb` (newer unified engine) – authoritative exit placement.
- `trailing_engine.rb` / `orders/trailing_engine.rb` – trailing stop logic.
- `unified_exit_checker.rb` – composes all exit conditions and delegates to exit engine.
- `market_feed_hub_service.rb` – adapter making `MarketFeedHub` look like a supervised “service”.
- `redis_pnl_cache.rb`, `pnl_updater_service.rb` – PnL snapshots in Redis and periodic flush to DB.
- `reconciliation_service.rb` – broker vs DB reconciliation.
- `position_index.rb` – in-memory `security_id → PositionTracker` index for fast lookup.
- `time_regime_service.rb`, `daily_limits.rb`, `edge_failure_detector.rb`, `feed_health_service.rb` – time-of-day risk gating, daily trade limits, early trend/edge failure detection, WebSocket health checks.

### 2.4 `app/services/signal`

- `engine.rb` – orchestrates signal generation:
  - Supertrend + ADX, multi-timeframe, market regime detection.
  - Integrates with `Options::ChainAnalyzer`, `Entries::EntryGuard`.
- `scheduler.rb` – 30s loop to run the engine per index configuration (NIFTY/BANKNIFTY/SENSEX).
- `index_selector.rb`, `trend_scorer.rb` – index selection and multi-indicator trend scoring.
- `confirmation_filter.rb` – additional confirmation filters around raw signals.

### 2.5 `app/services/options`

- `chain_analyzer.rb` – main options chain analysis:
  - Strike selection (ATM±1, liquidity scoring, gamma-aware decisions).
  - Validates expected move, IV-like proxies, participation flows.
- `derivative_chain_analyzer.rb` – lower-level derivative chain access.
- `delta_acceleration_detector.rb`, `gamma_ramp_detector.rb`, `flow_analyzer.rb` – microstructure / flow detectors.
- `historical_calibration_engine.rb` – historical calibration of options behaviour.
- `prop_strike_selector.rb` – proprietary strike selection heuristics.

### 2.6 `app/services/entries`

- `entry_guard.rb` / `entry_guard_pipeline.rb` – multi-guard entry pipeline:
  - risk gates (circuit breaker, cooldowns),
  - exposure/daily limit checks,
  - LTP resolution checks (via `Live::MarketFeedHub`).
- `bos_entry_engine.rb` – Break-of-Structure entry management.
- `guards/` – guard implementations (`ltp_resolution_guard.rb`, exposure, cooldown, etc.).

### 2.7 `app/services/capital` and `app/services/orders`

- `capital/allocator.rb` / `dynamic_risk_allocator.rb` – lot sizing based on risk config and trend regime.
- `orders/`:
  - `gateway_live.rb` / `gateway_paper.rb` (via `gateway_factory.rb`) – real vs paper execution paths.
  - `placer.rb` – idempotent order placement with dry-run support.
  - `executor.rb`, `adjuster.rb`, `gamma_trailing_engine.rb`, `expiry_rule_engine.rb`, `analyzer.rb`, `adaptive_trailing.rb` – rich order/execution control and trailing.
  - `mfe_exit_engine.rb`, `trailing_engine.rb`, `volatility_regime_detector.rb` – exit mechanics and volatility regime awareness.

### 2.8 `app/services/positions`

- `active_cache.rb` / `active_positions_cache.rb` – in-memory/Redis-backed active positions cache.
- `high_water_mark.rb`, `trailing_config.rb`, `drawdown_schedule.rb` (under `app/services` or `lib/positions`) – high-water mark and trailing configuration helpers.
- `metadata_resolver.rb` – derives index key, direction, and underlying metadata from a `PositionTracker`.
- `serializer.rb` – shapes JSON for open/closed positions used by `Api::PositionsController`.

### 2.9 `app/services/auto_exp`, `backtest`, `orchestration`, `market_state`, `optimization`

- `auto_exp/` – auto-experimentation:
  - `experiment_runner.rb`, `backtest_executor.rb`, `llm_planner.rb`, `results_store.rb` – backtesting and AI-driven configuration exploration.
- `backtest/` – backtest engine:
  - `engine.rb`, `market_replayer.rb`, `strategy_adapter.rb`, `api_loader.rb`, `data_loader.rb`.
- `orchestration/strategy_runner.rb` – coordinates strategies across indices/timeframes.
- `market_state/` – `market_state_engine.rb`, `trend_detector.rb`, `volatility_detector.rb`.
- `optimization/` – `trade_analyzer.rb`, `trailing_optimizer.rb`.

### 2.10 `app/jobs`

- `clear_carried_overnight_positions_job.rb` – clean up positions carried unintentionally.
- `instruments_import_job.rb` – daily instrument CSV import from DhanHQ.
- `smc_scanner_job.rb`, `ai_technical_analysis_job.rb` – SMC pattern scans + AI analysis.
- `analysis_job.rb` – on-demand analysis (async).

### 2.11 `lib/` and Trading System

- `lib/trading_system/daemon.rb`, `bootstrap.rb`, `supervisor.rb` – process lifecycle and service wiring for the trading daemon.
- `lib/services/ai/` – OpenAI integration (`openai_client.rb`, `technical_analysis_agent/*`).
- `lib/notifications/telegram_notifier.rb` – low-level Telegram bot wrapper.
- `lib/tasks/*.rake` – rake tasks:
  - Trading daemon (`trading.rake`),
  - options calibration, historical options, trailing optimization,
  - AI technical analysis, SMC diagnostics, Redis/WS diagnostics, backtests.

### 2.12 `dashboard/`

- Vue-based (or hybrid) dashboard that consumes API endpoints:
  - `OpenPositions.vue`, `ClosedTrades.vue`, and composables (e.g., `usePositions.js`) that read from `/api/positions` and related endpoints.

### 2.13 `docs/`

- Architecture diagrams and narrative docs:
  - `docs/architecture/diagrams/*` – system-level diagrams and service maps.
  - `docs/trading/entry_and_exit_rules.md` – detailed entry/exit rule descriptions.
  - `docs/services/*` – service catalog, live services notes.
  - `docs/position_tracker_exit_logic_analysis.md` – deep dive into position/exit logic.

---

## 3. Modes and Configuration

- **Paper vs Live**:
  - Controlled via `config/algo.yml` → `paper_trading.enabled` and `dhanhq.enable_orders`.
  - Gateway selection at boot: paper → `Orders::GatewayPaper`, live → `Orders::GatewayLive`.
  - Both modes use real WebSocket and option chain data.
- **Typed Settings**:
  - `AlgoSetting` + `Setting` model + `config/algo.yml` drive:
    - feature flags, ADX thresholds, risk limits, time restrictions.
- **Profiles** (`config/profiles/*.yml`):
  - `entry_testing.yml`, `exit_testing.yml`, `production.yml` – profile-specific overrides.

---

## 4. Risk, Exits, and Circuit Breaker

- **Risk Rules** (`app/services/risk/rules/*`):
  - Implement individual exit and risk conditions (premium momentum failure, time stop, R:R booking, etc.).
- **Risk::CircuitBreaker** – Redis-backed toggle:
  - Checked in `Entries::EntryGuard` and `RiskManagerService`.
  - API surface in `Api::CircuitBreakerController`.
- **Unified Exit Path**:
  - All exits go through the unified exit engine (`app/services/orders/exit_engine.rb` / `app/services/live/exit_engine.rb`), so there is a single place to audit exit decisions.

---

## 5. Testing and Code Health

- **RSpec** (`spec/`):
  - Model specs (`spec/models`), service specs (`spec/services`), integration/smoke specs.
  - Heavy use of FactoryBot and VCR (for DhanHQ HTTP/WebSocket interactions).
- **Static analysis and code health**:
  - `rubocop` + Rails/RSpec/Faker cops.
  - `debride` via `rake code_health:debride` for dead-method candidates.
  - `rails_best_practices` available (configured via `config/rails_best_practices.yml`, used advisably, not as absolute truth).
  - `rubycritic` available for complexity/smell analysis.

---

## 6. Entry Points and Commands

- **Development**:
  - `./bin/dev` – run web, trading, jobs, and dashboard together.
  - `bundle exec rspec` – test suite.
  - `bundle exec rubocop` – style/lint.
  - `bin/brakeman --no-pager` – security scan.
- **Trading Daemon**:
  - `ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon` – run only the trading brain.
- **Code Health**:
  - `bundle exec rake code_health:debride`
  - `bundle exec rails_best_practices .` (advisory).

This summary should give you a single, up-to-date view of how the repo is structured and where to look for specific behaviour (signals, exits, risk, WebSocket feeds, dashboards, and AI tooling).

