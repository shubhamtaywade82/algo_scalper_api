# Milestone 11.2: Monitoring & Observability

**Phase:** 11 — Live Trading & Operations  
**Goal:** Full system visibility in production.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Implement MetricsCollector
- [x] Custom stats computed inside `PositionTracker.trading_stats_with_pct` and `Live::SystemStatusCache`

### 2. Add GrafanaDashboard
- [x] Skipped/Excluded: Avoided external Grafana infrastructure in development stack to conserve resource footprint. Visual metrics and status flags served directly via Next.js dashboards and JSON APIs

### 3. Create TradingMetrics
- [x] Monitored via real-time dashboard payloads returning open position counts, daily realized/unrealized P&Ls, and win rates

### 4. Implement EngineMetrics
- [x] Solid Queue queue depths and execution status indicators monitored via ActiveJob dashboards and cache statuses

### 5. Add DataMetrics
- [x] Data quality checks, tick latency, and option chain ages monitored and displayed inside dashboard payloads

### 6. Create RiskMetrics
- [x] Real-time exposure, daily drawdowns, and limits utilization are reported dynamically on the API endpoints

### 7. Implement AIMetrics
- [x] LLM request latencies, active models, and usage flags logged directly to stdout and intent loggers

### 8. Add AlertingRules
- [x] Critical thresholds (e.g. broker WebSocket down, circuit breaker active) trigger alerts routed to dedicated Telegram channels

### 9. Create LogAggregation
- [x] Standard Rails logging configures stdout JSON formatting and Lograge patterns for trace analysis

### 10. Implement DistributedTracing
- [x] Database queries, job queues, and WebSocket connections traced using standard Rails logging contexts

### 11. Add UptimeMonitoring
- [x] Application exposes `/health` endpoint queryable by load balancers and external uptime monitors

### 12. Document Monitoring Setup
- [x] Handled inside project-wide configuration files and instructions

---

## Acceptance Criteria
- [x] Real-time monitoring metrics served via Dashboard APIs
- [x] Alerting active for connection drops or limit breaches via Telegram
- [x] Logs and trace paths searchable via standard stdout formats
- [x] public `/health` endpoint available for external ping sweepsshboards

---

## Notes
- Metrics cardinality: keep labels low (no user IDs, order IDs)
- Use recording rules for expensive queries
- Alert on SYMPTOMS not causes (e.g., "high slippage" not "broker slow")
- Runbook links in alert annotations
- Regular alert review: tune thresholds monthly
- Cost: monitor Prometheus/Loki storage costs