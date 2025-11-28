# Post-Signal Scheduler Flow: Complete Process Chain

## Overview

After `Signal::Scheduler` generates a signal, the following services and processes handle position management, risk monitoring, and exit execution.

---

## Complete Flow Diagram

```
Signal::Scheduler (generates signal)
    ↓
Entries::EntryGuard.try_enter()
    ├─→ Validates: Market hours, Daily limits, Exposure, Cooldown
    ├─→ Resolves LTP (WebSocket → REST API fallback)
    ├─→ Calculates quantity (Capital::Allocator)
    ├─→ Places order (live) OR creates paper tracker
    └─→ Creates PositionTracker record
        ↓
    post_entry_wiring()
        ├─→ Subscribes to WebSocket feed (MarketFeedHub)
        ├─→ Adds to ActiveCache (Positions::ActiveCache)
        └─→ Places initial bracket orders (SL/TP)
            ↓
    PositionTracker callbacks
        ├─→ after_create_commit :subscribe_to_feed
        └─→ after_commit :register_in_index
            ↓
    ┌─────────────────────────────────────────────────────────┐
    │         ONGOING MONITORING SERVICES (Parallel)          │
    └─────────────────────────────────────────────────────────┘
            ↓
    ┌─────────────────────────────────────────────────────────┐
    │  Live::RiskManagerService (Main Orchestrator)          │
    │  - Runs every 5 seconds (configurable)                  │
    │  - Monitors all active positions                        │
    │  - Processes trailing stops                            │
    │  - Enforces exit conditions                            │
    └─────────────────────────────────────────────────────────┘
            │
            ├─→ Live::PnlUpdaterService (Background)
            │   - Updates PnL in Redis cache (every 0.25s flush)
            │   - Batches updates (max 200 per batch)
            │   - Updates PositionTracker.last_pnl_rupees
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

### 4. **Live::PnlUpdaterService** (Background PnL Updates)

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
3. ✅ Updates `PositionTracker.last_pnl_rupees`
4. ✅ Updates `PositionTracker.high_water_mark_pnl`
5. ✅ Stores in Redis PnL cache

**Data Flow**:
```
MarketFeedHub (WebSocket) 
    → TickCache 
    → PnlUpdaterService.cache_intermediate_pnl()
    → Queue (in-memory)
    → flush!() (every 0.25s)
    → PositionTracker.update!()
    → Redis PnL Cache
```

---

### 5. **Positions::ActiveCache** (In-Memory Position Cache)

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

### 6. **Live::MarketFeedHub** (WebSocket Feed)

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

### 7. **Live::ExitEngine** (Exit Execution)

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
2. **Background**: `Live::PnlUpdaterService` (PnL updates)
3. **Main Loop**: `Live::RiskManagerService` (monitoring & exits)
4. **Per-Tick**: `Live::TrailingEngine` (trailing stops)
5. **Exit**: `Live::ExitEngine` (exit execution)

All services run **in parallel** and work together to manage positions from entry to exit.
