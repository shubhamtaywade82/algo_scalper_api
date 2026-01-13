# Complete System Analysis: algo_scalper_api

**Last Updated**: Current
**Purpose**: Comprehensive analysis of the entire trading system - what's used, what's not, configurations, services, and responsibilities

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Active Services & Responsibilities](#2-active-services--responsibilities)
3. [Configuration Analysis](#3-configuration-analysis)
4. [Unused/Disabled Features](#4-unuseddisabled-features)
5. [Complete System Flow](#5-complete-system-flow)
6. [Service Dependencies](#6-service-dependencies)
7. [Models & Data Structures](#7-models--data-structures)
8. [External Integrations](#8-external-integrations)

---

## 1. System Overview

### 1.1 Application Type
- **Framework**: Rails 8.0 API-only application
- **Purpose**: Automated options trading system for Indian markets (NSE)
- **Trading Mode**: Paper trading (configurable) or Live trading
- **Primary Strategy**: Supertrend + ADX with No-Trade Engine validation

### 1.2 Core Components
1. **Signal Generation**: Technical indicator-based signal generation
2. **Entry Management**: Position entry with validation
3. **Risk Management**: Position monitoring and exit execution
4. **Order Management**: Order placement and tracking
5. **Market Data**: Real-time WebSocket feed integration

### 1.3 Startup Flow

```
Rails Server (bin/dev)
  └─> config/initializers/trading_supervisor.rb
      └─> TradingSystem::Supervisor
          └─> Registers 9 services
              └─> Starts services (if market open)
```

---

## 2. Active Services & Responsibilities

### 2.1 Services Started by Supervisor

**Location**: `config/initializers/trading_supervisor.rb:155-163`

#### ✅ **1. MarketFeedHub** (Active)
- **Class**: `Live::MarketFeedHub` (Singleton)
- **Thread**: `market-feed-hub`
- **Status**: ✅ **ACTIVE** - Always starts (even when market closed)
- **Responsibilities**:
  - WebSocket connection to DhanHQ market data feed
  - Subscribe to watchlist instruments (NIFTY, BANKNIFTY, SENSEX)
  - Subscribe to option instruments on-demand
  - Distribute real-time ticks to subscribers
  - Store ticks in TickCache (in-memory) and RedisTickCache (Redis)
- **Dependencies**: DhanHQ WebSocket client, Redis
- **Subscribers**: ActiveCache, PositionIndex

#### ✅ **2. Signal::Scheduler** (Active)
- **Class**: `Signal::Scheduler` (Instance)
- **Thread**: `signal-scheduler`
- **Status**: ✅ **ACTIVE** - Starts when market open
- **Responsibilities**:
  - Generate trading signals every 1 second
  - Process each configured index (NIFTY, BANKNIFTY, SENSEX)
  - Call `Signal::Engine.run_for()` with No-Trade Engine validation
  - Trigger entry flow when signals validated
- **Flow**:
  1. Check market closed → skip if closed
  2. For each index:
     - Phase 1: Quick No-Trade pre-check
     - Signal generation (Supertrend + ADX)
     - Strike selection
     - Phase 2: Detailed No-Trade validation
     - EntryGuard.try_enter() (if both phases pass)
- **Dependencies**: Signal::Engine, NoTradeEngine, EntryGuard, ChainAnalyzer

#### ✅ **3. RiskManagerService** (Active)
- **Class**: `Live::RiskManagerService` (Instance)
- **Thread**: `risk-manager` + `risk-manager-watchdog`
- **Status**: ✅ **ACTIVE** - Starts when market open
- **Responsibilities**:
  - Monitor all active positions continuously
  - Update paper position PnL (every 1 minute)
  - Ensure positions in Redis/ActiveCache (every 5 seconds)
  - Process trailing stops for all positions
  - Enforce exit conditions (SL, TP, peak drawdown, session end)
  - Execute exits via ExitEngine
- **Frequency**: 500ms (active positions) or 5000ms (idle)
- **Dependencies**: ActiveCache, RedisPnlCache, TrailingEngine, ExitEngine

#### ✅ **4. PositionHeartbeat** (Active)
- **Class**: `TradingSystem::PositionHeartbeat` (Instance)
- **Thread**: `position-heartbeat`
- **Status**: ✅ **ACTIVE** - Starts when market open
- **Responsibilities**:
  - Periodic health check for active positions
  - Ensure positions are properly tracked
- **Dependencies**: PositionTracker model

#### ✅ **5. OrderRouter** (Active)
- **Class**: `TradingSystem::OrderRouter` (Instance)
- **Thread**: N/A (called synchronously)
- **Status**: ✅ **ACTIVE** - Starts when market open
- **Responsibilities**:
  - Route orders to appropriate gateway (Paper or Live)
  - Handle order retries with backoff
  - Manage order state transitions
- **Dependencies**: Orders::GatewayPaper, Orders::GatewayLive

#### ✅ **6. PaperPnlRefresher** (Active)
- **Class**: `Live::PaperPnlRefresher` (Instance)
- **Thread**: `paper-pnl-refresher`
- **Status**: ✅ **ACTIVE** - Starts when market open
- **Responsibilities**:
  - Refresh PnL for all paper positions periodically
  - Update PositionTracker database fields
  - Store PnL in RedisPnlCache
- **Frequency**: 1 second (active) or 5000ms (idle)
- **Dependencies**: TickCache, RedisPnlCache, PositionTracker

#### ✅ **7. ExitEngine** (Active)
- **Class**: `Live::ExitEngine` (Instance)
- **Thread**: N/A (called synchronously)
- **Status**: ✅ **ACTIVE** - Starts when market open
- **Responsibilities**:
  - Execute position exits (paper and live)
  - Place exit orders via OrderRouter
  - Update PositionTracker status
  - Handle exit idempotency
- **Dependencies**: OrderRouter, PositionTracker

#### ✅ **8. ActiveCache** (Active)
- **Class**: `Positions::ActiveCache` (Singleton)
- **Thread**: N/A (in-memory cache)
- **Status**: ✅ **ACTIVE** - Starts when market open
- **Responsibilities**:
  - In-memory cache of active positions
  - Subscribe to market data for active positions
  - Provide fast position lookups
- **Dependencies**: MarketFeedHub

#### ✅ **9. ReconciliationService** (Active)
- **Class**: `Live::ReconciliationService` (Singleton)
- **Thread**: N/A (called on-demand)
- **Status**: ✅ **ACTIVE** - Starts when market open
- **Responsibilities**:
  - Reconcile position data between database and cache
  - Ensure data consistency
- **Dependencies**: PositionTracker, ActiveCache

### 2.2 Services NOT Started by Supervisor (But Available)

#### ⚠️ **PnlUpdaterService** (Available but NOT started)
- **Class**: `Live::PnlUpdaterService` (Singleton)
- **Status**: ⚠️ **NOT STARTED** - Commented out in supervisor
- **Note**: PaperPnlRefresher handles paper PnL updates instead
- **Location**: `config/initializers/trading_supervisor.rb:166` (commented)

#### ⚠️ **OrderUpdateHub** (Available but NOT started)
- **Class**: `Live::OrderUpdateHub` (Instance)
- **Status**: ⚠️ **NOT STARTED** - Not registered in supervisor
- **Note**: Only starts in live mode (not paper mode)
- **Purpose**: WebSocket order updates for live trading

#### ⚠️ **OrderUpdateHandler** (Available but NOT started)
- **Class**: `Live::OrderUpdateHandler` (Instance)
- **Status**: ⚠️ **NOT STARTED** - Not registered in supervisor
- **Note**: Processes order updates from OrderUpdateHub
- **Purpose**: Handle order status changes for live trading

### 2.3 Utility Services (No Threads)

#### ✅ **EntryGuard** (Used)
- **Class**: `Entries::EntryGuard`
- **Status**: ✅ **USED** - Called by Signal::Scheduler
- **Responsibilities**:
  - Validate entry conditions
  - Check trading session, daily limits, exposure limits
  - Calculate quantity via Capital::Allocator
  - Place orders (paper or live)
  - Create PositionTracker records

#### ✅ **EntryManager** (Used)
- **Class**: `Orders::EntryManager`
- **Status**: ✅ **USED** - Called by EntryGuard
- **Responsibilities**:
  - Post-entry wiring (bracket orders, subscriptions, etc.)
  - Add positions to ActiveCache
  - Record trades in DailyLimits

#### ✅ **TrailingEngine** (Used)
- **Class**: `Live::TrailingEngine`
- **Status**: ✅ **USED** - Called by RiskManagerService
- **Responsibilities**:
  - Process trailing stop logic per position
  - Check peak-drawdown exit conditions
  - Update bracket orders via BracketPlacer

#### ✅ **ChainAnalyzer** (Used)
- **Class**: `Options::ChainAnalyzer`
- **Status**: ✅ **USED** - Called by Signal::Engine
- **Responsibilities**:
  - Analyze option chain
  - Score and rank option candidates
  - Select best strikes based on OI, IV, spread, volume

#### ✅ **Capital::Allocator** (Used)
- **Class**: `Capital::Allocator`
- **Status**: ✅ **USED** - Called by EntryGuard
- **Responsibilities**:
  - Calculate position quantity based on risk percentage
  - Use paper trading balance or live balance
  - Apply capital allocation per index

#### ✅ **DailyLimits** (Used)
- **Class**: `Live::DailyLimits`
- **Status**: ✅ **USED** - Called by EntryGuard and RiskManagerService
- **Responsibilities**:
  - Track daily loss limits per index
  - Track daily trade counts per index
  - Check if trading is allowed

#### ✅ **UnderlyingMonitor** (Used)
- **Class**: `Live::UnderlyingMonitor`
- **Status**: ✅ **USED** - Called by RiskManagerService
- **Responsibilities**:
  - Monitor underlying index health
  - Check trend strength, ATR collapse, structure breaks
  - Trigger exits when underlying conditions deteriorate

#### ✅ **BracketPlacer** (Used)
- **Class**: `Orders::BracketPlacer`
- **Status**: ✅ **USED** - Called by EntryManager and TrailingEngine
- **Responsibilities**:
  - Place/modify bracket orders (SL/TP)
  - Update SL orders when trailing stops move

#### ✅ **NoTradeEngine** (Used)
- **Class**: `Entries::NoTradeEngine`
- **Status**: ✅ **USED** - Called by Signal::Engine (if enabled)
- **Responsibilities**:
  - Two-phase validation to block bad trades
  - Phase 1: Quick pre-check (before signal generation)
  - Phase 2: Detailed validation (after signal generation)
  - 11-point scoring system (blocks if score ≥ 5)

---

## 3. Configuration Analysis

### 3.1 Active Configurations (Currently Used)

#### ✅ **Paper Trading** (Active)
```yaml
paper_trading:
  enabled: true  # ✅ ACTIVE - System runs in paper mode
  balance: 100000
```
- **Used by**: Orders::GatewayPaper, Capital::Allocator
- **Status**: ✅ **ACTIVE**

#### ✅ **Indices Configuration** (Active)
```yaml
indices:
  - key: NIFTY
  - key: BANKNIFTY
  - key: SENSEX
```
- **Used by**: Signal::Scheduler, EntryGuard, DailyLimits
- **Status**: ✅ **ACTIVE** - All 3 indices configured

#### ✅ **Risk Configuration** (Active)
```yaml
risk:
  sl_pct: 0.30  # ✅ USED - 30% stop loss
  tp_pct: 0.60  # ✅ USED - 60% take profit
  direct_trailing:
    enabled: true  # ✅ USED - Direct trailing stop
    distance_pct: 5.0
  daily_limits:
    enable: true  # ✅ USED - Daily loss limits
```
- **Used by**: RiskManagerService, TrailingEngine, DailyLimits
- **Status**: ✅ **ACTIVE**

#### ✅ **Signal Configuration** (Active)
```yaml
signals:
  enable_supertrend_signal: true  # ✅ ACTIVE
  enable_adx_filter: true  # ✅ ACTIVE
  enable_confirmation_timeframe: false  # ❌ DISABLED
  supertrend:
    period: 10  # ✅ USED
    base_multiplier: 1.5  # ✅ USED
  adx:
    min_strength: 10  # ✅ USED
```
- **Used by**: Signal::Engine
- **Status**: ✅ **ACTIVE** (Supertrend + ADX enabled, 5m confirmation disabled)

#### ✅ **Chain Analyzer** (Active)
```yaml
chain_analyzer:
  max_candidates: 2  # ✅ USED
  min_oi: 10000  # ✅ USED
  min_iv: 5.0  # ✅ USED
  max_iv: 60.0  # ✅ USED
```
- **Used by**: Options::ChainAnalyzer
- **Status**: ✅ **ACTIVE**

#### ✅ **Telegram** (Active)
```yaml
telegram:
  enabled: true  # ✅ ACTIVE
  notify_entry: true  # ✅ USED
  notify_exit: true  # ✅ USED
  notify_pnl_milestones: true  # ✅ USED
```
- **Used by**: TelegramNotifier (various services)
- **Status**: ✅ **ACTIVE**

### 3.2 Disabled/Unused Configurations

#### ❌ **No-Trade Engine** (Disabled)
```yaml
signals:
  enable_no_trade_engine: false  # ❌ DISABLED
```
- **Status**: ❌ **DISABLED** - Not currently active
- **Note**: Can be enabled by setting to `true`

#### ❌ **Trend Scorer** (Disabled)
```yaml
feature_flags:
  enable_trend_scorer: false  # ❌ DISABLED
```
- **Status**: ❌ **DISABLED** - Uses legacy Supertrend+ADX path
- **Note**: When enabled, uses TrendScorer instead of Supertrend+ADX

#### ❌ **Multi-Indicator Strategy** (Disabled)
```yaml
signals:
  use_multi_indicator_strategy: false  # ❌ DISABLED
```
- **Status**: ❌ **DISABLED** - Modular indicator system not active
- **Note**: When enabled, uses multiple indicators (Supertrend, ADX, RSI, MACD)

#### ❌ **Optimized Parameters** (Disabled)
```yaml
signals:
  use_optimized_params: false  # ❌ DISABLED
```
- **Status**: ❌ **DISABLED** - Uses hardcoded defaults from algo.yml
- **Note**: When enabled, loads from BestIndicatorParam database table

#### ❌ **Confirmation Timeframe** (Disabled)
```yaml
signals:
  enable_confirmation_timeframe: false  # ❌ DISABLED
```
- **Status**: ❌ **DISABLED** - Only uses 1m timeframe
- **Note**: When enabled, requires 5m confirmation

#### ❌ **Underlying-Aware Exits** (Disabled)
```yaml
feature_flags:
  enable_underlying_aware_exits: false  # ❌ DISABLED
```
- **Status**: ❌ **DISABLED** - UnderlyingMonitor checks not enforced
- **Note**: UnderlyingMonitor exists but exits not triggered

#### ❌ **Peak Drawdown Activation** (Disabled)
```yaml
feature_flags:
  enable_peak_drawdown_activation: false  # ❌ DISABLED
```
- **Status**: ❌ **DISABLED** - Peak drawdown protection not active
- **Note**: Configuration exists but not enforced

#### ❌ **Trading Time Restrictions** (Disabled)
```yaml
trading_time_restrictions:
  enabled: false  # ❌ DISABLED
  avoid_periods: []  # Empty
```
- **Status**: ❌ **DISABLED** - No time-based restrictions
- **Note**: Can be enabled to block trading during specific hours

#### ❌ **Tiered Trailing** (Not Used)
```yaml
risk:
  trailing_mode: direct  # Uses 'direct', not 'tiered'
  trailing_tiers: [...]  # ❌ NOT USED (only used if trailing_mode: 'tiered')
```
- **Status**: ❌ **NOT USED** - System uses direct trailing
- **Note**: Tiered trailing configuration exists but not active

### 3.3 Feature Flags Summary

| Feature Flag                         | Status     | Used By                               |
| ------------------------------------ | ---------- | ------------------------------------- |
| `enable_direction_before_chain`      | ✅ Active   | Signal::Engine                        |
| `enable_trend_scorer`                | ❌ Disabled | Signal::Scheduler                     |
| `enable_auto_subscribe_unsubscribe`  | ✅ Active   | MarketFeedHub                         |
| `enable_demand_driven_services`      | ✅ Active   | RiskManagerService, PaperPnlRefresher |
| `enable_underlying_aware_exits`      | ❌ Disabled | RiskManagerService                    |
| `enable_peak_drawdown_activation`    | ❌ Disabled | TrailingEngine                        |
| `auto_paper_on_insufficient_balance` | ❌ Disabled | EntryGuard                            |

---

## 4. Unused/Disabled Features

### 4.1 Services Not Started

1. **PnlUpdaterService** - Commented out in supervisor (PaperPnlRefresher used instead)
2. **OrderUpdateHub** - Not registered (only for live trading, not paper)
3. **OrderUpdateHandler** - Not registered (only for live trading, not paper)

### 4.2 Features Disabled in Config

1. **No-Trade Engine** - `enable_no_trade_engine: false`
2. **Trend Scorer** - `enable_trend_scorer: false`
3. **Multi-Indicator Strategy** - `use_multi_indicator_strategy: false`
4. **Optimized Parameters** - `use_optimized_params: false`
5. **Confirmation Timeframe** - `enable_confirmation_timeframe: false`
6. **Underlying-Aware Exits** - `enable_underlying_aware_exits: false`
7. **Peak Drawdown Activation** - `enable_peak_drawdown_activation: false`
8. **Trading Time Restrictions** - `trading_time_restrictions.enabled: false`

### 4.3 Unused Code Paths

1. **TrendScorer Path** - Code exists but disabled via feature flag
2. **Multi-Indicator System** - Fully implemented but not enabled
3. **Tiered Trailing** - Configuration exists but direct trailing used instead
4. **5m Confirmation** - Code exists but disabled

---

## 5. Complete System Flow

### 5.1 Startup Sequence

```
1. Rails Server Starts (bin/dev)
   └─> config/initializers/trading_supervisor.rb
       └─> TradingSystem::Supervisor.new
           └─> Registers 9 services
               └─> Check market closed
                   ├─> If closed: Start only MarketFeedHub
                   └─> If open: Start all services
```

### 5.2 Signal Generation Flow (Active Path)

```
Signal::Scheduler (every 1 second)
  └─> For each index (NIFTY, BANKNIFTY, SENSEX)
      └─> Check market closed → skip if closed
      └─> Signal::Engine.run_for(index_cfg)
          ├─> [IF enable_no_trade_engine: false] Skip No-Trade Engine
          ├─> Fetch instrument
          ├─> Load signal config (Supertrend + ADX)
          ├─> Analyze 1m timeframe
          │   ├─> Calculate Supertrend (period: 10, multiplier: 1.5)
          │   ├─> Calculate ADX (min_strength: 10)
          │   └─> Decide direction (bullish/bearish)
          ├─> [IF enable_confirmation_timeframe: false] Skip 5m confirmation
          ├─> Select option strikes (ChainAnalyzer)
          │   ├─> Filter by OI, IV, spread
          │   └─> Score and rank candidates
          └─> EntryGuard.try_enter()
              ├─> Validate entry conditions
              ├─> Check daily limits
              ├─> Calculate quantity (Capital::Allocator)
              ├─> Place order (GatewayPaper or GatewayLive)
              ├─> Create PositionTracker
              └─> EntryManager.post_entry_wiring()
                  ├─> Add to ActiveCache
                  ├─> Subscribe to market data
                  ├─> Place bracket orders (BracketPlacer)
                  └─> Record in DailyLimits
```

### 5.3 Position Monitoring Flow

```
RiskManagerService (every 500ms)
  └─> For each active position
      ├─> Update PnL (PaperPnlRefresher for paper positions)
      ├─> Process trailing stops (TrailingEngine)
      │   ├─> Check direct trailing (distance_pct: 5.0)
      │   └─> Update bracket orders if SL moved
      ├─> Check exit conditions (in priority order):
      │   1. Hard SL hit (-30%)
      │   2. Hard TP hit (+60%)
      │   3. Peak drawdown (if enabled)
      │   4. Session end (3:15 PM IST)
      │   5. Time-based exit (if configured)
      └─> Execute exit (ExitEngine)
          ├─> Place exit order (OrderRouter)
          ├─> Update PositionTracker
          └─> Unsubscribe from market data
```

### 5.4 Market Data Flow

```
MarketFeedHub (WebSocket)
  └─> Receives ticks from DhanHQ
      ├─> Store in TickCache (in-memory)
      ├─> Store in RedisTickCache (Redis)
      └─> Distribute to subscribers
          ├─> ActiveCache (for position updates)
          └─> PositionIndex (for PnL updates)
```

---

## 6. Service Dependencies

### 6.1 Dependency Graph

```
MarketFeedHub
  ├──→ ActiveCache (callbacks)
  ├──→ TickCache (storage)
  └──→ RedisTickCache (storage)

Signal::Scheduler
  ├──→ Signal::Engine
  ├──→ NoTradeEngine (if enabled)
  ├──→ ChainAnalyzer
  ├──→ EntryGuard
  └──→ TradingSession::Service

EntryGuard
  ├──→ TradingSession::Service
  ├──→ DailyLimits
  ├──→ Capital::Allocator
  └──→ Orders::Placer

EntryManager
  ├──→ ActiveCache
  ├──→ MarketFeedHub
  └──→ BracketPlacer

RiskManagerService
  ├──→ ActiveCache
  ├──→ RedisPnlCache
  ├──→ TrailingEngine
  ├──→ UnderlyingMonitor (if enabled)
  └──→ ExitEngine

TrailingEngine
  ├──→ TrailingConfig
  ├──→ ExitEngine
  └──→ BracketPlacer

ExitEngine
  └──→ OrderRouter

PaperPnlRefresher
  ├──→ TickCache
  └──→ RedisPnlCache
```

### 6.2 Startup Dependencies

**Order**:
1. MarketFeedHub (no dependencies)
2. ActiveCache (depends on MarketFeedHub)
3. Signal::Scheduler (depends on Signal::Engine)
4. RiskManagerService (depends on ExitEngine, ActiveCache)
5. ExitEngine (depends on OrderRouter)
6. OrderRouter (no dependencies)
7. PaperPnlRefresher (depends on TickCache)
8. PositionHeartbeat (no dependencies)
9. ReconciliationService (no dependencies)

---

## 7. Models & Data Structures

### 7.1 Active Models

#### ✅ **PositionTracker** (Active)
- **Purpose**: Track all trading positions
- **Used by**: All services
- **Key Fields**: `entry_price`, `exit_price`, `last_pnl_rupees`, `last_pnl_pct`, `status`

#### ✅ **Instrument** (Active)
- **Purpose**: Market instruments (indices, options)
- **Used by**: Signal::Engine, ChainAnalyzer
- **Key Methods**: `candle_series()`, `fetch_option_chain()`, `intraday_ohlc()`

#### ✅ **TradingSignal** (Active)
- **Purpose**: Store generated signals
- **Used by**: Signal::Engine
- **Key Fields**: `direction`, `index_key`, `signal_type`

#### ✅ **BestIndicatorParam** (Active)
- **Purpose**: Store optimized indicator parameters
- **Used by**: OptimizedParamsLoader (if `use_optimized_params: true`)
- **Status**: ⚠️ **NOT USED** (optimized params disabled)

#### ✅ **WatchlistItem** (Active)
- **Purpose**: WebSocket watchlist configuration
- **Used by**: MarketFeedHub
- **Status**: ✅ **USED** (or ENV['DHANHQ_WS_WATCHLIST'])

#### ✅ **Derivative** (Active)
- **Purpose**: Option chain data
- **Used by**: ChainAnalyzer
- **Key Fields**: `strike`, `option_type`, `oi`, `iv`, `ltp`

### 7.2 Data Caches

#### ✅ **TickCache** (Active)
- **Purpose**: In-memory tick storage
- **Used by**: MarketFeedHub, PaperPnlRefresher
- **Type**: In-memory hash

#### ✅ **RedisTickCache** (Active)
- **Purpose**: Persistent tick storage in Redis
- **Used by**: MarketFeedHub
- **Type**: Redis hash

#### ✅ **RedisPnlCache** (Active)
- **Purpose**: PnL data in Redis
- **Used by**: RiskManagerService, PaperPnlRefresher
- **Type**: Redis hash

#### ✅ **ActiveCache** (Active)
- **Purpose**: In-memory active position cache
- **Used by**: RiskManagerService, EntryManager
- **Type**: In-memory hash

#### ✅ **PositionIndex** (Active)
- **Purpose**: Index of active positions by instrument
- **Used by**: MarketFeedHub (subscriptions)
- **Type**: Concurrent::Map

---

## 8. External Integrations

### 8.1 DhanHQ API

#### ✅ **WebSocket Feed** (Active)
- **Purpose**: Real-time market data
- **Used by**: MarketFeedHub
- **Status**: ✅ **ACTIVE**

#### ✅ **REST API** (Active)
- **Purpose**: Historical data, option chain, order placement
- **Used by**: Instrument helpers, Orders::GatewayLive
- **Status**: ✅ **ACTIVE**

### 8.2 Redis

#### ✅ **Redis** (Active)
- **Purpose**: Caching (ticks, PnL), pub/sub
- **Used by**: RedisTickCache, RedisPnlCache
- **Status**: ✅ **ACTIVE**

### 8.3 Telegram

#### ✅ **Telegram** (Active)
- **Purpose**: Notifications (entry, exit, PnL milestones)
- **Used by**: TelegramNotifier (various services)
- **Status**: ✅ **ACTIVE** (if `telegram.enabled: true`)

---

## 9. Summary

### 9.1 What's Active

✅ **9 Services Started**: MarketFeedHub, Signal::Scheduler, RiskManagerService, PositionHeartbeat, OrderRouter, PaperPnlRefresher, ExitEngine, ActiveCache, ReconciliationService

✅ **Core Strategy**: Supertrend + ADX on 1m timeframe

✅ **Risk Management**: Direct trailing stops, daily limits, hard SL/TP

✅ **Paper Trading**: Fully functional

### 9.2 What's Disabled

❌ **No-Trade Engine**: Disabled (`enable_no_trade_engine: false`)

❌ **Trend Scorer**: Disabled (`enable_trend_scorer: false`)

❌ **Multi-Indicator System**: Disabled (`use_multi_indicator_strategy: false`)

❌ **Optimized Parameters**: Disabled (`use_optimized_params: false`)

❌ **5m Confirmation**: Disabled (`enable_confirmation_timeframe: false`)

❌ **Underlying-Aware Exits**: Disabled (`enable_underlying_aware_exits: false`)

❌ **Peak Drawdown**: Disabled (`enable_peak_drawdown_activation: false`)

### 9.3 Current Trading Flow

1. **Signal Generation**: Supertrend + ADX on 1m (every 1 second)
2. **Entry**: EntryGuard validates and places orders
3. **Monitoring**: RiskManagerService monitors positions (every 500ms)
4. **Exits**: Hard SL/TP, session end, direct trailing stops
5. **PnL Updates**: PaperPnlRefresher updates paper positions (every 1 second)

---

**This document provides a complete overview of the entire system. For specific implementation details, refer to individual service documentation.**

