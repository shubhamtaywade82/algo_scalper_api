# Trading System Flow - After RiskManagerService

## 📊 **Complete Flow Overview**

```
Signal::Scheduler
    ↓
Entries::EntryGuard
    ↓
PositionTracker (created)
    ↓
Live::RiskManagerService (monitors & enforces exits)
    ↓
Live::ExitEngine (executes exits)
    ↓
Orders::Gateway (places exit orders)
    ↓
DhanHQ API (broker execution)
    ↓
Live::OrderUpdateHub (receives order updates)
    ↓
Live::OrderUpdateHandler (processes updates)
    ↓
PositionTracker.mark_exited! (final state update)
```

---

## 🔄 **After RiskManagerService - Next Services**

### **1. Live::ExitEngine** 🔴 **IMMEDIATE NEXT**

**Purpose**: Executes exit orders when RiskManagerService determines an exit is needed

**Location**: `app/services/live/exit_engine.rb`

**Flow**:
```ruby
# RiskManagerService calls:
exit_engine.execute_exit(tracker, reason)

# ExitEngine:
1. Locks tracker (prevents double exit)
2. Gets LTP from cache
3. Calls Orders::Gateway.exit_market(tracker)
4. Marks tracker as exited if successful
```

**Key Methods**:
- `execute_exit(tracker, reason)` - Main entry point called by RiskManagerService
- `safe_ltp(tracker)` - Gets LTP from cache

**Responsibilities**:
- ✅ Prevents double exits (with_lock)
- ✅ Delegates to OrderRouter/Gateway
- ✅ Marks tracker as exited on success
- ✅ Logs exit execution

**Integration**:
- Called by: `RiskManagerService.dispatch_exit`
- Calls: `Orders::Gateway.exit_market`
- Updates: `PositionTracker.mark_exited!`

---

### **2. Orders::Gateway** 🟡 **ORDER PLACEMENT**

**Purpose**: Abstract interface for placing exit orders (paper vs live)

**Location**: `app/services/orders/gateway.rb`

**Implementations**:
- `Orders::GatewayLive` - Live trading (real broker orders)
- `Orders::GatewayPaper` - Paper trading (simulated orders)

**Flow**:
```ruby
# ExitEngine calls:
gateway.exit_market(tracker)

# Gateway:
1. Determines segment/security_id
2. Places market exit order via broker API
3. Returns success/failure result
```

**Key Methods**:
- `exit_market(tracker)` - Places market exit order
- `flat_position(segment, security_id)` - Flattens position

**Responsibilities**:
- ✅ Abstracts paper vs live trading
- ✅ Places exit orders via broker API
- ✅ Handles order placement errors
- ✅ Returns order result

**Integration**:
- Called by: `ExitEngine.execute_exit`
- Calls: Broker API (DhanHQ)
- Returns: Success/failure to ExitEngine

---

### **3. DhanHQ Broker API** 🟡 **EXTERNAL**

**Purpose**: Executes actual exit orders on the broker platform

**Flow**:
```
Gateway.exit_market → DhanHQ API → Order placed → Order updates via WebSocket
```

**Integration**:
- Receives: Exit order requests
- Executes: Market orders
- Sends: Order updates via WebSocket

---

### **4. Live::OrderUpdateHub** 🟢 **ORDER UPDATES**

**Purpose**: Receives real-time order updates from broker via WebSocket

**Location**: `app/services/live/order_update_hub.rb`

**Flow**:
```ruby
# WebSocket client receives order updates
OrderUpdateHub.on_update { |payload| handle_update(payload) }

# Publishes to ActiveSupport::Notifications
ActiveSupport::Notifications.instrument('dhanhq.order_update', payload)
```

**Key Features**:
- ✅ WebSocket connection to broker
- ✅ Receives order status updates
- ✅ Publishes updates via notifications
- ✅ Singleton pattern

**Integration**:
- Receives: WebSocket updates from broker
- Publishes: ActiveSupport notifications
- Subscribed by: `OrderUpdateHandler`

---

### **5. Live::OrderUpdateHandler** 🟢 **ORDER PROCESSING**

**Purpose**: Processes order updates and updates PositionTracker state

**Location**: `app/services/live/order_update_handler.rb`

**Flow**:
```ruby
# Subscribes to order updates
OrderUpdateHub.on_update { |payload| handle_update(payload) }

# Processes update:
1. Finds PositionTracker by order_no
2. Updates tracker status
3. If order filled → marks tracker as exited
4. Updates PnL if needed
```

**Key Methods**:
- `handle_order_update(payload)` - Processes order update
- `handle_update(payload)` - Main handler

**Responsibilities**:
- ✅ Processes order status updates
- ✅ Updates PositionTracker state
- ✅ Handles order fills
- ✅ Updates PnL on fill

**Integration**:
- Subscribes to: `OrderUpdateHub` notifications
- Updates: `PositionTracker` records
- Triggers: Position state changes

---

### **6. PositionTracker.mark_exited!** 🟢 **FINAL STATE**

**Purpose**: Marks position as exited in database

**Location**: `app/models/position_tracker.rb`

**Flow**:
```ruby
# Called by ExitEngine or OrderUpdateHandler
tracker.mark_exited!(
  exit_price: ltp,
  exit_reason: reason
)

# Updates:
1. status = 'exited'
2. exit_price = ltp
3. exit_reason = reason
4. exited_at = Time.current
```

**Key Features**:
- ✅ Database state update
- ✅ Prevents further processing
- ✅ Records exit details
- ✅ Atomic update (with_lock)

---

## 🔄 **Complete End-to-End Flow**

### **Exit Trigger Flow**:

```
1. RiskManagerService.monitor_loop
   ↓ (detects exit condition)
   
2. RiskManagerService.check_all_exit_conditions
   ↓ (SL/TP/time-based/session end)
   
3. RiskManagerService.dispatch_exit
   ↓ (delegates to ExitEngine)
   
4. ExitEngine.execute_exit
   ↓ (locks tracker, gets LTP)
   
5. Orders::Gateway.exit_market
   ↓ (places broker order)
   
6. DhanHQ API
   ↓ (executes order)
   
7. OrderUpdateHub
   ↓ (receives WebSocket update)
   
8. OrderUpdateHandler.handle_order_update
   ↓ (processes update)
   
9. PositionTracker.mark_exited!
   ↓ (final state update)
```

---

## 📋 **Service Responsibilities Summary**

| Service | Responsibility | Called By | Calls |
|---------|---------------|-----------|-------|
| **RiskManagerService** | Monitor positions, enforce exits | Signal loop | ExitEngine |
| **ExitEngine** | Execute exits, prevent double exits | RiskManagerService | Gateway |
| **Orders::Gateway** | Place exit orders (abstract) | ExitEngine | Broker API |
| **OrderUpdateHub** | Receive order updates | WebSocket | OrderUpdateHandler |
| **OrderUpdateHandler** | Process order updates | OrderUpdateHub | PositionTracker |
| **PositionTracker** | Final state update | ExitEngine/Handler | Database |

---

## 🎯 **Key Integration Points**

### **1. RiskManagerService → ExitEngine**

**Method**: `dispatch_exit(exit_engine, tracker, reason)`

**Flow**:
```ruby
if exit_engine && exit_engine.respond_to?(:execute_exit)
  exit_engine.execute_exit(tracker, reason)  # ← ExitEngine called here
else
  execute_exit(tracker, reason)  # Fallback to internal
end
```

---

### **2. ExitEngine → Gateway**

**Method**: `@router.exit_market(tracker)`

**Flow**:
```ruby
# ExitEngine.execute_exit
result = @router.exit_market(tracker)  # ← Gateway called here
success = (result == true) || (result.is_a?(Hash) && result[:success] == true)

if success
  tracker.mark_exited!(exit_price: ltp, exit_reason: reason)
end
```

---

### **3. Gateway → Broker API**

**Method**: `DhanHQ::Models::Order.place` or `flat_position`

**Flow**:
```ruby
# GatewayLive.exit_market
order = Orders.config.flat_position(
  segment: segment,
  security_id: tracker.security_id
)  # ← Broker API called here
```

---

### **4. Broker → OrderUpdateHub**

**Method**: WebSocket connection

**Flow**:
```ruby
# OrderUpdateHub receives WebSocket update
@ws_client.on(:update) { |payload| handle_update(payload) }
```

---

### **5. OrderUpdateHub → OrderUpdateHandler**

**Method**: ActiveSupport notifications

**Flow**:
```ruby
# OrderUpdateHub publishes
ActiveSupport::Notifications.instrument('dhanhq.order_update', payload)

# OrderUpdateHandler subscribes
ActiveSupport::Notifications.subscribe('dhanhq.order_update') do |*args|
  handle_order_update(payload)
end
```

---

## 🔍 **Next Service to Review**

### **Live::ExitEngine** 🔴 **RECOMMENDED NEXT**

**Why**:
- ✅ Directly called by RiskManagerService
- ✅ Critical path for exit execution
- ✅ Handles double-exit prevention
- ✅ Coordinates with OrderRouter

**Review Focus**:
- Thread safety (with_lock usage)
- Error handling
- Integration with Gateway
- State management

---

## 📝 **Summary**

**After RiskManagerService, the next service is:**

### **Live::ExitEngine** 🔴

**Flow**:
1. **RiskManagerService** detects exit condition
2. **ExitEngine** executes exit (prevents double exits)
3. **Orders::Gateway** places broker order
4. **Broker API** executes order
5. **OrderUpdateHub** receives updates
6. **OrderUpdateHandler** processes updates
7. **PositionTracker** marked as exited

**Key Services**:
- 🔴 **ExitEngine** - Immediate next (executes exits)
- 🟡 **Orders::Gateway** - Order placement
- 🟢 **OrderUpdateHub** - Receives updates
- 🟢 **OrderUpdateHandler** - Processes updates

---

**Next Step**: Review `Live::ExitEngine` for correctness, efficiency, and integration.
