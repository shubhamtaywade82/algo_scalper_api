# Services Summary - Complete Service Responsibilities

**Last Updated:** Based on actual codebase analysis  
**Repository:** https://github.com/shubhamtaywade82/algo_scalper_api/tree/new_trailing

---

## Table of Contents

1. [Independent Services](#1-independent-services)
2. [Integrated Services](#2-integrated-services)
3. [Utility Services](#3-utility-services)
4. [Service Dependencies](#4-service-dependencies)
5. [Service Lifecycle](#5-service-lifecycle)

---

## 1. Independent Services

Services that run continuously in their own threads.

### 1.1 MarketFeedHub

**Class:** `Live::MarketFeedHub`  
**File:** `app/services/live/market_feed_hub.rb`  
**Pattern:** Singleton  
**Thread:** `market-feed-hub`

**Responsibilities:**
- Manage WebSocket connection to DhanHQ market data feed
- Subscribe to watchlist instruments (indices: NIFTY, BANKNIFTY, SENSEX)
- Subscribe to individual option instruments on-demand
- Receive and distribute market ticks to subscribers
- Store ticks in TickCache (in-memory) and RedisTickCache (persistent)
- Monitor connection health and emit connection state events
- Handle reconnection logic on connection failures

**Key Methods:**
- `start!()` - Start WebSocket connection and subscribe to watchlist
- `stop!()` - Disconnect WebSocket and cleanup
- `subscribe_instrument(segment:, security_id:)` - Subscribe to specific instrument
- `unsubscribe_instrument(segment:, security_id:)` - Unsubscribe from instrument
- `on_tick { |tick| ... }` - Register callback for tick events
- `handle_tick(tick)` - Process incoming tick and distribute to callbacks

**Frequency:** Continuous (real-time tick reception)

**Dependencies:**
- DhanHQ WebSocket client
- Redis (for RedisTickCache)
- TickCache (in-memory)

**Subscribers:**
- ActiveCache (via callbacks)
- PositionIndex (for PnL updates)

---

### 1.2 Signal::Scheduler

**Class:** `Signal::Scheduler`  
**File:** `app/services/signal/scheduler.rb`  
**Pattern:** Instance (created by Supervisor)  
**Thread:** `signal-scheduler`

**Responsibilities:**
- Generate trading signals for configured indices (NIFTY, BANKNIFTY, SENSEX)
- **NEW**: Includes No-Trade Engine validation (two-phase)
- Evaluate trend direction using TrendScorer (when direction-first enabled)
- Select option candidates using ChainAnalyzer
- Validate signals through EntryGuard
- Process signals and trigger entry flow

**Key Methods:**
- `start()` - Start periodic signal generation loop
- `stop()` - Stop signal generation
- `process_index(index_cfg)` - Process single index
  - **NEW**: Calls `Signal::Engine.run_for()` which includes No-Trade Engine
- `evaluate_supertrend_signal(index_cfg)` - Generate signal for index (legacy path)
- `process_signal(index_cfg, signal)` - Process validated signal (legacy path)

**Frequency:** 1 second (configurable via `period`)

**Dependencies:**
- Signal::Engine.run_for() - **NEW**: Full flow with No-Trade Engine
- Entries::NoTradeEngine - **NEW**: Two-phase validation
- TrendScorer (for direction-first logic, if enabled)
- ChainAnalyzer (for option selection)
- EntryGuard (for entry execution)
- TradingSession::Service (for market hours check)

**Flow (Updated with No-Trade Engine):**
1. Loop through indices (every 1 second)
2. Check if market closed → skip
3. **NEW**: Call `Signal::Engine.run_for()` which includes:
   - Phase 1: Quick No-Trade pre-check (before signal generation)
   - Signal generation (Supertrend + ADX)
   - Strike selection
   - Phase 2: Detailed No-Trade validation (after signal generation)
   - EntryGuard.try_enter() (only if both phases pass)
4. Legacy path: evaluate_supertrend_signal() → process_signal() (if trend_scorer enabled)

---

### 1.3 RiskManagerService

**Class:** `Live::RiskManagerService`  
**File:** `app/services/live/risk_manager_service.rb`  
**Pattern:** Instance (created by Supervisor)  
**Thread:** `risk-manager`  
**Watchdog Thread:** `risk-manager-watchdog`

**Responsibilities:**
- Monitor all active positions continuously
- Update paper position PnL (every 1 minute)
- Ensure all positions are in Redis cache (every 5 seconds)
- Ensure all positions are in ActiveCache (every 5 seconds)
- Ensure all positions are subscribed to market data (every 5 seconds)
- Process trailing stops for all positions (every loop iteration)
- Enforce underlying-aware exits (if enabled)
- Enforce hard SL/TP limits
- Enforce session end exit (3:15 PM IST)
- Enforce time-based exit (if configured)
- Execute exits via ExitEngine (or self-managed fallback)

**Key Methods:**
- `start()` - Start monitoring loop
- `stop()` - Stop monitoring
- `monitor_loop()` - Main monitoring loop
- `process_trailing_for_all_positions()` - Process trailing logic per position
- `handle_underlying_exit()` - Check underlying-aware exit conditions
- `enforce_bracket_limits()` - Enforce hard SL/TP
- `enforce_session_end_exit()` - Force exit before 3:15 PM IST
- `guarded_exit()` - Execute exit with idempotency check

**Frequency:**
- Active positions: 500ms (`loop_interval_active`)
- No positions (demand-driven): 5000ms (`loop_interval_idle`)

**Dependencies:**
- ActiveCache (position data)
- RedisPnlCache (PnL data)
- UnderlyingMonitor (underlying health checks)
- TrailingEngine (trailing stop logic)
- ExitEngine (exit execution)
- TradingSession::Service (session checks)

**Exit Priority Order:**
1. Underlying structure break
2. Underlying weak trend
3. Underlying ATR collapse
4. Hard SL hit
5. Hard TP hit
6. Peak-drawdown exit
7. Session end exit (3:15 PM IST)
8. Time-based exit

---

### 1.4 PaperPnlRefresher

**Class:** `Live::PaperPnlRefresher`  
**File:** `app/services/live/paper_pnl_refresher.rb`  
**Pattern:** Instance (created by Supervisor)  
**Thread:** `paper-pnl-refresher`

**Responsibilities:**
- Refresh PnL for all paper positions periodically
- Update PositionTracker database fields (last_pnl_rupees, last_pnl_pct, high_water_mark_pnl)
- Store PnL in RedisPnlCache for fast access
- Wake up on position events (if demand-driven enabled)

**Key Methods:**
- `start()` - Start refresh loop
- `stop()` - Stop refresh loop
- `refresh_all()` - Refresh all paper positions
- `refresh_tracker(tracker)` - Refresh single tracker

**Frequency:**
- Active positions: 1 second (`realtime_interval_seconds`)
- No positions (demand-driven): 5000ms (`loop_interval_idle`)

**Dependencies:**
- TickCache (for LTP lookup)
- RedisPnlCache (for storage)
- PositionTracker (database)

**Flow:**
1. Get all paper active positions
2. For each position:
   - Get LTP from TickCache
   - Calculate PnL
   - Update database
   - Store in RedisPnlCache

---

### 1.5 PnlUpdaterService

**Class:** `Live::PnlUpdaterService`  
**File:** `app/services/live/pnl_updater_service.rb`  
**Pattern:** Singleton  
**Thread:** `pnl-updater-service`

**Responsibilities:**
- Batch write PnL updates to Redis cache
- Queue PnL updates from multiple sources (last-wins per tracker_id)
- Flush queue periodically to Redis
- Update PositionTracker database fields in batch

**Key Methods:**
- `start!()` - Start flush loop
- `stop!()` - Stop flush loop
- `cache_intermediate_pnl(tracker_id:, pnl:, pnl_pct:, ltp:, hwm:)` - Queue PnL update
- `flush!()` - Flush queue to Redis

**Frequency:**
- Flush interval: 250ms (`FLUSH_INTERVAL_SECONDS`)
- Queue empty: 60 seconds

**Dependencies:**
- RedisPnlCache (for storage)
- PositionTracker (database)

**Queue Population:**
- MarketFeedHub ticks → PositionIndex → `cache_intermediate_pnl()`

---

### 1.6 ReconciliationService

**Class:** `Live::ReconciliationService`  
**File:** `app/services/live/reconciliation_service.rb`  
**Pattern:** Singleton  
**Thread:** `reconciliation-service`

**Responsibilities:**
- Ensure data consistency across:
  - PositionTracker (Database)
  - RedisPnlCache
  - ActiveCache (in-memory)
  - MarketFeedHub subscriptions
- Detect and auto-correct inconsistencies
- Sync missing positions to ActiveCache
- Fix subscription mismatches

**Key Methods:**
- `start()` - Start reconciliation loop
- `stop()` - Stop reconciliation
- `reconcile_all_positions()` - Reconcile all positions

**Frequency:** Every 5 seconds (`RECONCILIATION_INTERVAL`)

**Dependencies:**
- PositionTracker (database)
- ActiveCache
- RedisPnlCache
- MarketFeedHub

---

### 1.7 ExitEngine

**Class:** `Live::ExitEngine`  
**File:** `app/services/live/exit_engine.rb`  
**Pattern:** Instance (created by Supervisor)  
**Thread:** `exit-engine` (idle thread)

**Responsibilities:**
- Execute exit orders when invoked by RiskManagerService
- Place market exit orders via OrderRouter
- Mark PositionTracker as exited
- Handle idempotency (check if already exited)

**Key Methods:**
- `start()` - Start idle thread (for future use)
- `stop()` - Stop thread
- `execute_exit(tracker, reason)` - Execute exit order

**Frequency:** On-demand (called by RiskManagerService)

**Dependencies:**
- OrderRouter (for order placement)
- PositionTracker (database)

**Flow:**
1. Check if tracker already exited → return if true
2. Get current LTP
3. Execute exit order via OrderRouter
4. Mark tracker as exited
5. Log exit

---

### 1.8 PositionHeartbeat

**Class:** `TradingSystem::PositionHeartbeat`  
**File:** `app/services/trading_system/position_heartbeat.rb`  
**Pattern:** Instance (created by Supervisor)  
**Thread:** `position-heartbeat`

**Responsibilities:**
- Monitor position health
- Detect stale positions
- Emit heartbeat events

**Frequency:** Configurable (typically 30 seconds)

**Dependencies:**
- PositionTracker (database)

---

## 2. Integrated Services

Services that are event-driven or called on-demand.

### 2.1 ActiveCache

**Class:** `Positions::ActiveCache`  
**File:** `app/services/positions/active_cache.rb`  
**Pattern:** Singleton  
**Thread:** N/A (event-driven callbacks)

**Responsibilities:**
- Maintain in-memory cache of active positions (PositionData structs)
- Subscribe to MarketFeedHub tick callbacks
- Update position PnL in real-time on tick reception
- Track peak profit percentage
- Track SL/TP offsets
- Persist peak values to Redis (7-day TTL)
- Emit position events (`positions.added`, `positions.removed`)
- Auto-subscribe positions to MarketFeedHub (if enabled)

**Key Methods:**
- `start!()` - Subscribe to MarketFeedHub callbacks, reload peaks
- `stop!()` - Unsubscribe from callbacks
- `add_position(tracker:, sl_price:, tp_price:)` - Add position to cache
- `remove_position(tracker_id:)` - Remove position from cache
- `handle_tick(tick)` - Update position on tick reception
- `get_by_tracker_id(tracker_id)` - Get position by tracker ID
- `all_positions()` - Get all cached positions

**Frequency:** Real-time (on every tick)

**Dependencies:**
- MarketFeedHub (for tick callbacks)
- Redis (for peak persistence)
- TickCache (for LTP lookup)

**Data Structure:**
```ruby
PositionData = Struct.new(
  :tracker_id, :security_id, :segment, :entry_price, :quantity,
  :sl_price, :tp_price, :high_water_mark, :current_ltp, :pnl, :pnl_pct,
  :peak_profit_pct, :sl_offset_pct, :position_direction,
  :underlying_segment, :underlying_security_id, :underlying_trend_score,
  :underlying_ltp, :last_updated_at
)
```

---

### 2.2 EntryManager

**Class:** `Orders::EntryManager`  
**File:** `app/services/orders/entry_manager.rb`  
**Pattern:** Instance (created on-demand)  
**Thread:** N/A (called synchronously)

**Responsibilities:**
- Process entry signals and place orders
- Calculate dynamic risk allocation based on trend score
- Validate entry through EntryGuard
- Add positions to ActiveCache
- Subscribe positions to MarketFeedHub
- Place bracket orders (SL/TP)
- Record trades in DailyLimits
- Emit entry_filled events

**Key Methods:**
- `process_entry(signal_result:, index_cfg:, direction:, scale_multiplier:, trend_score:)` - Main entry processing

**Flow:**
1. Extract pick/candidate from signal
2. Calculate dynamic risk_pct (if trend_score provided)
3. Validate via EntryGuard (places order, creates tracker)
4. Find PositionTracker
5. Calculate SL/TP prices
6. Add to ActiveCache
7. Place bracket orders
8. Record trade in DailyLimits
9. Emit entry_filled event

**Dependencies:**
- EntryGuard (validation and order placement)
- Capital::Allocator (quantity calculation)
- Capital::DynamicRiskAllocator (risk allocation)
- ActiveCache (position tracking)
- MarketFeedHub (subscription)
- BracketPlacer (bracket orders)
- DailyLimits (trade recording)

---

### 2.3 EntryGuard

**Class:** `Entries::EntryGuard`  
**File:** `app/services/entries/entry_guard.rb`  
**Pattern:** Class methods  
**Thread:** N/A (called synchronously)

**Responsibilities:**
- Validate entry conditions before placing orders
- Check trading session timing (9:20 AM - 3:15 PM IST)
- Check daily limits (loss limits, trade limits)
- Check exposure limits (max_same_side positions)
- Check cooldown periods
- Resolve LTP (WebSocket → REST API fallback)
- Calculate quantity via Capital::Allocator
- Place orders (paper or live)
- Create PositionTracker records
- Call EntryManager for post-entry wiring

**Key Methods:**
- `try_enter(index_cfg:, pick:, direction:, scale_multiplier:)` - Main validation and entry

**Validation Checks (in order):**
1. Instrument exists
2. Trading session allowed
3. Daily limits not exceeded
4. Exposure limits not exceeded
5. Cooldown not active
6. LTP valid
7. Quantity valid
8. Segment tradable

**Dependencies:**
- TradingSession::Service (session checks)
- DailyLimits (limit checks)
- Capital::Allocator (quantity calculation)
- Orders::Placer (order placement)
- PositionTracker (database)

---

### 2.4 TrailingEngine

**Class:** `Live::TrailingEngine`  
**File:** `app/services/live/trailing_engine.rb`  
**Pattern:** Instance (created by RiskManagerService)  
**Thread:** N/A (called synchronously)

**Responsibilities:**
- Process trailing stop logic per tick
- Check peak-drawdown exit conditions (with gating)
- Update peak profit percentage
- Apply tiered SL offsets based on profit tiers
- Execute exits via ExitEngine

**Key Methods:**
- `process_tick(position_data, exit_engine:)` - Process trailing for position
- `check_peak_drawdown(position_data, exit_engine:)` - Check peak-drawdown exit
- `update_peak(position_data)` - Update peak profit percentage
- `apply_tiered_sl(position_data, exit_engine:)` - Apply tiered SL offsets

**Dependencies:**
- TrailingConfig (tiered SL rules)
- ExitEngine (exit execution)
- BracketPlacer (SL order updates)

**Peak-Drawdown Logic:**
- Checks if drawdown >= 5% from peak
- Applies activation gating (if enabled):
  - Peak profit >= 25% AND SL offset >= 10%
- Exits if conditions met

---

### 2.5 UnderlyingMonitor

**Class:** `Live::UnderlyingMonitor`  
**File:** `app/services/live/underlying_monitor.rb`  
**Pattern:** Class methods  
**Thread:** N/A (called synchronously)

**Responsibilities:**
- Evaluate underlying index health for positions
- Compute trend score (0-21)
- Check BOS (Break of Structure) state
- Check ATR trend (falling/rising/flat)
- Check multi-timeframe confirmation

**Key Methods:**
- `evaluate(position_data)` - Evaluate underlying health

**Returns:** OpenStruct with:
- `trend_score` - Trend score (0-21)
- `bos_state` - :broken or :intact
- `bos_direction` - :bullish or :bearish
- `atr_trend` - :falling, :rising, or :flat
- `atr_ratio` - Current ATR / Historical ATR
- `mtf_confirm` - Multi-timeframe confirmation

**Dependencies:**
- TickCache (for underlying LTP)
- CandleSeries (for historical data)
- TrendScorer (for trend calculation)

---

### 2.6 PositionSyncService

**Class:** `Live::PositionSyncService`  
**File:** `app/services/live/position_sync_service.rb`  
**Pattern:** Singleton  
**Thread:** N/A (called periodically)

**Responsibilities:**
- Sync positions from DhanHQ to database (live trading)
- Create PositionTracker records for untracked positions
- Mark orphaned live positions as exited
- Ensure paper positions are subscribed to market data

**Key Methods:**
- `sync_positions!()` - Sync all positions
- `force_sync!()` - Force immediate sync

**Frequency:** Every 30 seconds (`@sync_interval`)

**Dependencies:**
- DhanHQ::Models::Position (live positions)
- PositionTracker (database)
- MarketFeedHub (subscription)

---

## 3. Utility Services

Services that provide utility functions without background threads.

### 3.1 Capital::Allocator

**Class:** `Capital::Allocator`  
**File:** `app/services/capital/allocator.rb`  
**Pattern:** Class methods  
**Thread:** N/A

**Responsibilities:**
- Calculate position quantity based on risk percentage
- Get available cash balance
- Determine deployment policy based on balance
- Round quantities to lot size

**Key Methods:**
- `qty_for(index_cfg:, entry_price:, derivative_lot_size:, scale_multiplier:)` - Calculate quantity
- `available_cash()` - Get available cash
- `deployment_policy(balance)` - Get risk policy for balance

---

### 3.2 Capital::DynamicRiskAllocator

**Class:** `Capital::DynamicRiskAllocator`  
**File:** `app/services/capital/dynamic_risk_allocator.rb`  
**Pattern:** Instance  
**Thread:** N/A

**Responsibilities:**
- Calculate dynamic risk percentage based on trend score
- Scale base risk by trend strength (0-21)
- Cap risk at reasonable limits

**Key Methods:**
- `risk_pct_for(index_key:, trend_score:)` - Calculate risk percentage

**Scaling:**
- Low trend (0-7): 0.5x base risk
- Medium trend (7-14): 1.0x base risk
- High trend (14-21): 1.5x base risk

---

### 3.3 OrderRouter

**Class:** `TradingSystem::OrderRouter`  
**File:** `app/services/trading_system/order_router.rb`  
**Pattern:** Instance  
**Thread:** N/A

**Responsibilities:**
- Route exit orders to appropriate gateway (paper/live)
- Place market exit orders
- Handle order placement errors

**Key Methods:**
- `exit_market(tracker)` - Place market exit order

---

### 3.4 BracketPlacer

**Class:** `Orders::BracketPlacer`  
**File:** `app/services/orders/bracket_placer.rb`  
**Pattern:** Instance  
**Thread:** N/A

**Responsibilities:**
- Place/modify bracket orders (SL/TP)
- Update SL orders when trailing stops move
- Handle bracket order errors

**Key Methods:**
- `place_bracket(tracker:, sl_price:, tp_price:, reason:)` - Place bracket orders

---

### 3.5 DailyLimits

**Class:** `Live::DailyLimits`  
**File:** `app/services/live/daily_limits.rb`  
**Pattern:** Instance  
**Thread:** N/A

**Responsibilities:**
- Track daily loss limits per index
- Track daily trade counts per index
- Check if trading is allowed
- Record trades and losses

**Key Methods:**
- `can_trade?(index_key:)` - Check if trading allowed
- `record_trade(index_key:)` - Record trade
- `record_loss(index_key:, amount:)` - Record loss

---

## 4. Service Dependencies

### 4.1 Dependency Graph

```
MarketFeedHub
  ├──→ ActiveCache (callbacks)
  ├──→ TickCache (storage)
  └──→ RedisTickCache (storage)

Signal::Scheduler
  ├──→ TrendScorer
  ├──→ ChainAnalyzer
  ├──→ EntryGuard
  └──→ TradingSession::Service

EntryGuard
  ├──→ TradingSession::Service
  ├──→ DailyLimits
  ├──→ Capital::Allocator
  └──→ Orders::Placer

EntryManager
  ├──→ EntryGuard
  ├──→ Capital::DynamicRiskAllocator
  ├──→ ActiveCache
  ├──→ MarketFeedHub
  └──→ BracketPlacer

RiskManagerService
  ├──→ ActiveCache
  ├──→ RedisPnlCache
  ├──→ UnderlyingMonitor
  ├──→ TrailingEngine
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

PnlUpdaterService
  └──→ RedisPnlCache
```

### 4.2 Startup Dependencies

**Order:**
1. MarketFeedHub (no dependencies)
2. ActiveCache (depends on MarketFeedHub)
3. Signal::Scheduler (no dependencies)
4. RiskManagerService (depends on ExitEngine)
5. ExitEngine (depends on OrderRouter)
6. OrderRouter (no dependencies)
7. PaperPnlRefresher (no dependencies)
8. ReconciliationService (depends on all)

---

## 5. Service Lifecycle

### 5.1 Startup Sequence

```
1. Supervisor creates all service instances
2. Supervisor registers services
3. Supervisor checks market status
4. If market open:
   - Start all services in registration order
   - Subscribe active positions to MarketFeedHub
5. If market closed:
   - Start only MarketFeedHub (WebSocket connection)
```

### 5.2 Shutdown Sequence

```
1. Supervisor receives INT/TERM signal
2. Supervisor stops all services in reverse order
3. Each service:
   - Sets @running = false
   - Kills background thread
   - Cleans up resources
4. Rails application exits
```

### 5.3 Service Health Checks

**MarketFeedHub:**
- Connection state: `connected?`
- Last tick timestamp: `@last_tick_at`
- Health status: `health_status()`

**RiskManagerService:**
- Watchdog thread monitors main thread
- Auto-restarts if thread dies

**All Services:**
- Check `TradingSession::Service.market_closed?`
- Sleep longer when market closed and no positions

---

**Document Version:** 1.0  
**Last Updated:** Based on actual codebase analysis  
**Repository:** https://github.com/shubhamtaywade82/algo_scalper_api/tree/new_trailing
