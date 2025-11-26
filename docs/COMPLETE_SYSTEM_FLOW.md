# Complete System Flow: From Initializer to Exit

## Overview

This document provides a complete, detailed flow of the NEMESIS V3 trading system from Rails initialization through position exit, including all service interactions, data flows, and decision points.

---

## 1. System Initialization

### 1.1 Rails Server Startup

**Entry Point:** `bin/dev` → `bin/rails server` → Puma web server

**Initialization Sequence:**

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Rails Application Initialization                         │
│    - Loads config/environment.rb                            │
│    - Loads database.yml, routes.rb                          │
│    - Initializes ActiveRecord, ActionController             │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Initializers Load (config/initializers/*.rb)           │
│    - algo_config.rb: Loads config/algo.yml                │
│    - dhanhq_config.rb: Configures DhanHQ client             │
│    - cors.rb: CORS configuration                            │
│    - filter_parameter_logging.rb: Log filtering            │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Trading Supervisor Initializer                          │
│    File: config/initializers/trading_supervisor.rb         │
│                                                             │
│    Checks:                                                  │
│    - Skip if Rails.env.test?                               │
│    - Skip if Rails::Console defined                         │
│    - Skip if BACKTEST_MODE=1 or SCRIPT_MODE=1              │
│    - Skip if DISABLE_TRADING_SERVICES=1                    │
│    - Only run in web process (puma/rails server)           │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. TradingSystem::Supervisor Creation                      │
│    - Creates supervisor instance                            │
│    - Registers all services via adapters                    │
└───────────────────────┬─────────────────────────────────────┘
```

### 1.2 Service Registration

**File:** `config/initializers/trading_supervisor.rb`

**Services Registered (in order):**

```ruby
supervisor.register(:market_feed, MarketFeedHubService.new)
supervisor.register(:signal_scheduler, Signal::Scheduler.new)
supervisor.register(:risk_manager, Live::RiskManagerService.new(exit_engine: exit_engine))
supervisor.register(:position_heartbeat, TradingSystem::PositionHeartbeat.new)
supervisor.register(:order_router, TradingSystem::OrderRouter.new)
supervisor.register(:paper_pnl_refresher, Live::PaperPnlRefresher.new)
supervisor.register(:exit_manager, exit_engine)
supervisor.register(:active_cache, ActiveCacheService.new)
supervisor.register(:reconciliation, Live::ReconciliationService.instance)
```

**Service Dependencies:**

```
ExitEngine ← OrderRouter
     │
     └── RiskManagerService (receives exit_engine)
```

### 1.3 Service Startup Sequence

**Conditional Startup:**

```ruby
if TradingSession::Service.market_closed?
  # Market closed: Only start WebSocket connection
  supervisor[:market_feed]&.start
else
  # Market open: Start all services
  supervisor.start_all
end
```

**Startup Order (when market is open):**

```
1. MarketFeedHub (WebSocket connection)
   └── Subscribes to watchlist (indices: NIFTY, BANKNIFTY, SENSEX)
   
2. ActiveCache
   └── Starts → subscribes to MarketFeedHub callbacks
   └── Reloads peak values from Redis
   
3. Signal::Scheduler
   └── Starts periodic loop (default: 30s interval)
   
4. RiskManagerService
   └── Starts monitoring loop (default: 5s interval, demand-driven)
   
5. PositionHeartbeat
   └── Starts heartbeat monitoring
   
6. OrderRouter
   └── Initializes (no background thread)
   
7. PaperPnlRefresher
   └── Starts PnL refresh loop (if paper trading enabled)
   
8. ExitEngine
   └── Starts idle thread (waits for exit requests)
   
9. ReconciliationService
   └── Starts reconciliation loop
```

**Active Position Resubscription:**

```ruby
# After all services started
active_pairs = Live::PositionIndex.instance.all_keys.map do |k|
  seg, sid = k.split(':', 2)
  { segment: seg, security_id: sid }
end

supervisor[:market_feed].subscribe_many(active_pairs) if active_pairs.any?
```

---

## 2. Signal Generation Flow

### 2.1 Scheduler Loop

**Service:** `Signal::Scheduler`

**Loop Frequency:** 30 seconds (configurable via `DEFAULT_PERIOD`)

**Process:**

```
┌─────────────────────────────────────────────────────────────┐
│ Signal::Scheduler.start()                                  │
│   Thread: 'signal-scheduler'                              │
│                                                             │
│   Loop:                                                    │
│     For each index (NIFTY, BANKNIFTY, SENSEX):            │
│       1. Check if market closed → skip                    │
│       2. process_index(index_cfg)                         │
│       3. Sleep 5s between indices                         │
│     Sleep @period (30s)                                    │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ process_index(index_cfg)                                    │
│                                                             │
│   1. evaluate_supertrend_signal(index_cfg)                 │
│      Returns: signal hash or nil                           │
│                                                             │
│   2. If signal present:                                    │
│      process_signal(index_cfg, signal)                     │
└───────────────────────┬─────────────────────────────────────┘
```

### 2.2 Signal Evaluation (Direction-First Path)

**When:** `enable_direction_before_chain: true`

```
┌─────────────────────────────────────────────────────────────┐
│ evaluate_supertrend_signal(index_cfg)                       │
│                                                             │
│ Step 1: Get Instrument                                      │
│   instrument = IndexInstrumentCache.instance.get_or_fetch()│
│                                                             │
│ Step 2: Direction-First Check (if enabled)                 │
│   trend_result = Signal::TrendScorer.compute_direction()   │
│     ├── Computes trend_score (0-21)                        │
│     ├── Determines direction (:bullish, :bearish, nil)     │
│     └── Returns: { trend_score: X, direction: :bullish }   │
│                                                             │
│   If trend_score < min_trend_score (14) OR direction nil:  │
│     → Return nil (skip chain analysis)                      │
│                                                             │
│ Step 3: Chain Analysis (only if direction confirmed)       │
│   candidate = select_candidate_from_chain()                │
│     ├── Options::ChainAnalyzer.new()                       │
│     ├── analyzer.select_candidates(limit: 2, direction)     │
│     └── Returns: candidate hash                            │
│                                                             │
│ Step 4: Build Signal Hash                                  │
│   {                                                         │
│     segment: candidate[:segment],                          │
│     security_id: candidate[:security_id],                  │
│     reason: 'trend_scorer_direction',                       │
│     meta: {                                                 │
│       candidate_symbol: candidate[:symbol],                │
│       lot_size: candidate[:lot_size],                      │
│       direction: direction,                                 │
│       trend_score: trend_score,                             │
│       source: 'trend_scorer'                                │
│     }                                                       │
│   }                                                         │
└───────────────────────┬─────────────────────────────────────┘
```

### 2.3 Signal Processing

```
┌─────────────────────────────────────────────────────────────┐
│ process_signal(index_cfg, signal)                           │
│                                                             │
│   1. Extract pick/candidate from signal                     │
│   2. Determine direction (from signal or config)           │
│   3. Call EntryGuard.try_enter()                           │
│      ├── Validates entry (cooldown, limits, etc.)         │
│      ├── Calls Orders::EntryManager.process_entry()        │
│      └── Returns: true if entry successful                 │
└───────────────────────┬─────────────────────────────────────┘
```

---

## 3. Entry Flow

### 3.1 EntryGuard Validation

**Service:** `Entries::EntryGuard`

**Validation Checks:**

```
┌─────────────────────────────────────────────────────────────┐
│ Entries::EntryGuard.try_enter()                            │
│                                                             │
│   1. Check cooldown period                                 │
│      → Skip if index in cooldown                           │
│                                                             │
│   2. Check daily trade limits                              │
│      → Skip if max_trades_per_day reached                  │
│                                                             │
│   3. Check exposure limits                                 │
│      → Skip if max_same_side positions reached             │
│                                                             │
│   4. Check capital allocation                              │
│      → Calculate risk_pct via DynamicRiskAllocator         │
│                                                             │
│   5. If all checks pass:                                   │
│      → Call Orders::EntryManager.process_entry()           │
└───────────────────────┬─────────────────────────────────────┘
```

### 3.2 EntryManager Processing

**Service:** `Orders::EntryManager`

**Complete Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│ Orders::EntryManager.process_entry()                        │
│                                                             │
│ Step 1: Extract Pick/Candidate                             │
│   pick = extract_pick(signal_result)                        │
│                                                             │
│ Step 2: Dynamic Risk Allocation                            │
│   risk_pct = Capital::DynamicRiskAllocator.risk_pct_for()  │
│     ├── Uses trend_score from signal                       │
│     └── Returns: risk_pct (0.01 - 0.02)                    │
│                                                             │
│ Step 3: Entry Validation                                   │
│   Entries::EntryGuard.try_enter()                          │
│     ├── Validates cooldown, limits, exposure               │
│     └── Places order via Orders::Placer                   │
│                                                             │
│ Step 4: Find PositionTracker                              │
│   tracker = find_tracker_for_pick(pick, index_cfg)         │
│     └── Finds most recent active tracker                   │
│                                                             │
│ Step 5: Calculate SL/TP                                    │
│   sl_price, tp_price = calculate_sl_tp(entry_price, dir)  │
│     ├── Bullish: SL = entry * 0.70, TP = entry * 1.60    │
│     └── Bearish: SL = entry * 1.30, TP = entry * 0.50    │
│                                                             │
│ Step 6: Add to ActiveCache                                  │
│   position_data = ActiveCache.add_position(                 │
│     tracker: tracker,                                       │
│     sl_price: sl_price,                                     │
│     tp_price: tp_price                                      │
│   )                                                         │
│     ├── Creates PositionData struct                        │
│     ├── Attaches underlying metadata                       │
│     ├── Subscribes to MarketFeedHub (if auto enabled)     │
│     └── Emits 'positions.added' event                      │
│                                                             │
│ Step 7: Place Bracket Orders                               │
│   BracketPlacer.place_bracket(                              │
│     tracker: tracker,                                       │
│     sl_price: sl_price,                                     │
│     tp_price: tp_price                                      │
│   )                                                         │
│     └── Places/modifies SL/TP orders via broker            │
│                                                             │
│ Step 8: Record Trade                                        │
│   DailyLimits.record_trade(index_key: index_cfg[:key])     │
│                                                             │
│ Step 9: Emit Event                                          │
│   EventBus.publish('entry_filled', event_data)             │
│                                                             │
│ Returns: { success: true, tracker: tracker, ... }          │
└───────────────────────┬─────────────────────────────────────┘
```

### 3.3 ActiveCache Position Addition

**Service:** `Positions::ActiveCache`

**Detailed Process:**

```
┌─────────────────────────────────────────────────────────────┐
│ ActiveCache.add_position(tracker:, sl_price:, tp_price:)     │
│                                                             │
│   1. Create PositionData Struct                             │
│      PositionData.new(                                      │
│        tracker_id: tracker.id,                              │
│        security_id: tracker.security_id,                    │
│        segment: tracker.segment,                            │
│        entry_price: tracker.entry_price,                     │
│        quantity: tracker.quantity,                          │
│        sl_price: sl_price,                                  │
│        tp_price: tp_price,                                  │
│        peak_profit_pct: 0.0,                                │
│        sl_offset_pct: nil,                                  │
│        ...                                                   │
│      )                                                       │
│                                                             │
│   2. Attach Underlying Metadata                             │
│      attach_underlying_metadata(position_data, tracker)     │
│        ├── Resolves underlying segment/security_id          │
│        ├── Gets underlying LTP from TickCache              │
│        └── Sets: underlying_segment, underlying_security_id │
│                                                             │
│   3. Check for Pending Peak Values                         │
│      → Apply peak from Redis if available                   │
│                                                             │
│   4. Get Current LTP                                        │
│      ltp = TickCache.ltp(segment, security_id)            │
│      position_data.update_ltp(ltp) if ltp                   │
│                                                             │
│   5. Auto-Subscribe to Market Data (if enabled)            │
│      MarketFeedHub.subscribe_instrument(                    │
│        segment: tracker.segment,                            │
│        security_id: tracker.security_id                     │
│      )                                                       │
│                                                             │
│   6. Store in Cache                                          │
│      @cache[composite_key] = position_data                 │
│      @tracker_index[tracker.id] = composite_key            │
│                                                             │
│   7. Emit Notification                                       │
│      ActiveSupport::Notifications.instrument(               │
│        'positions.added',                                   │
│        tracker_id: tracker.id                                │
│      )                                                       │
│      → Wakes up RiskManagerService (if demand-driven)       │
│                                                             │
│ Returns: PositionData instance                              │
└───────────────────────┬─────────────────────────────────────┘
```

---

## 4. Market Data Flow

### 4.1 WebSocket Tick Reception

**Service:** `Live::MarketFeedHub`

**Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│ DhanHQ WebSocket → MarketFeedHub.handle_tick(tick)         │
│                                                             │
│ Tick Format:                                                │
│   {                                                         │
│     segment: 'NSE_FNO',                                     │
│     security_id: '50001',                                   │
│     ltp: 150.50,                                            │
│     prev_close: 148.00,                                     │
│     timestamp: Time.current                                 │
│   }                                                         │
│                                                             │
│ Processing:                                                 │
│   1. Update connection state (:connected)                  │
│   2. Store in TickCache (in-memory)                        │
│      Live::TickCache.put(tick)                             │
│   3. Update FeedHealthService                              │
│   4. Emit ActiveSupport::Notifications                     │
│      ActiveSupport::Notifications.instrument(              │
│        'dhanhq.tick', tick                                  │
│      )                                                       │
│   5. Invoke ActiveCache callbacks                          │
│      @callbacks.each { |cb| cb.call(tick) }                │
│   6. Update PositionIndex PnL (if position exists)         │
│      Live::PositionIndex.instance.trackers_for(sid)        │
│      → Live::PnlUpdaterService.cache_intermediate_pnl()    │
└───────────────────────┬─────────────────────────────────────┘
```

### 4.2 ActiveCache Tick Handling

**Service:** `Positions::ActiveCache`

**Callback Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│ ActiveCache.handle_tick(tick)                               │
│                                                             │
│   1. Validate Tick                                          │
│      → Skip if ltp <= 0 or segment/security_id missing     │
│                                                             │
│   2. Find Position                                          │
│      composite_key = "#{tick[:segment]}:#{tick[:security_id]}"│
│      position = @cache[composite_key]                       │
│      → Skip if position not found                          │
│                                                             │
│   3. Update LTP                                              │
│      position.update_ltp(tick[:ltp].to_f)                   │
│        ├── Sets current_ltp = ltp                           │
│        ├── Calls recalculate_pnl()                          │
│        │   ├── pnl = (ltp - entry_price) * quantity        │
│        │   ├── pnl_pct = ((ltp - entry_price) / entry_price) * 100│
│        │   ├── Updates high_water_mark if pnl > hwm        │
│        │   └── Updates peak_profit_pct if pnl_pct > peak   │
│        └── Sets last_updated_at = Time.current              │
│                                                             │
│   4. Check Exit Triggers                                     │
│      check_exit_triggers(position)                          │
│        ├── If position.sl_hit?                             │
│        │   → EventBus.publish('sl_hit', ...)               │
│        └── If position.tp_hit?                             │
│            → EventBus.publish('tp_hit', ...)                │
│                                                             │
│   5. Update Stats                                            │
│      @stats[:updates_processed] += 1                        │
└───────────────────────┬─────────────────────────────────────┘
```

---

## 5. Risk Management Flow

### 5.1 RiskManagerService Monitoring Loop

**Service:** `Live::RiskManagerService`

**Loop Frequency:**
- Active positions: 500ms (configurable)
- No positions (demand-driven): 5000ms (configurable)

**Main Loop:**

```
┌─────────────────────────────────────────────────────────────┐
│ RiskManagerService.monitor_loop()                           │
│                                                             │
│   1. Check Market Status                                    │
│      If market closed AND no active positions:              │
│        → Sleep 60s, continue                                │
│                                                             │
│   2. Demand-Driven Check (if enabled)                      │
│      If ActiveCache.empty? AND enable_demand_driven:        │
│        → Sleep 5000ms, continue                             │
│                                                             │
│   3. Update Paper Positions PnL (if due)                   │
│      update_paper_positions_pnl_if_due()                   │
│        → Runs every 1 minute                               │
│                                                             │
│   4. Ensure All Positions in Redis                         │
│      ensure_all_positions_in_redis()                       │
│        → Syncs PnL to Redis cache                          │
│                                                             │
│   5. Ensure All Positions in ActiveCache                    │
│      ensure_all_positions_in_active_cache()                 │
│        → Adds missing positions to cache                    │
│                                                             │
│   6. Ensure All Positions Subscribed                        │
│      ensure_all_positions_subscribed()                      │
│        → Subscribes to MarketFeedHub if not subscribed     │
│                                                             │
│   7. Process Trailing for All Positions                    │
│      process_trailing_for_all_positions()                   │
│        → Main risk management logic                        │
│                                                             │
│   8. Enforce Session End Exit                              │
│      enforce_session_end_exit()                            │
│        → Exits all positions before 3:15 PM IST            │
│                                                             │
│   9. Backwards-Compatible Enforcement (if no ExitEngine)   │
│      enforce_hard_limits()                                 │
│      enforce_trailing_stops()                              │
│      enforce_time_based_exit()                             │
└───────────────────────┬─────────────────────────────────────┘
```

### 5.2 Trailing Processing (Per Position)

**Service:** `Live::RiskManagerService`

**Detailed Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│ process_trailing_for_all_positions()                        │
│                                                             │
│   For each position in ActiveCache:                         │
│                                                             │
│   Step 1: Recalculate Position Metrics                     │
│     recalculate_position_metrics(position, tracker)         │
│       ├── Syncs PnL from Redis cache                       │
│       ├── Ensures LTP is current                           │
│       ├── Recalculates PnL if needed                        │
│       └── Updates peak_profit_pct if current > peak        │
│                                                             │
│   Step 2: Check Underlying-Aware Exits (if enabled)        │
│     handle_underlying_exit(position, tracker, exit_engine) │
│       ├── Calls UnderlyingMonitor.evaluate(position)      │
│       │   ├── Computes trend_score (0-21)                  │
│       │   ├── Checks bos_state (:broken, :intact)          │
│       │   ├── Checks atr_trend (:falling, :rising, :flat) │
│       │   └── Returns: OpenStruct with all metrics         │
│       │                                                   │
│       ├── If structure_break_against_position?            │
│       │   → guarded_exit('underlying_structure_break')    │
│       │   → Return true (skip remaining checks)            │
│       │                                                   │
│       ├── If trend_score < threshold (10)                  │
│       │   → guarded_exit('underlying_trend_weak')         │
│       │   → Return true                                    │
│       │                                                   │
│       └── If atr_collapse? (ATR ratio < 0.65)             │
│           → guarded_exit('underlying_atr_collapse')        │
│           → Return true                                    │
│                                                             │
│   Step 3: Enforce Hard SL/TP Limits (always active)         │
│     enforce_bracket_limits(position, tracker, exit_engine)│
│       ├── If position.sl_hit?                             │
│       │   → guarded_exit('SL HIT X.XX%')                  │
│       │   → Return true                                    │
│       │                                                   │
│       └── If position.tp_hit?                             │
│           → guarded_exit('TP HIT X.XX%')                   │
│           → Return true                                    │
│                                                             │
│   Step 4: Apply Tiered Trailing SL Offsets                 │
│     desired_sl_offset_pct =                                │
│       TrailingConfig.sl_offset_for(position.pnl_pct)       │
│         ├── Returns SL offset % based on profit tier       │
│         └── Example: 25% profit → +10% SL offset          │
│                                                             │
│     If desired_sl_offset_pct present:                      │
│       position.sl_offset_pct = desired_sl_offset_pct      │
│       ActiveCache.update_position(                          │
│         tracker_id,                                         │
│         sl_offset_pct: desired_sl_offset_pct               │
│       )                                                     │
│                                                             │
│   Step 5: Process Trailing with Peak-Drawdown Gating       │
│     TrailingEngine.process_tick(position, exit_engine)     │
│       ├── Checks peak-drawdown FIRST                       │
│       ├── Updates peak_profit_pct if current > peak       │
│       ├── Applies tiered SL offsets                        │
│       └── Handles peak-drawdown exit (if gating active)    │
└───────────────────────┬─────────────────────────────────────┘
```

### 5.3 TrailingEngine Processing

**Service:** `Live::TrailingEngine`

**Detailed Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│ TrailingEngine.process_tick(position_data, exit_engine)   │
│                                                             │
│   Step 1: Check Peak-Drawdown FIRST                         │
│     check_peak_drawdown(position_data, exit_engine)        │
│       ├── peak = position_data.peak_profit_pct             │
│       ├── current = position_data.pnl_pct                  │
│       ├── drawdown = peak - current                        │
│       │                                                   │
│       ├── If drawdown >= 5% (peak_drawdown_exit_pct):     │
│       │   ├── If peak_drawdown_activation enabled:        │
│       │   │   ├── Check activation conditions:             │
│       │   │   │   ├── peak >= 25% (activation_profit_pct) │
│       │   │   │   └── sl_offset_pct >= 10%                 │
│       │   │   │                                           │
│       │   │   ├── If activation conditions met:           │
│       │   │   │   → tracker.with_lock do                  │
│       │   │   │       → exit_engine.execute_exit(         │
│       │   │   │           tracker,                         │
│       │   │   │           'peak_drawdown_exit (...)'       │
│       │   │   │         )                                   │
│       │   │   │       → Return true                        │
│       │   │   │                                           │
│       │   │   └── Else: Return false (gating active)      │
│       │   │                                               │
│       │   └── Else (activation disabled):                 │
│       │       → Exit immediately                           │
│       │                                                   │
│       └── Else: Return false (no drawdown)                │
│                                                             │
│   Step 2: Update Peak Profit Percentage                    │
│     update_peak(position_data)                             │
│       ├── If current_pnl_pct > peak_profit_pct:           │
│       │   ├── ActiveCache.update_position(                 │
│       │   │     tracker_id,                                │
│       │   │     peak_profit_pct: current_pnl_pct           │
│       │   │   )                                             │
│       │   └── Persists peak to Redis (7-day TTL)          │
│       │                                                   │
│       └── Returns: true if updated                         │
│                                                             │
│   Step 3: Apply Tiered SL Offsets                          │
│     apply_tiered_sl(position_data)                        │
│       ├── sl_offset_pct =                                  │
│       │   TrailingConfig.sl_offset_for(current_profit_pct) │
│       │                                                   │
│       ├── new_sl_price =                                   │
│       │   TrailingConfig.sl_price_from_entry(              │
│       │     entry_price,                                   │
│       │     sl_offset_pct                                  │
│       │   )                                                 │
│       │                                                   │
│       ├── If new_sl_price > current_sl_price:             │
│       │   ├── BracketPlacer.update_bracket(                │
│       │   │     tracker: tracker,                          │
│       │   │     sl_price: new_sl_price                      │
│       │   │   )                                             │
│       │   ├── ActiveCache.update_position(                 │
│       │   │     tracker_id,                                │
│       │   │     sl_price: new_sl_price,                     │
│       │   │     sl_offset_pct: sl_offset_pct                │
│       │   │   )                                             │
│       │   └── Returns: { updated: true, ... }              │
│       │                                                   │
│       └── Else: Returns: { updated: false, ... }         │
│                                                             │
│   Returns: {                                                │
│     peak_updated: true/false,                              │
│     sl_updated: true/false,                                │
│     exit_triggered: true/false,                            │
│     reason: '...'                                          │
│   }                                                         │
└───────────────────────┬─────────────────────────────────────┘
```

---

## 6. Exit Flow

### 6.1 Exit Triggering

**Multiple Exit Paths:**

```
┌─────────────────────────────────────────────────────────────┐
│ Exit Triggers (Priority Order)                              │
│                                                             │
│   1. Underlying Structure Break                            │
│      → handle_underlying_exit()                            │
│      → Reason: 'underlying_structure_break'                │
│                                                             │
│   2. Underlying Weak Trend                                  │
│      → handle_underlying_exit()                            │
│      → Reason: 'underlying_trend_weak'                      │
│                                                             │
│   3. Underlying ATR Collapse                                │
│      → handle_underlying_exit()                            │
│      → Reason: 'underlying_atr_collapse'                    │
│                                                             │
│   4. Hard Stop Loss Hit                                     │
│      → enforce_bracket_limits()                            │
│      → Reason: 'SL HIT X.XX%'                              │
│                                                             │
│   5. Hard Take Profit Hit                                   │
│      → enforce_bracket_limits()                            │
│      → Reason: 'TP HIT X.XX%'                              │
│                                                             │
│   6. Peak-Drawdown Exit                                     │
│      → TrailingEngine.check_peak_drawdown()                │
│      → Reason: 'peak_drawdown_exit (drawdown: X%, peak: Y%)'│
│                                                             │
│   7. Session End Exit (3:15 PM IST)                        │
│      → enforce_session_end_exit()                          │
│      → Reason: 'session end (deadline: 3:15 PM IST)'      │
│                                                             │
│   8. Time-Based Exit                                        │
│      → enforce_time_based_exit()                           │
│      → Reason: 'time-based exit (HH:MM)'                   │
└───────────────────────┬─────────────────────────────────────┘
```

### 6.2 Guarded Exit Execution

**Service:** `Live::RiskManagerService`

**Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│ guarded_exit(tracker, reason, exit_engine)                  │
│                                                             │
│   If exit_engine is external (not self):                    │
│     ├── Check if tracker.exited? → return if true          │
│     └── exit_engine.execute_exit(tracker, reason)          │
│                                                             │
│   Else (self-managed):                                      │
│     tracker.with_lock do                                    │
│       ├── Check if tracker.exited? → return if true        │
│       └── dispatch_exit(self, tracker, reason)            │
│     end                                                      │
└───────────────────────┬─────────────────────────────────────┘
```

### 6.3 ExitEngine Execution

**Service:** `Live::ExitEngine`

**Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│ ExitEngine.execute_exit(tracker, reason)                    │
│                                                             │
│   tracker.with_lock do                                       │
│     1. Check if already exited                              │
│        → Return if tracker.exited?                         │
│                                                             │
│     2. Get Current LTP                                      │
│        ltp = safe_ltp(tracker)                              │
│          ├── Try TickCache.ltp()                           │
│          └── Fallback to RedisTickCache                     │
│                                                             │
│     3. Execute Exit Order                                   │
│        result = OrderRouter.exit_market(tracker)           │
│          ├── For paper: Simulates exit                     │
│          └── For live: Places market exit order            │
│                                                             │
│     4. Mark Tracker Exited                                  │
│        tracker.mark_exited!(                                │
│          exit_price: ltp,                                   │
│          exit_reason: reason                                │
│        )                                                    │
│          ├── Updates status: :exited                       │
│          ├── Sets exit_price, exit_reason                  │
│          ├── Updates last_pnl_rupees, last_pnl_pct         │
│          └── Saves to database                              │
│                                                             │
│     5. Log Exit                                             │
│        Rails.logger.info(                                   │
│          "[ExitEngine] Exit executed #{tracker.order_no}: "│
│          "#{reason}"                                        │
│        )                                                    │
│   end                                                        │
└───────────────────────┬─────────────────────────────────────┘
```

### 6.4 Post-Exit Cleanup

**Automatic Cleanup:**

```
┌─────────────────────────────────────────────────────────────┐
│ After tracker.mark_exited!()                                │
│                                                             │
│   1. ActiveCache Cleanup                                    │
│      → Position removed from ActiveCache                    │
│      → MarketFeedHub.unsubscribe_instrument() called        │
│      → 'positions.removed' event emitted                    │
│                                                             │
│   2. PositionIndex Cleanup                                  │
│      → Tracker removed from PositionIndex                   │
│                                                             │
│   3. Redis Cleanup                                          │
│      → PnL cache entries remain (for history)              │
│      → Peak values remain (7-day TTL)                      │
│                                                             │
│   4. DailyLimits Update                                     │
│      → Loss recorded if exit_price < entry_price           │
│      → Trade count incremented                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. Complete Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    COMPLETE SYSTEM FLOW                                  │
└─────────────────────────────────────────────────────────────────────────┘

[RAILS INITIALIZATION]
         │
         ▼
[TRADING SUPERVISOR INITIALIZER]
         │
         ├──→ MarketFeedHub.start!()
         │         │
         │         ├──→ WebSocket Connection
         │         ├──→ Subscribe to Watchlist (indices)
         │         └──→ Start Tick Handler Loop
         │
         ├──→ ActiveCache.start!()
         │         │
         │         ├──→ Subscribe to MarketFeedHub Callbacks
         │         └──→ Reload Peaks from Redis
         │
         ├──→ Signal::Scheduler.start()
         │         │
         │         └──→ Start Periodic Loop (30s)
         │
         ├──→ RiskManagerService.start()
         │         │
         │         └──→ Start Monitoring Loop (500ms)
         │
         └──→ Other Services...

[SIGNAL GENERATION LOOP]
         │
         ├──→ For each index:
         │         │
         │         ├──→ TrendScorer.compute_direction()
         │         │         │
         │         │         └──→ If trend_score < 14: SKIP
         │         │
         │         ├──→ ChainAnalyzer.select_candidates()
         │         │
         │         └──→ EntryGuard.try_enter()
         │                 │
         │                 └──→ EntryManager.process_entry()
         │                         │
         │                         ├──→ Create PositionTracker
         │                         ├──→ ActiveCache.add_position()
         │                         ├──→ MarketFeedHub.subscribe_instrument()
         │                         └──→ BracketPlacer.place_bracket()

[MARKET DATA FLOW]
         │
         ├──→ WebSocket Tick Received
         │         │
         │         ├──→ TickCache.put(tick)
         │         ├──→ ActiveCache.handle_tick(tick)
         │         │         │
         │         │         ├──→ position.update_ltp(ltp)
         │         │         ├──→ position.recalculate_pnl()
         │         │         └──→ Check SL/TP hits
         │         │
         │         └──→ PnlUpdaterService.cache_intermediate_pnl()

[RISK MANAGEMENT LOOP]
         │
         ├──→ For each position:
         │         │
         │         ├──→ recalculate_position_metrics()
         │         │
         │         ├──→ handle_underlying_exit()
         │         │         │
         │         │         ├──→ UnderlyingMonitor.evaluate()
         │         │         └──→ Exit if structure break/weak trend/ATR collapse
         │         │
         │         ├──→ enforce_bracket_limits()
         │         │         │
         │         │         └──→ Exit if SL/TP hit
         │         │
         │         ├──→ Apply tiered SL offsets
         │         │
         │         └──→ TrailingEngine.process_tick()
         │                 │
         │                 ├──→ check_peak_drawdown()
         │                 │         │
         │                 │         └──→ Exit if drawdown >= 5% (with gating)
         │                 │
         │                 ├──→ update_peak()
         │                 │
         │                 └──→ apply_tiered_sl()

[EXIT EXECUTION]
         │
         ├──→ ExitEngine.execute_exit()
         │         │
         │         ├──→ OrderRouter.exit_market()
         │         ├──→ tracker.mark_exited!()
         │         └──→ Cleanup:
         │                 │
         │                 ├──→ ActiveCache.remove_position()
         │                 ├──→ MarketFeedHub.unsubscribe_instrument()
         │                 └──→ DailyLimits.record_loss() (if loss)
```

---

## 8. Key Decision Points

### 8.1 Entry Decision Tree

```
Signal Generated?
    │
    ├── NO → Continue monitoring
    │
    └── YES
         │
         ├── Direction Confirmed? (trend_score >= 14)
         │   │
         │   ├── NO → Skip chain analysis
         │   │
         │   └── YES
         │         │
         │         ├── Chain Analysis → Candidates Found?
         │         │   │
         │         │   ├── NO → Skip entry
         │         │   │
         │         │   └── YES
         │         │         │
         │         │         ├── EntryGuard Validation
         │         │         │   │
         │         │         │   ├── Cooldown Active? → Skip
         │         │         │   ├── Daily Limit Reached? → Skip
         │         │         │   ├── Exposure Limit Reached? → Skip
         │         │         │   └── All Checks Pass → ENTER
         │         │         │
         │         │         └── EntryManager.process_entry()
```

### 8.2 Exit Decision Tree

```
For Each Position:
    │
    ├── Underlying Structure Break? (if enabled)
    │   │
    │   ├── YES → EXIT ('underlying_structure_break')
    │   │
    │   └── NO
    │         │
    │         ├── Underlying Trend Weak? (trend_score < 10)
    │         │   │
    │         │   ├── YES → EXIT ('underlying_trend_weak')
    │         │   │
    │         │   └── NO
    │         │         │
    │         │         ├── ATR Collapse? (ratio < 0.65)
    │         │         │   │
    │         │         │   ├── YES → EXIT ('underlying_atr_collapse')
    │         │         │   │
    │         │         │   └── NO
    │         │         │         │
    │         │         │         ├── SL Hit? (current_ltp <= sl_price)
    │         │         │         │   │
    │         │         │         │   ├── YES → EXIT ('SL HIT')
    │         │         │         │   │
    │         │         │         │   └── NO
    │         │         │         │         │
    │         │         │         │         ├── TP Hit? (current_ltp >= tp_price)
    │         │         │         │         │   │
    │         │         │         │         │   ├── YES → EXIT ('TP HIT')
    │         │         │         │         │   │
    │         │         │         │         │   └── NO
    │         │         │         │         │         │
    │         │         │         │         │         ├── Peak-Drawdown? (drawdown >= 5%)
    │         │         │         │         │         │   │
    │         │         │         │         │         │   ├── YES
    │         │         │         │         │         │   │   │
    │         │         │         │         │         │   │   ├── Gating Active?
    │         │         │         │         │         │   │   │   │
    │         │         │         │         │         │   │   │   ├── YES → Check Activation
    │         │         │         │         │         │   │   │   │   │
    │         │         │         │         │         │   │   │   │   ├── Peak >= 25% AND SL >= 10%?
    │         │         │         │         │         │   │   │   │   │   │
    │         │         │         │         │         │   │   │   │   │   ├── YES → EXIT ('peak_drawdown')
    │         │         │         │         │         │   │   │   │   │   │
    │         │         │         │         │         │   │   │   │   │   └── NO → Continue (gated)
    │         │         │         │         │         │   │   │   │   │
    │         │         │         │         │         │   │   │   └── NO → EXIT immediately
    │         │         │         │         │         │   │   │
    │         │         │         │         │         │   └── NO → Continue monitoring
    │         │         │         │         │         │
    │         │         │         │         │         └── Apply Trailing SL Updates
```

---

## 9. Data Structures

### 9.1 PositionData (ActiveCache)

```ruby
PositionData = Struct.new(
  :tracker_id,              # Integer - PositionTracker ID
  :security_id,             # String - Option security ID
  :segment,                 # String - Exchange segment
  :entry_price,             # Float - Entry price
  :quantity,                # Integer - Position quantity
  :sl_price,                # Float - Stop loss price
  :tp_price,                # Float - Take profit price
  :high_water_mark,         # Float - Highest PnL achieved
  :current_ltp,             # Float - Current last traded price
  :pnl,                     # Float - Current PnL (rupees)
  :pnl_pct,                 # Float - Current PnL percentage
  :peak_profit_pct,         # Float - Peak profit percentage
  :sl_offset_pct,           # Float - Current SL offset percentage
  :position_direction,       # Symbol - :bullish or :bearish
  :index_key,               # String - Index key (NIFTY, BANKNIFTY, etc.)
  :underlying_segment,      # String - Underlying index segment
  :underlying_security_id,  # String - Underlying index security ID
  :underlying_symbol,       # String - Underlying index symbol
  :underlying_trend_score,  # Float - Underlying trend score (0-21)
  :underlying_ltp,          # Float - Underlying index LTP
  :last_updated_at          # Time - Last update timestamp
)
```

### 9.2 UnderlyingMonitor State

```ruby
OpenStruct.new(
  trend_score: Float,      # 0-21 composite trend score
  bos_state: Symbol,       # :broken, :intact, :unknown
  bos_direction: Symbol,   # :bullish, :bearish, :neutral
  atr_trend: Symbol,       # :falling, :rising, :flat
  atr_ratio: Float,        # Current ATR / Previous ATR
  mtf_confirm: Boolean,    # Multi-timeframe confirmation
  ltp: Float              # Underlying index LTP
)
```

---

## 10. Configuration Reference

### 10.1 Feature Flags

```yaml
feature_flags:
  enable_direction_before_chain: true      # Direction-first signal generation
  enable_demand_driven_services: true       # Sleep when no positions
  enable_underlying_aware_exits: false     # Underlying-aware exit logic
  enable_peak_drawdown_activation: false   # Peak-drawdown gating
  enable_auto_subscribe_unsubscribe: true  # Auto market data subscription
```

### 10.2 Risk Configuration

```yaml
risk:
  sl_pct: 0.30                              # 30% fixed SL
  tp_pct: 0.60                              # 60% fixed TP
  peak_drawdown_exit_pct: 5                 # 5% drawdown threshold
  peak_drawdown_activation_profit_pct: 25.0  # Activation: profit >= 25%
  peak_drawdown_activation_sl_offset_pct: 10.0 # Activation: SL offset >= 10%
  underlying_trend_score_threshold: 10.0    # Exit if trend < 10
  underlying_atr_collapse_multiplier: 0.65  # Exit if ATR ratio < 0.65
```

---

## 11. Monitoring & Observability

### 11.1 Key Log Patterns

```
[UNDERLYING_EXIT] reason=underlying_structure_break tracker_id=123 ...
[PEAK_DRAWDOWN] tracker_id=123 peak_pct=35.0 current_pct=28.0 drawdown=7.0%
[RiskManager] Exit executed ORD123: SL HIT -30.00%
[ExitEngine] Exit executed ORD123: peak_drawdown_exit (drawdown: 7.00%, peak: 35.00%)
```

### 11.2 Metrics to Track

- `underlying_exit_count` - Count of underlying-triggered exits
- `peak_drawdown_exit_count` - Count of peak-drawdown exits
- `signals_processed` - Signal generation rate
- `entries_created` - Entry success rate
- `exits_triggered{reason=...}` - Exit reasons breakdown

---

**Document Version:** 1.0  
**Last Updated:** 2025-01-XX  
**Author:** AI Assistant (Composer)
