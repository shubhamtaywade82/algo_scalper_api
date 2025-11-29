# Complete Trading System Flow - All Inline Services

## 📋 **Overview**

This document maps out the complete trading system flow from signal generation to position closure, identifying all inline services/components.

---

## 🔄 **Complete Trading Flow**

### **Phase 1: Signal Generation & Entry**

```
1. Signal::Scheduler
   ↓ (generates signals)
2. Signal::TrendScorer (Path 1) OR Signal::Engine (Path 2)
   ↓ (evaluates indicators)
3. Entries::EntryGuard
   ↓ (validates & executes entry)
4. Orders::EntryManager
   ↓ (orchestrates entry)
5. Orders::GatewayLive OR Orders::GatewayPaper
   ↓ (places order)
6. Orders::Placer
   ↓ (API call to broker)
7. PositionTracker.mark_active!
   ↓ (creates position)
```

### **Phase 2: Position Monitoring & Risk Management**

```
8. Live::RiskManagerService
   ↓ (monitors positions)
9. Live::PnlUpdaterService
   ↓ (updates PnL in Redis)
10. Live::RedisPnlCache
    ↓ (stores PnL data)
11. Live::TrailingEngine
    ↓ (manages trailing stops)
12. Live::ExitEngine
    ↓ (executes exits)
```

### **Phase 3: Exit Execution**

```
13. TradingSystem::OrderRouter
    ↓ (wraps gateway with retries)
14. Orders::GatewayLive OR Orders::GatewayPaper
    ↓ (exit order placement)
15. Orders::Placer.exit_position!
    ↓ (API call to broker)
16. [Order placed with broker]
    ↓
```

### **Phase 4: Order Updates & Position Closure**

```
17. Live::OrderUpdateHub
    ↓ (WebSocket receives updates)
18. Live::OrderUpdateHandler
    ↓ (processes updates)
19. PositionTracker.mark_exited!
    ↓ (updates DB state)
```

---

## 📊 **All Inline Services/Components**

### **Signal & Entry Flow** (7 services)

| # | Service/Component | Location | Status | Specs |
|---|------------------|----------|--------|-------|
| 1 | `Signal::Scheduler` | `app/services/signal/scheduler.rb` | ⚠️ WIP | ✅ Has specs |
| 2 | `Signal::TrendScorer` | `app/services/signal/trend_scorer.rb` | ⚠️ WIP | ✅ Has specs |
| 3 | `Signal::Engine` | `app/services/signal/engine.rb` | ⚠️ WIP | ✅ Has specs |
| 4 | `Entries::EntryGuard` | `app/services/entries/entry_guard.rb` | ⚠️ WIP | ✅ Has specs |
| 5 | `Orders::EntryManager` | `app/services/orders/entry_manager.rb` | ✅ Stable | ✅ Has specs |
| 6 | `Orders::GatewayLive` | `app/services/orders/gateway_live.rb` | ✅ Stable | ⚠️ Partial |
| 7 | `Orders::GatewayPaper` | `app/services/orders/gateway_paper.rb` | ✅ Stable | ❌ Missing |

---

### **Position Monitoring & Risk Management** (5 services)

| # | Service/Component | Location | Status | Specs |
|---|------------------|----------|--------|-------|
| 8 | `Live::RiskManagerService` | `app/services/live/risk_manager_service.rb` | ⚠️ WIP | ✅ Has specs |
| 9 | `Live::PnlUpdaterService` | `app/services/live/pnl_updater_service.rb` | ✅ Stable | ✅ Has specs |
| 10 | `Live::RedisPnlCache` | `app/services/live/redis_pnl_cache.rb` | ✅ Stable | ❌ Missing |
| 11 | `Live::TrailingEngine` | `app/services/live/trailing_engine.rb` | ✅ Stable | ✅ Has specs |
| 12 | `Live::ExitEngine` | `app/services/live/exit_engine.rb` | ✅ Fixed | ✅ Has specs |

---

### **Exit Execution Flow** (3 services)

| # | Service/Component | Location | Status | Specs |
|---|------------------|----------|--------|-------|
| 13 | `TradingSystem::OrderRouter` | `app/services/trading_system/order_router.rb` | ✅ Stable | ❌ Missing |
| 14 | `Orders::GatewayLive` | `app/services/orders/gateway_live.rb` | ✅ Stable | ⚠️ Partial |
| 15 | `Orders::Placer` | `app/services/orders/placer.rb` | ✅ Stable | ✅ Has specs |

---

### **Order Updates & Position Closure** (2 services)

| # | Service/Component | Location | Status | Specs |
|---|------------------|----------|--------|-------|
| 16 | `Live::OrderUpdateHub` | `app/services/live/order_update_hub.rb` | ✅ Stable | ❌ Missing |
| 17 | `Live::OrderUpdateHandler` | `app/services/live/order_update_handler.rb` | ✅ Stable | ❌ Missing |

---

## 📈 **Summary Statistics**

### **Total Inline Services**: **17 services**

**By Status**:
- ✅ **Stable**: 12 services
- ⚠️ **Work in Progress**: 5 services

**By Specs Status**:
- ✅ **Has specs**: 9 services
- ⚠️ **Partial specs**: 2 services
- ❌ **Missing specs**: 6 services

---

## 🎯 **Services Needing Attention**

### **Missing Specs** (6 services) - **STABLE COMPONENTS**

1. ❌ `Orders::GatewayPaper` - Paper trading gateway
2. ❌ `Live::RedisPnlCache` - PnL cache in Redis
3. ❌ `TradingSystem::OrderRouter` - Order router with retries
4. ❌ `Live::OrderUpdateHub` - WebSocket hub for order updates
5. ❌ `Live::OrderUpdateHandler` - Processes order updates
6. ❌ `Live::PositionIndex` - Position index (if in flow)

### **Work in Progress** (5 services) - **NEEDS IMPROVEMENT**

1. ⚠️ `Signal::Scheduler` - Signal generation orchestrator
2. ⚠️ `Signal::TrendScorer` - Path 1 signal analysis
3. ⚠️ `Signal::Engine` - Path 2 signal analysis
4. ⚠️ `Entries::EntryGuard` - Entry validation & execution
5. ⚠️ `Live::RiskManagerService` - Risk management orchestrator

---

## 🔄 **Complete Flow Diagram**

```
┌─────────────────────────────────────────────────────────────┐
│                    SIGNAL GENERATION                        │
├─────────────────────────────────────────────────────────────┤
│ 1. Signal::Scheduler                                        │
│    ├─→ Signal::TrendScorer (Path 1)                         │
│    └─→ Signal::Engine (Path 2)                              │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│                      ENTRY EXECUTION                        │
├─────────────────────────────────────────────────────────────┤
│ 2. Entries::EntryGuard                                      │
│ 3. Orders::EntryManager                                     │
│ 4. Orders::GatewayLive / GatewayPaper                       │
│ 5. Orders::Placer                                           │
│ 6. PositionTracker.mark_active!                             │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│              POSITION MONITORING & RISK                     │
├─────────────────────────────────────────────────────────────┤
│ 7. Live::RiskManagerService                                 │
│    ├─→ Live::PnlUpdaterService                              │
│    ├─→ Live::RedisPnlCache                                  │
│    ├─→ Live::TrailingEngine                                 │
│    └─→ Live::ExitEngine                                     │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│                      EXIT EXECUTION                        │
├─────────────────────────────────────────────────────────────┤
│ 8. TradingSystem::OrderRouter                               │
│ 9. Orders::GatewayLive / GatewayPaper                       │
│ 10. Orders::Placer.exit_position!                           │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│                  ORDER UPDATES & CLOSURE                    │
├─────────────────────────────────────────────────────────────┤
│ 11. Live::OrderUpdateHub (WebSocket)                        │
│ 12. Live::OrderUpdateHandler                                │
│ 13. PositionTracker.mark_exited!                            │
└─────────────────────────────────────────────────────────────┘
```

---

## 📋 **Recommended Order of Work**

### **Phase 1: Complete Specs for Stable Components** (6 services)

**Priority Order**:
1. `Live::OrderUpdateHub` + `Live::OrderUpdateHandler` (Critical - closes the loop)
2. `Live::RedisPnlCache` (Important - PnL management)
3. `Orders::GatewayPaper` (Important - paper trading)
4. `TradingSystem::OrderRouter` (Simple - retry logic)
5. `Live::PositionIndex` (If in flow - verify)

**Estimated**: 6 services × 1-2 hours = **6-12 hours**

---

### **Phase 2: Improve Work-in-Progress Components** (5 services)

**Priority Order**:
1. `Signal::Scheduler` (Core - signal generation)
2. `Live::RiskManagerService` (Critical - risk management)
3. `Entries::EntryGuard` (Important - entry validation)
4. `Signal::TrendScorer` (Path 1 - new approach)
5. `Signal::Engine` (Path 2 - legacy)

**Estimated**: 5 services × 2-4 hours = **10-20 hours**

---

## ✅ **Answer: How Many More Inline Are Available?**

### **Total Inline Services**: **17 services**

**Already Reviewed/Improved**:
- ✅ `Live::ExitEngine` - Recently fixed and improved

**Remaining**:
- **16 services** still available for review/improvement

**Breakdown**:
- **6 stable services** need specs (missing)
- **5 work-in-progress services** need implementation improvements
- **5 other services** have specs but may need verification

---

## 🎯 **Next Steps**

**Immediate Next** (Based on your approach):
1. **OrderUpdateHub** + **OrderUpdateHandler** (missing specs, critical)
2. **RedisPnlCache** (missing specs, important)
3. **GatewayPaper** (missing specs, important)
4. **OrderRouter** (missing specs, simple)

**Then**:
- Improve Signal::Scheduler
- Improve RiskManagerService
- Improve EntryGuard
