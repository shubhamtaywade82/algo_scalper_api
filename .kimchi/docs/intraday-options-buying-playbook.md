# Intraday Options Buying Playbook — NIFTY, BANKNIFTY, SENSEX
## DhanHQ v2 API + WebSocket — Complete Automation Guide

**Version:** 1.0  
**Date:** 2026-06-19  
**Broker API:** DhanHQ v2  
**Markets:** NSE F&O (NIFTY 50, NIFTY BANK, SENSEX)  
**Strategy:** Intraday Index Option Buying (CE/PE)  

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [DhanHQ v2 API Reference](#2-dhanhq-v2-api-reference)
3. [Market Data & WebSocket Feed](#3-market-data--websocket-feed)
4. [Order Lifecycle & WebSocket Updates](#4-order-lifecycle--websocket-updates)
5. [Option Chain Analysis & Strike Selection](#5-option-chain-analysis--strike-selection)
6. [Entry Signal Generation (SMC Layer)](#6-entry-signal-generation-smc-layer)
7. [Order Placement & Execution Flow](#7-order-placement--execution-flow)
8. [Risk Management & Exits](#8-risk-management--exits)
9. [Bracket Orders & Super Orders](#9-bracket-orders--super-orders)
10. [Paper Trading vs Live Trading](#10-paper-trading-vs-live-trading)
11. [Intraday Timing & Market Sessions](#11-intraday-timing--market-sessions)
12. [Error Handling & Rate Limits](#12-error-handling--rate-limits)
13. [Deployment Checklist](#13-deployment-checklist)
14. [Code Snippets](#14-code-snippets)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          TRADING SYSTEM ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                  │
│  │  Market Feed │    │ SMC Signal   │    │  Order Mgmt  │                  │
│  │  WebSocket   │◄──►│  Generator   │◄──►│  WebSocket   │                  │
│  │  (Ticks)     │    │              │    │  (Updates)   │                  │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘                  │
│         │                   │                    │                          │
│         ▼                   ▼                    ▼                          │
│  ┌──────────────────────────────────────────────────────┐                  │
│  │              TICK CACHE (Redis)                       │                  │
│  └──────────────────────────────────────────────────────┘                  │
│                            │                                                │
│                            ▼                                                │
│  ┌──────────────────────────────────────────────────────┐                  │
│  │           STRATEGY RUNNER / ENTRY ENGINE              │                  │
│  │  • EntryGuard + Pipeline                              │                  │
│  │  • StrikeSelector (ATM/1OTM/2OTM)                     │                  │
│  │  • RiskManager / Capital Allocator                    │                  │
│  │  • TrendScorer + PermissionResolver                   │                  │
│  └──────────────────────────────────────────────────────┘                  │
│                            │                                                │
│                            ▼                                                │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                  │
│  │ EntryManager │───►│ Orders::     │───►│ DhanHQ v2    │                  │
│  │              │    │  Placer      │    │  REST API    │                  │
│  └──────────────┘    └──────────────┘    └──────────────┘                  │
│         │                   │                    │                          │
│         ▼                   ▼                    ▼                          │
│  ┌──────────────────────────────────────────────────────┐                  │
│  │              POSITION LIFECYCLE                       │                  │
│  │  • PositionTracker (DB)                               │                  │
│  │  • ActiveCache (Redis)                                │                  │
│  │  • States: entered → partial → filled → exit_pending   │                  │
│  │  • PnL Updater, Exit Engine, Trailing Engine           │                  │
│  └──────────────────────────────────────────────────────┘                  │
│                            │                                                │
│                            ▼                                                │
│  ┌──────────────────────────────────────────────────────┐                  │
│  │              NOTIFICATIONS & MONITORING               │                  │
│  │  • Telegram alerts (entry, exit, SL, TP)              │                  │
│  │  • Live Dashboard (Next.js + ActionCable)             │                  │
│  │  • EventBus (pub/sub for cross-service comms)         │                  │
│  └──────────────────────────────────────────────────────┘                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Responsibility | Path in Codebase |
|-----------|---------------|------------------|
| **MarketFeedHub** | WebSocket client for LTP/Quote/Full ticks | `app/services/live/market_feed_hub.rb` |
| **TickQuery** | Redis-backed tick lookup by segment+security_id | `app/services/live/tick_query.rb` |
| **DerivativeChainAnalyzer** | Fetches option chain, scores strikes by OI/IV | `app/services/options/derivative_chain_analyzer.rb` |
| **StrikeSelector** | Selects ATM/1OTM/2OTM based on trend score | `app/services/options/strike_selector.rb` |
| **EntryEngine** | SMC-based signal generation (sweep + displacement) | `app/services/trading/entry_engine.rb` |
| **EntryGuardPipeline** | Multi-layer validation before order placement | `app/services/entries/entry_guard_pipeline.rb` |
| **EntryManager** | Orchestrates pick → order → position tracking | `app/services/orders/entry_manager.rb` |
| **Orders::Placer** | Gateway abstraction for paper/live order placement | `app/services/orders/placer.rb` |
| **Orders::GatewayLive** | DhanHQ v2 REST API client (real orders) | `app/services/orders/gateway_live.rb` |
| **Orders::GatewayPaper** | Simulated fills for backtesting/paper trading | `app/services/orders/gateway_paper.rb` |
| **OrderUpdateHub** | WebSocket for real-time order status updates | `app/services/live/order_update_hub.rb` |
| **PnLUpdater** | Real-time PnL calculation from tick changes | `app/services/live/pnl_updater_service.rb` |
| **ExitEngine** | Monitors positions, triggers exits (SL/TP/trailing) | `app/services/orders/exit_engine.rb` |
| **RiskManagerService** | Daily loss limits, drawdown circuit breakers | `app/services/live/risk_manager_service*.rb` |

---

## 2. DhanHQ v2 API Reference

### 2.1 Base URL & Authentication

```
Base URL:    https://api.dhan.co/v2
WebSocket Feed:   wss://api-feed.dhan.co
WebSocket Orders: wss://api-order-update.dhan.co
Auth Header:      access-token: <JWT>
```

**Rate Limits:**
- Order APIs: **10 orders / second**
- Market Data: 5 WebSocket connections per user, 5000 instruments per connection
- Data APIs: Throttled at broker level; handle `DH-904` with exponential backoff

**Static IP Whitelisting Required** for all order placement/modification/cancellation APIs.

### 2.2 Exchange Segments for Index Options

| Enum | Exchange | Segment | Use For |
|------|----------|---------|---------|
| `NSE_FNO` | NSE | Futures & Options | NIFTY 50, BANKNIFTY, SENSEX options |
| `BSE_FNO` | BSE | Futures & Options | SENSEX options (dual listing) |
| `IDX_I` | — | Index Value | Spot index tracking (no trading) |

### 2.3 Product Types

| Enum | Description | Valid For |
|------|-------------|-----------|
| `INTRADAY` | Intraday — auto square-off at 3:15/3:30 PM | Equity, F&O |
| `MARGIN` | Carry Forward in F&O | Futures, Options writing |
| `CO` | Cover Order (SL compulsory) | Intraday only |
| `BO` | Bracket Order (Entry + SL + Target) | Intraday only |

> **For intraday option buying:** Always use `INTRADAY` (or `CO`/`BO` if bracket desired).

### 2.4 Order Types

| Enum | Description | When to Use |
|------|-------------|-------------|
| `MARKET` | Market order — executes at best available price | **Preferred for entries** — fast execution |
| `LIMIT` | Limit order — executes at specified price or better | For precise entry, but risk of non-fill |
| `STOP_LOSS` | Stop-Loss Limit — triggers at price, executes as limit | SL on existing position |
| `STOP_LOSS_MARKET` | Stop-Loss Market — triggers at price, executes as market | SL when speed matters |

### 2.5 Order Placement (Entry)

```http
POST https://api.dhan.co/v2/orders
Content-Type: application/json
access-token: <JWT>
```

**Request Body — NIFTY CE Buy (Market Order):**

```json
{
  "dhanClientId": "100xxxxxxx",
  "correlationId": "nifty_ce_20260619_093045_abc123",
  "transactionType": "BUY",
  "exchangeSegment": "NSE_FNO",
  "productType": "INTRADAY",
  "orderType": "MARKET",
  "validity": "DAY",
  "securityId": "52175",
  "quantity": "50",
  "price": "0",
  "triggerPrice": "",
  "afterMarketOrder": false,
  "boProfitValue": "",
  "boStopLossValue": ""
}
```

**Key Fields:**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `dhanClientId` | string | ✅ | Your Dhan client ID |
| `correlationId` | string | — | Max 30 chars `[a-zA-Z0-9 _-]`. Use for idempotency & tracking |
| `transactionType` | enum | ✅ | `BUY` or `SELL` |
| `exchangeSegment` | enum | ✅ | `NSE_FNO` for index options |
| `productType` | enum | ✅ | `INTRADAY` for day trades |
| `orderType` | enum | ✅ | `MARKET` for entries, `STOP_LOSS`/`STOP_LOSS_MARKET` for SL |
| `validity` | enum | ✅ | `DAY` or `IOC` |
| `securityId` | string | ✅ | Exchange security ID (NOT trading symbol). See instrument master |
| `quantity` | int | ✅ | In **units**, not lots. NIFTY lot = 25, BANKNIFTY = 15, SENSEX = 10 |
| `price` | float | ✅ | `0` for MARKET orders. Actual price for LIMIT |
| `triggerPrice` | float | — | Required for SL orders |

**Response:**

```json
{
  "orderId": "112111182198",
  "orderStatus": "PENDING"
}
```

> Order statuses: `TRANSIT` → `PENDING` → `PART_TRADED` → `TRADED` | `REJECTED` | `CANCELLED` | `EXPIRED`

### 2.6 Order Modification (Move SL / Trail)

```http
PUT https://api.dhan.co/v2/orders/{order-id}
Content-Type: application/json
access-token: <JWT>
```

```json
{
  "dhanClientId": "100xxxxxxx",
  "orderId": "112111182198",
  "orderType": "STOP_LOSS",
  "quantity": "50",
  "price": "245.50",
  "triggerPrice": "245.00",
  "validity": "DAY"
}
```

> Only `PENDING` or `PART_TRADED` orders can be modified. For BO/CO, specify `legName`: `ENTRY_LEG`, `TARGET_LEG`, `STOP_LOSS_LEG`.

### 2.7 Order Cancellation

```http
DELETE https://api.dhan.co/v2/orders/{order-id}
access-token: <JWT>
```

Response (202 Accepted):

```json
{
  "orderId": "112111182198",
  "orderStatus": "CANCELLED"
}
```

### 2.8 Order Book (Poll for Status)

```http
GET https://api.dhan.co/v2/orders
access-token: <JWT>
```

Response includes `filledQty`, `remainingQuantity`, `averageTradedPrice` — use for position reconciliation.

### 2.9 Get Order by Correlation ID

```http
GET https://api.dhan.co/v2/orders/external/{correlation-id}
access-token: <JWT>
```

> Use this for **idempotency recovery** — if network drops after placing order, poll by correlationId to check if order exists.

### 2.10 Margin Calculator

```http
POST https://api.dhan.co/v2/margincalculator
Content-Type: application/json
access-token: <JWT>
```

```json
{
  "dhanClientId": "100xxxxxxx",
  "transactionType": "BUY",
  "exchangeSegment": "NSE_FNO",
  "productType": "INTRADAY",
  "securityId": "52175",
  "quantity": "50",
  "price": "250.00"
}
```

> Call before placing orders to verify available margin. For options buying, margin = premium × quantity (+ brokerage).

### 2.11 Security ID Lookup (Instruments)

Security IDs are exchange-assigned numeric identifiers. You CANNOT use trading symbols in order placement.

**Instrument Master CSV:**
- Available via Dhan dashboard or API: `GET https://api.dhan.co/v2/instruments`
- Download and cache locally; update daily via cron/Solid Queue job

**For index options, you need:**
1. **Index spot security IDs** (for tick subscription): NIFTY (~`13`), BANKNIFTY (~`25`), SENSEX (~`47`)
2. **Option contract security IDs** (for order placement): Each strike × expiry × type (CE/PE) has a unique ID

**Finding an option contract's securityId:**
- Download instrument master CSV, filter by `exchangeSegment=NSE_FNO` + `instrumentType=OPTIDX` + `underlying=NIFTY/BANKNIFTY/SENSEX` + `expiryDate` + `strikePrice` + `optionType=CE/PE`
- Store in your `instruments` table (see `app/models/instrument.rb`)

---

## 3. Market Data & WebSocket Feed

### 3.1 Connection

```
wss://api-feed.dhan.co?version=2&token=<JWT>&clientId=<CLIENT_ID>&authType=2
```

### 3.2 Feed Request Codes

| Code | Action |
|------|--------|
| `11` | Connect Feed |
| `12` | Disconnect Feed |
| `15` | Subscribe — Ticker Packet |
| `17` | Subscribe — Quote Packet |
| `21` | Subscribe — Full Packet (LTP + Quote + OI + Market Depth) |

### 3.3 Subscribe to Instruments

**Max 100 instruments per JSON message. Max 5000 per connection.**

```json
{
  "RequestCode": 21,
  "InstrumentCount": 3,
  "InstrumentList": [
    { "ExchangeSegment": "IDX_I", "SecurityId": "13" },
    { "ExchangeSegment": "NSE_FNO", "SecurityId": "52175" },
    { "ExchangeSegment": "NSE_FNO", "SecurityId": "52176" }
  ]
}
```

### 3.4 Binary Packet Parsing

All responses are **binary, Little Endian**. You need a binary parser.

**Response Header (8 bytes):**

| Bytes | Type | Size | Description |
|-------|------|------|-------------|
| 0 | byte | 1 | Feed Response Code |
| 1-2 | int16 | 2 | Message Length |
| 3 | byte | 1 | Exchange Segment |
| 4-7 | int32 | 4 | Security ID |

**Ticker Packet (Response Code = 2):**

| Bytes | Type | Size | Field |
|-------|------|------|-------|
| 0-8 | header | 8 | Response Header |
| 9-12 | float32 | 4 | Last Traded Price (LTP) |
| 13-16 | int32 | 4 | Last Trade Time (Unix Epoch) |

**Quote Packet (Response Code = 4):**

| Bytes | Type | Size | Field |
|-------|------|------|-------|
| 0-8 | header | 8 | Response Header |
| 9-12 | float32 | 4 | LTP |
| 13-14 | int16 | 2 | Last Traded Quantity |
| 15-18 | int32 | 4 | Last Trade Time |
| 19-22 | float32 | 4 | Average Trade Price |
| 23-26 | int32 | 4 | Volume |
| 27-30 | int32 | 4 | Total Sell Qty |
| 31-34 | int32 | 4 | Total Buy Qty |
| 35-38 | float32 | 4 | Day Open |
| 39-42 | float32 | 4 | Day Close |
| 43-46 | float32 | 4 | Day High |
| 47-50 | float32 | 4 | Day Low |

**OI Packet (Response Code = 5):**

| Bytes | Type | Size | Field |
|-------|------|------|-------|
| 0-8 | header | 8 | Response Header |
| 9-12 | int32 | 4 | Open Interest |

**Full Packet (Response Code = 8):** Quote data + OI + Market Depth (5 levels × 20 bytes)

### 3.5 Ping-Pong Keepalive

Server sends ping every **10 seconds**. Client must respond with pong. If no response for **40 seconds**, connection drops. Reconnect with exponential backoff (5s → 10s → 30s → 60s max).

### 3.6 Recommended Feed Strategy for Intraday Options

| Subscription | Feed Mode | Why |
|-------------|-----------|-----|
| Index spot (NIFTY/BANKNIFTY/SENSEX) | `Ticker` (code 15) | Fastest LTP for signal generation |
| Selected option contract | `Full` (code 21) | Need LTP + OI + depth for exit decisions |
| Nearby strikes (±3) | `Quote` (code 17) | Monitor gamma ramp, IV changes |

> **Pro tip:** Subscribe to index spot with Ticker for sub-100ms signal latency. Use Full feed only for the active option position to conserve bandwidth.

---

## 4. Order Lifecycle & WebSocket Updates

### 4.1 Order Update WebSocket

```
wss://api-order-update.dhan.co
```

**Auth Message:**

```json
{
  "LoginReq": {
    "MsgCode": 42,
    "ClientId": "100xxxxxxx",
    "Token": "<JWT>"
  },
  "UserType": "SELF"
}
```

### 4.2 Order Update Payload

```json
{
  "Data": {
    "Exchange": "NSE",
    "Segment": "D",
    "SecurityId": "52175",
    "ClientId": "100xxxxxxx",
    "ExchOrderNo": "1400000000404591",
    "OrderNo": "1124091136546",
    "Product": "I",
    "TxnType": "B",
    "OrderType": "MKT",
    "Validity": "DAY",
    "Quantity": 50,
    "TradedQty": 50,
    "RemainingQuantity": 0,
    "Price": 0,
    "TradedPrice": 248.50,
    "AvgTradedPrice": 248.50,
    "OrderDateTime": "2026-06-19 09:30:45",
    "ReasonDescription": "CONFIRMED",
    "Status": "TRADED",
    "LotSize": 25,
    "StrikePrice": 24500,
    "ExpiryDate": "2026-06-19 00:00:00",
    "OptType": "CE",
    "DisplayName": "NIFTY 19JUN26 24500 CE",
    "CorrelationId": "nifty_ce_20260619_093045_abc123",
    "RefLtp": 248.75,
    "TickSize": 0.05
  },
  "Type": "order_alert"
}
```

### 4.3 Field Mappings for Options

| WS Field | Meaning for Options |
|----------|-------------------|
| `TxnType` | `B`=Buy, `S`=Sell |
| `Product` | `I`=INTRADAY, `C`=CNC, `M`=MARGIN |
| `OrderType` | `MKT`=Market, `LMT`=Limit, `SL`=Stop-Loss Limit, `SLM`=SL Market |
| `OptType` | `CE` or `PE` |
| `StrikePrice` | Strike price of the option |
| `ExpiryDate` | Contract expiry |
| `LotSize` | 25 for NIFTY, 15 for BANKNIFTY, 10 for SENSEX |
| `Status` | `TRANSIT`, `PENDING`, `REJECTED`, `CANCELLED`, `TRADED`, `EXPIRED` |
| `TradedQty` | Filled quantity in **units** |
| `AvgTradedPrice` | Average execution price |

### 4.4 Order State Machine

```
PLACE_ORDER ──► TRANSIT ──► PENDING ──► TRADED
                    │           │           │
                    ▼           ▼           ▼
                REJECTED   CANCELLED   PART_TRADED
                                          │
                                          ▼
                                        TRADED (remaining fills)
```

**Handling `PART_TRADED`:**
- Update `filledQty` and `remainingQuantity`
- Recalculate average price: `avg_price = (prev_filled × prev_avg + new_qty × new_price) / total_filled`
- If remaining is large, consider modifying price or canceling + re-entering

---

## 5. Option Chain Analysis & Strike Selection

### 5.1 Strike Selection Strategy

| Momentum Score | Trend Score | Allowed Strikes |
|---------------|-------------|-----------------|
| 0 | Any | Skip (no momentum) |
| 1+ (≥1/3) | < 12 | ATM only |
| 2+ (≥2/3) | 12–17 | ATM + 1OTM |
| 2+ (≥2/3) | ≥ 18 | ATM + 1OTM + 2OTM |

**Strike increments:**
- NIFTY: 50 points
- BANKNIFTY: 100 points
- SENSEX: 100 points

### 5.2 Strike Selection Flow

```
1. Get spot price → calculate ATM strike
   ├─ From tick cache (fastest) via Live::TickQuery
   └─ Fallback: Instrument.ltp API call

2. Query DerivativeChainAnalyzer → get candidates
   ├─ Filter by expiry (nearest = current week)
   ├─ Filter by direction: bullish → CE, bearish → PE
   └─ Score by OI buildup, IV, liquidity

3. Filter by strike distance (ATM ± max_otm_depth × increment)

4. Apply PremiumFilter validation
   ├─ Min/max premium bounds per index
   ├─ Spread check (bid-ask spread < threshold)
   └─ Liquidity check (OI > min threshold)

5. Return normalized instrument hash
```

### 5.3 Index-Specific Rules

| Index | Lot Size | Strike Incr | Min Premium | Max Spread | Session Close |
|-------|----------|-------------|-------------|------------|---------------|
| NIFTY | 25 | 50 | ₹15 | 5% | 15:30 IST |
| BANKNIFTY | 15 | 100 | ₹20 | 5% | 15:30 IST |
| SENSEX | 10 | 100 | ₹30 | 5% | 15:30 IST |

### 5.4 Option Chain Data Points to Monitor

| Metric | Signal Interpretation |
|--------|---------------------|
| **OI Change (CE)** | Rising = resistance building; Falling = short covering (bullish) |
| **OI Change (PE)** | Rising = support building; Falling = put writing (bullish) |
| **PCR (Put-Call Ratio)** | > 1.2 = oversold, < 0.7 = overbought |
| **IV Rank** | > 70% = expensive premiums, < 30% = cheap premiums |
| **Gamma Ramp** | Strikes with high gamma = magnetic price levels |

---

## 6. Entry Signal Generation (SMC Layer)

### 6.1 Smart Money Concepts (SMC) Entry Engine

The `Trading::EntryEngine` generates signals using multi-timeframe confluence:

**Required Conditions for BUY_CE:**
1. Structure trend = `bullish`
2. MTF bias = `bullish` (higher timeframe alignment)
3. Price in `discount` zone (below equilibrium)
4. Liquidity sweep = `sweep_low` (stop hunt below structure)
5. Displacement = `bullish` (strong green candle breaking structure)
6. Volume spike confirmed
7. Risk:Reward ≥ 1.8

**Required Conditions for BUY_PE:**
1. Structure trend = `bearish`
2. MTF bias = `bearish`
3. Price in `premium` zone (above equilibrium)
4. Liquidity sweep = `sweep_high` (stop hunt above structure)
5. Displacement = `bearish` (strong red candle breaking structure)
6. Volume spike confirmed
7. Risk:Reward ≥ 1.8

### 6.2 Entry Guard Pipeline

Before any order is placed, the `Entries::EntryGuardPipeline` validates:

| Layer | Check | Failure Action |
|-------|-------|---------------|
| 1. Market Hours | Is market open? (09:15–15:30 IST) | Block entry |
| 2. Daily Limits | Trades today < max per index? | Block entry |
| 3. Capital Available | Margin check via Capital::Allocator | Block entry |
| 4. Risk Manager | Daily loss / drawdown within limits? | Block entry |
| 5. Position Check | No duplicate active position for same index? | Block entry |
| 6. Trend Score | Trend score ≥ minimum threshold? | Block entry |
| 7. Momentum | Momentum validator passes? | Block entry |
| 8. Strike Validation | Selected strike passes PremiumFilter? | Block entry |

### 6.3 Signal Flow

```
Tick Received
    │
    ▼
┌────────────────────┐
│ SMC Indicator calculations (structure, liquidity, displacement, volume)
│ - Uses 1-min and 5-min aggregations
└────────────────────┘
    │
    ▼
┌────────────────────┐
│ TrendScorer (0-21 scale)
│ - Combines multiple timeframe biases
└────────────────────┘
    │
    ▼
┌────────────────────┐
│ EntryEngine.call → Signal or nil
└────────────────────┘
    │
    ▼
┌────────────────────┐
│ StrikeSelector.select(...) → pick/candidate
└────────────────────┘
    │
    ▼
┌────────────────────┐
│ EntryGuardPipeline.validate(...) → pass/fail
└────────────────────┘
    │
    ▼
┌────────────────────┐
│ EntryManager.process_entry(...) → place order
└────────────────────┘
```

---

## 7. Order Placement & Execution Flow

### 7.1 Order Gateway Abstraction

```ruby
# app/services/orders/gateway_factory.rb
gateway = Orders::GatewayFactory.for(mode: paper? ? :paper : :live)
# Returns Orders::GatewayPaper or Orders::GatewayLive
```

### 7.2 Live Gateway Order Flow

```
Orders::Placer.place(
  security_id: "52175",
  segment: "NSE_FNO",
  transaction_type: "BUY",
  quantity: 50,
  order_type: "MARKET",
  product_type: "INTRADAY",
  price: 0,
  correlation_id: "..."
)
    │
    ▼
Orders::GatewayLive.place_order(params)
    │
    ▼
POST https://api.dhan.co/v2/orders
    │
    ▼
Store order_id in PositionTracker
    │
    ▼
Listen to OrderUpdate WebSocket for fills
    │
    ▼
On TRADED: Update PositionTracker.entry_price = AvgTradedPrice
```

### 7.3 Idempotency Pattern

**Critical for intraday automation:** Network failures between order placement and acknowledgment can cause duplicate orders.

```ruby
correlation_id = "#{index_key}_#{direction}_#{Time.current.strftime('%Y%m%d_%H%M%S')}_#{ SecureRandom.hex(4) }"

# Before placing, check if order already exists with this correlation_id
existing = Orders::Placer.find_by_correlation(correlation_id)
return existing if existing

# Place order
result = gateway.place_order(..., correlation_id: correlation_id)

# If network fails after request sent but before response received,
# on reconnect, poll: GET /orders/external/{correlation_id}
```

### 7.4 Quantity Calculation

```ruby
# NIFTY: lot_size = 25
# Capital per trade = portfolio_value × risk_pct (e.g., ₹10L × 0.02 = ₹20,000)
# Premium per lot ≈ LTP × lot_size
# Lots = (capital_per_trade / (premium_per_lot * 1.1))  # 1.1 buffer for slippage
# Quantity = lots × lot_size

lots = (capital_per_trade / (ltp * lot_size * 1.1)).floor
quantity = lots * lot_size
quantity = [quantity, lot_size].max  # Minimum 1 lot
```

---

## 8. Risk Management & Exits

### 8.1 Stop Loss (Hard Stop)

| Index | Default SL | Type |
|-------|-----------|------|
| All | Entry Premium × 0.70 (30% loss) | Premium-based |

> For CE: If entry at ₹100, SL at ₹70. For PE: If entry at ₹100, SL at ₹130 (PE SL is above entry).

**Implementation:** Place a GTT (Good Till Triggered) or modify with STOP_LOSS order after entry fill.

### 8.2 Take Profit

| Index | Default TP | Notes |
|-------|-----------|-------|
| All | Entry Premium × 1.60 (60% gain) | For bullish (CE) |
| All | Entry Premium × 0.50 (50% gain) | For bearish (PE) — more conservative |

### 8.3 Trailing Stop Loss

```
When PnL reaches +20%: Trail SL to breakeven
When PnL reaches +40%: Trail SL to +20% of entry
When PnL reaches +60%: Trail SL to +40% of entry
```

**Engines:**
- `Orders::TrailingEngine` — basic percentage-based trailing
- `Orders::AdaptiveTrailing` — adjusts trail distance based on volatility (ATR)
- `Orders::GammaTrailingEngine` — tightens trail near gamma ramp strikes
- `Orders::MfeExitEngine` — exits at Maximum Favorable Excursion pullback

### 8.4 Time-Based Exit

| Rule | Action |
|------|--------|
| After 15:00 IST | No new entries (reduces overnight risk) |
| After 15:15 IST | Close all open positions (market close approaching) |
| Position open > 2 hours with < +5% PnL | Consider early exit (time decay) |

### 8.5 Risk Manager Circuit Breakers

```ruby
# app/services/live/risk_manager_service.rb
# Daily loss limit: e.g., ₹3,000 or 3% of capital
# Drawdown limit: e.g., 5% from peak PnL
# Consecutive loss limit: e.g., 3 losing trades → pause for 30 minutes
```

**States:**
- `NORMAL` → All trading allowed
- `CAUTION` → Reduce position size by 50%
- `HALTED` → No new entries until next day or manual reset

### 8.6 Dynamic Risk Allocation

```ruby
# app/services/capital/dynamic_risk_allocator.rb
def risk_pct_for(index_key:, trend_score:)
  base = 0.02  # 2% base risk

  # Scale up with strong trend
  multiplier = case trend_score
               when 0..8   then 0.5   # Weak trend: 1%
               when 9..14  then 1.0   # Moderate: 2%
               when 15..18 then 1.25  # Strong: 2.5%
               when 19..21 then 1.5   # Very strong: 3%
               else 1.0
               end

  [base * multiplier, 0.05].min  # Cap at 5%
end
```

---

## 9. Bracket Orders & Super Orders

### 9.1 Bracket Orders (BO)

Bracket Order = Entry + Target + Stop-Loss in one call.

**Benefits:**
- Auto-exits on SL or TP
- No need to manage separate exit orders
- Best for fully automated systems

**Limitations:**
- Intraday only (auto square-off at 3:15 PM)
- Dhan may not support BO on all option contracts
- Less control over partial fills

```http
POST https://api.dhan.co/v2/orders
```

```json
{
  "dhanClientId": "100xxxxxxx",
  "correlationId": "bo_nifty_001",
  "transactionType": "BUY",
  "exchangeSegment": "NSE_FNO",
  "productType": "BO",
  "orderType": "MARKET",
  "validity": "DAY",
  "securityId": "52175",
  "quantity": "50",
  "price": "0",
  "boProfitValue": "60",
  "boStopLossValue": "30"
}
```

> `boProfitValue` and `boStopLossValue` are **absolute values in points**, NOT percentages.

### 9.2 Super Orders (Recommended for Automation)

Super Orders allow placing entry + target + SL as a single composite order with individual leg control.

```http
POST https://api.dhan.co/v2/super/orders
```

```json
{
  "dhanClientId": "100xxxxxxx",
  "correlationId": "super_nifty_001",
  "transactionType": "BUY",
  "exchangeSegment": "NSE_FNO",
  "productType": "INTRADAY",
  "orderType": "MARKET",
  "validity": "DAY",
  "securityId": "52175",
  "quantity": "50",
  "price": "0",
  "targetPrice": "400",
  "stopLossPrice": "170",
  "trailingJump": "10"
}
```

| Field | Description |
|-------|-------------|
| `targetPrice` | Target price for auto-exit |
| `stopLossPrice` | Stop-loss trigger price |
| `trailingJump` | Trailing stop jump size (points) |

**Advantages over BO:**
1. Full control over each leg via `PUT /super/orders/{order-id}`
2. Can modify target/stop-loss independently
3. Get status of all legs in one API call: `GET /super/orders`

### 9.3 BracketPlacer Service

The existing `Orders::BracketPlacer` handles post-entry SL/TP placement:

```ruby
bracket_placer = Orders::BracketPlacer.new
bracket_placer.place_bracket(
  tracker: tracker,
  sl_price: sl_price,
  tp_price: tp_price,
  reason: 'initial_bracket'
)
```

This places separate SL and TP orders after the entry fill — more flexible than BO but requires managing multiple order IDs.

---

## 10. Paper Trading vs Live Trading

### 10.1 Mode Selection

| Environment Variable | Effect |
|---------------------|--------|
| `LIVE_TRADING=true` | Live gateway, real orders (requires `PLACE_ORDER=true`) |
| `LIVE_TRADING=false` or unset | Paper gateway, simulated fills |
| `PLACE_ORDER=true` | Enable actual broker order placement |
| `PLACE_ORDER=false` | Orders logged but NOT sent to broker |

### 10.2 Paper Gateway Behavior

```ruby
# app/services/orders/gateway_paper.rb
# Simulates fills at LTP + random slippage (±0.5%)
# Updates PositionTracker as if real fill occurred
# Emits same events as live gateway for dashboard/testing
```

### 10.3 Testing Sequence

```
1. Paper mode + no orders (PLACE_ORDER=false)
   → Verify signals are generated
   → Verify strike selection works
   → Verify EntryGuard blocks appropriately

2. Paper mode + paper orders (PAPER_TRADING=true)
   → Verify order lifecycle (pending → filled)
   → Verify PnL calculation
   → Verify exits trigger correctly

3. Live mode + small quantity (1 lot)
   → Run for 1 full session
   → Monitor fills, slippage, order status
   → Verify WebSocket order updates arrive

4. Full deployment
   → Scale to normal position sizing
```

---

## 11. Intraday Timing & Market Sessions

### 11.1 NSE Market Timings (IST)

| Session | Time | Action |
|---------|------|--------|
| Pre-market | 09:00–09:15 | Observe SGX Nifty, global cues. No entries. |
| Opening | 09:15–09:30 | High volatility. Wait for first 5-min candle close. |
| Morning | 09:30–11:30 | Best trading window. Strongest signals. |
| Mid-day | 11:30–13:30 | Lower volume, choppy. Reduce position size by 50%. |
| Afternoon | 13:30–15:00 | Second wind possible. Resume normal sizing. |
| Close | 15:00–15:30 | No new entries. Close all positions by 15:15. |
| Post-market | 15:30–15:45 | ATZ (After Market) for next day analysis only. |

### 11.2 Day-of-Week Adjustments

| Day | Recommendation |
|-----|---------------|
| Monday | Highest IV often. Good for directional plays. |
| Tuesday–Wednesday | Normal conditions. Full deployment. |
| Thursday | Expiry day (if weekly). Higher gamma risk. Reduce size by 30%. |
| Friday | Weekend theta decay. Close all before 15:15. No overnight. |

### 11.3 Monthly Expiry Adjustments

| Proximity to Expiry | Adjustment |
|--------------------|------------|
| T-5 to T-3 | Normal |
| T-2 | Reduce size by 20% (theta accel) |
| T-1 (day before) | Reduce size by 40%, tighten SL to 20% |
| T-0 (expiry) | Reduce size by 60%, only scalp, 15-min max hold |

---

## 12. Error Handling & Rate Limits

### 12.1 DhanHQ Error Codes

| Code | Meaning | Action |
|------|---------|--------|
| `DH-901` | Invalid auth token | Refresh token via `TokenManager`, retry |
| `DH-902` | No API access | Check subscription in Dhan dashboard |
| `DH-903` | Account error | Check segment activation, KYC status |
| `DH-904` | Rate limit exceeded | Exponential backoff: 1s → 2s → 4s → 8s |
| `DH-905` | Bad input | Log params, fix validation, retry once |
| `DH-906` | Order error | Log full error, do NOT retry automatically |
| `DH-907` | Data error | Check securityId, retry once after 2s |
| `DH-908` | Server error | Retry after 5s, max 3 attempts |

### 12.2 WebSocket Disconnection Codes

| Code | Meaning | Action |
|------|---------|--------|
| `800` | Internal server error | Reconnect after 5s |
| `804` | >100 instruments in single sub | Split into multiple subscribe messages |
| `805` | >5 connections or too many requests | Close oldest connection, reconnect |
| `806` | Data APIs not subscribed | Subscribe via Dhan dashboard |
| `807` | Token expired | Refresh JWT, reconnect |
| `808–810` | Auth failed | Re-generate access token |

### 12.3 Retry Strategy

```ruby
RETRY_CONFIG = {
  order_place: { max_attempts: 2, backoff: [1, 2] },
  order_modify: { max_attempts: 3, backoff: [0.5, 1, 2] },
  order_cancel: { max_attempts: 2, backoff: [0.5, 1] },
  ws_reconnect: { max_attempts: :infinite, backoff: [5, 10, 30, 60] },
  margin_check: { max_attempts: 2, backoff: [1, 2] }
}
```

---

## 13. Deployment Checklist

### 13.1 Pre-Deployment

- [ ] DhanHQ developer account activated + API subscription active
- [ ] Static IP whitelisted in Dhan dashboard
- [ ] `access-token` and `client-id` stored in `.env` (NOT in repo)
- [ ] Instrument master CSV downloaded and `instruments` table seeded
- [ ] Security IDs verified for:
  - [ ] NIFTY spot (IDX_I)
  - [ ] BANKNIFTY spot (IDX_I)
  - [ ] SENSEX spot (IDX_I)
  - [ ] Current week CE/PE contracts for all 3 indices
- [ ] Paper trading validated for 5+ sessions
- [ ] All tests pass: `bundle exec rspec`
- [ ] Lint clean: `bundle exec rubocop`

### 13.2 Configuration

```yaml
# config/algo.yml (excerpt)
trading:
  enabled: true
  max_positions_per_index: 1
  entries_per_day_per_index: 3

paper_trading:
  enabled: false  # Set true for paper mode

dhanhq:
  client_id: <%= ENV['DHAN_CLIENT_ID'] %>
  access_token: <%= ENV['DHAN_ACCESS_TOKEN'] %>
  enable_orders: true  # Set false to disable ALL broker orders

risk:
  max_daily_loss_pct: 0.03
  max_drawdown_pct: 0.05
  max_consecutive_losses: 3
  base_risk_per_trade_pct: 0.02

signals:
  tick_ai_analysis_enabled: false  # Optional: Ollama AI analysis
  telegram_notify_entry: true
  telegram_notify_exit: true
```

### 13.3 Startup Sequence

```bash
# 1. Database & queue
rails db:migrate
rails solid_queue:load_recurring

# 2. Verify config
rails runner "puts AlgoConfig.fetch.to_yaml"

# 3. Start in paper mode first
LIVE_TRADING=false PLACE_ORDER=true ./bin/dev

# 4. After validation, switch to live
LIVE_TRADING=true PLACE_ORDER=true ENABLE_TRADING_SERVICES=true ./bin/dev
```

### 13.4 Monitoring

| Check | Command / Method |
|-------|-----------------|
| WebSocket health | Dashboard → "Feed Status" indicator |
| Active positions | `GET /api/positions` or dashboard |
| Order status | `GET /api/orders` or poll order book |
| Daily PnL | Dashboard PnL card or `Live::DailyPnlRecorder` |
| Risk status | `Live::RiskManagerService.status` |
| Logs | `tail -f log/trading.log` |
| Telegram alerts | Verify bot is responding to `/status` |

### 13.5 Shutdown Sequence

```bash
# 1. Stop accepting new signals
# 2. Close all open positions (market orders)
# 3. Cancel all pending orders
# 4. Disconnect WebSocket feeds
# 5. Save final PnL to database
# 6. Send shutdown notification
# 7. Terminate processes
```

---

## 14. Code Snippets

### 14.1 Place a NIFTY CE Market Order (Ruby)

```ruby
# frozen_string_literal: true

require 'net/http'
require 'json'

class DhanOrderClient
  BASE_URL = 'https://api.dhan.co/v2'

  def initialize(client_id:, access_token:)
    @client_id = client_id
    @access_token = access_token
  end

  def place_market_order(security_id:, quantity:, transaction_type: 'BUY',
                         exchange_segment: 'NSE_FNO', product_type: 'INTRADAY',
                         correlation_id: nil)
    uri = URI("#{BASE_URL}/orders")
    req = Net::HTTP::Post.new(uri)
    req['Content-Type'] = 'application/json'
    req['access-token'] = @access_token

    payload = {
      dhanClientId: @client_id,
      correlationId: correlation_id || SecureRandom.hex(8),
      transactionType: transaction_type,
      exchangeSegment: exchange_segment,
      productType: product_type,
      orderType: 'MARKET',
      validity: 'DAY',
      securityId: security_id.to_s,
      quantity: quantity.to_s,
      price: '0',
      afterMarketOrder: false
    }

    req.body = payload.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    JSON.parse(res.body)
  rescue JSON::ParserError
    { error: res.body, status_code: res.code }
  end

  def get_order_by_correlation(correlation_id)
    uri = URI("#{BASE_URL}/orders/external/#{correlation_id}")
    req = Net::HTTP::Get.new(uri)
    req['access-token'] = @access_token

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    JSON.parse(res.body)
  end
end

# Usage
client = DhanOrderClient.new(
  client_id: ENV['DHAN_CLIENT_ID'],
  access_token: ENV['DHAN_ACCESS_TOKEN']
)

result = client.place_market_order(
  security_id: '52175',
  quantity: 50,  # 2 lots of NIFTY (25 × 2)
  correlation_id: 'nifty_ce_20260619_093045_ABC123'
)

puts result
# => { "orderId" => "112111182198", "orderStatus" => "PENDING" }
```

### 14.2 WebSocket Market Feed (Ruby — Simplified)

```ruby
# frozen_string_literal: true

require 'websocket-client-simple'
require 'json'

class DhanMarketFeed
  WS_URL = 'wss://api-feed.dhan.co'

  def initialize(client_id:, access_token:)
    @client_id = client_id
    @access_token = access_token
    @running = false
  end

  def connect
    url = "#{WS_URL}?version=2&token=#{@access_token}&clientId=#{@client_id}&authType=2"
    @ws = WebSocket::Client::Simple.connect(url)

    @ws.on :message do |msg|
      if msg.type == :binary
        parse_binary(msg.data)
      else
        puts "Text: #{msg.data}"
      end
    end

    @ws.on :open do
      puts 'Connected to market feed'
      subscribe_instruments
    end

    @ws.on :close do |e|
      puts "Closed: #{e}"
      reconnect
    end

    @ws.on :error do |e|
      puts "Error: #{e}"
    end

    @running = true
    sleep while @running
  end

  def subscribe_instruments
    # NIFTY spot + 1 CE contract
    msg = {
      RequestCode: 21,  # Full packet
      InstrumentCount: 2,
      InstrumentList: [
        { ExchangeSegment: 'IDX_I', SecurityId: '13' },
        { ExchangeSegment: 'NSE_FNO', SecurityId: '52175' }
      ]
    }
    @ws.send(msg.to_json)
  end

  def parse_binary(data)
    bytes = data.bytes
    return if bytes.length < 8

    response_code = bytes[0]
    msg_length = bytes[1..2].pack('C*').unpack1('v')  # Little endian int16
    segment = bytes[3]
    security_id = bytes[4..7].pack('C*').unpack1('V')  # Little endian int32

    case response_code
    when 2
      ltp = bytes[9..12].pack('C*').unpack1('e')  # float32 little endian
      ltt = bytes[13..16].pack('C*').unpack1('V')  # int32
      puts "[TICK] Security=#{security_id} LTP=#{ltp} Time=#{Time.at(ltt)}"
    when 4
      # Parse quote packet...
    when 8
      # Parse full packet...
    end
  end

  def reconnect
    @running = false
    sleep 5
    connect
  end
end
```

### 14.3 Complete Entry Flow (Using Existing Services)

```ruby
# frozen_string_literal: true

# This shows how the existing algo_scalper_api services orchestrate a trade

class OptionsBuyingExample
  def initialize
    @entry_engine = Trading::EntryEngine.new(
      structure: Smc::StructureAnalyzer.new,
      liquidity: Smc::LiquidityAnalyzer.new,
      zones: Smc::ZoneCalculator.new,
      price: current_price,
      displacement: Smc::DisplacementDetector.new,
      volume: Indicators::VolumeSpike.new,
      mtf: MarketContext::MultiTimeframe.new
    )
    @strike_selector = Options::StrikeSelector.new
    @entry_manager = Orders::EntryManager.new
  end

  def run(index_key: 'NIFTY')
    # 1. Generate signal
    signal = @entry_engine.call
    return { action: :no_signal } unless signal

    direction = signal.action == 'BUY_CE' ? :bullish : :bearish

    # 2. Get trend score
    trend_scorer = Trading::TrendScorer.new(index_key: index_key)
    trend_score = trend_scorer.score

    # 3. Select strike
    index_cfg = IndexConfigLoader.find(index_key)
    pick = @strike_selector.select(
      index_key: index_key,
      direction: direction,
      trend_score: trend_score
    )
    return { action: :no_strike } unless pick

    # 4. Check entry guard
    permitted = Entries::EntryGuardPipeline.call(
      index_cfg: index_cfg,
      pick: pick,
      direction: direction
    )
    return { action: :guard_blocked } unless permitted

    # 5. Calculate position size
    allocator = Capital::Allocator.new(index_key: index_key)
    lots = allocator.lots_for(pick, trend_score: trend_score)
    quantity = lots * pick[:lot_size]

    # 6. Place order via EntryManager
    result = @entry_manager.process_entry(
      signal_result: { candidate: pick },
      index_cfg: index_cfg,
      direction: direction,
      scale_multiplier: 1,
      trend_score: trend_score
    )

    if result[:success]
      {
        action: :entered,
        order_no: result[:order_no],
        tracker_id: result[:tracker_id],
        sl_price: result[:sl_price],
        tp_price: result[:tp_price]
      }
    else
      { action: :entry_failed, error: result[:error] }
    end
  end
end
```

### 14.4 Exit Monitoring Loop

```ruby
# Runs in the trading daemon (see lib/trading_system/daemon.rb)
# Every tick triggers this check for active positions

def check_exits(tick)
  ActiveCache.instance.each_position do |position|
    tracker = position.tracker
    current_ltp = tick.ltp.to_f
    entry = tracker.entry_price.to_f

    # PnL percentage
    pnl_pct = tracker.direction == 'bullish' ?
                ((current_ltp - entry) / entry) :
                ((entry - current_ltp) / entry)

    # Hard SL (premium stop)
    if current_ltp <= position.sl_price
      exit_position(tracker, :stop_loss, current_ltp)
      next
    end

    # Take profit
    if position.tp_price && current_ltp >= position.tp_price
      exit_position(tracker, :take_profit, current_ltp)
      next
    end

    # Trailing stop
    if pnl_pct >= 0.20
      new_sl = entry * 1.0  # Breakeven
      update_trailing_stop(position, new_sl)
    end

    # Time-based exit
    if Time.current.hour >= 15 && Time.current.min >= 15
      exit_position(tracker, :time_exit, current_ltp)
    end
  end
end
```

---

## Appendix A: Lot Sizes & Multipliers

| Index | Lot Size | Min Tick | Margin (approx, ATM) |
|-------|----------|----------|---------------------|
| NIFTY 50 | 25 | ₹0.05 | ₹500–2,000 |
| BANKNIFTY | 15 | ₹0.05 | ₹800–3,000 |
| SENSEX | 10 | ₹0.05 | ₹1,000–4,000 |

> Margin varies with IV and days to expiry. Always call margin calculator before placing.

## Appendix B: Quick Reference — curl Commands

```bash
# 1. Place NIFTY CE Market Order
curl -X POST https://api.dhan.co/v2/orders \
  -H "Content-Type: application/json" \
  -H "access-token: $DHAN_TOKEN" \
  -d '{
    "dhanClientId":"'$DHAN_CLIENT_ID'",
    "correlationId":"test_nifty_ce_001",
    "transactionType":"BUY",
    "exchangeSegment":"NSE_FNO",
    "productType":"INTRADAY",
    "orderType":"MARKET",
    "validity":"DAY",
    "securityId":"52175",
    "quantity":"25",
    "price":"0"
  }'

# 2. Get order status
curl https://api.dhan.co/v2/orders/112111182198 \
  -H "access-token: $DHAN_TOKEN"

# 3. Get order by correlation ID
curl https://api.dhan.co/v2/orders/external/test_nifty_ce_001 \
  -H "access-token: $DHAN_TOKEN"

# 4. Cancel order
curl -X DELETE https://api.dhan.co/v2/orders/112111182198 \
  -H "access-token: $DHAN_TOKEN"

# 5. Get order book
curl https://api.dhan.co/v2/orders \
  -H "access-token: $DHAN_TOKEN"

# 6. Get trade book
curl https://api.dhan.co/v2/trades \
  -H "access-token: $DHAN_TOKEN"

# 7. Calculate margin
curl -X POST https://api.dhan.co/v2/margincalculator \
  -H "Content-Type: application/json" \
  -H "access-token: $DHAN_TOKEN" \
  -d '{
    "dhanClientId":"'$DHAN_CLIENT_ID'",
    "transactionType":"BUY",
    "exchangeSegment":"NSE_FNO",
    "productType":"INTRADAY",
    "securityId":"52175",
    "quantity":"25",
    "price":"250"
  }'
```

---

*Playbook compiled from DhanHQ v2 API docs (https://dhanhq.co/docs/v2/) and algo_scalper_api codebase analysis. For the latest API specs, always refer to the official DhanHQ documentation.*
