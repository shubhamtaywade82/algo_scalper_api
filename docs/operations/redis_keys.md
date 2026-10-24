# Redis Keys Reference

This document lists all Redis keys used in the Algo Scalper API application.

## Direct Redis Usage (via `Redis.new`)

These keys are stored directly in Redis using the `redis` gem, not through Rails.cache.

### 1. Position PnL Cache
**Pattern:** `pnl:tracker:{tracker_id}`
**Type:** Hash
**TTL:** 1 hour
**Service:** `Live::RedisPnlCache`
**Fields:**
- `pnl` - Current profit/loss in rupees (string)
- `pnl_pct` - Current profit/loss percentage (string)
- `hwm_pnl` - High-water mark PnL (string)
- `ltp` - Last traded price (string)
- `timestamp` - Unix timestamp when stored (string)
- `updated_at` - Unix timestamp of last update (string)

**Usage:**
- Stored when position PnL is updated by `RiskManagerService`
- Fetched for real-time PnL tracking
- Cleared when position is exited

**Example:**
```
pnl:tracker:317
```

### 2. Tick Cache
**Pattern:** `tick:{segment}:{security_id}`
**Type:** Hash
**TTL:** 1 hour
**Service:** `Live::RedisPnlCache`
**Fields:**
- `ltp` - Last traded price (string)
- `timestamp` - Unix timestamp when stored (string)
- `updated_at` - Unix timestamp of last update (string)

**Usage:**
- Stored when WebSocket ticks arrive via `MarketFeedHub`
- Fetched for LTP resolution in `InstrumentHelpers`
- Used for real-time price updates

**Example:**
```
tick:NSE_FNO:40122
tick:IDX_I:13
```

---

## Rails.cache Usage

These keys use Rails.cache, which may be backed by Redis (depending on `config.cache_store` configuration).

### 3. Re-entry Cooldown
**Pattern:** `reentry:{symbol}`
**Type:** String (Time)
**TTL:** 8 hours
**Service:** `EntryGuard`, `PositionTracker`
**Usage:**
- Prevents re-entry into the same symbol within cooldown period
- Set when position is exited
- Checked before allowing new entries

**Example:**
```
reentry:NIFTY-Nov2025-25650-PE
```

### 4. Circuit Breaker
**Pattern:** `risk:circuit_breaker:tripped`
**Type:** Hash
**TTL:** 8 hours (configurable)
**Service:** `Risk::CircuitBreaker`
**Fields:**
- `at` - Time when circuit breaker was tripped
- `reason` - Reason for tripping

**Usage:**
- Tracks if risk circuit breaker is active
- Prevents trading when tripped
- Can be reset manually

**Example:**
```
risk:circuit_breaker:tripped
```

### 5. Signal State Tracker
**Pattern:** `signal:state:{index_key}`
**Type:** Hash
**TTL:** Configurable (default: 900 seconds / 15 minutes)
**Service:** `Signal::StateTracker`
**Fields:**
- `direction` - Current signal direction (symbol)
- `count` - Consecutive signal count
- `last_candle_timestamp` - Timestamp of last candle
- `last_seen_at` - Last update time

**Usage:**
- Tracks consecutive signals for scaling logic
- Used to determine position size multipliers
- Automatically expires based on decay configuration

**Example:**
```
signal:state:NIFTY
signal:state:BANKNIFTY
signal:state:SENSEX
```

### 6. Client Order ID Deduplication
**Pattern:** `coid:{client_order_id}`
**Type:** Boolean
**TTL:** 20 minutes
**Service:** `Orders::Placer`
**Usage:**
- Prevents duplicate order placement
- Tracks recently used client order IDs
- Automatically expires after 20 minutes

**Example:**
```
coid:AS-NIFT-50074-1234567890
```

### 7. Option Chain Cache
**Pattern:** `option_chain:{security_id}:{expiry}`
**Type:** Hash
**TTL:** 2 minutes (configurable)
**Service:** `Instrument`
**Fields:**
- `last_price` - Underlying last price
- `oc` - Filtered option chain data

**Usage:**
- Caches option chain data from DhanHQ API
- Reduces API calls for option chain lookups
- Automatically refreshes every 2 minutes

**Example:**
```
option_chain:13:2025-11-27
```

### 8. Option Chain Timestamp
**Pattern:** `option_chain:{security_id}:{expiry}:timestamp`
**Type:** Time
**TTL:** 2 minutes (configurable)
**Service:** `Instrument`
**Usage:**
- Tracks when option chain was last cached
- Used to determine if cache is stale
- Stored alongside option chain data

**Example:**
```
option_chain:13:2025-11-27:timestamp
```

### 9. Settings Cache
**Pattern:** `setting:{key}`
**Type:** Any
**TTL:** 30 seconds (default, configurable)
**Service:** `Setting` model
**Usage:**
- Caches application settings
- Reduces database queries for frequently accessed settings
- Automatically expires and refreshes

**Example:**
```
setting:max_positions
setting:risk_limit
```

---

## In-Memory Caches (Not Redis)

These are in-memory caches and do NOT use Redis:

### Index Instrument Cache
**Service:** `IndexInstrumentCache`
**Storage:** In-memory hash (`@cache`)
**Pattern:** `{index_key}_{sid}_{segment}`
**TTL:** 5 minutes (in-memory)

### Tick Cache
**Service:** `TickCache`
**Storage:** In-memory hash (`@map`)
**Pattern:** `{segment}:#{security_id}`
**TTL:** 5 minutes (in-memory)

---

## Key Patterns Summary

### Direct Redis Keys (via `redis` gem)
1. `pnl:tracker:{tracker_id}` - Position PnL data
2. `tick:{segment}:{security_id}` - Real-time tick data

### Rails.cache Keys (may use Redis)
3. `reentry:{symbol}` - Re-entry cooldown
4. `risk:circuit_breaker:tripped` - Circuit breaker state
5. `signal:state:{index_key}` - Signal state tracking
6. `coid:{client_order_id}` - Order deduplication
7. `option_chain:{security_id}:{expiry}` - Option chain data
8. `option_chain:{security_id}:{expiry}:timestamp` - Option chain timestamp
9. `setting:{key}` - Application settings

---

## Redis Commands for Inspection

### List all PnL tracker keys
```bash
redis-cli KEYS "pnl:tracker:*"
```

### List all tick cache keys
```bash
redis-cli KEYS "tick:*"
```

### List all Rails.cache keys (if using Redis store)
```bash
redis-cli KEYS "*"
# Or with namespace:
redis-cli KEYS "reentry:*"
redis-cli KEYS "risk:*"
redis-cli KEYS "signal:*"
redis-cli KEYS "coid:*"
redis-cli KEYS "option_chain:*"
redis-cli KEYS "setting:*"
```

### Get PnL data for a tracker
```bash
redis-cli HGETALL "pnl:tracker:317"
```

### Get tick data
```bash
redis-cli HGETALL "tick:NSE_FNO:40122"
```

### Check TTL for a key
```bash
redis-cli TTL "pnl:tracker:317"
```

### Count keys by pattern
```bash
redis-cli --scan --pattern "pnl:tracker:*" | wc -l
redis-cli --scan --pattern "tick:*" | wc -l
```

---

## Notes

1. **TTL**: All keys have TTL (Time To Live) to prevent Redis from growing indefinitely
2. **Data Format**: All numeric values are stored as strings in Redis (Redis stores everything as strings)
3. **Namespace**: Direct Redis keys use prefixes (`pnl:`, `tick:`) to avoid collisions
4. **Rails.cache**: If `config.cache_store` is set to `:redis_cache_store`, Rails.cache keys will also be in Redis with a namespace prefix
5. **Cleanup**: Keys are automatically expired by TTL, but can also be manually deleted when positions exit

