# Algo Scalper API

A production-grade autonomous intraday options scalping system for Indian index markets (NIFTY, BANKNIFTY, SENSEX), built with Ruby on Rails 8. Self-contained pipeline: signal generation → options analysis → capital allocation → order execution → position management.

## System Overview

Algo Scalper API automates the entire trade lifecycle — from signal identification using technical analysis (Supertrend, ADX, SMC) through dynamic risk-managed exits. It runs as a **process-isolated execution engine**: the trading daemon operates separately from the web/dashboard processes to ensure low-latency tick processing and order execution.

### Key Capabilities

- **Multi-Strategy Signal Engine** — Supertrend + ADX with multi-timeframe confirmation, market regime detection, and dynamic validation modes (balanced/conservative)
- **Smart Money Concepts (SMC)** — Order block detection, FVG analysis, break-of-structure entries, institutional flow scoring
- **Real-time WebSocket Hub** — DhanHQ tick ingestion with write-through Redis caching, automatic reconnection, and per-position subscription management
- **Institutional Risk Management** — 15 exit rule engines: stop-loss, take-profit, trailing stops (tiered/direct/gamma-aware), peak drawdown, time-based, early trend failure, premium momentum failure, structure invalidation
- **Options Chain Intelligence** — ATM±1 strike selection with liquidity scoring, gamma ramp detection, expected move validation, per-index rules (NIFTY/BANKNIFTY/SENSEX)
- **Paper & Live Trading** — Seamless toggle; both modes use real DhanHQ WebSocket data. Paper simulates fills; live submits to exchange via DhanHQ API
- **Circuit Breaker** — Redis-backed singleton with API control (`GET/POST/DELETE /api/circuit_breaker/trip`); EntryGuard checks before every entry, RiskManager force-closes all positions when tripped
- **AI Technical Analysis** — Optional OpenAI integration for multi-timeframe analysis and SMC pattern enrichment
- **Telegram Notifications** — Trade alerts, PnL milestones, daily stats, SMC signals

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Ruby 3.3.4 |
| Framework | Rails 8.0.2 (API-only mode) |
| Database | PostgreSQL |
| Cache/State | Redis (tick cache, PnL cache, position state) |
| Job Queue | Solid Queue (not Sidekiq) |
| WebSocket Broadcast | Solid Cable (ActionCable backend) |
| Broker | DhanHQ v2 via `dhanhq` gem |
| AI | OpenAI (optional) |
| Notifications | Telegram Bot |
| Frontend | Next.js dashboard (separate process) |
| Deployment | Kamal + Docker |

## Quick Start

### Prerequisites

- Ruby 3.3.4, PostgreSQL 14+, Redis
- DhanHQ account with API credentials
- Node.js (for dashboard)

### Setup

```bash
bundle install
rails db:setup
rails db:migrate
rails solid_queue:load_recurring    # populate recurring job schedule
```

### Run

```bash
./bin/dev    # starts all 4 processes via foreman
```

This launches (via `Procfile.dev`):

| Process | Command | Purpose |
|---------|---------|---------|
| `web` | `bin/rails server -p 3001` | Rails API server |
| `trading` | `ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon` | Trading brain (all live services) |
| `jobs` | `bin/jobs` | Solid Queue worker (SMC scanner, AI analysis, instrument sync) |
| `dashboard` | `cd dashboard && npm run dev` | Next.js frontend |

### Other Commands

```bash
bundle exec rspec                          # run full test suite
bundle exec rspec spec/path/file_spec.rb   # run single spec
bundle exec rubocop                        # lint check
bin/brakeman --no-pager                    # security scan
bin/jobs                                   # start Solid Queue worker standalone
```

## Architecture

### Process Model

```
┌──────────────────────────────────────────────────────────────────┐
│ bin/dev (foreman)                                                │
├──────────────┬──────────────┬──────────────┬─────────────────────┤
│ web          │ trading      │ jobs         │ dashboard           │
│ Rails API    │ Daemon       │ Solid Queue  │ Next.js             │
│ port 3001    │ 11 services  │ recurring    │ frontend            │
│              │ in threads   │ tasks        │                     │
└──────┬───────┴──────┬───────┴──────┬───────┴─────────────────────┘
       │              │              │
       └──────┬───────┴──────┬───────┘
              │              │
         PostgreSQL       Redis
```

The **web** and **trading** processes share PostgreSQL and Redis but do NOT share in-process objects. The trading daemon runs all services as Ruby threads managed by `TradingSystem::Supervisor`.

### Trading Daemon Services

Started by `TradingSystem::Supervisor` (registered in `lib/trading_system/bootstrap.rb`):

| # | Service | Thread | Cadence |
|---|---------|--------|---------|
| 1 | `Live::MarketFeedHubService` | WebSocket event loop | Event-driven |
| 2 | `Signal::Scheduler` | `signal-scheduler` | 30s per cycle |
| 3 | `Live::RiskManagerService` | risk monitor | 5s enforcement loop + per-tick EventBus |
| 4 | `TradingSystem::PositionHeartbeat` | `position-heartbeat` | 10s |
| 5 | `TradingSystem::OrderRouter` | (stateless) | On-demand |
| 6 | `Live::PaperPnlRefresher` | `paper-pnl-refresher` | 1s (paper mode) |
| 7 | `Live::ExitEngine` | (called directly) | On-demand |
| 8 | `Positions::ActiveCacheService` | (called directly) | On-demand |
| 9 | `Live::ReconciliationService` | reconciliation | 30s |
| 10 | `Live::StatsNotifierService` | `stats-notifier` | At market close |
| 11 | `Smc::Scanner` | `smc-scanner` | 5 min |

### Recurring Jobs (Solid Queue)

Configured in `config/recurring.yml`:

| Job | Cadence | Purpose |
|-----|---------|---------|
| `InstrumentsImportJob` | Daily at 8:45 AM | Sync DhanHQ instrument master CSV |
| `SmcScannerJob` | Every 15 min (market hours) | SMC + AVRZ pattern detection |
| `AiTechnicalAnalysisJob` (NIFTY) | Every 15 min (market hours) | AI-powered analysis |
| `AiTechnicalAnalysisJob` (SENSEX) | Every 15 min (market hours) | AI-powered analysis |

### Service Directory

```
app/services/
  core/event_bus.rb                    # pub/sub (debug subscriber only; active comms use direct calls)
  live/                                # real-time trading brain
    market_feed_hub.rb                 # WebSocket tick distribution (Singleton)
    risk_manager_service.rb            # PnL guard, daily limits, kill switch
    exit_engine.rb                     # single source of truth for all exits
    trailing_engine.rb                 # trailing stop management (tiered/direct/gamma-aware)
    unified_exit_checker.rb            # evaluates all exit conditions in priority order
    pnl_updater_service.rb             # 250ms flush, PnL computation, EventBus publish
    reconciliation_service.rb          # broker/DB state sync every 30s
    order_update_handler.rb            # WebSocket order fill/cancel handler
    order_update_hub.rb                # DhanHQ order update WebSocket
    position_index.rb                  # in-memory security_id → tracker lookup
    redis_pnl_cache.rb                 # Redis PnL snapshot store
    redis_tick_cache.rb                # Redis tick persistence
    tick_cache.rb                      # write-through memory + Redis tick store
    tick_query.rb                      # authoritative LTP read boundary
  signal/                              # signal generation
    engine.rb                          # Supertrend + ADX + regime detection + validation
    scheduler.rb                       # 30s signal polling loop
  entries/                             # entry pipeline
    entry_guard.rb                     # orchestrates entry from signal to order
    entry_guard_pipeline.rb            # 10-guard chain (circuit breaker → cooldown)
    bos_entry_engine.rb                # Break-of-Structure entry state machine
    guards/                            # individual entry guards
  capital/                             # position sizing
    allocator.rb                       # rupee-based and percentage-based sizing
    dynamic_risk_allocator.rb          # trend-score-based dynamic risk
  orders/                              # order execution
    gateway_factory.rb                 # paper/live gateway selection
    gateway_live.rb                    # real DhanHQ execution with retry
    gateway_paper.rb                   # simulated fills
    placer.rb                          # DhanHQ API calls, idempotency, PLACE_ORDER live-order gate
    bracket_placer.rb                  # SL/TP bracket placement
  options/                             # options analysis
    chain_analyzer.rb                  # strike selection with qualification scoring
    derivative_chain_analyzer.rb       # expiry resolution
    gamma_ramp_detector.rb             # gamma pressure detection
    index_rules/                       # per-index strike rules (nifty, banknifty, sensex)
  risk/                                # risk management
    circuit_breaker.rb                 # Redis-backed emergency halt
    rules/                             # 15 exit rule engines
  smc/                                 # Smart Money Concepts
    scanner.rb                         # SMC pattern detection loop
    bias_engine.rb                     # SMC directional bias
    detectors/                         # FVG, order blocks, liquidity, structure
  indicators/                          # technical indicators
    supertrend.rb                      # adaptive Supertrend
    adx_indicator.rb                   # ADX strength
  dhan/                                # DhanHQ integration
    token_manager.rb                   # 3-tier token provisioning (authority → TOTP → static)
  adapters/                            # broker adapters
    option_chain/dhan_adapter.rb       # live option chain fetch
  trading/                             # trading utilities
    permission_resolver.rb             # SMC + AVRZ permission gating
    capital_allocator.rb               # lot calculation
  positions/                           # position state management
    active_cache.rb                    # in-memory + Redis position cache
    trailing_config.rb                 # trailing stop configuration
```

### Trading Flow

```
Signal::Scheduler (30s loop)
  │
  ├─ Signal::Engine.run_for(index_cfg)
  │   ├─ Fetch candle series + compute Supertrend/ADX
  │   ├─ Market regime detection (TRENDING/RANGING/CHOPPY)
  │   ├─ Dynamic validation mode (balanced → conservative in choppy)
  │   ├─ Multi-timeframe confirmation (optional)
  │   ├─ Comprehensive validation (IV proxy, theta risk, ADX strength, trend confirm)
  │   ├─ Entries::EntryFilterEngine (structure, liquidity, volatility)
  │   ├─ Trading::PermissionResolver (SMC + AVRZ gating)
  │   ├─ SMC decision alignment check
  │   └─ Signal::MomentumValidator (momentum scoring 0-3)
  │
  ├─ Options::ChainAnalyzer.pick_strikes_with_qualification
  │   ├─ Fetch nearest expiry from instrument
  │   ├─ Fetch option chain via DhanAdapter
  │   ├─ Filter by DB Derivative records
  │   ├─ Score strikes (liquidity, OI, spread, IV)
  │   └─ Expected move validation
  │
  └─ Entries::EntryGuard.try_enter
      ├─ EntryGuardPipeline (10 guards in sequence):
      │   CircuitBreaker → BosContract → TimeRegime → BankniftyLastWeek
      │   → EdgeFailure → DailyLimits → InstrumentLookup → Exposure
      │   → Cooldown → LtpResolution
      ├─ Capital::Allocator.qty_for (risk-based sizing)
      ├─ Orders.config.gateway.place_market (paper or live)
      └─ PositionTracker.create + subscribe to WebSocket feed
```

### Position Management Flow

```
DhanHQ WebSocket tick
  → MarketFeedHub.handle_tick
  → TickCache.put (memory + Redis write-through)
  → PositionIndex.trackers_for(security_id)
  → PnlUpdaterService.cache_intermediate_pnl (enqueue)
  → [every 250ms flush]
    → Batch DB load, compute PnL, store to RedisPnlCache
    → EventBus.publish(:ltp)
      → RiskManagerService.handle_pnl_event (high-frequency path)
        → UnifiedExitChecker.check_exit_conditions
          → SL / TP / Trailing / Time checks
          → ExitEngine.execute_exit if triggered
  → [every 5s enforcement loop]
    → RiskManagerService.run_enforcement_cycle
      → Premium R-stop, dynamic trailing, profit floor, structure invalidation
      → Premium momentum failure, R:R booking, percentage PnL, time stop
```

## Paper vs Live Trading

Controlled by `config/algo.yml`:

```yaml
paper_trading:
  enabled: true    # true = paper (simulated fills), false = live (real DhanHQ orders)
  balance: 100000  # simulated starting capital

dhanhq:
  enable_orders: false  # legacy broker toggle (keep false unless explicitly needed)

# Runtime live-order gate:
# PLACE_ORDER=true (environment variable)
```

Both modes use **real DhanHQ WebSocket data** for market ticks. The difference is only in order execution:

| Aspect | Paper Mode | Live Mode |
|--------|-----------|-----------|
| Market data | Real WebSocket ticks | Real WebSocket ticks |
| Option chain | Real DhanHQ API | Real DhanHQ API |
| Order execution | Simulated fills (`GatewayPaper`) | Real DhanHQ API (`GatewayLive`) |
| PnL tracking | Real LTP-based | Real LTP-based |
| Order updates | Synthetic | DhanHQ WebSocket |
| Wallet | Simulated balance | Real funds API |

### Environment Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `DHAN_CLIENT_ID` | Yes | DhanHQ client ID |
| `DHAN_ACCESS_TOKEN` | Yes | DhanHQ access token (static fallback) |
| `DHAN_PIN` | Recommended | For TOTP auto-refresh |
| `DHAN_TOTP_SECRET` | Recommended | For TOTP auto-refresh |
| `ENABLE_TRADING_SERVICES` | Auto (Procfile) | Must be `"true"` for daemon |
| `PLACE_ORDER` | Live only | Must be `"true"` to allow live broker order placement |
| `DHANHQ_WS_ENABLED` | Optional | Enable WebSocket (defaults based on env) |
| `DISABLE_TRADING_SERVICES` | Optional | Set to `"1"` to disable |
| `BACKTEST_MODE` | Optional | Set to `"1"` for backtesting |

### Live Trading Checklist

Before switching `paper_trading.enabled: false`:

- [ ] DhanHQ credentials set (`DHAN_CLIENT_ID`, `DHAN_ACCESS_TOKEN`)
- [ ] TOTP credentials set (`DHAN_PIN`, `DHAN_TOTP_SECRET`) for token auto-refresh
- [ ] `PLACE_ORDER=true` in environment for intentional live broker order placement
- [ ] `InstrumentsImporter` has run recently (`rails runner 'puts Derivative.count'`)
- [ ] Database migrated (`rails db:migrate:status`)
- [ ] Redis running (`redis-cli ping`)
- [ ] Solid Queue recurring tasks loaded (`rails solid_queue:load_recurring`)

## API Endpoints

```
GET  /api/health                      # System health status
GET  /api/dashboard                   # Dashboard data (positions, PnL, indices)
GET  /api/positions                   # Active positions with live PnL
GET  /api/analysis/:index_key         # AI analysis for index
GET  /api/settings                    # Current algo settings
PATCH /api/settings/bulk              # Bulk update settings
GET  /api/circuit_breaker             # Circuit breaker status
POST /api/circuit_breaker/trip        # Trip circuit breaker (emergency halt)
DELETE /api/circuit_breaker/trip      # Reset circuit breaker
GET  /smc/decision                    # SMC analytics decision
POST /cable                           # ActionCable WebSocket (positions, dashboard channels)
```

## Database Schema

Key tables:

| Table | Purpose |
|-------|---------|
| `instruments` | Master instrument data from DhanHQ CSV |
| `derivatives` | Options contracts (strike, expiry, option_type, lot_size) |
| `position_trackers` | Live position tracking (entry, exit, PnL, trade state) |
| `candles` | OHLC candle data by timeframe |
| `trading_signals` | Generated trading signals with metadata |
| `trade_telemetry` | Trade execution telemetry (entry/exit stats) |
| `trade_analytics` | MAE/MFE analysis, volatility metrics |
| `dhan_access_tokens` | DhanHQ API token storage |
| `settings` | Runtime config overrides (DB overrides algo.yml with 30s cache) |

## Configuration

All trading parameters live in `config/algo.yml` (838 lines). Key sections:

| Section | Purpose |
|---------|---------|
| `paper_trading` | Paper/live mode toggle and simulated balance |
| `dhanhq` | Broker settings (`enable_orders` safety gate) |
| `indices` | Per-index config: segment, SID, capital allocation, ADX thresholds, trailing tiers |
| `trade_limits` | Global daily limits |
| `risk` | Circuit breaker, drawdown, time stops, SL/TP percentages (DECIMAL format) |
| `position_sizing` | Rupee-based or percentage-based capital allocation |
| `signals` | Signal generation: ADX thresholds, timeframes, validation modes |
| `chain_analyzer` | Options chain scoring parameters |
| `broker_fees` | Brokerage and transaction charges |
| `telegram` | Telegram bot configuration and PnL milestones |
| `ai` | OpenAI API settings |

Runtime config changes: `AlgoConfig.fetch` has a 30-second in-process cache. DB overrides via the `settings` table are deep-merged on top of YAML values, enabling hot config changes without restart.

## Critical Rules

- **DhanHQ only** — no other broker code
- Live services communicate via **direct method calls** — `event_bus.rb` has only a debug subscriber; it is infrastructure for future use
- `exit_engine.rb` is the **single source of truth** for exit placement — RiskManager and TrailingEngine detect conditions and call it directly
- `TickQuery` returns `nil` on cache miss — callers must treat nil as stale data, not zero
- Position sizing must go through `capital/` — never inline the math
- **Solid Queue** is the job runner (not Sidekiq) — use `ApplicationJob`
- Redis tick cache is **write-through** — if Redis is down, fall back gracefully
- **Never write to DB** from WebSocket tick handlers — enqueue a job or use the PnlUpdater flush
- All percentage config values use **DECIMAL format** (0.12 = 12%, not 12.0)
- WebSocket event handlers must be **idempotent** — the feed can reconnect and replay

## License

This project is proprietary and confidential.
