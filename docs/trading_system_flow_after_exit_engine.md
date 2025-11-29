# Trading System Flow After ExitEngine

## 📋 **Overview**

After `Live::ExitEngine` executes an exit, the flow continues through several services to complete the order lifecycle and update position state.

---

## 🔄 **Complete Flow After ExitEngine**

```
ExitEngine.execute_exit(tracker, reason)
    ↓
TradingSystem::OrderRouter.exit_market(tracker)
    ↓
Orders::GatewayLive.exit_market(tracker)  (or GatewayPaper)
    ↓
Orders::Placer.exit_position!(seg, sid, client_order_id)
    ↓
DhanHQ::Models::Order.create(payload)  [API Call]
    ↓
[Order placed with broker]
    ↓
Live::OrderUpdateHub  [WebSocket receives order updates]
    ↓
Live::OrderUpdateHandler  [Processes updates]
    ↓
PositionTracker.mark_exited!  [Updates DB state]
```

---

## 🔧 **Services in Order**

### **1. TradingSystem::OrderRouter** ⬅️ **NEXT SERVICE TO REVIEW**

**Location**: `app/services/trading_system/order_router.rb`

**Purpose**: 
- Wraps Gateway with retry logic
- Provides consistent interface for order placement
- Handles retries (3 attempts with exponential backoff)

**Key Method**:
```ruby
def exit_market(tracker)
  with_retries do
    @gateway.exit_market(tracker)
  end
rescue StandardError => e
  Rails.logger.error("[OrderRouter] exit_market exception for #{tracker.order_no}: #{e.class} - #{e.message}")
  { success: false, error: e.message }
end
```

**Called By**: `ExitEngine.execute_exit`

**Calls**: `Orders::GatewayLive.exit_market` or `Orders::GatewayPaper.exit_market`

**Responsibilities**:
- ✅ Retry logic (3 attempts, 0.2s base sleep)
- ✅ Error handling
- ✅ Return value normalization

**Potential Issues**:
- ⚠️ Retry logic might retry on non-retryable errors
- ⚠️ No circuit breaker for repeated failures
- ⚠️ No metrics tracking

---

### **2. Orders::GatewayLive** (or GatewayPaper)

**Location**: `app/services/orders/gateway_live.rb` / `app/services/orders/gateway_paper.rb`

**Purpose**:
- Abstract interface for order placement
- Live vs Paper trading implementations
- Handles API timeouts and retries

**Key Method**:
```ruby
def exit_market(tracker)
  coid = "AS-EXIT-#{tracker.security_id}-#{Time.now.to_i}"
  
  order = Orders::Placer.exit_position!(
    seg: tracker.segment,
    sid: tracker.security_id,
    client_order_id: coid
  )
  
  return { success: true } if order
  { success: false, error: 'exit failed' }
end
```

**Called By**: `TradingSystem::OrderRouter.exit_market`

**Calls**: `Orders::Placer.exit_position!`

**Responsibilities**:
- ✅ Generate client order ID
- ✅ Call Placer with correct parameters
- ✅ Return success/failure status
- ✅ Handle API timeouts (8s timeout)

**Potential Issues**:
- ⚠️ Client order ID generation might collide (timestamp-based)
- ⚠️ No validation of tracker state before exit
- ⚠️ No duplicate order prevention at Gateway level

---

### **3. Orders::Placer**

**Location**: `app/services/orders/placer.rb`

**Purpose**:
- Direct interaction with DhanHQ API
- Places orders (BUY/SELL) with broker
- Handles order placement logic

**Key Method**:
```ruby
def self.exit_position!(seg:, sid:, client_order_id:)
  # Fetches position details
  position = fetch_position_details(sid)
  
  # Determines if BUY or SELL based on position side
  if position && position[:net_qty].to_i > 0
    # Long position - SELL to exit
    sell_market!(seg: seg, sid: sid, qty: position[:net_qty], client_order_id: client_order_id)
  elsif position && position[:net_qty].to_i < 0
    # Short position - BUY to exit
    buy_market!(seg: seg, sid: sid, qty: position[:net_qty].abs, client_order_id: client_order_id)
  else
    # No position - cannot exit
    nil
  end
end
```

**Called By**: `Orders::GatewayLive.exit_market`

**Calls**: `DhanHQ::Models::Order.create` (API call)

**Responsibilities**:
- ✅ Fetch position details from broker
- ✅ Determine exit direction (BUY vs SELL)
- ✅ Prevent duplicate orders (client_order_id check)
- ✅ Validate segments
- ✅ Place order with broker API

**Potential Issues**:
- ⚠️ Position fetch might fail (API call)
- ⚠️ Race condition: position might change between fetch and order placement
- ⚠️ No idempotency key (relies on client_order_id uniqueness)

---

### **4. Live::OrderUpdateHub** 🔄 **CLOSES THE LOOP**

**Location**: `app/services/live/order_update_hub.rb`

**Purpose**:
- Singleton service that establishes WebSocket connection to DhanHQ
- Receives real-time order updates from broker
- Publishes updates via `ActiveSupport::Notifications`

**Key Features**:
- WebSocket connection management
- Reconnection logic
- Event publishing: `order.update` notifications

**Called By**: System initialization (singleton)

**Calls**: Publishes notifications (doesn't call other services)

**Responsibilities**:
- ✅ Maintain WebSocket connection
- ✅ Receive order updates from broker
- ✅ Publish updates to subscribers
- ✅ Handle reconnection on disconnect

**Integration**: 
- Subscribed by `Live::OrderUpdateHandler`
- Updates flow: Broker → OrderUpdateHub → OrderUpdateHandler → PositionTracker

---

### **5. Live::OrderUpdateHandler** 🔄 **CLOSES THE LOOP**

**Location**: `app/services/live/order_update_handler.rb`

**Purpose**:
- Subscribes to `OrderUpdateHub` notifications
- Processes incoming order updates
- Updates `PositionTracker` state based on actual broker execution

**Key Features**:
- Subscribes to `order.update` notifications
- Updates tracker status: `mark_active!`, `mark_exited!`, `mark_cancelled!`
- Handles order state transitions

**Called By**: System initialization (singleton, subscribes to OrderUpdateHub)

**Calls**: `PositionTracker.mark_exited!`, `PositionTracker.mark_active!`, etc.

**Responsibilities**:
- ✅ Process order updates from broker
- ✅ Update PositionTracker state
- ✅ Handle order state transitions
- ✅ Sync order execution details

**Integration**:
- Closes the loop: Order placed → Broker executes → Update received → Tracker updated
- This is how `PositionTracker` gets updated with actual execution details

---

## 🎯 **Recommended Next Review**

### **Option 1: TradingSystem::OrderRouter** ⭐ **RECOMMENDED**

**Why**:
- Directly called by `ExitEngine`
- Critical retry logic and error handling
- Simple service (easier to review)
- Potential improvements: circuit breaker, metrics, better retry logic

**Review Focus**:
- Retry logic correctness
- Error handling
- Return value consistency
- Metrics/observability

---

### **Option 2: Live::OrderUpdateHub + OrderUpdateHandler** 🔄

**Why**:
- Closes the loop (updates PositionTracker after order execution)
- Critical for position state consistency
- WebSocket reliability is important
- Handles race conditions with ExitEngine

**Review Focus**:
- WebSocket connection reliability
- Reconnection logic
- Event processing correctness
- Race condition handling (ExitEngine vs OrderUpdateHandler)

---

### **Option 3: Orders::Placer**

**Why**:
- Direct API interaction
- Position fetch logic
- Exit direction determination
- Duplicate order prevention

**Review Focus**:
- API error handling
- Position fetch reliability
- Race conditions (position changes)
- Idempotency

---

## 📊 **Service Comparison**

| Service | Complexity | Criticality | Review Priority |
|---------|-----------|------------|-----------------|
| **OrderRouter** | Low | High | ⭐⭐⭐ High |
| **GatewayLive** | Medium | High | ⭐⭐ Medium |
| **Placer** | High | High | ⭐⭐ Medium |
| **OrderUpdateHub** | High | Critical | ⭐⭐⭐ High |
| **OrderUpdateHandler** | Medium | Critical | ⭐⭐⭐ High |

---

## 🔍 **Key Integration Points**

### **1. ExitEngine → OrderRouter**
- ExitEngine calls `@router.exit_market(tracker)`
- OrderRouter must return hash with `success` key
- OrderRouter handles retries

### **2. OrderRouter → Gateway**
- OrderRouter calls `@gateway.exit_market(tracker)`
- Gateway generates client_order_id
- Gateway calls Placer

### **3. Gateway → Placer**
- Gateway calls `Placer.exit_position!`
- Placer fetches position from broker
- Placer determines BUY/SELL direction
- Placer places order with broker API

### **4. Broker → OrderUpdateHub**
- Broker sends WebSocket updates
- OrderUpdateHub receives and publishes
- OrderUpdateHandler subscribes and processes

### **5. OrderUpdateHandler → PositionTracker**
- OrderUpdateHandler updates tracker state
- `mark_exited!` called with actual execution details
- Closes the loop (ExitEngine → Broker → Update → Tracker)

---

## ⚠️ **Potential Race Conditions**

### **Race 1: ExitEngine vs OrderUpdateHandler**
- **Scenario**: ExitEngine calls `mark_exited!` but OrderUpdateHandler also updates tracker
- **Current Handling**: ExitEngine uses `tracker.with_lock` and checks `tracker.exited?`
- **Status**: ✅ Handled (idempotent design)

### **Race 2: Position Fetch vs Order Placement**
- **Scenario**: Position changes between fetch and order placement
- **Current Handling**: Placer fetches position immediately before placing order
- **Status**: ⚠️ Potential issue (position might change)

### **Race 3: Duplicate Orders**
- **Scenario**: Same exit triggered multiple times
- **Current Handling**: ExitEngine uses `tracker.with_lock` and checks `tracker.exited?`
- **Status**: ✅ Handled (double-exit prevention)

---

## 📝 **Summary**

**After ExitEngine, the next service in line is:**

### **TradingSystem::OrderRouter** ⬅️ **RECOMMENDED NEXT REVIEW**

**Why**:
- Directly called by ExitEngine
- Critical retry and error handling logic
- Simple service (easier to review)
- Potential for improvements

**Alternative**: Review `OrderUpdateHub` + `OrderUpdateHandler` to understand the complete order lifecycle and position state updates.

---

## 🚀 **Next Steps**

1. **Review OrderRouter** (recommended)
2. **Review OrderUpdateHub + OrderUpdateHandler** (understand complete flow)
3. **Review Placer** (API interaction details)
