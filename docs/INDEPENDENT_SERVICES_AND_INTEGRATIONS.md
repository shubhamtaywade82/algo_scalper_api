# Independent Services and End-to-End Integrations

This document identifies independent services and their responsibilities, and explains how to test end-to-end integrations.

## Independent Services

### 1. MarketFeedHub (Singleton)

**Class**: `Live::MarketFeedHub`
**Access**: `Live::MarketFeedHub.instance`
**Responsibilities**:
- ✅ Connect to DhanHQ WebSocket
- ✅ Subscribe to watchlist items from `WatchlistItem` model
- ✅ Receive market ticks from WebSocket
- ✅ Store ticks in TickCache (in-memory + Redis)
- ✅ Manage WebSocket connection lifecycle
- ✅ Distribute ticks to subscribed callbacks

**Key Methods**:
- `start!` - Start WebSocket connection
- `stop!` - Stop WebSocket connection
- `subscribe_many(instruments)` - Subscribe to instruments
- `on_tick(&block)` - Register callback for ticks
- `handle_tick(tick)` - Process incoming tick

**Flow**:
```
WebSocket → handle_tick(tick) → Live::TickCache.put(tick) → callbacks
```

**Independence**: ✅ Fully independent - manages its own WebSocket connection and lifecycle

---

### 2. TickCache (Singleton)

**Class**: `TickCache` (accessed via `Live::TickCache` module)
**Access**: `Live::TickCache.ltp(segment, security_id)`
**Responsibilities**:
- ✅ Store ticks in-memory (Concurrent::Map)
- ✅ Store ticks in Redis (via RedisTickCache)
- ✅ Provide LTP access: `Live::TickCache.ltp(segment, security_id)`
- ✅ Provide tick fetch: `Live::TickCache.fetch(segment, security_id)`
- ✅ Fallback to Redis if memory miss

**Key Methods**:
- `put(tick)` - Store tick (in-memory + Redis)
- `ltp(segment, security_id)` - Get LTP (with Redis fallback)
- `fetch(segment, security_id)` - Get full tick data
- `delete(segment, security_id)` - Remove tick

**Flow**:
```
TickCache.put(tick) → In-memory (Concurrent::Map) + RedisTickCache.store_tick()
TickCache.ltp() → Memory first, then Redis fallback
```

**Independence**: ✅ Fully independent - can be accessed without MarketFeedHub running (uses Redis fallback)

---

### 3. RedisTickCache (Singleton)

**Class**: `Live::RedisTickCache`
**Access**: `Live::RedisTickCache.instance`
**Responsibilities**:
- ✅ Store ticks in Redis (key: `tick:SEG:SID`)
- ✅ Fetch ticks from Redis
- ✅ Prune stale ticks
- ✅ Protect index feeds and active positions from pruning

**Key Methods**:
- `store_tick(segment:, security_id:, data:)` - Store tick in Redis
- `fetch_tick(segment, security_id)` - Fetch tick from Redis
- `fetch_all` - Fetch all ticks
- `prune_stale(max_age:)` - Remove stale ticks

**Independence**: ✅ Fully independent - direct Redis access, no dependencies

---

### 4. ActiveCache (Singleton)

**Class**: `Positions::ActiveCache`
**Access**: `Positions::ActiveCache.instance`
**Responsibilities**:
- ✅ Cache active positions in-memory
- ✅ Subscribe to MarketFeedHub for tick updates
- ✅ Calculate PnL for positions
- ✅ Store peak profit data
- ✅ Persist peak data to Redis

**Key Methods**:
- `start!` - Subscribe to MarketFeedHub
- `add_position(tracker, sl_price, tp_price)` - Add position to cache
- `update_position(tracker_id, **updates)` - Update position data
- `recalculate_pnl(tracker_id)` - Recalculate PnL from TickCache

**Dependencies**:
- Requires MarketFeedHub to be running (for tick subscriptions)
- Uses TickCache for LTP lookups

**Independence**: ⚠️  Partially independent - can work without MarketFeedHub but needs it for real-time updates

---

### 5. PositionIndex (Singleton)

**Class**: `Live::PositionIndex`
**Access**: `Live::PositionIndex.instance`
**Responsibilities**:
- ✅ Track active positions by `segment:security_id`
- ✅ Provide position lookup
- ✅ Bulk load positions from database

**Key Methods**:
- `add(segment, security_id, tracker_id)` - Add position
- `remove(segment, security_id)` - Remove position
- `tracked?(segment, security_id)` - Check if tracked
- `bulk_load_active!` - Load all active positions from DB

**Independence**: ✅ Fully independent - manages its own state

---

## Integration Flow

### Complete Flow: MarketFeedHub → TickCache → Services

```
1. MarketFeedHub
   ├─ Connects to WebSocket
   ├─ Subscribes to watchlist items
   └─ Receives ticks

2. MarketFeedHub.handle_tick(tick)
   ├─ Updates connection health
   ├─ Calls Live::TickCache.put(tick)
   └─ Invokes callbacks (ActiveCache, etc.)

3. TickCache.put(tick)
   ├─ Stores in-memory (Concurrent::Map)
   └─ Stores in Redis (RedisTickCache.store_tick())

4. Other Services Access Ticks
   ├─ EntryGuard → Live::TickCache.ltp(segment, security_id)
   ├─ RiskManager → Live::TickCache.ltp(segment, security_id)
   ├─ ExitEngine → Live::TickCache.ltp(segment, security_id)
   ├─ PaperPnlRefresher → Live::TickCache.ltp(segment, security_id)
   └─ ActiveCache → Live::TickCache.ltp(segment, security_id)
```

---

## Testing End-to-End Integration

### Quick Test

```bash
rails runner scripts/test_services/test_end_to_end_integration.rb
```

### What It Tests

1. **MarketFeedHub Independence**
   - ✅ Connects to WebSocket
   - ✅ Subscribes to watchlist items
   - ✅ Receives ticks
   - ✅ Stores ticks in TickCache

2. **TickCache Storage**
   - ✅ Ticks stored in-memory
   - ✅ Ticks stored in Redis
   - ✅ Accessible via `Live::TickCache.ltp()`

3. **Service Access**
   - ✅ EntryGuard can access ticks
   - ✅ RiskManager can access ticks
   - ✅ ExitEngine can access ticks

4. **Full Integration Flow**
   - ✅ MarketFeedHub → TickCache → RedisTickCache
   - ✅ ActiveCache subscription
   - ✅ RiskManager running
   - ✅ ExitEngine running

### Expected Output

```
✅ MarketFeedHub is running and connected
✅ TickCache has X ticks stored
✅ ActiveCache is subscribed to MarketFeedHub
✅ RiskManager is running
✅ ExitEngine is running
✅ TickCache.ltp('IDX_I', '13') = 25000.0 (independent access)
✅ RedisTickCache.fetch_tick('IDX_I', '13') = 25000.0
```

---

## Service Dependencies

### Independent (No Dependencies)
- ✅ **MarketFeedHub** - Manages own WebSocket connection
- ✅ **TickCache** - Can work with Redis fallback
- ✅ **RedisTickCache** - Direct Redis access
- ✅ **PositionIndex** - Manages own state

### Dependent Services
- ⚠️  **ActiveCache** - Needs MarketFeedHub for real-time updates
- ⚠️  **RiskManager** - Needs TickCache for LTP lookups
- ⚠️  **ExitEngine** - Needs TickCache for exit price resolution
- ⚠️  **Signal::Scheduler** - Needs TickCache for LTP in signal generation

---

## Testing Individual Service Independence

### Test MarketFeedHub Independence

```ruby
# MarketFeedHub should work independently
hub = Live::MarketFeedHub.instance
hub.start!
# Should connect, subscribe, and start receiving ticks
```

### Test TickCache Independence

```ruby
# TickCache should be accessible even if MarketFeedHub is not running
ltp = Live::TickCache.ltp('IDX_I', '13')
# Should return LTP from Redis if available
```

### Test RedisTickCache Independence

```ruby
# RedisTickCache should work independently
redis_cache = Live::RedisTickCache.instance
tick = redis_cache.fetch_tick('IDX_I', '13')
# Should return tick from Redis
```

---

## Common Integration Issues

### Issue: TickCache.ltp() returns nil

**Possible Causes**:
1. MarketFeedHub not running
2. No ticks received yet (wait longer)
3. Instrument not subscribed
4. Redis not accessible

**Solution**:
```ruby
# Check MarketFeedHub
hub = Live::MarketFeedHub.instance
puts "Running: #{hub.running?}, Connected: #{hub.connected?}"

# Check Redis directly
redis_cache = Live::RedisTickCache.instance
tick = redis_cache.fetch_tick('IDX_I', '13')
puts "Redis tick: #{tick.inspect}"

# Wait for ticks
sleep 10
ltp = Live::TickCache.ltp('IDX_I', '13')
```

### Issue: ActiveCache not receiving ticks

**Possible Causes**:
1. ActiveCache not started
2. ActiveCache not subscribed to MarketFeedHub
3. MarketFeedHub not running

**Solution**:
```ruby
# Start ActiveCache
cache = Positions::ActiveCache.instance
cache.start!  # Subscribes to MarketFeedHub

# Verify subscription
subscription_id = cache.instance_variable_get(:@subscription_id)
puts "Subscribed: #{subscription_id.present?}"
```

---

## Best Practices

1. **Always use singleton access**: `Live::MarketFeedHub.instance`, not `new`
2. **Check service status**: Verify `running?` before using
3. **Use TickCache for LTP**: Don't access RedisTickCache directly
4. **Handle nil LTP**: Always check if `ltp` is present before using
5. **Wait for ticks**: Allow time for WebSocket connection and tick arrival

---

## Quick Reference

```ruby
# MarketFeedHub
hub = Live::MarketFeedHub.instance
hub.start!
hub.running?  # => true/false
hub.connected?  # => true/false

# TickCache
ltp = Live::TickCache.ltp('IDX_I', '13')  # => Float or nil
tick = Live::TickCache.fetch('IDX_I', '13')  # => Hash or nil

# RedisTickCache
redis_cache = Live::RedisTickCache.instance
tick = redis_cache.fetch_tick('IDX_I', '13')  # => Hash or {}

# ActiveCache
cache = Positions::ActiveCache.instance
cache.start!  # Subscribe to MarketFeedHub
positions = cache.all_positions  # => Array

# PositionIndex
index = Live::PositionIndex.instance
index.tracked?('IDX_I', '13')  # => true/false
keys = index.all_keys  # => Array of "SEG:SID" strings
```

---

## Next Steps

1. **Run integration test**: `rails runner scripts/test_services/test_end_to_end_integration.rb`
2. **Check service health**: `rails runner scripts/health_check_all_services.rb`
3. **Run full test suite**: `./scripts/test_services/run_all_tests.sh`

