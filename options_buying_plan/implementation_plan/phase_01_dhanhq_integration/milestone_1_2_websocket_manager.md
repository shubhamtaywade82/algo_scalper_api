# Milestone 1.2: WebSocket Manager

**Phase:** 1 — DhanHQ Integration  
**Goal:** Fault-tolerant, auto-recovering market data streams.  
**Estimated Tasks:** 17

---

## Tasks

### 1. Create DhanHQ::WebSocketClient
- [ ] Create `app/gateway/dhanhq/websocket_client.rb`
- [ ] Use `faye-websocket` or `websocket-client-simple`
- [ ] Configure: URL, auth headers, reconnect options
- [ ] Handle binary and text message formats
- [ ] Parse DhanHQ message format (JSON with `type` field)

### 2. Implement MarketFeed Handler
- [ ] Create `app/gateway/dhanhq/handlers/market_feed_handler.rb`
- [ ] Handle tick-by-tick LTP data (message type: `ltp`)
- [ ] Parse: `security_id`, `ltp`, `volume`, `timestamp`, `oi`
- [ ] Convert to `MarketTick` domain object
- [ ] Publish to EventBus: `market.ticks`
- [ ] Batch ticks for repository insertion (every 100ms or 100 ticks)

### 3. Implement MarketDepth Handler
- [ ] Create `app/gateway/dhanhq/handlers/market_depth_handler.rb`
- [ ] Handle 5-level order book (message type: `depth`)
- [ ] Parse bid/ask arrays: `[[price, size], ...]`
- [ ] Calculate: spread, mid_price, bid/ask imbalance, total volume
- [ ] Convert to `MarketDepthSnapshot` domain object
- [ ] Publish to EventBus: `market.depth`

### 4. Implement OrderUpdates Handler
- [ ] Create `app/gateway/dhanhq/handlers/order_updates_handler.rb`
- [ ] Handle order status events (message type: `order`)
- [ ] Parse: `order_id`, `status`, `filled_qty`, `avg_price`, `timestamp`
- [ ] Update local `orders` table
- [ ] Publish to EventBus: `orders.updates`
- [ ] Trigger position reconciliation on fill

### 5. Add Automatic Reconnection
- [ ] Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, max 60s
- [ ] Jitter: ±10% to prevent thundering herd
- [ ] Reset backoff on successful connection > 60s
- [ ] Max reconnection attempts: unlimited (run forever)
- [ ] Log each reconnection attempt with reason

### 6. Implement Heartbeat Monitoring
- [ ] Server heartbeat: expect ping every 30s (DhanHQ spec)
- [ ] Client heartbeat: send ping every 20s
- [ ] Timeout detection: no message for 30s → force reconnect
- [ ] Track: last_message_at, last_ping_at, last_pong_at
- [ ] Metrics: `websocket_heartbeat_missed_total`

### 7. Add Health Check Endpoint
- [ ] Create `GET /health/websocket` endpoint
- [ ] Response:
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
- [ ] Used by load balancer and monitoring

### 8. Implement Automatic Resubscribe
- [ ] Store active subscriptions in Redis (survives restart)
- [ ] On reconnect: send subscription messages for all stored symbols
- [ ] Handle subscription ack/nack from server
- [ ] Retry failed subscriptions individually
- [ ] Log subscription changes

### 9. Add Connection Metrics
- [ ] Metrics (Prometheus):
  - `websocket_uptime_seconds` (gauge)
  - `websocket_reconnections_total` (counter)
  - `websocket_messages_received_total` (counter by type)
  - `websocket_messages_processed_duration_seconds` (histogram)
  - `websocket_subscription_count` (gauge)
- [ ] Track per-connection and aggregated

### 10. Create WebSocketSupervisor
- [ ] Create `app/services/websocket_supervisor.rb`
- [ ] Use `concurrent-ruby` for connection pooling
- [ ] Manage multiple connections (one per index: NIFTY, BANKNIFTY, etc.)
- [ ] Supervise: restart crashed connections, balance subscriptions
- [ ] Graceful shutdown: wait for in-flight messages, flush buffers

### 11. Implement Graceful Shutdown
- [ ] Trap SIGTERM/SIGINT
- [ ] Stop accepting new subscriptions
- [ ] Wait for pending message processing (max 5s)
- [ ] Flush tick buffers to repository
- [ ] Close WebSocket connections cleanly
- [ ] Update health check to `draining` state

### 12. Add Message Deduplication
- [ ] DhanHQ may send duplicate ticks on reconnect
- [ ] Track sequence numbers per security_id
- [ ] Drop messages with sequence <= last_processed
- [ ] Handle sequence reset on new trading day
- [ ] Log duplicate rate for monitoring

### 13. Create TickNormalizer
- [ ] Create `app/services/tick_normalizer.rb`
- [ ] Convert raw WebSocket message to `MarketTick`:
  - Normalize timestamp to UTC
  - Validate price > 0, volume >= 0
  - Calculate bid/ask from LTP if not provided
  - Enrich with instrument metadata (lot_size, tick_size)
- [ ] Reject invalid ticks with metrics

### 14. Implement Backpressure Handling
- [ ] Monitor Redis queue depth for tick ingestion
- [ ] If queue > threshold: log warning, sample ticks (1 in N)
- [ ] If queue critical: drop depth updates, keep LTP only
- [ ] Alert via EventBus when backpressure active
- [ ] Metrics: `websocket_backpressure_active` (gauge)

### 15. Add WebSocket Integration Tests
- [ ] Create mock WebSocket server using `websocket-eventmachine-server`
- [ ] Test scenarios:
  - Connect, subscribe, receive ticks, disconnect
  - Reconnection with resubscribe
  - Heartbeat timeout triggers reconnect
  - Message deduplication
  - Backpressure sampling
- [ ] Run in CI with `WebMock` disabled

### 16. Create Manual Connection Test Script
- [ ] Create `scripts/websocket_monitor.rb`
- [ ] CLI: connect to DhanHQ, print live ticks
- [ ] Options: `--symbol`, `--duration`, `--output-file`
- [ ] Useful for debugging and verification

### 17. Document WebSocket Event Schema
- [ ] Create `docs/websocket.md` with:
  - Connection flow diagram
  - Message types and JSON schemas
  - Subscription message format
  - Error codes and handling
  - Reconnection behavior
  - Health check response format

---

## Acceptance Criteria
- [ ] WebSocket connects and stays connected for > 24h in paper trading
- [ ] Reconnection works after network interruption (test with `tc qdisc`)
- [ ] Heartbeat timeout triggers reconnect within 35s
- [ ] Resubscribe restores all subscriptions after reconnect
- [ ] Health endpoint returns accurate status
- [ ] No duplicate ticks in database (sequence check)
- [ ] Backpressure activates and logs correctly under load
- [ ] Graceful shutdown completes in < 5s
- [ ] Metrics match expected values

---

## Notes
- DhanHQ WebSocket requires `access_token` in connection URL
- One connection can handle ~500 symbols; use multiple for full coverage
- Market hours: 9:15-15:30 IST; handle pre/post market if supported
- Test with `websocketd` or similar for local mock server
- Consider `async-websocket` for Ruby 3.0+ fiber-based handling