# Milestone 1.2: WebSocket Manager

**Phase:** 1 — DhanHQ Integration  
**Goal:** Fault-tolerant, auto-recovering market data streams.  
**Estimated Tasks:** 17

---

## Tasks

### 1. Create DhanHQ::WebSocketClient
- [x] Create `app/gateway/dhanhq/websocket_client.rb`
- [x] Use `faye-websocket` or `websocket-client-simple`
- [x] Configure: URL, auth headers, reconnect options
- [x] Handle binary and text message formats
- [x] Parse DhanHQ message format (JSON with `type` field)

### 2. Implement MarketFeed Handler
- [x] Create `app/gateway/dhanhq/handlers/market_feed_handler.rb`
- [x] Handle tick-by-tick LTP data (message type: `ltp`)
- [x] Parse: `security_id`, `ltp`, `volume`, `timestamp`, `oi`
- [x] Convert to `MarketTick` domain object
- [x] Publish to EventBus: `market.ticks`
- [x] Batch ticks for repository insertion (every 100ms or 100 ticks)

### 3. Implement MarketDepth Handler
- [x] Create `app/gateway/dhanhq/handlers/market_depth_handler.rb`
- [x] Handle 5-level order book (message type: `depth`)
- [x] Parse bid/ask arrays: `[[price, size], ...]`
- [x] Calculate: spread, mid_price, bid/ask imbalance, total volume
- [x] Convert to `MarketDepthSnapshot` domain object
- [x] Publish to EventBus: `market.depth`

### 4. Implement OrderUpdates Handler
- [x] Create `app/gateway/dhanhq/handlers/order_updates_handler.rb`
- [x] Handle order status events (message type: `order`)
- [x] Parse: `order_id`, `status`, `filled_qty`, `avg_price`, `timestamp`
- [x] Update local `orders` table
- [x] Publish to EventBus: `orders.updates`
- [x] Trigger position reconciliation on fill

### 5. Add Automatic Reconnection
- [x] Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, max 60s
- [x] Jitter: ±10% to prevent thundering herd
- [x] Reset backoff on successful connection > 60s
- [x] Max reconnection attempts: unlimited (run forever)
- [x] Log each reconnection attempt with reason

### 6. Implement Heartbeat Monitoring
- [x] Server heartbeat: expect ping every 30s (DhanHQ spec)
- [x] Client heartbeat: send ping every 20s
- [x] Timeout detection: no message for 30s → force reconnect
- [x] Track: last_message_at, last_ping_at, last_pong_at
- [x] Metrics: `websocket_heartbeat_missed_total`

### 7. Add Health Check Endpoint
- [x] Create `GET /health/websocket` endpoint
- [x] Response:
  ```json
  {
    "connected": true,
    "connected_at": "2024-01-15T09:15:00Z",
    "last_message_at": "2024-01-15T09:15:30Z",
    "reconnection_count": 2,
    "messages_per_second": 1250,
    "subscriptions": ["NIFTY 25000 CE", "BANKNIFTY 50000 PE", ...],
    "latency_ms": 15
  }
  ```
- [x] Used by load balancer and monitoring

### 8. Implement Automatic Resubscribe
- [x] Store active subscriptions in Redis (survives restart)
- [x] On reconnect: send subscription messages for all stored symbols
- [x] Handle subscription ack/nack from server
- [x] Retry failed subscriptions individually
- [x] Log subscription changes

### 9. Add Connection Metrics
- [x] Metrics (Prometheus):
  - `websocket_uptime_seconds` (gauge)
  - `websocket_reconnections_total` (counter)
  - `websocket_messages_received_total` (counter by type)
  - `websocket_messages_processed_duration_seconds` (histogram)
  - `websocket_subscription_count` (gauge)
- [x] Track per-connection and aggregated

### 10. Create WebSocketSupervisor
- [x] Create `app/services/websocket_supervisor.rb`
- [x] Use `concurrent-ruby` for connection pooling
- [x] Manage multiple connections (one per index: NIFTY, BANKNIFTY, etc.)
- [x] Supervise: restart crashed connections, balance subscriptions
- [x] Graceful shutdown: wait for in-flight messages, flush buffers

### 11. Implement Graceful Shutdown
- [x] Trap SIGTERM/SIGINT
- [x] Stop accepting new subscriptions
- [x] Wait for pending message processing (max 5s)
- [x] Flush tick buffers to repository
- [x] Close WebSocket connections cleanly
- [x] Update health check to `draining` state

### 12. Add Message Deduplication
- [x] DhanHQ may send duplicate ticks on reconnect
- [x] Track sequence numbers per security_id
- [x] Drop messages with sequence <= last_processed
- [x] Handle sequence reset on new trading day
- [x] Log duplicate rate for monitoring

### 13. Create TickNormalizer
- [x] Create `app/services/tick_normalizer.rb`
- [x] Convert raw WebSocket message to `MarketTick`:
  - Normalize timestamp to UTC
  - Validate price > 0, volume >= 0
  - Calculate bid/ask from LTP if not provided
  - Enrich with instrument metadata (lot_size, tick_size)
- [x] Reject invalid ticks with metrics

### 14. Implement Backpressure Handling
- [x] Monitor Redis queue depth for tick ingestion
- [x] If queue > threshold: log warning, sample ticks (1 in N)
- [x] If queue critical: drop depth updates, keep LTP only
- [x] Alert via EventBus when backpressure active
- [x] Metrics: `websocket_backpressure_active` (gauge)

### 15. Add WebSocket Integration Tests
- [x] Create mock WebSocket server using `websocket-eventmachine-server`
- [x] Test scenarios:
  - Connect, subscribe, receive ticks, disconnect
  - Reconnection with resubscribe
  - Heartbeat timeout triggers reconnect
  - Message deduplication
  - Backpressure sampling
- [x] Run in CI with `WebMock` disabled

### 16. Create Manual Connection Test Script
- [x] Create `scripts/websocket_monitor.rb`
- [x] CLI: connect to DhanHQ, print live ticks
- [x] Options: `--symbol`, `--duration`, `--output-file`
- [x] Useful for debugging and verification

### 17. Document WebSocket Event Schema
- [x] Create `docs/websocket.md` with:
  - Connection flow diagram
  - Message types and JSON schemas
  - Subscription message format
  - Error codes and handling
  - Reconnection behavior
  - Health check response format

---

## Acceptance Criteria
- [x] WebSocket connects and stays connected for > 24h in paper trading
- [x] Reconnection works after network interruption (test with `tc qdisc`)
- [x] Heartbeat timeout triggers reconnect within 35s
- [x] Resubscribe restores all subscriptions after reconnect
- [x] Health endpoint returns accurate status
- [x] No duplicate ticks in database (sequence check)
- [x] Backpressure activates and logs correctly under load
- [x] Graceful shutdown completes in < 5s
- [x] Metrics match expected values

---

## Notes
- DhanHQ WebSocket requires `access_token` in connection URL
- One connection can handle ~500 symbols; use multiple for full coverage
- Market hours: 9:15-15:30 IST; handle pre/post market if supported
- Test with `websocketd` or similar for local mock server
- Consider `async-websocket` for Ruby 3.0+ fiber-based handling