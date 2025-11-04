# WebSocket Implementation Fix - Summary

## Issues Found and Fixed

### 1. ✅ **Fixed: Incorrect `subscribe_many` Parameter**

**Problem:**
- Code was calling `subscribe_many(req: mode, list: list)`
- DhanHQ client's `subscribe_many` only accepts `list:` parameter
- This caused `TypeError: no implicit conversion of Symbol into Integer`

**Root Cause:**
- The `req:` parameter doesn't exist in the DhanHQ client API
- Mode is set when creating the client (`DhanHQ::WS::Client.new(mode: :quote)`), not during subscription

**Fix:**
```ruby
# Before (WRONG):
@ws_client.subscribe_many(req: mode, list: @watchlist)

# After (CORRECT):
normalized_list = @watchlist.map do |item|
  {
    ExchangeSegment: item[:segment] || item['segment'],
    SecurityId: (item[:security_id] || item['security_id']).to_s
  }
end
@ws_client.subscribe_many(list: normalized_list)
```

---

### 2. ✅ **Fixed: Incorrect Hash Key Format**

**Problem:**
- Watchlist uses `:segment` and `:security_id` keys
- DhanHQ client expects `:ExchangeSegment` and `:SecurityId` keys (capitalized)

**Fix:**
- Added normalization to convert watchlist format to DhanHQ client format
- Applied to both `subscribe_many` and `unsubscribe_many` calls

---

### 3. ✅ **Fixed: Removed Unsupported Event Handlers**

**Problem:**
- Code tried to register `:connect`, `:disconnect`, `:error` event handlers
- DhanHQ client only supports `:tick`, `:open`, `:close`, `:error` events
- But `:connect` doesn't exist, causing TypeError

**Fix:**
- Removed unsupported event handlers
- Connection monitoring now uses tick-based approach:
  - Connection state updated to `:connected` when first tick received
  - `connected?` checks if ticks received within 30 seconds
  - State set to `:disconnected` on explicit `stop!`

---

### 4. ✅ **Fixed: Removed Debug Statements**

**Problem:**
- Debug `pp` statements were left in code

**Fix:**
- Removed all `pp` debug statements
- Cleaned up commented debug code

---

## Correct Implementation Pattern

Based on DhanHQ documentation and gem source code:

```ruby
# 1. Create client with mode
client = DhanHQ::WS::Client.new(mode: :quote)  # or :ticker, :full

# 2. Register tick handler
client.on(:tick) { |tick| handle_tick(tick) }

# 3. Start the client
client.start

# 4. Subscribe to instruments (after client is started)
# For single subscription:
client.subscribe_one(segment: "IDX_I", security_id: "13")

# For batch subscription:
normalized_list = [
  { ExchangeSegment: "IDX_I", SecurityId: "13" },
  { ExchangeSegment: "IDX_I", SecurityId: "25" }
]
client.subscribe_many(list: normalized_list)
```

---

## Key Points

1. **Mode is set at client creation**, not during subscription
2. **subscribe_many/unsubscribe_many** only accept `list:` parameter (not `req:`)
3. **Hash keys must be capitalized**: `ExchangeSegment`, `SecurityId` (not `segment`, `security_id`)
4. **Client must be started** before subscribing
5. **Only `:tick` events are reliably supported** - connection monitoring uses tick activity

---

## Testing

After fixes:
- ✅ Hub starts without TypeError
- ✅ Subscriptions use correct format
- ✅ Connection monitoring works via tick reception
- ✅ Code matches DhanHQ gem API

---

## Files Modified

- `app/services/live/market_feed_hub.rb`
  - Fixed `subscribe_many` calls (3 locations)
  - Fixed `unsubscribe_many` calls (1 location)
  - Removed unsupported event handlers
  - Added proper key normalization

