# Flow After OrderRouter - Next Inline Services

## 📋 **Current Position**

**Completed**: `TradingSystem::OrderRouter` ✅

**Next**: Services called by OrderRouter

---

## 🔄 **Flow After OrderRouter**

```
OrderRouter.exit_market(tracker)
    ↓
Gateway.exit_market(tracker)  [GatewayLive OR GatewayPaper]
    ↓
[Live Mode: Placer.exit_position! → DhanHQ API]
[Paper Mode: Returns success with exit_price]
    ↓
[Order placed with broker / Paper exit completed]
    ↓
OrderUpdateHub (WebSocket receives updates)
    ↓
OrderUpdateHandler (processes updates)
    ↓
PositionTracker.mark_exited! (updates DB)
```

---

## 🔧 **Next Inline Services**

### **1. Orders::GatewayLive** OR **Orders::GatewayPaper** ⬅️ **IMMEDIATE NEXT**

**Location**: 
- `app/services/orders/gateway_live.rb`
- `app/services/orders/gateway_paper.rb`

**Called By**: `TradingSystem::OrderRouter.exit_market`

**Selection**: Based on `AlgoConfig.fetch.dig(:paper_trading, :enabled)`
- `true` → `Orders::GatewayPaper`
- `false` → `Orders::GatewayLive`

**Purpose**:
- Abstract interface for order placement
- Live vs Paper trading implementations
- Handles API timeouts and retries (live mode)

**Key Methods**:
- `exit_market(tracker)` - Exit a position
- `place_market(...)` - Place entry orders
- `position(...)` - Get position snapshot
- `wallet_snapshot` - Get wallet balance

**Status**:
- ✅ **GatewayPaper**: Recently fixed (removed double tracker update)
- ✅ **GatewayLive**: Stable, working correctly

**Specs Status**:
- ⚠️ **GatewayPaper**: Missing specs
- ⚠️ **GatewayLive**: Partial specs (may need completion)

---

### **2. Orders::Placer** (Live Mode Only)

**Location**: `app/services/orders/placer.rb`

**Called By**: `Orders::GatewayLive.exit_market` (live mode only)

**Purpose**:
- Direct interaction with DhanHQ API
- Places orders (BUY/SELL) with broker
- Handles order placement logic

**Key Method**:
```ruby
def self.exit_position!(seg:, sid:, client_order_id:)
  # Fetches position details
  # Determines BUY/SELL direction
  # Places order with broker API
end
```

**Status**: ✅ Stable, has specs

**Note**: Only called in live mode. Paper mode doesn't use Placer.

---

### **3. Live::OrderUpdateHub** (After Order Execution)

**Location**: `app/services/live/order_update_hub.rb`

**Purpose**:
- Singleton service that establishes WebSocket connection to DhanHQ
- Receives real-time order updates from broker
- Publishes updates via `ActiveSupport::Notifications`

**Key Features**:
- WebSocket connection management
- Reconnection logic
- Event publishing: `order.update` notifications

**Status**: ✅ Stable, missing specs

**Called By**: System initialization (singleton, background service)

**Note**: This runs in parallel/asynchronously, not directly called by OrderRouter/Gateway.

---

### **4. Live::OrderUpdateHandler** (After Order Execution)

**Location**: `app/services/live/order_update_handler.rb`

**Purpose**:
- Subscribes to `OrderUpdateHub` notifications
- Processes incoming order updates
- Updates `PositionTracker` state based on actual broker execution

**Key Features**:
- Subscribes to `order.update` notifications
- Updates tracker status: `mark_active!`, `mark_exited!`, `mark_cancelled!`
- Handles order state transitions

**Status**: ✅ Stable, missing specs

**Called By**: System initialization (singleton, subscribes to OrderUpdateHub)

**Note**: This runs in parallel/asynchronously, not directly called by OrderRouter/Gateway.

---

## 📊 **Execution Flow Comparison**

### **Live Mode Flow**:

```
OrderRouter.exit_market(tracker)
    ↓
GatewayLive.exit_market(tracker)  ⬅️ NEXT
    ↓
Placer.exit_position!(seg, sid, coid)
    ↓
DhanHQ API (order placed)
    ↓
[Async] OrderUpdateHub receives WebSocket update
    ↓
[Async] OrderUpdateHandler processes update
    ↓
PositionTracker.mark_exited!
```

### **Paper Mode Flow**:

```
OrderRouter.exit_market(tracker)
    ↓
GatewayPaper.exit_market(tracker)  ⬅️ NEXT
    ↓
Returns { success: true, exit_price: ... }
    ↓
ExitEngine updates PositionTracker.mark_exited!
    ↓
[No OrderUpdateHub/Handler needed - paper mode]
```

---

## 🎯 **Answer: What's Next After OrderRouter?**

### **Immediate Next**: **Orders::GatewayLive** OR **Orders::GatewayPaper**

**Why**:
- Directly called by `OrderRouter.exit_market`
- Next step in the execution chain
- Different implementations for live vs paper mode

**Selection**:
- Based on `AlgoConfig.fetch.dig(:paper_trading, :enabled)`
- `true` → `GatewayPaper` (recently fixed ✅)
- `false` → `GatewayLive` (stable ✅)

---

## 📋 **Services After Gateway**

### **If Live Mode**:
1. `Orders::Placer` - Places order with broker API
2. `Live::OrderUpdateHub` - Receives WebSocket updates (async)
3. `Live::OrderUpdateHandler` - Processes updates (async)

### **If Paper Mode**:
1. Returns success to ExitEngine
2. ExitEngine updates PositionTracker
3. No OrderUpdateHub/Handler needed

---

## ✅ **Recommendation**

**Next Service to Review**: **Orders::GatewayLive** + **Orders::GatewayPaper**

**Why**:
- Directly called by OrderRouter
- Critical for both live and paper modes
- GatewayPaper recently fixed (good to verify)
- GatewayLive needs spec completion

**Focus Areas**:
- GatewayPaper: Verify fix is correct, add specs
- GatewayLive: Review implementation, complete specs
- Both: Ensure consistent interface

---

## 📝 **Summary**

**After OrderRouter, the next inline service is**:

### **Orders::GatewayLive** OR **Orders::GatewayPaper** ⬅️ **NEXT**

**Then**:
- **Live Mode**: `Orders::Placer` → DhanHQ API
- **Paper Mode**: Returns to ExitEngine (no Placer)

**After Order Execution** (async):
- `Live::OrderUpdateHub` (WebSocket)
- `Live::OrderUpdateHandler` (processes updates)
