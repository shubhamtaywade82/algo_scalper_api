# Comprehensive Test Planning Strategy

**Purpose**: Plan specs for all modules to ensure they work as expected  
**Last Updated**: Current Session  
**Status**: Planning Document

---

## 🎯 **Executive Summary**

This document provides a systematic approach to planning and implementing test coverage for all modules in the trading system. It includes:

1. **Current Test Coverage Analysis**
2. **Missing Test Coverage Identification**
3. **Test Planning Framework** (Unit, Integration, System)
4. **Prioritization Strategy**
5. **Test Structure & Organization**
6. **Implementation Roadmap**

---

## 📊 **Current Test Coverage Analysis**

### **Test Coverage by Category**

| Category | Total Services | Has Specs | Missing Specs | Coverage % |
|----------|---------------|-----------|---------------|------------|
| **Live Services** | 17 | 13 | 4 | 76% |
| **Signal Services** | 8 | 6 | 2 | 75% |
| **Orders Services** | 6 | 5 | 1 | 83% |
| **Indicators** | 9 | 9 | 0 | 100% |
| **Options** | 5 | 4 | 1 | 80% |
| **Capital** | 2 | 2 | 0 | 100% |
| **Positions** | 4 | 2 | 2 | 50% |
| **Trading System** | 3 | 2 | 1 | 67% |
| **TOTAL** | **54** | **43** | **11** | **80%** |

### **Services with Complete Test Coverage** ✅

1. **Indicators** (100%):
   - ✅ `adx_indicator_spec.rb`
   - ✅ `base_indicator_spec.rb`
   - ✅ `calculator_spec.rb`
   - ✅ `indicator_factory_spec.rb`
   - ✅ `macd_indicator_spec.rb`
   - ✅ `rsi_indicator_spec.rb`
   - ✅ `supertrend_indicator_spec.rb`
   - ✅ `threshold_config_spec.rb`
   - ✅ `trend_duration_indicator_spec.rb`

2. **Capital** (100%):
   - ✅ `allocator_spec.rb`
   - ✅ `dynamic_risk_allocator_spec.rb`

3. **Live Services** (High Coverage):
   - ✅ `exit_engine_spec.rb`
   - ✅ `risk_manager_service_spec.rb` (3 phases)
   - ✅ `order_update_hub_spec.rb`
   - ✅ `order_update_handler_spec.rb`
   - ✅ `gateway_live_spec.rb`
   - ✅ `gateway_paper_spec.rb`
   - ✅ `position_sync_service_spec.rb`
   - ✅ `pnl_updater_service_spec.rb`
   - ✅ `trailing_engine_spec.rb`
   - ✅ `daily_limits_spec.rb`
   - ✅ `underlying_monitor_spec.rb`
   - ✅ `market_feed_hub_spec.rb`

---

## 🔴 **Missing Test Coverage** (Priority Order)

### **🔴 CRITICAL PRIORITY** (Production Blocking)

1. **Signal::Scheduler** ⚠️ **INCOMPLETE**
   - **Missing**: `start` method tests, `stop` method tests, `running?` tests
   - **Impact**: HIGH - Core signal generation service
   - **Files**: `spec/services/signal/scheduler_spec.rb` (exists but incomplete)
   - **Estimated Time**: 3-4 hours

2. **TradingSystem::OrderRouter** ⚠️ **MISSING**
   - **Missing**: Complete spec file
   - **Impact**: HIGH - Routes orders between live/paper modes
   - **Files**: Need to create `spec/services/trading_system/order_router_spec.rb`
   - **Estimated Time**: 2-3 hours

3. **Live::PositionIndex** ⚠️ **MISSING**
   - **Missing**: Complete spec file
   - **Impact**: HIGH - In-memory position index for fast lookups
   - **Files**: Need to create `spec/services/live/position_index_spec.rb`
   - **Estimated Time**: 2-3 hours

4. **Live::RedisPnlCache** ⚠️ **MISSING**
   - **Missing**: Complete spec file
   - **Impact**: HIGH - Real-time PnL caching
   - **Files**: Need to create `spec/services/live/redis_pnl_cache_spec.rb`
   - **Estimated Time**: 2-3 hours

5. **Positions::ActiveCache** ⚠️ **INCOMPLETE**
   - **Missing**: Comprehensive tests (only has `activecache_add_remove_spec.rb`)
   - **Impact**: HIGH - Active position cache
   - **Files**: `spec/services/positions/activecache_add_remove_spec.rb` (exists but incomplete)
   - **Estimated Time**: 2-3 hours

### **🟡 HIGH PRIORITY** (Important but not blocking)

6. **Orders::Placer** ⚠️ **INCOMPLETE**
   - **Missing**: Additional test scenarios
   - **Impact**: MEDIUM - Direct DhanHQ API interaction
   - **Files**: `spec/services/orders/placer_spec.rb` (exists but may need expansion)
   - **Estimated Time**: 1-2 hours

7. **Live::ReconciliationService** ⚠️ **INCOMPLETE**
   - **Missing**: Comprehensive reconciliation scenarios
   - **Impact**: MEDIUM - Data consistency service
   - **Files**: `spec/services/live/reconciliation_service_market_close_spec.rb` (only market close tests)
   - **Estimated Time**: 2-3 hours

8. **Entries::EntryGuard** ⚠️ **INCOMPLETE**
   - **Missing**: Additional edge cases
   - **Impact**: MEDIUM - Entry validation service
   - **Files**: Has multiple spec files but may need consolidation/expansion
   - **Estimated Time**: 1-2 hours

### **🟢 MEDIUM PRIORITY** (Nice to have)

9. **Options::DerivativeChainAnalyzer** ⚠️ **MISSING**
   - **Missing**: Complete spec file
   - **Impact**: LOW - Alternative chain analyzer
   - **Files**: Need to create `spec/services/options/derivative_chain_analyzer_spec.rb`
   - **Estimated Time**: 2-3 hours

10. **Live::FeedHealthService** ⚠️ **MISSING**
    - **Missing**: Complete spec file
    - **Impact**: LOW - Feed health monitoring
    - **Files**: Need to create `spec/services/live/feed_health_service_spec.rb`
    - **Estimated Time**: 1-2 hours

11. **Live::PositionTrackerPruner** ⚠️ **MISSING**
    - **Missing**: Complete spec file
    - **Impact**: LOW - Cleanup service
    - **Files**: Need to create `spec/services/live/position_tracker_pruner_spec.rb`
    - **Estimated Time**: 1-2 hours

---

## 📋 **Test Planning Framework**

### **1. Test Types**

#### **A. Unit Tests** (Fast, Isolated)
- **Purpose**: Test individual methods/classes in isolation
- **Scope**: Single service/class
- **Dependencies**: Mocked/stubbed
- **Speed**: Fast (< 1 second per test)
- **Coverage Target**: 80%+ line coverage

**Example Structure**:
```ruby
RSpec.describe Signal::Scheduler do
  describe '#start' do
    context 'when config fetch succeeds' do
      it 'starts the scheduler thread'
      it 'sets running flag to true'
    end
    
    context 'when config fetch fails' do
      it 'logs error and does not start'
      it 'resets running flag'
    end
  end
end
```

#### **B. Integration Tests** (Medium Speed, Real Dependencies)
- **Purpose**: Test interactions between services
- **Scope**: Multiple services working together
- **Dependencies**: Real services (with test data)
- **Speed**: Medium (1-5 seconds per test)
- **Coverage Target**: Critical paths only

**Example Structure**:
```ruby
RSpec.describe 'Signal::Scheduler Integration' do
  describe 'full signal generation flow' do
    it 'generates signal and passes to EntryGuard'
    it 'handles EntryGuard rejection gracefully'
  end
end
```

#### **C. System Tests** (Slow, Full Stack)
- **Purpose**: Test end-to-end workflows
- **Scope**: Entire system
- **Dependencies**: Full stack (DB, Redis, external APIs mocked)
- **Speed**: Slow (5-30 seconds per test)
- **Coverage Target**: Critical user journeys only

**Example Structure**:
```ruby
RSpec.describe 'Trading System E2E' do
  describe 'complete trading cycle' do
    it 'generates signal, places order, tracks position, exits'
  end
end
```

---

### **2. Test Categories by Service Type**

#### **A. Singleton Services** (Thread-Safe, Lifecycle)
**Test Focus**:
- ✅ `start` method (initialization, error handling)
- ✅ `stop` method (graceful shutdown, cleanup)
- ✅ `running?` method (state query)
- ✅ Thread safety (concurrent access)
- ✅ Error handling (config failures, external API failures)
- ✅ Paper mode handling (if applicable)

**Example**: `Signal::Scheduler`, `Live::OrderUpdateHub`, `Live::RiskManagerService`

#### **B. Stateless Services** (Pure Functions)
**Test Focus**:
- ✅ Input validation
- ✅ Output correctness
- ✅ Edge cases (nil, empty, invalid inputs)
- ✅ Error handling

**Example**: `Capital::Allocator`, `Indicators::*`, `Options::StrikeSelector`

#### **C. Stateful Services** (Database/Redis)
**Test Focus**:
- ✅ CRUD operations
- ✅ State transitions
- ✅ Concurrency (if applicable)
- ✅ Data consistency
- ✅ Error handling (DB failures, Redis failures)

**Example**: `Live::RedisPnlCache`, `Live::PositionIndex`, `Positions::ActiveCache`

#### **D. Gateway Services** (External API)
**Test Focus**:
- ✅ API call structure
- ✅ Error handling (network, timeout, API errors)
- ✅ Retry logic
- ✅ Response parsing
- ✅ Paper vs Live mode differences

**Example**: `Orders::GatewayLive`, `Orders::GatewayPaper`, `Orders::Placer`

---

## 🎯 **Test Planning Template**

### **For Each Service, Plan Tests For**:

#### **1. Core Functionality** (Must Have)
- [ ] Happy path scenarios
- [ ] Input validation
- [ ] Output correctness
- [ ] Error handling

#### **2. Edge Cases** (Should Have)
- [ ] Nil/empty inputs
- [ ] Boundary conditions
- [ ] Invalid data
- [ ] Resource exhaustion

#### **3. Integration** (Should Have)
- [ ] Dependencies interaction
- [ ] Service composition
- [ ] Data flow

#### **4. Concurrency** (If Applicable)
- [ ] Thread safety
- [ ] Race conditions
- [ ] Deadlock prevention

#### **5. Lifecycle** (If Applicable)
- [ ] Initialization
- [ ] Shutdown
- [ ] State transitions

#### **6. Paper Mode** (If Applicable)
- [ ] Paper mode behavior
- [ ] Live mode behavior
- [ ] Mode switching

---

## 📐 **Test Structure & Organization**

### **File Naming Convention**

```
spec/
  services/
    {domain}/
      {service_name}_spec.rb          # Main spec file
      {service_name}_{scenario}_spec.rb # Scenario-specific tests
```

**Examples**:
- `spec/services/signal/scheduler_spec.rb` - Main tests
- `spec/services/signal/scheduler_market_close_spec.rb` - Market close scenarios
- `spec/services/live/risk_manager_service_spec.rb` - Main tests
- `spec/services/live/risk_manager_service_phase2_spec.rb` - Phase 2 specific

### **Test Organization Pattern**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ServiceName do
  # Setup
  let(:service) { described_class.new(...) }
  let(:dependencies) { ... }

  # Main method tests
  describe '#main_method' do
    context 'when conditions are met' do
      it 'does expected behavior'
    end

    context 'when conditions are not met' do
      it 'handles gracefully'
    end

    context 'when error occurs' do
      it 'logs error and recovers'
    end
  end

  # Lifecycle tests (if applicable)
  describe '#start' do
    # ...
  end

  describe '#stop' do
    # ...
  end

  # Edge cases
  describe 'edge cases' do
    # ...
  end

  # Integration tests
  describe 'integration' do
    # ...
  end
end
```

---

## 🚀 **Implementation Roadmap**

### **Phase 1: Critical Services** (Week 1)
**Goal**: Get production-blocking services fully tested

1. **Signal::Scheduler** (3-4 hours)
   - [ ] `start` method tests
   - [ ] `stop` method tests
   - [ ] `running?` method tests
   - [ ] Error handling tests
   - [ ] Market closed scenarios

2. **TradingSystem::OrderRouter** (2-3 hours)
   - [ ] Route to live gateway
   - [ ] Route to paper gateway
   - [ ] Error handling
   - [ ] Paper mode detection

3. **Live::PositionIndex** (2-3 hours)
   - [ ] Add/remove positions
   - [ ] Lookup operations
   - [ ] Thread safety
   - [ ] Callback handling

4. **Live::RedisPnlCache** (2-3 hours)
   - [ ] PnL storage/retrieval
   - [ ] Purge operations
   - [ ] Redis error handling
   - [ ] Performance (scan_each)

5. **Positions::ActiveCache** (2-3 hours)
   - [ ] Position updates
   - [ ] Peak tracking
   - [ ] Subscription handling
   - [ ] Thread safety

**Total Time**: 11-16 hours

---

### **Phase 2: High Priority Services** (Week 2)
**Goal**: Complete important but non-blocking services

6. **Orders::Placer** (1-2 hours)
   - [ ] Order placement
   - [ ] Error handling
   - [ ] Retry logic

7. **Live::ReconciliationService** (2-3 hours)
   - [ ] DB/Redis sync
   - [ ] ActiveCache sync
   - [ ] Inconsistency detection

8. **Entries::EntryGuard** (1-2 hours)
   - [ ] Entry validation
   - [ ] Entry execution
   - [ ] Edge cases

**Total Time**: 4-7 hours

---

### **Phase 3: Medium Priority Services** (Week 3)
**Goal**: Complete remaining services

9. **Options::DerivativeChainAnalyzer** (2-3 hours)
10. **Live::FeedHealthService** (1-2 hours)
11. **Live::PositionTrackerPruner** (1-2 hours)

**Total Time**: 4-7 hours

---

## 📊 **Test Coverage Metrics**

### **Target Coverage Goals**

| Service Type | Unit Tests | Integration Tests | System Tests |
|-------------|------------|-------------------|--------------|
| **Critical Services** | 90%+ | 70%+ | 50%+ |
| **High Priority** | 80%+ | 60%+ | 40%+ |
| **Medium Priority** | 70%+ | 50%+ | 30%+ |

### **Coverage Tools**

```bash
# Run with coverage
COVERAGE=true bundle exec rspec

# View coverage report
open coverage/index.html
```

---

## ✅ **Test Quality Checklist**

For each test file, ensure:

- [ ] **Arrange-Act-Assert** pattern followed
- [ ] **Descriptive test names** (describe what, not how)
- [ ] **One assertion per test** (when possible)
- [ ] **Test isolation** (no shared state between tests)
- [ ] **Fast execution** (< 1 second per unit test)
- [ ] **Proper mocking** (external dependencies mocked)
- [ ] **Error scenarios** covered
- [ ] **Edge cases** covered
- [ ] **Paper mode** tested (if applicable)
- [ ] **Thread safety** tested (if applicable)

---

## 🎯 **Prioritization Framework**

### **Priority Calculation**

**Priority Score** = (Impact × Frequency × Risk) / Complexity

**Factors**:
- **Impact**: How critical is this service? (1-10)
- **Frequency**: How often is it used? (1-10)
- **Risk**: What's the risk if it fails? (1-10)
- **Complexity**: How complex is the service? (1-10)

### **Priority Levels**

1. **🔴 CRITICAL** (Score > 7.0): Production blocking
2. **🟡 HIGH** (Score 5.0-7.0): Important but not blocking
3. **🟢 MEDIUM** (Score 3.0-5.0): Nice to have
4. **⚪ LOW** (Score < 3.0): Can wait

---

## 📝 **Test Planning Template**

### **For Each Service**

```markdown
## ServiceName

### Overview
- **Purpose**: What does this service do?
- **Dependencies**: What does it depend on?
- **Criticality**: High/Medium/Low

### Test Plan

#### Unit Tests
- [ ] Method 1: Happy path
- [ ] Method 1: Error handling
- [ ] Method 2: Happy path
- [ ] Method 2: Error handling
- [ ] Edge cases

#### Integration Tests
- [ ] Service A + Service B interaction
- [ ] Service A + Service C interaction

#### System Tests
- [ ] End-to-end workflow

### Estimated Time
- Unit Tests: X hours
- Integration Tests: Y hours
- System Tests: Z hours
- **Total**: X+Y+Z hours
```

---

## 🚀 **Next Steps**

1. **Review this document** with the team
2. **Prioritize services** based on business needs
3. **Create test plans** for each service using the template
4. **Start with Phase 1** (Critical Services)
5. **Track progress** using the checklist
6. **Review and iterate** based on findings

---

## 📚 **Resources**

- **RSpec Best Practices**: https://rspec.info/documentation/
- **Testing Rails**: https://guides.rubyonrails.org/testing.html
- **FactoryBot**: https://github.com/thoughtbot/factory_bot
- **VCR** (for API mocking): https://github.com/vcr/vcr

---

**Document Status**: ✅ **Ready for Implementation**
