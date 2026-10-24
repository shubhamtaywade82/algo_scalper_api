# DhanHQ V2 Indian Markets Automated Trading Platform

**Status:** Proposed
**Version:** 1.0
**Primary Repository:** `algo_scalper_api`
**Broker SDK:** `dhanhq-client`
**Market:** Indian NSE/BSE Equity + F&O
**Initial Execution Mode:** Live Market Data + Local Paper Execution
**Future Execution Mode:** Live DhanHQ Orders
**Architecture:** Rails API + Trading Runtime + Redis + PostgreSQL + DhanHQ V2

---

# 1. Executive Summary

We are building a broker-connected automated trading platform for Indian markets using:

- Ruby on Rails
- `dhanhq-client`
- DhanHQ V2 REST APIs
- DhanHQ V2 Market Feed WebSocket
- DhanHQ V2 Order Update WebSocket
- PostgreSQL
- Redis
- Solid Queue
- Concurrent Ruby
- ActionCable
- configurable strategy/risk engines

The platform must support:

```text
NSE Equity
NSE Futures
NSE Options
BSE Equity
BSE Futures
BSE Options
Index instruments
```

The system must support:

```text
Market data ingestion
Instrument discovery
Historical data
OHLCV aggregation
Technical indicators
Market regime detection
Strategy execution
Position sizing
Risk management
Margin validation
Paper execution
Order lifecycle management
Position management
P&L
Reconciliation
Trade journal
Backtesting
Paper/live parity
Eventually live execution
```

The key architectural principle is:

> **Strategies should never know whether an order is paper or live.**

They produce an **Order Intent**.

The execution layer decides whether that intent is:

```text
Paper → simulated
Live  → DhanHQ REST
```

This gives us one strategy implementation and two execution environments.

---

# 2. Current Situation

The current `algo_scalper_api` already contains significant infrastructure.

The repository currently describes:

```text
TradingSystem::Supervisor
Live::MarketFeedHubService
Live::RiskManagerService
TradingSystem::OrderRouter
Live::PaperPnlRefresher
Live::ExitEngine
Positions::ActiveCacheService
Live::ReconciliationService
Live::OrderUpdateHub
```

It also uses:

```text
PostgreSQL
Redis
Solid Queue
Rails API
separate trading daemon
```

The documented architecture explicitly uses Redis for real-time state and PostgreSQL for durable state.

The existing DhanHQ integration already has:

```text
DhanHQ.configure_with_env
DhanHQ::Client
Dhan::TokenManager
DhanhqProvider
MarketFeedHub
OrderUpdateHub
GatewayPaper
GatewayLive
PositionTracker
OptionChain::DhanAdapter
InstrumentsImportJob
```

The current integration also already has separate paper/live gateways.

Therefore:

> **Do not rebuild the broker integration from scratch. Generalize it.**

---

# 3. Product Vision

The final product should look conceptually like this:

```text
                       ┌───────────────────────┐
                       │       DhanHQ V2       │
                       │                       │
                       │ REST + Market WS      │
                       │ Order Update WS       │
                       └───────────┬───────────┘
                                   │
                  ┌────────────────┴────────────────┐
                  │                                 │
             Market Data                       Trading APIs
                  │                                 │
                  ▼                                 ▼
        ┌──────────────────┐             ┌──────────────────┐
        │ Market Data      │             │ Broker Gateway   │
        │ Gateway          │             │                  │
        └────────┬─────────┘             └────────┬─────────┘
                 │                                │
                 ▼                                ▼
        ┌──────────────────┐             ┌──────────────────┐
        │ Market State     │             │ Order Lifecycle  │
        │ Redis            │             │                  │
        └────────┬─────────┘             └────────┬─────────┘
                 │                                │
                 └──────────────┬─────────────────┘
                                ▼
                    ┌──────────────────────┐
                    │ Trading Runtime      │
                    │                      │
                    │ Signal               │
                    │ Strategy             │
                    │ Portfolio            │
                    │ Risk                 │
                    │ Margin               │
                    │ Position             │
                    └──────────┬───────────┘
                               │
                     ┌─────────┴─────────┐
                     │                   │
                     ▼                   ▼
               Paper Gateway        Live Gateway
                     │                   │
                     ▼                   ▼
               Simulator             DhanHQ
```

---

# 4. Critical Architectural Decision

## Live market data + paper execution

The preferred paper-trading architecture is:

```text
DhanHQ live market data
        ↓
real tick
        ↓
strategy
        ↓
paper order
        ↓
paper fill simulator
        ↓
paper position
        ↓
real LTP
        ↓
paper P&L
```

Do **not** make paper trading depend on DhanHQ accepting fake orders.

Instead:

```text
DhanHQ = market-data authority
DhanHQ = broker/account authority in LIVE mode

Our application = execution simulator in PAPER mode
```

This gives us deterministic paper trading while still using genuine live market conditions.

Dhan provides live market data through WebSockets and market snapshots through APIs.

---

# 5. Product Goals

## P0 Goals

### G1 — Complete market-data pipeline

Support:

```text
Instrument master
Security IDs
LTP
Ticker
Quote
Depth
OHLCV
Historical candles
Option chain
OI
IV
Greeks
```

### G2 — Generic instrument model

The system must not be options-specific.

A strategy should be able to operate on:

```text
RELIANCE equity
NIFTY future
NIFTY CE
BANKNIFTY PE
SENSEX option
```

using the same instrument abstraction.

### G3 — Paper execution

The system must simulate:

```text
BUY
SELL
LIMIT
MARKET
STOP
partial fills
fees
slippage
positions
realized P&L
unrealized P&L
margin
```

### G4 — Strategy/execution separation

A strategy must not call:

```ruby
DhanHQ::Models::Order
```

directly.

Instead:

```text
Strategy
   ↓
OrderIntent
   ↓
Risk
   ↓
ExecutionGateway
```

### G5 — Live-readiness

The paper gateway and live gateway must implement the same interface.

```ruby
ExecutionGateway
```

Implementations:

```ruby
GatewayPaper
GatewayLive
```

### G6 — Reconciliation

The system must continuously compare:

```text
Application state
vs
Dhan state
```

when live trading is enabled.

---

# 6. Non-Goals

Initial version will not attempt to:

- predict the market using an LLM
- automatically discover profitable strategies
- support every possible order type immediately
- provide HFT-grade co-location
- guarantee fills
- guarantee profitability
- perform naked derivative selling without explicit risk approval
- automatically enable live capital
- treat backtest results as proof of production profitability

---

# 7. Market Coverage

The platform should eventually support:

## Equity

```text
NSE_EQ
BSE_EQ
```

Examples:

```text
RELIANCE
HDFCBANK
INFY
TCS
ICICIBANK
```

## Futures

```text
NSE_FNO
BSE_FNO
```

Examples:

```text
NIFTY FUT
BANKNIFTY FUT
RELIANCE FUT
```

## Options

```text
NSE_FNO
BSE_FNO
```

Examples:

```text
NIFTY CE
NIFTY PE
BANKNIFTY CE
BANKNIFTY PE
STOCK CE
STOCK PE
```

The exact availability of a specific contract must always come from the current DhanHQ instrument master.

---

# 8. Technology Stack

## Application

```text
Ruby 3.x
Ruby on Rails 7/8
Rails API
```

## Broker

```text
dhanhq-client
DhanHQ V2 REST
DhanHQ V2 WebSocket
```

## Database

```text
PostgreSQL
```

## Low-latency state

```text
Redis
Concurrent::Map
```

## Background processing

```text
Solid Queue
```

## Real-time UI

```text
ActionCable
Next.js / React
```

## Testing

```text
RSpec
WebMock
VCR
custom WebSocket test transport
```

## Deployment

Recommended:

```text
AWS EC2
Docker
PostgreSQL
ElastiCache Redis
CloudWatch
GitHub Actions
```

---

# 9. DhanHQ Communication Model

There are four distinct communication channels.

## Channel A — Instrument/Reference REST

Used for:

```text
Instrument master
Security IDs
Contract metadata
```

---

## Channel B — Market REST

Used for:

```text
LTP
Quote
Option chain
Historical data
Intraday data
Margin calculation
```

---

## Channel C — Market WebSocket

Used for:

```text
real-time ticks
LTP
quote
depth
```

DhanHQ's V2 market feed uses persistent WebSocket connections. The application sends JSON subscription messages and receives binary market-data packets. The current Dhan documentation states that one connection can handle up to 5,000 instruments, with up to five connections per user.

Your `dhanhq-client` already contains a WebSocket packet parser and dedicated market-feed documentation.

---

## Channel D — Order Update WebSocket

Used for:

```text
order accepted
order pending
order traded
order rejected
order cancelled
partial fills
```

The broker's order-update WebSocket should be considered the primary live order-event stream.

The repository already has dedicated order-update documentation and Rails integration.

---

# 10. Complete Wiring

This is the actual wiring we want.

```text
                       DHANHQ
                          │
       ┌──────────────────┼───────────────────┐
       │                  │                   │
       ▼                  ▼                   ▼
 Instrument REST      Market REST        Market WS
       │                  │                   │
       │                  │                   ▼
       │                  │             MarketFeedHub
       │                  │                   │
       ▼                  ▼                   ▼
 Instrument DB       Data Services       TickCache
       │                  │                   │
       └────────────┬─────┴──────────────┬────┘
                    │                    │
                    ▼                    ▼
               PostgreSQL              Redis
                    │                    │
                    └─────────┬──────────┘
                              ▼
                       Trading Runtime
                              │
             ┌────────────────┼────────────────┐
             │                │                │
             ▼                ▼                ▼
         Strategy           Risk            Portfolio
             │                │                │
             └────────────────┼────────────────┘
                              ▼
                         OrderIntent
                              │
                              ▼
                        Risk Approval
                              │
                    ┌─────────┴──────────┐
                    │                    │
                    ▼                    ▼
               GatewayPaper         GatewayLive
                    │                    │
                    ▼                    ▼
              Fill Simulator        DhanHQ REST
                    │                    │
                    │                    ▼
                    │              Order Update WS
                    │                    │
                    └─────────┬──────────┘
                              ▼
                       Position Engine
                              │
                              ▼
                       P&L / Risk / UI
```

---

# 11. Instrument Lifecycle

This is the first thing the system needs to get right.

## Step 1 — Download instrument master

Daily job:

```text
08:30-08:45 IST
      ↓
Download Dhan instrument CSV
      ↓
Parse
      ↓
Validate
      ↓
Upsert
```

The existing application already has `InstrumentsImportJob`, which synchronizes DhanHQ's instrument master and creates derivative records.

---

# 12. Instrument Data Model

Recommended generalized model:

```ruby
Instrument
```

Fields:

```text
id
exchange
exchange_segment
security_id
symbol
trading_symbol
custom_symbol
isin
instrument_type
underlying_security_id
underlying_symbol

expiry_date
strike_price
option_type

lot_size
tick_size

contract_multiplier

active
tradable

metadata
```

Instrument types:

```text
EQUITY
INDEX
FUTURE
OPTION
ETF
```

Option type:

```text
CALL
PUT
NA
```

---

# 13. Derivative Model

Keep derivative-specific metadata separate where useful.

```text
Derivative
---------
instrument_id
underlying_id
expiry_date
strike_price
option_type
lot_size
contract_type
```

This allows:

```text
Instrument
    ↓
Derivative
```

without polluting equity instruments with options-only attributes.

---

# 14. Instrument Resolution

Strategies should never manually construct:

```text
security_id = "12345"
```

Instead:

```ruby
InstrumentResolver.resolve(
  exchange: :nse,
  symbol: "NIFTY",
  instrument_type: :option,
  expiry: expiry,
  strike: strike,
  option_type: :call
)
```

Returns:

```ruby
Instrument
```

Then:

```ruby
instrument.security_id
instrument.exchange_segment
instrument.lot_size
instrument.tick_size
```

This eliminates hard-coded security IDs.

---

# 15. Market Data Architecture

## MarketFeedHub

The existing `Live::MarketFeedHub` should become the central DhanHQ market-data ingress.

Its responsibilities:

```text
connect
authenticate
subscribe
unsubscribe
receive
decode
normalize
cache
publish
reconnect
resubscribe
```

It should NOT:

```text
calculate strategy signals
place orders
calculate risk
```

---

# 16. Tick Processing

Raw Dhan packet:

```text
binary packet
```

↓

```text
DhanHQ packet parser
```

↓

normalized event:

```ruby
MarketTick.new(
  exchange_segment: "NSE_EQ",
  security_id: "1333",
  timestamp: ...,
  ltp: 1524.25,
  volume: ...,
  bid: ...,
  ask: ...
)
```

↓

```text
TickCache
```

---

# 17. TickCache

Use two levels.

## L1

```text
Concurrent::Map
```

for ultra-fast runtime reads.

## L2

```text
Redis
```

for:

```text
shared state
restart recovery
other processes
dashboard
risk services
```

Existing architecture already follows this Redis-first pattern.

---

# 18. Tick Redis Structure

Example:

```text
market:tick:NSE_EQ:1333
```

```json
{
  "security_id": "1333",
  "exchange_segment": "NSE_EQ",
  "ltp": 1524.25,
  "bid": 1524.20,
  "ask": 1524.30,
  "volume": 1820345,
  "timestamp": 1786874400
}
```

---

# 19. Candle Engine

Ticks should feed the candle engine.

```text
Tick
 ↓
1m Candle
 ↓
5m Candle
 ↓
15m Candle
 ↓
30m Candle
 ↓
1H Candle
 ↓
Daily Candle
```

For every timeframe:

```text
open
high
low
close
volume
timestamp
```

Store finalized candles in PostgreSQL.

Keep current incomplete candle in Redis.

---

# 20. Historical Data

Historical REST API should be used for:

```text
initial backfill
strategy warm-up
backtesting
missing candle recovery
restart recovery
data validation
```

It should NOT be used as the primary real-time feed.

Correct architecture:

```text
Historical REST
      ↓
PostgreSQL
      ↓
Strategy warm-up

Live WebSocket
      ↓
Redis
      ↓
Runtime
```

---

# 21. Option Chain

Option chain is different from tick streaming.

Use REST for:

```text
expiry discovery
strike discovery
OI
IV
Greeks
bid
ask
LTP
volume
```

The current application already uses `Adapters::OptionChain::DhanAdapter` and intentionally fetches live option-chain data even in paper mode.

Recommended cache:

```text
option_chain:NIFTY:2026-08-20
```

with a short TTL.

Do not call option-chain REST on every tick.

---

# 22. Market Data Responsibilities

| Data | Primary source |
|---|---|
| Instrument master | REST/CSV |
| LTP | WebSocket |
| Tick | WebSocket |
| Quote | WebSocket / REST snapshot |
| Depth | WebSocket |
| Historical candles | REST |
| Intraday candles | REST |
| Option chain | REST |
| OI | Option chain / quote |
| IV | Option chain |
| Greeks | Option chain |
| Account funds | REST |
| Positions | REST |
| Orders | REST + Order WS |

---

# 23. Trading Runtime

The trading runtime is the heart of the system.

It should run separately from Rails/Puma.

Existing architecture already follows this model: the trading daemon is separated from the web server and job worker.

Recommended:

```text
Puma
 └── Rails API

Trading Process
 └── TradingSystem::Supervisor

Solid Queue
 └── scheduled/background work

Next.js
 └── dashboard
```

---

# 24. Why Trading Must Be a Separate Process

Do NOT run the trading engine inside:

```text
Puma request thread
```

because:

```text
HTTP request lifecycle ≠ trading lifecycle
```

The trading process needs:

```text
persistent WebSockets
long-running loops
reconnect handling
tick processing
risk monitoring
position monitoring
```

---

# 25. Supervisor

Existing:

```text
TradingSystem::Supervisor
```

should become the runtime orchestrator.

Recommended services:

```text
MarketDataService
InstrumentService
SignalService
StrategyService
RiskService
MarginService
ExecutionService
PositionService
PortfolioService
ReconciliationService
HealthService
```

---

# 26. Strategy Contract

Every strategy should implement something like:

```ruby
Strategy
  # evaluate(context)
  # produce OrderIntent / NoTrade
end
```

Example:

```ruby
class VWAPMomentumStrategy
  def evaluate(context)
    ...
  end
end
```

Return:

```ruby
Signal
```

not an order.

---

# 27. Signal Contract

Example:

```json
{
  "strategy": "vwap_momentum",
  "instrument_id": 123,
  "direction": "LONG",
  "confidence": 0.82,
  "reason": "VWAP reclaim + volume expansion",
  "timestamp": "..."
}
```

---

# 28. Order Intent

This is one of the most important abstractions.

```ruby
OrderIntent
```

Example:

```json
{
  "strategy": "vwap_momentum",
  "instrument_id": 123,
  "side": "BUY",
  "quantity": 10,
  "order_type": "MARKET",
  "product_type": "INTRADAY",
  "validity": "DAY",
  "stop_loss": 1450,
  "target": 1510
}
```

The strategy does not know:

```text
DhanHQ
REST
WebSocket
paper
live
```

---

# 29. Multi-Leg Order Intent

For F&O:

```json
{
  "strategy": "bull_put_spread",
  "legs": [
    {
      "instrument_id": 1001,
      "side": "BUY",
      "quantity": 75
    },
    {
      "instrument_id": 1002,
      "side": "SELL",
      "quantity": 75
    }
  ]
}
```

This is essential for:

```text
spreads
straddles
strangles
iron condors
calendars
hedges
pairs
```

---

# 30. Risk Engine

Risk must operate before execution.

Pipeline:

```text
Signal
 ↓
Strategy validation
 ↓
Portfolio exposure
 ↓
Risk limits
 ↓
Position sizing
 ↓
Margin
 ↓
Execution approval
```

Risk rules:

```text
max daily loss
max trade loss
max position size
max exposure
max leverage
max open positions
max strategy exposure
max sector exposure
max instrument exposure
max margin utilization
cooldown
duplicate trade prevention
```

---

# 31. Margin Engine

Margin should have two layers.

## Layer 1 — Local estimation

Fast:

```text
equity cash requirement
futures approximate margin
option premium requirement
defined-risk spread max loss
```

## Layer 2 — Broker validation

Before execution:

```text
DhanHQ margin API
```

This is authoritative.

The DhanHQ API documentation exposes margin-related APIs alongside trading APIs.

---

# 32. Execution Architecture

Define:

```ruby
ExecutionGateway
```

Interface:

```ruby
place_order(intent)
cancel_order(order)
modify_order(order, params)
close_position(position)
```

Implementations:

```ruby
Orders::GatewayPaper
Orders::GatewayLive
```

---

# 33. Paper Gateway

Paper gateway receives:

```text
OrderIntent
```

and simulates:

```text
order acknowledgement
fill
average price
fees
slippage
position
P&L
```

It never sends an order to DhanHQ.

---

# 34. Paper Fill Model

Do not make every paper market order magically fill at LTP.

That produces fantasy results.

Recommended:

### Market BUY

```text
fill = ask
```

### Market SELL

```text
fill = bid
```

If bid/ask unavailable:

```text
fill = LTP + configured slippage
```

For limit orders:

```text
BUY:
    fill only when ask <= limit

SELL:
    fill only when bid >= limit
```

---

# 35. Paper Slippage

Config:

```yaml
paper_trading:
  slippage:
    enabled: true
    market_buy_ticks: 1
    market_sell_ticks: 1
```

For options:

```text
spread-aware fill
```

should be preferred.

---

# 36. Paper Fees

The simulator should calculate:

```text
brokerage
STT
exchange transaction charges
SEBI charges
GST
stamp duty
other applicable charges
```

The fee model must be configurable and periodically updated.

---

# 37. Paper Wallet

Create:

```ruby
PaperAccount
```

Fields:

```text
starting_capital
cash
available_margin
used_margin
realized_pnl
unrealized_pnl
fees
equity
```

Example:

```text
Starting capital = ₹500,000

Cash             ₹500,000
Used margin      ₹100,000
Available margin ₹400,000
Realized P&L     ₹5,000
Unrealized P&L   ₹2,000
Equity           ₹507,000
```

---

# 38. Paper Positions

```ruby
PaperPosition
```

Fields:

```text
account_id
instrument_id
side
quantity
average_entry_price
average_exit_price
realized_pnl
unrealized_pnl
opened_at
closed_at
status
```

---

# 39. Order State Machine

Use:

```text
CREATED
 ↓
RISK_PENDING
 ↓
APPROVED
 ↓
SUBMITTED
 ↓
ACKNOWLEDGED
 ↓
PARTIALLY_FILLED
 ↓
FILLED
```

Terminal:

```text
CANCELLED
REJECTED
EXPIRED
FAILED
```

---

# 40. Multi-Leg State Machine

For a spread:

```text
STRATEGY_CREATED
       ↓
RISK_APPROVED
       ↓
MARGIN_APPROVED
       ↓
HEDGE_PENDING
       ↓
HEDGE_FILLED
       ↓
SHORT_LEG_PENDING
       ↓
SHORT_LEG_FILLED
       ↓
STRATEGY_ACTIVE
```

Failure:

```text
HEDGE_FILLED
      ↓
SHORT_LEG_FAILED
      ↓
EMERGENCY_FLATTEN
```

This is mandatory for live trading.

---

# 41. Live Execution

Live gateway:

```text
OrderIntent
 ↓
Risk
 ↓
Margin
 ↓
Orders::GatewayLive
 ↓
DhanHQ::Models::Order
 ↓
POST /v2/orders
 ↓
Dhan order_id
```

Your existing Rails integration already follows this basic path through `Orders::GatewayLive` and `Orders::Placer`.

---

# 42. Critical Rule: Do Not Retry POST Orders Blindly

DhanHQ order writes are not safe to blindly retry after an HTTP timeout.

Scenario:

```text
POST order
 ↓
Dhan receives order
 ↓
network timeout
 ↓
Rails thinks request failed
 ↓
automatic retry
```

could create:

```text
duplicate order
```

The existing gem's Rails integration explicitly warns about this.

Therefore:

```text
Order POST timeout
      ↓
DO NOT blindly retry
      ↓
query order state
      ↓
resolve using correlation/client ID
      ↓
only then decide whether another action is required
```

---

# 43. Correlation IDs

Every order must have:

```text
strategy_id
trade_id
order_intent_id
leg_id
client correlation ID
```

Example:

```text
TRD-20260816-000123
TRD-20260816-000123-L1
TRD-20260816-000123-L2
```

This makes debugging and reconciliation possible.

---

# 44. Order Update Flow

Live:

```text
DhanHQ
  │
  ▼
Order Update WebSocket
  │
  ▼
OrderUpdateHub
  │
  ▼
OrderUpdateHandler
  │
  ├── Update Order
  ├── Update Fill
  ├── Update Position
  ├── Update P&L
  └── Publish Event
```

The current architecture already contains this pattern.

---

# 45. REST vs WebSocket Rule

Use:

```text
WebSocket = events
REST = authority/reconciliation
```

Never make WebSocket the only source of truth.

For example:

```text
WebSocket says FILLED
```

then periodically:

```text
GET order
GET positions
GET trades
```

to verify state.

---

# 46. Reconciliation

Every 30–60 seconds during live trading:

```text
Dhan orders
Dhan trades
Dhan positions
Dhan funds
```

compare against:

```text
local orders
local fills
local positions
local account
```

Existing `Live::ReconciliationService` already has this responsibility.

---

# 47. Reconciliation States

```text
MATCHED
LOCAL_ONLY
BROKER_ONLY
QUANTITY_MISMATCH
PRICE_MISMATCH
STATUS_MISMATCH
UNKNOWN
```

Any unresolved broker/local mismatch should trigger:

```text
risk halt
```

for the affected strategy/account.

---

# 48. Position Engine

Position engine should be broker-neutral.

Input:

```text
Fill
```

Output:

```text
Position
```

Responsibilities:

```text
open
increase
reduce
reverse
close
average
calculate realized P&L
calculate unrealized P&L
```

---

# 49. Portfolio Engine

Aggregates:

```text
positions
cash
margin
exposure
P&L
drawdown
sector exposure
underlying exposure
strategy exposure
```

---

# 50. Risk Monitoring

Risk should run continuously.

Fast path:

```text
tick
 ↓
position
 ↓
P&L
 ↓
risk rule
 ↓
exit
```

Slow path:

```text
every 1–5 sec
 ↓
scan all active positions
 ↓
risk enforcement
```

Your existing architecture already uses both per-tick and periodic enforcement paths.

---

# 51. Exit Engine

One component should own exits.

```text
ExitEngine
```

Reasons:

```text
STOP_LOSS
TARGET
TRAILING_STOP
TIME_EXIT
STRATEGY_INVALIDATION
DAILY_LOSS_LIMIT
KILL_SWITCH
EXPIRY
SYSTEM_FAILURE
MANUAL_EXIT
```

---

# 52. Kill Switch

System-level:

```text
TRADING_ENABLED=false
```

Account-level:

```text
account_halted=true
```

Strategy-level:

```text
strategy_enabled=false
```

Instrument-level:

```text
instrument_blocked=true
```

A kill switch must be able to prevent new orders immediately.

DhanHQ itself also exposes a kill-switch capability, which can be incorporated as an emergency broker-side control for live operation.

---

# 53. Paper Trading Flow

Example:

```text
09:30
  ↓
NIFTY tick arrives
  ↓
TickCache
  ↓
Candle updated
  ↓
Signal engine
  ↓
BUY NIFTY 25,000 CE
  ↓
Risk approved
  ↓
Paper Gateway
  ↓
Read CE bid/ask
  ↓
Simulated fill at ask
  ↓
Paper Position created
  ↓
Real WebSocket CE ticks
  ↓
Paper P&L updates
  ↓
Target reached
  ↓
Paper SELL
  ↓
Position closed
  ↓
Trade journal
```

No real order is sent.

---

# 54. Live Trading Flow

Exactly the same upstream pipeline:

```text
Market data
 ↓
Signal
 ↓
Risk
 ↓
OrderIntent
 ↓
GatewayLive
 ↓
DhanHQ REST
 ↓
Order ID
 ↓
Order Update WS
 ↓
Fill
 ↓
Position
 ↓
P&L
```

This is the most important design principle.

---

# 55. Paper/Live Parity

The strategy must not contain:

```ruby
if paper?
```

Instead:

```ruby
gateway.place(order_intent)
```

Configuration decides:

```yaml
execution:
  mode: paper
```

or:

```yaml
execution:
  mode: live
```

---

# 56. Configuration

Example:

```yaml
environment:
  mode: paper

market:
  exchanges:
    - NSE
    - BSE

segments:
    - EQUITY
    - FNO

execution:
  mode: paper

paper:
  initial_capital: 500000
  slippage_enabled: true
  fees_enabled: true
  fill_model: bid_ask

risk:
  max_daily_loss_pct: 3
  max_trade_risk_pct: 1
  max_margin_utilization_pct: 75
  max_open_positions: 10

trading:
  start_time: "09:20"
  end_time: "15:15"

dhanhq:
  market_feed_enabled: true
  order_updates_enabled: true
  enable_orders: false
```

---

# 57. Environment Safety

The application should require explicit live configuration.

Recommended:

```text
PAPER
SIMULATION
LIVE
```

not merely:

```text
true / false
```

For live:

```text
TRADING_ENV=live
PLACE_ORDER=true
DHANHQ_ENABLE_ORDERS=true
```

all must agree.

Additionally:

```text
LIVE_CAPITAL_APPROVED=true
```

should be a deliberate operational gate.

---

# 58. Database Schema

Core tables:

```text
accounts
instruments
derivatives
market_sessions

candles
market_ticks_archive

strategies
strategy_configs
strategy_runs
signals

order_intents
orders
order_legs
fills

positions
position_legs

paper_accounts
paper_orders
paper_fills
paper_positions

risk_events
risk_limits
margin_snapshots

trade_journals
trade_analytics

reconciliation_runs
reconciliation_discrepancies

dhan_access_tokens
settings
system_events
```

---

# 59. Order Intent Schema

```text
order_intents
-------------
id
strategy_id
strategy_run_id
trade_id
instrument_id
side
quantity
order_type
product_type
validity
limit_price
trigger_price

risk_approved
margin_approved

status

created_at
updated_at
```

---

# 60. Orders Schema

```text
orders
------
id
order_intent_id

gateway
broker
broker_order_id
correlation_id

instrument_id
side
quantity

order_type
product_type
validity

requested_price
average_fill_price
filled_quantity
remaining_quantity

status

submitted_at
filled_at
cancelled_at
rejected_at
```

---

# 61. Fills Schema

```text
fills
-----
id
order_id
quantity
price
fees
slippage
exchange_trade_id
executed_at
```

---

# 62. Position Schema

```text
positions
---------
id
account_id
instrument_id

side
quantity
average_price

realized_pnl
unrealized_pnl
fees

status

opened_at
closed_at
```

---

# 63. Strategy Registry

Strategies should be registered:

```ruby
StrategyRegistry.register(
  "vwap_momentum",
  Strategies::VwapMomentum
)

StrategyRegistry.register(
  "orb",
  Strategies::OpeningRangeBreakout
)

StrategyRegistry.register(
  "long_option_momentum",
  Strategies::LongOptionMomentum
)
```

Eventually:

```text
equity
futures
options
spreads
pairs
statistical
```

---

# 64. Strategy Context

Every strategy receives:

```ruby
StrategyContext
```

containing:

```text
market snapshot
instrument
candles
indicators
portfolio
positions
risk state
account state
time
configuration
```

Not raw DhanHQ objects.

---

# 65. Indicator Engine

Generic:

```text
SMA
EMA
VWAP
RSI
MACD
ATR
ADX
Bollinger Bands
Supertrend
Volume
OI
IV
Greeks
```

The engine should consume:

```text
CandleSeries
OptionChain
MarketSnapshot
```

and return deterministic features.

---

# 66. Market Regime Engine

Classify:

```text
TREND_UP
TREND_DOWN
RANGE
HIGH_VOLATILITY
LOW_VOLATILITY
BREAKOUT
BREAKDOWN
UNKNOWN
```

Strategies can then define:

```text
allowed regimes
```

---

# 67. Strategy Selection

Eventually:

```text
Market Regime
       ↓
Strategy Selector
       ↓
Candidate Strategies
       ↓
Risk Scoring
       ↓
Best Eligible Strategy
       ↓
Order Intent
```

But initially:

```text
one configured strategy at a time
```

is safer.

---

# 68. API Layer

Rails API should expose:

```text
GET /api/health

GET /api/instruments
GET /api/instruments/:id

GET /api/market/:security_id
GET /api/candles

GET /api/strategies
POST /api/strategies/:id/start
POST /api/strategies/:id/stop

GET /api/signals

GET /api/orders
GET /api/orders/:id

GET /api/positions

GET /api/portfolio

GET /api/risk
GET /api/margin

GET /api/trades
GET /api/trades/:id

GET /api/reconciliation

POST /api/circuit_breaker/trip
DELETE /api/circuit_breaker/trip
```

The existing application already exposes several health, dashboard, positions, settings and circuit-breaker endpoints.

---

# 69. ActionCable

Use ActionCable only for UI-facing updates.

```text
Dhan WebSocket
       ↓
MarketFeedHub
       ↓
Redis
       ↓
Trading runtime
       ↓
ActionCable
       ↓
Dashboard
```

Do NOT use ActionCable as the internal trading event bus.

---

# 70. Internal Events

Eventually introduce a proper internal event model:

```text
MarketTickReceived
CandleClosed
SignalGenerated
OrderIntentCreated
OrderApproved
OrderSubmitted
OrderFilled
PositionOpened
PositionUpdated
RiskTriggered
ExitRequested
PositionClosed
ReconciliationMismatch
```

The existing architecture currently uses direct service calls rather than a central event bus.

That is acceptable for now.

Do not introduce Kafka just because the system is "big."

Redis + PostgreSQL + direct service calls are sufficient at this stage.

---

# 71. Redis Responsibilities

Redis should contain ephemeral runtime state:

```text
latest ticks
latest quotes
active positions
live P&L
risk state
strategy runtime state
WebSocket status
locks
idempotency keys
circuit breaker
```

Example:

```text
trading:system:status

trading:risk:daily_pnl

trading:position:123

market:tick:NSE_FNO:52175

strategy:orb:NIFTY:state
```

---

# 72. PostgreSQL Responsibilities

PostgreSQL stores durable truth:

```text
orders
fills
positions
signals
trades
strategies
instruments
candles
risk events
reconciliation
audit logs
```

---

# 73. Locks

Use Redis locks for:

```text
one strategy instance
one instrument entry
one position exit
one reconciliation process
one token refresh
```

Example:

```text
lock:order:exit:position:123
```

---

# 74. DhanHQ Rate Limiting

The DhanHQ API has separate rate limits for order/data/quote/non-trading categories. The uploaded Dhan documentation records, for example, 10 order API requests/sec, 5 data requests/sec and 1 quote request/sec, with additional minute/hour/day limits.

Therefore the client layer needs:

```text
RateLimiter
RequestQueue
Backoff
CircuitBreaker
Metrics
```

The existing gem already has rate-limit-related infrastructure, and the Rails initializer additionally normalizes 429 handling.

---

# 75. WebSocket Reliability

Market feed:

```text
CONNECT
 ↓
AUTHENTICATE
 ↓
SUBSCRIBE
 ↓
RECEIVE
 ↓
HEARTBEAT
 ↓
RECONNECT
 ↓
RESUBSCRIBE
```

On disconnect:

```text
mark feed unhealthy
 ↓
reconnect
 ↓
resubscribe
 ↓
backfill missing candles
 ↓
resume strategy
```

Dhan's market feed uses server ping/pong; failure to respond can result in connection closure.

---

# 76. Stale Data Protection

Every tick must have:

```text
timestamp
received_at
```

Calculate:

```text
data_age_ms
```

If:

```text
data_age > threshold
```

strategy must not enter new trades.

Example:

```text
Equity: 2 seconds
Futures: 1 second
Options: configurable
```

For exits, stale data should trigger a stronger safety path.

---

# 77. Market Session Engine

System should know:

```text
PRE_OPEN
OPEN
CLOSED
POST_CLOSE
HOLIDAY
EXPIRY
SPECIAL_SESSION
```

Do not hard-code:

```text
9:15
15:30
```

in strategies.

Use:

```ruby
MarketSession.current
```

---

# 78. Trading Calendar

Maintain:

```text
exchange
date
session_open
session_close
special_session
holiday
expiry
```

This becomes critical for:

```text
expiry strategies
EOD exits
historical backtests
paper trading
```

---

# 79. Paper Trading Day Lifecycle

```text
08:00
 ↓
Load instruments
 ↓
Validate token
 ↓
Connect market feed
 ↓
Load previous candles
 ↓
Warm indicators
 ↓
Initialize paper account
 ↓
09:15
 ↓
Trading enabled
 ↓
Signals
 ↓
Paper execution
 ↓
Risk monitoring
 ↓
15:15
 ↓
EOD square-off
 ↓
Reconciliation
 ↓
Daily journal
 ↓
Performance report
```

---

# 80. Startup Lifecycle

```text
Rails boot
 ↓
Load configuration
 ↓
Validate Dhan credentials
 ↓
Load instrument cache
 ↓
Initialize Redis
 ↓
Initialize PostgreSQL
 ↓
Initialize DhanHQ client
 ↓
Start MarketFeedHub
 ↓
Start OrderUpdateHub if LIVE
 ↓
Synchronize positions
 ↓
Start strategy runtime
 ↓
Start risk engine
 ↓
READY
```

---

# 81. Health Model

Expose:

```text
Dhan REST
Dhan Market WS
Dhan Order WS
Redis
PostgreSQL
Trading Runtime
Instrument Master
Token
Risk Engine
Reconciliation
```

Example:

```json
{
  "status": "healthy",
  "market_feed": "connected",
  "order_feed": "connected",
  "redis": "connected",
  "database": "connected",
  "token": "valid",
  "trading": "paper",
  "reconciliation": "healthy"
}
```

---

# 82. Observability

Every important event must be logged with:

```text
timestamp
request_id
trade_id
strategy_id
order_id
instrument_id
event
latency
status
error
```

Metrics:

```text
tick_latency
strategy_latency
order_latency
fill_latency
websocket_reconnects
REST_errors
429_count
order_rejections
paper_slippage
risk_events
reconciliation_mismatches
```

---

# 83. Paper Trading Performance

Paper trading should measure:

```text
gross P&L
net P&L
fees
slippage
win rate
average win
average loss
expectancy
profit factor
max drawdown
Sharpe
Sortino
MAE
MFE
```

Also:

```text
signal → simulated fill latency
```

---

# 84. Paper vs Backtest Comparison

Every paper trade should retain:

```text
strategy version
configuration version
signal timestamp
market snapshot
expected entry
actual simulated fill
exit
fees
slippage
```

Then compare:

```text
Backtest
vs
Paper
```

This identifies:

```text
lookahead bias
slippage assumptions
fill assumptions
data leakage
signal timing problems
```

---

# 85. Strategy Versioning

Every trade should record:

```text
strategy_name
strategy_version
configuration_version
code_commit_sha
```

Example:

```text
ORB
v3.2
config-20260815
commit=a82f91c
```

This is essential for reproducibility.

---

# 86. Paper Trading Safety Rules

Paper mode must guarantee:

```text
GatewayPaper cannot instantiate GatewayLive
GatewayPaper cannot call DhanHQ order endpoint
PLACE_ORDER ignored
LIVE credentials cannot change gateway automatically
```

Prefer compile/configuration separation where possible.

---

# 87. Live Safety Gates

Live requires all:

```text
TRADING_ENV=live
PAPER_TRADING=false
DHANHQ_ENABLE_ORDERS=true
PLACE_ORDER=true
LIVE_CAPITAL_APPROVED=true
```

Additionally:

```text
risk engine healthy
market feed healthy
order feed healthy
reconciliation healthy
token valid
clock synchronized
```

Otherwise:

```text
NO NEW ORDERS
```

---

# 88. Failure Handling

## Market WebSocket disconnect

```text
stop new entries
attempt reconnect
resubscribe
backfill
resume
```

## Order WebSocket disconnect

```text
continue only with caution
poll REST order book
reconcile
reconnect
```

## Redis unavailable

```text
halt trading
```

## PostgreSQL unavailable

```text
halt new trading
```

## Dhan REST unavailable

```text
halt new entries
continue emergency position management if possible
```

## Unknown order state

```text
DO NOT RETRY
reconcile first
```

---

# 89. Security

Never store:

```text
DHAN_ACCESS_TOKEN
DHAN_PIN
DHAN_TOTP_SECRET
```

in Git.

Use:

```text
AWS Secrets Manager
Rails encrypted credentials
environment secrets
```

Access tokens must remain confidential. Dhan explicitly advises users not to share API access tokens with untrusted platforms or individuals.

Dhan currently states that API access tokens have 24-hour validity, so token lifecycle management is a first-class production concern.

Your current application already has a token-provider abstraction and token-healing path.

---

# 90. Recommended Repository Structure

## dhanHQ-client

Remain the broker SDK:

```text
dhanhq-client/
├── lib/
│   └── DhanHQ/
│       ├── client.rb
│       ├── models/
│       ├── resources/
│       ├── ws/
│       │   ├── client.rb
│       │   ├── market_feed.rb
│       │   ├── order_updates.rb
│       │   └── websocket_packet_parser.rb
│       └── rate_limiter.rb
│
├── docs/
│   ├── RAILS_INTEGRATION.md
│   ├── WEBSOCKET_PROTOCOL.md
│   └── ...
│
└── spec/
```

The gem already contains dedicated WebSocket protocol, Rails integration, market-feed and order-update documentation.

---

# 91. algo_scalper_api Structure

Generalize the current application toward:

```text
app/
├── models/
│   ├── account.rb
│   ├── instrument.rb
│   ├── derivative.rb
│   ├── candle.rb
│   ├── strategy.rb
│   ├── signal.rb
│   ├── order_intent.rb
│   ├── order.rb
│   ├── order_leg.rb
│   ├── fill.rb
│   ├── position.rb
│   ├── trade.rb
│   ├── risk_event.rb
│   └── reconciliation.rb
│
├── services/
│   ├── market_data/
│   │   ├── market_feed_hub.rb
│   │   ├── tick_normalizer.rb
│   │   ├── candle_builder.rb
│   │   └── subscription_manager.rb
│   │
│   ├── instruments/
│   │   ├── resolver.rb
│   │   └── importer.rb
│   │
│   ├── strategies/
│   │   ├── registry.rb
│   │   ├── base.rb
│   │   └── ...
│   │
│   ├── risk/
│   │   ├── engine.rb
│   │   ├── position_sizer.rb
│   │   └── rules/
│   │
│   ├── margin/
│   │   ├── estimator.rb
│   │   └── dhan_validator.rb
│   │
│   ├── orders/
│   │   ├── order_intent_builder.rb
│   │   ├── gateway.rb
│   │   ├── gateway_paper.rb
│   │   ├── gateway_live.rb
│   │   └── state_machine.rb
│   │
│   ├── execution/
│   │   ├── paper_fill_engine.rb
│   │   └── multi_leg_executor.rb
│   │
│   ├── positions/
│   │   ├── manager.rb
│   │   └── reconciler.rb
│   │
│   └── portfolio/
│
├── jobs/
│
└── controllers/
```

---

# 92. Runtime Processes

Recommended production deployment:

```text
                    AWS
                     │
          ┌──────────┴──────────┐
          │                     │
       Rails API           Trading Runtime
          │                     │
       Puma                 Supervisor
          │                     │
          └──────────┬──────────┘
                     │
               ┌─────┴─────┐
               │           │
            Redis       PostgreSQL
               │
          Solid Queue
```

---

# 93. Process Responsibilities

## Puma

```text
REST API
authentication
dashboard API
settings
manual controls
```

## Trading daemon

```text
WebSockets
ticks
strategies
risk
execution
positions
reconciliation
```

## Solid Queue

```text
instrument import
historical backfills
analytics
reports
maintenance
```

---

# 94. Phase Plan

## Phase 0 — Architecture Hardening

Before adding strategies:

```text
[ ] Freeze broker interface
[ ] Freeze Instrument model
[ ] Freeze OrderIntent
[ ] Freeze ExecutionGateway
[ ] Freeze Position interface
[ ] Freeze Risk interface
```

---

# 95. Phase 1 — Instrument + Market Data

Build:

```text
Instrument importer
Instrument resolver
MarketFeedHub
TickCache
CandleBuilder
Historical backfill
Market session
```

Acceptance:

```text
NSE equity receives ticks
NSE futures receives ticks
NSE options receives ticks
BSE instruments receive ticks
ticks survive WebSocket reconnect
```

---

# 96. Phase 2 — Paper Execution

Build:

```text
PaperAccount
PaperGateway
FillEngine
Fees
Slippage
Positions
P&L
```

Acceptance:

```text
BUY creates paper order
order fills according to fill model
position updates
P&L updates from live ticks
fees deducted
exit closes position
```

---

# 97. Phase 3 — Strategy Runtime

Build:

```text
StrategyRegistry
SignalEngine
StrategyContext
OrderIntent
RiskEngine
```

Start with:

```text
EMA crossover
VWAP
ORB
RSI
```

for equity/futures before complicated options strategies.

---

# 98. Phase 4 — F&O

Add:

```text
expiry resolution
strike resolution
option chain
Greeks
IV
OI
lot sizing
margin
multi-leg strategies
```

Strategies:

```text
Long Call
Long Put
Bull Call Spread
Bear Put Spread
Bull Put Spread
Bear Call Spread
```

---

# 99. Phase 5 — Paper Multi-Leg Execution

Implement:

```text
leg dependency
hedge-first
partial fills
rollback
flatten
net P&L
max loss
```

Then:

```text
Iron Condor
Straddle
Strangle
Calendar
```

---

# 100. Phase 6 — Reconciliation

Implement:

```text
REST order reconciliation
REST position reconciliation
REST funds reconciliation
trade reconciliation
discrepancy engine
```

Acceptance:

```text
local state intentionally corrupted
system detects mismatch
system halts trading
system repairs/reconciles state
```

---

# 101. Phase 7 — Live Shadow Mode

This is extremely important.

Run:

```text
Real Dhan market data
Real strategy
Real risk
Real order intents
```

but:

```text
NO REAL ORDERS
```

Log:

```text
what would have been sent
```

Compare against:

```text
paper execution
```

---

# 102. Phase 8 — Controlled Live

Start:

```text
1 strategy
1 instrument
1 lot
strict daily loss
```

No automatic strategy switching.

No aggressive multi-leg execution initially.

---

# 103. Phase 9 — Multi-Strategy

Only after live reliability:

```text
Strategy A
Strategy B
Strategy C
```

with:

```text
portfolio-level risk
strategy allocation
correlation
capital allocation
```

---

# 104. Phase 10 — Research Platform

Then build:

```text
backtesting
parameter optimization
walk-forward
Monte Carlo
MAE/MFE
regime analysis
trade attribution
```

---

# 105. Acceptance Criteria — Market Data

System passes when:

```text
✓ Instrument master loads
✓ Security IDs resolve
✓ Market WS connects
✓ subscriptions succeed
✓ binary packets decode
✓ ticks enter TickCache
✓ Redis contains current ticks
✓ candles are generated
✓ WebSocket reconnects
✓ subscriptions are restored
✓ missing candles are backfilled
```

---

# 106. Acceptance Criteria — Paper Trading

```text
✓ OrderIntent generated
✓ Risk approves/rejects
✓ Paper order created
✓ Fill generated
✓ Slippage applied
✓ Fees applied
✓ Position created
✓ Live LTP updates P&L
✓ Stop loss exits
✓ Target exits
✓ EOD exit works
✓ trade journal generated
```

---

# 107. Acceptance Criteria — Live Readiness

Before live:

```text
✓ Token renewal tested
✓ REST rate limiting tested
✓ Market WS reconnect tested
✓ Order WS reconnect tested
✓ Unknown order state tested
✓ Duplicate order protection tested
✓ Partial fills tested
✓ Broker/local reconciliation tested
✓ Kill switch tested
✓ Emergency flatten tested
✓ Server restart recovery tested
✓ Database recovery tested
✓ Redis failure tested
```

---

# 108. Testing Strategy

## Unit tests

```text
InstrumentResolver
RiskEngine
PositionSizer
FillEngine
P&L
MarginEstimator
Strategy
```

## Integration tests

```text
DhanHQ REST
DhanHQ WebSocket
Redis
PostgreSQL
```

## Contract tests

Verify that:

```text
GatewayPaper
GatewayLive
```

implement the same execution contract.

## Failure tests

```text
WebSocket disconnect
REST timeout
429
401
duplicate order
partial fill
database failure
Redis failure
stale tick
```

---

# 109. Deterministic Paper Replay

Paper execution should support:

```text
recorded ticks
      ↓
replay
      ↓
same strategy
      ↓
same expected fills
```

This gives us:

```text
production bug reproduction
strategy debugging
regression testing
```

---

# 110. Event Recording

Every important runtime event should optionally be recorded:

```text
MarketTick
Signal
OrderIntent
RiskDecision
Order
Fill
PositionChange
ExitDecision
```

This creates a lightweight event-sourced audit trail without requiring the entire application to become event-sourced.

---

# 111. AI/LLM Integration

LLMs should remain **outside the deterministic execution path**.

Bad:

```text
tick
 ↓
LLM
 ↓
BUY
```

Good:

```text
ticks
 ↓
deterministic indicators
 ↓
strategy
 ↓
risk
 ↓
execution
```

LLM can provide:

```text
research
strategy analysis
trade explanation
post-trade analysis
anomaly investigation
configuration suggestions
```

but should not directly place orders.

---

# 112. Complete End-to-End Example

Suppose:

```text
Capital = ₹500,000
Instrument = NIFTY
Strategy = ORB
Mode = PAPER
```

### Startup

```text
Rails boot
 ↓
DhanHQ client
 ↓
token
 ↓
instrument master
 ↓
NIFTY security ID
 ↓
MarketFeedHub
```

### Market open

```text
Dhan WebSocket
 ↓
NIFTY tick
 ↓
TickCache
 ↓
CandleBuilder
 ↓
5-minute candle
```

### Signal

```text
ORB breakout detected
 ↓
Signal
 ↓
Strategy
 ↓
OrderIntent
```

### Risk

```text
capital = 500000
risk/trade = 1%
risk allowed = 5000

position size calculated
 ↓
risk approved
```

### Execution

```text
GatewayPaper
 ↓
NIFTY market data
 ↓
simulated fill
 ↓
PaperPosition
```

### Monitoring

```text
NIFTY ticks
 ↓
P&L engine
 ↓
Redis
 ↓
Risk engine
```

### Exit

```text
target hit
 ↓
ExitEngine
 ↓
GatewayPaper
 ↓
simulated SELL
 ↓
position CLOSED
```

### Journal

```text
Trade
 ↓
P&L
 ↓
fees
 ↓
slippage
 ↓
MAE/MFE
 ↓
analytics
```

No real order was sent.

---

# 113. Live Version of Exactly the Same Flow

Only this changes:

```text
GatewayPaper
```

becomes:

```text
GatewayLive
```

Then:

```text
OrderIntent
 ↓
GatewayLive
 ↓
DhanHQ REST
 ↓
order_id
 ↓
OrderUpdate WebSocket
 ↓
FILLED
 ↓
Position
```

The strategy itself remains unchanged.

That is the architecture we want.

---

# 114. The Most Important Interfaces

The entire system can be reduced to these contracts:

```ruby
MarketDataProvider
InstrumentProvider
Strategy
RiskEngine
MarginProvider
ExecutionGateway
PositionManager
PortfolioProvider
ReconciliationService
```

The strategy should only depend on these abstractions.

---

# 115. Final Architecture

```text
                         ┌─────────────────────┐
                         │       DhanHQ        │
                         └──────────┬──────────┘
                                    │
               ┌────────────────────┼───────────────────┐
               │                    │                   │
               ▼                    ▼                   ▼
        Instrument REST       Market REST          WebSockets
               │                    │             ┌─────┴──────┐
               │                    │             │            │
               │                    │          Market WS    Order WS
               │                    │             │            │
               ▼                    ▼             ▼            ▼
        Instrument Store      Data Provider   MarketFeed   OrderUpdates
               │                    │             │            │
               └───────────┬────────┴──────┬──────┴────────────┘
                           │               │
                           ▼               ▼
                       PostgreSQL        Redis
                           │               │
                           └───────┬───────┘
                                   ▼
                         ┌────────────────────┐
                         │  Trading Runtime   │
                         │                    │
                         │ Signal Engine      │
                         │ Strategy Engine    │
                         │ Risk Engine        │
                         │ Margin Engine      │
                         │ Portfolio Engine   │
                         └─────────┬──────────┘
                                   │
                              OrderIntent
                                   │
                                   ▼
                         ┌────────────────────┐
                         │ Execution Gateway  │
                         └─────────┬──────────┘
                                   │
                     ┌─────────────┴─────────────┐
                     │                           │
                     ▼                           ▼
              ┌──────────────┐           ┌──────────────┐
              │ PAPER        │           │ LIVE         │
              │ Gateway      │           │ Gateway      │
              └──────┬───────┘           └──────┬───────┘
                     │                          │
                     ▼                          ▼
               Fill Simulator             DhanHQ REST
                     │                          │
                     │                    Order Update WS
                     │                          │
                     └────────────┬─────────────┘
                                  ▼
                         Position Manager
                                  │
                    ┌─────────────┼─────────────┐
                    ▼             ▼             ▼
                   P&L          Risk       Reconciliation
                    │             │             │
                    └─────────────┼─────────────┘
                                  ▼
                           PostgreSQL/Redis
                                  │
                                  ▼
                            Rails API
                                  │
                                  ▼
                            Dashboard
```

---

# 116. Final Engineering Decision

The system should **not** become:

```text
Rails app + huge collection of Dhan API calls
```

It should become:

```text
Trading Runtime
      +
Broker Adapter
      +
Market Data Runtime
      +
Execution Runtime
      +
Risk Runtime
      +
Research/Data Platform
```

And `dhanhq-client` should remain the **broker SDK boundary**.

The Rails application should own:

```text
what to trade
when to trade
how much to trade
how risky it is
how to simulate it
how to manage positions
how to reconcile
how to journal
```

The gem should own:

```text
how to talk to DhanHQ
```

---

# 117. What We Should Build First

Do **not** immediately implement 20 strategies.

The first production-quality milestone should be:

```text
DhanHQ V2
    ↓
Instrument Master
    ↓
Live Market WebSocket
    ↓
TickCache
    ↓
Candle Engine
    ↓
Generic Instrument Resolver
    ↓
One deterministic strategy
    ↓
Risk Engine
    ↓
OrderIntent
    ↓
Paper Gateway
    ↓
Realistic Fill Engine
    ↓
Paper Position
    ↓
Real-time P&L
    ↓
Exit Engine
    ↓
Trade Journal
    ↓
Dashboard
```

Then prove this pipeline works for:

```text
NSE Equity
NSE Future
NSE Option
```

before adding complex multi-leg F&O.

---

# 118. Final Principle

The architecture should ultimately allow this:

```ruby
strategy = Strategies::MyStrategy.new(context)

intent = strategy.evaluate

risk.approve(intent)

execution_gateway.execute(intent)
```

The strategy does not know whether:

```text
GatewayPaper
```

or:

```text
GatewayLive
```

will execute it.

That single abstraction is what allows us to build a **real paper-trading environment first and transition to live DhanHQ execution without rewriting the strategy layer**.

DhanHQ explicitly supports custom-code trading through its APIs, while its Data APIs provide live market data, historical data and intraday data.

The existing `algo_scalper_api` is already unusually close to this architecture: it has the separate trading daemon, Redis-first market state, paper/live gateways, market-feed hub, order-update handling, reconciliation and paper P&L infrastructure.

**The next engineering task should therefore be architectural consolidation and generalization, not a rewrite.**

### Recommended implementation order

```text
1. Generalize Instrument model
2. Freeze MarketDataProvider contract
3. Freeze ExecutionGateway contract
4. Harden MarketFeedHub
5. Harden CandleBuilder
6. Build generic PaperAccount + FillEngine
7. Build generic OrderIntent
8. Move Risk before Gateway
9. Build generic Position/Portfolio engine
10. Add reconciliation
11. Test NSE equity
12. Test NSE futures
13. Test NSE options
14. Test multi-leg options
15. Run live-market paper trading
16. Run shadow mode
17. Only then enable controlled live execution
```

That gives you a **complete Indian-market trading runtime**, rather than an options bot that happens to talk to DhanHQ.