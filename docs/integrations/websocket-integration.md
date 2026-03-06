# State Management & Redis

The system utilizes Redis as a high-performance state store to ensure low-latency communication between the trading daemon and the web process.

## Key Persistence Stores

### 1. Redis Tick Cache (`Live::RedisTickCache`)
- **Purpose**: Stores the latest price (LTP) for all subscribed symbols.
- **Access**: Used by `Signal::Engine` to get current spot prices for analysis.
- **TTL**: Ticks are typically volatile and cleared at the end of the trading session.

### 2. Redis PnL Cache (`Live::RedisPnlCache`)
- **Purpose**: Holds the real-time "unrealized" PnL and High-Water Mark (HWM) for active positions.
- **Source of Truth**: During a live trade, the values in Redis are the source of truth for Risk Management, NOT the database. The database is synced periodically or at exit.

### 3. Circuit Breaker State
- **Key**: `risk:circuit_breaker:tripped`
- **Purpose**: Global flag to halt all trading. Residing in Redis ensures it is respected across all Rails processes/workers.

### 4. Re-entry Cooldowns
- **Key**: `reentry:{symbol}`
- **Purpose**: Stores the timestamp of the last exit to prevent over-trading in a choppy market.

## Database (PostgreSQL)
While Redis handles real-time state, PostgreSQL is used for:
- **Configuration**: `AlgoSetting`, `WatchlistItem`.
- **Auditing**: `PositionTracker` (historical trades), `TradeTelemetry`.
- **Market Context**: `SmcStructure` (historical support/resistance).
