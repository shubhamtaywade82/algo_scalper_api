# Complete System Flow: From Initializer to Exit/EOD

**Last Updated:** 2025-01-16 - Added TrendScorer toggle, market close checks, Redis UI
**Repository:** https://github.com/shubhamtaywade82/algo_scalper_api/tree/new_trailing

---

## Table of Contents

1. [System Initialization](#1-system-initialization)
2. [Service Responsibilities](#2-service-responsibilities)
3. [Signal Generation Flow](#3-signal-generation-flow)
4. [Entry Flow](#4-entry-flow)
5. [Market Data Flow](#5-market-data-flow)
6. [PnL Update Flow](#6-pnl-update-flow)
7. [Risk Management Flow](#7-risk-management-flow)
8. [Exit Flow](#8-exit-flow)
9. [EOD Handling](#9-eod-handling)
10. [Service Intervals & Frequencies](#10-service-intervals--frequencies)
11. [Redis Cache Architecture](#11-redis-cache-architecture)
12. [Session Checks](#12-session-checks)
13. [Redis UI](#13-redis-ui)

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
│    - algo_config.rb: Loads config/algo.yml                 │
│    - dhanhq_config.rb: Configures DhanHQ client             │
│    - cors.rb: CORS configuration                            │
│    - filter_parameter_logging.rb: Log filtering            │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Trading Supervisor Initializer                          │
│    File: config/initializers/trading_supervisor.rb          │
│                                                             │
│    Skip Conditions:                                         │
│    - Rails.env.test?                                        │
│    - Rails::Console defined                                 │
│    - BACKTEST_MODE=1 or SCRIPT_MODE=1                      │
│    - DISABLE_TRADING_SERVICES=1                            │
│    - Not a web process (puma/rails server)                 │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. TradingSystem::Supervisor Creation                      │
│    - Creates supervisor instance                            │
│    - Registers all services via adapters                    │
└───────────────────────┬─────────────────────────────────────┘
```

### 1.2 Service Registration Order

**File:** `config/initializers/trading_supervisor.rb:147-159`

```ruby
# Service Registration (in order):
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

### 1.3 Conditional Startup

**Market Status Check:** `TradingSession::Service.market_closed?`

```ruby
if TradingSession::Service.market_closed?
  # Market closed: Only start WebSocket connection
  supervisor[:market_feed]&.start
else
  # Market open: Start all services
  supervisor.start_all
end
```

**Startup Sequence (when market is open):**

```
1. MarketFeedHub (WebSocket connection)
   └── Subscribes to watchlist (indices: NIFTY, BANKNIFTY, SENSEX)
   └── Thread: 'market-feed-hub'

2. ActiveCache
   └── Starts → subscribes to MarketFeedHub callbacks
   └── Reloads peak values from Redis
   └── Thread: N/A (event-driven callbacks)

3. Signal::Scheduler
   └── Starts periodic loop (default: 30s interval)
   └── Thread: 'signal-scheduler'

4. RiskManagerService
   └── Starts monitoring loop (default: 5s interval, demand-driven)
   └── Thread: 'risk-manager'
   └── Watchdog thread: 'risk-manager-watchdog' (restarts if dead)

5. PositionHeartbeat
   └── Starts heartbeat monitoring
   └── Thread: 'position-heartbeat'

6. OrderRouter
   └── Initializes (no background thread)

7. PaperPnlRefresher
   └── Starts PnL refresh loop (if paper trading enabled)
   └── Thread: 'paper-pnl-refresher'

8. ExitEngine
   └── Starts idle thread (waits for exit requests)
   └── Thread: 'exit-engine'

9. ReconciliationService
   └── Starts reconciliation loop (every 5 seconds)
   └── Thread: 'reconciliation-service'
```

**Active Position Resubscription:**

```ruby
# After all services started (if market is open)
active_pairs = Live::PositionIndex.instance.all_keys.map do |k|
  seg, sid = k.split(':', 2)
  { segment: seg, security_id: sid }
end

supervisor[:market_feed].subscribe_many(active_pairs) if active_pairs.any?
```

---

## 2. Service Responsibilities

### 2.1 Independent Services (Run Continuously)

| Service                   | Thread Name              | Responsibility                                                | Frequency                  |
| ------------------------- | ------------------------ | ------------------------------------------------------------- | -------------------------- |
| **MarketFeedHub**         | `market-feed-hub`        | WebSocket connection, tick reception, subscription management | Continuous                 |
| **Signal::Scheduler**     | `signal-scheduler`       | Generate trading signals for indices                          | 30s (configurable)         |
| **RiskManagerService**    | `risk-manager`           | Monitor positions, enforce exits, update PnL                  | 500ms active / 5000ms idle |
| **PaperPnlRefresher**     | `paper-pnl-refresher`    | Refresh paper position PnL                                    | 1s (configurable)          |
| **PnlUpdaterService**     | `pnl-updater-service`    | Batch write PnL to Redis                                      | 250ms flush interval       |
| **ReconciliationService** | `reconciliation-service` | Data consistency checks                                       | Every 5 seconds            |
| **ExitEngine**            | `exit-engine`            | Execute exit orders (idle thread)                             | On-demand                  |

### 2.2 Integrated Services (Event-Driven)

| Service                 | Trigger             | Responsibility                             |
| ----------------------- | ------------------- | ------------------------------------------ |
| **ActiveCache**         | MarketFeedHub ticks | Update position PnL in-memory, emit events |
| **PositionSyncService** | Periodic (30s)      | Sync positions from DhanHQ to DB           |
| **PositionHeartbeat**   | Periodic            | Monitor position health                    |

### 2.3 Service Dependencies

```
MarketFeedHub
  ├──→ ActiveCache (via callbacks)
  ├──→ TickCache (in-memory storage)
  └──→ RedisTickCache (persistent storage)

Signal::Scheduler
  ├──→ TrendScorer (direction calculation)
  ├──→ ChainAnalyzer (option selection)
  ├──→ EntryGuard (validation)
  └──→ EntryManager (order placement)

RiskManagerService
  ├──→ ActiveCache (position data)
  ├──→ RedisPnlCache (PnL data)
  ├──→ UnderlyingMonitor (underlying health)
  ├──→ TrailingEngine (trailing stops)
  └──→ ExitEngine (exit execution)

EntryManager
  ├──→ Capital::Allocator (quantity calculation)
  ├──→ Capital::DynamicRiskAllocator (risk %)
  ├──→ EntryGuard (validation)
  ├──→ ActiveCache (add position)
  └──→ MarketFeedHub (subscribe instrument)

PaperPnlRefresher
  ├──→ TickCache (LTP lookup)
  └──→ RedisPnlCache (store PnL)

PnlUpdaterService
  └──→ RedisPnlCache (batch write)
```

---

## 3. Signal Generation Flow

### 3.1 Scheduler Loop

**Service:** `Signal::Scheduler`
**File:** `app/services/signal/scheduler.rb`
**Thread:** `signal-scheduler`
**Frequency:** 30 seconds (`DEFAULT_PERIOD`)

**Process:**

```
┌─────────────────────────────────────────────────────────────┐
│ Signal::Scheduler.start()                                  │
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
│   1. TradingSession::Service.market_closed? → return      │
│   2. evaluate_supertrend_signal(index_cfg)                 │
│      Returns: signal hash or nil                           │
│   3. If signal present:                                    │
│      process_signal(index_cfg, signal)                     │
└───────────────────────┬─────────────────────────────────────┘
```

### 3.2 Signal Evaluation (TrendScorer vs Legacy Path)

**Toggle:** `enable_trend_scorer` feature flag (new explicit toggle)
**Legacy Toggle:** `enable_direction_before_chain` (backward compatibility)

**Logic:** If `enable_trend_scorer: false`, TrendScorer is disabled regardless of legacy flag.

```
┌─────────────────────────────────────────────────────────────┐
│ evaluate_supertrend_signal(index_cfg)                       │
│                                                             │
│ Step 1: Get Instrument                                      │
│   instrument = IndexInstrumentCache.instance.get_or_fetch()│
│                                                             │
│ Step 2: TrendScorer Path (if enabled)                       │
│   if trend_scorer_enabled?                                  │
│     # Check: enable_trend_scorer != false (explicit check)  │
│     # AND (enable_trend_scorer == true OR                   │
│     #      enable_direction_before_chain == true)            │
│                                                             │
│     trend_result = Signal::TrendScorer.compute_direction()   │
│       ├── Computes trend_score (0-21)                      │
│       │   ├── pa_score (0-7): Price action patterns        │
│       │   ├── ind_score (0-7): Technical indicators        │
│       │   └── mtf_score (0-7): Multi-timeframe alignment   │
│       ├── Determines direction (:bullish, :bearish, nil)   │
│       └── Returns: { trend_score: X, direction: :bullish,   │
│                     breakdown: { pa: Y, ind: Z, mtf: W } } │
│                                                             │
│     min_trend_score = 14.0 (default, configurable)         │
│     If trend_score < min_trend_score OR direction nil:      │
│       → Log warning with breakdown                          │
│       → Return nil (skip chain analysis)                    │
│                                                             │
│     # Direction confirmed - proceed to chain analysis       │
│     candidate = select_candidate_from_chain()              │
│       ├── Options::ChainAnalyzer.new()                     │
│       ├── analyzer.select_candidates(limit: 2, direction)    │
│       └── Returns: candidate hash                          │
│                                                             │
│     Return signal hash with candidate                       │
│                                                             │
│ Step 3: Legacy Supertrend+ADX Path (if TrendScorer disabled)│
│   indicator_result = Signal::Engine.analyze_multi_timeframe()│
│     ├── Checks enable_supertrend_signal flag               │
│     ├── Checks enable_adx_filter flag                      │
│     ├── Checks enable_confirmation_timeframe flag          │
│     ├── Analyzes 1m Supertrend (if enabled)               │
│     ├── Analyzes ADX strength (if enabled)                 │
│     └── Analyzes 5m confirmation (if enabled)             │
│                                                             │
│   direction = indicator_result[:final_direction]            │
│   If direction nil or :avoid → return nil                   │
│   candidate = select_candidate_from_chain()                │
│   Return signal hash                                       │
└───────────────────────┬─────────────────────────────────────┘
```

### 3.3 Signal Processing

```
┌─────────────────────────────────────────────────────────────┐
│ process_signal(index_cfg, signal)                           │
│                                                             │
│   1. Extract pick/candidate from signal                     │
│   2. Determine direction (from signal or config)           │
│   3. Call EntryGuard.try_enter()                           │
│      ├── Validates entry (cooldown, limits, exposure)     │
│      ├── Places order (paper/live)                         │
│      ├── Creates PositionTracker                           │
│      └── Calls EntryManager.process_entry()                 │
│                                                             │
│   4. If EntryGuard returns false:                          │
│      → Log warning, skip entry                             │
└───────────────────────┬─────────────────────────────────────┘
```

---

## 4. Entry Flow

### 4.1 EntryGuard Validation

**Service:** `Entries::EntryGuard`
**File:** `app/services/entries/entry_guard.rb`
**Method:** `try_enter()`

**Validation Checks (in order):**

```
┌─────────────────────────────────────────────────────────────┐
│ Entries::EntryGuard.try_enter()                            │
│                                                             │
│   1. Find Instrument                                        │
│      → Skip if instrument not found                        │
│                                                             │
│   2. Trading Session Check                                 │
│      TradingSession::Service.entry_allowed?                │
│      → Skip if before 9:20 AM or after 3:15 PM IST        │
│                                                             │
│   3. Daily Limits Check                                     │
│      Live::DailyLimits.can_trade?(index_key:)              │
│      → Skip if daily_loss limit reached                    │
│      → Skip if daily_trades limit reached                  │
│                                                             │
│   4. Exposure Check                                         │
│      exposure_ok?(instrument:, side:, max_same_side:)     │
│      → Skip if max_same_side positions reached             │
│      → Check pyramiding rules if second position           │
│                                                             │
│   5. Cooldown Check                                         │
│      cooldown_active?(symbol, cooldown_sec)                │
│      → Skip if symbol in cooldown period                   │
│                                                             │
│   6. LTP Resolution                                         │
│      → Try WebSocket TickCache first                        │
│      → Fallback to REST API if WS unavailable              │
│      → Skip if LTP invalid                                 │
│                                                             │
│   7. Quantity Calculation                                   │
│      Capital::Allocator.qty_for()                          │
│      → Calculate based on risk_pct and lot_size            │
│      → Auto-paper fallback if insufficient live balance   │
│                                                             │
│   8. Segment Validation                                     │
│      → Skip if segment not tradable (indices)              │
│                                                             │
│   9. Order Placement                                        │
│      If paper_mode:                                         │
│        → create_paper_tracker!()                           │
│      Else:                                                  │
│        → Orders.config.place_market()                      │
│        → create_tracker!()                                  │
│                                                             │
│   10. Post-Entry Wiring                                     │
│       post_entry_wiring(tracker:, side:, index_cfg:)       │
│       → Calls EntryManager.process_entry()                 │
└───────────────────────┬─────────────────────────────────────┘
```

### 4.2 EntryManager Processing

**Service:** `Orders::EntryManager`
**File:** `app/services/orders/entry_manager.rb`
**Method:** `process_entry()`

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
│     ├── Scales base_risk by trend_score (0-21)            │
│     └── Returns: risk_pct (0.01 - 0.10)                    │
│                                                             │
│ Step 3: Entry Validation                                   │
│   Entries::EntryGuard.try_enter()                          │
│     ├── Validates cooldown, limits, exposure               │
│     ├── Places order via Orders::Placer                    │
│     └── Creates PositionTracker                            │
│                                                             │
│ Step 4: Find PositionTracker                                │
│   tracker = find_tracker_for_pick(pick, index_cfg)         │
│     └── Finds most recent active tracker                   │
│                                                             │
│ Step 5: Validate Quantity                                   │
│   → Reject if quantity < 1 lot-equivalent                  │
│                                                             │
│ Step 6: Calculate SL/TP                                     │
│   sl_price, tp_price = calculate_sl_tp(entry_price, dir)  │
│     ├── Bullish: SL = entry * 0.70, TP = entry * 1.60    │
│     └── Bearish: SL = entry * 1.30, TP = entry * 0.50    │
│                                                             │
│ Step 7: Add to ActiveCache                                  │
│   position_data = @active_cache.add_position(              │
│     tracker: tracker,                                       │
│     sl_price: sl_price,                                     │
│     tp_price: tp_price                                      │
│   )                                                         │
│     ├── Creates PositionData struct                        │
│     ├── Attaches underlying metadata                       │
│     ├── Auto-subscribes to MarketFeedHub (if enabled)     │
│     └── Emits 'positions.added' event                      │
│                                                             │
│ Step 8: Place Bracket Orders                                │
│   BracketPlacer.place_bracket(                              │
│     tracker: tracker,                                       │
│     sl_price: sl_price,                                     │
│     tp_price: tp_price                                      │
│   )                                                         │
│     └── Places/modifies SL/TP orders via broker            │
│                                                             │
│ Step 9: Record Trade                                        │
│   DailyLimits.record_trade(index_key: index_cfg[:key])     │
│                                                             │
│ Step 10: Emit Event                                         │
│    EventBus.publish('entry_filled', event_data)            │
│                                                             │
│ Returns: { success: true, tracker: tracker, ... }          │
└───────────────────────┬─────────────────────────────────────┘
```

### 4.3 Capital Allocation

**Service:** `Capital::Allocator`
**File:** `app/services/capital/allocator.rb`
**Method:** `qty_for()`

**Process:**

```
┌─────────────────────────────────────────────────────────────┐
│ Capital::Allocator.qty_for()                               │
│                                                             │
│   1. Get Available Cash                                    │
│      available_cash = Capital::Allocator.available_cash    │
│                                                             │
│   2. Get Deployment Policy                                 │
│      policy = Capital::Allocator.deployment_policy(balance)│
│        ├── Determines risk_per_trade_pct based on balance  │
│        └── Returns policy hash                             │
│                                                             │
│   3. Calculate Risk Amount                                  │
│      risk_amount = available_cash * risk_per_trade_pct     │
│                                                             │
│   4. Calculate Quantity                                    │
│      quantity = (risk_amount / entry_price) / lot_size     │
│      quantity = quantity * scale_multiplier                 │
│                                                             │
│   5. Round to Lot Size                                      │
│      quantity = (quantity / lot_size).floor * lot_size     │
│                                                             │
│   Returns: Integer quantity (lot-aligned)                  │
└───────────────────────┬─────────────────────────────────────┘
```

**Dynamic Risk Allocator:**

**Service:** `Capital::DynamicRiskAllocator`
**File:** `app/services/capital/dynamic_risk_allocator.rb`
**Method:** `risk_pct_for()`

```
┌─────────────────────────────────────────────────────────────┐
│ Capital::DynamicRiskAllocator.risk_pct_for()               │
│                                                             │
│   1. Get Base Risk for Index                               │
│      base_risk = base_risk_for_index(index_key)            │
│                                                             │
│   2. Scale by Trend Score (if provided)                   │
│      scaled_risk = scale_by_trend(trend_score, base_risk)  │
│        ├── Low trend (0-7): 0.5x base risk                │
│        ├── Medium trend (7-14): 1.0x base risk            │
│        └── High trend (14-21): 1.5x base risk              │
│                                                             │
│   3. Cap Risk                                               │
│      capped_risk = cap_risk(scaled_risk, base_risk)        │
│        ├── Max 2x base risk                               │
│        └── Max 10% absolute                                │
│                                                             │
│   Returns: Float risk_pct (0.0 to 0.10)                    │
└───────────────────────┬─────────────────────────────────────┘
```

### 4.4 ActiveCache Position Addition

**Service:** `Positions::ActiveCache`
**File:** `app/services/positions/active_cache.rb`
**Method:** `add_position()`

**Detailed Process:**

```
┌─────────────────────────────────────────────────────────────┐
│ ActiveCache.add_position(tracker:, sl_price:, tp_price:)   │
│                                                             │
│   1. Create PositionData Struct                             │
│      PositionData.new(                                      │
│        tracker_id: tracker.id,                              │
│        security_id: tracker.security_id,                    │
│        segment: tracker.segment,                            │
│        entry_price: tracker.entry_price,                    │
│        quantity: tracker.quantity,                          │
│        sl_price: sl_price,                                  │
│        tp_price: tp_price,                                  │
│        peak_profit_pct: 0.0,                                │
│        sl_offset_pct: nil,                                  │
│        ...                                                   │
│      )                                                       │
│                                                             │
│   2. Attach Underlying Metadata                             │
│      attach_underlying_metadata(position_data, tracker)   │
│        ├── Resolves underlying segment/security_id          │
│        ├── Gets underlying LTP from TickCache              │
│        └── Sets: underlying_segment, underlying_security_id│
│                                                             │
│   3. Check for Pending Peak Values                         │
│      → Load peak from Redis if available                   │
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
│   7. Persist Peak to Redis                                  │
│      → Store peak_profit_pct with 7-day TTL                │
│                                                             │
│   8. Emit Notification                                      │
│      ActiveSupport::Notifications.instrument(               │
│        'positions.added',                                   │
│        tracker_id: tracker.id                                │
│      )                                                       │
│      → Wakes up RiskManagerService (if demand-driven)       │
│      → Wakes up PaperPnlRefresher (if demand-driven)       │
│                                                             │
│ Returns: PositionData instance                              │
└───────────────────────┬─────────────────────────────────────┘
```

---

## 5. Market Data Flow

### 5.1 WebSocket Tick Reception

**Service:** `Live::MarketFeedHub`
**File:** `app/services/live/market_feed_hub.rb`
**Thread:** `market-feed-hub`

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
│   3. Store in RedisTickCache (persistent)                  │
│      Live::RedisTickCache.instance.store_tick(tick)        │
│   4. Update FeedHealthService                              │
│   5. Emit ActiveSupport::Notifications                     │
│      ActiveSupport::Notifications.instrument(              │
│        'dhanhq.tick', tick                                  │
│      )                                                       │
│   6. Invoke ActiveCache callbacks                          │
│      @callbacks.each { |cb| cb.call(tick) }                │
│   7. Update PositionIndex PnL (if position exists)         │
│      Live::PositionIndex.instance.trackers_for(sid)        │
│      → Live::PnlUpdaterService.cache_intermediate_pnl()    │
└───────────────────────┬─────────────────────────────────────┘
```

### 5.2 ActiveCache Tick Handling

**Service:** `Positions::ActiveCache`
**File:** `app/services/positions/active_cache.rb`
**Method:** `handle_tick()`

**Callback Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│ ActiveCache.handle_tick(tick)                              │
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
│        ├── Sets current_ltp = ltp                          │
│        ├── Calls recalculate_pnl()                          │
│        │   ├── pnl = (ltp - entry_price) * quantity        │
│        │   ├── pnl_pct = ((ltp - entry_price) / entry_price) * 100│
│        │   ├── Updates high_water_mark if pnl > hwm        │
│        │   └── Updates peak_profit_pct if pnl_pct > peak   │
│        └── Sets last_updated_at = Time.current              │
│                                                             │
│   4. Persist Peak to Redis                                   │
│      → Store peak_profit_pct if updated (7-day TTL)        │
│                                                             │
│   5. Check Exit Triggers                                     │
│      check_exit_triggers(position)                          │
│        ├── If position.sl_hit?                             │
│        │   → EventBus.publish('sl_hit', ...)               │
│        └── If position.tp_hit?                             │
│            → EventBus.publish('tp_hit', ...)                │
│                                                             │
│   6. Update Stats                                            │
│      @stats[:updates_processed] += 1                        │
└───────────────────────┬─────────────────────────────────────┘
```

---

## 6. PnL Update Flow

### 6.1 PaperPnlRefresher

**Service:** `Live::PaperPnlRefresher`
**File:** `app/services/live/paper_pnl_refresher.rb`
**Thread:** `paper-pnl-refresher`
**Frequency:** 1 second (configurable via `realtime_interval_seconds`)

**Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│ PaperPnlRefresher.run_loop()                               │
│                                                             │
│   1. Check Market Status                                    │
│      If market closed AND no active positions:              │
│        → Sleep 60s, continue                                │
│                                                             │
│   2. Demand-Driven Check (if enabled)                      │
│      If ActiveCache.empty? AND enable_demand_driven:        │
│        → Sleep idle_interval (default: 5000ms), continue    │
│                                                             │
│   3. Refresh All Paper Positions                           │
│      refresh_all()                                          │
│        For each PositionTracker.paper.active:               │
│          refresh_tracker(tracker)                           │
│            ├── Get LTP from TickCache                      │
│            ├── Calculate PnL                               │
│            ├── Update tracker.last_pnl_rupees              │
│            ├── Update tracker.last_pnl_pct                 │
│            ├── Update tracker.high_water_mark_pnl          │
│            └── Store in RedisPnlCache                       │
│                                                             │
│   4. Sleep active_interval (default: 1000ms)                │
└───────────────────────┬─────────────────────────────────────┘
```

### 6.2 PnlUpdaterService

**Service:** `Live::PnlUpdaterService`
**File:** `app/services/live/pnl_updater_service.rb`
**Thread:** `pnl-updater-service`
**Frequency:** 250ms flush interval

**Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│ PnlUpdaterService.run_loop()                                │
│                                                             │
│   1. Check Market Status                                    │
│      If market closed AND no active positions:              │
│        → Sleep 60s, continue                                │
│                                                             │
│   2. Flush Queue to Redis                                   │
│      flush!()                                               │
│        ├── Take up to MAX_BATCH (200) items                │
│        ├── Batch load trackers from DB                      │
│        ├── For each tracker:                                │
│        │   ├── Update tracker.last_pnl_rupees              │
│        │   ├── Update tracker.last_pnl_pct                 │
│        │   ├── Update tracker.high_water_mark_pnl          │
│        │   └── Store in RedisPnlCache (batch write)       │
│        └── Remove processed items from queue                │
│                                                             │
│   3. Sleep Based on Queue State                             │
│      If queue empty: sleep longer (60s)                    │
│      Else: sleep FLUSH_INTERVAL (250ms)                    │
└───────────────────────┬─────────────────────────────────────┘
```

**Queue Population:**

```
MarketFeedHub.handle_tick()
  └──→ PositionIndex.trackers_for()
       └──→ PnlUpdaterService.cache_intermediate_pnl()
            └──→ Adds to queue (last-wins per tracker_id)
```

### 6.3 RiskManagerService PnL Updates

**Service:** `Live::RiskManagerService`
**File:** `app/services/live/risk_manager_service.rb`
**Method:** `update_paper_positions_pnl_if_due()`

**Frequency:** Every 1 minute

**Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│ RiskManagerService.update_paper_positions_pnl_if_due()     │
│                                                             │
│   1. Check if Due                                           │
│      If last_update_time < 1 minute ago: return             │
│                                                             │
│   2. Update All Paper Positions                             │
│      update_paper_positions_pnl()                           │
│        For each PositionTracker.paper.active:               │
│          ├── Stagger API calls (1s between)                │
│          ├── Get LTP (TickCache → RedisTickCache → API)    │
│          ├── Calculate PnL                                 │
│          ├── Update tracker.last_pnl_rupees                │
│          ├── Update tracker.last_pnl_pct                   │
│          ├── Update tracker.high_water_mark_pnl            │
│          └── Store in RedisPnlCache                        │
└───────────────────────┬─────────────────────────────────────┘
```

---

## 7. Risk Management Flow

### 7.1 RiskManagerService Monitoring Loop

**Service:** `Live::RiskManagerService`
**File:** `app/services/live/risk_manager_service.rb`
**Thread:** `risk-manager`
**Frequency:**
- Active positions: 500ms (`loop_interval_active`)
- No positions (demand-driven): 5000ms (`loop_interval_idle`)

**Main Loop:**

```
┌─────────────────────────────────────────────────────────────┐
│ RiskManagerService.monitor_loop()                           │
│                                                             │
│   1. Check Market Status                                    │
│      If market closed AND no active positions:              │
│        → Sleep 60s, continue                                │
│                                                             │
│   2. Demand-Driven Check (if enabled)                       │
│      If ActiveCache.empty? AND enable_demand_driven:        │
│        → Sleep 5000ms, continue                             │
│                                                             │
│   3. Update Paper Positions PnL (if due)                    │
│      update_paper_positions_pnl_if_due()                   │
│        → Runs every 1 minute                               │
│                                                             │
│   4. Ensure All Positions in Redis                          │
│      ensure_all_positions_in_redis()                       │
│        → Syncs PnL to Redis cache (every 5s)               │
│                                                             │
│   5. Ensure All Positions in ActiveCache                    │
│      ensure_all_positions_in_active_cache()                 │
│        → Adds missing positions to cache (every 5s)        │
│                                                             │
│   6. Ensure All Positions Subscribed                        │
│      ensure_all_positions_subscribed()                      │
│        → Subscribes to MarketFeedHub if not subscribed (every 5s)│
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

### 7.2 Trailing Processing (Per Position)

**Service:** `Live::RiskManagerService`
**Method:** `process_trailing_for_all_positions()`

**Detailed Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│ process_trailing_for_all_positions()                        │
│                                                             │
│   For each position in ActiveCache:                         │
│                                                             │
│   Step 1: Recalculate Position Metrics                     │
│     recalculate_position_metrics(position, tracker)       │
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
│       │   → guarded_exit('underlying_structure_break')     │
│       │   → Return true (skip remaining checks)              │
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
│     enforce_bracket_limits(position, tracker, exit_engine)  │
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

---

## 8. Exit Flow

### 8.1 Exit Trigger Priority Order

```
┌─────────────────────────────────────────────────────────────┐
│ Exit Triggers (Priority Order)                             │
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

### 8.2 Guarded Exit Execution

**Service:** `Live::RiskManagerService`
**Method:** `guarded_exit()`

**Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│ guarded_exit(tracker, reason, exit_engine)                  │
│                                                             │
│   If exit_engine is external (not self):                    │
│     ├── Check if tracker.exited? → return if true          │
│     └── exit_engine.execute_exit(tracker, reason)            │
│                                                             │
│   Else (self-managed):                                      │
│     tracker.with_lock do                                    │
│       ├── Check if tracker.exited? → return if true        │
│       └── dispatch_exit(self, tracker, reason)            │
│     end                                                      │
└───────────────────────┬─────────────────────────────────────┘
```

### 8.3 ExitEngine Execution

**Service:** `Live::ExitEngine`
**File:** `app/services/live/exit_engine.rb`
**Method:** `execute_exit()`

**Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│ ExitEngine.execute_exit(tracker, reason)                   │
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

### 8.4 Post-Exit Cleanup

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

## 9. EOD Handling

### 9.1 Session End Exit

**Service:** `Live::RiskManagerService`
**Method:** `enforce_session_end_exit()`

**Flow:**

```
┌─────────────────────────────────────────────────────────────┐
│ enforce_session_end_exit(exit_engine:)                     │
│                                                             │
│   1. Check Session Deadline                                 │
│      session_check = TradingSession::Service.should_force_exit?│
│      → Return if should_exit == false                       │
│                                                             │
│   2. Get All Active Positions                               │
│      positions = active_cache_positions                    │
│      → Return if empty                                      │
│                                                             │
│   3. Exit All Positions                                     │
│      For each position:                                     │
│        ├── Sync PnL from Redis                             │
│        ├── Call guarded_exit()                             │
│        └── Reason: 'session end (deadline: 3:15 PM IST)'   │
│                                                             │
│   4. Log Exit Count                                         │
│      Rails.logger.info("Session end exit: #{exited_count} positions exited")│
└───────────────────────┬─────────────────────────────────────┘
```

### 9.2 Market Closed Behavior

**All Services Check:** `TradingSession::Service.market_closed?`

**Market Close Time:** 3:30 PM IST (`MARKET_CLOSE_HOUR = 15`, `MARKET_CLOSE_MINUTE = 30`)

**Behavior:**

- **MarketFeedHub:** Always runs (WebSocket connection maintained)
  - Resubscribes watchlist items on reconnect
  - Skips resubscribing active positions when market is closed

- **Signal::Scheduler:**
  - Skips signal generation if market closed
  - Sleeps 60s when market closed

- **RiskManagerService:**
  - Sleeps 60s if market closed AND no active positions
  - Continues monitoring if positions exist (needed for exits)

- **PaperPnlRefresher:**
  - Sleeps 60s if market closed AND no active positions
  - Continues refresh if positions exist (needed for PnL updates)

- **PnlUpdaterService:**
  - Sleeps 60s if market closed AND no active positions
  - Continues processing if positions exist

- **ReconciliationService:**
  - Sleeps 60s if market closed AND no active positions
  - Continues reconciliation if positions exist

- **PositionHeartbeat:**
  - Sleeps 60s if market closed AND no active positions
  - Continues heartbeat if positions exist

**Supervisor Initialization:**
- If market closed on startup: Only starts `MarketFeedHub` (WebSocket only)
- If market open on startup: Starts all services

---

## 10. Service Intervals & Frequencies

### 10.1 Service Loop Intervals

| Service                   | Active Interval | Idle Interval | Config Key                                                            |
| ------------------------- | --------------- | ------------- | --------------------------------------------------------------------- |
| **Signal::Scheduler**     | 30s             | N/A           | `DEFAULT_PERIOD`                                                      |
| **RiskManagerService**    | 500ms           | 5000ms        | `risk.loop_interval_active` / `risk.loop_interval_idle`               |
| **PaperPnlRefresher**     | 1000ms          | 5000ms        | `paper_trading.realtime_interval_seconds` / `risk.loop_interval_idle` |
| **PnlUpdaterService**     | 250ms           | 60s           | `FLUSH_INTERVAL_SECONDS`                                              |
| **ReconciliationService** | 5s              | 60s           | `RECONCILIATION_INTERVAL`                                             |
| **PositionSyncService**   | 30s             | N/A           | `@sync_interval`                                                      |

### 10.2 Demand-Driven Behavior

**Feature Flag:** `enable_demand_driven_services`

**When Enabled:**
- **RiskManagerService:** Sleeps 5000ms when `ActiveCache.empty?`
- **PaperPnlRefresher:** Sleeps idle_interval when `ActiveCache.empty?`
- Both services wake up on `positions.added` / `positions.removed` events

**Event Subscription:**

```ruby
ActiveSupport::Notifications.subscribe('positions.added') { wake_up! }
ActiveSupport::Notifications.subscribe('positions.removed') { wake_up! }
```

---

## 11. Redis Cache Architecture

### 11.1 RedisPnlCache

**Service:** `Live::RedisPnlCache`
**Key Format:** `pnl:tracker:#{tracker_id}`

**Data Structure:**

```json
{
  "pnl": 150.50,
  "pnl_pct": 5.25,
  "ltp": 157.50,
  "hwm_pnl": 200.00,
  "peak_profit_pct": 8.50,
  "timestamp": 1234567890
}
```

**TTL:** None (persistent)

**Writers:**
- `PnlUpdaterService` (batch writes every 250ms)
- `PaperPnlRefresher` (direct writes every 1s)
- `RiskManagerService.update_paper_positions_pnl()` (every 1 minute)

**Readers:**
- `RiskManagerService.sync_position_pnl_from_redis()`
- `RiskManagerService.ensure_all_positions_in_redis()`

### 11.2 RedisTickCache

**Service:** `Live::RedisTickCache`
**Key Format:** `tick:#{segment}:#{security_id}`

**Data Structure:**

```json
{
  "ltp": 150.50,
  "prev_close": 148.00,
  "timestamp": 1234567890
}
```

**TTL:** 24 hours

**Writers:**
- `MarketFeedHub.handle_tick()` (every tick)

**Readers:**
- `RiskManagerService.get_paper_ltp()` (fallback)
- `ActiveCache.ensure_position_snapshot()` (fallback)

### 11.3 Peak Profit Cache

**Service:** `Positions::ActiveCache`
**Key Format:** `peak_profit:tracker:#{tracker_id}`

**Data Structure:**

```json
{
  "peak_profit_pct": 35.50,
  "updated_at": 1234567890
}
```

**TTL:** 7 days

**Writers:**
- `ActiveCache.handle_tick()` (when peak updated)
- `ActiveCache.add_position()` (on entry)

**Readers:**
- `ActiveCache.add_position()` (on entry, reload peaks)
- `ActiveCache.reload_peaks()` (on startup)

---

## 12. Session Checks

### 12.1 TradingSession::Service

**File:** `app/services/trading_session.rb`

**Methods:**

| Method               | Purpose                        | Time Range            |
| -------------------- | ------------------------------ | --------------------- |
| `entry_allowed?`     | Check if entry is allowed      | 9:20 AM - 3:15 PM IST |
| `should_force_exit?` | Check if exit should be forced | After 3:15 PM IST     |
| `market_closed?`     | Check if market is closed      | After 3:30 PM IST     |
| `in_session?`        | Check if in trading session    | 9:20 AM - 3:15 PM IST |

**Time Constants:**

```ruby
ENTRY_START_HOUR = 9
ENTRY_START_MINUTE = 20
EXIT_DEADLINE_HOUR = 15
EXIT_DEADLINE_MINUTE = 15
MARKET_CLOSE_HOUR = 15
MARKET_CLOSE_MINUTE = 30
```

### 12.2 Session Check Usage

**EntryGuard:**
```ruby
session_check = TradingSession::Service.entry_allowed?
return false unless session_check[:allowed]
```

**Signal::Scheduler:**
```ruby
return if TradingSession::Service.market_closed?
```

**RiskManagerService:**
```ruby
if TradingSession::Service.market_closed?
  active_count = PositionTracker.active.count
  if active_count.zero?
    sleep 60
    next
  end
end
```

**Session End Exit:**
```ruby
session_check = TradingSession::Service.should_force_exit?
return unless session_check[:should_exit]
# Exit all positions
```

---

## Complete Flow Diagram

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
         │         └──→ Start Monitoring Loop (500ms/5000ms)
         │
         └──→ Other Services...

[SIGNAL GENERATION LOOP]
         │
         ├──→ For each index:
         │         │
         │         ├──→ TradingSession.market_closed? → Skip
         │         │
         │         ├──→ Check enable_trend_scorer flag
         │         │         │
         │         │         ├──→ If enabled: TrendScorer.compute_direction()
         │         │         │         │
         │         │         │         └──→ If trend_score < 14: SKIP
         │         │         │
         │         │         └──→ If disabled: Signal::Engine.analyze_multi_timeframe()
         │         │                   (Legacy Supertrend+ADX path)
         │         │
         │         ├──→ ChainAnalyzer.select_candidates()
         │         │
         │         └──→ EntryGuard.try_enter()
         │                 │
         │                 ├──→ Session Check (9:20 AM - 3:15 PM)
         │                 ├──→ Daily Limits Check
         │                 ├──→ Exposure Check
         │                 ├──→ Cooldown Check
         │                 ├──→ Capital::Allocator.qty_for()
         │                 ├──→ Place Order (paper/live)
         │                 └──→ EntryManager.process_entry()
         │                         │
         │                         ├──→ DynamicRiskAllocator.risk_pct_for()
         │                         ├──→ ActiveCache.add_position()
         │                         ├──→ MarketFeedHub.subscribe_instrument()
         │                         └──→ BracketPlacer.place_bracket()

[MARKET DATA FLOW]
         │
         ├──→ WebSocket Tick Received
         │         │
         │         ├──→ TickCache.put(tick)
         │         ├──→ RedisTickCache.store_tick(tick)
         │         ├──→ ActiveCache.handle_tick(tick)
         │         │         │
         │         │         ├──→ position.update_ltp(ltp)
         │         │         ├──→ position.recalculate_pnl()
         │         │         └──→ Persist peak to Redis
         │         │
         │         └──→ PnlUpdaterService.cache_intermediate_pnl()

[PnL UPDATE FLOW]
         │
         ├──→ PaperPnlRefresher (1s interval)
         │         │
         │         └──→ Refresh paper positions → RedisPnlCache
         │
         ├──→ PnlUpdaterService (250ms flush)
         │         │
         │         └──→ Batch write queue → RedisPnlCache
         │
         └──→ RiskManagerService (1 minute)
                 │
                 └──→ Update paper positions → RedisPnlCache

[RISK MANAGEMENT LOOP]
         │
         ├──→ For each position:
         │         │
         │         ├──→ recalculate_position_metrics()
         │         │         │
         │         │         ├──→ Sync PnL from Redis
         │         │         └──→ Update peak if current > peak
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

[EOD HANDLING]
         │
         ├──→ TradingSession.should_force_exit? (3:15 PM IST)
         │         │
         │         └──→ enforce_session_end_exit()
         │                 │
         │                 └──→ Exit all positions
```

---

---

## 13. Redis UI

### 13.1 Overview

**Controller:** `RedisUiController`
**File:** `app/controllers/redis_ui_controller.rb`
**View:** `app/views/redis_ui/index.html.erb`
**Route:** `/redis_ui` (development only)

**Purpose:** Web interface for browsing and managing Redis keys in development environment.

### 13.2 Features

**Key Browsing:**
- Pattern-based search (e.g., `pnl:*`, `tick:*`, `*`)
- Database selection (0-15)
- Pagination support (SCAN cursor-based)
- Key type detection (string, hash, list, set, zset)
- TTL display

**Live Tables:**
- **PnL Keys Table:** Auto-refreshes every 2 seconds
  - Displays: Key, PnL (₹), PnL %, LTP, HWM, Updated, Actions
  - Color-coded: Green for positive, red for negative

- **Tick Keys Table:** Auto-refreshes every 2 seconds
  - Displays: Key, LTP, Volume, Timestamp, Updated, Actions

- **All Keys Table:** Configurable refresh interval (2s, 5s, 10s, 30s, 60s)
  - Displays: Key, Type, Size/Count, TTL, Actions

**Key Operations:**
- View key details (modal popup with full value)
- Delete keys (with confirmation)
- Redis server info display

### 13.3 Security

**Access Control:**
- Only available in `Rails.env.development?`
- Returns 403 Forbidden in production

**Implementation:**
```ruby
before_action :ensure_development

def ensure_development
  return if Rails.env.development?
  render json: { error: 'Redis UI is only available in development' }, status: :forbidden
end
```

### 13.4 Configuration

**Routes (development only):**
```ruby
if Rails.env.development?
  get 'redis_ui', to: 'redis_ui#index'
  get 'redis_ui/info', to: 'redis_ui#info'
  get 'redis_ui/:id', to: 'redis_ui#show', as: :redis_ui_key
  delete 'redis_ui/:id', to: 'redis_ui#destroy'
end
```

**ActionView Requirement:**
- Conditionally enabled in `config/application.rb`:
  ```ruby
  require "action_view/railtie" if Rails.env.development?
  ```

---

**Document Version:** 2.1
**Last Updated:** 2025-01-16 - Added TrendScorer toggle, market close checks, Redis UI
**Repository:** https://github.com/shubhamtaywade82/algo_scalper_api/tree/new_trailing
