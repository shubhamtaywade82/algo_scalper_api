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

- **Web API** (`bin/rails server -p 3001`) — REST/JSON endpoints, dashboards, AI tools.
- **Trading daemon** (`ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon`) — runs all live trading services in threads, coordinated by `lib/trading_system/supervisor.rb`.

Jobs process (`bin/jobs`) runs Solid Queue for recurring tasks. Dashboard (`cd dashboard && npm run dev`) is a separate Next.js frontend.

---

## 2. Key Directories and Responsibilities

### 2.1 `app/controllers/api`

- `health_controller.rb` — `/api/health` endpoint, includes MarketFeedHub / trading system health.
- `positions_controller.rb` — JSON representation of open/closed positions using `Positions::Serializer`.
- `dashboard_controller.rb` — aggregates PnL/statistics for the frontend.
- `analysis_controller.rb` — historical/analysis endpoints.
- `settings_controller.rb` — bulk update/read of typed settings via `AlgoSetting`.
- `circuit_breaker_controller.rb` — HTTP API around `Risk::CircuitBreaker` singleton (trip/reset).

### 2.2 `app/models`

- `position_tracker.rb` — central model for live and paper positions; owns lifecycle (active vs exited), PnL aggregation, Redis PnL cache integration, metadata for exits, strategies, and analytics.
- `instrument.rb` / `derivative.rb` — instruments and derivatives imported from DhanHQ CSVs.
- `candle_series.rb`, `candle.rb` — OHLC time series representation and indicator helpers.
- `trading_signal.rb` — persisted signals with accuracy and "avoid" logic.
- `watchlist_item.rb` — dynamic watchlist; connects to `Instrument`/`Derivative`.
- `algo_setting.rb` — typed façade over `Setting` table, with SCHEMA-based accessors.
- `dhan_access_token.rb` — persistent broker OAuth token (`expiry_time` based).

### 2.3 `app/services/live` (Trading Runtime)

Core runtime services wired in `lib/trading_system/bootstrap.rb`:

- `market_feed_hub.rb` — **DhanHQ WebSocket client singleton**: manages WS connection lifecycle, subscriptions for watchlist and active positions, distributes ticks to `TickCache`, `Positions::ActiveCache`, `RiskManagerService`. Resubscribes active positions after reconnect.
- `risk_manager_service.rb` (+ `config.rb`, `runner.rb`, `exit_enforcement.rb`, `exit_execution.rb`, `pnl_cache.rb`) — enforces global and per-position risk limits, time-based exits, premium momentum failure, drawdown rules, trailing/secured profit transitions.
- `exit_engine.rb` — authoritative exit placement (single source of truth).
- `trailing_engine.rb` — trailing stop logic.
- `unified_exit_checker.rb` — composes all exit conditions and delegates to exit engine.
- `market_feed_hub_service.rb` — adapter making `MarketFeedHub` look like a supervised service.
- `redis_pnl_cache.rb`, `pnl_updater_service.rb` — PnL snapshots in Redis and periodic flush to DB (250ms).
- `reconciliation_service.rb` — broker vs DB reconciliation every 30s.
- `position_index.rb` — in-memory `security_id → PositionTracker` index for fast lookup.
- `time_regime_service.rb`, `daily_limits.rb`, `edge_failure_detector.rb`, `feed_health_service.rb` — time-of-day risk gating, daily trade limits, early trend/edge failure detection, WebSocket health checks.

### 2.4 `app/services/signal`

- `engine.rb` — orchestrates signal generation: Supertrend + ADX, multi-timeframe, market regime detection. Integrates with `Options::ChainAnalyzer`, `Entries::EntryGuard`. Supports optional market context gate when `market_context.enabled: true`.
- `scheduler.rb` — 30s loop to run the engine per index configuration (NIFTY/BANKNIFTY/SENSEX).
- `index_selector.rb`, `trend_scorer.rb` — index selection and multi-indicator trend scoring.
- `confirmation_filter.rb` — additional confirmation filters around raw signals.

### 2.5 `app/services/options`

- `chain_analyzer.rb` — main options chain analysis: strike selection (ATM±1, liquidity scoring, gamma-aware decisions), expected move validation, IV-like proxies, participation flows.
- `derivative_chain_analyzer.rb` — lower-level derivative chain access.
- `delta_acceleration_detector.rb`, `gamma_ramp_detector.rb`, `flow_analyzer.rb` — microstructure / flow detectors.
- `historical_calibration_engine.rb` — historical calibration of options behaviour.
- `chain_signal_extractor.rb` — derives chain confirmation (optional market context gate input).

### 2.6 `app/services/entries`

- `entry_guard.rb` / `entry_guard_pipeline.rb` — 20-guard entry pipeline (DrawdownGuard through SmcNavigatorGuard).
- `bos_entry_engine.rb` — Break-of-Structure entry management.
- `guards/` — guard implementations (20 guards total including `ExpiryWeekPowerTrendGuard`).

### 2.7 `app/services/capital` and `app/services/orders`

- `capital/allocator.rb` / `dynamic_risk_allocator.rb` — lot sizing based on risk config and trend regime.
- `orders/gateway_live.rb` / `gateway_paper.rb` (via `gateway_factory.rb`) — real vs paper execution paths.
- `orders/placer.rb` — idempotent order placement; requires `PLACE_ORDER=true` for live broker calls.
- `orders/executor.rb`, `adjuster.rb`, `gamma_trailing_engine.rb`, `expiry_rule_engine.rb`, `analyzer.rb`, `adaptive_trailing.rb` — rich order/execution control and trailing.
- `orders/mfe_exit_engine.rb`, `trailing_engine.rb`, `volatility_regime_detector.rb` — exit mechanics and volatility regime awareness.

### 2.8 `app/services/positions`

- `active_cache.rb` / `active_positions_cache.rb` — in-memory/Redis-backed active positions cache.
- `high_water_mark.rb`, `trailing_config.rb`, `drawdown_schedule.rb` — high-water mark and trailing configuration helpers.
- `metadata_resolver.rb` — derives index key, direction, and underlying metadata from a `PositionTracker`.
- `serializer.rb` — shapes JSON for open/closed positions used by `Api::PositionsController`.

### 2.9 `app/services/market_context` (Optional Alpha Layer)

When `market_context.enabled: true` in `config/algo.yml`:

- `regime_composer.rb` — builds `RegimeSnapshot` from `MarketRegimeDetector` + structure/volatility/participation analyzers.
- `regime_snapshot.rb` — value object with structure, strength, volatility_state, participation, conviction_score.
- `structure_analyzer.rb`, `volatility_analyzer.rb`, `participation_analyzer.rb` — component analyzers.

### 2.10 `app/services/auto_exp`, `backtest`, `orchestration`, `market_state`, `optimization`

- `auto_exp/` — experiment runner, backtest executor, LLM planner, results store.
- `backtest/` — backtest engine, market replayer, strategy adapter.
- `orchestration/strategy_runner.rb` — coordinates strategies across indices/timeframes.
- `market_state/` — market state engine, trend detector, volatility detector.

### 2.11 `app/jobs`

- `clear_carried_overnight_positions_job.rb` — clean up positions carried unintentionally.
- `instruments_import_job.rb` — daily instrument CSV import from DhanHQ.
- `smc_scanner_job.rb`, `ai_technical_analysis_job.rb` — SMC pattern scans + AI analysis (runs via Solid Queue).
- `analysis_job.rb` — on-demand analysis (async).

### 2.12 `lib/` and Trading System

- `lib/trading_system/daemon.rb`, `bootstrap.rb`, `supervisor.rb` — process lifecycle and service wiring for the trading daemon (11 services).
- `lib/services/ai/ollama_client.rb` — thin wrapper around `Ollama::Client` from the `ollama-client` gem (`~> 1.1`). Provides chat, generate, and streaming interfaces with serialized request queuing and model auto-selection. **Not OpenAI** — ruby-openai and openai gems have been removed.
- `lib/services/ai/technical_analysis_agent.rb` (+ `technical_analysis_agent/`) — LLM-backed multi-timeframe technical analysis.
- `lib/notifications/telegram_notifier.rb` — low-level Telegram bot wrapper.
- `lib/tasks/*.rake` — rake tasks: trading daemon, options calibration, AI technical analysis, SMC diagnostics, Redis/WS diagnostics, backtests.

### 2.13 `dashboard/`

Next.js dashboard that consumes API endpoints (positions, PnL, indices). Runs as a separate process via `Procfile.dev`.

### 2.14 `docs/`

Architecture diagrams and narrative docs:
- `docs/architecture/` — system overview, component map, execution flow, WebSocket feed.
- `docs/trading/` — trading pipeline, entry/exit rules, signal engine, risk management, safety mechanisms.
- `docs/services/` — service catalog, live services, signal services, risk services, order services.
- `docs/development/` — deployment, testing, testing profiles.
- `docs/integrations/` — DhanHQ API integration.
- `docs/market-data/` — market data flow.

---

## 3. Modes and Configuration

- **Paper vs Live**: Effective `paper_trading.enabled` from `AlgoConfig.fetch`: `config/algo.yml` → DB `algo_config_overrides` → `config/signal_tier_presets.yml` (tier from `SIGNAL_TIER` or `signals.signal_tier`) → **`LIVE_TRADING` env** forces paper when unset/false. Live broker submission still needs `dhanhq.enable_orders: true` and `PLACE_ORDER=true`. Gateway selected at boot; restart after changing `LIVE_TRADING`.
- **Signal tiers**: `exploratory` / `standard` / `selective` — YAML preset overlay only; not a second gateway switch.
- **All percentage config values use DECIMAL format** (0.12 = 12%, not 12.0).
- **Typed Settings**: `AlgoSetting` + `Setting` model + `config/algo.yml` drive feature flags, ADX thresholds, risk limits, time restrictions. `AlgoConfig.fetch` has a 30s cache with the merge order above.

---

## 4. Entry Guard Pipeline (20 Guards)

Run by `Entries::EntryGuardPipeline#run`. First block wins. Current order:

| # | Guard | Notes |
|---|-------|-------|
| 1 | `DrawdownGuard` | Portfolio drawdown check |
| 2 | `EntryPolicyGuard` | Policy enforcement |
| 3 | `CircuitBreakerGuard` | Redis-backed kill switch |
| 4 | `MiddayQualityGuard` | Bypassed if ADX >= 28 (`trending_adx_bypass`) |
| 5 | `EdgeFailureGuard` | Index-specific edge pause |
| 6 | `LossStreakGuard` | Consecutive losses threshold |
| 7 | `DailyLimitsGuard` | Daily trade/loss/profit limits |
| 8 | `MaxConcurrentGuard` | Concurrent position cap |
| 9 | `InstrumentLookupGuard` | Sets context[:instrument] |
| 10 | `LtpResolutionGuard` | Sets context[:ltp] |
| 11 | `ExpiryWeekPowerTrendGuard` | Enriches context[:expiry_power_trend]; does NOT block |
| 12 | `TimeRegimeGuard` | Bypasses S3 block when expiry_power_trend = true |
| 13 | `BankniftyLastWeekGuard` | BANKNIFTY only in last week of month |
| 14 | `WeeklyExpiryGuard` | Weekly contract requirement |
| 15 | `BosStructureGuard` | BOS requirement |
| 16 | `ExposureGuard` | Same-side position cap |
| 17 | `CooldownGuard` | Per-symbol cooldown |
| 18 | `SizingGuard` | Capital sizing |
| 19 | `RiskPolicyGuard` | Risk policy |
| 20 | `SmcNavigatorGuard` | SMC alignment |

---

## 5. Risk, Exits, and Circuit Breaker

- **Risk Rules** (`app/services/risk/rules/*`): Individual exit and risk conditions (premium momentum failure, time stop, R:R booking, structure invalidation, percentage PnL, etc.).
- **Risk::CircuitBreaker** — Redis-backed toggle: checked in `Entries::EntryGuard` and `RiskManagerService`. API surface in `Api::CircuitBreakerController`.
- **Unified Exit Path**: All exits go through `app/services/live/exit_engine.rb` — single place to audit exit decisions.
- **Exit Paths Logged**: `early_trend_failure`, `stop_loss`, `take_profit`, `trailing_stop`, `time_based`, `premium_r_stop`, `profit_floor_lock`, `profit_floor_time_kill`, `structure_invalidation`, `premium_momentum_failure`, `rr_profit_booking`, `percentage_pnl_exit`, `time_stop`, `stall_detection`.

---

## 6. AI Integration

- **Provider**: Ollama (local LLM) via `ollama-client` gem (`~> 1.1`). **OpenAI/ruby-openai gems have been removed.**
- **Client**: `lib/services/ai/ollama_client.rb` — wraps `Ollama::Client`; provides `chat`, `generate`, `chat_stream`.
- **Model selection**: If `OLLAMA_MODEL` env var set and available, uses it. Otherwise auto-selects from available models (prefers llama3.1:8b).
- **ENV**: `OLLAMA_MODEL` (default: llama3.2:3b), `OLLAMA_BASE_URL` / `OLLAMA_HOST_URL` (default: http://localhost:11434), `OLLAMA_TIMEOUT` (default: 120s).
- **Agent**: `lib/services/ai/technical_analysis_agent.rb` runs multi-turn LLM analysis for NIFTY and SENSEX every 15 minutes via `AiTechnicalAnalysisJob`.

---

## 7. Testing and Code Health

- **RSpec** (`spec/`): Model specs, service specs, integration/smoke specs. Uses FactoryBot and VCR.
- **Static analysis**: `rubocop` + Rails/RSpec/Faker cops; `brakeman` for security.
- **Code health**: `rubycritic` for complexity/smell analysis; `debride` for dead-method candidates.

---

## 8. Entry Points and Commands

```bash
./bin/dev                                                              # web + trading + jobs + dashboard
ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon           # trading daemon standalone
bin/jobs                                                               # Solid Queue worker standalone
bundle exec rspec                                                       # test suite
bundle exec rubocop                                                     # style/lint
bin/brakeman --no-pager                                                 # security scan
rails solid_queue:load_recurring                                        # load recurring job schedule
```
