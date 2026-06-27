# Milestone 11.2: Monitoring & Observability

**Phase:** 11 — Live Trading & Operations  
**Goal:** Full system visibility in production.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Implement MetricsCollector
- [ ] Create `app/services/metrics_collector.rb`
- [ ] Use `prometheus-client` gem
- [ ] Custom metrics registry (separate from default)
- [ ] Push gateway for batch jobs (Solid Queue workers)
- [ ] Metric naming convention: `algoscalper_{subsystem}_{metric}`
- [ ] Labels: environment, instance, strategy, instrument

### 2. Add GrafanaDashboard
- [ ] Create `monitoring/grafana/dashboards/`
- [ ] Dashboards:
  - `system-overview.json` (CPU, memory, disk, network, GC)
  - `trading-metrics.json` (orders, fills, P&L, risk)
  - `engine-latency.json` (per-engine p50/p95/p99)
  - `data-quality.json` (tick lag, gaps, freshness)
  - `ai-gateway.json` (latency, cost, success rate)
  - `business.json` (daily P&L, win rate, drawdown)
- [ ] Provision via Grafana API or ConfigMaps
- [ ] Alerting rules in dashboard annotations

### 3. Create TradingMetrics
- [ ] Metrics:
  - `algoscalper_orders_total` (counter: placed, filled, cancelled, rejected)
  - `algoscalper_fills_total` (counter by strategy, instrument)
  - `algoscalper_slippage_bps` (histogram by instrument, strategy)
  - `algoscalper_fill_rate` (gauge: fills/placed)
  - `algoscalper_order_latency_ms` (histogram)
  - `algoscalper_position_count` (gauge by instrument)
  - `algoscalper_daily_pnl` (gauge)
  - `algoscalper_risk_utilization` (gauge: daily/weekly/monthly)

### 4. Implement EngineMetrics
- [ ] Metrics per engine:
  - `algoscalper_engine_latency_ms` (histogram by engine)
  - `algoscalper_engine_output_score` (gauge: last score)
  - `algoscalper_engine_errors_total` (counter by error type)
  - `algoscalper_queue_depth` (gauge: Solid Queue per queue)
  - `algoscalper_worker_count` (gauge)
  - `algoscalper_job_duration_ms` (histogram by job)

### 5. Add DataMetrics
- [ ] Metrics:
  - `algoscalper_tick_lag_ms` (gauge: now - tick_timestamp)
  - `algoscalper_candle_freshness_s` (gauge per timeframe)
  - `algoscalper_gap_count` (counter by instrument)
  - `algoscalper_tick_throughput` (gauge: ticks/sec ingested)
  - `algoscalper_option_chain_age_s` (gauge)
  - `algoscalper_depth_update_lag_ms` (gauge)

### 6. Create RiskMetrics
- [ ] Metrics:
  - `algoscalper_exposure_rupees` (gauge by instrument)
  - `algoscalper_margin_utilization` (gauge)
  - `algoscalper_daily_loss_rupees` (gauge)
  - `algoscalper_weekly_loss_rupees` (gauge)
  - `algoscalper_monthly_loss_rupees` (gauge)
  - `algoscalper_drawdown_pct` (gauge)
  - `algoscalper_max_drawdown_pct` (gauge)
  - `algoscalper_risk_limit_breaches` (counter)

### 7. Implement AIMetrics
- [ ] Metrics:
  - `algoscalper_ai_request_latency_ms` (histogram by agent, provider)
  - `algoscalper_ai_requests_total` (counter by provider, status)
  - `algoscalper_ai_tokens_used` (counter by provider, model)
  - `algoscalper_ai_cost_usd` (counter by provider)
  - `algoscalper_ai_success_rate` (gauge)
  - `algoscalper_ai_provider_healthy` (gauge per provider)
  - `algoscalper_ai_key_quarantined` (gauge)

### 8. Add AlertingRules
- [ ] Prometheus alerting rules (`monitoring/alerts.yml`):
  - `TradingHalted` (risk circuit breaker active)
  - `HighSlippage` (avg slippage > 5 bps for 5 min)
  - `DataStale` (tick lag > 5s)
  - `BrokerDisconnected` (WebSocket down > 30s)
  - `EngineLatencyHigh` (p99 > budget for 5 min)
  - `QueueBacklog` (Solid Queue depth > 1000)
  - `AIDegraded` (primary provider down)
  - `DiskSpaceLow` (> 80%)
  - `MemoryHigh` (> 85%)
- [ ] Routes: P1 → PagerDuty, P2 → Slack, P3 → Email

### 9. Create LogAggregation
- [ ] Structured JSON logging (`lograge` + custom)
- [ ] Fields: `timestamp`, `level`, `service`, `trace_id`, `span_id`, `message`, `context`
- [ ] Ship to: Loki / Elasticsearch / CloudWatch
- [ ] Retention: 30 days hot, 1 year cold
- [ ] Queries: by trace_id, service, time range

### 10. Implement DistributedTracing
- [ ] Add `opentelemetry` gem
- [ ] Instrument: HTTP clients, DB queries, Redis, jobs
- [ ] Trace context propagation: HTTP headers, job args
- [ ] Exporters: Jaeger / Zipkin / OTLP
- [ ] Sampling: 10% requests, 100% errors
- [ ] Key traces: order placement, risk check, AI request

### 11. Add UptimeMonitoring
- [ ] External: Pingdom / UptimeRobot / BetterUptime
- [ ] Checks:
  - `GET /health` (every 30s)
  - `GET /api/v1/dashboard/regime` (every 60s)
  - WebSocket connection test
- [ ] Alert: downtime > 1 min
- [ ] Status page: public status.io page

### 12. Document Monitoring Setup
- [ ] Create `docs/monitoring.md` with:
  - Metrics catalog (all metrics with descriptions)
  - Dashboard links and usage
  - Alert runbooks (per alert: meaning, investigation, resolution)
  - Log query examples
  - Trace analysis guide
  - Capacity planning thresholds
  - On-call handoff checklist

---

## Acceptance Criteria
- [ ] All 7 metric categories implemented and scraping
- [ ] Grafana dashboards load in < 5s
- [ ] Alerting rules fire correctly (test with `amtool`)
- [ ] Logs searchable by trace_id
- [ ] Distributed traces show full request flow
- [ ] External uptime monitoring active
- [ ] Documentation complete and accurate
- [ ] On-call can diagnose issues from dashboards

---

## Notes
- Metrics cardinality: keep labels low (no user IDs, order IDs)
- Use recording rules for expensive queries
- Alert on SYMPTOMS not causes (e.g., "high slippage" not "broker slow")
- Runbook links in alert annotations
- Regular alert review: tune thresholds monthly
- Cost: monitor Prometheus/Loki storage costs