# Milestone 1.1: REST Client & Instrument Manager

**Phase:** 1 — DhanHQ Integration  
**Goal:** Reliable, resilient broker REST API wrapper.  
**Estimated Tasks:** 18

---

## Tasks

### 1. Audit Existing DhanHQ Gem
- [x] Review current `dhanhq` gem usage in codebase
- [x] Identify missing v2 endpoints (compare with DhanHQ API docs)
- [x] Document gaps in `docs/broker_api_gaps.md`
- [x] Decide: extend gem vs. build custom wrapper

### 2. Create DhanHQ::RestClient Wrapper
- [x] Create `app/gateway/dhanhq/rest_client.rb`
- [x] HTTP client: `faraday` with connection pooling
- [x] Automatic retry with exponential backoff (max 3 retries, base 1s)
- [x] Retry on: 429, 500, 502, 503, 504, timeout
- [x] Request/response logging with sanitized headers (no auth tokens)
- [x] Circuit breaker: open after 5 consecutive failures, half-open after 30s
- [x] Metrics: latency histogram, error counter, retry counter
- [x] Configurable timeouts: connect 5s, read 30s

### 3. Implement HistoricalDataService
- [x] Create `app/services/engines/historical_data_service.rb`
- [x] Method: `fetch_ohlcv(security_id, from:, to:, interval:)`
- [x] Supported intervals: 1m, 5m, 15m, 30m, 1h, 1d
- [x] Handle pagination (max 1000 candles per request)
- [x] Return normalized `Candle` objects
- [x] Cache in Redis (TTL: 1h for intraday, 24h for daily)

### 4. Implement OptionChainService
- [x] Create `app/services/engines/option_chain_service.rb`
- [x] Method: `fetch_chain(underlying, expiry)`
- [x] Parse Greeks: IV, Delta, Gamma, Theta, Vega
- [x] Parse OI, Volume, Bid, Ask, LTP for each strike
- [x] Return `OptionChainSnapshot` domain objects
- [x] Handle rate limits (DhanHQ: 1 req/sec for option chain)

### 5. Implement MarketQuoteService
- [x] Create `app/services/engines/market_quote_service.rb`
- [x] Methods:
  - `ltp(security_ids)` - last traded price (batch up to 50)
  - `ohlc(security_ids)` - open, high, low, close
  - `quote(security_ids)` - full quote with depth
- [x] Batch requests to minimize API calls
- [x] Return `MarketQuote` objects

### 6. Implement OrderService
- [x] Create `app/services/engines/order_service.rb`
- [x] Methods:
  - `place(order_params)` - returns `OrderResponse`
  - `modify(order_id, params)`
  - `cancel(order_id)`
  - `status(order_id)`
  - `history(from:, to:)`
- [x] Order params validation before submission
- [x] Map DhanHQ order types: LIMIT, MARKET, SL, SL_M
- [x] Map product types: INTRADAY, CARRYFORWARD, CO, OCO
- [x] Idempotency key support for retries

### 7. Implement PositionService
- [x] Create `app/services/engines/position_service.rb`
- [x] Methods:
  - `positions` - all open positions
  - `holdings` - delivery holdings
  - `position(security_id)` - single position detail
- [x] Return `Position` objects with unrealized P&L
- [x] Sync with local `positions` table

### 8. Implement FundsService
- [x] Create `app/services/engines/funds_service.rb`
- [x] Methods:
  - `available_margin` - cash available for trading
  - `used_margin` - margin blocked by positions
  - `span_margin` - SPAN margin requirement
  - `exposure_margin` - exposure margin
- [x] Cache for 30 seconds (changes infrequently)

### 9. Implement MarginCalculatorService
- [x] Create `app/services/engines/margin_calculator_service.rb`
- [x] Method: `estimate(order_params)` - pre-trade margin check
- [x] Use DhanHQ margin calculator API
- [x] Return: `total_margin`, `span`, `exposure`, `additional`
- [x] Validate against `AppConfig.risk.max_margin_utilization`

### 10. Create InstrumentManager
- [x] Create `app/services/instrument_manager.rb`
- [x] Auto-load on boot: NIFTY, BANKNIFTY, SENSEX, FINNIFTY
- [x] Background job: daily refresh from DhanHQ security master
- [x] Methods:
  - `underlyings` - array of active index symbols
  - `current_expiry(underlying)` - nearest weekly/monthly
  - `atm_strike(underlying, expiry)` - calculate from spot
  - `strikes_around_atm(underlying, expiry, range: 5)` - ATM ± N
- [x] Watch for expiry rollover (Thursday expiry)

### 11. Implement ATM Strike Calculation
- [x] Calculate ATM from spot price (round to nearest strike interval)
- [x] Strike intervals: NIFTY 50, BANKNIFTY 100, FINNIFTY 50, SENSEX 100
- [x] Dynamic rolling: re-calculate when spot moves > 0.5% from last ATM
- [x] Cache ATM strike in Redis (TTL: 30s)

### 12. Track ATM ±5 Strikes
- [x] Subscribe to 11 strikes per expiry per index (ATM-5 to ATM+5)
- [x] Auto-rebalance on index moves > strike interval
- [x] Maintain subscription list in Redis
- [x] WebSocket resubscribe on ATM change

### 13. Add Request/Response Logging
- [x] Structured JSON logging for all Dhanhq.requests`
- [x] Fields: method, endpoint, duration_ms, status, retry_count, sanitized_params
- [x] Sanitize: access_token, client_id, Authorization header
- [x] Log level: INFO for success, WARN for retry, ERROR for failure

### 14. Implement Circuit Breaker
- [x] Use `circuitbox` gem or custom implementation
- [x] State: closed → open → half-open → closed
- [x] Thresholds: 5 failures in 10s opens, 1 success in half-open closes
- [x] Separate breakers per endpoint group (orders, quotes, chain)
- [x] Alert on circuit open via EventBus

### 15. Add Metrics Collection
- [x] Use `prometheus-client` for metrics
- [x] Metrics:
  - `dhanhq_request_duration_seconds` (histogram by endpoint)
  - `dhanhq_requests_total` (counter by endpoint, status)
  - `dhanhq_retries_total` (counter by endpoint)
  - `dhanhq_circuit_breaker_state` (gauge: 0=closed, 1=half-open, 2=open)
- [x] Expose via `/metrics` endpoint

### 16. Write VCR Integration Tests
- [x] Add `vcr` gem to test group
- [x] Create cassettes for each service method
- [x] Test fixtures in `spec/fixtures/dhanhq/`
- [x] Configure `vcr` to filter sensitive data
- [x] Run in CI with recorded cassettes

### 17. Add WebMock Stubs for Offline Development
- [x] Create `spec/support/webmock_stubs.rb`
- [x] Stub all DhanHQ endpoints with realistic responses
- [x] Enable via `WEB_MOCK=true` env var
- [x] Include error scenarios (rate limit, auth failure, maintenance)

### 18. Create Broker API Documentation
- [x] Create `docs/broker_api.md` with:
  - Table mapping each DhanHQ endpoint to our service method
  - Request/response examples
  - Rate limits and quotas
  - Error codes and handling
  - Sandbox vs production differences

---

## Acceptance Criteria
- [x] All 9 services implemented and tested
- [x] Circuit breaker activates and recovers correctly
- [x] Retry logic handles transient failures
- [x] Metrics exposed and scrapable
- [x] VCR tests pass in CI
- [x] WebMock mode works for offline development
- [x] InstrumentManager loads 4 indices with correct strikes
- [x] ATM calculation matches manual verification
- [x] Order placement flow works end-to-end in sandbox

---

## Notes
- Keep DhanHQ gem as dependency for now; wrapper isolates changes
- Use `Faraday::Request::Retry` middleware for retry logic
- All services return `Result` objects (success/failure)
- Sandbox credentials in `.env.paper`, production in credentials
- Document any DhanHQ API quirks in `docs/broker_api.md`