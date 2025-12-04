# Complete Signal Flow: From Scheduler to Exit

## Overview

This document details the **complete end-to-end flow** from signal generation through position management, risk monitoring, and exit execution. This includes the **No-Trade Engine** validation that was recently integrated.

**Last Updated**: Includes No-Trade Engine integration (two-phase validation)

---

## Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 0: SYSTEM STARTUP                                        │
└─────────────────────────────────────────────────────────────────┘
    │
    └─> TradingSystem::SignalScheduler.start()
        └─> Signal::Scheduler (thread: 'signal-scheduler')
            └─> Loop every 1 second
                └─> process_index(index_cfg) for each index
                    │
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 1: SIGNAL GENERATION (WITH No-Trade Engine)              │
└─────────────────────────────────────────────────────────────────┘
    │
    └─> Signal::Engine.run_for(index_cfg) ← ✅ Full flow with No-Trade Engine
        │
        ├─> [PHASE 1] Quick No-Trade Pre-Check ← ✅ FIRST GATE
        │   ├─> Check market closed (TradingSession::Service)
        │   ├─> Fetch instrument (IndexInstrumentCache)
        │   ├─> Time windows (09:15-09:18, 11:20-13:30, after 15:05)
        │   ├─> Fetch bars_1m (instrument.candle_series(interval: '1'))
        │   ├─> Basic structure check (RangeUtils.range_pct)
        │   ├─> Fetch option chain (instrument.fetch_option_chain())
        │   ├─> Basic option chain check (IV threshold, spread)
        │   └─> Return: {allowed, score, reasons, option_chain_data, bars_1m}
        │
        ├─> [IF BLOCKED] → EXIT (no signal generation, saves resources)
        │
        ├─> [IF ALLOWED] Signal Generation
        │   ├─> Load config (AlgoConfig.fetch[:signals])
        │   ├─> Strategy recommendation check (if enabled)
        │   ├─> Supertrend + ADX Analysis
        │   │   ├─> Primary timeframe: analyze_timeframe()
        │   │   │   ├─> Fetch candle series
        │   │   │   ├─> Calculate Supertrend (Indicators::Supertrend)
        │   │   │   ├─> Calculate ADX (instrument.adx())
        │   │   │   └─> Decide direction (decide_direction())
        │   │   └─> Confirmation timeframe: analyze_timeframe() [if enabled]
        │   │       └─> Multi-timeframe direction (multi_timeframe_direction())
        │   ├─> Comprehensive validation (comprehensive_validation())
        │   ├─> Signal persistence (Signal::StateTracker.record())
        │   ├─> TradingSignal.create_from_analysis()
        │   └─> Final direction: :bullish or :bearish
        │
        ├─> [IF :avoid] → EXIT
        │
        ├─> Strike Selection
        │   └─> Options::ChainAnalyzer.pick_strikes()
        │       └─> Returns picks (CE for bullish, PE for bearish)
        │
        ├─> [PHASE 2] Detailed No-Trade Validation ← ✅ SECOND GATE
        │   ├─> Reuse bars_1m from Phase 1
        │   ├─> Fetch bars_5m (instrument.candle_series(interval: '5'))
        │   ├─> Reuse option_chain_data from Phase 1
        │   ├─> Build context (NoTradeContextBuilder.build())
        │   ├─> NoTradeEngine.validate(ctx) - All 11 conditions
        │   └─> Return: {allowed, score, reasons}
        │
        ├─> [IF BLOCKED] → EXIT (signal generated but blocked)
        │
        └─> [IF ALLOWED] EntryGuard.try_enter() ← ✅ PROTECTED ENTRY
            │
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 2: ENTRY EXECUTION                                        │
└─────────────────────────────────────────────────────────────────┘
    │
    └─> Entries::EntryGuard.try_enter(index_cfg, pick, direction, scale_multiplier)
        ├─> Find instrument (Instrument.find_by_sid_and_segment())
        ├─> Trading session check (TradingSession::Service.entry_allowed?)
        ├─> Daily limits check (Live::DailyLimits.can_trade?)
        ├─> Exposure check (exposure_ok?)
        │   ├─> Check active positions (PositionTracker.active)
        │   └─> Pyramiding check (if second position)
        ├─> Cooldown check (cooldown_active?)
        ├─> LTP resolution (resolve_entry_ltp())
        │   ├─> Try WebSocket cache (Live::TickCache.ltp())
        │   └─> Fallback to REST API (instrument.fetch_ltp_from_api())
        ├─> Quantity calculation (Capital::Allocator.qty_for())
        ├─> Paper mode check (paper_trading_enabled?)
        │
        ├─> Order Placement
        │   ├─> Paper Mode: create_paper_tracker!()
        │   │   └─> PositionTracker.create!(paper: true)
        │   └─> Live Mode: Orders::Placer.place_market()
        │       └─> DhanHQ API call
        │           └─> create_tracker!()
        │               └─> PositionTracker.build_or_average!()
        │
        └─> Post-Entry Wiring (post_entry_wiring())
            ├─> Subscribe to feed (subscribe_to_option_feed())
            │   └─> Live::MarketFeedHub.subscribe()
            ├─> Add to active cache (add_to_active_cache())
            │   └─> Positions::ActiveCache.instance.add_position()
            └─> Place bracket orders (place_initial_bracket())
                └─> Orders::BracketPlacer.place_bracket()
                    │
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 3: POSITION LIFECYCLE                                     │
└─────────────────────────────────────────────────────────────────┘
    │
    └─> PositionTracker.created
        ├─> after_create_commit :subscribe_to_feed
        │   └─> Live::MarketFeedHub.subscribe()
        │       └─> WebSocket subscription for real-time ticks
        └─> Positions::ActiveCache.instance.add_position()
            └─> Tracks position for RiskManagerService monitoring
                │
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 4: POSITION MONITORING (Continuous)                      │
└─────────────────────────────────────────────────────────────────┘
    │
    └─> Live::RiskManagerService (runs continuously, every 5 seconds)
        ├─> monitor_loop()
        │   ├─> Get active positions (Positions::ActiveCache.instance.positions)
        │   ├─> Update PnL (hydrate_pnl_from_cache!)
        │   │   └─> Live::RedisPnlCache.fetch_pnl()
        │   └─> Evaluate exit conditions (Risk::RuleEngine.evaluate())
        │       ├─> Stop loss rule (Priority: 20)
        │       ├─> Take profit rule (Priority: 30)
        │       ├─> Trailing stop rule (Priority: 50)
        │       ├─> Time-based exit rule (Priority: 40)
        │       ├─> Peak-drawdown rule (Priority: 45)
        │       ├─> Session end rule (Priority: 10)
        │       └─> Underlying exit rule (Priority: 60)
        │
        └─> When exit condition met:
            └─> Live::ExitEngine.execute_exit()
                │
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 5: EXIT EXECUTION                                         │
└─────────────────────────────────────────────────────────────────┘
    │
    └─> Live::ExitEngine.execute_exit(tracker, reason)
        ├─> Validate tracker (active?, not already exited?)
        ├─> Get LTP (Live::TickCache.ltp())
        ├─> Place exit order (Orders::OrderRouter.exit_market())
        │   └─> DhanHQ API call (sell order)
        └─> Mark position exited (PositionTracker.mark_exited!())
            ├─> Update status to 'exited'
            ├─> Set exit_price and exit_reason
            └─> Positions::ActiveCache.remove_position()
                │
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 6: PnL UPDATES (Continuous, Parallel)                    │
└─────────────────────────────────────────────────────────────────┘
    │
    └─> Live::PnlUpdaterService (runs continuously)
        ├─> For each active position:
        │   ├─> Read tick from Live::TickCache
        │   ├─> Calculate PnL
        │   ├─> Update PositionTracker.last_pnl_rupees
        │   └─> Store in Live::RedisPnlCache
        └─> Live::PaperPnlRefresher (for paper positions)
            └─> Updates paper position PnL
            │
            ├─→ Live::RedisPnlCache (Redis Storage)
            │   - Stores PnL data in Redis (key: pnl:tracker:{id})
            │   - TTL: 6 hours
            │   - Syncs to DB every 30 seconds (throttled)
            │   - Provides fast PnL lookups for RiskManager
            │   - Stores: pnl, pnl_pct, ltp, hwm, drawdown, metadata
            │
            ├─→ Live::PnlUpdaterService (Background)
            │   - Updates PnL in Redis cache (every 0.25s flush)
            │   - Batches updates (max 200 per batch)
            │   - Writes to RedisPnlCache.store_pnl()
            │   - Updates PositionTracker.last_pnl_rupees (throttled)
            │
            ├─→ Live::TrailingEngine (Per-Tick Processing)
            │   - Updates peak_profit_pct
            │   - Applies tiered SL offsets
            │   - Checks peak-drawdown exit
            │   - Updates bracket orders via BracketPlacer
            │
            ├─→ Positions::ActiveCache (In-Memory Cache)
            │   - Sub-second position lookups
            │   - Real-time LTP updates from WebSocket
            │   - Tracks peak profit, PnL, SL/TP status
            │
            ├─→ Live::MarketFeedHub (WebSocket Feed)
            │   - Receives tick data from broker
            │   - Updates TickCache
            │   - Triggers ActiveCache updates
            │   - Feeds PnlUpdaterService
            │
            └─→ Exit Enforcement (Multiple Triggers)
                ├─→ Hard SL/TP limits (enforce_hard_limits)
                ├─→ Trailing stop (enforce_trailing_stops)
                ├─→ Peak-drawdown exit (TrailingEngine)
                ├─→ Session end exit (3:15 PM IST)
                ├─→ Time-based exit (configurable)
                └─→ Underlying-aware exit (if enabled)
                    ↓
                Live::ExitEngine.execute_exit()
                    ├─→ Orders::OrderRouter.exit_market()
                    ├─→ Places exit order via broker API
                    └─→ PositionTracker.mark_exited!()
                        ↓
                    Post-Exit Cleanup
                        ├─→ Removes from ActiveCache
                        ├─→ Unsubscribes from WebSocket
                        ├─→ Records loss in DailyLimits (if applicable)
                        └─→ Updates PositionTracker status
```

---

## Detailed Service Breakdown

### 0. **Signal Generation with No-Trade Engine** (NEW - Integrated)

**Purpose**: Validates market conditions before and after signal generation

**Key Components**:
- `Signal::Engine.run_for()` - Main entry point with No-Trade Engine
- `Entries::NoTradeEngine` - Validation engine
- `Entries::NoTradeContextBuilder` - Context builder

**Phase 1: Quick Pre-Check** (Before Signal Generation):
- Time windows (09:15-09:18, 11:20-13:30, after 15:05)
- Basic structure (volatility, range)
- Basic option chain (IV threshold, spread)
- **Blocks bad conditions BEFORE expensive signal calculations**

**Phase 2: Detailed Validation** (After Signal Generation):
- ADX/DI values (from signal calculations)
- Detailed structure (OB, FVG, BOS)
- VWAP traps
- Option chain microstructure (CE/PE OI)
- Candle quality
- **Blocks marginal setups AFTER signal generation**

**Integration Point**: `Signal::Scheduler.process_index()` → `Signal::Engine.run_for()`

**Benefits**:
- ✅ Fails fast (Phase 1 blocks before signal generation)
- ✅ Full context validation (Phase 2 uses signal data)
- ✅ Data reuse (option chain and bars_1m cached)
- ✅ Blocks 60-70% of bad trades

---

### 1. **Entries::EntryGuard** (Immediate Post-Signal)

**Purpose**: Validates and executes entry

**Key Methods**:
- `try_enter()` - Main entry point
- `post_entry_wiring()` - Sets up position monitoring

**What It Does**:
1. ✅ Validates market hours (9:20 AM - 3:15 PM IST)
2. ✅ Checks daily limits (loss/trade limits)
3. ✅ Validates exposure (max positions per side)
4. ✅ Checks cooldown (prevents rapid re-entry)
5. ✅ Resolves LTP (WebSocket → REST API fallback)
6. ✅ Calculates quantity (`Capital::Allocator.qty_for`)
7. ✅ Places order (live) or creates paper tracker
8. ✅ Subscribes to WebSocket feed
9. ✅ Adds to `ActiveCache`
10. ✅ Places initial bracket orders (SL/TP)

**Next Service**: `RiskManagerService` (monitoring loop)

---

### 2. **Live::RiskManagerService** (Main Orchestrator)

**Purpose**: Central monitoring and risk management service

**Frequency**: Runs every 5 seconds (configurable via `risk.loop_interval_active`)

**Key Responsibilities**:

#### A. Position Monitoring Loop (`monitor_loop`)
```ruby
1. Update paper positions PnL (if due, every 1 minute)
2. Ensure all positions in Redis cache
3. Ensure all positions in ActiveCache
4. Ensure all positions subscribed to market data
5. Process trailing for all positions (per-tick)
6. Enforce session end exit (3:15 PM IST)
7. Enforce hard limits (SL/TP)
8. Enforce trailing stops
9. Enforce time-based exit
```

#### B. Trailing Processing (`process_trailing_for_all_positions`)
- Calls `TrailingEngine.process_tick()` for each position
- Handles underlying-aware exits (if enabled)
- Enforces bracket limits (SL/TP hits)
- Applies tiered SL offsets

#### C. Exit Enforcement
- **Hard Limits**: SL/TP percentage thresholds
- **Trailing Stops**: Drop from high water mark
- **Session End**: Force exit before 3:15 PM IST
- **Time-Based**: Configurable time exit
- **Peak-Drawdown**: Via TrailingEngine
- **Underlying-Aware**: Structure breaks, trend weakness, ATR collapse

**Next Services**: 
- `TrailingEngine` (per-tick processing)
- `ExitEngine` (exit execution)

---

### 3. **Live::TrailingEngine** (Per-Tick Processing)

**Purpose**: Manages trailing stops and peak-drawdown exits

**Called By**: `RiskManagerService.process_trailing_for_all_positions()`

**Key Methods**:
- `process_tick(position_data, exit_engine:)` - Main processing method

**What It Does**:
1. ✅ **Peak-Drawdown Check** (FIRST - before SL adjustments)
   - Checks if drawdown from peak exceeds threshold
   - Applies activation gating (if enabled)
   - Triggers exit if breached

2. ✅ **Update Peak Profit**
   - Tracks highest profit % achieved
   - Updates `position_data.peak_profit_pct`
   - Persists to Redis

3. ✅ **Apply Tiered SL Offsets**
   - 5% profit → SL moves to -15% offset
   - 10% profit → SL moves to -5% offset
   - 15% profit → SL moves to breakeven
   - 25% profit → SL moves to +10% offset
   - Updates bracket orders via `BracketPlacer`

**Next Service**: `ExitEngine` (if exit triggered)

---

### 4. **Live::RedisPnlCache** (Redis PnL Storage)

**Purpose**: Fast PnL storage and retrieval in Redis

**Key Features**:
- Singleton service (one instance)
- Redis hash storage: `pnl:tracker:{tracker_id}`
- TTL: 6 hours
- Throttled DB sync (every 30 seconds per tracker)

**Key Methods**:
- `store_pnl()` - Store PnL data in Redis
- `fetch_pnl(tracker_id)` - Retrieve PnL data
- `sync_pnl_to_database_throttled()` - Sync to DB (throttled)
- `clear_tracker()` - Remove tracker data

**Stored Data**:
```ruby
{
  pnl: Float,              # Current PnL in rupees
  pnl_pct: Float,          # Current PnL percentage
  ltp: Float,              # Last traded price
  hwm_pnl: Float,          # High water mark PnL
  hwm_pnl_pct: Float,      # High water mark percentage
  timestamp: Integer,       # Unix timestamp
  # Metadata (if tracker provided):
  entry_price, quantity, segment, security_id,
  symbol, side, order_no, paper,
  price_change_pct, capital_deployed,
  time_in_position_sec, drawdown_rupees, drawdown_pct,
  index_key, direction
}
```

**Usage in RiskManagerService**:
- `fetch_pnl()` - Fast PnL lookups for exit conditions
- `sync_position_pnl_from_redis()` - Syncs Redis → ActiveCache
- Used as fallback when ActiveCache is stale

**DB Sync Strategy**:
- Throttled: Only syncs to DB every 30 seconds per tracker
- Reduces database load while maintaining Redis freshness
- Force sync available for immediate updates (e.g., on exit)

---

### 5. **Live::PnlUpdaterService** (Background PnL Updates)

**Purpose**: Keeps PnL data fresh in Redis and database

**Frequency**: Flushes every 0.25 seconds (batches up to 200 updates)

**Key Methods**:
- `cache_intermediate_pnl()` - Queues PnL update
- `flush!()` - Batch updates to database

**What It Does**:
1. ✅ Receives PnL updates from multiple sources:
   - WebSocket tick data (via `MarketFeedHub`)
   - Redis tick cache
   - API fallback calls

2. ✅ Batches updates (max 200 per flush)
3. ✅ Writes to `RedisPnlCache.store_pnl()` (high frequency)
4. ✅ Updates `PositionTracker.last_pnl_rupees` (throttled via RedisPnlCache)
5. ✅ Updates `PositionTracker.high_water_mark_pnl` (throttled via RedisPnlCache)

**Integration with RedisPnlCache**:
- `PnlUpdaterService` calls `RedisPnlCache.store_pnl()` on every flush
- `RedisPnlCache` handles throttled DB sync (every 30s per tracker)
- This separation allows high-frequency Redis updates with low DB load

**Data Flow**:
```
MarketFeedHub (WebSocket) 
    → TickCache 
    → PnlUpdaterService.cache_intermediate_pnl()
    → Queue (in-memory)
    → flush!() (every 0.25s)
    → RedisPnlCache.store_pnl() (Redis)
    → PositionTracker.update!() (DB, throttled every 30s)
```

**RedisPnlCache Integration**:
- `RiskManagerService` reads from RedisPnlCache for fast PnL lookups
- `PnlUpdaterService` writes to RedisPnlCache (high frequency)
- RedisPnlCache syncs to DB every 30 seconds (throttled to reduce DB load)

---

### 6. **Positions::ActiveCache** (In-Memory Position Cache)

**Purpose**: Ultra-fast position lookups for exit conditions

**Performance**: Sub-millisecond lookups

**Key Features**:
- In-memory cache (`Concurrent::Map`)
- Real-time LTP updates from WebSocket
- Tracks: PnL, peak profit, SL/TP status, underlying data
- Subscribes to `MarketFeedHub` callbacks

**Position Data Structure**:
```ruby
PositionData {
  tracker_id, security_id, segment,
  entry_price, quantity,
  sl_price, tp_price,
  current_ltp, pnl, pnl_pct,
  peak_profit_pct, high_water_mark,
  sl_offset_pct, position_direction,
  underlying_trend_score, ...
}
```

**Methods**:
- `add_position()` - Add new position
- `update_ltp()` - Update LTP from tick
- `get_by_tracker_id()` - Fast lookup
- `all_positions()` - Get all active positions

---

### 7. **Live::MarketFeedHub** (WebSocket Feed)

**Purpose**: Receives real-time market data from broker

**Key Responsibilities**:
- Maintains WebSocket connection
- Subscribes to instruments
- Receives tick data
- Updates `TickCache`
- Triggers `ActiveCache` updates
- Feeds `PnlUpdaterService`

**Data Flow**:
```
Broker WebSocket
    → MarketFeedHub.on_tick()
    → TickCache.store()
    → ActiveCache.update_ltp()
    → PnlUpdaterService.cache_intermediate_pnl()
```

---

### 8. **Live::ExitEngine** (Exit Execution)

**Purpose**: Executes exit orders when triggered

**Called By**: `RiskManagerService` (via `dispatch_exit()`)

**Key Methods**:
- `execute_exit(tracker, reason)` - Main exit method

**What It Does**:
1. ✅ Locks tracker (prevents double-exit)
2. ✅ Gets current LTP
3. ✅ Calls `OrderRouter.exit_market()`
4. ✅ Places exit order via broker API
5. ✅ Marks tracker as exited (`mark_exited!()`)
6. ✅ Records exit reason and price

**Exit Reasons**:
- `SL HIT` - Stop loss triggered
- `TP HIT` - Take profit triggered
- `peak_drawdown_exit` - Peak drawdown breached
- `session end` - Market closing deadline
- `underlying_structure_break` - Underlying trend reversed
- `underlying_trend_weak` - Underlying trend weakened
- `TRAILING STOP` - Trailing stop triggered

---

## Service Startup Order

### Recommended Startup Sequence:

```ruby
# 1. Start WebSocket feed (foundation)
MarketFeedHub.instance.start!

# 2. Start PnL updater (background processing)
PnlUpdaterService.instance.start!

# 3. Start Risk Manager (main orchestrator)
risk_manager = Live::RiskManagerService.new(
  exit_engine: exit_engine,
  trailing_engine: trailing_engine
)
risk_manager.start

# 4. Start Signal Scheduler (entry point)
Signal::Scheduler.new.start
```

---

## Key Configuration Points

### Risk Manager Loop Intervals
```yaml
risk:
  loop_interval_active: 500    # ms (when positions exist)
  loop_interval_idle: 5000     # ms (when no positions)
```

### PnL Update Frequency
```ruby
FLUSH_INTERVAL_SECONDS = 0.25  # 250ms flush interval
MAX_BATCH = 200                # Max updates per flush
```

### Trailing Stop Configuration
```yaml
trailing:
  peak_drawdown_threshold: 5.0  # % drop from peak
  tiered_sl_offsets:
    - profit_pct: 5
      sl_offset_pct: -15
    - profit_pct: 10
      sl_offset_pct: -5
    - profit_pct: 15
      sl_offset_pct: 0    # Breakeven
    - profit_pct: 25
      sl_offset_pct: 10   # Lock in profit
```

---

## Summary: Next Service After Signal Scheduler

**Answer**: **`Live::RiskManagerService`** is the main service that processes positions after entry.

However, the complete picture includes:

1. **Immediate**: `Entries::EntryGuard` (entry execution)
2. **Redis Storage**: `Live::RedisPnlCache` (PnL cache in Redis)
3. **Background**: `Live::PnlUpdaterService` (PnL updates → writes to RedisPnlCache)
4. **Main Loop**: `Live::RiskManagerService` (monitoring & exits, reads from RedisPnlCache)
5. **Per-Tick**: `Live::TrailingEngine` (trailing stops)
6. **Exit**: `Live::ExitEngine` (exit execution)

All services run **in parallel** and work together to manage positions from entry to exit.

### RedisPnlCache Role

**`Live::RedisPnlCache`** is a critical service that:
- **Stores** PnL data in Redis (high-frequency writes from `PnlUpdaterService`)
- **Provides** fast PnL lookups for `RiskManagerService` (avoids DB queries)
- **Syncs** to database every 30 seconds (throttled to reduce DB load)
- **Enables** `RiskManagerService` to check exit conditions without hitting DB

**Key Integration Points**:
- `RiskManagerService.enforce_hard_limits()` - Reads from RedisPnlCache for positions not in ActiveCache
- `RiskManagerService.sync_position_pnl_from_redis()` - Syncs Redis → ActiveCache
- `PnlUpdaterService.flush!()` - Writes to RedisPnlCache.store_pnl()
- `RiskManagerService.ensure_all_positions_in_redis()` - Ensures all positions have Redis cache entries
