# algo_scalper_api

Rails 8 API backend for **fully autonomous** intraday options scalping on Indian index markets (NIFTY, BANKNIFTY, SENSEX). Self-contained pipeline: signal generation → options analysis → capital allocation → order execution → position management.

## Stack

- Ruby 3.3.4, Rails 8.0.2, API-only mode
- PostgreSQL (persistence, Solid Queue backend)
- Redis (tick cache, PnL cache, position state, circuit breaker)
- Solid Queue (background job processing — not Sidekiq)
- Solid Cable (ActionCable WebSocket backend)
- Solid Cache (Rails.cache backend)
- DhanHQ v2 via `dhanhq` gem (broker API + WebSocket)
- Optional: Ollama (local LLM via `ollama-client`) for AI technical analysis
- Optional: Telegram Bot for notifications

## Commands

```bash
bundle install
rails db:setup
rails db:migrate
rails solid_queue:load_recurring       # populate recurring job schedule
bundle exec rspec
bundle exec rspec spec/path/file_spec.rb
bundle exec rubocop
bundle exec rake rswag:specs:swaggerize # regenerate swagger/v1/swagger.yaml from RSwag specs
bin/brakeman --no-pager                # security scan
./bin/dev                              # start all processes (web + trading + jobs + dashboard)
bin/jobs                               # start Solid Queue worker standalone
ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon  # trading daemon standalone
```

## Process Model

`./bin/dev` starts 4 processes via `Procfile.dev`:

| Process | Command | Purpose |
|---------|---------|---------|
| `web` | `bin/rails server -p 3011` | Rails API server |
| `trading` | `ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon` | Trading brain (11 services in threads) |
| `jobs` | `bin/jobs` | Solid Queue worker (recurring tasks) |
| `dashboard` | `cd dashboard && npm run dev` | Next.js frontend |

Web and trading are separate OS processes sharing PostgreSQL and Redis — no shared in-process objects.

## Architecture

```
app/services/
  core/
    event_bus.rb                   # pub/sub (debug subscriber only; direct calls are the active layer)
  live/                            # real-time runtime (the trading brain)
    market_feed_hub.rb             # WebSocket tick distribution (Singleton)
    pnl_updater_service.rb         # 250ms PnL flush, EventBus publish
    risk_manager_service.rb        # PnL guard, daily limits, kill switch (5s loop + per-tick)
    exit_engine.rb                 # unified exit logic (single source of truth)
    trailing_engine.rb             # trailing stop management (tiered/direct/gamma-aware)
    unified_exit_checker.rb        # evaluates all exit conditions in priority order
    reconciliation_service.rb      # broker/DB state sync every 30s
    order_update_handler.rb        # WebSocket order fill/cancel handler
    order_update_hub.rb            # DhanHQ order update WebSocket
    position_index.rb              # in-memory security_id → tracker lookup
    redis_pnl_cache.rb             # Redis PnL snapshot store (30s DB sync throttle)
    tick_cache.rb                  # write-through memory + Redis tick store
    tick_query.rb                  # authoritative LTP read boundary
    gateway.rb                     # deprecated — delegates to Orders::GatewayLive
  signal/
    engine.rb                      # Supertrend + ADX + regime detection + validation
    scheduler.rb                   # 30s signal polling loop
  entries/
    entry_guard.rb                 # orchestrates entry from signal to order
    entry_guard_pipeline.rb        # 10-guard chain
    bos_entry_engine.rb            # Break-of-Structure entry state machine
    guards/                        # circuit_breaker, cooldown, daily_limits, exposure, etc.
  capital/
    allocator.rb                   # rupee-based and percentage-based sizing
  orders/
    gateway_factory.rb             # paper/live selection at boot
    gateway_live.rb                # real DhanHQ execution with retry + token auto-heal
    gateway_paper.rb               # simulated fills
    placer.rb                      # DhanHQ API, idempotency, dry-run gate
  options/
    chain_analyzer.rb              # strike selection with qualification scoring
    index_rules/                   # per-index rules (nifty, banknifty, sensex)
  risk/
    circuit_breaker.rb             # Redis-backed emergency halt
    rules/                         # 15 exit rule engines
  smc/                             # Smart Money Concepts detection
  indicators/                      # Supertrend, ADX, RSI, MACD
  dhan/
    token_manager.rb               # 3-tier token: authority server → TOTP → static ENV
  adapters/
    option_chain/dhan_adapter.rb   # live option chain fetch (always wired, even in paper mode)
  research/                        # offline research pipeline (see below) — never called from the live trading path

app/jobs/
  instruments_import_job.rb        # daily DhanHQ CSV sync
  smc_scanner_job.rb               # SMC + AVRZ pattern detection
  ai_technical_analysis_job.rb     # AI analysis (NIFTY, SENSEX)
  analysis_job.rb                  # on-demand analysis (async adapter, not Solid Queue)

lib/trading_system/
  daemon.rb                        # trading process lifecycle
  bootstrap.rb                     # service wiring (builds supervisor with 11 services)
  supervisor.rb                    # start_all / stop_all coordinator
```

## Trading Daemon Services

Registered in `lib/trading_system/bootstrap.rb`, started by `supervisor.start_all`:

| # | Key | Service | Cadence |
|---|-----|---------|---------|
| 1 | `:market_feed` | `Live::MarketFeedHubService` | WebSocket event-driven |
| 2 | `:signal_scheduler` | `Signal::Scheduler` | 30s per cycle |
| 3 | `:risk_manager` | `Live::RiskManagerService` | 5s loop + per-tick EventBus |
| 4 | `:position_heartbeat` | `TradingSystem::PositionHeartbeat` | 10s |
| 5 | `:order_router` | `TradingSystem::OrderRouter` | On-demand |
| 6 | `:paper_pnl_refresher` | `Live::PaperPnlRefresher` | 1s (paper mode) |
| 7 | `:exit_manager` | `Live::ExitEngine` | On-demand |
| 8 | `:active_cache` | `Positions::ActiveCacheService` | On-demand |
| 9 | `:reconciliation` | `Live::ReconciliationService` | 30s |
| 10 | `:stats_notifier` | `Live::StatsNotifierService` | At market close |
| 11 | `:smc_scanner` | `Smc::Scanner` | 5 min |

## Recurring Jobs (Solid Queue — `config/recurring.yml`)

| Job | Cadence | Purpose |
|-----|---------|---------|
| `InstrumentsImportJob` | Daily 8:45 AM | DhanHQ instrument master CSV sync |
| `SmcScannerJob` | Every 15 min (market hours) | SMC + AVRZ pattern detection |
| `AiTechnicalAnalysisJob` (NIFTY) | Every 15 min (market hours) | AI-powered analysis |
| `AiTechnicalAnalysisJob` (SENSEX) | Every 15 min (market hours) | AI-powered analysis |
| `Research::DailyLifecycleJob` (NIFTY/BANKNIFTY/SENSEX) | Daily 9:00 AM | Auto-runs the prior session's premium-lifecycle board so `research_premium_lifecycles` accumulates without manual dashboard clicks — resolves spot from persisted candles, skips silently on non-trading days or missing candle data |

Run `rails solid_queue:load_recurring` to populate the schedule after config changes.

## Trading Flow

```
Signal::Scheduler (30s)
  → Signal::Engine.run_for(index_cfg)
    → Supertrend + ADX + market regime detection
    → Comprehensive validation (IV proxy, theta, ADX strength, trend confirm)
    → EntryFilterEngine + PermissionResolver + SMC alignment
  → Options::ChainAnalyzer.pick_strikes_with_qualification
    → ATM±1 strike selection, liquidity scoring, expected move validation
  → Entries::EntryGuard.try_enter
    → 10-guard pipeline (circuit breaker → cooldown → exposure → ...)
    → Capital::Allocator.qty_for (risk-based sizing)
    → Orders.config.gateway.place_market
    → PositionTracker.create + subscribe to WebSocket feed

Position monitoring:
  DhanHQ tick → MarketFeedHub → TickCache (memory + Redis)
    → PnlUpdaterService (250ms flush) → RedisPnlCache → EventBus(:ltp)
      → RiskManagerService → UnifiedExitChecker
        → ExitEngine.execute_exit (if triggered)

Exit enforcement (5s loop):
  RiskManagerService.run_enforcement_cycle
    → Premium R-stop, trailing (tiered/direct/gamma), profit floor
    → Structure invalidation, premium momentum, R:R booking, time stop
```

## Research Pipeline (`Research::` — offline, decoupled from live trading)

A layered pipeline over Dhan's `ExpiredOptionsData` ("rollingoption") and the persisted `candles` table, for studying option premium behavior — never wired into the live entry/exit path.

- `research_raw_fetches` — raw API response archive (audit/replay)
- `research_option_bars` — normalized minute/5-min option OHLCV, keyed by contract identity (symbol/expiry_flag/option_type/strike_label/interval/ts)
- `research_signals` — signal-time snapshot (spot/direction/timestamp), buildable manually or from a `TradingSignal`
- `research_option_candidates` — ATM+/-N candidate strikes per signal, scored (entry/exit/MFE/MAE/return) by `Research::TradeScorer`
- `research_premium_lifecycles` — full premium path (entry → peak → decay → end) per strike across a session, with a best-effort underlying context snapshot (ATR/ADX/RSI/MACD/VWAP, plus `Research::ContextClassifier`'s regime labels) at entry and peak via `Research::UnderlyingContextSnapshot`

`Research::ContextClassifier` buckets the underlying into regime labels (market structure, trend strength, volatility regime, momentum, volume regime, time-of-day, VWAP relation, liquidity sweep, opening-range breakout, gap) — the goal being "what market context produces high-expectancy premium expansion", not single-indicator thresholds. Reuses the existing `Smc::Detectors::Structure`/`Liquidity` (pure, side-effect-free) for structure/BOS/CHoCH/sweep detection rather than re-deriving swing points. Thresholds are a documented first cut (see the class), not calibrated against historical data yet.

`Research::ExpectancyReport` is the Context → Expectancy Map itself: groups persisted `research_premium_lifecycles` rows by a caller-chosen subset of their entry (or peak) regime labels and computes sample size / avg peak return / win rate / avg time-to-peak / avg drawdown per bucket, ranked best-to-worst — this is what tells you which contexts are worth trading and which aren't, rather than a single "buy when X" rule.

Entry points: `Research::Pipeline.run` (single signal → ranked candidates), `Research::LifecycleRunner.run` (full ATM+/-N board → ranked lifecycles), `Research::ExpectancyReport.call` (persisted lifecycles → ranked context buckets). Rake tasks: `research:run_signal`, `research:run_board_lifecycle` (see `lib/tasks/research.rake`). Dashboard: `/research` (Signal Pipeline, Premium Lifecycle Board, and Context → Expectancy panels), backed by `/api/research/*`.

## Paper vs Live Mode

**Effective paper vs live** is determined after `AlgoConfig.fetch` merges:

1. `config/algo.yml`
2. DB `algo_config_overrides` (`settings` table)
3. `config/signal_tier_presets.yml` for tier `exploratory` | `standard` | `selective` (from `SIGNAL_TIER` env or `signals.signal_tier`)
4. **`LIVE_TRADING` env** — when unset/false, `paper_trading.enabled` is **forced true**; when true, forced false (overrides YAML for gateway selection)

- `paper_trading.enabled: true` (effective) → `Orders::GatewayPaper` (simulated fills, real data)
- `paper_trading.enabled: false` (effective) → `Orders::GatewayLive` (real DhanHQ execution path)
- For actual broker submission on live: `dhanhq.enable_orders: true` **and** `PLACE_ORDER=true` (without these, live path still dry-runs in `Orders::Placer`)

Both modes use real DhanHQ WebSocket data and real option chain API. Gateway is selected once at boot (`config/initializers/orders_gateway.rb`); switching effective mode requires restart.

## Config Format

All percentage values in `config/algo.yml` use **DECIMAL format**: `0.12` means 12%, `0.05` means 5%. Never use whole-number percentages.

`AlgoConfig.fetch` has a 30-second in-process cache. Merge order: base YAML → DB overrides → signal tier preset → `LIVE_TRADING` paper override.

## Critical Rules

- **DhanHQ only** — no other broker code
- Live subsystems communicate via **direct method calls** — `event_bus.rb` exists but has only a debug subscriber; do not treat it as the active communication layer
- `Risk::CircuitBreaker` — singleton backed by Rails.cache; API at `GET/POST/DELETE /api/circuit_breaker/trip`; EntryGuard checks before every entry, RiskManager force-closes all positions when tripped
- WebSocket event handlers must be **idempotent** — the feed can reconnect and replay
- `exit_engine.rb` is the **single source of truth** for exit placement — RiskManager and TrailingEngine detect exit conditions and call it directly
- `TickQuery` returns `nil` on cache miss (silently) — callers that receive nil must treat it as stale data, not zero
- Position sizing must go through `capital/` — never inline the math elsewhere
- **Solid Queue** is the job runner (not Sidekiq) — use `ApplicationJob`, not `ApplicationWorker`
- Redis tick cache is **write-through** — if Redis is down, fall back gracefully, don't crash
- Never write to the DB from within WebSocket tick handlers — enqueue a job or use PnlUpdaterService flush
- `Live::Gateway` is **deprecated** — use `Orders::GatewayLive` directly
- Option chain adapter is always `DhanAdapter` (even in paper mode) — option chain reads are live
- Token refresh uses `Dhan::TokenManager` with 3-tier fallback: authority server → TOTP auto-refresh → static ENV

## Stable vs Alpha Layers (Change Policy)

You MUST treat execution infrastructure as **stable** and only iterate on the **alpha layer** by default.

- **LOCKED (infra, do not change unless Critical Scenario):**
  - DhanHQ integration and gateways: `app/services/dhan/`, `app/services/orders/gateway_live.rb`, `app/services/orders/gateway_paper.rb`, `app/services/orders/gateway_factory.rb`, `app/services/orders/placer.rb`, DhanHQ-specific adapters in `app/services/options/` or `lib/`.
  - WebSocket + market data + caching: `app/services/live/market_feed_hub.rb`, `app/services/live/order_update_hub.rb`, `app/services/live/order_update_handler.rb`, `app/services/live/redis_tick_cache.rb`, `app/services/live/tick_query.rb`, `app/services/market_data/market_cache.rb`, `app/services/live/pnl_updater_service.rb`, `app/services/live/redis_pnl_cache.rb`.
  - Position lifecycle: `app/services/positions/active_cache.rb`, `app/services/positions/serializer.rb`, all `app/services/positions/states/*`, and any position index/`PositionTracker`-style services.
  - Core order execution plumbing: `app/services/orders/commands/*`, `app/services/orders/executor.rb`, `app/services/orders/entry_manager.rb`, `app/services/orders/exit_engine.rb`, `app/services/orders/trailing_engine.rb`, `app/services/orders/mfe_exit_engine.rb`, `app/services/orders/gamma_trailing_engine.rb`, `app/services/orders/expiry_rule_engine.rb`, `app/services/live/unified_exit_checker.rb`.
  - Risk-manager plumbing: all `app/services/live/risk_manager_service*` files (runner, config, pnl cache, exit execution/enforcement).
  - Process wiring and orchestration: `lib/trading_system/`, `app/services/trading_session.rb`, `app/services/orchestration/strategy_runner.rb`, `app/jobs/*`, and API controllers/routes (except when adding new endpoints).
  - Instrument and chain plumbing: `app/models/instrument.rb`, `app/services/options/chain_analyzer.rb`, `app/services/options/derivative_chain_analyzer.rb`, `app/services/options/strike_selector.rb`, `app/services/options/strike_aggregator.rb`, `app/services/options/expiry_calendar.rb`, and other pure data/chain assembly services.

- **ALPHA LAYERS (safe to iterate):**
  - Entry strategy: `app/services/signal/*`, `app/services/indicators/*`, `app/services/market_state/*`, `app/services/smc/*`, `app/services/trading/trend_scorer.rb`, `app/services/trading/permission_resolver.rb`.
  - Entry orchestration and guards: `app/services/entries/entry_guard.rb`, `app/services/entries/entry_filter_engine.rb`, `app/services/entries/entry_guard_pipeline.rb`, all `app/services/entries/guards/*`.
  - Exit logic (conditions, not plumbing): `app/services/orders/analyzer.rb`, `app/services/orders/adjuster.rb`, `app/services/orders/adaptive_trailing.rb`, `app/services/orders/gamma_detector.rb`, `app/services/trading/trailing_engine.rb`.
  - Risk model: all `app/services/risk/*`, all `app/services/policies/*`, and `app/services/capital/allocator.rb`.
  - Option-chain decision logic: `app/services/options/flow_analyzer.rb`, all `app/services/options/strike_qualification/*`, `app/services/options/historical_calibration_engine.rb`.

### Critical Scenarios (when infra may be modified)

Only touch LOCKED layers when **one of these is explicitly in scope**:

1. **DhanHQ gem/API change**: the `dhanhq-client` gem or upstream DhanHQ API changes in a way that breaks compatibility or requires new fields/endpoints.
2. **Verified execution defect**: reproducible duplicate orders, missing exits, incorrect quantities, or misrouted orders, ideally reproducible in paper mode.
3. **Data integrity / state divergence**: tick cache serving stale/incorrect prices, positions not recovering correctly after restart, or broker vs DB position mismatch attributable to infra.
4. **Structural performance failure**: WebSocket/feed/caching cannot keep up with production load and directly threatens fills or risk management.
5. **Security/compliance**: issues related to broker integration, credentials handling, or sensitive data exposure.

When changing locked layers for a Critical Scenario:

- Prefer the smallest possible change that fixes the concrete issue.
- Preserve idempotency, order uniqueness, and linear position lifecycle.
- Keep PnL tuning (alpha work) in the ALPHA LAYERS only.
