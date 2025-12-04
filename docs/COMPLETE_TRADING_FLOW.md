# Complete Trading Flow: Signal Scheduler to Exit

**Last Updated**: Includes No-Trade Engine integration (two-phase validation)

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Phase-by-Phase Flow](#phase-by-phase-flow)
3. [Service Responsibilities](#service-responsibilities)
4. [Data Flow](#data-flow)
5. [Risk Management Rules](#risk-management-rules)
6. [Exit Execution](#exit-execution)
7. [Configuration](#configuration)

---

## System Overview

The complete trading flow consists of **6 phases**:

1. **System Startup** - Services initialization
2. **Signal Generation** - With No-Trade Engine validation
3. **Entry Execution** - Position creation
4. **Position Lifecycle** - Monitoring setup
5. **Position Monitoring** - Risk management and exit conditions
6. **Exit Execution** - Position closure

---

## Phase-by-Phase Flow

### Phase 0: System Startup

```
TradingSystem::SignalScheduler.start()
  └─> Creates thread: 'signal-scheduler'
      └─> Loop every 1 second
          └─> Signal::Scheduler.new(period: 1)
              └─> process_index(index_cfg) for each configured index
```

**Services Started**:
- ✅ TradingSystem::SignalScheduler
- ✅ Live::MarketFeedHub (WebSocket feed)
- ✅ Live::RiskManagerService (position monitoring)
- ✅ Live::PnlUpdaterService (PnL updates)
- ✅ Live::ExitEngine (exit execution)
- ✅ Live::PaperPnlRefresher (paper position PnL)

---

### Phase 1: Signal Generation (WITH No-Trade Engine)

```
Signal::Scheduler.process_index(index_cfg)
  └─> Signal::Engine.run_for(index_cfg) ← ✅ Full flow with No-Trade Engine
      │
      ├─> [PHASE 1] Quick No-Trade Pre-Check ← ✅ FIRST GATE
      │   ├─> Check market closed (TradingSession::Service.market_closed?)
      │   ├─> Fetch instrument (IndexInstrumentCache.instance.get_or_fetch())
      │   ├─> Time windows check
      │   │   ├─> 09:15-09:18 (avoid first 3 minutes)
      │   │   ├─> 11:20-13:30 (lunch-time theta zone)
      │   │   └─> After 15:05 (theta crush)
      │   ├─> Fetch bars_1m (instrument.candle_series(interval: '1'))
      │   ├─> Basic structure check
      │   │   └─> RangeUtils.range_pct() < 0.1% (low volatility)
      │   ├─> Fetch option chain (instrument.fetch_option_chain())
      │   ├─> Basic option chain check
      │   │   ├─> IV threshold (NIFTY < 10, BANKNIFTY < 13)
      │   │   └─> Spread check (wide bid-ask)
      │   └─> Return: {allowed, score, reasons, option_chain_data, bars_1m}
      │
      ├─> [IF BLOCKED] → EXIT (no signal generation, saves resources)
      │   └─> Log: "NO-TRADE pre-check blocked: score=X/11, reasons=..."
      │
      ├─> [IF ALLOWED] Signal Generation
      │   ├─> Load config (AlgoConfig.fetch[:signals])
      │   ├─> Strategy recommendation (if enabled)
      │   │   └─> StrategyRecommender.best_for_index()
      │   ├─> Supertrend + ADX Analysis
      │   │   ├─> Primary timeframe: analyze_timeframe()
      │   │   │   ├─> Fetch candle series (instrument.candle_series())
      │   │   │   ├─> Calculate Supertrend (Indicators::Supertrend)
      │   │   │   ├─> Calculate ADX (instrument.adx())
      │   │   │   └─> Decide direction (decide_direction())
      │   │   └─> Confirmation timeframe: analyze_timeframe() [if enabled]
      │   │       └─> Multi-timeframe direction (multi_timeframe_direction())
      │   ├─> Comprehensive validation (comprehensive_validation())
      │   │   ├─> IV Rank check
      │   │   ├─> Theta risk assessment
      │   │   ├─> ADX strength validation
      │   │   └─> Trend confirmation
      │   ├─> Signal persistence
      │   │   ├─> Signal::StateTracker.record()
      │   │   └─> TradingSignal.create_from_analysis()
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
      │   ├─> NoTradeEngine.validate(ctx)
      │   │   ├─> Check all 11 conditions:
      │   │   │   ├─> Trend weakness (ADX < 15, DI overlap < 2)
      │   │   │   ├─> Market structure (no BOS, inside OB/FVG)
      │   │   │   ├─> VWAP traps (near VWAP, trapped)
      │   │   │   ├─> Volatility (low range, ATR downtrend)
      │   │   │   ├─> Option chain (both CE/PE OI rising, low IV, wide spread)
      │   │   │   ├─> Candle quality (high wick ratio)
      │   │   │   └─> Time windows (with ADX context)
      │   │   ├─> Calculate score (0-11)
      │   │   └─> Return: {allowed, score, reasons}
      │   └─> Return: {allowed, score, reasons}
      │
      ├─> [IF BLOCKED] → EXIT (signal generated but blocked)
      │   └─> Log: "NO-TRADE detailed validation blocked: score=X/11, reasons=..."
      │
      └─> [IF ALLOWED] EntryGuard.try_enter() ← ✅ PROTECTED ENTRY
```

**Key Points**:
- ✅ Phase 1 blocks bad conditions BEFORE expensive signal calculations
- ✅ Phase 2 validates with full context AFTER signal generation
- ✅ Data is cached and reused between phases (efficient)
- ✅ EntryGuard only called if both phases pass

---

### Phase 2: Entry Execution

```
Entries::EntryGuard.try_enter(index_cfg, pick, direction, scale_multiplier)
  ├─> Find instrument (Instrument.find_by_sid_and_segment())
  ├─> Trading session check (TradingSession::Service.entry_allowed?)
  │   └─> Must be between 9:20 AM - 3:15 PM IST
  ├─> Daily limits check (Live::DailyLimits.can_trade?)
  │   ├─> Check daily loss limit
  │   └─> Check daily trade count limit
  ├─> Exposure check (exposure_ok?)
  │   ├─> Check active positions (PositionTracker.active)
  │   ├─> Check max_same_side limit
  │   └─> Pyramiding check (if second position)
  │       └─> First position must be profitable for 5+ minutes
  ├─> Cooldown check (cooldown_active?)
  │   └─> Prevents rapid re-entry on same symbol
  ├─> LTP resolution (resolve_entry_ltp())
  │   ├─> Try WebSocket cache (Live::TickCache.ltp())
  │   └─> Fallback to REST API (instrument.fetch_ltp_from_api())
  ├─> Quantity calculation (Capital::Allocator.qty_for())
  │   └─> Based on risk per trade and available capital
  ├─> Paper mode check (paper_trading_enabled?)
  │   └─> Auto fallback if insufficient live balance
  │
  ├─> Order Placement
  │   ├─> Paper Mode:
  │   │   └─> create_paper_tracker!()
  │   │       └─> PositionTracker.create!(paper: true)
  │   └─> Live Mode:
  │       └─> Orders::Placer.place_market()
  │           ├─> DhanHQ API call (buy order)
  │           └─> create_tracker!()
  │               └─> PositionTracker.build_or_average!()
  │
  └─> Post-Entry Wiring (post_entry_wiring())
      ├─> Subscribe to feed (subscribe_to_option_feed())
      │   └─> Live::MarketFeedHub.subscribe()
      │       └─> WebSocket subscription for real-time ticks
      ├─> Add to active cache (add_to_active_cache())
      │   └─> Positions::ActiveCache.instance.add_position()
      │       └─> Tracks position for RiskManagerService monitoring
      └─> Place bracket orders (place_initial_bracket())
          └─> Orders::BracketPlacer.place_bracket()
              ├─> Calculate SL/TP prices
              └─> Place SL/TP orders (if enabled)
```

**Key Points**:
- ✅ Multiple validation layers before entry
- ✅ Automatic paper mode fallback if insufficient balance
- ✅ WebSocket subscription for real-time data
- ✅ ActiveCache registration for monitoring

---

### Phase 3: Position Lifecycle

```
PositionTracker.created
  ├─> after_create_commit :subscribe_to_feed
  │   └─> Live::MarketFeedHub.subscribe()
  │       └─> WebSocket subscription for real-time ticks
  │
  ├─> Positions::ActiveCache.instance.add_position()
  │   └─> Tracks position for RiskManagerService monitoring
  │       └─> Stores: entry_price, quantity, sl_price, tp_price, etc.
  │
  └─> Orders::BracketPlacer.place_bracket()
      └─> Places SL/TP orders (if enabled)
```

**Key Points**:
- ✅ Automatic WebSocket subscription on creation
- ✅ Position tracked in ActiveCache immediately
- ✅ Bracket orders placed automatically

---

### Phase 4: Position Monitoring

```
Live::RiskManagerService (runs continuously, every 5 seconds)
  ├─> monitor_loop()
  │   ├─> Update paper positions PnL (if due, every 1 minute)
  │   ├─> Ensure all positions in Redis cache
  │   │   └─> Live::RedisPnlCache.store_pnl() (if missing)
  │   ├─> Ensure all positions in ActiveCache
  │   │   └─> Positions::ActiveCache.add_position() (if missing)
  │   ├─> Ensure all positions subscribed to market data
  │   │   └─> Live::MarketFeedHub.subscribe() (if not subscribed)
  │   │
  │   ├─> Process trailing for all positions (process_trailing_for_all_positions)
  │   │   └─> Live::TrailingEngine.process_tick()
  │   │       ├─> Update peak profit
  │   │       ├─> Apply tiered SL offsets
  │   │       └─> Check peak-drawdown exit
  │   │
  │   └─> Evaluate exit conditions (Risk::RuleEngine.evaluate())
  │       ├─> Priority 10: SessionEndRule (3:15 PM IST)
  │       ├─> Priority 20: StopLossRule (hard SL)
  │       ├─> Priority 25: BracketLimitRule (SL/TP hit)
  │       ├─> Priority 30: TakeProfitRule (hard TP)
  │       ├─> Priority 35: SecureProfitRule (profit ≥ ₹1000, drawdown ≥ 3%)
  │       ├─> Priority 40: TimeBasedExitRule (time-based exit)
  │       ├─> Priority 45: PeakDrawdownRule (trailing stop)
  │       ├─> Priority 50: TrailingStopRule (legacy trailing)
  │       └─> Priority 60: UnderlyingExitRule (BOS break, trend weak, ATR collapse)
  │
  └─> When exit condition met:
      └─> Live::ExitEngine.execute_exit()
```

**Key Points**:
- ✅ Continuous monitoring every 5 seconds
- ✅ Priority-based rule evaluation (first match wins)
- ✅ Real-time PnL updates from Redis cache
- ✅ Trailing stops processed per-tick

---

### Phase 5: Exit Execution

```
Live::ExitEngine.execute_exit(tracker, reason)
  ├─> Validate tracker (active?, not already exited?)
  ├─> Lock tracker (prevents double-exit)
  ├─> Get LTP (Live::TickCache.ltp())
  ├─> Place exit order (Orders::OrderRouter.exit_market())
  │   └─> DhanHQ API call (sell order)
  │
  └─> Mark position exited (PositionTracker.mark_exited!)
      ├─> Update status to 'exited'
      ├─> Set exit_price and exit_reason
      ├─> Positions::ActiveCache.remove_position()
      ├─> Live::MarketFeedHub.unsubscribe()
      └─> Live::RedisPnlCache.clear_tracker()
```

**Exit Reasons**:
- `SL HIT` - Stop loss triggered
- `TP HIT` - Take profit triggered
- `peak_drawdown_exit` - Peak drawdown breached
- `session end` - Market closing deadline (3:15 PM IST)
- `underlying_structure_break` - Underlying trend reversed
- `underlying_trend_weak` - Underlying trend weakened
- `underlying_atr_collapse` - Volatility collapsed
- `TRAILING STOP` - Trailing stop triggered
- `time-based exit` - Time-based exit triggered
- `secure_profit_exit` - Secure profit rule triggered

---

### Phase 6: PnL Updates (Continuous, Parallel)

```
Live::PnlUpdaterService (runs continuously)
  ├─> Flush every 0.25 seconds (FLUSH_INTERVAL_SECONDS)
  ├─> Batch up to 200 updates per flush (MAX_BATCH)
  ├─> For each active position:
  │   ├─> Read tick from Live::TickCache
  │   ├─> Calculate PnL
  │   ├─> Update PositionTracker.last_pnl_rupees (throttled)
  │   └─> Store in Live::RedisPnlCache.store_pnl()
  │
  └─> Live::PaperPnlRefresher (for paper positions)
      └─> Updates paper position PnL every 1 second
```

**Data Flow**:
```
MarketFeedHub (WebSocket)
  └─> TickCache.store()
      └─> PnlUpdaterService.cache_intermediate_pnl()
          └─> Queue (in-memory)
              └─> flush!() (every 0.25s)
                  └─> RedisPnlCache.store_pnl() (Redis)
                      └─> PositionTracker.update!() (DB, throttled every 30s)
```

---

## Service Responsibilities

### Signal Generation Services

| Service | Responsibility | Frequency |
|---------|--------------|-----------|
| **TradingSystem::SignalScheduler** | Wrapper service, starts Signal::Scheduler | On startup |
| **Signal::Scheduler** | Main scheduler loop | Every 1 second |
| **Signal::Engine** | Signal generation with No-Trade Engine | Per index, per cycle |
| **Entries::NoTradeEngine** | Two-phase validation | Before/after signal generation |
| **Options::ChainAnalyzer** | Strike selection | After signal generation |

### Entry Services

| Service | Responsibility | Frequency |
|---------|--------------|-----------|
| **Entries::EntryGuard** | Entry validation and execution | Per signal |
| **Capital::Allocator** | Quantity calculation | Per entry |
| **Orders::Placer** | Order placement | Per entry |
| **Orders::BracketPlacer** | Bracket order placement | Per entry |

### Monitoring Services

| Service | Responsibility | Frequency |
|---------|--------------|-----------|
| **Live::RiskManagerService** | Main orchestrator, exit condition evaluation | Every 5 seconds |
| **Live::TrailingEngine** | Trailing stop processing | Per-tick (via RiskManager) |
| **Live::PnlUpdaterService** | PnL updates to Redis | Every 0.25 seconds |
| **Live::PaperPnlRefresher** | Paper position PnL | Every 1 second |
| **Live::ReconciliationService** | Data consistency checks | Every 5 seconds |

### Exit Services

| Service | Responsibility | Frequency |
|---------|--------------|-----------|
| **Live::ExitEngine** | Exit order execution | On exit condition |
| **Orders::OrderRouter** | Exit order placement | On exit condition |

### Data Services

| Service | Responsibility | Frequency |
|---------|--------------|-----------|
| **Live::MarketFeedHub** | WebSocket feed management | Continuous |
| **Live::TickCache** | In-memory tick storage | Real-time |
| **Live::RedisPnlCache** | Redis PnL storage | Real-time |
| **Positions::ActiveCache** | In-memory position cache | Real-time |

---

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
PositionTracker (Database)
  ├─> Positions::ActiveCache (in-memory cache)
  │   └─> Live::RiskManagerService (monitoring)
  │
  ├─> Live::TickCache (current prices)
  │   └─> Live::PnlUpdaterService (PnL calculation)
  │
  └─> Live::RedisPnlCache (PnL storage)
      └─> Live::RiskManagerService (exit decisions)
```

---

## Risk Management Rules

### Rule Priority Order

Rules are evaluated in priority order (lower number = higher priority):

1. **SessionEndRule** (Priority: 10) - Forces exit at 3:15 PM IST
2. **StopLossRule** (Priority: 20) - Hard stop loss
3. **BracketLimitRule** (Priority: 25) - SL/TP bracket hits
4. **TakeProfitRule** (Priority: 30) - Hard take profit
5. **SecureProfitRule** (Priority: 35) - Secure profit above threshold
6. **TimeBasedExitRule** (Priority: 40) - Time-based exit
7. **PeakDrawdownRule** (Priority: 45) - Trailing stop (peak drawdown)
8. **TrailingStopRule** (Priority: 50) - Legacy trailing stop
9. **UnderlyingExitRule** (Priority: 60) - Market structure checks

### Rule Evaluation Logic

- **First-match-wins**: First rule that triggers exit wins, evaluation stops
- **Fail-safe**: Rule errors are caught, evaluation continues
- **Skip on missing data**: Rules skip if required data unavailable
- **Live data required**: Rules use real-time data (WebSocket, Redis)

---

## Exit Execution

### Exit Flow

```
RiskManagerService.monitor_loop()
  └─> Risk::RuleEngine.evaluate()
      └─> Rule triggers exit
          └─> Live::ExitEngine.execute_exit()
              ├─> Orders::OrderRouter.exit_market()
              ├─> PositionTracker.mark_exited!()
              └─> Cleanup (ActiveCache, WebSocket, Redis)
```

### Exit Reasons

| Reason | Trigger Condition | Priority |
|--------|------------------|----------|
| `session end` | Time >= 3:15 PM IST | 10 |
| `SL HIT` | PnL <= -SL% | 20 |
| `TP HIT` | PnL >= TP% | 30 |
| `peak_drawdown_exit` | Drawdown from peak >= threshold | 45 |
| `underlying_structure_break` | BOS break against position | 60 |
| `underlying_trend_weak` | Underlying trend weakened | 60 |
| `underlying_atr_collapse` | ATR collapsed | 60 |
| `TRAILING STOP` | Trailing stop triggered | 50 |
| `time-based exit` | Time >= exit_time & profit >= min | 40 |
| `secure_profit_exit` | Profit >= ₹1000 & drawdown >= 3% | 35 |

---

## No-Trade Engine Timeframes

The No-Trade Engine uses **two timeframes**:

1. **1-minute (1m)** - Used for:
   - Structure detection (BOS, Order Blocks, FVG)
   - VWAP calculations
   - Volatility checks (Range, ATR)
   - Candle quality analysis

2. **5-minute (5m)** - Used for:
   - ADX/DI trend strength calculations

**See**: `docs/NO_TRADE_ENGINE_TIMEFRAMES.md` for complete details

---

## Configuration

### Signal Generation

```yaml
signals:
  primary_timeframe: "5m"
  confirmation_timeframe: "15m"  # Optional
  enable_supertrend_signal: true
  enable_adx_filter: true
  supertrend:
    period: 7
    multiplier: 3.0
  adx:
    min_strength: 20
```

### No-Trade Engine

**No configuration needed** - uses sensible defaults:
- ADX threshold: 15
- DI overlap threshold: 2
- IV thresholds: NIFTY=10, BANKNIFTY=13
- Spread thresholds: NIFTY=2, BANKNIFTY=3
- Blocking threshold: Score >= 3

### Risk Management

```yaml
risk:
  loop_interval_active: 500    # ms (when positions exist)
  loop_interval_idle: 5000     # ms (when no positions)
  sl_pct: 0.30                 # 30% stop loss
  tp_pct: 0.60                 # 60% take profit
  peak_drawdown_threshold: 5.0 # % drop from peak
```

### Trailing Stops

```yaml
trailing:
  peak_drawdown_threshold: 5.0
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

## Summary

**Complete Flow**:
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
