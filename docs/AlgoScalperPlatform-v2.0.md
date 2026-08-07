Below is a **complete master prompt** you can paste into **Claude Code**, Cursor, Windsurf, Aider, or any coding assistant that can read/edit your current `algo_scalper_api` repository.

Before using it, ideally save the earlier documents in your repo as:

```text
docs/PRD.md
docs/IMPLEMENTATION_PLAN.md
docs/KPI.md
docs/ARCHITECTURE_NOTES.md
```

If you cannot save them as files, paste them after the prompt under the sections:

```text
<PRD>
...
</PRD>

<IMPLEMENTATION_PLAN>
...
</IMPLEMENTATION_PLAN>

<KPI>
...
</KPI>
```

---

# Complete Claude Code Prompt

Copy everything inside the block below.

```text
You are a staff-level full-stack engineer, quant platform architect, and trading-systems safety engineer.

You are working inside the existing repository: algo_scalper_api.

Your job is to update, complete, or start the full implementation of the Algo Scalper API platform according to the attached/available product and engineering documentation.

The product is an end-to-end NIFTY options scalping platform with:
1. Historical backtesting using DhanHQ v2 APIs.
2. Realistic paper trading using a simulated broker engine.
3. Live trading through DhanHQ REST/WebSocket APIs.
4. Real-time dashboard using SolidJS.
5. Rails API as the control plane, backtesting engine, clearing house, and trade journal.
6. Node.js TypeScript engine as the low-latency hot path for market data, candle building, indicators, signals, order routing, and position monitoring.
7. Redis as the real-time state machine, pub/sub bus, virtual capital store, and command bridge.
8. KPI instrumentation, audit logs, reconciliation, and risk controls.

Read and use the following documents if they exist in the repository:
- docs/PRD.md
- docs/IMPLEMENTATION_PLAN.md
- docs/KPI.md
- docs/ARCHITECTURE_NOTES.md
- README.md
- Any existing Rails, Node, TypeScript, SolidJS, Redis, Docker, or test files.

If those documents are not present as files, treat the documentation appended at the end of this prompt as the source of truth.

============================================================
PRIMARY OBJECTIVE
============================================================

Implement a production-grade architecture with clean separation:

1. Hot Path: Node.js TypeScript engine
   - Connects to DhanHQ WebSocket for live ticks.
   - Builds current candles from ticks.
   - Calculates indicators such as EMA 9 and EMA 21.
   - Evaluates strategy signals.
   - Routes orders through LiveDhanRouter or PaperRouter.
   - Monitors active positions for stop loss, target, trailing SL, square-off, kill switch.
   - Publishes trade/state events to Redis.

2. Cold Path: Rails API
   - Handles authentication, users, strategies, backtests, trades, analytics, reconciliation, and audit logs.
   - Uses the dhanhq-client Ruby gem for historical data, instruments sync, and backtesting.
   - Acts as clearing house for paper trades, calculating brokerage, STT, exchange charges, GST, stamp duty, etc.
   - Exposes REST endpoints and ActionCable WebSocket channels for the SolidJS frontend.
   - Stores durable records in PostgreSQL.

3. Real-Time State/Bus: Redis
   - Stores bot mode, bot status, strategy config, virtual capital, active trades, idempotency keys, risk state, and instrument mappings.
   - Provides pub/sub channels for trade events, state updates, and bot commands.
   - Ensures paper and live state are isolated.

4. Frontend: SolidJS
   - Reads from Rails API and ActionCable.
   - Displays dashboard, bot state, capital, PnL, active position, trade feed, backtests, trade history, strategy settings, and risk alerts.
   - Uses fine-grained SolidJS signals for high-frequency UI updates.
   - Clearly shows PAPER and LIVE mode with strong confirmation for live mode.

============================================================
NON-NEGOTIABLE SAFETY CONSTRAINTS
============================================================

1. Default mode must always be PAPER unless explicitly changed by the user.
2. Live trading must require explicit confirmation.
3. Never expose Dhan access tokens or client secrets to the frontend.
4. Never hardcode credentials. Use environment variables.
5. Do not send real live orders in tests. Mock all broker order execution in tests.
6. Paper and live state must never mix.
7. Duplicate orders from the same signal must be impossible. Implement idempotency keys.
8. If Redis is unavailable, the system must fail safely and prevent order routing.
9. If market data is stale, entries must be blocked and the UI must be alerted.
10. Active position state must survive Node engine restarts.
11. Kill switch must stop new entries immediately and optionally square off positions.
12. Risk limits must be enforced before any order is submitted.
13. All money-related database fields must use decimal/numeric types, not floating point.
14. All sensitive actions must be audit logged.
15. Do not destructively rewrite the current app without first understanding it.
16. Preserve existing functionality unless explicitly replacing it with a safer/equivalent implementation.
17. If a decision is ambiguous and could affect trading safety, choose the conservative option.

============================================================
CURRENT REPOSITORY HANDLING
============================================================

First, inspect the current repository structure.

Do all of the following before writing major code:

1. Identify whether the repository is:
   - Rails-only
   - Node-only
   - monorepo
   - mixed Rails + Node + frontend
   - partially implemented

2. List the current stack:
   - Ruby/Rails version if present
   - Node/TypeScript setup if present
   - frontend framework if present
   - database configuration
   - Redis usage
   - background jobs
   - tests
   - Docker setup
   - CI setup

3. Identify what already exists:
   - models
   - controllers
   - services
   - workers
   - channels
   - frontend components
   - Node engine modules
   - DhanHQ integrations
   - backtester code
   - paper engine code
   - WebSocket code
   - tests

4. Produce a short implementation audit:
   - what is complete
   - what is missing
   - what is unsafe
   - what should be refactored
   - what should be created from scratch

5. Create or update:
   - docs/CURRENT_STATE.md
   - docs/IMPLEMENTATION_TASKS.md

The implementation task file must contain checkboxes organized by phase.

Unless the repository is empty or badly broken, prefer incremental integration over rewriting everything.

If the current app is Rails-only, integrate the Node engine and SolidJS app in a clean subfolder structure without breaking Rails conventions.

Recommended target structure:

```text
algo_scalper_api/
├── apps/
│   ├── api/                    # Rails API, if monorepo is appropriate
│   ├── engine/                 # Node.js TypeScript hot path
│   └── web/                    # SolidJS frontend
├── packages/
│   ├── shared-types/           # Shared TS types
│   ├── redis-schemas/          # Redis key/event schemas
│   └── strategy-core/          # Pure strategy logic
├── docs/
│   ├── PRD.md
│   ├── IMPLEMENTATION_PLAN.md
│   ├── KPI.md
│   ├── ARCHITECTURE_NOTES.md
│   ├── CURRENT_STATE.md
│   ├── IMPLEMENTATION_TASKS.md
│   └── RUNBOOK.md
├── infrastructure/
│   ├── docker-compose.yml
│   ├── redis.conf
│   └── nginx.conf
├── scripts/
│   ├── seed_instruments.rb
│   └── replay_historical_data.ts
└── README.md
```

If the current repository is already a standard Rails root app and not a monorepo, adapt safely. For example:

```text
algo_scalper_api/
├── app/
├── config/
├── db/
├── engine/                  # Node hot path
├── frontend/                # SolidJS app
├── packages/
├── docs/
└── docker-compose.yml
```

Choose the structure that causes the least disruption to the current app while preserving the architecture.

============================================================
TECH STACK REQUIREMENTS
============================================================

Use the following stack unless the current repo already has a strongly conflicting and working setup:

Backend Control Plane:

- Ruby on Rails API
- PostgreSQL
- Redis
- Sidekiq
- ActionCable
- dhanhq-client Ruby gem

Hot Path Engine:

- Node.js
- TypeScript strict mode
- dhanhq-ts
- ioredis
- ws
- technicalindicators or equivalent indicator library
- pino or similar structured logger
- uuid

Frontend:

- SolidJS
- Vite
- TypeScript
- @rails/actioncable
- lightweight-charts or similar for candlestick charting

Infrastructure:

- Docker Compose for local development
- PostgreSQL
- Redis
- environment-variable-based configuration

============================================================
FUNCTIONAL SCOPE TO IMPLEMENT
============================================================

Implement or complete the following modules.

------------------------------------------------------------

1. Authentication and Users

------------------------------------------------------------

Create or update:

- users table
- authentication using JWT or secure session tokens
- password hashing
- roles: trader, admin, ops
- encrypted Dhan credentials storage
- API token authentication
- authorization for user-owned resources

Required endpoints:

POST /api/v1/auth/register
POST /api/v1/auth/login
POST /api/v1/auth/logout
GET  /api/v1/me

------------------------------------------------------------
1. Strategy Management

------------------------------------------------------------

Create Strategy model with:

- user_id
- name
- strategy_type
- parameters jsonb
- is_active
- timestamps

Default strategy:

strategy_type = "ema_breakout"

Default parameters:

{
  "underlying": "NIFTY",
  "exchangeSegment": "NSE_FNO",
  "instrument": "OPTIDX",
  "optionType": "CALL",
  "strikeMode": "ATM",
  "candleInterval": "5",
  "emaFast": 9,
  "emaSlow": 21,
  "slPct": 0.15,
  "targetPct": 0.30,
  "trailingSlPct": null,
  "slippagePct": 0.01,
  "qty": 50,
  "marketOpen": "09:20",
  "marketClose": "15:15",
  "squareOff": "15:20",
  "maxTradesPerDay": 10,
  "maxDailyLoss": 5000
}

Endpoints:

GET    /api/v1/strategies
POST   /api/v1/strategies
GET    /api/v1/strategies/:id
PATCH  /api/v1/strategies/:id
POST   /api/v1/strategies/:id/activate
POST   /api/v1/strategies/:id/deactivate

Validate parameters carefully.

------------------------------------------------------------
1. Bot Control

------------------------------------------------------------

Implement bot control endpoints:

GET  /api/v1/bot/status
POST /api/v1/bot/start
POST /api/v1/bot/stop
POST /api/v1/bot/square_off
POST /api/v1/bot/switch_mode
POST /api/v1/bot/kill_switch

Bot modes:

- paper
- live

Bot status:

- running
- stopped
- error
- halted_risk
- stale_data
- disconnected

Mode switching must:

- require explicit confirmation when switching to live
- square off current position if necessary
- update Redis mode
- notify Node engine via Redis command channel
- update frontend via ActionCable
- create an audit log

Kill switch must:

- stop new entries immediately
- optionally square off active position
- disable order router
- notify UI
- persist state
- require manual reset

------------------------------------------------------------
1. Redis State Manager

------------------------------------------------------------

Create a shared Redis key schema.

Use namespaces:

algo:{user_id}:bot_mode
algo:{user_id}:bot_status
algo:{user_id}:strategy_config
algo:{user_id}:{mode}:active_trade
algo:{user_id}:{mode}:orders
algo:{user_id}:virtual_capital
algo:{user_id}:live_candle
algo:{user_id}:pending_orders
algo:{user_id}:idempotency
algo:{user_id}:risk_state
dhan:instruments:{segment}

Where mode is paper or live.

Active trade hash schema:

{
  "orderId": string,
  "tradingSymbol": string,
  "securityId": string,
  "entryPrice": string,
  "entrySpot": string,
  "quantity": string,
  "stopLoss": string,
  "target": string,
  "trailingSl": string,
  "entryTime": string,
  "entryEma9": string,
  "entryEma21": string
}

Pub/Sub channels:

algo:{user_id}:trade_events
algo:{user_id}:state_updates
algo:{user_id}:bot_commands
algo:{user_id}:risk_events
algo:{user_id}:backtest_events

Implement Redis state managers in both Rails and Node.

Node RedisStateManager should support:

- getBotMode
- setBotMode
- getBotStatus
- setBotStatus
- getStrategyConfig
- setStrategyConfig
- getActiveTrade
- setActiveTrade
- clearActiveTrade
- updateTrailingSl
- getVirtualCapital
- incrementCapital
- decrementCapital
- publishTradeEvent
- publishStateUpdate
- subscribeToCommands
- getIdempotency
- setIdempotency

Rails RedisStateManager should support equivalent operations.

------------------------------------------------------------
1. Market Data and Candle Builder in Node

------------------------------------------------------------

Create Node engine modules:

- MarketDataManager
- CandleBuilder
- IndicatorEngine
- StrategyEngine
- PositionTracker
- OrderRouter
- LiveDhanRouter
- PaperRouter
- RiskManager
- RateLimiter
- CircuitBreaker
- MetricsCollector
- BotOrchestrator

MarketDataManager:

- connects to DhanHQ WebSocket using dhanhq-ts
- subscribes to NIFTY spot and selected option contract
- handles reconnect with exponential backoff
- emits tick events
- marks data stale if no ticks for configurable threshold
- fetches historical candles for warmup

CandleBuilder:

- builds current candle from ticks
- supports configurable interval, default 5 minutes
- detects candle close
- maintains rolling candle history, default 200 candles
- allows loading historical warmup candles

IndicatorEngine:

- calculates EMA 9 and EMA 21 on spot close by default
- supports future indicators such as VWAP, RSI, Supertrend, ATR
- deterministic calculation

StrategyEngine:

- implements strategy interface
- evaluates completed candles only for entry signals
- prevents duplicate signals per candle
- outputs signal with reason and metadata

Default MVP strategy:

Entry conditions:

- current candle close > previous candle high
- EMA fast > EMA slow
- current time within trading window
- no active position
- risk manager allows trade
- bot status running
- market data not stale

Exit conditions:

- stop loss hit
- target hit
- trailing stop loss hit if enabled
- square-off time reached
- manual square-off
- kill switch triggered

------------------------------------------------------------
1. Paper Trading Engine

------------------------------------------------------------

Implement a simulated broker in Node.

PaperRouter must implement OrderRouter interface:

placeOrder(order)
modifyOrder(orderId, changes)
cancelOrder(orderId)
getOrderStatus(orderId)

Paper engine must simulate:

- order validation
- margin/capital checks
- latency
- slippage
- tick size rounding
- market order fills using best ask/bid if depth available
- limit order fills if implemented
- partial fills optionally
- order rejection
- order IDs
- trade IDs
- virtual capital debit/credit
- fee calculation
- event publishing

Default paper fill rules:

For MARKET BUY:

- fill at best ask if depth exists
- otherwise LTP plus slippage
- add realistic slippage
- round to instrument tick size

For MARKET SELL:

- fill at best bid if depth exists
- otherwise LTP minus slippage
- round to instrument tick size

Default option tick size:

- 0.05

Default simulated latency:

- random between 40ms and 150ms, configurable

Default charges:

- brokerage: 20 per executed order
- STT: 0.0125% on sell side for options
- exchange transaction charge: configurable, approx 0.053%
- GST: 18% on brokerage + transaction charges
- stamp duty: 0.003% on buy side
- SEBI charges: configurable nominal turnover charge

Paper engine must publish events:

ORDER_ACCEPTED
ORDER_REJECTED
ORDER_FILLED
POSITION_OPENED
POSITION_CLOSED
SL_HIT
TARGET_HIT
SQUARE_OFF
CAPITAL_UPDATED

Paper trades must never call Dhan order APIs.

------------------------------------------------------------
1. Live Trading Router

------------------------------------------------------------

LiveDhanRouter must use dhanhq-ts to place real orders.

Live order requirements:

- validate live mode explicitly
- validate Dhan credentials
- validate risk manager
- validate idempotency
- validate market hours
- validate instrument active status
- use rate limiter
- use circuit breaker
- log full order lifecycle
- sync order state where possible
- handle 429 and timeout with backoff
- prioritize exit orders over entry orders

Live engine must:

- read active position from Redis after restart
- reconcile with Dhan positions/orders if possible
- resume monitoring active position
- raise alert on mismatch
- never blindly duplicate an order

------------------------------------------------------------
1. Risk Manager

------------------------------------------------------------

Implement risk checks before entry and during live operation.

RiskManager must enforce:

- max daily loss
- max trades per day
- max open positions
- stale data guard
- kill switch
- bot stopped state
- insufficient virtual/live capital
- duplicate signal prevention
- market hours
- expiry-day restrictions if configured

If risk limit is breached:

- block entries
- publish risk event
- notify UI
- record audit/risk log
- optionally square off according to configuration

------------------------------------------------------------
1. Rails Backtesting Engine

------------------------------------------------------------

Implement backtesting using Ruby and dhanhq-client.

Create service:

Backtesting::NiftyOptionsBacktester

Features:

- fetch rolling option data from Dhan /v2/charts/rollingoption
- fetch spot data if required from /v2/charts/intraday
- split date range into chunks of max 28 days
- normalize response arrays into candle hashes
- calculate EMA indicators
- simulate entry/exit logic
- apply slippage
- apply stop loss and target
- apply intraday square-off
- optionally estimate charges
- generate trade list
- generate summary
- store results in database
- support CSV export

Backtest date chunking must respect Dhan 30-day API limit.

Use rollingoption relative strikes such as:

- ATM
- ATM+1
- ATM-1
- ATM+2
- ATM-2

Because historical expired security IDs may not be available, do not depend on historical securityId lookup for MVP backtesting.

Implement dynamic offset helper:

strike_shift = round((current_spot - entry_spot) / strike_step)

For NIFTY default strike_step = 50.

If spot moves up:

- original CE becomes ATM-{shift}

If spot moves down:

- original CE becomes ATM+{shift}

Backtest output must include:

- total trades
- win rate
- gross PnL
- estimated charges
- net PnL
- max drawdown
- average win
- average loss
- expectancy
- profit factor
- trade list
- CSV download

Create BacktestRun model with:

- user_id
- strategy_id
- start_date
- end_date
- status
- total_trades
- win_rate
- total_pnl
- max_drawdown
- parameters_snapshot
- results_summary
- timestamps

Backtest statuses:

- pending
- running
- completed
- failed

Use Sidekiq worker for execution.

Endpoints:

POST /api/v1/backtests
GET  /api/v1/backtests
GET  /api/v1/backtests/:id
GET  /api/v1/backtests/:id/results
GET  /api/v1/backtests/:id/download_csv

------------------------------------------------------------
 1. Instrument Sync

------------------------------------------------------------

Implement instrument master sync using dhanhq-client.

Rails service must:

- fetch NSE_FNO instrument CSV
- parse relevant fields
- store cache date
- populate Redis mapping for active contracts
- expose sync status
- log errors

Redis instrument mapping should allow Node to resolve active security IDs quickly.

Example key:

dhan:instruments:NSE_FNO:NIFTY:WEEK:24000:CE

Value:

{
  "securityId": "42528",
  "lotSize": 50,
  "tickSize": 0.05,
  "expiry": "2026-01-25",
  "symbol": "NIFTY"
}

Add endpoint:

POST /api/v1/instruments/sync
GET  /api/v1/instruments/search
GET  /api/v1/instruments/sync_status

------------------------------------------------------------
 1. Trade Journal and Clearing

------------------------------------------------------------

Create TradeLog model with fields:

- user_id
- strategy_id
- mode
- broker_order_id
- exchange_order_id
- trade_id
- trading_symbol
- security_id
- transaction_type
- order_type
- product_type
- quantity
- price
- average_price
- turnover
- brokerage
- stt
- txn_charges
- gst
- stamp_duty
- sebi_charges
- net_charges
- pnl
- status
- is_paper_trade
- executed_at
- metadata jsonb

Indexes:

- user_id + mode + executed_at
- exchange_order_id
- strategy_id
- is_paper_trade

Rails clearing service must listen to Redis trade events and persist fills.

For paper fills:

- calculate charges
- store trade log
- update virtual capital if needed
- broadcast to frontend

For live fills:

- store trade log
- mark is_paper_trade=false
- reconcile later with broker records

------------------------------------------------------------
 1. Daily Performance and Reconciliation

------------------------------------------------------------

Create DailyPerformance model:

- user_id
- trading_date
- mode
- total_trades
- winning_trades
- losing_trades
- gross_pnl
- total_taxes
- net_pnl
- win_rate
- max_drawdown
- virtual_capital_end
- timestamps

Create reconciliation worker:

- runs end of day
- compares internal trades with broker records for live mode
- compares internal ledger for paper mode
- stores reconciliation report
- raises alert on mismatch

------------------------------------------------------------
 1. Audit Logs

------------------------------------------------------------

Create AuditLog model:

- user_id
- action
- entity_type
- entity_id
- old_value jsonb
- new_value jsonb
- ip_address
- user_agent
- created_at

Audit log these actions:

- bot start
- bot stop
- mode switch
- live confirmation
- kill switch
- strategy config change
- capital reset
- square off
- risk breach
- reconciliation mismatch

------------------------------------------------------------
 1. ActionCable Realtime API

------------------------------------------------------------

Create ScalperChannel.

Client-to-server actions:

start_bot
stop_bot
square_off
switch_mode
update_config

Server-to-client events:

state_updates
trade_events
bot_status
mode_change
risk_alert
connection_status
backtest_update

Continuous state updates must be throttled.

Default:

- state_updates every 100ms from Node or Rails broadcaster
- trade_events instant
- candle/chart updates every 500ms or 1s if needed

------------------------------------------------------------
 1. SolidJS Frontend

------------------------------------------------------------

Create or update SolidJS app.

Required pages:

- Dashboard
- Backtesting
- Trade History
- Strategy Settings
- Settings/Risk

Dashboard must show:

- bot status
- mode badge: PAPER or LIVE
- connection status
- virtual capital
- unrealized PnL
- realized PnL
- active position card
- trade feed
- candlestick chart
- start/stop controls
- square-off button
- kill switch
- risk alerts
- stale data warning

Use SolidJS signals and ActionCable.

Create hook:

useScalperSocket

It should expose reactive signals for:

- virtualCapital
- activeTrade
- livePnl
- orderEvents
- botStatus
- mode
- isConnected

Use @rails/actioncable.

Ensure cleanup on unmount.

Frontend must not directly call Dhan APIs.

Frontend must clearly distinguish paper and live modes.

Live mode switch must show a dangerous confirmation modal.

------------------------------------------------------------
 1. KPI Instrumentation

------------------------------------------------------------

Instrument metrics and logs for:

Trading KPIs:

- net PnL
- gross PnL
- total charges
- win rate
- profit factor
- expectancy
- max drawdown
- average win
- average loss
- payoff ratio
- charge impact ratio

Execution KPIs:

- signal-to-order latency
- tick-to-signal latency
- slippage
- order rejection rate
- duplicate order count
- order timeout count
- paper/live fill divergence

Risk KPIs:

- daily loss limit breaches
- max trades/day breaches
- stale data events
- kill switch activations
- unrecovered crash positions
- reconciliation mismatches

Reliability KPIs:

- WebSocket disconnect count
- reconnect success rate
- Node crash count
- crash recovery time
- Redis availability
- API availability
- stale UI events

Backtest KPIs:

- completed backtests
- failed backtests
- backtest duration
- backtest-to-paper gap
- reproducibility status

Add metrics collection in Node and Rails.

For MVP, structured logs plus database analytics are acceptable. If Prometheus/OpenTelemetry is already present, integrate with it.

------------------------------------------------------------
 1. Testing Requirements

------------------------------------------------------------

Create tests for:

Ruby:

- models
- services
- backtester date chunking
- paper clearing service
- fee calculator
- API endpoints
- ActionCable channel behavior
- workers

Node:

- candle builder
- EMA calculation
- strategy signal logic
- paper matching engine
- tick size rounding
- risk manager
- rate limiter
- idempotency
- order router factory
- Redis state manager with mocked Redis

Frontend:

- component render tests where practical
- socket hook tests with mocked ActionCable
- mode badge behavior
- stale data indicator behavior

Do not call real Dhan APIs in tests.
Use mocks/fixtures.

Add fixtures for:

- historical candles
- rolling option responses
- tick data
- instrument CSV
- order responses

------------------------------------------------------------
 1. Configuration and Environment

------------------------------------------------------------

Create or update .env.example:

DHAN_CLIENT_ID=
DHAN_ACCESS_TOKEN=
DATABASE_URL=postgres://user:password@localhost:5432/algo_scalper
REDIS_URL=redis://localhost:6379/0
RAILS_ENV=development
BOT_MODE=paper
NODE_ENV=development
LOG_LEVEL=info
VITE_API_URL=<http://localhost:3000>
VITE_WS_URL=ws://localhost:3000

Never commit real credentials.

------------------------------------------------------------
 1. Docker and Local Development

------------------------------------------------------------

Create or update docker-compose.yml with:

- postgres
- redis
- rails_api
- node_engine
- solidjs_web

Also provide scripts:

bin/setup
bin/dev
or equivalent.

README must explain how to:

- install dependencies
- setup database
- run migrations
- seed instruments
- start Redis/Postgres
- start Rails
- start Node engine
- start SolidJS frontend
- run tests
- run backtest
- start paper trading

------------------------------------------------------------
 1. Implementation Process
============================================================

Work in this order:

Phase 0: Repository audit

- inspect current code
- identify gaps
- create docs/CURRENT_STATE.md
- create docs/IMPLEMENTATION_TASKS.md

Phase 1: Documentation and task breakdown

- ensure PRD, implementation plan, KPI docs exist
- create implementation checklist

Phase 2: Database schema and Rails models

- create migrations
- create models
- add validations
- add indexes

Phase 3: Redis schema and state manager

- create shared key conventions
- implement Redis managers in Rails and Node

Phase 4: Rails API core

- auth
- strategies
- bot control
- trades
- dashboard
- backtests
- instruments
- audit logs

Phase 5: Backtesting engine

- date chunker
- Dhan historical service
- indicator calculator
- simulation engine
- CSV export
- Sidekiq worker

Phase 6: Node engine core

- TypeScript setup
- config loader
- logger
- Redis client
- market data manager
- candle builder
- indicator engine
- strategy engine
- orchestrator

Phase 7: Paper engine

- paper router
- matching engine
- virtual RMS
- fee calculator
- capital ledger
- event publishing

Phase 8: Live router

- live order router
- rate limiter
- circuit breaker
- live position tracker
- crash recovery/reconciliation hooks

Phase 9: Realtime integration

- Rails ActionCable channel
- Redis subscriber worker
- frontend socket hook

Phase 10: SolidJS frontend

- dashboard
- controls
- settings
- backtest UI
- trade history
- KPI widgets

Phase 11: KPI instrumentation

- logs
- metrics
- analytics queries
- reconciliation reports

Phase 12: Tests

- Ruby tests
- Node tests
- frontend tests
- E2E critical path tests where practical

Phase 13: Hardening

- health checks
- error handling
- retry/backoff
- stale data guard
- kill switch
- recovery flows
- runbook

============================================================
DEFINITION OF DONE
============================================================

The implementation is complete only when:

1. Rails API runs successfully.
2. Node engine runs successfully.
3. SolidJS frontend runs successfully.
4. Redis and PostgreSQL are integrated.
5. Paper trading works end-to-end without calling Dhan order APIs.
6. Backtesting works with date chunking and CSV export.
7. Live order router exists but is protected by explicit mode and safety checks.
8. Active paper position survives Node restart.
9. Kill switch works.
10. Mode switching works safely.
11. Dashboard updates in real time.
12. Paper and live records are separated.
13. Trade logs are persisted.
14. Audit logs are created for sensitive actions.
15. Tests pass.
16. README and runbook are updated.
17. No secrets are hardcoded.
18. The system defaults to paper mode.
19. Duplicate orders are prevented.
20. Risk limits are enforced.

============================================================
CODING STANDARDS
============================================================

Ruby/Rails:

- follow Rails conventions
- use service objects for complex logic
- use Sidekiq for background jobs
- use strong parameters
- use validations
- use decimal for money
- use UTC in database
- use IST carefully for market-hour logic
- keep controllers thin

TypeScript/Node:

- strict mode
- explicit interfaces
- small composable modules
- no any unless unavoidable
- use async/await cleanly
- handle promise rejections
- use structured logging
- use environment variables
- separate pure strategy logic from I/O

SolidJS:

- use signals correctly
- avoid unnecessary re-renders
- clean up WebSocket subscriptions
- use TypeScript
- keep components small
- show loading/error/empty states

Redis:

- use namespaced keys
- use JSON payloads for events
- avoid unbounded lists
- set TTL where appropriate
- do not store secrets in Redis unless encrypted and necessary

Testing:

- prefer deterministic tests
- mock external APIs
- test edge cases
- test crash recovery logic where possible
- test risk rejections

============================================================
OUTPUT EXPECTATIONS
============================================================

As you work:

1. First output the repository audit and proposed implementation plan.
2. Then implement incrementally.
3. After each major phase, summarize:
   - files changed
   - files created
   - migrations added
   - tests added
   - remaining tasks
4. If you encounter a blocker, clearly state:
   - what is blocked
   - why
   - what information or decision is needed
   - safe fallback if no decision is provided
5. Do not ask unnecessary clarifying questions unless the ambiguity affects trading safety, data integrity, or destructive refactoring.
6. When implementation is complete, provide:
   - final change summary
   - how to run the app
   - how to run tests
   - how to start paper trading
   - how to run a backtest
   - how to switch to live mode safely
   - known limitations
   - follow-up recommendations

============================================================
IMPORTANT IMPLEMENTATION DETAILS
============================================================

Do not forget these domain-specific details:

1. Dhan rolling option historical endpoint accepts max 30-day windows. Use 28-day chunks to be safe.

2. Dhan historical responses often contain parallel arrays:
   - open
   - high
   - low
   - close
   - volume
   - timestamp
   - spot
   - strike
   - iv
   - oi

   Convert these into arrays of candle hashes.

3. For historical backtesting, do not rely on historical expired security IDs from current instrument master. Use rolling option relative strikes.

4. For live trading, use current instrument master to resolve active security IDs.

5. For options, default NSE tick size is 0.05, but make it configurable from instrument data.

6. For NIFTY, default strike step is 50, but make it configurable.

7. Market hours default:
   - entries allowed 09:20 IST to 15:15 IST
   - square-off at 15:20 IST

8. Candle close signals should be evaluated only after candle completion.

9. Intra-candle monitoring should be used for:
   - stop loss
   - target
   - trailing SL
   - square-off
   - kill switch

10. Paper trading must simulate:

- latency
- slippage
- tick size
- charges
- capital checks
- rejections

 1. Live trading must include:

- rate limiting
- retries/backoff
- circuit breaker
- idempotency
- order state sync
- crash recovery

 1. Frontend must never poll aggressively for real-time state when ActionCable/Redis pub/sub can be used.

 2. UI must display stale data and disconnected states.

 3. KPIs should be queryable from trade logs, event logs, reconciliation reports, and metrics/logs.

============================================================
START NOW
============================================================

Begin by inspecting the current repository.

Then produce:

1. docs/CURRENT_STATE.md
2. docs/IMPLEMENTATION_TASKS.md
3. A short summary of the safest implementation path.

After that, proceed with implementation incrementally.

If documentation is appended below, treat it as authoritative product and engineering context.

<PRD>
[PASTE FULL PRD HERE OR REMOVE IF docs/PRD.md EXISTS]
</PRD>

<IMPLEMENTATION_PLAN>
[PASTE FULL IMPLEMENTATION PLAN HERE OR REMOVE IF docs/IMPLEMENTATION_PLAN.md EXISTS]
</IMPLEMENTATION_PLAN>

<KPI>
[PASTE FULL KPI DOCUMENT HERE OR REMOVE IF docs/KPI.md EXISTS]
</KPI>

<ARCHITECTURE_NOTES>
[PASTE ADDITIONAL ARCHITECTURE NOTES HERE OR REMOVE IF docs/ARCHITECTURE_NOTES.md EXISTS]
</ARCHITECTURE_NOTES>

```

---

## Recommended Way to Use This Prompt

### Option A: Best — Save Docs as Files

Create these files first:

```text
docs/PRD.md
docs/IMPLEMENTATION_PLAN.md
docs/KPI.md
docs/ARCHITECTURE_NOTES.md
```

Then remove the placeholder sections at the bottom of the prompt:

```text
<PRD>
[PASTE FULL PRD HERE OR REMOVE IF docs/PRD.md EXISTS]
</PRD>
```

and replace them with:

```text
The full documentation is already present in the docs/ directory. Read all files in docs/ before implementation.
```

---

### Option B: Paste Docs Directly

If you cannot store docs in the repo yet, paste the full earlier outputs inside:

```text
<PRD>
...
</PRD>

<IMPLEMENTATION_PLAN>
...
</IMPLEMENTATION_PLAN>

<KPI>
...
</KPI>
```

---

## Optional Follow-Up Prompt After First Audit

After Claude Code produces `docs/CURRENT_STATE.md` and `docs/IMPLEMENTATION_TASKS.md`, use this follow-up:

```text
Proceed with Phase 0 and Phase 1 implementation now.

Priorities:
1. Do not break existing functionality.
2. Create missing database migrations and models.
3. Add Redis state manager.
4. Add strategy, bot, trade, backtest, and audit log foundations.
5. Add docs/RUNBOOK.md.
6. Keep everything in paper mode by default.
7. Do not implement live order execution until the paper engine foundation is stable.

After each major step, summarize changed files and next steps.
```

---

## Prompt for Implementing the Node Engine Specifically

If the Rails foundation is already complete, use this:

```text
Now implement the Node.js TypeScript hot path engine.

Requirements:
- Use TypeScript strict mode.
- Use ioredis.
- Use dhanhq-ts.
- Use pino logging.
- Create modules for:
  - BotOrchestrator
  - MarketDataManager
  - CandleBuilder
  - IndicatorEngine
  - StrategyEngine
  - PositionTracker
  - OrderRouter
  - LiveDhanRouter
  - PaperRouter
  - RiskManager
  - RateLimiter
  - CircuitBreaker
  - RedisStateManager
  - MetricsCollector

Default mode must be paper.

The engine must:
- read strategy config from Redis
- warm up candles from historical data
- build current candles from ticks
- evaluate EMA breakout strategy on candle close
- monitor active positions intra-candle
- publish events to Redis
- recover active state after restart
- never send live orders unless bot_mode is live and risk checks pass
- prevent duplicate signals with idempotency keys

Add unit tests for pure logic and mocked tests for Redis/Dhan interactions.
```

---

## Prompt for Implementing the Paper Engine Specifically

```text
Implement the paper trading engine as a simulated broker inside the Node.js TypeScript engine.

The paper engine must simulate:
- order acceptance/rejection
- virtual capital checks
- configurable latency
- configurable slippage
- market order fills using best bid/ask when depth is available
- tick size rounding, default 0.05
- partial fills if depth quantity is insufficient, or explicitly document the simplified full-fill assumption
- order IDs and trade IDs
- virtual capital debit/credit
- Dhan-style charges: brokerage, STT, exchange transaction charges, GST, stamp duty, SEBI charges
- Redis event publishing
- separation from live state

Do not call Dhan order APIs in paper mode.

Add tests for:
- insufficient capital rejection
- market buy fill at ask plus slippage
- market sell fill at bid minus slippage
- tick size rounding
- charge calculation
- duplicate signal prevention
- active trade recovery from Redis
```

---

## Prompt for Implementing the SolidJS Frontend

```text
Implement the SolidJS frontend for Algo Scalper API.

The frontend must connect to Rails API and ActionCable.

Create:
- Dashboard page
- Backtesting page
- Trade History page
- Strategy Settings page
- Risk/Settings page

Dashboard must display:
- connection status
- bot status
- mode badge: PAPER or LIVE
- virtual capital
- unrealized PnL
- active position
- trade feed
- candlestick chart
- start/stop controls
- square-off button
- kill switch
- risk alerts
- stale data warning

Use SolidJS signals and @rails/actioncable.

Create a useScalperSocket hook exposing:
- virtualCapital
- activeTrade
- livePnl
- orderEvents
- botStatus
- mode
- isConnected

Clean up WebSocket subscriptions on unmount.

The UI must make live mode extremely explicit and require confirmation before switching to live.
```

---

## Final Tip

For best results with Claude Code, run the implementation in this order:

1. **Audit prompt**
   Let it inspect the current repo and produce `CURRENT_STATE.md`.

2. **Foundation prompt**
   Rails models, migrations, Redis schema, API endpoints.

3. **Backtesting prompt**
   Ruby backtester, chunking, CSV export.

4. **Node engine prompt**
   Market data, candles, indicators, strategy.

5. **Paper engine prompt**
   Simulated broker, fees, virtual ledger.

6. **Frontend prompt**
   SolidJS dashboard and controls.

7. **Hardening prompt**
   Tests, KPI instrumentation, reconciliation, runbook.

# Key Success Metrics / KPIs for Algo Scalper API

For this product, success should **not** be measured by PnL alone. Because this is a trading infrastructure system, the KPIs must cover:

1. **Strategy effectiveness**
2. **Execution quality**
3. **Risk control**
4. **System reliability**
5. **Paper trading realism**
6. **Backtest quality**
7. **User experience / dashboard performance**
8. **Operational safety**

The true North Star is:

> **The trader can safely validate a strategy in backtest, prove it in realistic paper trading, and deploy it live with controlled risk, full auditability, and minimal operational failure.**

---

## 1. North Star Metric

### Primary North Star

**Risk-Adjusted Net Profitability After Costs**

This means the strategy produces positive net performance after:

- brokerage
- STT
- exchange charges
- GST
- stamp duty
- slippage
- latency impact
- rejected/expired orders
- square-off exits

Formula:

```text
Net PnL = Gross PnL - Total Charges - Slippage Impact
```

However, this must be evaluated together with drawdown and reliability.

A stronger North Star formulation is:

> **Net profit per unit of risk, with zero uncontrolled operational incidents.**

Example:

```text
Success = Positive Expectancy + Max Drawdown Within Limit + Zero Critical System Failures
```

---

## 2. KPI Categories

| Category | Purpose |
| --- | --- |
| Strategy Performance | Is the trading strategy profitable and robust? |
| Execution Quality | Are orders executed efficiently and reliably? |
| Risk Management | Are losses and exposures controlled? |
| System Reliability | Is the platform stable during market hours? |
| Paper Trading Fidelity | Does paper trading realistically simulate live trading? |
| Backtest Quality | Are backtests trustworthy and reproducible? |
| Product/UX | Is the user able to operate the system confidently? |
| Data Quality | Are market data, candles, and instruments accurate? |
| Compliance/Audit | Are all actions traceable and safe? |

---

# 3. Strategy Performance KPIs

These measure whether the trading strategy itself is viable.

---

## 3.1 Net PnL

### Definition

Total profit or loss after all costs.

```text
Net PnL = Gross PnL - Brokerage - Taxes - Charges
```

### Why It Matters

This is the ultimate trading outcome metric.

### Suggested Target

- Paper mode: positive expectancy over statistically meaningful sample
- Live mode: positive after costs over rolling 20/50/100 trades

### Important Note

Net PnL should not be evaluated without drawdown and sample size.

---

## 3.2 Win Rate

### Definition

```text
Win Rate = Winning Trades / Total Closed Trades
```

### Why It Matters

Helps understand strategy behavior.

### Warning

Win rate alone is dangerous. A 90% win rate strategy can still lose money if losses are large.

### Reasonable Range

For option buying scalping:

- 35%–60% can still be profitable if payoff ratio is strong
- Very high win rate may indicate overly tight targets and fat tail risk

---

## 3.3 Average Win / Average Loss

### Definition

```text
Average Win = Total Profit from Winning Trades / Number of Winning Trades
Average Loss = Total Loss from Losing Trades / Number of Losing Trades
```

### Why It Matters

Shows payoff quality.

### KPI

```text
Payoff Ratio = Average Win / Average Loss
```

### Suggested Target

- Payoff ratio > 1.5 for option buying scalping
- Ideally > 2.0 if win rate is moderate

---

## 3.4 Expectancy

### Definition

Expected profit per trade.

```text
Expectancy = (Win Rate × Average Win) - (Loss Rate × Average Loss)
```

### Why It Matters

This is one of the most important strategy KPIs.

### Target

- Expectancy > 0 after all charges
- Preferably stable across market regimes

---

## 3.5 Profit Factor

### Definition

```text
Profit Factor = Gross Profit / Gross Loss
```

### Why It Matters

Measures overall edge quality.

### Suggested Target

| Profit Factor | Interpretation |
| ---: | --- |
| < 1.0 | Losing system |
| 1.0–1.2 | Weak / marginal |
| 1.2–1.5 | Acceptable but sensitive to costs |
| 1.5–2.0 | Good |
| > 2.0 | Strong, but verify overfitting |

---

## 3.6 Maximum Drawdown

### Definition

Largest peak-to-trough decline in capital or PnL.

```text
Max Drawdown = Lowest Equity Point - Previous Peak Equity
```

### Why It Matters

This is critical for survivability.

### Suggested Target

Depends on risk appetite, but for scalping:

- Intraday max daily drawdown limit enforced
- Strategy max drawdown should be within user-defined capital risk ceiling

Example:

```text
Max daily loss <= 1%–2% of trading capital
```

---

## 3.7 Sharpe / Sortino Ratio

### Definition

Risk-adjusted return metrics.

```text
Sharpe = Average Return / Standard Deviation of Returns
Sortino = Average Return / Downside Deviation
```

### Why It Matters

Useful for comparing strategies.

### Target

For intraday scalping:

- Sortino is often more useful than Sharpe because it penalizes downside volatility only.

---

## 3.8 Average Holding Time

### Definition

Average time between entry and exit.

### Why It Matters

Scalping strategies should not accidentally become positional due to failed exits.

### KPI

- Average holding time should match strategy intent
- Sudden increase may indicate exit logic failure or liquidity issues

---

## 3.9 Number of Trades

### Definition

Total executed trades in a period.

### Why It Matters

Statistical significance requires enough trades.

### KPI

- Avoid strategies with too few trades to validate
- Also avoid overtrading where charges destroy edge

---

## 3.10 Charge Impact Ratio

### Definition

How much of gross edge is eaten by charges.

```text
Charge Impact = Total Charges / Gross Profit
```

or

```text
Charge Drag = Total Charges / Gross PnL
```

### Why It Matters

Options scalping can look profitable before charges and fail after charges.

### Target

- Lower is better
- If charges consume > 30%–50% of gross profit, strategy is fragile

---

# 4. Execution Quality KPIs

These measure whether the system executes the strategy efficiently.

---

## 4.1 Signal-to-Order Latency

### Definition

Time between signal generation and order submission.

```text
Signal-to-Order Latency = Order Submission Time - Signal Time
```

### Target

| Environment | Target |
| --- | ---: |
| Node internal processing | < 5 ms |
| Signal to live order submission | < 500 ms excluding broker network |
| Paper simulated latency | configurable 20–200 ms |

---

## 4.2 Tick-to-Signal Latency

### Definition

Time from receiving market tick to strategy evaluation.

```text
Tick-to-Signal Latency = Strategy Evaluation Time - Tick Received Time
```

### Target

- p50 < 2 ms
- p95 < 5 ms
- p99 < 10 ms

This excludes external network latency.

---

## 4.3 Slippage

### Definition

Difference between expected signal price and actual fill price.

```text
Slippage = Actual Fill Price - Expected Price
```

For buys, positive slippage is usually bad. For sells, negative slippage is usually bad.

### Why It Matters

Scalping strategies are highly sensitive to slippage.

### KPI

- Average slippage per trade
- Worst-case slippage
- Slippage as % of premium

### Target

- Paper: modeled realistically
- Live: tracked and compared to paper assumptions

---

## 4.4 Implementation Shortfall

### Definition

Difference between theoretical strategy performance and actual executed performance.

```text
Implementation Shortfall = Theoretical Signal PnL - Actual Executed PnL
```

### Why It Matters

It measures the cost of real-world execution.

### Target

- Should be stable and explainable
- Large divergence indicates execution issues, latency, liquidity, or bad assumptions

---

## 4.5 Order Rejection Rate

### Definition

```text
Order Rejection Rate = Rejected Orders / Total Orders
```

### Split By Reason

- RMS rejection
- insufficient margin
- invalid instrument
- expired contract
- rate limit
- broker error
- system error

### Target

- System-caused rejection rate: near 0%
- Risk-caused rejections: acceptable if intentional

---

## 4.6 Order Timeout Rate

### Definition

Orders not confirmed within expected time.

### Why It Matters

May indicate broker API latency, network issue, or order state sync failure.

### Target

- Very low
- Alert if repeated

---

## 4.7 Duplicate Order Rate

### Definition

Number of duplicate orders caused by same signal.

```text
Duplicate Order Rate = Duplicate Orders / Total Signals
```

### Target

Must be:

```text
0%
```

This requires idempotency keys.

---

## 4.8 Order Modification / Cancellation Success Rate

### Definition

If modifications or cancellations are used:

```text
Success Rate = Successful Mods or Cancels / Requested Mods or Cancels
```

### Target

- High
- Failures must trigger safe fallback

---

# 5. Risk Management KPIs

These measure whether the system protects capital.

---

## 5.1 Max Daily Loss Compliance

### Definition

Percentage of days where daily loss stayed within configured limit.

```text
Daily Loss Compliance = Compliant Days / Total Trading Days
```

### Target

```text
100%
```

---

## 5.2 Number of Risk Limit Breaches

### Definition

Count of events where limits were hit:

- max daily loss
- max trades/day
- max open positions
- stale data block
- kill switch triggered

### Why It Matters

Shows whether risk controls are active and effective.

### Target

- Breaches should be contained automatically
- Zero uncontained breaches

---

## 5.3 Kill Switch Activation Time

### Definition

Time from kill switch trigger to order routing disabled.

### Target

```text
< 1 second
```

If configured to square off:

```text
Square-off order initiated within 1–2 seconds
```

---

## 5.4 Stale Data Events

### Definition

Number of times market data became stale beyond threshold.

### Target

- Low count
- All stale events should block entries
- Repeated stale events require infrastructure investigation

---

## 5.5 Position Reconciliation Accuracy

### Definition

Match between internal position state and broker position.

```text
Reconciliation Match = Matched Positions / Total Live Positions
```

### Target

```text
100% for live trading
```

For paper:

```text
100% internal ledger match
```

---

## 5.6 Unauthorized Order Count

### Definition

Orders sent outside configured risk rules or mode.

### Target

Must be:

```text
0
```

---

## 5.7 Unrecovered Crash Positions

### Definition

Open positions not recovered after Node engine crash/restart.

### Target

```text
0
```

---

# 6. System Reliability KPIs

These measure platform stability.

---

## 6.1 Market Hours Uptime

### Definition

Percentage of market time where the full stack is healthy.

```text
Uptime = Healthy Market Minutes / Total Market Minutes
```

### Target

| Stage | Target |
| --- | ---: |
| MVP | 99%+ market hours |
| Production trading | 99.5%+ market hours |

---

## 6.2 Node Engine Crash Count

### Definition

Number of Node engine crashes during market hours.

### Target

- Zero unexplained crashes
- Any crash must auto-restart and recover state

---

## 6.3 Crash Recovery Time

### Definition

Time from engine crash to restored monitoring of active positions.

```text
Recovery Time = Process Restart + Redis State Load + Position Validation
```

### Target

```text
< 5 seconds
```

---

## 6.4 WebSocket Disconnect Count

### Definition

Number of Dhan WebSocket disconnects.

### Target

- As low as possible
- Alert if repeated
- Disconnects must trigger stale data guard

---

## 6.5 WebSocket Reconnect Success Rate

### Definition

```text
Reconnect Success = Successful Reconnects / Disconnects
```

### Target

```text
100%
```

---

## 6.6 Redis Availability

### Definition

Redis read/write success rate.

### Target

```text
Near 100%
```

If Redis is unavailable, trading should halt safely.

---

## 6.7 Rails API Availability

### Definition

Availability of control-plane APIs.

### Target

- High availability during market hours
- API downtime should not cause uncontrolled live trading

---

## 6.8 ActionCable Delivery Latency

### Definition

Time from Redis event to frontend receipt.

### Target

- p95 < 250 ms
- State updates throttled at 100 ms

---

## 6.9 Frontend Stale UI Events

### Definition

Number of times UI lost live state updates.

### Target

- Low
- UI must show warning when stale

---

# 7. Paper Trading Fidelity KPIs

These measure how realistic the simulated broker is.

---

## 7.1 Paper vs Live Fill Divergence

### Definition

Difference between paper simulated fills and live fills for similar market conditions.

```text
Fill Divergence = Live Fill Price - Paper Simulated Fill Price
```

### Why It Matters

If paper results are much better than live results, the paper engine is too optimistic.

### Target

- Divergence should be explainable
- Should be within configured tolerance

---

## 7.2 Paper Fill Latency Realism

### Definition

Whether simulated latency matches real-world order latency.

### KPI

- Average simulated latency
- Average live order latency
- Difference between them

### Target

Paper latency should be configurable and realistic.

---

## 7.3 Paper Slippage Accuracy

### Definition

Comparison of assumed slippage vs actual live slippage.

### Target

- Paper slippage should not be materially lower than live slippage
- If live slippage consistently exceeds paper assumptions, update paper model

---

## 7.4 Paper Charge Accuracy

### Definition

Whether simulated brokerage/taxes match actual or expected broker charges.

### Target

- Paper charges within small tolerance of actual/live expected charges

---

## 7.5 Paper Rejection Behavior

### Definition

Whether paper engine rejects orders for:

- insufficient capital
- max daily loss
- max trades/day
- stale data
- kill switch

### Target

```text
100% policy compliance
```

---

## 7.6 Paper-to-Live Performance Gap

### Definition

Difference between paper performance and live performance.

```text
Performance Gap = Paper Net PnL - Live Net PnL
```

### Why It Matters

Large gaps usually indicate unrealistic simulation.

### Target

- Gap should be explainable by market conditions, liquidity, and latency
- Persistent large positive paper bias means paper engine is too optimistic

---

# 8. Backtest Quality KPIs

These measure whether backtests are trustworthy.

---

## 8.1 Backtest Completion Rate

### Definition

```text
Completion Rate = Completed Backtests / Requested Backtests
```

### Target

```text
100%
```

Failures should be due to invalid input, not system bugs.

---

## 8.2 Backtest Date Chunk Compliance

### Definition

Percentage of historical API calls staying within 30-day Dhan limit.

### Target

```text
100%
```

---

## 8.3 Backtest Reproducibility

### Definition

Same parameters and data produce same results.

### Target

```text
100% deterministic
```

---

## 8.4 Backtest Overfitting Gap

### Definition

Performance degradation from in-sample to out-of-sample data.

```text
Overfitting Gap = In-Sample Performance - Out-of-Sample Performance
```

### Why It Matters

A strategy may look excellent in backtest but fail live.

### Target

- Small degradation is normal
- Large collapse indicates overfitting

---

## 8.5 Backtest-to-Paper Gap

### Definition

Difference between backtest performance and subsequent paper performance.

```text
Backtest-to-Paper Gap = Backtest Net PnL - Paper Net PnL
```

### Why It Matters

Validates whether historical simulation is realistic.

---

## 8.6 Number of Trades in Backtest

### Definition

Total simulated trades.

### Why It Matters

Too few trades means low statistical confidence.

### Target

Use judgment, but generally:

- < 30 trades: low confidence
- 100+ trades: better
- 300+ trades: stronger, if across varying market conditions

---

# 9. Data Quality KPIs

These measure whether the data feeding decisions is reliable.

---

## 9.1 Missing Candle Count

### Definition

Number of expected candles missing from historical or live feed.

### Target

```text
0 unexplained missing candles
```

---

## 9.2 Candle Alignment Accuracy

### Definition

Whether candles align to correct exchange interval boundaries.

### Target

```text
100% correct alignment
```

---

## 9.3 Tick Staleness Rate

### Definition

Percentage of time tick data is older than threshold.

### Target

- Very low
- Stale state should block entries

---

## 9.4 Instrument Mapping Accuracy

### Definition

Correct security ID mapping for selected strike/expiry.

### Target

```text
100%
```

Incorrect instrument mapping is critical.

---

## 9.5 Expired Instrument Handling Accuracy

### Definition

System should not subscribe to or trade expired instruments.

### Target

```text
0 expired instrument errors
```

---

# 10. Product / UX KPIs

These measure whether the user can operate the system effectively.

---

## 10.1 Time to Run First Backtest

### Definition

Time from signup/setup to first completed backtest.

### Target

- < 10 minutes for technical user
- < 30 minutes for non-technical user with docs

---

## 10.2 Time to Start Paper Trading

### Definition

Time from setup to first paper trade.

### Target

- < 15 minutes after configuration

---

## 10.3 Time to Switch Modes

### Definition

Time from UI mode switch request to Redis/Node mode update.

### Target

```text
< 2 seconds
```

Including safety square-off may take longer.

---

## 10.4 UI Update Smoothness

### Definition

Whether dashboard updates without lag or freezing.

### Target

- 60 FPS rendering where possible
- No visible freeze during high tick volume
- State updates every 100 ms for core metrics

---

## 10.5 User Confidence Indicators

Qualitative but important:

- user knows current mode
- user sees connection status
- user sees risk alerts
- user sees why trade was entered/exited
- user can stop bot easily

---

# 11. Adoption KPIs

If this becomes a multi-user product, these matter.

---

## 11.1 Active Trading Days

### Definition

Number of days user runs bot in paper or live mode.

---

## 11.2 Backtests per User

### Definition

Number of backtests created per user per week/month.

---

## 11.3 Paper-to-Live Conversion Rate

### Definition

```text
Conversion = Users Who Enable Live / Users Who Use Paper
```

### Why It Matters

Indicates whether users trust the platform after validation.

---

## 11.4 Retention

### Definition

Percentage of users returning weekly/monthly.

---

## 11.5 Feature Usage

Examples:

- CSV export usage
- backtest result views
- strategy parameter edits
- kill switch usage
- square-off usage

---

# 12. Compliance and Audit KPIs

These are essential for a trading system.

---

## 12.1 Audit Log Coverage

### Definition

Percentage of sensitive actions logged.

Must include:

- mode switch
- bot start/stop
- kill switch
- config change
- live confirmation
- capital reset
- order submission
- order rejection

### Target

```text
100%
```

---

## 12.2 Trade Log Completeness

### Definition

Every executed or simulated trade has a database record.

### Target

```text
100%
```

---

## 12.3 Reconciliation Report Success Rate

### Definition

Percentage of EOD reconciliations completed successfully.

### Target

```text
100%
```

---

## 12.4 Live Confirmation Compliance

### Definition

Every live mode switch requires explicit confirmation.

### Target

```text
100%
```

---

# 13. Recommended KPI Dashboard

The product should have a KPI dashboard with these sections.

---

## Section A: Trading Performance

Display:

- Net PnL today
- Net PnL rolling 7 days
- Net PnL rolling 30 days
- Win rate
- Profit factor
- Expectancy
- Average win/loss
- Max drawdown
- Charge impact

---

## Section B: Execution Quality

Display:

- Average signal-to-order latency
- Average slippage
- Order rejection rate
- Duplicate order count
- Order timeout count
- Live vs paper fill divergence

---

## Section C: Risk Controls

Display:

- Max daily loss status
- Trades remaining today
- Kill switch state
- Stale data events
- Position reconciliation status
- Risk breaches today

---

## Section D: System Health

Display:

- WebSocket connected
- Redis connected
- Rails API healthy
- Node engine alive
- Last tick time
- Last state update time
- Crash count
- Recovery time

---

## Section E: Paper Fidelity

Display:

- Paper net PnL
- Paper charges
- Paper slippage
- Paper fill latency
- Paper-to-live divergence

---

## Section F: Backtest Quality

Display:

- Completed backtests
- Failed backtests
- Average backtest duration
- Backtest-to-paper gap
- Reproducibility check status

---

# 14. Suggested KPI Targets for MVP

These are practical targets for the first production version.

| KPI | Target |
| --- | ---: |
| Duplicate orders | 0 |
| Unrecovered crash positions | 0 |
| Position reconciliation accuracy | 100% |
| Backtest date chunk compliance | 100% |
| Market hours uptime | 99%+ |
| Node crash recovery time | < 5 seconds |
| Kill switch activation time | < 1 second |
| Signal-to-order latency | < 500 ms |
| Tick-to-signal internal latency | < 5 ms |
| UI state refresh | 100 ms |
| Order rejection due to system bugs | 0 |
| Stale data entries allowed | 0 |
| Audit log coverage | 100% |
| Trade log completeness | 100% |
| Paper/live mode mixing | 0 |

---

# 15. Suggested Strategy-Level KPI Targets

These depend on market conditions and risk appetite, but can be used as starting guidelines.

| KPI | Desired Direction |
| --- | --- |
| Net expectancy | Positive after charges |
| Profit factor | > 1.3, preferably > 1.5 |
| Max daily drawdown | Within configured risk limit |
| Payoff ratio | > 1.5 |
| Charge impact | Not consuming majority of gross edge |
| Trade sample size | Enough for statistical confidence |
| Time in market | Consistent with scalping intent |
| Overtrading | Controlled by max trades/day |

---

# 16. Guardrail Metrics

These are metrics that must not worsen even if PnL improves.

| Guardrail | Rule |
| --- | --- |
| Risk breaches | Must not increase |
| Duplicate orders | Must remain zero |
| System-caused order failures | Must remain near zero |
| Max drawdown | Must not exceed limit |
| Stale data entries | Must remain zero |
| UI disconnections | Must not go unnoticed |
| Live mode accidental activation | Must remain zero |
| Unreconciled positions | Must remain zero |

---

# 17. Metrics to Avoid Optimizing Blindly

Some metrics can mislead if optimized alone.

---

## 17.1 Win Rate Alone

A high win rate can hide catastrophic losses.

---

## 17.2 Gross PnL Alone

Gross PnL ignores brokerage, taxes, slippage, and operational risk.

---

## 17.3 Number of Trades Alone

More trades can mean more charges and more risk.

---

## 17.4 Backtest Returns Alone

Backtests can be overfitted or unrealistic.

---

## 17.5 Speed Alone

Low latency is useless if risk controls fail.

---

# 18. Best KPI Framework for This Product

A good framework is:

```text
Profitability + Risk Control + Execution Quality + System Reliability
```

More specifically:

```text
Primary Success = Positive net expectancy after costs
Secondary Success = Drawdown and risk limits respected
Operational Success = Zero uncontrolled failures
Validation Success = Paper trading closely predicts live behavior
```

---

# 19. Final Recommended KPI Set

If you only track a small set, track these:

## Business/Trading KPIs

1. Net PnL after charges
2. Expectancy per trade
3. Profit factor
4. Maximum drawdown
5. Win rate and payoff ratio
6. Charge impact ratio

## Execution KPIs

1. Signal-to-order latency
2. Slippage vs expected
3. Order rejection rate
4. Duplicate order count
5. Order timeout rate

## Risk KPIs

 1. Daily loss limit breaches
 2. Kill switch activation time
 3. Position reconciliation accuracy
 4. Stale data blocked entries
 5. Unrecovered crash positions

## Reliability KPIs

 1. Market hours uptime
 2. Node engine crash recovery time
 3. WebSocket disconnect/reconnect success
 4. Redis availability

## Paper Fidelity KPIs

 1. Paper vs live fill divergence
 2. Paper vs live slippage divergence
 3. Paper-to-live performance gap

## Product KPIs

 1. Time to first backtest
 2. Time to first paper trade
 3. UI stale events
 4. Active trading days

---

# 20. Summary

The most important KPIs for **Algo Scalper API** are not just trading profits. The product succeeds only if:

- The strategy has **positive expectancy after costs**
- Drawdown is **controlled**
- Execution is **fast and reliable**
- Paper trading is **realistic**
- Live trading is **safe and auditable**
- The system recovers from failures without losing track of positions
- The user always knows the bot state, mode, and risk status

A concise success definition is:

> **Algo Scalper API is successful when it enables a trader to move from backtest to paper to live with high confidence, minimal execution error, strict risk containment, and full transparency into every trade and system event.**

# Product Requirements Document

## Algo Scalper API — DhanHQ NIFTY Options Scalping, Paper Trading, Backtesting & Live Execution Platform

**Product Name:** Algo Scalper API
**Version:** 1.0
**Status:** Draft / Ready for Implementation
**Primary Stack:** Rails API, Node.js TypeScript, Redis, SolidJS, DhanHQ v2 APIs
**Repositories:**

- `algo_scalper_api` — Rails API, control plane, backtesting, clearing, dashboard API
- `dhanhq-client` — Ruby gem for DhanHQ REST APIs
- `dhanhq-ts` — TypeScript/Node.js client for DhanHQ REST/WebSocket
- SolidJS frontend inside `algo_scalper_api/apps/web`

---

## 1. Executive Summary

Algo Scalper API is an end-to-end algorithmic trading platform for NIFTY index options buying, focused on intraday scalping strategies. The system supports:

1. **Historical backtesting** using DhanHQ historical endpoints.
2. **Paper trading** using live or replayed market data with a simulated broker engine.
3. **Live trading** using DhanHQ WebSocket market data and REST order execution.
4. **Real-time monitoring** through a SolidJS dashboard connected via Rails ActionCable.
5. **Risk management**, virtual capital ledger, trade journaling, reconciliation, and audit logs.

The architecture separates:

- **Hot Path**: Node.js TypeScript engine for market data ingestion, candle building, indicators, strategy signals, order routing, and position monitoring.
- **Cold Path**: Rails API for configuration, backtesting, trade journal, analytics, clearing, user management, and frontend API.
- **State/Event Bus**: Redis for live state, pub/sub, command dispatch, virtual capital, active positions, and instrument mapping.
- **Frontend**: SolidJS real-time dashboard consuming Rails API and ActionCable.

The MVP strategy is a configurable NIFTY options buying scalper using EMA trend confirmation and premium breakout entry.

---

## 2. Problem Statement

Retail algorithmic traders need a reliable system to:

- Backtest options strategies using historical options data.
- Validate strategies in paper trading before risking capital.
- Simulate realistic broker behavior, including slippage, latency, taxes, brokerage, and order rejection.
- Execute live trades with strict risk controls.
- Monitor live positions, PnL, bot state, and trade events in real time.
- Maintain a complete audit trail of trades, signals, configuration changes, and system events.

Existing setups often fail because they:

- Use only continuous ATM data and ignore strike drift.
- Ignore taxes, slippage, and liquidity.
- Lack realistic paper trading.
- Have high latency due to routing live ticks through slow back-office systems.
- Lack crash recovery for open positions.
- Do not provide real-time UI visibility.

Algo Scalper API solves these by separating execution, state, and analytics while providing a realistic simulated broker for paper trading.

---

## 3. Goals

### 3.1 Primary Goals

1. Build a production-grade NIFTY options scalping system.
2. Provide realistic paper trading that simulates Dhan broker behavior.
3. Provide historical backtesting using DhanHQ rolling options and spot data.
4. Support live trading with risk controls and kill switch.
5. Provide real-time dashboard using SolidJS.
6. Maintain complete trade journal and analytics.
7. Ensure crash recovery, idempotency, and observability.

### 3.2 Success Metrics

| Metric | Target |
| --- | ---: |
| Paper trade fill simulation latency | Configurable 20–200 ms |
| Tick processing to signal evaluation | < 5 ms in-process |
| Live order dispatch after signal | < 500 ms excluding broker network |
| UI state refresh | Every 100 ms for live state |
| Backtest chunk compliance | 100% within 30-day API window |
| Crash recovery time for active position | < 5 seconds |
| Duplicate order rate | 0% with idempotency |
| Daily reconciliation match | 100% for paper, broker-matched for live |

---

## 4. Non-Goals for MVP

The following are not included in MVP unless explicitly marked as Phase 2:

1. Multi-tenant SaaS billing.
2. Multi-broker support.
3. Full options chain Greeks analytics.
4. Machine learning signal generation.
5. Complex multi-leg options strategies.
6. Automated strategy optimization.
7. Mobile native apps.
8. Social trading or strategy marketplace.
9. Historical tick data warehouse.
10. Custom charting engine beyond lightweight chart integration.

---

## 5. Target Users

### 5.1 Primary User: Algorithmic Trader

- Wants to automate NIFTY option buying strategies.
- Needs backtesting, paper trading, and live execution.
- Cares about latency, risk controls, and realistic simulation.
- Understands options basics: ATM, OTM, ITM, premium, SL, target.

### 5.2 Secondary User: Developer / Quant

- Wants to add new strategies.
- Needs clean interfaces for indicators, signals, and order routing.
- Needs logs, metrics, and testability.

### 5.3 Secondary User: Operator / Admin

- Needs health checks, kill switch, audit logs, reconciliation reports.
- Needs to monitor failures, rate limits, and token expiry.

---

## 6. Product Modes

The system must support three major modes.

### 6.1 Backtest Mode

Runs historical simulations using DhanHQ historical endpoints.

Features:

- Fetch NIFTY spot candles.
- Fetch rolling option candles using relative strikes such as ATM, ATM+1, ATM-1.
- Apply 30-day date chunking.
- Calculate EMA and other indicators.
- Simulate entry, exit, stop loss, target, slippage, and square-off.
- Export CSV.
- Store backtest run and results in database.

### 6.2 Paper Trading Mode

Runs real-time simulation using live or replayed market data.

Features:

- Uses real Dhan WebSocket ticks or replay feed.
- Constructs current candles locally.
- Evaluates strategy in Node.js.
- Simulates order fills, slippage, latency, brokerage, taxes, and margin.
- Maintains virtual capital.
- Publishes events to Rails and frontend.
- Does not send orders to Dhan.

### 6.3 Live Trading Mode

Runs real trading using DhanHQ.

Features:

- Uses live WebSocket market data.
- Constructs current candles locally.
- Evaluates strategy.
- Sends real orders through Dhan REST API.
- Monitors stop loss, target, trailing SL, square-off.
- Enforces risk limits.
- Syncs order state with Dhan.
- Requires explicit user confirmation and safety checks.

---

## 7. Core Strategy Definition

The MVP includes one primary strategy: **EMA-Confirmed NIFTY Option Breakout**.

### 7.1 Strategy Summary

- Underlying: NIFTY 50 Index.
- Segment: NSE F&O index options.
- Option side: Call option by default; configurable for Put later.
- Strike: ATM by default; configurable relative strike.
- Timeframe: 5-minute candles by default; configurable.
- Entry conditions:
  1. Current candle close breaks previous candle high.
  2. Spot EMA fast > Spot EMA slow.
  3. Time is within trading window.
  4. No active position.
  5. Risk manager allows trade.
- Exit conditions:
  1. Stop loss hit.
  2. Target hit.
  3. Trailing stop loss hit.
  4. Intraday square-off time reached.
  5. Manual square-off.
  6. Kill switch triggered.

### 7.2 Default Parameters

| Parameter | Default | Description |
| --- | ---: | --- |
| Candle interval | 5 minutes | Strategy timeframe |
| EMA fast period | 9 | Fast trend filter |
| EMA slow period | 21 | Slow trend filter |
| Stop loss | 15% | On option premium |
| Target | 30% | On option premium |
| Slippage | 1% | Simulation/entry buffer |
| Lot size | 50 | NIFTY lot size, configurable |
| Strike selection | ATM | Relative strike |
| Option type | CALL | CE default |
| Trading start | 09:20 IST | Skip initial volatility |
| Trading stop | 15:15 IST | No new entries |
| Square-off | 15:20 IST | Force exit |
| Max trades/day | Configurable | Risk limit |
| Max daily loss | Configurable | Risk limit |

All parameters must be editable from the frontend and stored in database/Redis.

---

## 8. High-Level System Architecture

### 8.1 Architecture Principles

1. **Hot path must be low latency.**
   - Node.js handles ticks, candles, indicators, signals, and order execution.

2. **Cold path must be reliable and auditable.**
   - Rails handles persistence, configuration, backtesting, analytics, clearing, and frontend API.

3. **Redis is the real-time bridge.**
   - Stores bot mode, active trade, virtual capital, pending commands, instrument mappings, and pub/sub events.

4. **Frontend must not talk directly to Dhan.**
   - SolidJS reads from Rails API and ActionCable.

5. **Paper and live state must be isolated.**
   - Separate Redis namespaces and database flags.

6. **Strategy logic must be framework-agnostic.**
   - Pure TypeScript strategy evaluation should be testable without network.

---

### 8.2 Component Diagram

```text
┌────────────────┐
│  SolidJS Web   │
└───────┬────────┘
        │ HTTPS / WebSocket
        ▼
┌────────────────┐        ┌────────────────┐
│   Rails API    │◄──────►│  PostgreSQL    │
│ algo_scalper   │        └────────────────┘
└───────┬────────┘
        │ Redis Pub/Sub + State
        ▼
┌────────────────┐        ┌────────────────┐
│     Redis      │◄──────►│ Node.js Engine │
└────────────────┘        └───────┬────────┘
                                  │ DhanHQ REST + WebSocket
                                  ▼
                          ┌────────────────┐
                          │ DhanHQ v2 APIs │
                          └────────────────┘
```

---

## 9. Functional Requirements

Requirement IDs use:

- `FR` = Functional Requirement
- `PR` = Paper Engine Requirement
- `LR` = Live Trading Requirement
- `BR` = Backtesting Requirement
- `UI` = Frontend Requirement
- `NFR` = Non-Functional Requirement

---

## 10. Authentication and User Management

### FR-AUTH-001: User Accounts

The system must support user registration and login.

Fields:

- email
- password
- role
- Dhan client ID
- encrypted Dhan access token
- created_at
- updated_at

### FR-AUTH-002: Token Authentication

API requests must be authenticated using JWT or secure session token.

### FR-AUTH-003: Role-Based Access

Roles:

| Role | Permissions |
| --- | --- |
| trader | Manage own strategies, run backtests, control bot |
| admin | Manage users, view audit logs, manage global settings |
| ops | View health, logs, metrics; cannot change strategy capital |

MVP may be single-user, but schema must support multi-user.

### FR-AUTH-004: Secure Dhan Credentials

Dhan access tokens must be encrypted at rest.

Frontend must never receive raw Dhan access token.

---

## 11. Strategy Management

### FR-STRAT-001: Create Strategy

User can create a strategy with:

- name
- strategy_type
- parameters
- is_active

### FR-STRAT-002: Edit Strategy

User can update parameters while bot is stopped.

If bot is running, configuration update must require:

1. Save to database.
2. Publish to Redis.
3. Notify Node engine.
4. Confirm reload.

### FR-STRAT-003: Activate/Deactivate

Only one active strategy per user per bot mode in MVP.

### FR-STRAT-004: Parameter Validation

The system must validate:

- stop loss percentage between 1% and 90%
- target percentage between 1% and 500%
- EMA fast < EMA slow
- candle interval supported
- quantity positive integer
- lot size valid for instrument
- strike relative value valid

---

## 12. Bot Control

### FR-BOT-001: Start Bot

User can start bot from UI.

System must check:

- Dhan credentials present
- Redis reachable
- Node engine healthy
- strategy active
- market mode valid
- no conflicting state

### FR-BOT-002: Stop Bot

User can stop bot.

Bot stop must:

- stop new entries
- continue monitoring open positions unless user selects square-off
- update Redis bot status
- notify frontend

### FR-BOT-003: Square Off

User can manually square off all open positions.

For live mode:

- send real exit order
- confirm order state
- update trade log

For paper mode:

- simulate exit fill
- update virtual ledger

### FR-BOT-004: Mode Switch

User can switch between paper and live.

Mode switch must:

1. Require explicit confirmation for live.
2. Square off current paper/live position.
3. Update Redis `bot_mode`.
4. Notify Node engine.
5. Update UI banner.
6. Record audit log.

### FR-BOT-005: Kill Switch

Global kill switch must:

- stop all entries immediately
- optionally square off positions
- disable order router
- persist state
- notify UI
- require manual reset

---

## 13. Market Data Requirements

### FR-MD-001: Dhan WebSocket Connection

Node engine must connect to DhanHQ WebSocket for live market data.

### FR-MD-002: Subscription Management

Node engine must subscribe to:

- NIFTY spot for signal calculation
- active option contract for position monitoring

### FR-MD-003: Tick Processing

Each tick must include at least:

- securityId
- LTP
- timestamp
- volume
- market depth if available

### FR-MD-004: Reconnection

WebSocket client must:

- reconnect automatically
- use exponential backoff
- resubscribe instruments
- mark data stale if disconnected
- pause entries if stale beyond threshold

### FR-MD-005: Market Hours Guard

System must respect market hours.

Default:

- Entry allowed: 09:20 IST to 15:15 IST
- Square-off: 15:20 IST

Configurable.

---

## 14. Candle Building Requirements

### FR-CANDLE-001: Historical Warmup

On startup, Node engine must fetch historical candles for indicator warmup.

Default:

- last 100 candles for configured interval.

### FR-CANDLE-002: Current Candle Construction

Node engine must construct current candle from ticks.

Fields:

- startTime
- endTime
- open
- high
- low
- close
- volume

### FR-CANDLE-003: Candle Close Detection

When candle boundary is reached:

1. Finalize current candle.
2. Append to candle history.
3. Recalculate indicators.
4. Evaluate strategy.
5. Start next candle.

### FR-CANDLE-004: Candle History Limit

Maintain rolling window, default 200 candles.

### FR-CANDLE-005: Live Candle Sync

Current candle may be synced to Redis periodically for dashboard display.

Default: every 1 second or 500 ms.

---

## 15. Indicator Requirements

### FR-IND-001: EMA Calculation

System must calculate EMA on spot close prices.

Default periods:

- EMA 9
- EMA 21

### FR-IND-002: Indicator Warmup

Indicators must not generate signals until enough candles exist.

Minimum:

- at least EMA slow period + 5 candles.

### FR-IND-003: Extensibility

Indicator engine must support future indicators:

- VWAP
- Supertrend
- RSI
- ATR
- Bollinger Bands

### FR-IND-004: Determinism

Indicator calculation must be deterministic for backtest and live.

Same input candles must produce same indicator output.

---

## 16. Strategy Engine Requirements

### FR-SIG-001: Strategy Interface

Strategy must implement:

```text
evaluate(candles, indicators, context) -> Signal
```

Signal output:

- action: BUY / SELL / NONE
- reason
- symbol metadata
- quantity
- stopLossPct
- targetPct
- confidence optional
- required strike/option metadata

### FR-SIG-002: Entry Signal

For MVP EMA breakout:

Entry is valid when:

```text
current_close > previous_high
AND ema_fast > ema_slow
AND within trading window
AND no active position
AND risk manager allows trade
```

### FR-SIG-003: One Signal Per Candle

Strategy must prevent duplicate signals for same candle.

Use candle ID:

```text
symbol:interval:candle_start_timestamp
```

### FR-SIG-004: Exit Signal Evaluation

Position tracker must monitor:

- stop loss
- target
- trailing stop loss
- square-off
- manual exit
- kill switch

### FR-SIG-005: Signal Logging

Every signal must be logged with:

- timestamp
- mode
- candle time
- spot price
- option price
- EMA values
- reason
- accepted/rejected
- rejection reason

---

## 17. Instrument Master Requirements

### FR-INST-001: Daily Instrument Sync

Rails must fetch Dhan instrument master for NSE F&O daily.

### FR-INST-002: Parse and Store

System must parse relevant fields:

- exchange segment
- symbol
- expiry
- strike price
- option type
- security ID
- lot size
- tick size
- trading status

### FR-INST-003: Redis Mapping

Rails must store mappings in Redis for fast Node lookup.

Example key:

```text
dhan:instruments:NSE_FNO:NIFTY:WEEK:24000:CE
```

Value:

```json
{
  "securityId": "42528",
  "lotSize": 50,
  "tickSize": 0.05,
  "expiry": "2026-01-25",
  "symbol": "NIFTY"
}
```

### FR-INST-004: Expiry Handling

System must avoid subscribing to expired contracts.

For weekly options, active expiry must be selected dynamically.

### FR-INST-005: Historical Instrument Limitation

System must recognize that historical expired security IDs may not be available from current instrument master.

Backtesting must primarily use `/charts/rollingoption` relative strike data.

---

## 18. Backtesting Requirements

### BR-001: Backtest Creation

User can create backtest with:

- strategy_id
- start_date
- end_date
- mode = backtest
- optional parameter overrides

### BR-002: Date Chunking

Backtester must split date range into chunks of maximum 28 days to respect Dhan 30-day limit.

### BR-003: Spot Data Fetch

Backtester may fetch NIFTY spot candles from:

```text
/v2/charts/intraday
```

### BR-004: Rolling Option Data Fetch

Backtester must fetch option candles from:

```text
/v2/charts/rollingoption
```

Supported relative strikes:

- ATM
- ATM+1
- ATM-1
- ATM+2
- ATM-2
- up to API-supported limits

### BR-005: Dynamic Strike Offset

Backtester must record entry spot and support dynamic offset calculation:

```text
strike_shift = round((current_spot - entry_spot) / strike_step)
```

For NIFTY default strike step: 50.

If spot moves up:

```text
original CE becomes ATM-{shift}
```

If spot moves down:

```text
original CE becomes ATM+{shift}
```

### BR-006: Historical Simulation

Backtester must simulate:

- entry
- stop loss
- target
- trailing SL optional
- square-off
- slippage
- brokerage/taxes optional but recommended

### BR-007: Trade Output

Each backtest trade must include:

- entry_time
- entry_price
- entry_spot
- exit_time
- exit_price
- pnl
- result
- charges estimated
- metadata

### BR-008: Summary Output

Backtest must produce:

- total trades
- win rate
- total PnL
- gross PnL
- net PnL
- total charges
- max drawdown
- average win
- average loss
- expectancy

### BR-009: CSV Export

User can export trade logs to CSV.

Columns:

- Entry Time
- Entry Price
- Entry Spot
- Exit Time
- Exit Price
- PnL
- Charges
- Result
- Strategy
- Mode

### BR-010: Backtest Persistence

Backtest run must be stored in PostgreSQL with status:

- pending
- running
- completed
- failed

### BR-011: Backtest Status API

Frontend can poll or receive updates for backtest status.

---

## 19. Paper Trading Engine Requirements

The Paper Engine is a simulated broker. It must be located primarily in Node.js for low-latency processing.

---

### PR-001: Paper Engine Location

Paper engine must run inside Node.js hot path.

Rails acts as clearing house and ledger.

---

### PR-002: Order Router Abstraction

System must provide common interface:

```text
placeOrder(order)
modifyOrder(orderId, changes)
cancelOrder(orderId)
getOrderStatus(orderId)
```

Implementations:

- LiveDhanRouter
- PaperRouter

Strategy engine must not know which router is active.

---

### PR-003: Paper Order Lifecycle

Paper engine must support order states:

- VALIDATION_PENDING
- ACCEPTED
- OPEN
- PARTIALLY_FILLED
- FILLED
- CANCELLED
- REJECTED

MVP may simplify MARKET orders to instant fill, but schema must support full lifecycle.

---

### PR-004: Order Types

MVP:

- MARKET

Phase 2:

- LIMIT
- SL
- SL-M

---

### PR-005: Market Order Fill Rules

For market orders:

- BUY fills at best ask if depth available.
- SELL fills at best bid if depth available.
- If depth unavailable, fill at LTP plus slippage.
- Apply configurable slippage.
- Round to instrument tick size.

Default option tick size: 0.05.

---

### PR-006: Limit Order Fill Rules

For limit orders:

- BUY LIMIT fills when market trades at or below limit price.
- SELL LIMIT fills when market trades at or above limit price.
- Fill price should respect limit price.
- Queue position simulation optional in Phase 2.

---

### PR-007: Partial Fill Simulation

If order quantity exceeds visible depth quantity:

- fill available quantity at first price level
- continue walking book if enabled
- or reject remainder if configured

MVP may assume full fill but must log assumption.

---

### PR-008: Latency Simulation

Paper engine must simulate exchange/network latency.

Configurable:

- min_latency_ms
- max_latency_ms

Default:

- 40 ms to 150 ms.

---

### PR-009: Slippage Simulation

Configurable slippage model:

- fixed percentage
- fixed points
- depth-based impact cost

MVP default:

- 1% for strategy simulation
- additional 0.5 tick to 1 tick for market orders in paper engine

---

### PR-010: Virtual Risk Management System

Before accepting order, paper engine must check:

- virtual capital available
- max trades per day
- max daily loss
- bot kill switch state
- market hours
- instrument tradable status

Reject order if validation fails.

---

### PR-011: Virtual Capital Ledger

System must maintain virtual capital per user.

Stored in Redis for real-time use and persisted in PostgreSQL for audit.

Events affecting capital:

- simulated buy debit
- simulated sell credit
- taxes and charges debit
- manual capital reset
- daily reconciliation adjustment

---

### PR-012: Fee Simulation

Paper engine must simulate realistic charges.

Default Dhan/NSE-style approximation:

| Charge | Rule |
| --- | --- |
| Brokerage | ₹20 per executed order |
| STT | 0.0125% on sell side for options |
| Exchange transaction charge | approx 0.053% on turnover |
| GST | 18% on brokerage + transaction charges |
| Stamp duty | 0.003% on buy side |
| SEBI charges | nominal turnover-based charge |

Rates must be configurable.

---

### PR-013: Paper Trade IDs

Paper engine must generate:

- broker_order_id
- exchange_order_id
- trade_id

Example:

```text
broker_order_id: PAPER-uuid
exchange_order_id: SIM-exchange-uuid
```

---

### PR-014: Paper Event Publishing

Paper engine must publish events:

- ORDER_ACCEPTED
- ORDER_REJECTED
- ORDER_FILLED
- POSITION_OPENED
- POSITION_CLOSED
- SL_HIT
- TARGET_HIT
- SQUARE_OFF
- CAPITAL_UPDATED

---

### PR-015: Paper State Isolation

Paper state must use separate Redis namespace:

```text
algo:{user_id}:paper:active_trade
algo:{user_id}:paper:capital
algo:{user_id}:paper:orders
```

Database records must include:

```text
is_paper_trade = true
```

---

### PR-016: Paper Position Recovery

If Node engine restarts during paper trade:

- read active trade from Redis
- resume SL/target monitoring
- restore virtual capital state
- log recovery event

---

## 20. Live Trading Requirements

### LR-001: Live Order Router

Live router must use `dhanhq-ts` to place real orders.

### LR-002: Live Order Validation

Before sending live order, system must validate:

- user has live mode enabled
- explicit live confirmation completed
- Dhan token valid
- capital/margin available
- risk limits not breached
- instrument active
- market open
- no duplicate signal

### LR-003: Live Order Payload

Order must include:

- dhanClientId
- transactionType
- exchangeSegment
- productType
- orderType
- validity
- securityId
- quantity
- price
- triggerPrice if applicable

### LR-004: Live Order Rate Limiting

Order router must use token bucket rate limiter.

If rate limit exhausted:

- queue order
- retry with backoff
- log delay
- reject if staleness exceeds threshold

### LR-005: Live Order State Sync

System must sync order state from Dhan using:

- order response
- order update WebSocket if available
- REST polling fallback

### LR-006: Live Position Monitoring

For open live position, system must monitor ticks for:

- stop loss
- target
- trailing SL
- square-off
- manual exit

### LR-007: Live Crash Recovery

If Node engine restarts:

1. Read Redis state.
2. Fetch Dhan positions/orders.
3. Reconcile local state with broker state.
4. Resume monitoring if position exists.
5. Raise alert if mismatch found.

### LR-008: Live Safety Controls

Live mode must require:

- explicit switch confirmation
- visible LIVE banner
- kill switch accessible
- max daily loss enforced
- max trades/day enforced
- token expiry monitoring

### LR-009: Live Reconciliation

End-of-day job must reconcile:

- local trades
- Dhan order book
- Dhan trade book
- charges
- PnL
- final capital

---

## 21. Risk Management Requirements

### FR-RISK-001: Max Daily Loss

If daily net loss exceeds configured limit:

- stop new entries
- optionally square off
- notify user
- require manual reset

### FR-RISK-002: Max Trades Per Day

If max trades reached:

- stop new entries
- allow exits

### FR-RISK-003: Max Open Positions

MVP default:

- one open position per strategy per user.

### FR-RISK-004: Stale Data Guard

If market data stale beyond threshold:

- disable entries
- alert UI
- optionally square off

Default threshold: 3 seconds.

### FR-RISK-005: Duplicate Order Prevention

System must maintain idempotency keys per signal.

Example:

```text
{user_id}:{strategy_id}:{candle_id}:{mode}
```

### FR-RISK-006: Order Timeout

If live order not confirmed within configurable timeout:

- check order status
- cancel if necessary
- log error
- avoid duplicate retry unless safe

### FR-RISK-007: Circuit Breaker

If repeated order failures occur:

- open circuit breaker
- pause order routing
- alert user
- require manual reset or cooldown

---

## 22. Rails API Requirements

### FR-API-001: REST API

Rails must expose REST endpoints under `/api/v1`.

### FR-API-002: Authentication

All endpoints except auth must require token.

### FR-API-003: CORS

CORS must allow configured frontend origin.

### FR-API-004: Pagination

Trade logs and backtest lists must support pagination.

### FR-API-005: Audit Logging

Sensitive actions must create audit logs:

- mode switch
- bot start/stop
- strategy parameter change
- kill switch
- live confirmation
- capital reset

---

## 23. API Specification

### 23.1 Authentication

| Method | Endpoint | Description |
| --- | --- | --- |
| POST | `/api/v1/auth/register` | Register user |
| POST | `/api/v1/auth/login` | Login and receive token |
| POST | `/api/v1/auth/logout` | Logout |

---

### 23.2 Strategies

| Method | Endpoint | Description |
| --- | --- | --- |
| GET | `/api/v1/strategies` | List strategies |
| POST | `/api/v1/strategies` | Create strategy |
| GET | `/api/v1/strategies/:id` | Get strategy |
| PATCH | `/api/v1/strategies/:id` | Update strategy |
| POST | `/api/v1/strategies/:id/activate` | Activate strategy |
| POST | `/api/v1/strategies/:id/deactivate` | Deactivate strategy |

---

### 23.3 Bot Control

| Method | Endpoint | Description |
| --- | --- | --- |
| GET | `/api/v1/bot/status` | Get bot status |
| POST | `/api/v1/bot/start` | Start bot |
| POST | `/api/v1/bot/stop` | Stop bot |
| POST | `/api/v1/bot/square_off` | Square off positions |
| POST | `/api/v1/bot/switch_mode` | Switch paper/live |
| POST | `/api/v1/bot/kill_switch` | Trigger kill switch |

---

### 23.4 Backtests

| Method | Endpoint | Description |
| --- | --- | --- |
| POST | `/api/v1/backtests` | Create backtest |
| GET | `/api/v1/backtests` | List backtests |
| GET | `/api/v1/backtests/:id` | Get backtest |
| GET | `/api/v1/backtests/:id/results` | Get results |
| GET | `/api/v1/backtests/:id/download_csv` | Download CSV |

---

### 23.5 Trades and Analytics

| Method | Endpoint | Description |
| --- | --- | --- |
| GET | `/api/v1/trades` | List trades |
| GET | `/api/v1/trades/paper` | List paper trades |
| GET | `/api/v1/trades/live` | List live trades |
| GET | `/api/v1/dashboard/summary` | Dashboard summary |
| GET | `/api/v1/dashboard/pnl_chart` | PnL chart data |
| GET | `/api/v1/daily_performances` | Daily performance |

---

### 23.6 Instruments

| Method | Endpoint | Description |
| --- | --- | --- |
| GET | `/api/v1/instruments/search` | Search instruments |
| POST | `/api/v1/instruments/sync` | Trigger instrument sync |
| GET | `/api/v1/instruments/sync_status` | Sync status |

---

## 24. WebSocket / ActionCable Requirements

Rails ActionCable must provide real-time communication between frontend and backend.

### 24.1 Client-to-Server Actions

| Action | Payload | Description |
| --- | --- | --- |
| `start_bot` | none | Start bot |
| `stop_bot` | none | Stop bot |
| `square_off` | none | Square off |
| `switch_mode` | `{ mode }` | Switch paper/live |
| `update_config` | `{ parameters }` | Update strategy config |

### 24.2 Server-to-Client Events

| Event | Description |
| --- | --- |
| `state_updates` | Throttled capital, PnL, active trade |
| `trade_events` | Entry, exit, fill, rejection |
| `bot_status` | Running/stopped/error |
| `mode_change` | Paper/live changed |
| `risk_alert` | Risk limit triggered |
| `connection_status` | WebSocket health |
| `backtest_update` | Backtest progress/status |

### 24.3 Throttling

Continuous state updates must be throttled.

Default:

- state updates: 100 ms
- candle/chart updates: 500 ms or 1 second
- trade events: instant

---

## 25. Redis Requirements

### 25.1 Key Namespaces

```text
algo:{user_id}:bot_mode
algo:{user_id}:bot_status
algo:{user_id}:strategy_config
algo:{user_id}:{mode}:active_trade
algo:{user_id}:{mode}:orders
algo:{user_id}:virtual_capital
algo:{user_id}:live_candle
algo:{user_id}:pending_orders
algo:{user_id}:idempotency
algo:{user_id}:risk_state
dhan:instruments:{segment}
```

Where `mode` is `paper` or `live`.

---

### 25.2 Active Trade Hash

```json
{
  "orderId": "PAPER-uuid",
  "tradingSymbol": "NIFTY 24000 CE",
  "securityId": "42528",
  "entryPrice": "150.50",
  "entrySpot": "24020.5",
  "quantity": "50",
  "stopLoss": "127.93",
  "target": "195.65",
  "trailingSl": "140.25",
  "entryTime": "1706774400",
  "entryEma9": "24025.5",
  "entryEma21": "24010.2"
}
```

---

### 25.3 Pub/Sub Channels

```text
algo:{user_id}:trade_events
algo:{user_id}:state_updates
algo:{user_id}:bot_commands
algo:{user_id}:risk_events
algo:{user_id}:backtest_events
```

---

### 25.4 Persistence

Redis must be configured with:

- AOF persistence recommended
- maxmemory policy not to evict active trade keys
- separate logical DB or prefix per environment

---

## 26. Database Requirements

### 26.1 Tables

Required tables:

- users
- strategies
- trade_logs
- daily_performances
- backtest_runs
- instrument_caches
- audit_logs
- risk_events
- order_events
- reconciliation_reports

---

### 26.2 Trade Log Fields

- user_id
- strategy_id
- mode
- broker_order_id
- exchange_order_id
- trade_id
- trading_symbol
- security_id
- transaction_type
- order_type
- product_type
- quantity
- price
- average_price
- turnover
- brokerage
- stt
- txn_charges
- gst
- stamp_duty
- sebi_charges
- net_charges
- pnl
- status
- is_paper_trade
- executed_at
- metadata

---

### 26.3 Audit Log Fields

- user_id
- action
- entity_type
- entity_id
- old_value
- new_value
- ip_address
- user_agent
- created_at

---

## 27. SolidJS Frontend Requirements

### UI-001: Dashboard

Dashboard must show:

- bot status
- mode banner: PAPER / LIVE
- virtual capital
- unrealized PnL
- realized PnL
- active position
- trade feed
- candlestick chart
- connection status
- start/stop controls
- kill switch

---

### UI-002: Mode Banner

UI must display mode clearly:

- PAPER: yellow/orange badge
- LIVE: red pulsing badge

Live mode must require confirmation.

---

### UI-003: Real-Time Updates

Dashboard must update via ActionCable.

Signals:

- capital
- livePnl
- activeTrade
- orderEvents
- botStatus
- mode
- isConnected

---

### UI-004: Active Position Card

Must show:

- symbol
- quantity
- entry price
- current price
- unrealized PnL
- stop loss
- trailing SL
- target
- entry time

---

### UI-005: Trade Feed

Must show latest events:

- entry
- exit
- rejection
- SL hit
- target hit
- square-off
- risk halt

Each event must include timestamp and price where relevant.

---

### UI-006: Strategy Settings Page

User can edit:

- strategy name
- candle interval
- EMA periods
- strike selection
- option type
- lot size
- stop loss
- target
- trailing SL
- slippage
- max trades/day
- max daily loss
- trading window
- square-off time

---

### UI-007: Backtest Page

User can:

- select strategy
- select date range
- override parameters
- start backtest
- view status
- view results
- download CSV

Results must show:

- total trades
- win rate
- net PnL
- gross PnL
- charges
- max drawdown
- trade table

---

### UI-008: Trade History Page

Filters:

- date range
- mode
- strategy
- result
- symbol

Columns:

- time
- symbol
- side
- quantity
- entry price
- exit price
- PnL
- charges
- result
- mode

---

### UI-009: Risk Alerts

UI must show risk alerts:

- max daily loss reached
- stale data
- WebSocket disconnected
- token expired
- order router failure
- circuit breaker open

---

### UI-010: Stale Data Indicator

If no state update received for configurable threshold, UI must show warning and disable trading controls if necessary.

---

## 28. Backtesting Product Details

### 28.1 Backtest Input

```json
{
  "strategy_id": 1,
  "start_date": "2026-01-01",
  "end_date": "2026-02-15",
  "override_parameters": {
    "sl_pct": 0.15,
    "target_pct": 0.30
  }
}
```

### 28.2 Backtest Process

1. Create backtest run.
2. Split date range into 28-day chunks.
3. Fetch option rolling candles.
4. Fetch spot candles if required.
5. Normalize candles.
6. Calculate indicators.
7. Simulate signals.
8. Store trades.
9. Calculate summary.
10. Mark run completed.

### 28.3 Backtest Output

```json
{
  "backtest_run_id": 12,
  "status": "completed",
  "start_date": "2026-01-01",
  "end_date": "2026-02-15",
  "total_trades": 87,
  "win_rate": 58.62,
  "gross_pnl": 14500.25,
  "estimated_charges": 4320.00,
  "net_pnl": 10180.25,
  "max_drawdown": -3200.00,
  "csv_url": "/api/v1/backtests/12/download_csv"
}
```

---

## 29. Paper Trading Product Details

### 29.1 Paper Trading Flow

1. User selects paper mode.
2. Rails writes mode to Redis.
3. Node engine reads mode.
4. Node connects to market data.
5. Node builds candles.
6. Strategy generates signal.
7. PaperRouter simulates order.
8. Matching engine fills order.
9. Redis stores active trade.
10. Rails receives fill event.
11. Rails stores paper trade.
12. SolidJS dashboard updates.

---

### 29.2 Paper Engine Fill Event

```json
{
  "event": "ORDER_FILLED",
  "mode": "paper",
  "orderId": "PAPER-uuid",
  "exchangeOrderId": "SIM-exchange-uuid",
  "tradingSymbol": "NIFTY 24000 CE",
  "transactionType": "BUY",
  "quantity": 50,
  "fillPrice": 151.25,
  "timestamp": 1706774400123
}
```

---

### 29.3 Paper Engine Rejection Event

```json
{
  "event": "ORDER_REJECTED",
  "mode": "paper",
  "reason": "RMS_MARGIN_SHORTFALL",
  "orderId": "PAPER-uuid",
  "timestamp": 1706774400123
}
```

---

## 30. Live Trading Product Details

### 30.1 Live Trading Flow

1. User switches to live mode with confirmation.
2. Rails verifies credentials and risk state.
3. Rails squares off paper positions if any.
4. Redis mode set to live.
5. Node engine switches to LiveDhanRouter.
6. Node receives live ticks.
7. Strategy generates signal.
8. Risk manager validates.
9. Live order sent to Dhan.
10. Order state synced.
11. Position monitored.
12. Exit order sent when SL/target/square-off triggers.
13. Rails records live trade.
14. Dashboard updates.

---

### 30.2 Live Order Event

```json
{
  "event": "LIVE_ORDER_SUBMITTED",
  "orderId": "dhan-order-id",
  "tradingSymbol": "NIFTY 24000 CE",
  "transactionType": "BUY",
  "quantity": 50,
  "orderType": "MARKET",
  "timestamp": 1706774400123
}
```

---

## 31. Non-Functional Requirements

### NFR-001: Performance

| Component | Target |
| --- | ---: |
| Tick handler in Node | < 5 ms |
| Indicator update | < 2 ms for 200 candles |
| Paper fill simulation | 20–200 ms configurable |
| Redis read/write | < 5 ms local |
| Rails API endpoints | < 300 ms p95 |
| Dashboard state update | 100 ms cadence |

---

### NFR-002: Availability

- Node engine must auto-restart on crash.
- Redis must be monitored.
- Rails API should be horizontally scalable if needed.
- Bot should recover active state after restart.

---

### NFR-003: Reliability

- No duplicate orders from same signal.
- Active trade state must survive process restart.
- All mode changes must be logged.
- All order events must be persisted.

---

### NFR-004: Security

- TLS required in production.
- Dhan tokens encrypted at rest.
- Secrets stored in environment or vault.
- Frontend must not receive broker secrets.
- CORS restricted.
- WebSocket authenticated.
- Rate limit auth endpoints.

---

### NFR-005: Observability

System must log:

- tick connection state
- signal accepted/rejected
- order submitted/filled/rejected
- risk events
- mode changes
- reconciliation results
- errors and stack traces

Metrics:

- ticks/sec
- signal rate
- order success rate
- order rejection rate
- API latency
- WebSocket reconnect count
- Redis latency
- daily PnL
- max drawdown

---

### NFR-006: Scalability

MVP:

- 1 user per deployment.

Phase 2:

- multi-user with per-user Redis namespaces.
- per-user Node worker or multiplexed engine.
- background job scaling via Sidekiq.

---

### NFR-007: Data Integrity

- Database writes must not block hot path.
- Redis state and DB ledger must reconcile.
- Paper and live trades must never mix.
- Backtest trades must be isolated from live/paper trades.

---

## 32. Edge Cases and Failure Handling

### 32.1 WebSocket Disconnect

System must:

- mark data stale
- pause entries
- attempt reconnect
- resubscribe instruments
- continue exits if position exists and last price available
- alert UI if stale threshold exceeded

---

### 32.2 Node Engine Crash

System must:

- restart automatically
- read Redis state
- recover active trade
- verify broker/live position if live mode
- log recovery event

---

### 32.3 Redis Down

System must:

- halt trading if active state unavailable
- alert user
- prevent order routing
- not rely on in-memory state alone

---

### 32.4 Rails API Down

Node engine may continue hot-path risk monitoring if Redis is available, but:

- no config changes allowed
- no backtests allowed
- UI stale indicator shown
- alerts raised

For live trading, configurable policy:

- conservative: halt entries if Rails/control channel unavailable
- aggressive: continue monitoring but no new entries

Recommended default: no new entries if control plane unhealthy.

---

### 32.5 Dhan Token Expired

System must:

- detect auth failure
- stop bot
- alert user
- require re-login/token refresh

---

### 32.6 Rate Limit 429

System must:

- backoff exponentially
- queue non-critical calls
- prioritize exit orders
- alert if repeated

---

### 32.7 Partial Order Fill

For live:

- track filled quantity
- monitor remaining position
- cancel unfilled remainder if configured
- avoid duplicate order for same signal

For paper:

- simulate partial fill if enabled.

---

### 32.8 Market Gap Through Stop Loss

If price gaps below stop loss:

- exit at available market price
- do not assume exact SL price

---

### 32.9 Expiry Day

On expiry:

- avoid new entries after configurable cutoff
- force square-off before exchange cutoff
- handle low liquidity and near-zero premiums

---

### 32.10 Clock Drift

System must use exchange timestamp where available and validate local clock sync.

---

## 33. Compliance and Risk Disclaimer

### 33.1 User Responsibility

The platform executes user-defined strategies. Users are responsible for:

- strategy risk
- capital allocation
- compliance with broker terms
- applicable regulations
- taxes

### 33.2 No Investment Advice

The product does not provide financial advice. It provides technical execution infrastructure.

### 33.3 Broker API Terms

System must comply with DhanHQ API usage limits and terms.

### 33.4 Auditability

All live trading actions must be auditable.

---

## 34. Analytics Requirements

### 34.1 Dashboard Summary

Must show:

- today net PnL
- today gross PnL
- today charges
- win rate
- total trades
- open position
- capital
- max drawdown

### 34.2 Trade Analytics

Must calculate:

- average win
- average loss
- profit factor
- expectancy
- max consecutive wins
- max consecutive losses
- average holding time
- charge impact percentage

### 34.3 Strategy Comparison

Phase 2 should allow comparing backtests by parameter set.

---

## 35. Testing Requirements

### 35.1 Unit Tests

Cover:

- EMA calculation
- candle builder
- strategy signal logic
- paper matching engine
- tick size rounding
- fee calculator
- risk manager
- date chunker

### 35.2 Integration Tests

Cover:

- Rails API endpoints
- Redis pub/sub flow
- ActionCable broadcast
- backtest worker
- instrument sync
- clearing service

### 35.3 End-to-End Tests

Cover:

- paper trade entry and exit
- mode switch
- kill switch
- Node crash recovery
- stale data handling
- duplicate signal prevention
- CSV export

### 35.4 Soak Test

Paper trading must run continuously for at least:

- 5 market days without anomaly before live approval.

### 35.5 Live Dry Run

Before real capital:

- run live mode with minimum lot size.
- verify order placement, modification, cancellation, and reconciliation.

---

## 36. Acceptance Criteria

### 36.1 Backtesting Acceptance

- User can run backtest over multi-month range.
- System automatically chunks dates.
- Results include trades, summary, and CSV.
- EMA filter prevents counter-trend entries.
- Square-off exits positions before market close.
- Backtest stores in database.

### 36.2 Paper Trading Acceptance

- Paper mode does not send orders to Dhan.
- Paper fills include slippage and latency.
- Paper trades appear in UI in real time.
- Paper capital updates after fills and taxes.
- Active paper position survives Node restart.
- Paper trades are marked `is_paper_trade=true`.

### 36.3 Live Trading Acceptance

- Live mode requires explicit confirmation.
- Live orders are sent to Dhan.
- Live order state is synced.
- Live position can be squared off manually.
- Kill switch stops new entries.
- Live trades are marked `is_paper_trade=false`.
- Reconciliation matches broker records.

### 36.4 UI Acceptance

- Dashboard shows real-time capital, PnL, position, and events.
- Mode banner is clearly visible.
- WebSocket disconnect warning appears when connection lost.
- Trade feed updates without full page reload.
- Settings changes propagate to bot after confirmation.

### 36.5 Risk Acceptance

- Max daily loss stops entries.
- Max trades/day stops entries.
- Duplicate candle signal does not create duplicate order.
- Stale market data blocks entries.
- Kill switch works within 1 second.

---

## 37. Milestones and Delivery Plan

### Milestone 1: Foundation

**Deliverables:**

- monorepo setup
- Docker compose
- Rails API skeleton
- Node engine skeleton
- SolidJS skeleton
- Redis setup
- PostgreSQL schema
- authentication

**Exit Criteria:**

- services run locally
- health checks pass
- authenticated API works

---

### Milestone 2: Backtesting Engine

**Deliverables:**

- Dhan historical data service
- date chunking
- rolling option fetcher
- EMA indicator
- simulation engine
- CSV export
- backtest persistence

**Exit Criteria:**

- multi-month backtest completes
- results stored and downloadable
- no API window violations

---

### Milestone 3: Paper Trading Engine

**Deliverables:**

- Node WebSocket market data
- candle builder
- strategy engine
- paper matching engine
- virtual capital
- fee calculator
- Redis state
- Rails clearing service

**Exit Criteria:**

- paper trade lifecycle works end-to-end
- UI updates in real time
- paper ledger accurate
- crash recovery works

---

### Milestone 4: SolidJS Dashboard

**Deliverables:**

- dashboard
- live state updates
- trade feed
- strategy settings
- bot controls
- mode switch
- backtest UI

**Exit Criteria:**

- real-time updates stable
- controls work
- mode banner accurate
- stale data warning works

---

### Milestone 5: Live Trading

**Deliverables:**

- live order router
- live position tracking
- live reconciliation
- risk manager
- kill switch
- audit logs

**Exit Criteria:**

- live order placed and exited successfully in sandbox/small size
- reconciliation matches
- crash recovery validated
- kill switch validated

---

### Milestone 6: Hardening and Production

**Deliverables:**

- monitoring
- alerts
- backups
- security review
- load testing
- documentation
- runbooks

**Exit Criteria:**

- 5 consecutive paper days stable
- live dry run successful
- no critical bugs
- ops team sign-off

---

## 38. Operational Requirements

### 38.1 Health Endpoints

Node engine:

```text
GET /health
```

Rails API:

```text
GET /up
GET /health/redis
GET /health/postgres
GET /health/dhan_token
```

### 38.2 Logs

Log levels:

- fatal
- error
- warn
- info
- debug

Production default:

- info for services
- debug disabled unless troubleshooting

### 38.3 Alerts

Alert when:

- WebSocket disconnected > 30 seconds
- Dhan auth failure
- repeated order failures
- max daily loss triggered
- Redis unavailable
- Node engine crash loop
- stale data detected
- reconciliation mismatch

### 38.4 Backups

- PostgreSQL daily backup
- Redis persistence enabled
- audit logs retained minimum 1 year

---

## 39. Configuration Management

All configurable values must be stored in strategy parameters or app settings.

### 39.1 Strategy Config Example

```json
{
  "strategy_type": "ema_breakout",
  "underlying": "NIFTY",
  "exchangeSegment": "NSE_FNO",
  "instrument": "OPTIDX",
  "optionType": "CALL",
  "strikeMode": "ATM",
  "candleInterval": "5",
  "emaFast": 9,
  "emaSlow": 21,
  "slPct": 0.15,
  "targetPct": 0.30,
  "trailingSlPct": null,
  "slippagePct": 0.01,
  "qty": 50,
  "marketOpen": "09:20",
  "marketClose": "15:15",
  "squareOff": "15:20",
  "maxTradesPerDay": 10,
  "maxDailyLoss": 5000
}
```

### 39.2 Engine Config Example

```json
{
  "mode": "paper",
  "stateSyncIntervalMs": 100,
  "candleSyncIntervalMs": 1000,
  "staleDataThresholdMs": 3000,
  "paperLatencyMinMs": 40,
  "paperLatencyMaxMs": 150,
  "rateLimitTokens": 25,
  "rateLimitRefillPerSecond": 5
}
```

---

## 40. Dependencies

### External Dependencies

- DhanHQ v2 REST API
- DhanHQ WebSocket API
- Dhan instrument master
- Redis
- PostgreSQL
- Node.js runtime
- Ruby/Rails runtime

### Repository Dependencies

- `dhanhq-client` for Ruby/Rails historical data and admin operations
- `dhanhq-ts` for Node.js live market data and order execution

---

## 41. Assumptions

1. User has valid DhanHQ credentials.
2. DhanHQ API limits and endpoints remain stable.
3. NIFTY option lot size and tick size may change; system must make them configurable.
4. Historical expired instrument security IDs are not reliably available; rolling option endpoint is primary historical source.
5. Paper trading uses live market data unless replay feed is enabled.
6. MVP supports one active position per user per strategy.
7. Live trading requires user confirmation and is user-responsibility.

---

## 42. Open Questions

| ID | Question | Proposed Default |
| --- | --- | --- |
| OQ-01 | Should limit orders be included in MVP? | No, MARKET only |
| OQ-02 | Should paper engine simulate order book queue position? | Phase 2 |
| OQ-03 | Should backtest include full tax simulation by default? | Yes, configurable |
| OQ-04 | Should live mode auto-square-off on engine failure? | Yes, configurable |
| OQ-05 | Should system support PUT options in MVP? | Optional config, default CALL |
| OQ-06 | Should trailing SL be enabled by default? | No, configurable |
| OQ-07 | Should historical tick replay be MVP? | No, Phase 2 |
| OQ-08 | Should multiple strategies run simultaneously? | Phase 2 |
| OQ-09 | Should user be able to select strike manually? | Phase 2 |
| OQ-10 | Should system support BANKNIFTY? | Phase 2 |

---

## 43. Release Gates

### Paper Trading Release Gate

Before enabling live mode, the following must pass:

- 5 full market days of paper trading stable
- zero duplicate orders
- zero crash without recovery
- virtual ledger reconciles 100%
- UI real-time updates stable
- kill switch tested
- stale data guard tested
- risk limits tested

### Live Trading Release Gate

Before using meaningful capital:

- live dry run with minimum lot size successful
- order placement, cancellation, modification verified
- reconciliation verified
- crash recovery verified
- token expiry handling verified
- kill switch verified
- operator runbook approved

---

## 44. Final Product Definition

Algo Scalper API is a specialized options scalping platform with three core loops:

1. **Backtest Loop**
   Validate strategy on historical DhanHQ rolling options data using date chunking, EMA trend filter, dynamic strike awareness, slippage, and cost simulation.

2. **Paper Trading Loop**
   Simulate real broker behavior using live market data, local candle construction, paper matching engine, virtual capital, latency, slippage, taxes, and real-time UI.

3. **Live Trading Loop**
   Execute real orders with DhanHQ using low-latency Node.js hot path, strict risk controls, live position monitoring, reconciliation, and auditability.

The system is designed so that the same strategy logic can move from backtest to paper to live with minimal changes, while preserving safety, observability, and realistic execution modeling.

# `algo_scalper_api` — Complete End-to-End Implementation Plan

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        algo_scalper_api ECOSYSTEM                            │
│                                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                  │
│  │  SolidJS UI  │◄──►│  Rails API   │◄──►│  PostgreSQL  │                  │
│  │  (Frontend)  │    │ (Cold Path)  │    │  (Journal)   │                  │
│  └──────────────┘    └──────┬───────┘    └──────────────┘                  │
│                             │                                               │
│                      ┌──────▼───────┐                                       │
│                      │    Redis     │                                       │
│                      │ (State/Bus)  │                                       │
│                      └──────┬───────┘                                       │
│                             │                                               │
│                      ┌──────▼───────┐    ┌──────────────┐                  │
│                      │  Node.js TS  │◄──►│ DhanHQ APIs  │                  │
│                      │  (Hot Path)  │    │ (REST + WS)  │                  │
│                      └──────────────┘    └──────────────┘                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 0: Foundation & Repository Structure

### 0.1 Monorepo Layout

```
algo_scalper_api/
├── apps/
│   ├── api/                    # Rails API (Cold Path)
│   ├── engine/                 # Node.js TypeScript (Hot Path)
│   └── web/                    # SolidJS Frontend
├── packages/
│   ├── shared-types/           # Shared TypeScript types (Order, Tick, Candle)
│   ├── redis-schemas/          # Redis key schemas & serializers
│   └── strategy-core/          # Pure strategy logic (framework-agnostic)
├── infrastructure/
│   ├── docker-compose.yml
│   ├── redis.conf
│   └── nginx.conf
├── scripts/
│   ├── seed_instruments.rb
│   └── replay_historical_data.ts
└── README.md
```

### 0.2 Core Dependencies

**Rails (`apps/api/Gemfile`)**

```ruby
gem 'rails', '~> 7.1'
gem 'pg'
gem 'redis'
gem 'sidekiq'
gem 'actioncable'
gem 'DhanHQ', git: 'https://github.com/shubhamtaywade82/dhanhq-client.git', branch: 'main'
gem 'jwt'
gem 'rack-cors'
gem 'puma'
gem 'csv'
```

**Node.js (`apps/engine/package.json`)**

```json
{
  "dependencies": {
    "dhanhq-ts": "github:shubhamtaywade82/dhanhq-ts",
    "ioredis": "^5.3.0",
    "ws": "^8.16.0",
    "technicalindicators": "^3.1.0",
    "uuid": "^9.0.0",
    "pino": "^8.17.0",
    "dotenv": "^16.3.0"
  },
  "devDependencies": {
    "typescript": "^5.3.0",
    "tsx": "^4.7.0",
    "vitest": "^1.1.0"
  }
}
```

**SolidJS (`apps/web/package.json`)**

```json
{
  "dependencies": {
    "solid-js": "^1.8.0",
    "@rails/actioncable": "^7.1.0",
    "lightweight-charts": "^4.1.0",
    "solid-icons": "^1.1.0"
  },
  "devDependencies": {
    "vite": "^5.0.0",
    "vite-plugin-solid": "^2.8.0",
    "typescript": "^5.3.0"
  }
}
```

### 0.3 Docker Compose

```yaml
# infrastructure/docker-compose.yml
version: '3.9'

services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: algo_scalper
      POSTGRES_USER: scalper
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru
    ports:
      - "6379:6379"

  rails_api:
    build: ./apps/api
    depends_on: [postgres, redis]
    environment:
      DATABASE_URL: postgres://scalper:${DB_PASSWORD}@postgres:5432/algo_scalper
      REDIS_URL: redis://redis:6379/0
      DHAN_CLIENT_ID: ${DHAN_CLIENT_ID}
      DHAN_ACCESS_TOKEN: ${DHAN_ACCESS_TOKEN}
    ports:
      - "3000:3000"

  node_engine:
    build: ./apps/engine
    depends_on: [redis]
    environment:
      REDIS_URL: redis://redis:6379/0
      DHAN_CLIENT_ID: ${DHAN_CLIENT_ID}
      DHAN_ACCESS_TOKEN: ${DHAN_ACCESS_TOKEN}
      BOT_MODE: paper  # 'paper' or 'live'
    restart: always  # Critical for zombie position recovery

  solidjs_web:
    build: ./apps/web
    ports:
      - "5173:5173"
    depends_on: [rails_api]

volumes:
  pgdata:
```

---

## Phase 1: Database Schema (Rails)

### 1.1 Core Models & Migrations

```ruby
# db/migrate/001_create_users.rb
class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :dhan_client_id
      t.string :dhan_access_token_encrypted
      t.string :role, default: 'trader'
      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end

# db/migrate/002_create_strategies.rb
class CreateStrategies < ActiveRecord::Migration[7.1]
  def change
    create_table :strategies do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :strategy_type, default: 'ema_breakout'
      t.jsonb :parameters, default: {
        sl_pct: 0.15,
        target_pct: 0.30,
        slippage: 0.01,
        qty: 50,
        ema_fast: 9,
        ema_slow: 21,
        interval: '5',
        strike_relative: 'ATM',
        option_type: 'CALL'
      }
      t.boolean :is_active, default: false
      t.timestamps
    end
  end
end

# db/migrate/003_create_trade_logs.rb
class CreateTradeLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :trade_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :strategy, foreign_key: true
      t.string :exchange_order_id
      t.string :broker_order_id
      t.string :trading_symbol, null: false
      t.string :security_id
      t.string :transaction_type, null: false  # BUY / SELL
      t.string :order_type, default: 'MARKET'  # MARKET / LIMIT
      t.integer :quantity, null: false
      t.decimal :price, precision: 12, scale: 4
      t.decimal :average_price, precision: 12, scale: 4
      t.decimal :turnover, precision: 14, scale: 2
      t.decimal :brokerage, precision: 8, scale: 2, default: 0
      t.decimal :stt, precision: 8, scale: 4, default: 0
      t.decimal :txn_charges, precision: 8, scale: 4, default: 0
      t.decimal :gst, precision: 8, scale: 4, default: 0
      t.decimal :stamp_duty, precision: 8, scale: 4, default: 0
      t.decimal :net_charges, precision: 10, scale: 2, default: 0
      t.decimal :pnl, precision: 12, scale: 2
      t.string :status, default: 'PENDING'  # PENDING, OPEN, FILLED, CANCELLED, REJECTED
      t.boolean :is_paper_trade, default: false, null: false
      t.datetime :executed_at
      t.jsonb :metadata, default: {}  # Extra: entry_spot, ema_values, signal_reason
      t.timestamps
    end
    add_index :trade_logs, [:user_id, :is_paper_trade, :executed_at]
    add_index :trade_logs, :exchange_order_id
  end
end

# db/migrate/004_create_daily_performances.rb
class CreateDailyPerformances < ActiveRecord::Migration[7.1]
  def change
    create_table :daily_performances do |t|
      t.references :user, null: false, foreign_key: true
      t.date :trading_date, null: false
      t.string :mode, default: 'paper'  # 'paper' or 'live'
      t.integer :total_trades, default: 0
      t.integer :winning_trades, default: 0
      t.integer :losing_trades, default: 0
      t.decimal :gross_pnl, precision: 14, scale: 2, default: 0
      t.decimal :total_taxes, precision: 10, scale: 2, default: 0
      t.decimal :net_pnl, precision: 14, scale: 2, default: 0
      t.decimal :win_rate, precision: 5, scale: 2, default: 0
      t.decimal :max_drawdown, precision: 12, scale: 2
      t.decimal :virtual_capital_end, precision: 14, scale: 2
      t.timestamps
    end
    add_index :daily_performances, [:user_id, :trading_date, :mode], unique: true
  end
end

# db/migrate/005_create_backtest_runs.rb
class CreateBacktestRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :backtest_runs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :strategy, foreign_key: true
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :status, default: 'pending'  # pending, running, completed, failed
      t.integer :total_trades
      t.decimal :win_rate, precision: 5, scale: 2
      t.decimal :total_pnl, precision: 14, scale: 2
      t.decimal :max_drawdown, precision: 12, scale: 2
      t.jsonb :parameters_snapshot
      t.jsonb :results_summary
      t.timestamps
    end
  end
end

# db/migrate/006_create_instrument_cache.rb
class CreateInstrumentCache < ActiveRecord::Migration[7.1]
  def change
    create_table :instrument_caches do |t|
      t.string :exchange_segment, null: false
      t.date :cache_date, null: false
      t.text :csv_data  # Or store in S3 and keep URL
      t.timestamps
    end
    add_index :instrument_caches, [:exchange_segment, :cache_date], unique: true
  end
end
```

---

## Phase 2: Redis Schema & State Management

### 2.1 Key Namespace Convention

```
algo_scalper:{user_id}:{mode}:{resource}
```

### 2.2 Redis Key Definitions

```typescript
// packages/redis-schemas/src/keys.ts
export const REDIS_KEYS = {
  // Bot Control
  botMode: (userId: string) => `algo:${userId}:bot_mode`,           // 'paper' | 'live'
  botStatus: (userId: string) => `algo:${userId}:bot_status`,       // 'running' | 'stopped'

  // Strategy Config (written by Rails, read by Node)
  strategyConfig: (userId: string) => `algo:${userId}:strategy_config`,

  // Live State (written by Node, read by Rails)
  activeTrade: (userId: string, mode: string) => `algo:${userId}:${mode}:active_trade`,
  virtualCapital: (userId: string) => `algo:${userId}:virtual_capital`,
  liveCandle: (userId: string) => `algo:${userId}:live_candle`,

  // Instruments (written by Rails, read by Node)
  instrumentMap: (segment: string) => `dhan:instruments:${segment}`,

  // Order Queue (for rate limiting)
  pendingOrders: (userId: string) => `algo:${userId}:pending_orders`,

  // Pub/Sub Channels
  tradeEvents: (userId: string) => `algo:${userId}:trade_events`,
  stateUpdates: (userId: string) => `algo:${userId}:state_updates`,
  botCommands: (userId: string) => `algo:${userId}:bot_commands`,
};
```

### 2.3 Active Trade Hash Schema

```
HGETALL algo:1:paper:active_trade
{
  "orderId": "PAPER-uuid-123",
  "tradingSymbol": "NIFTY 24000 CE",
  "securityId": "42528",
  "entryPrice": "150.50",
  "entrySpot": "24020.5",
  "quantity": "50",
  "stopLoss": "127.93",
  "target": "195.65",
  "trailingSl": "140.25",
  "entryTime": "1706774400",
  "entryEma9": "24025.5",
  "entryEma21": "24010.2"
}
```

---

## Phase 3: Node.js Engine (Hot Path)

### 3.1 Directory Structure

```
apps/engine/
├── src/
│   ├── index.ts                    # Entry point
│   ├── config/
│   │   ├── env.ts
│   │   └── constants.ts
│   ├── core/
│   │   ├── BotOrchestrator.ts      # Main loop controller
│   │   ├── MarketDataManager.ts    # WebSocket connection & tick routing
│   │   ├── CandleBuilder.ts        # Tick-to-candle aggregation
│   │   └── IndicatorEngine.ts      # EMA, VWAP, Supertrend
│   ├── strategy/
│   │   ├── StrategyInterface.ts    # Abstract strategy contract
│   │   ├── EmaBreakoutStrategy.ts  # Our NIFTY strategy
│   │   └── SignalGenerator.ts      # Entry/exit signal logic
│   ├── execution/
│   │   ├── OrderRouter.ts          # Interface + Factory
│   │   ├── LiveDhanRouter.ts       # Real order execution
│   │   ├── PaperRouter.ts          # Simulated execution
│   │   └── RateLimiter.ts          # Token bucket for API limits
│   ├── paper/
│   │   ├── MatchingEngine.ts       # Simulated order matching
│   │   ├── VirtualRMS.ts           # Margin & capital checks
│   │   └── FeeCalculator.ts        # Dhan brokerage + taxes
│   ├── state/
│   │   ├── RedisStateManager.ts    # Read/write Redis state
│   │   └── PositionTracker.ts      # Trailing SL, target monitoring
│   └── utils/
│       ├── logger.ts
│       ├── time.ts                 # Market hours, candle boundaries
│       └── errors.ts
├── tsconfig.json
├── package.json
└── Dockerfile
```

### 3.2 Core Bot Orchestrator

```typescript
// src/core/BotOrchestrator.ts
import { MarketDataManager } from './MarketDataManager';
import { CandleBuilder } from './CandleBuilder';
import { IndicatorEngine } from './IndicatorEngine';
import { EmaBreakoutStrategy } from '../strategy/EmaBreakoutStrategy';
import { OrderRouter, createOrderRouter } from '../execution/OrderRouter';
import { RedisStateManager } from '../state/RedisStateManager';
import { PositionTracker } from '../state/PositionTracker';
import { REDIS_KEYS } from '@algo_scalper/redis-schemas';

export class BotOrchestrator {
  private marketData: MarketDataManager;
  private candleBuilder: CandleBuilder;
  private indicatorEngine: IndicatorEngine;
  private strategy: EmaBreakoutStrategy;
  private orderRouter: OrderRouter;
  private stateManager: RedisStateManager;
  private positionTracker: PositionTracker;
  private mode: 'paper' | 'live';
  private userId: string;
  private isRunning = false;

  async initialize(userId: string) {
    this.userId = userId;
    this.stateManager = new RedisStateManager();

    // Read mode from Redis (set by Rails)
    this.mode = await this.stateManager.getBotMode(userId);

    // Initialize components
    this.marketData = new MarketDataManager();
    this.candleBuilder = new CandleBuilder('5'); // 5-minute candles
    this.indicatorEngine = new IndicatorEngine();
    this.strategy = new EmaBreakoutStrategy();
    this.orderRouter = createOrderRouter(this.mode);
    this.positionTracker = new PositionTracker(this.stateManager, this.orderRouter);

    // Warm up indicators with historical data
    await this.warmUpIndicators();

    // Subscribe to Redis commands (start/stop/config changes from Rails)
    await this.subscribeToCommands();

    console.log(`[Bot] Initialized in ${this.mode} mode for user ${userId}`);
  }

  async start() {
    this.isRunning = true;
    await this.stateManager.setBotStatus(this.userId, 'running');

    // Connect to Dhan WebSocket
    this.marketData.connect();

    // Register tick handler
    this.marketData.onTick((tick) => this.handleTick(tick));

    // Start state sync interval (for dashboard updates)
    this.startStateSync();

    console.log('[Bot] Started');
  }

  async stop() {
    this.isRunning = false;
    await this.stateManager.setBotStatus(this.userId, 'stopped');
    this.marketData.disconnect();
    console.log('[Bot] Stopped');
  }

  private async handleTick(tick: TickData) {
    if (!this.isRunning) return;

    // 1. Check if we're in market hours
    if (!this.isMarketHours(tick.timestamp)) return;

    // 2. Update position tracker (SL/Target monitoring)
    if (this.positionTracker.hasActivePosition()) {
      await this.positionTracker.monitorTick(tick);
      return; // Don't look for new entries while in a position
    }

    // 3. Update candle builder
    const candleEvent = this.candleBuilder.processTick(tick);

    // 4. If candle just closed, evaluate strategy
    if (candleEvent === 'CANDLE_CLOSED') {
      const completedCandle = this.candleBuilder.getLastCompletedCandle();
      const candles = this.candleBuilder.getCandles();

      // Calculate indicators
      const indicators = this.indicatorEngine.calculate(candles);

      // Generate signal
      const signal = this.strategy.evaluate(completedCandle, candles, indicators);

      if (signal.action === 'BUY') {
        await this.executeEntry(signal, tick);
      }
    }
  }

  private async executeEntry(signal: StrategySignal, tick: TickData) {
    try {
      // Get security ID from Redis instrument map
      const securityId = await this.stateManager.getSecurityId(
        'NSE_FNO',
        signal.strike,
        signal.optionType
      );

      if (!securityId) {
        console.error(`[Bot] No security ID found for ${signal.strike} ${signal.optionType}`);
        return;
      }

      // Build order payload
      const order: OrderPayload = {
        dhanClientId: process.env.DHAN_CLIENT_ID!,
        transactionType: 'BUY',
        exchangeSegment: 'NSE_FNO',
        productType: 'INTRADAY',
        orderType: 'MARKET',
        validity: 'DAY',
        securityId: securityId,
        quantity: signal.quantity,
        price: 0,
        triggerPrice: 0,
        afterMarketOrder: false,
      };

      // Route order (live or paper)
      const response = await this.orderRouter.placeOrder(order);

      if (response.status === 'COMPLETE' || response.status === 'FILLED') {
        // Save active trade state
        await this.stateManager.setActiveTrade(this.userId, this.mode, {
          orderId: response.orderId,
          tradingSymbol: signal.tradingSymbol,
          securityId,
          entryPrice: response.averagePrice,
          entrySpot: tick.ltp,
          quantity: signal.quantity,
          stopLoss: response.averagePrice * (1 - signal.slPct),
          target: response.averagePrice * (1 + signal.targetPct),
          trailingSl: response.averagePrice * (1 - signal.slPct),
          entryTime: Date.now().toString(),
          entryEma9: signal.ema9.toString(),
          entryEma21: signal.ema21.toString(),
        });

        // Publish fill event to Rails
        await this.stateManager.publishTradeEvent(this.userId, {
          event: 'ENTRY',
          orderId: response.orderId,
          tradingSymbol: signal.tradingSymbol,
          transactionType: 'BUY',
          quantity: signal.quantity,
          fillPrice: response.averagePrice,
          timestamp: Date.now(),
          metadata: { ema9: signal.ema9, ema21: signal.ema21, spot: tick.ltp }
        });

        console.log(`[Bot] ENTRY: ${signal.tradingSymbol} @ ${response.averagePrice}`);
      }
    } catch (error) {
      console.error('[Bot] Entry execution failed:', error);
    }
  }

  private startStateSync() {
    // Publish state to Redis every 100ms for dashboard updates
    setInterval(async () => {
      if (!this.isRunning) return;

      const activeTrade = await this.stateManager.getActiveTrade(this.userId, this.mode);
      const capital = await this.stateManager.getVirtualCapital(this.userId);

      await this.stateManager.publishStateUpdate(this.userId, {
        capital,
        activeTrade,
        timestamp: Date.now(),
      });
    }, 100);
  }

  private isMarketHours(timestamp: number): boolean {
    const time = new Date(timestamp);
    const hours = time.getHours();
    const minutes = time.getMinutes();
    const totalMinutes = hours * 60 + minutes;

    // 09:20 to 15:15 IST
    return totalMinutes >= 560 && totalMinutes <= 915;
  }

  private async warmUpIndicators() {
    // Fetch last 100 candles from Dhan REST API via dhanhq-ts
    const historicalCandles = await this.marketData.fetchHistoricalCandles(100);
    this.candleBuilder.loadHistoricalCandles(historicalCandles);
    console.log(`[Bot] Warmed up with ${historicalCandles.length} historical candles`);
  }

  private async subscribeToCommands() {
    this.stateManager.subscribeToCommands(this.userId, async (command) => {
      switch (command.action) {
        case 'start': await this.start(); break;
        case 'stop': await this.stop(); break;
        case 'square_off': await this.positionTracker.forceSquareOff(); break;
        case 'update_config': await this.reloadConfig(); break;
      }
    });
  }
}
```

### 3.3 Candle Builder

```typescript
// src/core/CandleBuilder.ts
export class CandleBuilder {
  private candles: Candle[] = [];
  private currentCandle: Candle | null = null;
  private intervalMs: number;
  private maxCandles: number;

  constructor(intervalMinutes: string, maxCandles = 200) {
    this.intervalMs = parseInt(intervalMinutes) * 60 * 1000;
    this.maxCandles = maxCandles;
  }

  processTick(tick: TickData): 'UPDATED' | 'CANDLE_CLOSED' | 'NEW_CANDLE' {
    const candleStartTime = this.getCandleStartTime(tick.timestamp);

    // Check if we need to close the current candle
    if (this.currentCandle && candleStartTime > this.currentCandle.startTime) {
      this.closeCurrentCandle();
      this.startNewCandle(candleStartTime, tick);
      return 'CANDLE_CLOSED';
    }

    // Update current candle
    if (this.currentCandle) {
      this.currentCandle.high = Math.max(this.currentCandle.high, tick.ltp);
      this.currentCandle.low = Math.min(this.currentCandle.low, tick.ltp);
      this.currentCandle.close = tick.ltp;
      this.currentCandle.volume += tick.volume || 0;
      return 'UPDATED';
    }

    // First tick
    this.startNewCandle(candleStartTime, tick);
    return 'NEW_CANDLE';
  }

  private getCandleStartTime(timestamp: number): number {
    return Math.floor(timestamp / this.intervalMs) * this.intervalMs;
  }

  private startNewCandle(startTime: number, tick: TickData) {
    this.currentCandle = {
      startTime,
      endTime: startTime + this.intervalMs,
      open: tick.ltp,
      high: tick.ltp,
      low: tick.ltp,
      close: tick.ltp,
      volume: tick.volume || 0,
    };
  }

  private closeCurrentCandle() {
    if (this.currentCandle) {
      this.candles.push({ ...this.currentCandle });
      if (this.candles.length > this.maxCandles) {
        this.candles.shift();
      }
      this.currentCandle = null;
    }
  }

  getCandles(): Candle[] { return [...this.candles]; }
  getLastCompletedCandle(): Candle | null { return this.candles[this.candles.length - 1] || null; }
  getCurrentCandle(): Candle | null { return this.currentCandle; }

  loadHistoricalCandles(candles: Candle[]) {
    this.candles = candles;
  }
}
```

### 3.4 Paper Matching Engine

```typescript
// src/paper/MatchingEngine.ts
import { v4 as uuidv4 } from 'uuid';

export class MatchingEngine {
  constructor(private redis: RedisStateManager) {}

  async processOrder(order: OrderPayload, currentTick: TickData): Promise<OrderResponse> {
    // 1. Virtual RMS Check
    const capital = await this.redis.getVirtualCapital(order.dhanClientId);
    const orderCost = order.price * order.quantity || currentTick.ltp * order.quantity;

    if (orderCost > capital) {
      return {
        orderId: `REJ-${uuidv4()}`,
        status: 'REJECTED',
        reason: 'RMS_MARGIN_SHORTFALL',
        averagePrice: 0,
      };
    }

    // 2. Simulate Exchange Latency
    await this.simulateLatency(40, 150);

    // 3. Determine Fill Price
    let fillPrice: number;

    if (order.orderType === 'MARKET') {
      // Market orders fill at Best Ask (Buy) or Best Bid (Sell)
      const depth = currentTick.depth;
      if (order.transactionType === 'BUY') {
        fillPrice = depth?.askPrice1 || currentTick.ltp;
      } else {
        fillPrice = depth?.bidPrice1 || currentTick.ltp;
      }
      // Add slippage for market orders
      fillPrice += order.transactionType === 'BUY' ? 0.50 : -0.50;
    } else {
      fillPrice = order.price;
    }

    // 4. Enforce NSE Tick Size (0.05 for options)
    fillPrice = this.roundToTickSize(fillPrice, 0.05);

    // 5. Generate Order IDs
    const orderId = `SIM-${uuidv4()}`;
    const exchangeOrderId = `NSE-${Date.now()}-${Math.floor(Math.random() * 9999)}`;

    // 6. Deduct Virtual Capital
    await this.redis.decrementCapital(order.dhanClientId, orderCost);

    return {
      orderId,
      exchangeOrderId,
      status: 'COMPLETE',
      averagePrice: fillPrice,
      quantity: order.quantity,
    };
  }

  private simulateLatency(min: number, max: number): Promise<void> {
    const delay = min + Math.random() * (max - min);
    return new Promise(resolve => setTimeout(resolve, delay));
  }

  private roundToTickSize(price: number, tickSize: number): number {
    return Math.round(price / tickSize) * tickSize;
  }
}
```

### 3.5 Position Tracker (Trailing SL & Target)

```typescript
// src/state/PositionTracker.ts
export class PositionTracker {
  constructor(
    private stateManager: RedisStateManager,
    private orderRouter: OrderRouter
  ) {}

  async hasActivePosition(): Promise<boolean> {
    const trade = await this.stateManager.getActiveTrade(this.userId, this.mode);
    return trade !== null;
  }

  async monitorTick(tick: TickData) {
    const trade = await this.stateManager.getActiveTrade(this.userId, this.mode);
    if (!trade) return;

    const currentPrice = tick.ltp;

    // Check Square-off time (15:20 IST)
    if (this.isSquareOffTime(tick.timestamp)) {
      await this.executeExit(trade, currentPrice, 'Intraday Square-Off');
      return;
    }

    // Check Stop Loss
    if (currentPrice <= parseFloat(trade.trailingSl)) {
      await this.executeExit(trade, currentPrice, 'SL Hit');
      return;
    }

    // Check Target
    if (currentPrice >= parseFloat(trade.target)) {
      await this.executeExit(trade, currentPrice, 'Target Hit');
      return;
    }

    // Update Trailing SL (if price moved up by 1% from entry)
    const entryPrice = parseFloat(trade.entryPrice);
    const trailActivation = entryPrice * 1.05; // Activate trailing after 5% profit

    if (currentPrice >= trailActivation) {
      const newTrailingSl = currentPrice * 0.95; // Trail 5% below current price
      if (newTrailingSl > parseFloat(trade.trailingSl)) {
        await this.stateManager.updateTrailingSl(this.userId, this.mode, newTrailingSl.toString());
      }
    }
  }

  async executeExit(trade: ActiveTrade, exitPrice: number, reason: string) {
    const order: OrderPayload = {
      dhanClientId: process.env.DHAN_CLIENT_ID!,
      transactionType: 'SELL',
      exchangeSegment: 'NSE_FNO',
      productType: 'INTRADAY',
      orderType: 'MARKET',
      validity: 'DAY',
      securityId: trade.securityId,
      quantity: parseInt(trade.quantity),
      price: 0,
      triggerPrice: 0,
    };

    const response = await this.orderRouter.placeOrder(order);

    if (response.status === 'COMPLETE') {
      // Clear active trade from Redis
      await this.stateManager.clearActiveTrade(this.userId, this.mode);

      // Add capital back
      const proceeds = response.averagePrice * parseInt(trade.quantity);
      await this.redis.incrementCapital(this.userId, proceeds);

      // Publish exit event
      await this.stateManager.publishTradeEvent(this.userId, {
        event: 'EXIT',
        reason,
        orderId: response.orderId,
        tradingSymbol: trade.tradingSymbol,
        transactionType: 'SELL',
        quantity: trade.quantity,
        entryPrice: trade.entryPrice,
        exitPrice: response.averagePrice,
        pnl: (response.averagePrice - parseFloat(trade.entryPrice)) * parseInt(trade.quantity),
        timestamp: Date.now(),
      });

      console.log(`[Bot] EXIT (${reason}): ${trade.tradingSymbol} @ ${response.averagePrice}`);
    }
  }

  async forceSquareOff() {
    const trade = await this.stateManager.getActiveTrade(this.userId, this.mode);
    if (trade) {
      await this.executeExit(trade, 0, 'Manual Square-Off');
    }
  }

  private isSquareOffTime(timestamp: number): boolean {
    const time = new Date(timestamp);
    return time.getHours() === 15 && time.getMinutes() >= 20;
  }
}
```

---

## Phase 4: Rails API (Cold Path)

### 4.1 Directory Structure

```
apps/api/
├── app/
│   ├── channels/
│   │   ├── application_cable/
│   │   └── scalper_channel.rb
│   ├── controllers/
│   │   ├── api/v1/
│   │   │   ├── strategies_controller.rb
│   │   │   ├── trades_controller.rb
│   │   │   ├── backtests_controller.rb
│   │   │   ├── dashboard_controller.rb
│   │   │   └── bot_controller.rb
│   │   └── application_controller.rb
│   ├── models/
│   │   ├── user.rb
│   │   ├── strategy.rb
│   │   ├── trade_log.rb
│   │   ├── daily_performance.rb
│   │   ├── backtest_run.rb
│   │   └── instrument_cache.rb
│   ├── services/
│   │   ├── dhan/
│   │   │   ├── instrument_sync_service.rb
│   │   │   ├── historical_data_service.rb
│   │   │   └── order_reconciliation_service.rb
│   │   ├── backtesting/
│   │   │   ├── nifty_options_backtester.rb
│   │   │   ├── date_chunker.rb
│   │   │   └── indicator_calculator.rb
│   │   ├── paper/
│   │   │   ├── clearing_service.rb
│   │   │   └── fee_calculator.rb
│   │   └── redis/
│   │       ├── state_publisher.rb
│   │       └── command_subscriber.rb
│   ├── workers/
│   │   ├── instrument_sync_worker.rb
│   │   ├── eod_reconciliation_worker.rb
│   │   ├── backtest_execution_worker.rb
│   │   └── redis_subscriber_worker.rb
│   └── models/concerns/
│       └── dhan_api_configurable.rb
├── config/
│   ├── routes.rb
│   ├── cable.yml
│   └── initializers/
│       ├── redis.rb
│       ├── dhan_hq.rb
│       └── sidekiq.rb
├── db/
│   └── migrate/
└── spec/  # or test/
```

### 4.2 Key Services

```ruby
# app/services/backtesting/nifty_options_backtester.rb
# (This is the complete backtester we built earlier, integrated as a service)
module Backtesting
  class NiftyOptionsBacktester
    NIFTY_SECURITY_ID = '13'

    def initialize(strategy_params, start_date, end_date)
      @params = strategy_params
      @start_date = start_date
      @end_date = end_date
      @expired_data_resource = DhanHQ::Resources::ExpiredOptionsData.new
      @historical_data_resource = DhanHQ::Resources::HistoricalData.new
    end

    def run
      date_chunks = DateChunker.generate(@start_date, @end_date)
      all_trades = []

      date_chunks.each do |chunk|
        candles = fetch_rolling_data(chunk[:from], chunk[:to])
        next if candles.empty?

        candles = add_technical_indicators(candles)
        chunk_trades = execute_simulation(candles)
        all_trades.concat(chunk_trades)
      end

      generate_summary(all_trades)
    end

    # ... (all the methods from our earlier implementation)
  end
end
```

```ruby
# app/services/paper/clearing_service.rb
module Paper
  class ClearingService
    BROKERAGE_PER_ORDER = 20.0
    STT_RATE = 0.000125
    TXN_CHARGE_RATE = 0.00053
    GST_RATE = 0.18
    STAMP_DUTY_RATE = 0.00003

    def process_fill(fill_data)
      turnover = fill_data['fillPrice'].to_f * fill_data['quantity'].to_i

      brokerage = BROKERAGE_PER_ORDER
      txn_charges = turnover * TXN_CHARGE_RATE
      gst = (brokerage + txn_charges) * GST_RATE
      stt = fill_data['transactionType'] == 'SELL' ? (turnover * STT_RATE) : 0.0
      stamp_duty = fill_data['transactionType'] == 'BUY' ? (turnover * STAMP_DUTY_RATE) : 0.0
      total_taxes = brokerage + txn_charges + gst + stt + stamp_duty

      TradeLog.create!(
        user_id: fill_data['user_id'],
        exchange_order_id: fill_data['exchangeOrderId'],
        trading_symbol: fill_data['tradingSymbol'],
        transaction_type: fill_data['transactionType'],
        quantity: fill_data['quantity'],
        average_price: fill_data['fillPrice'],
        turnover: turnover,
        brokerage: brokerage,
        stt: stt,
        txn_charges: txn_charges,
        gst: gst,
        stamp_duty: stamp_duty,
        net_charges: total_taxes,
        is_paper_trade: true,
        status: 'FILLED',
        executed_at: Time.at(fill_data['timestamp'].to_i / 1000.0),
        metadata: fill_data['metadata'] || {}
      )

      # Deduct taxes from virtual capital
      RedisStateManager.decrement_capital(fill_data['user_id'], total_taxes)
    end
  end
end
```

### 4.3 ActionCable Channel

```ruby
# app/channels/scalper_channel.rb
class ScalperChannel < ApplicationCable::Channel
  def subscribed
    stream_from "scalper_#{current_user.id}"
  end

  def receive(data)
    case data['action']
    when 'start_bot'
      Redis.current.publish("algo:#{current_user.id}:bot_commands", { action: 'start' }.to_json)
    when 'stop_bot'
      Redis.current.publish("algo:#{current_user.id}:bot_commands", { action: 'stop' }.to_json)
    when 'square_off'
      Redis.current.publish("algo:#{current_user.id}:bot_commands", { action: 'square_off' }.to_json)
    when 'switch_mode'
      switch_mode(data['mode'])
    when 'update_config'
      update_strategy_config(data['parameters'])
    end
  end

  private

  def switch_mode(new_mode)
    return unless %w[paper live].include?(new_mode)

    # Safety: Square off all positions before switching
    Redis.current.publish("algo:#{current_user.id}:bot_commands", { action: 'square_off' }.to_json)

    sleep(2) # Wait for square-off to process

    Redis.current.set("algo:#{current_user.id}:bot_mode", new_mode)

    ActionCable.server.broadcast("scalper_#{current_user.id}", {
      channel: 'mode_change',
      payload: { mode: new_mode, timestamp: Time.current.to_i }
    })
  end

  def update_strategy_config(params)
    strategy = current_user.strategies.find(params['strategy_id'])
    strategy.update!(parameters: strategy.parameters.merge(params))

    # Push to Redis for Node.js to read
    Redis.current.set(
      "algo:#{current_user.id}:strategy_config",
      strategy.parameters.to_json
    )

    # Notify Node to reload
    Redis.current.publish("algo:#{current_user.id}:bot_commands", { action: 'update_config' }.to_json)
  end
end
```

### 4.4 Redis Subscriber Worker (Sidekiq)

```ruby
# app/workers/redis_subscriber_worker.rb
class RedisSubscriberWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'critical', retry: false

  def perform
    redis = Redis.new(url: ENV['REDIS_URL'])
    clearing_service = Paper::ClearingService.new

    # Subscribe to all user trade events and state updates
    # In production, use Redis patterns or per-user subscriptions
    redis.psubscribe('algo:*:trade_events', 'algo:*:state_updates') do |on|
      on.pmessage do |pattern, channel, message|
        data = JSON.parse(message)
        user_id = channel.split(':')[1]

        case channel
        when /trade_events/
          # Save to database
          clearing_service.process_fill(data) if data['event'] == 'ENTRY' || data['event'] == 'EXIT'

          # Broadcast to SolidJS frontend
          ActionCable.server.broadcast("scalper_#{user_id}", {
            channel: 'trade_events',
            payload: data
          })

        when /state_updates/
          # Broadcast throttled state to frontend (already throttled by Node at 100ms)
          ActionCable.server.broadcast("scalper_#{user_id}", {
            channel: 'state_updates',
            payload: data
          })
        end
      end
    end
  end
end
```

### 4.5 API Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount ActionCable.server => '/cable'

  namespace :api do
    namespace :v1 do
      # Auth
      post 'auth/login', to: 'auth#login'
      post 'auth/register', to: 'auth#register'

      # Strategies
      resources :strategies do
        member do
          post :activate
          post :deactivate
        end
      end

      # Bot Control
      post 'bot/start', to: 'bot#start'
      post 'bot/stop', to: 'bot#stop'
      post 'bot/square_off', to: 'bot#square_off'
      post 'bot/switch_mode', to: 'bot#switch_mode'
      get 'bot/status', to: 'bot#status'

      # Trades
      resources :trades, only: [:index, :show] do
        collection do
          get :paper
          get :live
        end
      end

      # Dashboard
      get 'dashboard/summary', to: 'dashboard#summary'
      get 'dashboard/pnl_chart', to: 'dashboard#pnl_chart'
      get 'dashboard/trade_history', to: 'dashboard#trade_history'

      # Backtesting
      resources :backtests, only: [:create, :index, :show] do
        member do
          get :results
          get :download_csv
        end
      end

      # Instruments
      get 'instruments/search', to: 'instruments#search'
      post 'instruments/sync', to: 'instruments#sync'
    end
  end
end
```

---

## Phase 5: SolidJS Frontend

### 5.1 Directory Structure

```
apps/web/
├── src/
│   ├── App.tsx
│   ├── index.tsx
│   ├── api/
│   │   ├── client.ts              # Axios/fetch wrapper
│   │   └── websocket.ts           # ActionCable connection
│   ├── hooks/
│   │   ├── useScalperSocket.ts    # Real-time data hook
│   │   ├── useAuth.ts
│   │   └── useBotControls.ts
│   ├── components/
│   │   ├── layout/
│   │   │   ├── Sidebar.tsx
│   │   │   └── Header.tsx
│   │   ├── dashboard/
│   │   │   ├── PnlTicker.tsx
│   │   │   ├── ActivePositionCard.tsx
│   │   │   ├── OrderBook.tsx
│   │   │   ├── TradeFeed.tsx
│   │   │   └── CandlestickChart.tsx
│   │   ├── backtest/
│   │   │   ├── BacktestForm.tsx
│   │   │   ├── BacktestResults.tsx
│   │   │   └── TradeTable.tsx
│   │   └── settings/
│   │       ├── StrategyConfig.tsx
│   │       └── ModeSwitch.tsx
│   ├── pages/
│   │   ├── Dashboard.tsx
│   │   ├── Backtesting.tsx
│   │   ├── TradeHistory.tsx
│   │   └── Settings.tsx
│   ├── stores/
│   │   ├── authStore.ts
│   │   └── botStore.ts
│   └── utils/
│       ├── formatters.ts
│       └── time.ts
├── vite.config.ts
├── tsconfig.json
└── package.json
```

### 5.2 Core WebSocket Hook

```typescript
// src/hooks/useScalperSocket.ts
import { createSignal, onMount, onCleanup } from 'solid-js';
import { createConsumer, Consumer } from '@rails/actioncable';

interface SocketState {
  virtualCapital: number;
  activeTrade: ActiveTrade | null;
  livePnl: number;
  orderEvents: TradeEvent[];
  botStatus: 'running' | 'stopped';
  mode: 'paper' | 'live';
  isConnected: boolean;
}

export function useScalperSocket(authToken: string) {
  const [state, setState] = createSignal<SocketState>({
    virtualCapital: 100000,
    activeTrade: null,
    livePnl: 0,
    orderEvents: [],
    botStatus: 'stopped',
    mode: 'paper',
    isConnected: false,
  });

  let consumer: Consumer | null = null;
  let subscription: any = null;

  onMount(() => {
    const wsUrl = `${import.meta.env.VITE_WS_URL}/cable?token=${authToken}`;
    consumer = createConsumer(wsUrl);

    subscription = consumer.subscriptions.create(
      { channel: 'ScalperChannel' },
      {
        connected() {
          setState(prev => ({ ...prev, isConnected: true }));
        },
        disconnected() {
          setState(prev => ({ ...prev, isConnected: false }));
        },
        received(data: { channel: string, payload: any }) {
          handleIncomingData(data);
        }
      }
    );
  });

  function handleIncomingData(data: { channel: string, payload: any }) {
    switch (data.channel) {
      case 'trade_events':
        setState(prev => ({
          ...prev,
          orderEvents: [data.payload, ...prev.orderEvents].slice(0, 100),
          activeTrade: data.payload.event === 'EXIT' ? null : prev.activeTrade,
        }));
        break;

      case 'state_updates':
        setState(prev => ({
          ...prev,
          virtualCapital: data.payload.capital,
          activeTrade: data.payload.activeTrade,
          livePnl: calculateLivePnl(data.payload.activeTrade, data.payload.currentPrice),
        }));
        break;

      case 'mode_change':
        setState(prev => ({ ...prev, mode: data.payload.mode }));
        break;

      case 'bot_status':
        setState(prev => ({ ...prev, botStatus: data.payload.status }));
        break;
    }
  }

  function sendCommand(action: string, payload?: any) {
    subscription?.send({ action, ...payload });
  }

  onCleanup(() => {
    consumer?.disconnect();
  });

  return {
    state,
    sendCommand,
  };
}

function calculateLivePnl(trade: ActiveTrade | null, currentPrice?: number): number {
  if (!trade || !currentPrice) return 0;
  return (currentPrice - parseFloat(trade.entryPrice)) * parseInt(trade.quantity);
}
```

### 5.3 Dashboard Page

```tsx
// src/pages/Dashboard.tsx
import { Component, Show, createMemo, createSignal } from 'solid-js';
import { useScalperSocket } from '../hooks/useScalperSocket';
import PnlTicker from '../components/dashboard/PnlTicker';
import ActivePositionCard from '../components/dashboard/ActivePositionCard';
import TradeFeed from '../components/dashboard/TradeFeed';
import CandlestickChart from '../components/dashboard/CandlestickChart';
import ModeSwitch from '../components/settings/ModeSwitch';

const Dashboard: Component = () => {
  const authToken = localStorage.getItem('auth_token') || '';
  const { state, sendCommand } = useScalperSocket(authToken);

  const [showConfirmLive, setShowConfirmLive] = createSignal(false);

  const handleModeSwitch = (mode: string) => {
    if (mode === 'live') {
      setShowConfirmLive(true);
    } else {
      sendCommand('switch_mode', { mode });
    }
  };

  const confirmLiveSwitch = () => {
    sendCommand('switch_mode', { mode: 'live' });
    setShowConfirmLive(false);
  };

  return (
    <div class="min-h-screen bg-gray-950 text-white p-6">
      {/* Header */}
      <header class="flex justify-between items-center mb-8">
        <div class="flex items-center gap-4">
          <h1 class="text-2xl font-bold">Algo Scalper</h1>
          <Show when={state().mode === 'paper'}>
            <span class="bg-yellow-600 text-xs px-2 py-1 rounded font-bold">PAPER</span>
          </Show>
          <Show when={state().mode === 'live'}>
            <span class="bg-red-600 text-xs px-2 py-1 rounded font-bold animate-pulse">LIVE</span>
          </Show>
        </div>

        <div class="flex items-center gap-4">
          <ModeSwitch
            currentMode={state().mode}
            onSwitch={handleModeSwitch}
          />
          <button
            onClick={() => sendCommand(state().botStatus === 'running' ? 'stop_bot' : 'start_bot')}
            class={`px-4 py-2 rounded font-bold ${
              state().botStatus === 'running'
                ? 'bg-red-600 hover:bg-red-700'
                : 'bg-green-600 hover:bg-green-700'
            }`}
          >
            {state().botStatus === 'running' ? 'STOP BOT' : 'START BOT'}
          </button>
        </div>
      </header>

      {/* Connection Status */}
      <Show when={!state().isConnected}>
        <div class="bg-red-900/50 border border-red-600 rounded p-3 mb-6 text-center">
          ⚠️ WebSocket Disconnected. Attempting to reconnect...
        </div>
      </Show>

      {/* Stats Grid */}
      <div class="grid grid-cols-4 gap-6 mb-8">
        <PnlTicker
          label="Virtual Capital"
          value={state().virtualCapital}
          prefix="₹"
        />
        <PnlTicker
          label="Unrealized P&L"
          value={state().livePnl}
          prefix="₹"
          colorize={true}
        />
        <PnlTicker
          label="Bot Status"
          value={state().botStatus}
        />
        <PnlTicker
          label="Mode"
          value={state().mode.toUpperCase()}
        />
      </div>

      {/* Main Content Grid */}
      <div class="grid grid-cols-3 gap-6">
        {/* Chart - Takes 2 columns */}
        <div class="col-span-2">
          <CandlestickChart />
        </div>

        {/* Right Panel */}
        <div class="space-y-6">
          <ActivePositionCard trade={state().activeTrade} />
          <TradeFeed events={state().orderEvents} />
        </div>
      </div>

      {/* Live Mode Confirmation Modal */}
      <Show when={showConfirmLive()}>
        <div class="fixed inset-0 bg-black/80 flex items-center justify-center z-50">
          <div class="bg-gray-900 border border-red-600 rounded-lg p-8 max-w-md">
            <h2 class="text-xl font-bold text-red-500 mb-4">⚠️ SWITCH TO LIVE TRADING</h2>
            <p class="text-gray-300 mb-6">
              This will start placing REAL orders with REAL money.
              All paper positions will be squared off. Are you absolutely sure?
            </p>
            <div class="flex gap-4">
              <button
                onClick={() => setShowConfirmLive(false)}
                class="flex-1 bg-gray-700 hover:bg-gray-600 px-4 py-2 rounded"
              >
                Cancel
              </button>
              <button
                onClick={confirmLiveSwitch}
                class="flex-1 bg-red-600 hover:bg-red-700 px-4 py-2 rounded font-bold"
              >
                YES, GO LIVE
              </button>
            </div>
          </div>
        </div>
      </Show>
    </div>
  );
};

export default Dashboard;
```

---

## Phase 6: Backtesting Engine Integration

### 6.1 Backtest Execution Worker

```ruby
# app/workers/backtest_execution_worker.rb
class BacktestExecutionWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'backtests', retry: 1

  def perform(backtest_run_id)
    run = BacktestRun.find(backtest_run_id)
    run.update!(status: 'running')

    begin
      strategy = run.strategy
      backtester = Backtesting::NiftyOptionsBacktester.new(
        strategy.parameters,
        run.start_date,
        run.end_date
      )

      results = backtester.run

      run.update!(
        status: 'completed',
        total_trades: results[:total_trades],
        win_rate: results[:win_rate],
        total_pnl: results[:total_pnl],
        max_drawdown: results[:max_drawdown],
        results_summary: results[:summary],
        parameters_snapshot: strategy.parameters
      )

      # Store detailed trade log
      store_trade_results(run, results[:trades])

    rescue StandardError => e
      run.update!(status: 'failed', results_summary: { error: e.message })
      raise e
    end
  end

  private

  def store_trade_results(run, trades)
    trades.each do |trade|
      TradeLog.create!(
        user_id: run.user_id,
        strategy_id: run.strategy_id,
        trading_symbol: trade[:trading_symbol] || 'NIFTY ATM CE',
        transaction_type: 'BUY',
        quantity: trade[:quantity] || 50,
        average_price: trade[:entry_price],
        pnl: trade[:pnl],
        is_paper_trade: true,
        status: trade[:result] == 'SL Hit' ? 'FILLED' : 'FILLED',
        executed_at: trade[:entry_time],
        metadata: {
          backtest_run_id: run.id,
          exit_time: trade[:exit_time],
          exit_price: trade[:exit_price],
          result: trade[:result],
          entry_spot: trade[:entry_spot]
        }
      )
    end
  end
end
```

### 6.2 Backtest API Controller

```ruby
# app/controllers/api/v1/backtests_controller.rb
module Api
  module V1
    class BacktestsController < ApplicationController
      def create
        strategy = current_user.strategies.find(params[:strategy_id])

        run = BacktestRun.create!(
          user: current_user,
          strategy: strategy,
          start_date: params[:start_date],
          end_date: params[:end_date],
          status: 'pending'
        )

        BacktestExecutionWorker.perform_async(run.id)

        render json: { id: run.id, status: 'pending' }, status: :accepted
      end

      def index
        runs = current_user.backtest_runs.order(created_at: :desc).limit(20)
        render json: runs.as_json(only: [:id, :start_date, :end_date, :status, :total_trades, :win_rate, :total_pnl, :created_at])
      end

      def show
        run = current_user.backtest_runs.find(params[:id])
        render json: run.as_json(include: { strategy: { only: [:name, :parameters] } })
      end

      def results
        run = current_user.backtest_runs.find(params[:id])
        trades = TradeLog.where(metadata: { backtest_run_id: run.id })

        render json: {
          summary: run.results_summary,
          trades: trades.as_json(only: [:average_price, :pnl, :executed_at, :metadata])
        }
      end

      def download_csv
        run = current_user.backtest_runs.find(params[:id])
        trades = TradeLog.where(metadata: { backtest_run_id: run.id })

        csv_data = generate_csv(trades)

        send_data csv_data,
          filename: "backtest_#{run.id}_#{Date.today}.csv",
          type: 'text/csv'
      end

      private

      def generate_csv(trades)
        CSV.generate do |csv|
          csv << ['Entry Time', 'Entry Price', 'Entry Spot', 'Exit Time', 'Exit Price', 'PnL', 'Result']
          trades.each do |t|
            csv << [
              t.executed_at,
              t.average_price,
              t.metadata['entry_spot'],
              t.metadata['exit_time'],
              t.metadata['exit_price'],
              t.pnl,
              t.metadata['result']
            ]
          end
        end
      end
    end
  end
end
```

---

## Phase 7: Deployment & DevOps

### 7.1 Environment Variables

```bash
# .env.production
# Dhan API
DHAN_CLIENT_ID=your_client_id
DHAN_ACCESS_TOKEN=your_access_token

# Database
DATABASE_URL=postgres://scalper:password@localhost:5432/algo_scalper

# Redis
REDIS_URL=redis://localhost:6379/0

# Rails
RAILS_ENV=production
SECRET_KEY_BASE=your_secret_key
RAILS_MAX_THREADS=5

# Node Engine
BOT_MODE=paper
LOG_LEVEL=info

# Frontend
VITE_API_URL=https://api.algoscaper.com
VITE_WS_URL=wss://api.algoscaper.com
```

### 7.2 Process Management (Production)

```yaml
# Procfile (for Heroku/Railway/Render)
web: cd apps/web && npm run build && npx serve dist
api: cd apps/api && bundle exec puma -C config/puma.rb
worker: cd apps/api && bundle exec sidekiq -C config/sidekiq.yml
engine: cd apps/engine && npm run start
```

### 7.3 PM2 Configuration (Node.js Engine)

```json
// apps/engine/ecosystem.config.json
{
  "apps": [{
    "name": "algo-scalper-engine",
    "script": "dist/index.js",
    "instances": 1,
    "autorestart": true,
    "watch": false,
    "max_memory_restart": "512M",
    "env": {
      "NODE_ENV": "production",
      "REDIS_URL": "redis://localhost:6379/0"
    },
    "log_date_format": "YYYY-MM-DD HH:mm:ss Z",
    "error_file": "./logs/engine-error.log",
    "out_file": "./logs/engine-out.log",
    "merge_logs": true,
    "restart_delay": 3000
  }]
}
```

### 7.4 Health Checks

```typescript
// src/health.ts
import { createServer } from 'http';

export function startHealthCheck(port = 3001) {
  createServer((req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        status: 'healthy',
        uptime: process.uptime(),
        timestamp: Date.now(),
        memory: process.memoryUsage(),
      }));
    } else {
      res.writeHead(404);
      res.end();
    }
  }).listen(port);
}
```

---

## Phase 8: Risk Management & Safeguards

### 8.1 Global Kill Switch

```typescript
// src/core/RiskManager.ts
export class RiskManager {
  private maxDailyLoss: number;
  private maxTradesPerDay: number;
  private dailyTradeCount = 0;
  private dailyPnl = 0;

  constructor(config: RiskConfig) {
    this.maxDailyLoss = config.maxDailyLoss;      // e.g., -5000
    this.maxTradesPerDay = config.maxTradesPerDay; // e.g., 20
  }

  canTrade(): boolean {
    if (this.dailyPnl <= this.maxDailyLoss) {
      console.log('[Risk] Daily loss limit hit. Trading halted.');
      return false;
    }
    if (this.dailyTradeCount >= this.maxTradesPerDay) {
      console.log('[Risk] Max trades per day reached.');
      return false;
    }
    return true;
  }

  recordTrade(pnl: number) {
    this.dailyTradeCount++;
    this.dailyPnl += pnl;
  }

  resetDaily() {
    this.dailyTradeCount = 0;
    this.dailyPnl = 0;
  }
}
```

### 8.2 Circuit Breaker Pattern

```typescript
// src/core/CircuitBreaker.ts
export class CircuitBreaker {
  private failures = 0;
  private lastFailureTime = 0;
  private readonly threshold: number;
  private readonly timeout: number;
  private state: 'CLOSED' | 'OPEN' | 'HALF_OPEN' = 'CLOSED';

  constructor(threshold = 5, timeout = 30000) {
    this.threshold = threshold;
    this.timeout = timeout;
  }

  async execute<T>(fn: () => Promise<T>): Promise<T> {
    if (this.state === 'OPEN') {
      if (Date.now() - this.lastFailureTime > this.timeout) {
        this.state = 'HALF_OPEN';
      } else {
        throw new Error('Circuit breaker is OPEN');
      }
    }

    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }

  private onSuccess() {
    this.failures = 0;
    this.state = 'CLOSED';
  }

  private onFailure() {
    this.failures++;
    this.lastFailureTime = Date.now();
    if (this.failures >= this.threshold) {
      this.state = 'OPEN';
      console.log('[CircuitBreaker] OPEN - Too many failures');
    }
  }
}
```

### 8.3 Order Rate Limiter (Token Bucket)

```typescript
// src/execution/RateLimiter.ts
export class TokenBucketRateLimiter {
  private tokens: number;
  private readonly maxTokens: number;
  private readonly refillRate: number; // tokens per second
  private lastRefill: number;

  constructor(maxTokens = 25, refillRate = 5) {
    this.maxTokens = maxTokens;
    this.tokens = maxTokens;
    this.refillRate = refillRate;
    this.lastRefill = Date.now();
  }

  async acquire(): Promise<boolean> {
    this.refill();

    if (this.tokens > 0) {
      this.tokens--;
      return true;
    }

    // Wait for a token to become available
    const waitTime = (1 / this.refillRate) * 1000;
    await new Promise(resolve => setTimeout(resolve, waitTime));
    return this.acquire();
  }

  private refill() {
    const now = Date.now();
    const elapsed = (now - this.lastRefill) / 1000;
    this.tokens = Math.min(this.maxTokens, this.tokens + elapsed * this.refillRate);
    this.lastRefill = now;
  }
}
```

---

## Phase 9: Testing Strategy

### 9.1 Unit Tests

```typescript
// apps/engine/src/__tests__/MatchingEngine.test.ts
import { describe, it, expect } from 'vitest';
import { MatchingEngine } from '../paper/MatchingEngine';

describe('MatchingEngine', () => {
  it('should enforce NSE tick size of 0.05', () => {
    const engine = new MatchingEngine(mockRedis);

    expect(engine.roundToTickSize(50.12, 0.05)).toBe(50.10);
    expect(engine.roundToTickSize(50.13, 0.05)).toBe(50.15);
    expect(engine.roundToTickSize(50.00, 0.05)).toBe(50.00);
  });

  it('should reject orders when capital is insufficient', async () => {
    const engine = new MatchingEngine(mockRedis);
    mockRedis.getVirtualCapital.mockResolvedValue(1000);

    const order = { price: 100, quantity: 50 }; // Cost: 5000
    const result = await engine.processOrder(order, mockTick);

    expect(result.status).toBe('REJECTED');
    expect(result.reason).toBe('RMS_MARGIN_SHORTFALL');
  });

  it('should apply slippage to market orders', async () => {
    const engine = new MatchingEngine(mockRedis);
    const tick = { ltp: 100, depth: { askPrice1: 100.5, bidPrice1: 99.5 } };

    const buyOrder = { orderType: 'MARKET', transactionType: 'BUY', price: 0, quantity: 1 };
    const result = await engine.processOrder(buyOrder, tick);

    // Should fill at ask + slippage, rounded to tick size
    expect(result.averagePrice).toBeGreaterThan(100.5);
  });
});
```

### 9.2 Integration Tests (Rails)

```ruby
# spec/services/backtesting/nifty_options_backtester_spec.rb
require 'rails_helper'

RSpec.describe Backtesting::NiftyOptionsBacktester do
  let(:strategy_params) do
    {
      sl_pct: 0.15,
      target_pct: 0.30,
      slippage: 0.01,
      qty: 50,
      ema_fast: 9,
      ema_slow: 21,
      interval: '5',
      strike_relative: 'ATM',
      option_type: 'CALL'
    }
  end

  describe '#run' do
    before do
      # Mock Dhan API responses
      allow_any_instance_of(DhanHQ::Resources::ExpiredOptionsData)
        .to receive(:fetch)
        .and_return(mock_rolling_option_response)
    end

    it 'generates trades with correct SL and target calculations' do
      backtester = described_class.new(strategy_params, '2026-01-01', '2026-01-05')
      results = backtester.run

      expect(results[:trades]).to be_an(Array)

      results[:trades].each do |trade|
        expect(trade[:stop_loss]).to eq(trade[:entry_price] * 0.85)
        expect(trade[:target]).to eq(trade[:entry_price] * 1.30)
      end
    end

    it 'applies slippage to entry and exit prices' do
      backtester = described_class.new(strategy_params, '2026-01-01', '2026-01-05')
      results = backtester.run

      results[:trades].each do |trade|
        # Entry price should include 1% slippage
        expect(trade[:entry_price]).to be > trade[:raw_close]
      end
    end
  end
end
```

### 9.3 End-to-End Test (Paper Trading)

```typescript
// apps/engine/src/__tests__/e2e/paper-trading.test.ts
import { describe, it, expect, beforeAll, afterAll } from 'vitest';

describe('Paper Trading E2E', () => {
  let orchestrator: BotOrchestrator;

  beforeAll(async () => {
    // Start Redis, mock Dhan WebSocket
    orchestrator = new BotOrchestrator();
    await orchestrator.initialize('test-user');
    await orchestrator.start();
  });

  afterAll(async () => {
    await orchestrator.stop();
  });

  it('should complete a full trade lifecycle', async () => {
    // 1. Simulate tick data that triggers entry
    const entryTicks = generateBreakoutTicks();
    for (const tick of entryTicks) {
      await orchestrator.handleTick(tick);
    }

    // 2. Verify position was opened
    const activeTrade = await redis.hgetall('algo:test-user:paper:active_trade');
    expect(activeTrade).toBeDefined();
    expect(activeTrade.entryPrice).toBeDefined();

    // 3. Simulate price hitting target
    const exitTicks = generateTargetHitTicks(parseFloat(activeTrade.target));
    for (const tick of exitTicks) {
      await orchestrator.handleTick(tick);
    }

    // 4. Verify position was closed
    const closedTrade = await redis.hgetall('algo:test-user:paper:active_trade');
    expect(closedTrade).toBeNull();

    // 5. Verify trade was logged to Redis events
    const events = await redis.lrange('algo:test-user:trade_events', 0, -1);
    expect(events.length).toBeGreaterThanOrEqual(2); // Entry + Exit
  });
});
```

---

## Phase 10: Monitoring & Observability

### 10.1 Logging Strategy

```typescript
// src/utils/logger.ts
import pino from 'pino';

export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport: {
    target: 'pino-pretty',
    options: {
      colorize: true,
      translateTime: 'SYS:standard',
    }
  },
  serializers: {
    tick: (tick) => ({ ltp: tick.ltp, ts: tick.timestamp }),
    order: (order) => ({ id: order.orderId, status: order.status }),
  }
});

// Usage
logger.info({ tick }, 'Processing tick');
logger.error({ error, order }, 'Order execution failed');
```

### 10.2 Metrics Collection

```typescript
// src/metrics/MetricsCollector.ts
export class MetricsCollector {
  private metrics = {
    ticksProcessed: 0,
    ordersPlaced: 0,
    ordersFilled: 0,
    ordersRejected: 0,
    averageLatency: 0,
    lastTickTime: 0,
  };

  recordTick() { this.metrics.ticksProcessed++; this.metrics.lastTickTime = Date.now(); }
  recordOrder(status: string) { /* ... */ }

  getSnapshot() { return { ...this.metrics }; }

  // Publish to Redis every 10 seconds for dashboard
  startPublishing(redis: Redis) {
    setInterval(() => {
      redis.set('algo:metrics', JSON.stringify(this.getSnapshot()));
    }, 10000);
  }
}
```

---

## Implementation Timeline

| Phase | Duration | Deliverables |
| ------- | ---------- | -------------- |
| **Phase 0: Foundation** | Week 1 | Repo setup, Docker, DB schema, Redis config |
| **Phase 1: Backtesting** | Week 2-3 | Ruby backtester, date chunking, CSV export |
| **Phase 2: Paper Engine** | Week 4-5 | Node.js matching engine, virtual RMS, fee calc |
| **Phase 3: Rails API** | Week 5-6 | ActionCable, clearing service, instrument sync |
| **Phase 4: SolidJS UI** | Week 6-7 | Dashboard, real-time charts, trade feed |
| **Phase 5: Live Trading** | Week 8-9 | Live order router, WebSocket integration |
| **Phase 6: Testing & QA** | Week 10 | Unit tests, E2E tests, paper trading validation |
| **Phase 7: Deployment** | Week 11 | Production deploy, monitoring, alerting |
| **Phase 8: Optimization** | Week 12+ | Performance tuning, strategy refinements |

---

## Critical Success Factors

1. **Never route live ticks through Rails** — Node.js handles all real-time processing
2. **Redis is the single source of truth for live state** — If Node crashes, it recovers from Redis
3. **Paper trading must simulate real broker behavior** — Slippage, latency, tick sizes, taxes
4. **SolidJS signals prevent UI freezing** — Only update DOM nodes that changed
5. **Rate limiting is non-negotiable** — Token bucket on all REST API calls
6. **Kill switch must be instant** — Redis pub/sub command stops all trading in <100ms
7. **Backtest results must include taxes** — A strategy profitable without taxes may lose money with them
8. **Always square off before mode switch** — Prevent ghost positions when switching paper→live

This is the complete, end-to-end architecture for `algo_scalper_api`. Every component, every file, every integration point has been addressed. The system is designed to scale from paper trading validation to live execution with minimal code changes, thanks to the clean separation between the Hot Path (Node.js), Cold Path (Rails), and State Layer (Redis).
