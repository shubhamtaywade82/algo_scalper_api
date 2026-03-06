# Safety Mechanisms & Resilience

Beyond individual trade risk, the system implements platform-level safety mechanisms to protect the entire capital base from extreme market events or technical failures.

## 1. System Circuit Breaker
The `Risk::CircuitBreaker` is an emergency "Kill Switch" that can be triggered manually or automatically.

- **Status**: Persists in Redis/Cache to survive process restarts.
- **Tripped State**:
    - **Entry Blocking**: `Entries::EntryGuard` immediately rejects all new trade signals.
    - **Force Closure**: `RiskManagerService` identifies the tripped state and invokes `force_close_all!`, exiting every open position within seconds.
- **Manual Control**:
    - Trip: `Risk::CircuitBreaker.instance.trip!(reason: 'Manual Halt')`
    - Reset: `Risk::CircuitBreaker.instance.reset!`

## 2. Edge Failure Detection
Monitors for hardware or connectivity "black swan" events.

- **Market Feed Heartbeat**: If the WebSocket feed from DhanHQ drops for a threshold period, the system can be configured to halt trading or flatten positions.
- **Order Timeout Protection**: Tracks "pending" orders that haven't received a broker callback to prevent capital being locked in "zombie" positions.

## 3. Daily Limits & Exposure Controls
Managed within `Entries::EntryGuard` before every trade:

- **Max Daily Loss**: Stops further entries if the day's total realized loss exceeds the configured rupee limit.
- **Max Open Positions**: Limits the number of concurrent trades per index or system-wide.
- **Max Capital at Risk**: Calculates the aggregate rupee-at-risk (Lot size * SL distance) to ensure it stays within global risk parameters.

## 4. Automatic Token Healing
- **Problem**: Access tokens for trading APIs typically expire daily or under specific error conditions.
- **Solution**: The `DhanHQ::Client` and `Orders::Placer` include logic to detect `401 Unauthorized` errors and trigger an automatic re-authentication flow if valid credentials/refresh-tokens are present.
