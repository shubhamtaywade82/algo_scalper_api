# Complete Signal Generation Flow: End-to-End Wiring

## ✅ FIXED: No-Trade Engine Now Integrated

**Previous Issue**: `Signal::Scheduler` was calling `analyze_multi_timeframe()` which bypassed No-Trade Engine.

**Fix Applied**: `Signal::Scheduler.process_index()` now calls `Signal::Engine.run_for()` directly, which includes full No-Trade Engine integration.

## Complete System Flow (After Fix)

### 1. System Startup & Initialization

```
TradingSystem::SignalScheduler.start()
  └─> Creates thread: 'signal-scheduler'
      └─> Loop every 1 second
          └─> Signal::Scheduler.new(period: 1)
              └─> process_index(index_cfg) for each index
```

### 2. Signal Generation Flow (WITH No-Trade Engine)

```
Signal::Scheduler.process_index(index_cfg)
  └─> Signal::Engine.run_for(index_cfg) ← ✅ Full flow with No-Trade Engine
      │
      ├─> [PHASE 1] Quick No-Trade Pre-Check ← ✅
      │   ├─> Time windows check
      │   ├─> Fetch bars_1m
      │   ├─> Basic structure (volatility, range)
      │   ├─> Fetch option chain
      │   ├─> Basic option chain (IV, spread)
      │   └─> Return: {allowed, option_chain_data, bars_1m}
      │
      ├─> [IF BLOCKED] → EXIT (no signal generation)
      │
      ├─> [IF ALLOWED] Signal Generation
      │   ├─> Strategy recommendation (if enabled)
      │   ├─> Supertrend + ADX calculation
      │   │   ├─> Primary timeframe analysis
      │   │   └─> Confirmation timeframe analysis (if enabled)
      │   ├─> Multi-timeframe direction decision
      │   ├─> Comprehensive validation
      │   └─> Final direction: :bullish or :bearish
      │
      ├─> [IF :avoid] → EXIT
      │
      ├─> Strike Selection
      │   └─> Options::ChainAnalyzer.pick_strikes()
      │       └─> Returns picks (CE for bullish, PE for bearish)
      │
      ├─> [PHASE 2] Detailed No-Trade Validation ← ✅
      │   ├─> Reuse bars_1m from Phase 1
      │   ├─> Fetch bars_5m (for ADX/DI)
      │   ├─> Reuse option_chain_data from Phase 1
      │   ├─> Build full context (ADX, DI, structure, VWAP, etc.)
      │   ├─> NoTradeEngine.validate(ctx)
      │   └─> Return: {allowed, score, reasons}
      │
      ├─> [IF BLOCKED] → EXIT (signal generated but blocked)
      │
      └─> [IF ALLOWED] EntryGuard.try_enter() ← ✅ Protected by No-Trade Engine
          ├─> Trading session check
          ├─> Daily limits check
          ├─> Exposure check
          ├─> Cooldown check
          ├─> LTP resolution
          ├─> Quantity calculation
          ├─> Order placement (live or paper)
          └─> PositionTracker.create! or PositionTracker.build_or_average!
```

### 3. Position Lifecycle (After Entry)

```
PositionTracker.created
  ├─> after_create_commit :subscribe_to_feed
  │   └─> Live::MarketFeedHub.subscribe()
  │       └─> WebSocket subscription for real-time ticks
  │
  ├─> Positions::ActiveCache.instance.add_position()
  │   └─> Tracks position for exit monitoring
  │
  └─> Orders::BracketPlacer.place_bracket()
      └─> Places SL/TP orders (if enabled)
```

### 4. Position Monitoring & Exit

```
Live::RiskManagerService (runs continuously)
  ├─> Monitors all active positions
  ├─> Checks exit conditions:
  │   ├─> Stop loss
  │   ├─> Take profit
  │   ├─> Trailing stop
  │   ├─> Time-based exit
  │   ├─> Underlying exit (if spot moves against)
  │   └─> Circuit breaker rules
  │
  └─> When exit condition met:
      └─> Live::ExitEngine.execute_exit()
          ├─> Orders::OrderRouter.exit_market()
          ├─> PositionTracker.mark_exited!()
          └─> Positions::ActiveCache.remove_position()
```

### 5. PnL Updates

```
Live::PnlUpdaterService (runs continuously)
  ├─> Updates PnL for all active positions
  ├─> Reads from Live::TickCache
  ├─> Calculates PnL
  └─> Updates PositionTracker.last_pnl_rupees
      └─> Stores in Live::RedisPnlCache
```

## Complete Service Chain

### Entry Flow (Signal → Position)
```
1. TradingSystem::SignalScheduler
   └─> Signal::Scheduler
       └─> Signal::Engine.run_for()
           ├─> Phase 1: No-Trade Pre-Check
           ├─> Signal Generation (Supertrend + ADX)
           ├─> Strike Selection
           ├─> Phase 2: No-Trade Validation
           └─> Entries::EntryGuard.try_enter()
               ├─> Capital::Allocator (quantity)
               ├─> Orders::Placer (order placement)
               └─> PositionTracker.create!
                   ├─> Positions::ActiveCache.add_position()
                   ├─> Live::MarketFeedHub.subscribe()
                   └─> Orders::BracketPlacer.place_bracket()
```

### Monitoring Flow (Position → Exit)
```
2. Live::RiskManagerService (continuous)
   └─> Checks Positions::ActiveCache
       └─> Evaluates exit conditions
           └─> Live::ExitEngine.execute_exit()
               └─> Orders::OrderRouter.exit_market()
                   └─> PositionTracker.mark_exited!()
```

### Data Flow (Market Data → Position Updates)
```
3. Live::MarketFeedHub (WebSocket)
   └─> Receives ticks
       ├─> Live::TickCache.store()
       ├─> Live::RedisPnlCache.update()
       └─> Live::PnlUpdaterService.refresh()
           └─> PositionTracker.update!(last_pnl_rupees)
```

## Service Dependencies

### Signal Generation Services
- **TradingSystem::SignalScheduler** → **Signal::Scheduler** → **Signal::Engine**
- **Signal::Engine** depends on:
  - `IndexInstrumentCache` (instrument data)
  - `Options::ChainAnalyzer` (strike selection)
  - `Entries::NoTradeEngine` (validation)
  - `Entries::EntryGuard` (entry)

### Entry Services
- **Entries::EntryGuard** depends on:
  - `Capital::Allocator` (quantity calculation)
  - `Orders::Placer` (order placement)
  - `Live::MarketFeedHub` (for LTP)
  - `TradingSession::Service` (session check)
  - `Live::DailyLimits` (daily limits)

### Monitoring Services
- **Live::RiskManagerService** depends on:
  - `Positions::ActiveCache` (active positions)
  - `Live::ExitEngine` (exit execution)
  - `Live::TickCache` (current prices)

### Exit Services
- **Live::ExitEngine** depends on:
  - `Orders::OrderRouter` (order placement)
  - `PositionTracker` (position updates)

## Data Flow Diagram

```
Market Data (DhanHQ API)
  │
  ├─> IndexInstrumentCache (cached instruments)
  │   └─> Signal::Engine (signal generation)
  │
  ├─> Live::MarketFeedHub (WebSocket ticks)
  │   ├─> Live::TickCache (tick storage)
  │   └─> Live::RedisPnlCache (PnL cache)
  │
  └─> Options::ChainAnalyzer (option chain)
      └─> Signal::Engine (strike selection)
```

## Key Integration Points

### ✅ No-Trade Engine Integration
- **Phase 1**: Runs BEFORE signal generation (fail fast)
- **Phase 2**: Runs AFTER signal generation (full context)
- **Data Reuse**: Option chain and bars_1m cached between phases
- **Entry Protection**: EntryGuard only called if both phases pass

### ✅ Signal Generation Integration
- **Supertrend + ADX**: Generates direction after Phase 1 passes
- **Strike Selection**: Uses direction from signal generation
- **Entry**: Uses direction and picks from previous steps

### ✅ Position Lifecycle Integration
- **Creation**: PositionTracker created by EntryGuard
- **Monitoring**: RiskManagerService monitors via ActiveCache
- **Exit**: ExitEngine executes exits triggered by RiskManagerService
- **PnL Updates**: PnlUpdaterService updates from TickCache

## Verification Checklist

### Signal Generation
- ✅ TradingSystem::SignalScheduler starts correctly
- ✅ Signal::Scheduler calls Signal::Engine.run_for()
- ✅ Phase 1 No-Trade pre-check runs first
- ✅ Signal generation runs after Phase 1 passes
- ✅ Phase 2 No-Trade validation runs after signal generation
- ✅ EntryGuard only called if both phases pass

### Data Flow
- ✅ Option chain fetched once (Phase 1), reused in Phase 2
- ✅ bars_1m fetched once (Phase 1), reused in Phase 2
- ✅ bars_5m fetched in Phase 2 (needed for ADX/DI)
- ✅ Direction flows: Signal → Strike Selection → Phase 2 → EntryGuard

### Position Management
- ✅ PositionTracker created on entry
- ✅ ActiveCache updated on entry
- ✅ MarketFeedHub subscription on entry
- ✅ RiskManagerService monitors positions
- ✅ ExitEngine executes exits
- ✅ PositionTracker marked exited on exit

## Summary

**Status**: ✅ **FULLY WIRED AND INTEGRATED**

The complete flow is now:
1. ✅ Scheduler starts → Signal::Engine.run_for()
2. ✅ Phase 1 pre-check → Blocks bad conditions early
3. ✅ Signal generation → Supertrend + ADX determines direction
4. ✅ Strike selection → Uses direction from signal
5. ✅ Phase 2 validation → Full context validation
6. ✅ EntryGuard → Protected entry
7. ✅ PositionTracker → Position created
8. ✅ RiskManagerService → Monitors position
9. ✅ ExitEngine → Executes exits

**No-Trade Engine is now fully integrated into the complete signal generation flow!**
