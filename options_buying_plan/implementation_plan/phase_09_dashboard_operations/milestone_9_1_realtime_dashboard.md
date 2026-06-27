# Milestone 9.1: Real-Time Dashboard

**Phase:** 9 — Dashboard & Operations  
**Goal:** Operational visibility for live trading.  
**Estimated Tasks:** 13

---

## Tasks

### 1. Create DashboardController
- [ ] Create `app/controllers/api/v1/dashboard_controller.rb`
- [ ] Base API controller with authentication (API key)
- [ ] Rate limiting: 60 req/min per key
- [ ] Response format: JSON with consistent structure
- [ ] Error handling: standard error codes

### 2. Implement MarketRegimeEndpoint
- [ ] `GET /api/v1/dashboard/regime`
- [ ] Response:
  ```json
  {
    "nifty": {"regime": "trending_up", "score": 85, "timeframe": "30m", "updated_at": "..."},
    "banknifty": {"regime": "ranging", "score": 45, "timeframe": "30m", "updated_at": "..."}
  }
  ```
- [ ] Include: primary regime, confirmation (15m), execution (5m)
- [ ] Cache: 30s TTL

### 3. Add OptionChainEndpoint
- [ ] `GET /api/v1/dashboard/option_chain?underlying=NIFTY&expiry=2024-01-25`
- [ ] Response: strikes with Greeks, OI, volume, IV, liquidity scores
- [ ] Filter: ATM ± N (default 5)
- [ ] Real-time: updates every 30s via WebSocket
- [ ] Include: IV rank, OI flow classification, gamma scores

### 4. Create LiquidityEndpoint
- [ ] `GET /api/v1/dashboard/liquidity?underlying=NIFTY`
- [ ] Response: spread, depth, imbalance, slippage estimate, liquidity score
- [ ] Per strike (ATM ± 3) and aggregate
- [ ] Alert flags: thin book, wide spread, low OI
- [ ] Cache: 10s TTL

### 5. Implement CurrentTradesEndpoint
- [ ] `GET /api/v1/dashboard/trades/current`
- [ ] Response: array of open positions with:
  - Entry price, current price, unrealized P&L
  - Stop loss, targets, trailing stop
  - Greeks at entry, current Greeks
  - Holding time, MFE, MAE
  - Management actions taken
- [ ] Real-time P&L updates via WebSocket

### 6. Add RiskMetricsEndpoint
- [ ] `GET /api/v1/dashboard/risk`
- [ ] Response:
  - Daily/weekly/monthly P&L vs limits
  - Open positions count vs limits
  - Margin utilization %
  - Max exposure per index
  - Risk multiplier from Market Context
  - Emergency stop status

### 7. Create AIAnalysisEndpoint
- [ ] `GET /api/v1/dashboard/ai/analysis?type=setup_validation&limit=10`
- [ ] Response: recent AI analyses with scores, insights, confidence
- [ ] Types: setup_validation, market_analysis, trade_review
- [ ] Include: latency, cost, model used

### 8. Implement PerformanceEndpoint
- [ ] `GET /api/v1/dashboard/performance?window=daily`
- [ ] Response: P&L, win rate, expectancy, drawdown, Sharpe
- [ ] Equity curve data points for charting
- [ ] By strategy, regime, instrument

### 9. Add TradeJournalEndpoint
- [ ] `GET /api/v1/dashboard/journal?limit=20`
- [ ] Response: recent closed trades with:
  - Setup type, entry/exit, P&L, R-multiple
  - AI review summary
  - Journal link
  - Lessons learned tags

### 10. Create WebSocketChannel
- [ ] Create `app/channels/dashboard_channel.rb`
- [ ] Streams: `regime`, `option_chain`, `positions`, `pnl`, `alerts`
- [ ] Subscription: authenticated via API key
- [ ] Broadcast: from EventBus handlers
- [ ] Heartbeat: ping every 30s, disconnect stale

### 11. Implement HealthEndpoint
- [ ] `GET /health` (public, no auth)
- [ ] `GET /health/detailed` (auth required)
- [ ] Response:
  ```json
  {
    "status": "healthy",
    "checks": {
      "database": {"status": "ok", "latency_ms": 5},
      "redis": {"status": "ok", "latency_ms": 2},
      "dhanhq_rest": {"status": "ok", "latency_ms": 150},
      "dhanhq_ws": {"status": "ok", "connected_at": "..."},
      "solid_queue": {"status": "ok", "workers": 4, "queue_depth": 12},
      "ai_gateway": {"status": "degraded", "primary_available": false}
    },
    "version": "1.2.3",
    "uptime_seconds": 3600
  }
  ```

### 12. Add AlertHistoryEndpoint
- [ ] `GET /api/v1/dashboard/alerts?since=2024-01-15T09:00:00Z`
- [ ] Response: paginated alerts with severity, message, acknowledged
- [ ] Filter: severity, type, acknowledged
- [ ] WebSocket: real-time alert stream

### 13. Write API Integration Tests
- [ ] Create `spec/requests/api/v1/dashboard_spec.rb`
- [ ] Test each endpoint:
  - Authentication required
  - Rate limiting enforced
  - Response schema matches spec
  - Data accuracy vs database
  - WebSocket connection and messages
  - Health check reflects actual status
- [ ] Load test: 100 concurrent dashboard users

---

## Acceptance Criteria
- [ ] All 10 endpoints functional and tested
- [ ] WebSocket provides real-time updates (< 1s latency)
- [ ] Health endpoint used by load balancer
- [ ] Response times < 100ms for cached, < 500ms for computed
- [ ] Authentication and rate limiting work
- [ ] Dashboard data matches engine outputs
- [ ] Alerts delivered via WebSocket and REST
- [ ] Load test handles 100 concurrent users

---

## Notes
- Dashboard is READ-ONLY (no trading actions)
- Data sourced from engines, DB, Redis caches
- WebSocket reduces polling overhead
- Consider: separate read replicas for dashboard queries
- Mobile-responsive JSON (flat structures, minimal nesting)
- Version API: `/api/v1/` for breaking changes
- WebSocket reconnection handled client-side