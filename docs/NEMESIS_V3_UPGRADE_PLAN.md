# NEMESIS V3 UPGRADE PLAN
## Comprehensive Architecture Analysis & Implementation Roadmap

**Status**: ⚠️ **ANALYSIS COMPLETE - AWAITING APPROVAL**
**Date**: 2025-01-22
**No code changes have been made. This document is for review and approval only.**

---

## 1. ARCHITECTURE MAP SUMMARY

### 1.1 System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    TRADING SYSTEM SUPERVISOR                         │
│              (config/initializers/trading_supervisor.rb)            │
│                                                                      │
│  Services Registered (in order):                                    │
│  1. market_feed (MarketFeedHubService)                              │
│  2. signal_scheduler (Signal::Scheduler)                            │
│  3. risk_manager (Live::RiskManagerService)                         │
│  4. position_heartbeat (TradingSystem::PositionHeartbeat)           │
│  5. order_router (TradingSystem::OrderRouter)                       │
│  6. paper_pnl_refresher (Live::PaperPnlRefresher)                   │
│  7. exit_manager (Live::ExitEngine)                                 │
│  8. active_cache (ActiveCacheService)                               │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    MARKET DATA LAYER                                 │
│                                                                      │
│  Live::MarketFeedHub (Singleton)                                    │
│    ├─ WebSocket Connection (DhanHQ)                                 │
│    ├─ Tick Processing                                               │
│    ├─ Subscription Management (@subscribed_keys tracking)           │
│    └─ Callbacks → ActiveCache, TickCache, RedisTickCache            │
│                                                                      │
│  Caches:                                                            │
│    ├─ Live::TickCache (in-memory, module delegating to singleton)   │
│    ├─ Live::RedisTickCache (Redis-backed, persistent)               │
│    └─ Live::RedisPnlCache (Redis-backed, PnL tracking)              │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    SIGNAL GENERATION LAYER                           │
│                                                                      │
│  Signal::Scheduler (Thread: 'signal-scheduler')                     │
│    ├─ Period: 30 seconds (DEFAULT_PERIOD)                           │
│    ├─ Processes indices sequentially (5s stagger)                  │
│    └─ Strategy Engines:                                             │
│         ├─ OpenInterestBuyingEngine                                 │
│         ├─ MomentumBuyingEngine                                     │
│         ├─ BtstMomentumEngine                                       │
│         └─ SwingOptionBuyingEngine                                  │
│                                                                      │
│  Signal::Engine (Legacy fallback)                                   │
│    └─ Uses SupertrendAdxStrategy, SimpleMomentumStrategy, etc.      │
│                                                                      │
│  Options::DerivativeChainAnalyzer                                   │
│    ├─ Uses Derivative records (DB)                                  │
│    ├─ Merges with DhanHQ API option chain                           │
│    └─ Scores candidates (OI, IV, spread, volume)                     │
│                                                                      │
│  Options::StrikeSelector                                            │
│    ├─ Uses DerivativeChainAnalyzer                                  │
│    └─ Applies index-specific rules (NIFTY, BANKNIFTY, SENSEX)       │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    ENTRY LAYER                                      │
│                                                                      │
│  Entries::EntryGuard (Class methods)                                │
│    ├─ try_enter() - Main entry validation                           │
│    ├─ exposure_ok?() - Position limits                              │
│    ├─ cooldown_active?() - Cooldown checks                          │
│    └─ Calls Capital::Allocator.qty_for()                            │
│                                                                      │
│  Orders::EntryManager (NEW - NEMESIS V3)                           │
│    ├─ process_entry() - Orchestrates entry                          │
│    ├─ Calls EntryGuard.try_enter()                                  │
│    ├─ Calculates SL/TP (30% SL, 60% TP default)                     │
│    ├─ Adds to Positions::ActiveCache                                │
│    └─ Emits entry_filled event via Core::EventBus                   │
│                                                                      │
│  Capital::Allocator                                                 │
│    ├─ qty_for() - Quantity calculation                              │
│    ├─ Uses CAPITAL_BANDS (account size-based)                      │
│    ├─ Calculates by allocation % and risk %                         │
│    └─ Enforces lot size constraints                                 │
│                                                                      │
│  Orders::Placer                                                     │
│    ├─ buy_market!() - Places market buy orders                      │
│    ├─ Supports bracket orders (boProfitValue, boStopLossValue)       │
│    └─ Uses DhanHQ::Models::Order.create()                           │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    POSITION TRACKING LAYER                           │
│                                                                      │
│  PositionTracker (ActiveRecord Model)                                │
│    ├─ Stores: entry_price, quantity, status, high_water_mark_pnl    │
│    ├─ Polymorphic: watchable (Instrument or Derivative)             │
│    ├─ Callbacks: subscribe_to_feed, register_in_index               │
│    └─ Methods: trailing_stop_triggered?, ready_to_trail?            │
│                                                                      │
│  Positions::ActiveCache (Singleton)                                   │
│    ├─ In-memory cache (Concurrent::Map)                             │
│    ├─ PositionData struct (tracker_id, entry_price, sl_price, etc.) │
│    ├─ Subscribes to MarketFeedHub callbacks                         │
│    ├─ Updates LTP on every tick                                     │
│    └─ Tracks: high_water_mark, pnl, pnl_pct, trailing_stop_price    │
│                                                                      │
│  Live::PositionIndex (Singleton)                                    │
│    ├─ In-memory index (security_id => metadata array)               │
│    └─ Used by MarketFeedHub for tick routing                        │
│                                                                      │
│  Positions::HighWaterMark (Module)                                   │
│    ├─ trailing_threshold()                                           │
│    ├─ trailing_triggered?()                                         │
│    ├─ drawdown_from_hwm()                                           │
│    └─ should_lock_breakeven?()                                      │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    RISK & EXIT LAYER                                 │
│                                                                      │
│  Live::RiskManagerService (Thread: 'risk-manager')                  │
│    ├─ LOOP_INTERVAL: 5 seconds                                      │
│    ├─ monitor_loop() - Main monitoring                              │
│    ├─ enforce_hard_limits() - SL/TP enforcement                     │
│    ├─ enforce_trailing_stops() - Trailing stop logic                │
│    ├─ enforce_time_based_exit() - Time-based exits                  │
│    └─ Delegates to ExitEngine.execute_exit()                        │
│                                                                      │
│  Live::ExitEngine (Thread: 'exit-engine')                           │
│    ├─ execute_exit() - Executes exit orders                         │
│    ├─ Uses TradingSystem::OrderRouter                               │
│    └─ Marks PositionTracker as exited                               │
│                                                                      │
│  Orders::BracketPlacer (NEW - NEMESIS V3)                           │
│    ├─ place_bracket() - Initial SL/TP placement                    │
│    ├─ update_bracket() - Modify SL/TP                              │
│    ├─ move_to_breakeven() - Breakeven lock                          │
│    └─ move_to_trailing() - Trailing stop moves                      │
│                                                                      │
│  TradingSystem::OrderRouter                                         │
│    └─ exit_market() - Routes exit to appropriate gateway            │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    EVENT BUS (Core::EventBus)                        │
│                                                                      │
│  Events:                                                             │
│    ├─ :ltp - LTP updates                                            │
│    ├─ :entry_filled - Entry order filled                            │
│    ├─ :sl_hit - Stop loss hit                                       │
│    ├─ :tp_hit - Take profit hit                                    │
│    ├─ :trailing_triggered - Trailing stop triggered                │
│    ├─ :bracket_placed - Bracket orders placed                       │
│    └─ :bracket_modified - Bracket orders modified                   │
│                                                                      │
│  Subscribers:                                                        │
│    └─ Currently: Positions::ActiveCache (removed FeedListener)      │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.2 Data Flow

```
MarketFeedHub (WebSocket)
    │
    ├─→ TickCache (in-memory)
    ├─→ RedisTickCache (Redis)
    └─→ ActiveCache.handle_tick() [per-tick LTP updates]
            │
            └─→ PositionData.update_ltp()
                    │
                    └─→ recalculate_pnl() [updates HWM]

Signal::Scheduler (30s loop)
    │
    ├─→ Options::DerivativeChainAnalyzer.select_candidates()
    ├─→ Signal::Engines::*Engine.evaluate()
    └─→ Entries::EntryGuard.try_enter()
            │
            ├─→ Capital::Allocator.qty_for()
            ├─→ Orders::Placer.buy_market!()
            └─→ PositionTracker.create!()
                    │
                    └─→ Orders::EntryManager.process_entry()
                            │
                            ├─→ Positions::ActiveCache.add_position()
                            └─→ Core::EventBus.publish(:entry_filled)

Live::RiskManagerService (5s loop)
    │
    ├─→ enforce_hard_limits()
    ├─→ enforce_trailing_stops()
    └─→ Live::ExitEngine.execute_exit()
            │
            └─→ TradingSystem::OrderRouter.exit_market()
                    │
                    └─→ PositionTracker.mark_exited!()
```

### 1.3 Key Components Discovery

#### **Bootstrap & Supervisor**
- **File**: `config/initializers/trading_supervisor.rb`
- **Purpose**: Central service lifecycle management
- **Services**: 8 services registered and started sequentially
- **Thread Safety**: Uses `$trading_supervisor_started` global flag

#### **Market Feed**
- **File**: `app/services/live/market_feed_hub.rb`
- **Type**: Singleton
- **Features**: WebSocket connection, subscription tracking, tick callbacks
- **Caches**: TickCache (in-memory), RedisTickCache (persistent)

#### **Signal Generation**
- **File**: `app/services/signal/scheduler.rb`
- **Type**: Thread-based service (30s period)
- **Strategies**: 4 strategy engines (OI, Momentum, BTST, Swing)
- **Integration**: Uses `Options::DerivativeChainAnalyzer` for strike selection

#### **Entry Validation**
- **File**: `app/services/entries/entry_guard.rb`
- **Type**: Class methods (stateless)
- **Features**: Exposure checks, cooldown, LTP resolution, quantity allocation

#### **Capital Allocation**
- **File**: `app/services/capital/allocator.rb`
- **Type**: Class methods
- **Features**: Account-size-based bands, risk-based quantity calculation
- **Note**: Has `daily_max_loss_pct` in bands but NOT enforced

#### **Order Placement**
- **File**: `app/services/orders/placer.rb`
- **Type**: Class methods
- **Features**: Market orders, bracket orders (SL/TP in entry order)

#### **Position Tracking**
- **File**: `app/services/positions/active_cache.rb`
- **Type**: Singleton
- **Features**: In-memory cache, real-time LTP updates, HWM tracking
- **Data Structure**: `PositionData` struct with 15 fields

#### **Risk Management**
- **File**: `app/services/live/risk_manager_service.rb`
- **Type**: Thread-based service (5s loop)
- **Features**: PnL updates, SL/TP enforcement, trailing stops, time-based exits
- **Integration**: Delegates to `ExitEngine` for actual exits

#### **Exit Execution**
- **File**: `app/services/live/exit_engine.rb`
- **Type**: Thread-based service (currently idle loop)
- **Features**: Executes exit orders via `OrderRouter`

#### **Technical Indicators**
- **Files**:
  - `app/models/candle_series.rb` - Candle data structure with indicator methods
  - `app/services/indicators/calculator.rb` - Wrapper for CandleSeries
  - `app/services/indicators/supertrend.rb` - Supertrend implementation
  - `app/services/trading/indicators.rb` - RSI, ATR, Supertrend utilities
- **Libraries**: `ruby-technical-analysis`, `technical-analysis` gems

#### **Configuration**
- **File**: `config/algo.yml`
- **Structure**: YAML with indices, risk, signals, strategies
- **Loader**: `app/lib/algo_config.rb` (AlgoConfig.fetch)

### 1.4 Existing Patterns & Conventions

#### **Naming Conventions**
- Services: `Module::ServiceName` (e.g., `Live::RiskManagerService`)
- Models: `CamelCase` (e.g., `PositionTracker`)
- Files: `snake_case.rb`
- Methods: `snake_case`, predicates end with `?`

#### **Service Patterns**
- **Singleton Services**: Use `include Singleton` (MarketFeedHub, ActiveCache, EventBus)
- **Thread-based Services**: Have `start`/`stop` methods, use named threads
- **Stateless Services**: Class methods (EntryGuard, Allocator, Placer)
- **Service Adapters**: Wrap singletons for Supervisor (MarketFeedHubService, ActiveCacheService)

#### **Error Handling**
- Explicit `rescue StandardError`
- Logging with class context: `[ClassName] Message`
- Graceful degradation (return `nil` or empty collections)

#### **Thread Safety**
- `Concurrent::Map`, `Concurrent::Array`, `Concurrent::Set` for shared state
- `Mutex.new` for critical sections
- Named threads for debugging

#### **Configuration Access**
- `AlgoConfig.fetch` - Loads `config/algo.yml`
- Environment variables: `ENV['VAR']` with fallbacks
- Paper trading: `AlgoConfig.fetch.dig(:paper_trading, :enabled)`

### 1.5 Risky/Tightly Coupled Files (DO NOT MODIFY WITHOUT CAUTION)

1. **`config/initializers/trading_supervisor.rb`**
   - Critical: Service startup order
   - Risk: Rails reload issues (creates new supervisor on each reload)
   - Action: Extend, don't rewrite

2. **`app/services/live/market_feed_hub.rb`**
   - Critical: WebSocket connection management
   - Risk: Breaking tick distribution
   - Action: Extend subscription tracking, don't change core logic

3. **`app/models/position_tracker.rb`**
   - Critical: Database model with callbacks
   - Risk: Breaking position lifecycle
   - Action: Add fields/methods, don't remove existing

4. **`app/services/entries/entry_guard.rb`**
   - Critical: Entry validation logic
   - Risk: Breaking entry flow
   - Action: Extend validation, don't change core checks

5. **`app/services/capital/allocator.rb`**
   - Critical: Quantity calculation
   - Risk: Breaking position sizing
   - Action: Extend with dynamic risk, don't change core calculation

---

## 2. UPGRADE PLAN

### 2.1 Configuration/Constants Module

**New File**: `app/services/positions/trailing_config.rb`

**Purpose**: Central configuration for trailing model (extends Positions namespace)

**Content**:
```ruby
module Positions
  module TrailingConfig
    PEAK_DRAWDOWN_PCT = 5.0

    TIERS = [
      { threshold_pct: 5.0,  sl_offset_pct: -15.0 },
      { threshold_pct: 10.0, sl_offset_pct: -5.0 },
      { threshold_pct: 15.0, sl_offset_pct: 0.0 },
      { threshold_pct: 25.0, sl_offset_pct: 10.0 },
      { threshold_pct: 40.0, sl_offset_pct: 20.0 },
      { threshold_pct: 60.0, sl_offset_pct: 30.0 },
      { threshold_pct: 80.0, sl_offset_pct: 40.0 },
      { threshold_pct: 120.0, sl_offset_pct: 60.0 }
    ].freeze

    # Helper methods for tier lookup
    def self.sl_offset_for(profit_pct)
      # Returns SL offset % for given profit %
    end
  end
end
```

**Integration Point**: Accessible from all services via `Positions::TrailingConfig`

---

### 2.2 Step 1: TrendScorer

**New File**: `app/services/signal/trend_scorer.rb`

**Purpose**: Compute trend scores (PA_score, IND_score, MTF_score) and aggregate to trend_score (0-21). Note: VOL_score removed - volume is always 0 for indices/underlying spots.

**Dependencies**:
- `CandleSeries` (existing)
- `Indicators::Calculator` (existing)
- `Instrument` model (for multi-timeframe data)

**Methods**:
```ruby
module Signal
  class TrendScorer
    def initialize(instrument:, primary_tf: '1m', confirmation_tf: '5m')
      @instrument = instrument
      @primary_tf = primary_tf
      @confirmation_tf = confirmation_tf
    end

    def compute_trend_score
      # Returns: { trend_score: 0-26, breakdown: { pa: X, ind: Y, mtf: Z, vol: W } }
    end

    private

    def pa_score
      # Price action score (0-7)
      # Uses: CandleSeries patterns, structure breaks, momentum
    end

    def ind_score
      # Indicator score (0-7)
      # Uses: RSI, MACD, ADX, Supertrend from Indicators::Calculator
    end

    def mtf_score
      # Multi-timeframe score (0-7)
      # Uses: Primary TF vs Confirmation TF alignment
    end

    # VOL_score removed - volume is always 0 for indices/underlying spots
  end
end
```

**Integration Points**:
- Extends `CandleSeries` methods (don't modify existing)
- Uses `Indicators::Calculator` (existing)
- Accesses `Instrument#candle_series_for(timeframe)` (existing)

**Tests**: `spec/services/signal/trend_scorer_spec.rb`

**Risk**: LOW - New service, no existing code modified

---

### 2.3 Step 2: IndexSelector

**New File**: `app/services/signal/index_selector.rb`

**Purpose**: Compute trend_score per index, pick best index, apply thresholds and tie-breakers

**Dependencies**:
- `Signal::TrendScorer` (Step 1)
- `AlgoConfig.fetch[:indices]` (existing)

**Methods**:
```ruby
module Signal
  class IndexSelector
    def initialize(config: {})
      @config = config
      @min_trend_score = config[:min_trend_score] || 15
    end

    def select_best_index
      # Returns: { index_key: :NIFTY, trend_score: 20, reason: "..." } or nil
    end

    private

    def score_all_indices
      # Returns: Array of { index_key, trend_score, breakdown }
    end

    def apply_tie_breakers(scored_indices)
      # Applies: volume, liquidity, recent performance
    end
  end
end
```

**Integration Points**:
- Uses `IndexInstrumentCache.instance.get_or_fetch()` (existing)
- Integrates with `Signal::Scheduler` (extend, don't modify)

**Tests**: `spec/services/signal/index_selector_spec.rb`

**Risk**: LOW - New service, integrates with existing scheduler

---

### 2.4 Step 3: PremiumFilter

**New File**: `app/services/options/premium_filter.rb`

**Purpose**: Enforce index-specific premium bands and liquidity/spread checks

**Dependencies**:
- `Options::IndexRules::*` (existing: Nifty, Banknifty, Sensex)
- `Options::StrikeSelector` (existing)

**Methods**:
```ruby
module Options
  class PremiumFilter
    def initialize(index_key:)
      @index_key = index_key
      @rules = IndexRules.const_get(index_key.to_s.camelize).new
    end

    def valid?(candidate)
      # Returns: true if candidate passes premium, liquidity, spread checks
    end

    private

    def premium_in_band?(premium)
      # Uses: @rules.min_premium, @rules.max_premium (if exists)
    end

    def liquidity_ok?(candidate)
      # Uses: @rules.min_volume, OI checks
    end

    def spread_ok?(candidate)
      # Uses: @rules.max_spread_pct
    end
  end
end
```

**Integration Points**:
- Extends `Options::StrikeSelector` (add filter step)
- Uses existing `Options::IndexRules::*` classes

**Tests**: `spec/services/options/premium_filter_spec.rb`

**Risk**: LOW - New service, extends existing selector

---

### 2.5 Step 4: Enhanced Strike Selection Policy

**File to Extend**: `app/services/options/strike_selector.rb`

**Changes**:
- Add `strike_policy` parameter (default: :atm, allow :atm_plus_1, :atm_plus_2)
- Enforce: Default ATM, allow 1OTM/2OTM per trend thresholds, disallow deeper OTM
- Integrate with `TrendScorer` to determine allowed OTM depth

**Method Signature Change**:
```ruby
def select(index_key:, direction:, strength: nil, timeframe: nil, meta: {}, strike_policy: :atm)
  # strike_policy: :atm, :atm_plus_1, :atm_plus_2 (based on trend_score)
end
```

**Integration Points**:
- Uses existing `DerivativeChainAnalyzer.select_candidates()`
- Filters candidates by strike distance from ATM

**Tests**: Update `spec/services/options/strike_selector_spec.rb`

**Risk**: MEDIUM - Modifying existing service, but adding optional parameter (backward compatible)

---

### 2.6 Step 5: DynamicRiskAllocator

**New File**: `app/services/capital/dynamic_risk_allocator.rb`

**Purpose**: Map index + trend strength → risk_pct returned to allocation logic

**Dependencies**:
- `Capital::Allocator` (existing)
- `AlgoConfig.fetch[:risk]` (existing)

**Methods**:
```ruby
module Capital
  class DynamicRiskAllocator
    def initialize(config: {})
      @config = config
    end

    def risk_pct_for(index_key:, trend_score:)
      # Returns: risk_pct (0.0 to 1.0) based on index and trend strength
      # Mapping: Higher trend_score → higher risk_pct (capped)
    end

    private

    def base_risk_for_index(index_key)
      # Gets base risk from Capital::Allocator.deployment_policy or index config
    end

    def scale_by_trend(trend_score, base_risk)
      # Scales base_risk by trend_score (0-26 → multiplier 0.5x to 1.5x)
    end
  end
end
```

**Integration Points**:
- Extends `Capital::Allocator.qty_for()` (add optional `risk_pct` parameter)
- Called by `EntryManager` before quantity calculation

**Tests**: `spec/services/capital/dynamic_risk_allocator_spec.rb`

**Risk**: MEDIUM - Extends existing allocator, but with optional parameter

---

### 2.7 Step 6: Upgrade EntryManager

**File to Extend**: `app/services/orders/entry_manager.rb`

**Changes**:
1. Integrate `DynamicRiskAllocator` to get risk_pct
2. Pass risk_pct to `Capital::Allocator.qty_for()` (if supported)
3. Reject if qty < 1 lot-equivalent
4. Call `BracketPlacer.place_bracket()` after entry

**Method Changes**:
```ruby
def process_entry(signal_result:, index_cfg:, direction:, scale_multiplier: 1, trend_score: nil)
  # ... existing code ...

  # NEW: Get dynamic risk
  risk_pct = if trend_score
    Capital::DynamicRiskAllocator.new.risk_pct_for(
      index_key: index_cfg[:key],
      trend_score: trend_score
    )
  else
    nil # Use default from Allocator
  end

  # NEW: Reject if qty < 1 lot
  if quantity < pick[:lot_size]
    return failure_result("Quantity #{quantity} < 1 lot (#{pick[:lot_size]})")
  end

  # NEW: Place bracket orders
  bracket_result = Orders::BracketPlacer.instance.place_bracket(
    tracker: tracker,
    sl_price: sl_price,
    tp_price: tp_price,
    reason: 'initial_bracket'
  )

  # ... rest of existing code ...
end
```

**Integration Points**:
- Extends existing `process_entry()` method
- Calls `BracketPlacer` (Step 7)
- Integrates with `DynamicRiskAllocator` (Step 5)

**Tests**: Update `spec/services/orders/entry_manager_spec.rb`

**Risk**: MEDIUM - Modifying existing service, but additive changes

---

### 2.8 Step 7: Harden BracketPlacer

**File to Extend**: `app/services/orders/bracket_placer.rb`

**Changes**:
1. Ensure SL = 30% below entry (fixed)
2. Ensure TP = 60% above entry (fixed)
3. Atomically place bracket orders (if DhanHQ supports)
4. Cache position metadata including `peak_profit_pct` in `ActiveCache`

**Method Changes**:
```ruby
def place_bracket(tracker:, sl_price:, tp_price:, reason: nil)
  # ENSURE: sl_price = entry * 0.70, tp_price = entry * 1.60
  entry = tracker.entry_price.to_f
  sl_price = entry * 0.70 unless sl_price
  tp_price = entry * 1.60 unless tp_price

  # NEW: Place bracket order via Orders::Placer (if not already placed with entry)
  # Note: DhanHQ bracket orders are typically placed WITH entry order
  # This is for cases where bracket needs to be placed separately

  # NEW: Update ActiveCache with peak_profit_pct = 0 (initial)
  @active_cache.update_position(
    tracker.id,
    sl_price: sl_price,
    tp_price: tp_price,
    peak_profit_pct: 0.0
  )

  # ... rest of existing code ...
end
```

**Integration Points**:
- Extends existing `place_bracket()` method
- Updates `Positions::ActiveCache` (add `peak_profit_pct` field)

**Tests**: Update `spec/services/orders/bracket_placer_spec.rb`

**Risk**: MEDIUM - Modifying existing service, adding new field to ActiveCache

---

### 2.9 Step 8: TrailingEngine

**New File**: `app/services/live/trailing_engine.rb`

**Purpose**: Per-tick trailing stop management with tiered SL offsets

**Dependencies**:
- `Positions::ActiveCache` (existing)
- `Positions::TrailingConfig` (Step 0)
- `Orders::BracketPlacer` (existing)

**Methods**:
```ruby
module Live
  class TrailingEngine
    def initialize(active_cache: Positions::ActiveCache.instance,
                   bracket_placer: Orders::BracketPlacer.instance)
      @active_cache = active_cache
      @bracket_placer = bracket_placer
    end

    def process_tick(position_data, exit_engine: nil)
      # Called per-tick for each position
      # 1. Update peak_profit_pct
      # 2. Check peak-drawdown (Step 9 - called first)
      # 3. Apply tiered SL offsets based on profit %
      # 4. Update ActiveCache and BracketPlacer
    end

    private

    def update_peak(position_data)
      # Updates peak_profit_pct if current > peak
    end

    def calculate_tiered_sl(entry_price, current_profit_pct)
      # Uses Positions::TrailingConfig.TIERS
      # Returns: new_sl_price based on current profit % tier
    end

    def should_move_sl?(position_data, new_sl_price)
      # Only move SL if new_sl > current_sl (for long positions)
    end
  end
end
```

**Integration Points**:
- Called by `RiskManagerService` per-tick (extend `monitor_loop`)
- Updates `Positions::ActiveCache` (extend `PositionData` struct)
- Calls `Orders::BracketPlacer.update_bracket()`

**Tests**: `spec/services/live/trailing_engine_spec.rb`

**Risk**: MEDIUM - New service, integrates with existing risk loop

---

### 2.10 Step 9: Peak-Drawdown Immediate Exit

**File to Extend**: `app/services/live/trailing_engine.rb` (Step 8)

**Changes**:
- Add `check_peak_drawdown()` method
- Called BEFORE any SL adjustments in `process_tick()`
- If `peak_profit_pct - current_profit_pct >= 5.0` → immediate market exit

**Method**:
```ruby
def check_peak_drawdown(position_data, exit_engine)
  peak = position_data.peak_profit_pct || 0.0
  current = position_data.pnl_pct || 0.0
  drawdown = peak - current

  if drawdown >= Positions::TrailingConfig::PEAK_DRAWDOWN_PCT
    # Immediate exit - no candle close wait
    tracker = PositionTracker.find(position_data.tracker_id)
    exit_engine.execute_exit(tracker, "peak_drawdown_exit (drawdown: #{drawdown.round(2)}%)")
    return true # Indicates exit was triggered
  end

  false
end
```

**Integration Points**:
- Called first in `TrailingEngine.process_tick()`
- Uses `Live::ExitEngine.execute_exit()` (existing)

**Tests**: `spec/services/live/trailing_engine_spec.rb` (add peak-drawdown tests)

**Risk**: MEDIUM - Critical exit logic, must be idempotent

---

### 2.11 Step 10: Integrate TrailingEngine into RiskManager

**File to Extend**: `app/services/live/risk_manager_service.rb`

**Changes**:
1. Add `TrailingEngine` instance
2. In `monitor_loop()`, call `TrailingEngine.process_tick()` for each position
3. Ensure peak-check runs FIRST (before SL adjustments)
4. Integrate with existing `enforce_trailing_stops()` (may replace or enhance)

**Method Changes**:
```ruby
def monitor_loop(last_paper_pnl_update)
  # ... existing PnL update code ...

  # NEW: Process trailing for all active positions
  @trailing_engine ||= Live::TrailingEngine.new
  Positions::ActiveCache.instance.all_positions.each do |position|
    # Peak-drawdown check happens inside TrailingEngine.process_tick()
    @trailing_engine.process_tick(position, exit_engine: @exit_engine)
  rescue StandardError => e
    Rails.logger.error("[RiskManager] TrailingEngine error: #{e.class} - #{e.message}")
  end

  # ... existing enforcement code (may be redundant now) ...
end
```

**Integration Points**:
- Extends existing `monitor_loop()` method
- Uses `Positions::ActiveCache` (existing)
- Delegates to `ExitEngine` (existing)

**Tests**: Update `spec/services/live/risk_manager_service_spec.rb`

**Risk**: MEDIUM - Modifying critical risk loop, but additive integration

---

### 2.12 Step 11: DailyMaxLoss & TradeFrequencyLimiter

**New File**: `app/services/live/daily_limits.rb`

**Purpose**: Per-index and global caps, persisted counters, auto-lock behavior

**Dependencies**:
- Redis (for persistent counters)
- `AlgoConfig.fetch[:risk]` (existing)

**Methods**:
```ruby
module Live
  class DailyLimits
    def initialize(redis: Redis.current)
      @redis = redis
    end

    def can_trade?(index_key:)
      # Returns: { allowed: true/false, reason: "..." }
      # Checks: daily_loss_limit, trade_frequency_limit
    end

    def record_loss(index_key:, amount:)
      # Increments daily loss counter for index and global
    end

    def record_trade(index_key:)
      # Increments trade count for index and global
    end

    def reset_daily_counters
      # Called at start of trading day (scheduled job)
    end

    private

    def daily_loss_key(index_key)
      "daily_limits:loss:#{Date.today}:#{index_key}"
    end

    def daily_trades_key(index_key)
      "daily_limits:trades:#{Date.today}:#{index_key}"
    end
  end
end
```

**Integration Points**:
- Called by `Entries::EntryGuard.try_enter()` (extend validation)
- Called by `Live::RiskManagerService` (record losses)
- Called by `Orders::EntryManager` (record trades)

**Tests**: `spec/services/live/daily_limits_spec.rb`

**Risk**: LOW - New service, integrates with existing validation

---

### 2.13 Step 12: Recovery Logic (Persist/Reload Peak Values)

**File to Extend**: `app/services/positions/active_cache.rb`

**Changes**:
1. Add `persist_peak()` method (saves to Redis)
2. Add `reload_peaks()` method (loads from Redis on startup)
3. Call `persist_peak()` whenever `peak_profit_pct` is updated
4. Call `reload_peaks()` in `start!()` method

**Method Changes**:
```ruby
def persist_peak(tracker_id, peak_profit_pct)
  redis_key = "position_peaks:#{tracker_id}"
  Redis.current.setex(redis_key, 86400 * 7, peak_profit_pct.to_s) # 7 days TTL
end

def reload_peaks
  PositionTracker.active.find_each do |tracker|
    redis_key = "position_peaks:#{tracker.id}"
    peak = Redis.current.get(redis_key)
    next unless peak

    position = get_by_tracker_id(tracker.id)
    next unless position

    position.peak_profit_pct = peak.to_f
  end
end
```

**Integration Points**:
- Extends existing `ActiveCache` service
- Uses Redis (existing infrastructure)

**Tests**: Update `spec/services/positions/active_cache_spec.rb`

**Risk**: LOW - Extends existing cache, additive functionality

---

## 3. RISK/IMPACT ANALYSIS PER STEP

### Step 0: Configuration Module
- **Risk**: NONE
- **Impact**: None (new file in Positions namespace)
- **Breaking Changes**: None
- **Rollback**: Delete file

### Step 1: TrendScorer
- **Risk**: LOW
- **Impact**: New service in Signal namespace, no existing code modified
- **Breaking Changes**: None
- **Rollback**: Delete file, remove from IndexSelector

### Step 2: IndexSelector
- **Risk**: LOW
- **Impact**: New service in Signal namespace, optional integration with Scheduler
- **Breaking Changes**: None (can be feature-flagged)
- **Rollback**: Remove from Scheduler integration

### Step 3: PremiumFilter
- **Risk**: LOW
- **Impact**: New service in Options namespace, extends existing StrikeSelector
- **Breaking Changes**: None (optional filter step)
- **Rollback**: Remove filter step from StrikeSelector

### Step 4: Enhanced Strike Selection
- **Risk**: MEDIUM
- **Impact**: Modifies existing StrikeSelector, but backward compatible
- **Breaking Changes**: None (optional parameter)
- **Rollback**: Revert parameter addition

### Step 5: DynamicRiskAllocator
- **Risk**: MEDIUM
- **Impact**: New service in Capital namespace, extends Capital::Allocator usage
- **Breaking Changes**: None (optional parameter)
- **Rollback**: Remove risk_pct parameter from Allocator calls

### Step 6: Upgrade EntryManager
- **Risk**: MEDIUM
- **Impact**: Modifies entry flow, but additive changes
- **Breaking Changes**: None (existing flow preserved)
- **Rollback**: Revert method changes

### Step 7: Harden BracketPlacer
- **Risk**: MEDIUM
- **Impact**: Modifies bracket placement, adds peak_profit_pct field
- **Breaking Changes**: None (additive)
- **Rollback**: Revert changes, remove peak_profit_pct field

### Step 8: TrailingEngine
- **Risk**: MEDIUM
- **Impact**: New service in Live namespace, integrates with RiskManager
- **Breaking Changes**: None (additive integration)
- **Rollback**: Remove from RiskManager integration

### Step 9: Peak-Drawdown Exit
- **Risk**: MEDIUM-HIGH
- **Impact**: Critical exit logic, must be idempotent
- **Breaking Changes**: None (additive)
- **Rollback**: Remove peak-drawdown check from TrailingEngine

### Step 10: Integrate TrailingEngine
- **Risk**: MEDIUM
- **Impact**: Modifies critical RiskManager loop
- **Breaking Changes**: None (additive, existing logic preserved)
- **Rollback**: Remove TrailingEngine calls from monitor_loop

### Step 11: DailyLimits
- **Risk**: LOW
- **Impact**: New service in Live namespace, integrates with validation
- **Breaking Changes**: None (additive validation)
- **Rollback**: Remove from EntryGuard validation

### Step 12: Recovery Logic
- **Risk**: LOW
- **Impact**: Extends ActiveCache, additive functionality
- **Breaking Changes**: None
- **Rollback**: Remove persist/reload methods

---

## 4. TESTING STRATEGY

### 4.1 Unit Tests (RSpec)

Each new service/module will have:
- **File**: `spec/services/<namespace>/<service_name>_spec.rb` (matching namespace)
- **Coverage**: Edge cases, boundary conditions, error handling
- **Fixtures**: Use FactoryBot for test data

### 4.2 Integration Tests

**File**: `spec/integration/nemesis_v3_flow_spec.rb`

**Scenarios**:
1. Full flow: Signal → Entry → Trailing → Exit
2. Peak-drawdown exit trigger
3. Tiered SL moves
4. Daily limits enforcement
5. Recovery after restart

### 4.3 Manual Validation Scripts

**Directory**: `scripts/test_services/`

**New Scripts**:
- `test_trend_scorer.rb` - Verify scoring logic (Signal::TrendScorer)
- `test_index_selector.rb` - Verify index selection (Signal::IndexSelector)
- `test_trailing_engine.rb` - Simulate tick sequences (Live::TrailingEngine)
- `test_peak_drawdown.rb` - Verify immediate exit (Live::TrailingEngine)
- `test_daily_limits.rb` - Verify limit enforcement (Live::DailyLimits)

### 4.4 Tick Sequence Simulation

**File**: `scripts/test_services/test_trailing_simulation.rb`

**Purpose**: Simulate tick sequences that:
- Cause trailing tiers to engage
- Hit peak-drawdown exit
- Verify no double-exit (idempotency)

---

## 5. FILES TO CREATE/EXTEND

### 5.1 New Files (13 files)

**Namespace Mapping** (using existing namespaces):
- `Positions::` - Position-related services (TrailingConfig)
- `Signal::` - Signal generation services (TrendScorer, IndexSelector)
- `Options::` - Options-related services (PremiumFilter)
- `Capital::` - Capital allocation services (DynamicRiskAllocator)
- `Live::` - Live trading services (TrailingEngine, DailyLimits)

1. `app/services/positions/trailing_config.rb` - Configuration constants
2. `app/services/signal/trend_scorer.rb` - Trend scoring
3. `app/services/signal/index_selector.rb` - Index selection
4. `app/services/options/premium_filter.rb` - Premium filtering
5. `app/services/capital/dynamic_risk_allocator.rb` - Dynamic risk
6. `app/services/live/trailing_engine.rb` - Trailing logic
7. `app/services/live/daily_limits.rb` - Daily limits
8. `spec/services/signal/trend_scorer_spec.rb` - Tests
9. `spec/services/signal/index_selector_spec.rb` - Tests
10. `spec/services/options/premium_filter_spec.rb` - Tests
11. `spec/services/capital/dynamic_risk_allocator_spec.rb` - Tests
12. `spec/services/live/trailing_engine_spec.rb` - Tests
13. `spec/services/live/daily_limits_spec.rb` - Tests

### 5.2 Files to Extend (8 files)

1. `app/services/options/strike_selector.rb` - Add strike policy
2. `app/services/orders/entry_manager.rb` - Integrate risk allocator, bracket placer
3. `app/services/orders/bracket_placer.rb` - Add peak_profit_pct tracking
4. `app/services/positions/active_cache.rb` - Add peak_profit_pct field, persist/reload
5. `app/services/live/risk_manager_service.rb` - Integrate TrailingEngine
6. `app/services/capital/allocator.rb` - Add optional risk_pct parameter
7. `app/services/entries/entry_guard.rb` - Add DailyLimits validation
8. `spec/services/orders/entry_manager_spec.rb` - Update tests

### 5.3 Configuration Updates

1. `config/algo.yml` - Add NEMESIS V3 configuration section (optional)

---

## 6. IMPLEMENTATION SEQUENCE

### Phase 1: Foundation (Steps 0-3)
- Step 0: Configuration module
- Step 1: TrendScorer
- Step 2: IndexSelector
- Step 3: PremiumFilter

**Duration**: ~2-3 days
**Risk**: LOW
**Dependencies**: None

### Phase 2: Entry Enhancement (Steps 4-7)
- Step 4: Enhanced strike selection
- Step 5: DynamicRiskAllocator
- Step 6: Upgrade EntryManager
- Step 7: Harden BracketPlacer

**Duration**: ~3-4 days
**Risk**: MEDIUM
**Dependencies**: Phase 1

### Phase 3: Trailing & Exit (Steps 8-10)
- Step 8: TrailingEngine
- Step 9: Peak-drawdown exit
- Step 10: Integrate TrailingEngine

**Duration**: ~3-4 days
**Risk**: MEDIUM-HIGH
**Dependencies**: Phase 2

### Phase 4: Limits & Recovery (Steps 11-12)
- Step 11: DailyLimits
- Step 12: Recovery logic

**Duration**: ~2 days
**Risk**: LOW
**Dependencies**: Phase 2

### Phase 5: Testing & Validation
- Unit tests for all new services
- Integration tests
- Manual validation scripts
- Tick sequence simulations

**Duration**: ~3-4 days
**Risk**: LOW
**Dependencies**: All phases

---

## 7. CRITICAL SAFETY MEASURES

### 7.1 Idempotency
- All exit operations MUST be idempotent
- Use per-position locks (Mutex) before exit/SL modifications
- Check position status before executing exit

### 7.2 Race Conditions
- Use `Concurrent::Map` for shared state
- Use `Mutex` for critical sections
- Ensure thread-safe access to `ActiveCache`

### 7.3 Backward Compatibility
- All new parameters are optional
- Existing flows remain unchanged
- Feature flags for gradual rollout

### 7.4 Error Handling
- Explicit `rescue StandardError`
- Logging with class context
- Graceful degradation (return `nil` or empty collections)

### 7.5 Testing
- Unit tests for all new services
- Integration tests for critical flows
- Manual validation before production

---

## 8. APPROVAL CHECKLIST

Before proceeding with implementation, please confirm:

- [ ] Architecture map is accurate
- [ ] Upgrade plan is acceptable
- [ ] Risk assessment is understood
- [ ] File locations are appropriate
- [ ] Integration points are correct
- [ ] Testing strategy is adequate
- [ ] Safety measures are sufficient

---

## 9. EXPLICIT STATEMENT

**⚠️ NO CODE WILL BE CHANGED UNTIL I RECEIVE EXPLICIT APPROVAL.**

This document is for review only. All code changes will be implemented sequentially, with diffs and tests provided after each step, and will wait for approval before proceeding to the next step.

---

## 10. NEXT STEPS (AFTER APPROVAL)

1. Implement Step 0 (Configuration module)
2. Provide diff and tests
3. Wait for approval
4. Implement Step 1 (TrendScorer)
5. Provide diff and tests
6. Wait for approval
7. Continue sequentially...

---

**END OF UPGRADE PLAN**

