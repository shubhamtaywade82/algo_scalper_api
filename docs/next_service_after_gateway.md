# Next Service After Gateway - Orders::Placer

## 📋 **Question**

Which is the next inline service after Gateway, and what is it used for?

---

## 🔄 **Flow After Gateway**

### **Live Mode Flow**:

```
GatewayLive.exit_market(tracker)
    ↓
Orders::Placer.exit_position!(seg, sid, client_order_id)  ⬅️ NEXT INLINE
    ↓
DhanHQ::Models::Order.create(payload)  [API Call]
    ↓
[Order placed with broker]
    ↓
[Async] OrderUpdateHub (WebSocket receives updates)
    ↓
[Async] OrderUpdateHandler (processes updates)
```

### **Paper Mode Flow**:

```
GatewayPaper.exit_market(tracker)
    ↓
Returns { success: true, exit_price: ... }
    ↓
ExitEngine updates PositionTracker  [Already done]
    ↓
[No Placer needed - paper mode]
```

---

## 🎯 **Answer: Next Inline Service**

### **Orders::Placer** ⬅️ **NEXT INLINE (Live Mode Only)**

**Location**: `app/services/orders/placer.rb`

**Called By**: `Orders::GatewayLive.exit_market` (live mode only)

**Not Called By**: `Orders::GatewayPaper` (paper mode doesn't use Placer)

---

## 🔧 **What is Orders::Placer Used For?**

### **Primary Purpose**:

**Direct interaction with DhanHQ API** to place orders with the broker.

**Key Responsibilities**:
1. ✅ **Fetches position details** from broker
2. ✅ **Determines exit direction** (BUY vs SELL based on position type)
3. ✅ **Prevents duplicate orders** (client_order_id check)
4. ✅ **Validates segments** (ensures tradable segments)
5. ✅ **Places order** with broker API (`DhanHQ::Models::Order.create`)

---

## 📋 **Key Methods**

### **1. exit_position!** (Called by GatewayLive)

```ruby
def self.exit_position!(seg:, sid:, client_order_id:)
  # 1. Fetch position details from broker
  position_details = fetch_position_details(sid)
  
  # 2. Determine transaction type (BUY or SELL)
  transaction_type = case position_type
                     when 'LONG' then 'SELL'  # Long position → SELL to exit
                     when 'SHORT' then 'BUY'  # Short position → BUY to exit
                     end
  
  # 3. Create order payload
  payload = {
    transactionType: transaction_type,
    exchangeSegment: actual_segment,
    securityId: sid.to_s,
    quantity: actual_qty.to_i,
    orderType: 'MARKET',
    ...
  }
  
  # 4. Place order with broker API
  order = DhanHQ::Models::Order.create(payload)
  
  # 5. Return order object
  order
end
```

**What it does**:
- Fetches current position from broker
- Determines if we need to BUY or SELL to exit
- Creates order payload with correct parameters
- Sends order to broker via DhanHQ API
- Returns order object (or nil on failure)

---

### **2. buy_market!** (Called by GatewayLive.place_market)

```ruby
def self.buy_market!(seg:, sid:, qty:, client_order_id:, ...)
  # Creates BUY order payload
  # Places order with broker
  # Returns order object
end
```

**What it does**:
- Creates BUY order payload
- Validates segment is tradable
- Prevents duplicate orders
- Places order with broker
- Returns order object

---

### **3. sell_market!** (Called by GatewayLive.place_market)

```ruby
def self.sell_market!(seg:, sid:, qty:, client_order_id:, ...)
  # Creates SELL order payload
  # Places order with broker
  # Returns order object
end
```

**What it does**:
- Creates SELL order payload
- Validates segment is tradable
- Prevents duplicate orders
- Places order with broker
- Returns order object

---

## 🔍 **How Placer Works**

### **Exit Position Flow**:

1. **Fetch Position**:
   ```ruby
   position_details = fetch_position_details(sid)
   # Returns: { net_qty: 50, position_type: 'LONG', exchange_segment: 'NSE_FNO', ... }
   ```

2. **Determine Direction**:
   ```ruby
   if position_type == 'LONG'
     transaction_type = 'SELL'  # Need to SELL to exit long position
   elsif position_type == 'SHORT'
     transaction_type = 'BUY'   # Need to BUY to exit short position
   end
   ```

3. **Create Payload**:
   ```ruby
   payload = {
     transactionType: transaction_type,
     exchangeSegment: actual_segment,
     securityId: sid.to_s,
     quantity: actual_qty.to_i,
     orderType: 'MARKET',
     productType: position_details[:product_type],
     ...
   }
   ```

4. **Place Order**:
   ```ruby
   order = DhanHQ::Models::Order.create(payload)
   # Sends HTTP request to DhanHQ API
   # Returns order object if successful
   ```

---

## ⚠️ **Important Notes**

### **1. Only Used in Live Mode**

- **Live Mode**: GatewayLive → Placer → DhanHQ API
- **Paper Mode**: GatewayPaper → Returns success (no Placer)

### **2. Position Fetch Required**

- Placer fetches position from broker before placing exit order
- Uses position details to determine BUY/SELL direction
- Uses actual quantity from broker (not tracker quantity)

### **3. Duplicate Prevention**

- Checks `client_order_id` against cache
- Prevents placing same order twice
- Uses `remember(normalized_id)` to track placed orders

### **4. Segment Validation**

- Validates segment is tradable
- Only allows: NSE_EQ, NSE_FNO, NSE_CURRENCY, BSE_EQ, BSE_FNO, BSE_CURRENCY, MCX_COMM
- Rejects indices (IDX_I, BSE_IDX, NSE_IDX) - not tradable

---

## 🔗 **Integration Points**

### **1. GatewayLive → Placer**

```ruby
# GatewayLive.exit_market
order = Orders::Placer.exit_position!(
  seg: tracker.segment,
  sid: tracker.security_id,
  client_order_id: coid
)

return { success: true } if order
{ success: false, error: 'exit failed' }
```

**Integration**: ✅ **Well-integrated**
- GatewayLive calls Placer
- Placer returns order object or nil
- GatewayLive converts to success/failure hash

---

### **2. Placer → DhanHQ API**

```ruby
# Placer.exit_position!
order = DhanHQ::Models::Order.create(payload)
```

**Integration**: ✅ **Direct API call**
- Placer makes HTTP request to DhanHQ API
- Returns order object on success
- Returns nil on failure (errors logged)

---

### **3. DhanHQ API → OrderUpdateHub** (Async)

```
Broker executes order
    ↓
Broker sends WebSocket update
    ↓
OrderUpdateHub receives update
    ↓
OrderUpdateHandler processes update
    ↓
PositionTracker.mark_exited!
```

**Integration**: ✅ **Asynchronous**
- Not directly called by Placer
- Runs in parallel via WebSocket
- Updates PositionTracker with actual execution details

---

## 📊 **Summary**

### **Next Inline Service**: **Orders::Placer** (Live Mode Only)

**What it's used for**:
- ✅ **Direct API interaction** with DhanHQ broker
- ✅ **Position fetching** from broker
- ✅ **Exit direction determination** (BUY vs SELL)
- ✅ **Order placement** with broker API
- ✅ **Duplicate prevention** (client_order_id check)
- ✅ **Segment validation** (ensures tradable segments)

**Key Characteristics**:
- **Stateless**: No shared state, thread-safe
- **API Wrapper**: Wraps DhanHQ API calls
- **Error Handling**: Returns nil on failure, logs errors
- **Idempotency**: Prevents duplicate orders

**Status**: ✅ **Stable**, has specs (`spec/services/orders/placer_spec.rb`)

---

## 🎯 **After Placer**

**Immediate**: Order placed with broker (DhanHQ API)

**Then (Async)**:
- `Live::OrderUpdateHub` - Receives WebSocket updates
- `Live::OrderUpdateHandler` - Processes updates
- `PositionTracker.mark_exited!` - Updates DB state

---

## 📝 **Answer Summary**

**Next inline service**: **Orders::Placer**

**Used for**: 
- Placing orders with DhanHQ broker API
- Fetching position details
- Determining exit direction (BUY/SELL)
- Preventing duplicate orders
- Validating tradable segments

**Only in live mode** - Paper mode doesn't use Placer.
