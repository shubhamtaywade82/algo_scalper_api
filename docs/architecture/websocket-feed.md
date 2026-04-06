# Real-time WebSocket Hub

The `Live::MarketFeedHub` is the high-performance backbone of the system, responsible for real-time market data ingestion and distribution.

## Functional Responsibilities

1. **WebSocket Management**: Maintains a persistent connection to DhanHQ v2 data API.
2. **Dynamic Subscriptions**:
   - **Startup**: Subscribes to index instruments (NIFTY, BANKNIFTY, SENSEX) on startup
   - **On entry**: Subscribes to specific option strike when a new position opens
   - **On exit**: Unsubscribes the option instrument when position closes
3. **Tick Distribution**: Normalizes incoming binary/JSON ticks and distributes to:
   - `Live::TickCache` — in-memory (`Concurrent::Map`)
   - `Live::RedisTickCache` — Redis write-through (cross-process)
   - `MarketData::MarketCache` — Rails.cache institutional layer
   - `Live::PnlUpdaterService` — PnL computation queue (250ms batch)

## Tick Schema

```ruby
{
  segment: "IDX_I",       # segment identifier
  security_id: "13",      # DhanHQ security ID
  ltp: 22450.50,          # last traded price
  prev_close: 22400.00,
  timestamp: "2026-03-31 10:15:00"
}
```

## Resilience Features

- **Automatic Reconnection**: On network drop, reconnects with exponential backoff.
- **State Restoration**: On reconnect, calls `resubscribe_active_positions_after_reconnect` — queries `PositionIndex` for all active positions and resubscribes their instruments.
- **Heartbeat Monitoring**: `Live::FeedHealthService` tracks tick liveness. If no ticks received for > 30 seconds, a warning is logged. Circuit breaker may trip if configured.
- **Idempotency**: All WebSocket event handlers are idempotent — reconnects and replays do not cause duplicate processing.

## Subscription Management

```ruby
hub = Live::MarketFeedHub.instance

# Subscribe single instrument
hub.subscribe(security_id: "13", segment: "IDX_I")

# Subscribe multiple instruments
hub.subscribe_many([{ security_id: "13", segment: "IDX_I" }, ...])

# Unsubscribe
hub.unsubscribe(security_id: "13", segment: "IDX_I")

# Connection status
hub.connected?

# Start/stop (via Supervisor)
hub.start!
hub.stop!
```

## Control Flow

```
DhanHQ WebSocket event
  ↓
MarketFeedHub#handle_tick(raw_tick)
  ↓
  ├── TickCache.put(tick)                     # in-memory O(1) write
  ├── RedisTickCache.put(tick)                # Redis write (graceful if down)
  ├── MarketData::MarketCache.update_ltp      # Rails.cache update
  ├── PositionIndex.trackers_for(security_id) # O(1) active position lookup
  └── PnlUpdaterService.cache_intermediate_pnl(tracker_id:, ltp:)
        # enqueued for 250ms batch
```

## Performance Characteristics

- **Concurrent handling**: `Concurrent::Array` and `Concurrent::Map` for all shared state
- **Tick throughput**: Processes individual ticks synchronously in the WebSocket callback thread; PnL computation deferred to 250ms batch
- **Dashboard throttling**: ActionCable broadcasts are emitted by `PnlUpdaterService` (250ms), not per-tick — prevents dashboard flooding
- **Risk checks**: `RiskManagerService` receives `EventBus :ltp` events (250ms) and runs its own 5s enforcement loop — never directly in the tick callback

## ENV and runtime gates

There is no `DHANHQ_WS_ENABLED` toggle: the tick feed starts whenever
`Live::MarketFeedHub#enabled?` passes (Dhan credentials present, and not
`BACKTEST_MODE=1`, `SCRIPT_MODE=1`, `DISABLE_TRADING_SERVICES=1`, or
`rails runner`). In `RAILS_ENV=test`, `config/environments/test.rb` disables
`config.x.dhanhq` WebSocket flags and tests stub the clients.

`Live::OrderUpdateHub` starts only in live mode (not paper); see
`app/services/live/order_update_hub.rb`.

## Order Update WebSocket

Separate WebSocket connection for order fill/cancel events:

- `Live::OrderUpdateHub` — manages the order update WebSocket connection
- `Live::OrderUpdateHandler` — processes fill/cancel events; updates `PositionTracker` state
- **Idempotent**: Duplicate events from reconnects are safe

## Relationship to TickQuery

`Live::TickQuery` is the authoritative read boundary for all services that need current LTP:

```ruby
Live::TickQuery.for_security(segment: "IDX_I", security_id: "13")
# → Float (LTP) or nil (cache miss)
```

Returns `nil` on miss — callers must treat `nil` as stale/absent, never as 0. Services that receive nil must skip processing rather than using a default value.
