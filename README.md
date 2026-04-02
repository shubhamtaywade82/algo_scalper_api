# Algo Scalper API

A production-grade autonomous intraday options scalping system for Indian index markets (NIFTY, BANKNIFTY, SENSEX), built with Ruby on Rails 8. Self-contained pipeline: signal generation → options analysis → capital allocation → order execution → position management.

## System Overview

Algo Scalper API automates the entire trade lifecycle — from signal identification using technical analysis (Supertrend, ADX, SMC) through dynamic risk-managed exits. It runs as a **process-isolated execution engine**: the trading daemon operates separately from the web/dashboard processes to ensure low-latency tick processing and order execution.

### Key Capabilities

- **Multi-Strategy Signal Engine** — Supertrend + ADX with multi-timeframe confirmation, market regime detection, and dynamic validation modes (balanced/conservative). Optional **market context** (`MarketContext::RegimeComposer`, chain signal extraction, `Trading::MarketPermissionGate`) is configurable in `config/algo.yml` (`market_context`); see `docs/trading/market_context_and_permission_gate.md`.
- **Smart Money Concepts (SMC)** — Order block detection, FVG analysis, break-of-structure entries, institutional flow scoring
- **Real-time WebSocket Hub** — DhanHQ tick ingestion with write-through Redis caching, automatic reconnection, and per-position subscription management
- **Institutional Risk Management** — Dual-path exit evaluation: per-tick `UnifiedExitChecker` (SL, TP, trailing, early trend failure, time-based) plus 5-second enforcement loop (premium R-stop, profit floor, structure invalidation, premium momentum failure, R:R booking, percentage PnL exit, time stop)
- **Options Chain Intelligence** — ATM±1 strike selection with liquidity scoring, gamma ramp detection, expected move validation, per-index rules (NIFTY/BANKNIFTY/SENSEX)
- **Expiry Week Power Trend** — ADX >= 40 + within 5 days of monthly expiry + 12:00-13:45 window → `ExpiryWeekPowerTrendGuard` enriches context to bypass chop-zone block
- **20-Guard Entry Pipeline** — Full guard chain from DrawdownGuard through SmcNavigatorGuard
- **Paper & Live Trading** — Seamless toggle; both modes use real DhanHQ WebSocket data. Paper simulates fills; live submits to exchange via DhanHQ API
- **Circuit Breaker** — Redis-backed singleton with API control (`GET/POST/DELETE /api/circuit_breaker/trip`); EntryGuard checks before every entry, RiskManager force-closes all positions when tripped
- **AI Technical Analysis** — Local Ollama LLM integration (`ollama-client` gem `~> 1.1`); auto-selects best available model
- **Telegram Notifications** — Trade alerts, PnL milestones, daily stats, SMC signals

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Ruby 3.3.4 |
| Framework | Rails 8.0.2 (API-only mode) |
| Database | PostgreSQL |
| Cache/State | Redis (tick cache, PnL cache, position state, circuit breaker) |
| Job Queue | Solid Queue (not Sidekiq) |
| WebSocket Broadcast | Solid Cable (ActionCable backend) |
| Broker | DhanHQ v2 via `dhanhq` gem |
| AI | Ollama via `ollama-client` gem (`~> 1.1`) — local LLM, no OpenAI |
| Notifications | Telegram Bot |
| Frontend | Next.js dashboard (separate process) |

## Quick Start

### Prerequisites

- Ruby 3.3.4, PostgreSQL 14+, Redis
- DhanHQ account with API credentials
- Node.js (for dashboard)
- Ollama running locally (optional, for AI analysis)

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
| `trading` | `ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon` | Trading brain (11 services in threads) |
| `jobs` | `bin/jobs` | Solid Queue worker (SMC scanner, AI analysis, instrument sync) |
| `dashboard` | `cd dashboard && npm run dev` | Next.js frontend |

### Other Commands

```bash
bundle exec rspec                          # run full test suite
bundle exec rspec spec/path/file_spec.rb   # run single spec
bundle exec rubocop                        # lint check
bin/brakeman --no-pager                    # security scan
bin/jobs                                   # start Solid Queue worker standalone
ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon  # trading daemon standalone
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

| # | Service | Cadence |
|---|---------|---------|
| 1 | `Live::MarketFeedHubService` | Event-driven (WebSocket) |
| 2 | `Signal::Scheduler` | 30s per cycle |
| 3 | `Live::RiskManagerService` | 5s enforcement loop + per-tick EventBus |
| 4 | `TradingSystem::PositionHeartbeat` | 10s |
| 5 | `TradingSystem::OrderRouter` | On-demand |
| 6 | `Live::PaperPnlRefresher` | 1s (paper mode only) |
| 7 | `Live::ExitEngine` | On-demand |
| 8 | `Positions::ActiveCacheService` | On-demand |
| 9 | `Live::ReconciliationService` | 30s |
| 10 | `Live::StatsNotifierService` | At market close |
| 11 | `Smc::Scanner` | 5 min |

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
    entry_guard_pipeline.rb            # 20-guard chain
    bos_entry_engine.rb                # Break-of-Structure entry state machine
    guards/                            # individual entry guards (20 total)
  capital/                             # position sizing
    allocator.rb                       # rupee-based and percentage-based sizing
    dynamic_risk_allocator.rb          # trend-score-based dynamic risk
  orders/                              # order execution
    gateway_factory.rb                 # paper/live gateway selection
    gateway_live.rb                    # real DhanHQ execution with retry
    gateway_paper.rb                   # simulated fills
    placer.rb                          # DhanHQ API calls, idempotency, PLACE_ORDER live-order gate
  options/                             # options analysis
    chain_analyzer.rb                  # strike selection with qualification scoring
    derivative_chain_analyzer.rb       # expiry resolution
    gamma_ramp_detector.rb             # gamma pressure detection
    index_rules/                       # per-index strike rules (nifty, banknifty, sensex)
  risk/                                # risk management
    circuit_breaker.rb                 # Redis-backed emergency halt
    rules/                             # exit rule engines
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

lib/services/ai/
  ollama_client.rb                     # Ollama::Client wrapper (chat, generate, stream)
  technical_analysis_agent.rb          # LLM-backed technical analysis agent
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
  │   └─ SMC decision alignment check
  │
  ├─ Options::ChainAnalyzer.pick_strikes_with_qualification
  │   ├─ Fetch nearest expiry from instrument
  │   ├─ Fetch option chain via DhanAdapter
  │   ├─ Score strikes (liquidity, OI, spread, IV)
  │   └─ Expected move validation
  │
  └─ Entries::EntryGuard.try_enter
      ├─ EntryGuardPipeline (20 guards in sequence)
      ├─ Capital::Allocator.qty_for (risk-based sizing)
      ├─ Orders.config.gateway.place_market (paper or live)
      └─ PositionTracker.create + subscribe to WebSocket feed
```

### Entry Guard Pipeline (20 guards, in order)

| # | Guard | Purpose |
|---|-------|---------|
| 1 | `DrawdownGuard` | Portfolio-level drawdown limit |
| 2 | `EntryPolicyGuard` | Entry policy enforcement |
| 3 | `CircuitBreakerGuard` | System-wide halt check |
| 4 | `MiddayQualityGuard` | Quality gate; bypassed if ADX >= 28 |
| 5 | `EdgeFailureGuard` | Pause when strategy has lost edge for index |
| 6 | `LossStreakGuard` | Block on consecutive loss streak |
| 7 | `DailyLimitsGuard` | Daily loss/profit/trade limits |
| 8 | `MaxConcurrentGuard` | Max simultaneous open positions |
| 9 | `InstrumentLookupGuard` | Resolves instrument; sets context[:instrument] |
| 10 | `LtpResolutionGuard` | Requires valid LTP; sets context[:ltp] |
| 11 | `ExpiryWeekPowerTrendGuard` | Enriches context[:expiry_power_trend] when pattern detected |
| 12 | `TimeRegimeGuard` | Time-of-day regime check; bypassed when expiry_power_trend = true |
| 13 | `BankniftyLastWeekGuard` | BANKNIFTY: only last week before monthly expiry |
| 14 | `WeeklyExpiryGuard` | Requires weekly contract |
| 15 | `BosStructureGuard` | Break-of-Structure requirement |
| 16 | `ExposureGuard` | Max same-side positions |
| 17 | `CooldownGuard` | Re-entry cooldown per symbol |
| 18 | `SizingGuard` | Capital sizing gate |
| 19 | `RiskPolicyGuard` | Risk policy compliance |
| 20 | `SmcNavigatorGuard` | SMC alignment check |

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
  enable_orders: true  # safety gate for DhanHQ order API
```

For live order placement, also set `PLACE_ORDER=true` in the environment. This is an additional safety gate in `Orders::Placer` that must be explicitly enabled.

Both modes use **real DhanHQ WebSocket data** for market ticks.

| Aspect | Paper Mode | Live Mode |
|--------|-----------|-----------|
| Market data | Real WebSocket ticks | Real WebSocket ticks |
| Option chain | Real DhanHQ API | Real DhanHQ API |
| Order execution | Simulated fills (`GatewayPaper`) | Real DhanHQ API (`GatewayLive`) |
| PnL tracking | Real LTP-based | Real LTP-based |
| Order updates | Synthetic | DhanHQ WebSocket |
| Wallet | Simulated balance | Real funds API |

## Run Modes

Set in `config/algo.yml` (`run_mode:`) or override with `RUN_MODE` env var:

| Mode | Purpose |
|------|---------|
| `production` | Full guards active, conservative entries |
| `exit_testing` | Frequent entries to test exit rules (bypasses most entry guards) |
| `entry_testing` | Relaxed guards to verify the entry pipeline |

Profile overrides live in `config/profiles/<run_mode>.yml`. **Current default:** `run_mode: exit_testing` (paper trading mode).

## Environment Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `DHAN_CLIENT_ID` | Yes | DhanHQ client ID |
| `DHAN_ACCESS_TOKEN` | Yes | DhanHQ access token (static fallback) |
| `DHAN_PIN` | Recommended | For TOTP auto-refresh |
| `DHAN_TOTP_SECRET` | Recommended | For TOTP auto-refresh |
| `ENABLE_TRADING_SERVICES` | Auto (Procfile) | Must be `"true"` for daemon |
| `PLACE_ORDER` | Live only | Must be `"true"` to allow live broker order placement |
| `DHANHQ_WS_ENABLED` | Optional | Enable WebSocket (defaults based on env) |
| `REDIS_URL` | Optional | Redis connection (default: redis://127.0.0.1:6379/0) |
| `DATABASE_URL` | Optional | PostgreSQL connection |
| `RAILS_ENV` | Optional | Rails environment |
| `RUN_MODE` | Optional | Override run_mode from config |
| `OLLAMA_MODEL` | Optional | Ollama model name (default: llama3.2:3b) |
| `OLLAMA_BASE_URL` / `OLLAMA_HOST_URL` | Optional | Ollama server URL (default: http://localhost:11434) |
| `OLLAMA_TIMEOUT` | Optional | Ollama request timeout in seconds (default: 120) |
| `TELEGRAM_BOT_TOKEN` | Optional | Telegram bot token |
| `TELEGRAM_CHAT_ID` | Optional | Telegram chat ID |

### Live Trading Checklist

Before switching `paper_trading.enabled: false`:

- [ ] DhanHQ credentials set (`DHAN_CLIENT_ID`, `DHAN_ACCESS_TOKEN`)
- [ ] TOTP credentials set (`DHAN_PIN`, `DHAN_TOTP_SECRET`) for token auto-refresh
- [ ] `PLACE_ORDER=true` in environment
- [ ] `dhanhq.enable_orders: true` in `config/algo.yml`
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
GET  /api/smc/decision                # SMC analytics decision (namespaced API)
GET  /smc/decision                    # Legacy URL → 301 redirect to /api/smc/decision
POST /cable                           # ActionCable WebSocket (positions, dashboard channels)
```

### OpenAPI (RSwag)

- Spec file: `swagger/v1/swagger.yaml` (regenerate with `bundle exec rake rswag:specs:swaggerize`).
- Swagger UI: `/api-docs` when mounted (development/test by default; in production set `ENABLE_SWAGGER_UI=true`).

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

All trading parameters live in `config/algo.yml`. Key sections:

| Section | Purpose |
|---------|---------|
| `paper_trading` | Paper/live mode toggle and simulated balance |
| `run_mode` | Runtime profile (`production`, `exit_testing`, `entry_testing`) |
| `dhanhq` | Broker settings (`enable_orders` safety gate) |
| `indices` | Per-index config: segment, SID, capital allocation, ADX thresholds, trailing tiers |
| `trade_limits` | Global daily limits |
| `risk` | Circuit breaker, drawdown, time stops, SL/TP percentages (DECIMAL format) |
| `position_sizing` | Rupee-based or percentage-based capital allocation |
| `signals` | Signal generation: ADX thresholds, timeframes, validation modes |
| `chain_analyzer` | Options chain scoring parameters |
| `expiry_week_power_trend` | ADX/timing/expiry window config for the power trend guard |
| `broker_fees` | Brokerage and transaction charges |
| `telegram` | Telegram bot configuration and PnL milestones |
| `ai` | Ollama AI settings (enabled flag) |

All percentage values use **DECIMAL format** (0.12 = 12%, not 12.0).

Runtime config changes: `AlgoConfig.fetch` has a 30-second in-process cache. DB overrides via the `settings` table are deep-merged on top of YAML values, enabling hot config changes without restart.

## Critical Rules

- **DhanHQ only** — no other broker code
- Live services communicate via **direct method calls** — `event_bus.rb` has only a debug subscriber; do not treat it as active communication
- `exit_engine.rb` is the **single source of truth** for exit placement — RiskManager and TrailingEngine detect conditions and call it directly
- `TickQuery` returns `nil` on cache miss — callers must treat nil as stale data, not zero
- Position sizing must go through `capital/` — never inline the math
- **Solid Queue** is the job runner (not Sidekiq) — use `ApplicationJob`
- Redis tick cache is **write-through** — if Redis is down, fall back gracefully
- **Never write to DB** from WebSocket tick handlers — enqueue a job or use the PnlUpdater flush
- All percentage config values use **DECIMAL format** (0.12 = 12%)
- WebSocket event handlers must be **idempotent** — the feed can reconnect and replay
- `Live::Gateway` is **deprecated** — use `Orders::GatewayLive` directly

## WSL2 Note

Default WSL2 memory limit is 8 GB even on 32 GB systems. Set `memory=16GB` in `~/.wslconfig` to prevent OOM kills of the trading daemon.

## License

This project is proprietary and confidential.
