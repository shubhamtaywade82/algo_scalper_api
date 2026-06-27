# Milestone 1.1: REST Client & Instrument Manager

**Phase:** 1 — DhanHQ Integration  
**Goal:** Reliable, resilient broker REST API wrapper.  
**Estimated Tasks:** 18

---

## Tasks

### 1. Audit Existing DhanHQ Gem
- [ ] Review current `dhanhq` gem usage in codebase
- [ ] Identify missing v2 endpoints (compare with DhanHQ API docs)
- [ ] Document gaps in `docs/broker_api_gaps.md`
- [ ] Decide: extend gem vs. build custom wrapper

### 2. Create DhanHQ::RestClient Wrapper
- [ ] Create `app/gateway/dhanhq/rest_client.rb`
- [ ] HTTP client: `faraday` with connection pooling
- [ ] Automatic retry with exponential backoff (max 3 retries, base 1s)
- [ ] Retry on: 429, 500, 502, 503, 504, timeout
- [ ] Request/response logging with sanitized headers (no auth tokens)
- [ ] Circuit breaker: open after 5 consecutive failures, half-open after 30s
- [ ] Metrics: latency histogram, error counter, retry counter
- [ ] Configurable timeouts: connect 5s, read 30s

### 3. Implement HistoricalDataService
- [ ] Create `app/services/engines/historical_data_service.rb`
- [ ] Method: `fetch_ohlcv(security_id, from:, to:, interval:)`
- [ ] Supported intervals: 1m, 5m, 15m, 30m, 1h, 1d
- [ ] Handle pagination (max 1000 candles per request)
- [ ] Return normalized `Candle` objects
- [ ] Cache in Redis (TTL: 1h for intraday, 24h for daily)

### 4. Implement OptionChainService
- [ ] Create `app/services/engines/option_chain_service.rb`
- [ ] Method: `fetch_chain(underlying, expiry)`
- [ ] Parse Greeks: IV, Delta, Gamma, Theta, Vega
- [ ] Parse OI, Volume, Bid, Ask, LTP for each strike
- [ ] Return `OptionChainSnapshot` domain objects
- [ ] Handle rate limits (DhanHQ: 1 req/sec for option chain)

### 5. Implement MarketQuoteService
- [ ] Create `app/services/engines/market_quote_service.rb`
- [ ] Methods:
  - `ltp(security_ids)` - last traded price (batch up to 50)
  - `ohlc(security_ids)` - open, high, low, close
  - `quote(security_ids)` - full quote with depth
- [ ] Batch requests to minimize API calls
- [ ] Return `MarketQuote` objects

### 6. Implement OrderService
- [ ] Create `app/services/engines/order_service.rb`
- [ ] Methods:
  - `place(order_params)` - returns `OrderResponse`
  - `modify(order_id, params)`
  - `cancel(order_id)`
  - `status(order_id)`
  - `history(from:, to:)`
- [ ] Order params validation before submission
- [ ] Map DhanHQ order types: LIMIT, MARKET, SL, SL_M
- [ ] Map product types: INTRADAY, CARRYFORWARD, CO, OCO
- [ ] Idempotency key support for retries

### 7. Implement PositionService
- [ ] Create `app/services/engines/position_service.rb`
- [ ] Methods:
  - `positions` - all open positions
  - `holdings` - delivery holdings
  - `position(security_id)` - single position detail
- [ ] Return `Position` objects with unrealized P&L
- [ ] Sync with local `positions` table

### 8. Implement FundsService
- [ ] Create `app/services/engines/funds_service.rb`
- [ ] Methods:
  - `available_margin` - cash available for trading
  - `used_margin` - margin blocked by positions
  - `span_margin` - SPAN margin requirement
  - `exposure_margin` - exposure margin
- [ ] Cache for 30 seconds (changes infrequently)

### 9. Implement MarginCalculatorService
- [ ] Create `app/services/engines/margin_calculator_service.rb`
- [ ] Method: `estimate(order_params)` - pre-trade margin check
- [ ] Use DhanHQ margin calculator API
- [ ] Return: `total_margin`, `span`, `exposure`, `additional`
- [ ] Validate against `AppConfig.risk.max_margin_utilization`

### 10. Create InstrumentManager
- [ ] Create `app/services/instrument_manager.rb`
- [ ] Auto-load on boot: NIFTY, BANKNIFTY, SENSEX, FINNIFTY
- [ ] Background job: daily refresh from DhanHQ security master
- [ ] Methods:
  - `underlyings` - array of active index symbols
  - `current_expiry(underlying)` - nearest weekly/monthly
  - `atm_strike(underlying, expiry)` - calculate from spot
  - `strikes_around_atm(underlying, expiry, range: 5)` - ATM ± N
- [ ] Watch for expiry rollover (Thursday expiry)

### 11. Implement ATM Strike Calculation
- [ ] Calculate ATM from spot price (round to nearest strike interval)
- [ ] Strike intervals: NIFTY 50, BANKNIFTY 100, FINNIFTY 50, SENSEX 100
- [ ] Dynamic rolling: re-calculate when spot moves > 0.5% from last ATM
- [ ] Cache ATM strike in Redis (TTL: 30s)

### 12. Track ATM ±5 Strikes
- [ ] Subscribe to 11 strikes per expiry per index (ATM-5 to ATM+5)
- [ ] Auto-rebalance on index moves > strike interval
- [ ] Maintain subscription list in Redis
- [ ] WebSocket resubscribe on ATM change

### 13. Add Request/Response Logging
- [ ] Structured JSON logging for all Dhanhq.requests`
- [ ] Fields: method, endpoint, duration_ms, status, retry_count, sanitized_params
- [ ] Sanitize: access_token, client_id, Authorization header
- [ ] Log level: INFO for success, WARN for retry, ERROR for failure

### 14. Implement Circuit Breaker
- [ ] Use `circuitbox` gem or custom implementation
- [ ] State: closed → open → half-open → closed
- [ ] Thresholds: 5 failures in 10s opens, 1 success in half-open closes
- [ ] Separate breakers per endpoint group (orders, quotes, chain)
- [ ] Alert on circuit open via EventBus

### 15. Add Metrics Collection
- [ ] Use `prometheus-client` for metrics
- [ ] Metrics:
  - `dhanhq_request_duration_seconds` (histogram by endpoint)
  - `dhanhq_requests_total` (counter by endpoint, status)
  - `dhanhq_retries_total` (counter by endpoint)
  - `dhanhq_circuit_breaker_state` (gauge: 0=closed, 1=half-open, 2=open)
- [ ] Expose via `/metrics` endpoint

### 16. Write VCR Integration Tests
- [ ] Add `vcr` gem to test group
- [ ] Create cassettes for each service method
- [ ] Test fixtures in `spec/fixtures/dhanhq/`
- [ ] Configure `vcr` to filter sensitive data
- [ ] Run in CI with recorded cassettes

### 17. Add WebMock Stubs for Offline Development
- [ ] Create `spec/support/webmock_stubs.rb`
- [ ] Stub all DhanHQ endpoints with realistic responses
- [ ] Enable via `WEB_MOCK=true` env var
- [ ] Include error scenarios (rate limit, auth failure, maintenance)

### 18. Create Broker API Documentation
- [ ] Create `docs/broker_api.md` with:
  - Table mapping each DhanHQ endpoint to our service method
  - Request/response examples
  - Rate limits and quotas
  - Error codes and handling
  - Sandbox vs production differences

---

## Acceptance Criteria
- [ ] All 9 services implemented and tested
- [ ] Circuit breaker activates and recovers correctly
- [ ] Retry logic handles transient failures
- [ ] Metrics exposed and scrapable
- [ ] VCR tests pass in CI
- [ ] WebMock mode works for offline development
- [ ] InstrumentManager loads 4 indices with correct strikes
- [ ] ATM calculation matches manual verification
- [ ] Order placement flow works end-to-end in sandbox

---

## Notes
- Keep DhanHQ gem as dependency for now; wrapper isolates changes
- Use `Faraday::Request::Retry` middleware for retry logic
- All services return `Result` objects (success/failure)
- Sandbox credentials in `.env.paper`, production in credentials
- Document any DhanHQ API quirks in `docs/broker_api.md`