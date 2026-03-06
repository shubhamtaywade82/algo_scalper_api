# Default Flow - What Runs When Rails Server Starts

**Last Updated**: Current
**Purpose**: Document the default active flow when starting Rails server (`rails s` or `./bin/dev`)

---

## 🚀 **Default Startup Flow**

### **1. Service Initialization** (via `trading_supervisor.rb`)

When Rails server starts, the `TradingSystem::Supervisor` initializes and registers these services:

```ruby
# Services registered (in order):
1. :market_feed          → MarketFeedHubService (WebSocket connection)
2. :signal_scheduler     → Signal::Scheduler (Signal generation loop)
3. :risk_manager         → Live::RiskManagerService (Position monitoring)
4. :position_heartbeat   → TradingSystem::PositionHeartbeat
5. :order_router         → TradingSystem::OrderRouter
6. :paper_pnl_refresher  → Live::PaperPnlRefresher
7. :exit_manager         → Live::ExitEngine (Exit execution)
8. :active_cache         → ActiveCacheService (Position cache)
9. :reconciliation       → Live::ReconciliationService (Data consistency)
```

### **2. Market Status Check**

The supervisor checks if market is closed:

```ruby
market_closed = TradingSession::Service.market_closed?
```

**If Market is CLOSED:**
- ✅ Only `MarketFeedHub` starts (WebSocket connection for data feed)
- ❌ All other services remain stopped
- **Reason**: No trading activity when market is closed

**If Market is OPEN:**
- ✅ **ALL services start** via `supervisor.start_all`
- ✅ Active positions are subscribed to `MarketFeedHub` for real-time ticks

---

## 📊 **Default Signal Generation Flow**

### **Active Path: Supertrend + ADX (Traditional)**

**Default Configuration** (`config/algo.yml`):
```yaml
signals:
  enable_supertrend_signal: true      # ✅ DEFAULT: Enabled
  enable_adx_filter: true              # ✅ DEFAULT: Enabled
  enable_confirmation_timeframe: true  # ✅ DEFAULT: Enabled
  use_multi_indicator_strategy: false  # ❌ DEFAULT: Disabled
  use_strategy_recommendations: false  # ❌ DEFAULT: Disabled (not in config, defaults to false)
```

### **Signal::Engine.run_for() Decision Tree**

When `Signal::Scheduler` calls `Signal::Engine.run_for()` for each index:

```
1. Check use_strategy_recommendations (default: false)
   └─ If true → Use StrategyRecommender.best_for_index()
   └─ If false → Continue to step 2

2. Check use_multi_indicator_strategy (default: false)
   └─ If true → Use MultiIndicatorStrategy with modular indicators
   └─ If false → Continue to step 3

3. Check enable_supertrend_signal (default: true) ✅ DEFAULT PATH
   └─ If true → Use Supertrend + ADX analysis
      ├─ Primary timeframe: 1m (from config)
      ├─ ADX filter: Enabled (min_strength: 18 for NIFTY, per-index config)
      └─ Confirmation timeframe: 5m (if enable_confirmation_timeframe: true)
```

### **Default Signal Generation Details**

**Primary Analysis (1m timeframe):**
- ✅ **Supertrend** indicator (period: 7, multiplier: 3.0)
- ✅ **ADX filter** enabled (min_strength: 18 for NIFTY, 18 for BANKNIFTY)
- ✅ Generates directional signal (bullish/bearish/avoid)

**Confirmation Analysis (5m timeframe):**
- ✅ **Supertrend** indicator (same config)
- ✅ **ADX filter** enabled (min_strength: 11 for NIFTY, 31 for BANKNIFTY)
- ✅ Confirms primary signal direction

**Signal Validation:**
- ✅ **NoTradeEngine** validation (Phase 1: Quick pre-check)
- ✅ **NoTradeEngine** validation (Phase 2: Detailed validation after signal)

**Entry Flow:**
- ✅ **Entries::EntryGuard** validates and places entry
- ✅ **Orders::Placer** places bracket orders
- ✅ **PositionTracker** created and tracked

---

## 🔄 **Complete Default Flow Diagram**

```
┌─────────────────────────────────────────────────────────────┐
│  Rails Server Starts (rails s or ./bin/dev)                 │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  TradingSystem::Supervisor Initializes                      │
│  - Registers 9 services                                     │
│  - Checks market status                                     │
└────────────────────┬────────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
    Market OPEN?            Market CLOSED?
         │                       │
         ▼                       ▼
┌──────────────────┐    ┌──────────────────┐
│ Start ALL Services│    │ Start MarketFeed │
│                  │    │ Only (WebSocket) │
└────────┬─────────┘    └──────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│  Signal::Scheduler.start()                                   │
│  - Loop every 30 seconds (DEFAULT_PERIOD)                    │
│  - Process each index: NIFTY, BANKNIFTY, SENSEX              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Signal::Engine.run_for(index_cfg)                           │
│                                                              │
│  Decision Path:                                             │
│  1. use_strategy_recommendations? → false (skip)            │
│  2. use_multi_indicator_strategy? → false (skip)            │
│  3. enable_supertrend_signal? → true ✅ DEFAULT PATH        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Supertrend + ADX Analysis (1m primary, 5m confirmation)     │
│  - Primary: 1m Supertrend + ADX filter (min_strength: 18)   │
│  - Confirmation: 5m Supertrend + ADX filter (min_strength)  │
│  - Generates: bullish/bearish/avoid signal                   │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  NoTradeEngine Validation (Phase 1: Quick pre-check)        │
│  - Validates 11 no-trade conditions                         │
│  - Returns quick result with option chain data               │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Signal Generation (if NoTradeEngine passes)                 │
│  - Options chain analysis                                   │
│  - Strike selection                                         │
│  - Premium filtering                                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  NoTradeEngine Validation (Phase 2: Detailed validation)     │
│  - Full validation with all context                         │
│  - Final go/no-go decision                                  │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Entries::EntryGuard.try_enter()                            │
│  - Capital allocation                                       │
│  - Position limits check                                    │
│  - Entry execution                                          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Orders::Placer.place_bracket_order()                        │
│  - Places bracket order via Gateway                         │
│  - Creates PositionTracker                                  │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Position Tracking & Risk Management                        │
│  - PositionTracker.active → tracked                        │
│  - ActiveCache.add_position()                               │
│  - RiskManagerService monitors position                     │
│  - MarketFeedHub subscribes to instrument                   │
└─────────────────────────────────────────────────────────────┘
```

---

## ⚙️ **Default Configuration Values**

### **Signal Generation**
- **Primary Timeframe**: `1m` (1-minute candles)
- **Confirmation Timeframe**: `5m` (5-minute candles) - **Enabled by default**
- **Supertrend Config**: `period: 7, multiplier: 3.0`
- **ADX Filter**: **Enabled** with per-index thresholds:
  - NIFTY: `primary_min_strength: 14, confirmation_min_strength: 11`
  - BANKNIFTY: `primary_min_strength: 18, confirmation_min_strength: 31`

### **Strategy Selection**
- **Strategy Recommendations**: **Disabled** (`use_strategy_recommendations: false`)
- **Multi-Indicator Strategy**: **Disabled** (`use_multi_indicator_strategy: false`)
- **Default Strategy**: **Supertrend + ADX** (traditional path)

### **Feature Flags** (from `config/algo.yml`)
```yaml
feature_flags:
  enable_direction_before_chain: true      # ✅ Enabled
  enable_trend_scorer: false                # ❌ Disabled (uses legacy path)
  enable_auto_subscribe_unsubscribe: true   # ✅ Enabled
  enable_demand_driven_services: true      # ✅ Enabled
  enable_underlying_aware_exits: false     # ❌ Disabled
  enable_peak_drawdown_activation: false   # ❌ Disabled
  auto_paper_on_insufficient_balance: false # ❌ Disabled
```

### **Paper Trading**
- **Paper Trading**: **Enabled by default** (`paper_trading.enabled: true`)
- **Paper Balance**: `₹100,000` (default)

---

## 📋 **Service Startup Order**

When market is **OPEN**, services start in this order:

1. **MarketFeedHub** - WebSocket connection to DhanHQ
2. **Signal::Scheduler** - Signal generation loop (30s interval)
3. **RiskManagerService** - Position monitoring loop
4. **PositionHeartbeat** - Position health checks
5. **OrderRouter** - Order routing (no-op start)
6. **PaperPnlRefresher** - Paper position PnL updates
7. **ExitEngine** - Exit execution (idle thread)
8. **ActiveCache** - Position cache (subscribes to MarketFeedHub)
9. **ReconciliationService** - Data consistency checks

---

## 🔍 **Key Default Behaviors**

### **Signal Generation**
- ✅ Uses **1m Supertrend + ADX** analysis (primary)
- ✅ Uses **5m Supertrend + ADX** confirmation (enabled)
- ✅ **ADX filter is enabled** (filters weak trends)
- ❌ Does NOT use strategy recommendations
- ❌ Does NOT use multi-indicator system
- ✅ **NoTradeEngine validation** runs in 2 phases

### **Risk Management**
- ✅ **All 9 risk rules** active (from `RuleFactory.create_engine()`)
- ✅ **Trailing stops** enabled (activation threshold: 10% by default)
- ✅ **Stop loss** and **take profit** rules active
- ✅ **Peak drawdown** rule active (but activation gating disabled)
- ❌ **Underlying-aware exits** disabled by default

### **Position Management**
- ✅ **ActiveCache** tracks all active positions in-memory
- ✅ **MarketFeedHub** subscribes to active position instruments
- ✅ **PnL updates** via `PnlUpdaterService` (demand-driven)
- ✅ **Reconciliation** runs every 5 seconds

---

## 🎯 **Summary**

**Default Active Flow:**
1. **Signal Generation**: Supertrend + ADX (1m primary, 5m confirmation)
2. **Validation**: NoTradeEngine (2-phase validation)
3. **Entry**: EntryGuard → Placer → Gateway
4. **Tracking**: ActiveCache → MarketFeedHub subscription
5. **Risk Management**: 9 active rules monitoring positions
6. **Exit**: ExitEngine executes exits triggered by risk rules

**Default Disabled Features:**
- Strategy recommendations
- Multi-indicator strategy
- Trend scorer (uses legacy Supertrend+ADX)
- Underlying-aware exits
- Peak drawdown activation gating

**To Enable Alternative Flows:**
- Set `signals.use_multi_indicator_strategy: true` → Uses modular indicator system
- Set `signals.use_strategy_recommendations: true` → Uses StrategyRecommender
- Set `feature_flags.enable_trend_scorer: true` → Uses TrendScorer instead of legacy path

