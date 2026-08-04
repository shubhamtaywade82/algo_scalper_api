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
- Optional: OpenAI for AI technical analysis
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
bin/brakeman --no-pager                # security scan
./bin/dev                              # start all processes (web + trading + jobs + dashboard)
bin/jobs                               # start Solid Queue worker standalone
ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon  # trading daemon standalone
```

## Process Model

`./bin/dev` starts 4 processes via `Procfile.dev`:

| Process | Command | Purpose |
|---------|---------|---------|
| `web` | `bin/rails server -p 3001` | Rails API server |
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

## Paper vs Live Mode

Controlled by `config/algo.yml`:
- `paper_trading.enabled: true` → `Orders::GatewayPaper` (simulated fills, real data)
- `paper_trading.enabled: false` → `Orders::GatewayLive` (real DhanHQ execution)
- `dhanhq.enable_orders: true` must also be set for live orders (safety gate — without it, orders log as "dry-run")

Both modes use real DhanHQ WebSocket data and real option chain API. Gateway is selected once at boot (`config/initializers/orders_gateway.rb`); switching requires restart.

## Config Format

All percentage values in `config/algo.yml` use **DECIMAL format**: `0.12` means 12%, `0.05` means 5%. Never use whole-number percentages.

`AlgoConfig.fetch` has a 30-second in-process cache with DB override support via the `settings` table (deep-merged on top of YAML).

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
