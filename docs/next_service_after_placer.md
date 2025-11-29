# Next Service After Placer - OrderUpdateHub & OrderUpdateHandler

## 📋 **Question**

Which is the next inline service after Orders::Placer, and what is it used for?

---

## 🔄 **Flow After Placer**

### **Complete Flow**:

```
Orders::Placer.exit_position!(seg, sid, client_order_id)
    ↓
DhanHQ::Models::Order.create(payload)  [API Call]
    ↓
[Order placed with broker - HTTP response received]
    ↓
[Broker executes order asynchronously]
    ↓
Live::OrderUpdateHub  ⬅️ NEXT INLINE (Async)
    ↓ (WebSocket receives order updates)
Live::OrderUpdateHandler  ⬅️ NEXT INLINE (Async)
    ↓ (processes updates)
PositionTracker.mark_exited!  [Updates DB state]
```

---

## 🎯 **Answer: Next Inline Services**

### **Live::OrderUpdateHub** ⬅️ **NEXT INLINE (Async)**

**Location**: `app/services/live/order_update_hub.rb`

**Purpose**:
- Singleton service that establishes **WebSocket connection** to DhanHQ
- Receives **real-time order updates** from broker
- Publishes updates via `ActiveSupport::Notifications`

**Key Features**:
- WebSocket connection management
- Reconnection logic
- Event publishing: `order.update` notifications

**Status**: ✅ Stable, missing specs

---

### **Live::OrderUpdateHandler** ⬅️ **NEXT INLINE (Async)**

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

---

## 🔍 **How They Work Together**

### **1. OrderUpdateHub** (WebSocket Receiver)

```ruby
# Singleton service - started at system initialization
def start!
  @ws_client = DhanHQ::WS::Orders::Client.new
  @ws_client.on(:update) { |payload| handle_update(payload) }
  @ws_client.start
end

def handle_update(payload)
  normalized = normalize(payload)
  # Publish to subscribers
  ActiveSupport::Notifications.instrument('dhanhq.order_update', normalized)
  @callbacks.each { |callback| safe_invoke(callback, normalized) }
end
```

**What it does**:
- Maintains WebSocket connection to DhanHQ
- Receives order updates from broker (TRADED, COMPLETE, CANCELLED, etc.)
- Normalizes payload format
- Publishes updates via ActiveSupport::Notifications
- Invokes registered callbacks

---

### **2. OrderUpdateHandler** (Update Processor)

```ruby
# Singleton service - subscribes to OrderUpdateHub
def start!
  Live::OrderUpdateHub.instance.start!
  Live::OrderUpdateHub.instance.on_update { |payload| handle_update(payload) }
end

def handle_update(payload)
  order_no = payload[:order_no] || payload[:order_id]
  tracker = PositionTracker.find_by(order_no: order_no)
  
  status = payload[:order_status] || payload[:status]
  transaction_type = payload[:transaction_type].to_s.upcase
  
  if FILL_STATUSES.include?(status)  # TRADED, COMPLETE
    if transaction_type == 'SELL'
      tracker.mark_exited!(exit_price: avg_price)
    else
      tracker.mark_active!(avg_price: avg_price, quantity: quantity)
    end
  elsif CANCELLED_STATUSES.include?(status)  # CANCELLED, REJECTED
    tracker.mark_cancelled!
  end
end
```

**What it does**:
- Subscribes to OrderUpdateHub notifications
- Finds PositionTracker by order_no
- Processes order status updates
- Updates PositionTracker state:
  - `mark_exited!` - Order filled (SELL transaction)
  - `mark_active!` - Order filled (BUY transaction)
  - `mark_cancelled!` - Order cancelled/rejected

---

## ⚠️ **Important Notes**

### **1. Asynchronous Processing**

- **Not directly called** by Placer or Gateway
- Runs in **background** via WebSocket
- Processes updates **as they arrive** from broker

### **2. Closes the Loop**

```
ExitEngine → OrderRouter → Gateway → Placer → [Order placed]
    ↓
[Broker executes order]
    ↓
OrderUpdateHub (receives update) → OrderUpdateHandler (processes) → PositionTracker updated
```

**This is how PositionTracker gets updated with actual execution details!**

### **3. Race Condition Handling**

- ExitEngine calls `mark_exited!` immediately after placing order
- OrderUpdateHandler also calls `mark_exited!` when broker confirms
- **Handled**: ExitEngine uses `tracker.with_lock` and checks `tracker.exited?`
- **Result**: Idempotent - both can update, but only first one succeeds

---

## 🔗 **Integration Points**

### **1. Placer → Broker → OrderUpdateHub**

```
Placer places order → Broker executes → WebSocket update → OrderUpdateHub receives
```

**Integration**: ✅ **Asynchronous WebSocket**
- Not directly connected
- Broker sends WebSocket updates
- OrderUpdateHub receives and publishes

---

### **2. OrderUpdateHub → OrderUpdateHandler**

```
OrderUpdateHub.handle_update(payload)
    ↓
ActiveSupport::Notifications.instrument('dhanhq.order_update', payload)
    ↓
OrderUpdateHandler.handle_update(payload)
```

**Integration**: ✅ **Event-based**
- OrderUpdateHub publishes events
- OrderUpdateHandler subscribes and processes

---

### **3. OrderUpdateHandler → PositionTracker**

```
OrderUpdateHandler.handle_update(payload)
    ↓
tracker = PositionTracker.find_by(order_no: order_no)
    ↓
tracker.mark_exited!(exit_price: avg_price)
```

**Integration**: ✅ **Direct DB update**
- Finds tracker by order_no
- Updates tracker state with actual execution details

---

## 📊 **Order Status Flow**

### **Order States**:

1. **PENDING** - Order placed, waiting for execution
2. **TRADED/COMPLETE** - Order executed (filled)
3. **CANCELLED/REJECTED** - Order cancelled or rejected

### **Handler Logic**:

```ruby
FILL_STATUSES = %w[TRADED COMPLETE]
CANCELLED_STATUSES = %w[CANCELLED REJECTED]

if FILL_STATUSES.include?(status)
  if transaction_type == 'SELL'
    tracker.mark_exited!(exit_price: avg_price)  # Exit order filled
  else
    tracker.mark_active!(avg_price: avg_price, quantity: quantity)  # Entry order filled
  end
elsif CANCELLED_STATUSES.include?(status)
  tracker.mark_cancelled!  # Order cancelled/rejected
end
```

---

## 🎯 **Summary**

### **Next Inline Services**: **OrderUpdateHub** + **OrderUpdateHandler**

**What they're used for**:
- ✅ **OrderUpdateHub**: Receives WebSocket updates from broker
- ✅ **OrderUpdateHandler**: Processes updates and updates PositionTracker

**Key Characteristics**:
- **Asynchronous**: Not directly called, runs in background
- **Event-driven**: OrderUpdateHub publishes, OrderUpdateHandler subscribes
- **Closes the loop**: Updates PositionTracker with actual broker execution details

**Status**: 
- ✅ **OrderUpdateHub**: Stable, missing specs
- ✅ **OrderUpdateHandler**: Stable, missing specs

---

## 📝 **Answer Summary**

**Next inline services**: **Live::OrderUpdateHub** + **Live::OrderUpdateHandler**

**Used for**: 
- Receiving real-time order updates from broker via WebSocket
- Processing order status updates (TRADED, COMPLETE, CANCELLED)
- Updating PositionTracker with actual execution details
- Closing the loop: Order placed → Broker executes → Tracker updated

**Important**: These are **asynchronous services** - they run in the background and process updates as they arrive from the broker.

---

## 🚀 **Next Steps**

**Recommended**: Review both OrderUpdateHub and OrderUpdateHandler together (they work as a pair)

**Focus Areas**:
- WebSocket connection reliability
- Reconnection logic
- Event processing correctness
- Race condition handling (with ExitEngine)
- Error handling
