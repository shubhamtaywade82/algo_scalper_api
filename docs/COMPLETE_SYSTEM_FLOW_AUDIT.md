# Complete System Flow Audit: Signal Generation to Exit

## ✅ Status: FULLY WIRED AND INTEGRATED

**Critical Fix Applied**: `Signal::Scheduler` now calls `Signal::Engine.run_for()` which includes full No-Trade Engine integration.

## Complete End-to-End Flow

### Phase 0: System Startup

```
1. TradingSystem::SignalScheduler.start()
   └─> Creates thread: 'signal-scheduler'
       └─> Loop every 1 second
           └─> Signal::Scheduler.new(period: 1)
               └─> process_index(index_cfg) for each configured index
```

**Services Started**:
- ✅ TradingSystem::SignalScheduler
- ✅ Live::MarketFeedHub (WebSocket)
- ✅ Live::RiskManagerService (monitoring)
- ✅ Live::PnlUpdaterService (PnL updates)
- ✅ Live::ExitEngine (exit execution)

### Phase 1: Signal Generation (WITH No-Trade Engine)

```
2. Signal::Scheduler.process_index(index_cfg)
   └─> Signal::Engine.run_for(index_cfg) ← ✅ FIXED: Now uses run_for() with No-Trade Engine
       │
       ├─> [PHASE 1] Quick No-Trade Pre-Check ← ✅ FIRST GATE
       │   ├─> Check market closed (TradingSession::Service)
       │   ├─> Fetch instrument (IndexInstrumentCache)
       │   ├─> Time windows check (09:15-09:18, 11:20-13:30, after 15:05)
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
       │   │   │   ├─> Fetch candle series (instrument.candle_series())
       │   │   │   ├─> Calculate Supertrend (Indicators::Supertrend)
       │   │   │   ├─> Calculate ADX (instrument.adx())
       │   │   │   └─> Decide direction (decide_direction())
       │   │   │
       │   │   └─> Confirmation timeframe: analyze_timeframe() [if enabled]
       │   │       └─> Multi-timeframe direction (multi_timeframe_direction())
       │   │
       │   ├─> Comprehensive validation (comprehensive_validation())
       │   │   ├─> IV Rank check
       │   │   ├─> Theta risk assessment
       │   │   ├─> ADX strength validation
       │   │   └─> Trend confirmation
       │   │
       │   ├─> Signal persistence (Signal::StateTracker.record())
       │   ├─> TradingSignal.create_from_analysis()
       │   └─> Final direction: :bullish or :bearish
       │
       ├─> [IF :avoid] → EXIT
       │
       ├─> Strike Selection
       │   └─> Options::ChainAnalyzer.pick_strikes()
       │       ├─> Get expiry list (instrument.expiry_list)
       │       ├─> Fetch option chain (instrument.fetch_option_chain())
       │       ├─> Filter strikes (IV, OI, spread, delta)
       │       ├─> Score strikes
       │       └─> Return picks (CE for bullish, PE for bearish)
       │
       ├─> [PHASE 2] Detailed No-Trade Validation ← ✅ SECOND GATE
       │   ├─> Reuse bars_1m from Phase 1
       │   ├─> Fetch bars_5m (instrument.candle_series(interval: '5'))
       │   ├─> Reuse option_chain_data from Phase 1
       │   ├─> Build context (NoTradeContextBuilder.build())
       │   │   ├─> ADX/DI values (from bars_5m)
       │   │   ├─> Structure indicators (StructureDetector)
       │   │   ├─> VWAP indicators (VWAPUtils)
       │   │   ├─> Volatility indicators (RangeUtils, ATRUtils)
       │   │   ├─> Option chain indicators (OptionChainWrapper)
       │   │   └─> Candle quality (CandleUtils)
       │   │
       │   ├─> NoTradeEngine.validate(ctx)
       │   │   ├─> Check all 11 conditions
       │   │   ├─> Calculate score
       │   │   └─> Return: {allowed, score, reasons}
       │   │
       │   └─> Return: {allowed, score, reasons}
       │
       ├─> [IF BLOCKED] → EXIT (signal generated but blocked)
       │
       └─> [IF ALLOWED] EntryGuard.try_enter() ← ✅ PROTECTED ENTRY
```

### Phase 2: Entry Execution

```
3. Entries::EntryGuard.try_enter(index_cfg, pick, direction, scale_multiplier)
   ├─> Find instrument (Instrument.find_by_sid_and_segment())
   ├─> Trading session check (TradingSession::Service.entry_allowed?)
   ├─> Daily limits check (Live::DailyLimits.can_trade?)
   ├─> Exposure check (exposure_ok?)
   │   ├─> Check active positions (PositionTracker.active)
   │   └─> Pyramiding check (if second position)
   │
   ├─> Cooldown check (cooldown_active?)
   ├─> LTP resolution (resolve_entry_ltp())
   │   ├─> Try WebSocket cache (Live::TickCache.ltp())
   │   └─> Fallback to REST API (instrument.fetch_ltp_from_api())
   │
   ├─> Quantity calculation (Capital::Allocator.qty_for())
   ├─> Paper mode check (paper_trading_enabled?)
   │
   ├─> Order Placement
   │   ├─> Paper Mode:
   │   │   └─> create_paper_tracker!()
   │   │       └─> PositionTracker.create!(paper: true)
   │   │
   │   └─> Live Mode:
   │       └─> Orders::Placer.place_market()
   │           └─> DhanHQ API call
   │               └─> create_tracker!()
   │                   └─> PositionTracker.build_or_average!()
   │
   └─> Post-Entry Wiring (post_entry_wiring())
       ├─> Subscribe to feed (subscribe_to_option_feed())
       │   └─> Live::MarketFeedHub.subscribe()
       ├─> Add to active cache (add_to_active_cache())
       │   └─> Positions::ActiveCache.instance.add_position()
       └─> Place bracket orders (place_initial_bracket())
           └─> Orders::BracketPlacer.place_bracket()
```

### Phase 3: Position Lifecycle

```
4. PositionTracker.created
   ├─> after_create_commit :subscribe_to_feed
   │   └─> Live::MarketFeedHub.subscribe()
   │       └─> WebSocket subscription for real-time ticks
   │
   └─> Positions::ActiveCache.instance.add_position()
       └─> Tracks position for RiskManagerService monitoring
```

### Phase 4: Position Monitoring

```
5. Live::RiskManagerService (runs continuously, every 5 seconds)
   ├─> monitor_loop()
   │   ├─> Get active positions (Positions::ActiveCache.instance.positions)
   │   ├─> Update PnL (hydrate_pnl_from_cache!)
   │   │   └─> Live::RedisPnlCache.fetch_pnl()
   │   │
   │   └─> Evaluate exit conditions (Risk::RuleEngine.evaluate())
   │       ├─> Stop loss rule
   │       ├─> Take profit rule
   │       ├─> Trailing stop rule
   │       ├─> Time-based exit rule
   │       ├─> Underlying exit rule
   │       └─> Circuit breaker rules
   │
   └─> When exit condition met:
       └─> Live::ExitEngine.execute_exit()
```

### Phase 5: Exit Execution

```
6. Live::ExitEngine.execute_exit(tracker, reason)
   ├─> Validate tracker (active?, not already exited?)
   ├─> Get LTP (Live::TickCache.ltp())
   ├─> Place exit order (Orders::OrderRouter.exit_market())
   │   └─> DhanHQ API call (sell order)
   │
   └─> Mark position exited (PositionTracker.mark_exited!)
       ├─> Update status to 'exited'
       ├─> Set exit_price and exit_reason
       └─> Positions::ActiveCache.remove_position()
```

### Phase 6: PnL Updates (Continuous)

```
7. Live::PnlUpdaterService (runs continuously)
   ├─> For each active position:
   │   ├─> Read tick from Live::TickCache
   │   ├─> Calculate PnL
   │   ├─> Update PositionTracker.last_pnl_rupees
   │   └─> Store in Live::RedisPnlCache
   │
   └─> Live::PaperPnlRefresher (for paper positions)
       └─> Updates paper position PnL
```

## Service Dependencies Graph

```
TradingSystem::SignalScheduler
  └─> Signal::Scheduler
      └─> Signal::Engine.run_for()
          ├─> IndexInstrumentCache
          ├─> Options::ChainAnalyzer
          ├─> Entries::NoTradeEngine
          └─> Entries::EntryGuard
              ├─> Capital::Allocator
              ├─> Orders::Placer
              ├─> TradingSession::Service
              └─> Live::DailyLimits
                  └─> PositionTracker
                      ├─> Positions::ActiveCache
                      ├─> Live::MarketFeedHub
                      └─> Orders::BracketPlacer
                          └─> Live::RiskManagerService
                              ├─> Live::ExitEngine
                              └─> Orders::OrderRouter
                                  └─> PositionTracker.mark_exited!
```

## Data Flow

### Market Data Flow
```
DhanHQ API
  ├─> IndexInstrumentCache (cached instruments)
  │   └─> Signal::Engine (signal generation)
  │
  ├─> Live::MarketFeedHub (WebSocket)
  │   ├─> Live::TickCache (tick storage)
  │   └─> Live::RedisPnlCache (PnL cache)
  │       └─> Live::PnlUpdaterService (PnL updates)
  │
  └─> Options::ChainAnalyzer (option chain)
      └─> Signal::Engine (strike selection)
```

### Position Data Flow
```
PositionTracker
  ├─> Positions::ActiveCache (active positions list)
  │   └─> Live::RiskManagerService (monitoring)
  │
  ├─> Live::TickCache (current prices)
  │   └─> Live::PnlUpdaterService (PnL calculation)
  │
  └─> Live::RedisPnlCache (PnL storage)
      └─> Live::RiskManagerService (exit decisions)
```

## Critical Integration Points

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

### Signal Generation Flow
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

**Status**: ✅ **COMPLETE AND FULLY WIRED**

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

**All services are properly wired and No-Trade Engine is fully integrated!**
