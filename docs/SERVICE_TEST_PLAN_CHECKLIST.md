# Service Test Plan Checklist

**Purpose**: Detailed test plans for each service  
**Last Updated**: Current Session  
**Status**: Implementation Checklist

---

## 🔴 **CRITICAL PRIORITY** - Production Blocking

### **1. Signal::Scheduler** ⚠️ **INCOMPLETE**

**File**: `spec/services/signal/scheduler_spec.rb`  
**Status**: Exists but incomplete  
**Estimated Time**: 3-4 hours

#### **Test Plan**:

- [ ] **`#start` method**
  - [ ] Successfully starts scheduler with valid config
  - [ ] Sets `@running` flag to true
  - [ ] Creates thread with correct name
  - [ ] Handles `AlgoConfig.fetch` failure gracefully
  - [ ] Logs error and resets `@running` on config failure
  - [ ] Handles empty indices configuration
  - [ ] Logs warning for empty indices
  - [ ] Resets `@running` flag for empty indices
  - [ ] Prevents double start (idempotent)

- [ ] **`#stop` method**
  - [ ] Gracefully stops running scheduler
  - [ ] Sets `@running` flag to false
  - [ ] Waits for thread to finish (2 seconds)
  - [ ] Kills thread if it doesn't finish in time
  - [ ] Logs warning when forcing termination
  - [ ] Cleans up thread reference
  - [ ] Handles errors during stop gracefully
  - [ ] Idempotent (can be called multiple times)
  - [ ] Logs success message

- [ ] **`#running?` method**
  - [ ] Returns true when scheduler is running
  - [ ] Returns false when scheduler is stopped
  - [ ] Thread-safe (mutex protected)

- [ ] **Market closed scenarios**
  - [ ] Skips processing when market is closed at cycle start
  - [ ] Stops processing when market closes during cycle
  - [ ] Logs debug message for market closed

- [ ] **Path selection**
  - [ ] Uses Path 1 (TrendScorer) when enabled
  - [ ] Uses Path 2 (Legacy) when TrendScorer disabled
  - [ ] Handles feature flag logic correctly

- [ ] **Error handling**
  - [ ] Handles `IndexInstrumentCache` failures
  - [ ] Handles `Signal::TrendScorer` failures (Path 1)
  - [ ] Handles `Signal::Engine` failures (Path 2)
  - [ ] Handles `Entries::EntryGuard` failures
  - [ ] Logs errors with context

---

### **2. TradingSystem::OrderRouter** ⚠️ **MISSING**

**File**: `spec/services/trading_system/order_router_spec.rb`  
**Status**: Does not exist  
**Estimated Time**: 2-3 hours

#### **Test Plan**:

- [ ] **`#route` method**
  - [ ] Routes to live gateway when `paper_trading` is false
  - [ ] Routes to paper gateway when `paper_trading` is true
  - [ ] Passes correct parameters to gateway
  - [ ] Returns gateway response
  - [ ] Handles gateway errors gracefully

- [ ] **Paper mode detection**
  - [ ] Correctly detects paper trading mode
  - [ ] Falls back to config if mode not specified
  - [ ] Handles missing config gracefully

- [ ] **Error handling**
  - [ ] Handles gateway initialization failures
  - [ ] Handles routing errors
  - [ ] Logs errors with context

- [ ] **Integration**
  - [ ] Works with `Orders::GatewayLive`
  - [ ] Works with `Orders::GatewayPaper`
  - [ ] Works with `ExitEngine`

---

### **3. Live::PositionIndex** ⚠️ **MISSING**

**File**: `spec/services/live/position_index_spec.rb`  
**Status**: Does not exist  
**Estimated Time**: 2-3 hours

#### **Test Plan**:

- [ ] **`#add` method**
  - [ ] Adds position to index
  - [ ] Updates existing position if already indexed
  - [ ] Handles nil/invalid positions gracefully

- [ ] **`#remove` method**
  - [ ] Removes position from index
  - [ ] Handles non-existent positions gracefully
  - [ ] Cleans up references

- [ ] **`#find` method**
  - [ ] Finds position by ID
  - [ ] Returns nil for non-existent positions
  - [ ] Fast lookup performance

- [ ] **`#all` method**
  - [ ] Returns all indexed positions
  - [ ] Returns empty array when no positions

- [ ] **Thread safety**
  - [ ] Handles concurrent add/remove operations
  - [ ] Handles concurrent find operations
  - [ ] No race conditions

- [ ] **Callbacks**
  - [ ] Updates index on `PositionTracker` creation
  - [ ] Updates index on `PositionTracker` update
  - [ ] Removes from index on `PositionTracker` deletion

- [ ] **Error handling**
  - [ ] Handles callback errors gracefully
  - [ ] Logs errors with context

---

### **4. Live::RedisPnlCache** ⚠️ **MISSING**

**File**: `spec/services/live/redis_pnl_cache_spec.rb`  
**Status**: Does not exist  
**Estimated Time**: 2-3 hours

#### **Test Plan**:

- [ ] **`#set` method**
  - [ ] Stores PnL for position ID
  - [ ] Updates existing PnL
  - [ ] Handles nil/invalid values gracefully

- [ ] **`#get` method**
  - [ ] Retrieves PnL for position ID
  - [ ] Returns nil for non-existent positions
  - [ ] Handles Redis errors gracefully

- [ ] **`#purge_exited!` method**
  - [ ] Removes PnL for exited positions
  - [ ] Keeps PnL for active positions
  - [ ] Uses `scan_each` (not `keys`)
  - [ ] Logs purge count
  - [ ] Handles Redis errors gracefully

- [ ] **Performance**
  - [ ] `scan_each` doesn't block Redis
  - [ ] Efficient for large datasets

- [ ] **Error handling**
  - [ ] Handles Redis connection failures
  - [ ] Handles Redis timeout errors
  - [ ] Logs errors with context

- [ ] **Integration**
  - [ ] Works with `RiskManagerService`
  - [ ] Works with `PnlUpdaterService`

---

### **5. Positions::ActiveCache** ⚠️ **INCOMPLETE**

**File**: `spec/services/positions/activecache_add_remove_spec.rb`  
**Status**: Exists but incomplete  
**Estimated Time**: 2-3 hours

#### **Test Plan**:

- [ ] **`#add_position` method**
  - [ ] Adds position to cache
  - [ ] Initializes position data structure
  - [ ] Handles duplicate additions gracefully

- [ ] **`#remove_position` method**
  - [ ] Removes position from cache
  - [ ] Handles non-existent positions gracefully

- [ ] **`#update_position` method**
  - [ ] Updates position PnL
  - [ ] Updates position peak
  - [ ] Handles partial updates
  - [ ] Persists peak correctly

- [ ] **`#get_position` method**
  - [ ] Retrieves position data
  - [ ] Returns nil for non-existent positions

- [ ] **`#all_positions` method**
  - [ ] Returns all cached positions
  - [ ] Returns empty array when no positions

- [ ] **Peak tracking**
  - [ ] Tracks peak PnL correctly
  - [ ] Persists peak across updates
  - [ ] Handles peak reset

- [ ] **MarketFeedHub subscription**
  - [ ] Subscribes to position updates
  - [ ] Updates cache on tick updates
  - [ ] Handles subscription errors

- [ ] **Thread safety**
  - [ ] Handles concurrent updates
  - [ ] No race conditions

- [ ] **Error handling**
  - [ ] Handles subscription failures
  - [ ] Handles update errors
  - [ ] Logs errors with context

---

## 🟡 **HIGH PRIORITY** - Important but Not Blocking

### **6. Orders::Placer** ⚠️ **INCOMPLETE**

**File**: `spec/services/orders/placer_spec.rb`  
**Status**: Exists but may need expansion  
**Estimated Time**: 1-2 hours

#### **Test Plan**:

- [ ] **`#place_order` method**
  - [ ] Places order via DhanHQ API
  - [ ] Handles API response correctly
  - [ ] Returns order details
  - [ ] Handles API errors gracefully

- [ ] **Error handling**
  - [ ] Handles network errors
  - [ ] Handles timeout errors
  - [ ] Handles API validation errors
  - [ ] Retries on transient errors
  - [ ] Logs errors with context

- [ ] **Retry logic**
  - [ ] Retries on network errors
  - [ ] Retries on timeout errors
  - [ ] Doesn't retry on validation errors
  - [ ] Exponential backoff

---

### **7. Live::ReconciliationService** ⚠️ **INCOMPLETE**

**File**: `spec/services/live/reconciliation_service_market_close_spec.rb`  
**Status**: Only has market close tests  
**Estimated Time**: 2-3 hours

#### **Test Plan**:

- [ ] **`#reconcile` method**
  - [ ] Syncs DB with Redis
  - [ ] Syncs DB with ActiveCache
  - [ ] Detects inconsistencies
  - [ ] Corrects inconsistencies

- [ ] **DB/Redis sync**
  - [ ] Updates Redis from DB
  - [ ] Updates DB from Redis
  - [ ] Handles missing entries

- [ ] **ActiveCache sync**
  - [ ] Updates ActiveCache from DB
  - [ ] Uses `update_position` method (not direct mutation)
  - [ ] Handles missing entries

- [ ] **Error handling**
  - [ ] Handles DB errors
  - [ ] Handles Redis errors
  - [ ] Handles ActiveCache errors
  - [ ] Logs errors with context

---

### **8. Entries::EntryGuard** ⚠️ **INCOMPLETE**

**File**: Multiple spec files exist  
**Status**: May need consolidation/expansion  
**Estimated Time**: 1-2 hours

#### **Test Plan**:

- [ ] **`#try_enter` method**
  - [ ] Validates entry conditions
  - [ ] Executes entry when valid
  - [ ] Rejects entry when invalid
  - [ ] Returns success/failure status

- [ ] **Validation**
  - [ ] Validates capital availability
  - [ ] Validates risk limits
  - [ ] Validates market conditions
  - [ ] Validates position limits

- [ ] **Error handling**
  - [ ] Handles validation errors
  - [ ] Handles execution errors
  - [ ] Logs errors with context

---

## 🟢 **MEDIUM PRIORITY** - Nice to Have

### **9. Options::DerivativeChainAnalyzer** ⚠️ **MISSING**

**File**: `spec/services/options/derivative_chain_analyzer_spec.rb`  
**Status**: Does not exist  
**Estimated Time**: 2-3 hours

#### **Test Plan**:

- [ ] **`#analyze` method**
  - [ ] Analyzes derivative chain
  - [ ] Returns analysis results
  - [ ] Handles errors gracefully

- [ ] **Error handling**
  - [ ] Handles data provider errors
  - [ ] Handles analysis errors
  - [ ] Logs errors with context

---

### **10. Live::FeedHealthService** ⚠️ **MISSING**

**File**: `spec/services/live/feed_health_service_spec.rb`  
**Status**: Does not exist  
**Estimated Time**: 1-2 hours

#### **Test Plan**:

- [ ] **Health monitoring**
  - [ ] Monitors feed health
  - [ ] Detects feed failures
  - [ ] Logs health status

- [ ] **Error handling**
  - [ ] Handles monitoring errors
  - [ ] Logs errors with context

---

### **11. Live::PositionTrackerPruner** ⚠️ **MISSING**

**File**: `spec/services/live/position_tracker_pruner_spec.rb`  
**Status**: Does not exist  
**Estimated Time**: 1-2 hours

#### **Test Plan**:

- [ ] **Pruning logic**
  - [ ] Removes old/exited positions
  - [ ] Keeps active positions
  - [ ] Handles errors gracefully

- [ ] **Error handling**
  - [ ] Handles DB errors
  - [ ] Logs errors with context

---

## 📊 **Progress Tracking**

### **Overall Progress**

- **Total Services**: 11
- **Critical Priority**: 5 services
- **High Priority**: 3 services
- **Medium Priority**: 3 services

### **Completion Status**

- [ ] **Phase 1 (Critical)**: 0/5 complete
- [ ] **Phase 2 (High)**: 0/3 complete
- [ ] **Phase 3 (Medium)**: 0/3 complete

### **Time Estimates**

- **Phase 1**: 11-16 hours
- **Phase 2**: 4-7 hours
- **Phase 3**: 4-7 hours
- **Total**: 19-30 hours

---

## 🎯 **Implementation Strategy**

### **Step 1: Review Test Plans**
- Review this checklist
- Adjust test plans based on service complexity
- Prioritize based on business needs

### **Step 2: Create Test Files**
- Create missing spec files
- Set up basic test structure
- Add setup/teardown code

### **Step 3: Implement Tests**
- Start with critical services
- Follow TDD approach (write tests first, then fix code)
- Ensure tests are fast and isolated

### **Step 4: Review & Iterate**
- Review test coverage
- Add missing scenarios
- Refactor tests for clarity

---

## ✅ **Test Quality Checklist**

For each test file:

- [ ] **Fast execution** (< 1 second per test)
- [ ] **Isolated** (no shared state)
- [ ] **Descriptive names** (clear what is being tested)
- [ ] **One assertion** (when possible)
- [ ] **Proper mocking** (external dependencies mocked)
- [ ] **Error scenarios** covered
- [ ] **Edge cases** covered
- [ ] **Paper mode** tested (if applicable)
- [ ] **Thread safety** tested (if applicable)

---

**Document Status**: ✅ **Ready for Implementation**
