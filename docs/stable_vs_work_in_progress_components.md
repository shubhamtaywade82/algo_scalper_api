# Stable vs Work-in-Progress Components Analysis

## 📋 **Overview**

This document categorizes components in the Algo Scalper API app into:
1. **✅ STABLE/FINAL** - Working well, can use as-is, complete specs
2. **⚠️ WORK IN PROGRESS** - Needs improvement, signal scheduling & risk management

---

## ✅ **STABLE/FINAL COMPONENTS** (Ready for Spec Completion)

### **1. WebSocket & Market Feed Infrastructure** ✅

**Components**:
- `Live::MarketFeedHub` - WebSocket hub for live market feeds
- `Live::WsHub` - Wrapper/delegate for MarketFeedHub
- `Live::TickCache` - In-memory tick cache
- `Live::RedisTickCache` - Redis-backed tick cache

**Status**: ✅ **STABLE**
- WebSocket connection management working
- LTP (Last Traded Price) feeds working
- Subscription/unsubscription working
- Already has specs: `market_feed_hub_spec.rb`, `market_feed_hub_subscription_spec.rb`, `market_feed_hub_market_close_spec.rb`

**Specs Status**:
- ✅ `spec/services/live/market_feed_hub_spec.rb` - Exists
- ✅ `spec/services/live/market_feed_hub_subscription_spec.rb` - Exists
- ✅ `spec/services/live/market_feed_hub_market_close_spec.rb` - Exists

**Action**: ✅ **Complete existing specs** (verify coverage, add edge cases if needed)

---

### **2. PnL Management (Redis + DB Sync)** ✅

**Components**:
- `Live::RedisPnlCache` - Redis cache for PnL data
- `Live::PnlUpdaterService` - Service that updates PnL in Redis
- `Live::PaperPnLRefresher` - Refreshes paper trading PnL

**Status**: ✅ **STABLE**
- PnL calculations working
- Redis storage working
- DB sync working (throttled)
- Already has specs: `redis_pnl_cache_spec.rb` (implied), `pnl_updater_service_spec.rb`

**Specs Status**:
- ✅ `spec/services/live/pnl_updater_service_spec.rb` - Exists
- ✅ `spec/services/live/pnl_updater_service_market_close_spec.rb` - Exists
- ✅ `spec/services/live/paper_pnl_refresher_market_close_spec.rb` - Exists
- ⚠️ `spec/services/live/redis_pnl_cache_spec.rb` - **NEEDS CHECK** (might be missing)

**Action**: ✅ **Complete specs** (verify RedisPnlCache has full coverage)

---

### **3. Position Syncing** ✅

**Components**:
- `Live::PositionSyncService` - Syncs positions from broker to DB
- `Live::OrderUpdateHub` - WebSocket hub for order updates
- `Live::OrderUpdateHandler` - Processes order updates and updates PositionTracker

**Status**: ✅ **STABLE**
- Position syncing working
- Order update processing working
- PositionTracker updates working
- Already has specs: `position_sync_service_spec.rb`

**Specs Status**:
- ✅ `spec/services/live/position_sync_service_spec.rb` - Exists
- ⚠️ `spec/services/live/order_update_hub_spec.rb` - **MISSING** (needs to be created)
- ⚠️ `spec/services/live/order_update_handler_spec.rb` - **MISSING** (needs to be created)

**Action**: ✅ **Create missing specs** for OrderUpdateHub and OrderUpdateHandler

---

### **4. Capital Allocation** ✅

**Components**:
- `Capital::Allocator` - Calculates position sizes based on capital
- `Capital::DynamicRiskAllocator` - Dynamic risk-based allocation

**Status**: ✅ **STABLE**
- Capital allocation working
- Position sizing working
- Already has comprehensive specs

**Specs Status**:
- ✅ `spec/services/capital/allocator_spec.rb` - Exists
- ✅ `spec/services/capital/allocator_integer_multiplier_spec.rb` - Exists
- ✅ `spec/services/capital/dynamic_risk_allocator_spec.rb` - Exists

**Action**: ✅ **Complete existing specs** (verify coverage)

---

### **5. Paper Trading Entry & Exit** ✅

**Components**:
- `Orders::GatewayPaper` - Paper trading gateway
- Paper entry logic (via GatewayPaper.place_market)
- Paper exit logic (via GatewayPaper.exit_market)

**Status**: ✅ **STABLE**
- Paper entry working
- Paper exit working
- PositionTracker creation working
- Already has specs: `gateway_paper_spec.rb` (implied via gateway specs)

**Specs Status**:
- ⚠️ `spec/services/orders/gateway_paper_spec.rb` - **NEEDS CHECK** (might be missing, check gateway specs)

**Action**: ✅ **Create/complete specs** for GatewayPaper

---

### **6. Position Tracking Infrastructure** ✅

**Components**:
- `PositionTracker` model - Database model for positions
- `Positions::ActiveCache` - In-memory cache for active positions
- `Positions::ActiveCacheService` - Service managing active cache
- `Live::PositionIndex` - Index for position lookups

**Status**: ✅ **STABLE**
- Position tracking working
- Active cache working
- Already has some specs

**Specs Status**:
- ✅ `spec/services/positions/activecache_add_remove_spec.rb` - Exists
- ⚠️ `spec/services/live/position_index_spec.rb` - **NEEDS CHECK**

**Action**: ✅ **Complete specs** for PositionIndex

---

### **7. Supporting Services** ✅

**Components**:
- `Live::DailyLimits` - Daily trading limits
- `Live::ReconciliationService` - Position reconciliation
- `Live::UnderlyingMonitor` - Monitors underlying instruments
- `Live::TrailingEngine` - Trailing stop management (separate from risk management)

**Status**: ✅ **STABLE**
- Daily limits working
- Reconciliation working
- Already has specs

**Specs Status**:
- ✅ `spec/services/live/daily_limits_spec.rb` - Exists
- ✅ `spec/services/live/reconciliation_service_market_close_spec.rb` - Exists
- ✅ `spec/services/live/underlying_monitor_spec.rb` - Exists
- ✅ `spec/services/live/trailing_engine_spec.rb` - Exists

**Action**: ✅ **Complete existing specs** (verify coverage)

---

## ⚠️ **WORK IN PROGRESS** (Needs Improvement)

### **1. Signal Scheduling** ⚠️

**Components**:
- `Signal::Scheduler` - Main signal generation orchestrator
- `Signal::TrendScorer` - Path 1: Direction-first signal analysis
- `Signal::Engine` - Path 2: Legacy multi-timeframe indicator analysis
- `Signal::IndexSelector` - Selects indices to trade
- `Signal::Validator` - Validates signals

**Status**: ⚠️ **WORK IN PROGRESS**
- Recent improvements made (INTER_INDEX_DELAY, market checks)
- Path 1 (TrendScorer) ready but needs verification
- Path 2 (Legacy Engine) still in use
- Signal evaluation logic needs refinement

**Specs Status**:
- ✅ `spec/services/signal/scheduler_spec.rb` - Exists
- ✅ `spec/services/signal/scheduler_direction_first_spec.rb` - Exists
- ✅ `spec/services/signal/scheduler_market_close_spec.rb` - Exists
- ✅ `spec/services/signal/trend_scorer_spec.rb` - Exists
- ✅ `spec/services/signal/engine_spec.rb` - Exists

**Action**: ⚠️ **Improve implementation first**, then complete specs

**Known Issues**:
- Path selection logic (Path 1 vs Path 2)
- Market status checking efficiency
- Signal evaluation timing
- Index processing order

---

### **2. Risk Management** ⚠️

**Components**:
- `Live::RiskManagerService` - Central risk management orchestrator
- `Live::ExitEngine` - Exit execution (recently improved ✅)
- Risk limit enforcement
- PnL monitoring
- Exit triggering

**Status**: ⚠️ **WORK IN PROGRESS**
- Recent improvements made (Phase 1, 2, 3)
- ExitEngine recently improved ✅
- Risk limit enforcement needs verification
- Exit triggering logic needs refinement

**Specs Status**:
- ✅ `spec/services/live/risk_manager_service_spec.rb` - Exists
- ✅ `spec/services/live/risk_manager_service_phase2_spec.rb` - Exists
- ✅ `spec/services/live/risk_manager_service_phase3_spec.rb` - Exists
- ✅ `spec/services/live/exit_engine_spec.rb` - Exists (recently improved ✅)

**Action**: ⚠️ **Improve implementation first**, then complete specs

**Known Issues**:
- Risk limit enforcement correctness
- Exit triggering timing
- PnL update frequency
- Position monitoring efficiency

---

### **3. Entry Management** ⚠️

**Components**:
- `Entries::EntryGuard` - Validates entry conditions and executes trades
- Entry validation logic
- Entry execution

**Status**: ⚠️ **WORK IN PROGRESS**
- Entry logic working but needs refinement
- Entry validation needs improvement

**Specs Status**:
- ✅ `spec/services/entries/entry_guard_spec.rb` - Exists
- ✅ `spec/services/entries/entry_guard_integration_spec.rb` - Exists
- ✅ `spec/services/entries/entry_guard_autowire_spec.rb` - Exists

**Action**: ⚠️ **Improve implementation first**, then complete specs

---

## 📊 **Summary Table**

| Component Category | Status | Specs Status | Action |
|-------------------|--------|--------------|--------|
| **WebSocket & Market Feeds** | ✅ STABLE | ✅ Complete | Complete specs |
| **PnL Management** | ✅ STABLE | ⚠️ Mostly complete | Complete missing specs |
| **Position Syncing** | ✅ STABLE | ⚠️ Partial | Create missing specs |
| **Capital Allocation** | ✅ STABLE | ✅ Complete | Verify coverage |
| **Paper Trading** | ✅ STABLE | ⚠️ Needs check | Create/complete specs |
| **Position Tracking** | ✅ STABLE | ⚠️ Partial | Complete specs |
| **Supporting Services** | ✅ STABLE | ✅ Complete | Verify coverage |
| **Signal Scheduling** | ⚠️ WIP | ✅ Has specs | Improve implementation first |
| **Risk Management** | ⚠️ WIP | ✅ Has specs | Improve implementation first |
| **Entry Management** | ⚠️ WIP | ✅ Has specs | Improve implementation first |

---

## 🎯 **Recommended Action Plan**

### **Phase 1: Complete Specs for Stable Components** ✅

**Priority Order**:

1. **OrderUpdateHub & OrderUpdateHandler** (Critical - missing specs)
   - Create `spec/services/live/order_update_hub_spec.rb`
   - Create `spec/services/live/order_update_handler_spec.rb`

2. **RedisPnlCache** (Check if missing)
   - Verify `spec/services/live/redis_pnl_cache_spec.rb` exists
   - If missing, create comprehensive spec

3. **GatewayPaper** (Check if missing)
   - Verify `spec/services/orders/gateway_paper_spec.rb` exists
   - If missing, create comprehensive spec

4. **PositionIndex** (Check if missing)
   - Verify `spec/services/live/position_index_spec.rb` exists
   - If missing, create spec

5. **Verify Existing Specs** (Complete coverage)
   - Review all stable component specs
   - Add edge cases if needed
   - Ensure 100% coverage

---

### **Phase 2: Improve Signal Scheduling & Risk Management** ⚠️

**After Phase 1 specs are complete**:

1. **Signal::Scheduler**
   - Refine Path 1 vs Path 2 selection
   - Improve market status checking
   - Optimize signal evaluation timing

2. **Live::RiskManagerService**
   - Verify risk limit enforcement
   - Improve exit triggering logic
   - Optimize PnL update frequency

3. **Entries::EntryGuard**
   - Improve entry validation
   - Refine entry execution logic

4. **Then complete specs** for improved implementations

---

## 📝 **Files to Check/Create**

### **Missing Specs to Create**:

1. `spec/services/live/order_update_hub_spec.rb` - **CREATE**
2. `spec/services/live/order_update_handler_spec.rb` - **CREATE**
3. `spec/services/live/redis_pnl_cache_spec.rb` - **CHECK/CREATE**
4. `spec/services/orders/gateway_paper_spec.rb` - **CHECK/CREATE**
5. `spec/services/live/position_index_spec.rb` - **CHECK/CREATE**

### **Specs to Verify/Complete**:

1. `spec/services/live/market_feed_hub_spec.rb` - Verify coverage
2. `spec/services/live/pnl_updater_service_spec.rb` - Verify coverage
3. `spec/services/live/position_sync_service_spec.rb` - Verify coverage
4. `spec/services/capital/allocator_spec.rb` - Verify coverage
5. `spec/services/live/trailing_engine_spec.rb` - Verify coverage

---

## ✅ **Conclusion**

**Stable Components** (Ready for spec completion):
- ✅ WebSocket & Market Feeds
- ✅ PnL Management
- ✅ Position Syncing (needs OrderUpdateHub/Handler specs)
- ✅ Capital Allocation
- ✅ Paper Trading (needs GatewayPaper spec check)
- ✅ Position Tracking (needs PositionIndex spec check)
- ✅ Supporting Services

**Work in Progress** (Improve implementation first):
- ⚠️ Signal Scheduling
- ⚠️ Risk Management
- ⚠️ Entry Management

**Recommended Approach**:
1. ✅ Complete specs for stable components first
2. ⚠️ Then improve signal scheduling & risk management
3. ✅ Then complete specs for improved implementations
