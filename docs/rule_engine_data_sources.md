# Rule Engine Data Sources - Live vs Stale Data

## Current Implementation

The rule engine uses **live data from Redis PnL cache** (synced with WebSocket ticks), NOT stale PositionTracker database records.

## Data Flow Architecture

```
WebSocket Ticks (MarketFeedHub)
    ↓
Redis PnL Cache (Live, Real-time)
    ↓
ActiveCache Position Data (Synced from Redis)
    ↓
Rule Context (Uses ActiveCache Position)
    ↓
Rule Engine Evaluation
```

## Step-by-Step Data Flow

### 1. WebSocket Tick Arrives
```ruby
# MarketFeedHub receives tick from WebSocket
tick = { segment: 'NSE_FNO', security_id: '12345', ltp: 105.50 }

# Updates Redis PnL Cache (live)
Live::RedisPnlCache.instance.store_pnl(
  tracker_id: tracker.id,
  pnl: calculated_pnl,
  pnl_pct: calculated_pnl_pct,
  ltp: tick[:ltp],
  timestamp: Time.current  # Current timestamp
)
```

### 2. ActiveCache Updates from WebSocket
```ruby
# ActiveCache also receives tick directly from MarketFeedHub
# This updates position.current_ltp and recalculates PnL
position.update_ltp(tick[:ltp])
# position.pnl and position.pnl_pct are recalculated
```

### 3. RiskManagerService Syncs Redis Data
```ruby
# Before rule evaluation, sync Redis PnL cache to ActiveCache
def process_all_positions_in_single_loop(positions, tracker_map, exit_engine)
  positions.each do |position|
    tracker = tracker_map[position.tracker_id]
    
    # CRITICAL: Sync Redis PnL cache (live data) to ActiveCache
    sync_position_pnl_from_redis(position, tracker)
    
    # Now rule evaluation uses synced data
    check_all_exit_conditions(position, tracker, exit_engine)
  end
end
```

### 4. sync_position_pnl_from_redis Method
```ruby
def sync_position_pnl_from_redis(position, tracker)
  # Fetch from Redis PnL Cache (live, synced with WebSocket)
  redis_pnl = @redis_pnl_cache[tracker.id] ||= 
    Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
  
  return unless redis_pnl && redis_pnl[:pnl]
  
  # Only use if data is fresh (within 30 seconds)
  redis_timestamp = redis_pnl[:timestamp] || 0
  return if (Time.current.to_i - redis_timestamp) > 30
  
  # Update ActiveCache position with LIVE Redis data
  position.pnl = redis_pnl[:pnl].to_f
  position.pnl_pct = redis_pnl[:pnl_pct].to_f
  position.high_water_mark = redis_pnl[:hwm_pnl].to_f
  position.current_ltp = redis_pnl[:ltp].to_f
  position.peak_profit_pct = redis_pnl[:peak_profit_pct].to_f
end
```

### 5. Rule Context Uses ActiveCache Position
```ruby
# RuleContext uses the position object (from ActiveCache)
# which has been synced with Redis PnL cache
context = Risk::Rules::RuleContext.new(
  position: position,  # ActiveCache position (synced from Redis)
  tracker: tracker,    # PositionTracker (for entry_price, quantity, etc.)
  risk_config: risk_config
)

# Rule evaluation uses LIVE data
result = rule_engine.evaluate(context)
```

## Data Sources Summary

| Data Source | Used For | Update Frequency | Staleness |
|------------|----------|------------------|-----------|
| **Redis PnL Cache** | PnL, PnL%, HWM, LTP | Real-time (WebSocket ticks) | **LIVE** ✅ |
| **ActiveCache** | Position data structure | Real-time (WebSocket + Redis sync) | **LIVE** ✅ |
| **PositionTracker DB** | Entry price, quantity, status | On position create/update | **Stale** ❌ |

## Why This Design?

### ✅ Uses Redis PnL Cache (Live)
- **Real-time updates**: Synced with WebSocket ticks
- **Fast access**: Redis is in-memory, sub-millisecond lookups
- **Fresh data**: Timestamp checked to ensure data is within 30 seconds

### ✅ Uses ActiveCache (Synced)
- **Dual updates**: Updated both from WebSocket ticks AND Redis sync
- **Consistency**: Redis sync ensures consistency if WebSocket misses a tick
- **Performance**: In-memory cache for fast rule evaluation

### ❌ Does NOT Use PositionTracker DB for PnL
- **Stale data**: Database records are only updated periodically
- **Slow**: Database queries are much slower than Redis
- **Not real-time**: DB updates lag behind market ticks

## Verification: Rule Context Data Access

```ruby
# RuleContext methods access position data (from ActiveCache, synced from Redis)
def pnl_pct
  position.pnl_pct  # ← From ActiveCache (synced from Redis PnL cache)
end

def pnl_rupees
  position.pnl      # ← From ActiveCache (synced from Redis PnL cache)
end

def high_water_mark
  position.high_water_mark  # ← From ActiveCache (synced from Redis PnL cache)
end

def current_ltp
  position.current_ltp  # ← From ActiveCache (synced from Redis PnL cache)
end

# Only uses PositionTracker for static data
def entry_price
  tracker.entry_price  # ← From PositionTracker DB (static, doesn't change)
end

def quantity
  tracker.quantity     # ← From PositionTracker DB (static, doesn't change)
end
```

## Example: Stop Loss Rule Evaluation

```ruby
# Position: Entry ₹100, Current LTP: ₹95 (from Redis PnL cache)

# 1. sync_position_pnl_from_redis updates ActiveCache:
position.pnl_pct = -5.0  # From Redis PnL cache (live)

# 2. RuleContext accesses position data:
context.pnl_pct  # => -5.0 (from ActiveCache, synced from Redis)

# 3. StopLossRule evaluates:
sl_pct = 2.0
normalized_pct = -5.0 / 100.0  # => -0.05
-0.05 <= -0.02?  # => YES
# → EXIT triggered using LIVE data ✅
```

## Ensuring Data Freshness

The system ensures data freshness through:

1. **Timestamp Check**: Only uses Redis data if timestamp is within 30 seconds
2. **Per-Cycle Cache**: `@redis_pnl_cache` avoids redundant Redis fetches
3. **Dual Updates**: ActiveCache updated from both WebSocket and Redis sync
4. **Fallback**: If Redis data is stale, falls back to ActiveCache (updated from WebSocket)

## Potential Improvement

To make it even more explicit that we're using Redis PnL cache, we could add a method to RuleContext that directly accesses Redis:

```ruby
# In RuleContext
def pnl_pct_from_redis
  redis_pnl = Live::RedisPnlCache.instance.fetch_pnl(tracker.id)
  redis_pnl[:pnl_pct] if redis_pnl
end
```

However, the current implementation is correct because:
- `sync_position_pnl_from_redis` is called BEFORE rule evaluation
- ActiveCache position is updated with Redis data
- RuleContext uses the synced position data

## Conclusion

**The rule engine uses LIVE data from Redis PnL cache** (synced with WebSocket ticks), not stale PositionTracker database records. The data flow ensures:

1. ✅ WebSocket ticks update Redis PnL cache in real-time
2. ✅ Redis PnL cache is synced to ActiveCache before rule evaluation
3. ✅ RuleContext uses ActiveCache position (with live data)
4. ✅ PositionTracker DB is only used for static data (entry_price, quantity)

This ensures rule evaluations are based on the most current market data available.
