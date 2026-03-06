# Real-time WebSocket Hub

The `Live::MarketFeedHub` is the high-performance backbone of the system, responsible for real-time market data ingestion and distribution.

## Functional Responsibilities

1.  **WebSocket Management**: Maintains a persistent connection to DhanHQ Data APIs.
2.  **Dynamic Subscriptions**:
    -   **Watchlist**: Automatically subscribes to primary indices (Nifty, BankNifty) on startup.
    -   **Ad-hoc**: Subscribes to specific option strikes triggered by the Signal Engine.
3.  **Tick Distribution**: Normalizes incoming binary/JSON ticks into a standard hash and broadcasts them via:
    -   **In-Memory Ticks**: Available globally via `Live::TickCache.last_for(security_id)`.
    -   **Internal Callbacks**: Services like `RiskManagerService` and `PnlUpdaterService` register for tick updates.
    -   **ActionCable**: Streams live prices to the web dashboard.

## Resilience Features

- **Automatic Reconnection**: In case of network drop, the hub attempts to reconnect.
- **State Restoration**: Upon reconnection, it automatically re-subscribes to all instruments required by currently `active` positions.
- **Heartbeat Monitoring**: Tracked via `Live::FeedHealthService`. If no ticks are received for >30s, the system logs a warning and may trip the circuit breaker if configured.

## Data Schema (Tick Hash)
```ruby
{
  segment: "IDX_I",
  security_id: "13",
  ltp: 22450.50,
  prev_close: 22400.00,
  timestamp: "2026-03-06 17:45:00"
}
```

## Performance Optimization
To handle high-frequency ticks (especially during volatility):
- **Concurrent Handling**: Uses `Concurrent::Array` for thread-safe callbacks.
- **Throttling**: Dashboard updates (ActionCable) are throttled, while Risk/PnL updates are processed immediately.
- **Redis Integration**: Ticks are optionally mirrored to Redis for cross-process visibility.
