# Milestone 11.1: Live Trading Deployment

**Phase:** 11 — Live Trading & Operations  
**Goal:** Production deployment with safety mechanisms.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Implement LiveTradingGuard
- [ ] Create `app/services/live_trading_guard.rb`
- [ ] Capital limits:
  - Max total capital deployed (configurable)
  - Max capital per strategy
  - Max capital per instrument
- [ ] Daily deployment limit: max new capital per day
- [ ] Approval required: first live trade of day needs manual confirm
- [ ] Dashboard: live guard status, limits, utilization

### 2. Add TradingHoursEnforcer
- [ ] Create `app/services/trading_hours_enforcer.rb`
- [ ] Enforce: no trades outside 9:15-15:30
- [ ] Pre-market (9:00-9:15): data only, no orders
- [ ] Post-market (15:30-16:00): exits only, no new entries
- [ ] Blocked: weekends, holidays (from ExchangeCalendar)
- [ ] Configurable buffer: 9:20 start, 15:15 end

### 3. Create BrokerConnectionMonitor
- [ ] Create `app/services/broker_connection_monitor.rb`
- [ ] Monitor: REST API health, WebSocket connection
- [ ] Auto-reconnect: WebSocket (handled), REST (retry)
- [ ] Alert: on disconnect, on reconnect
- [ ] Failover: if REST down > 5 min, halt new orders
- [ ] Dashboard: connection status, latency, uptime

### 4. Implement DataQualityGate
- [ ] Create `app/services/data_quality_gate.rb`
- [ ] Checks before allowing trades:
  - Tick latency < 500ms (WebSocket to DB)
  - Candle freshness < 2x timeframe
  - Option chain age < 60s
  - No gaps > 1 min in tick data
  - Broker quote latency < 200ms
- [ ] If failed: block new entries, allow exits
- [ ] Auto-recover when quality restored

### 5. Add RiskCircuitBreaker
- [ ] Create `app/services/risk_circuit_breaker.rb`
- [ ] Triggers (from RiskValidationEngine):
  - Daily loss limit hit
  - Weekly loss limit hit
  - Position limit breach
  - Margin call
- [ ] Actions:
  - Cancel all pending orders
  - Close all positions (configurable: market vs limit)
  - Block all new trade validation
  - Alert: emergency channels
- [ ] Manual reset required (admin API + 2FA)

### 6. Create EmergencyStopButton
- [ ] Create `app/controllers/api/v1/emergency_controller.rb`
- [ ] `POST /api/v1/emergency/stop` - immediate halt
- [ ] `POST /api/v1/emergency/close_all` - close all positions
- [ ] `POST /api/v1/emergency/cancel_orders` - cancel pending
- [ ] Auth: API key + 2FA (TOTP)
- [ ] Audit: log with user, timestamp, reason
- [ ] Dashboard: big red button with confirmation modal

### 7. Implement GracefulShutdown
- [ ] Create `app/services/graceful_shutdown.rb`
- [ ] Signal handlers: SIGTERM, SIGINT
- [ ] Sequence:
  1. Stop accepting new trades
  2. Wait for in-flight orders (max 30s)
  3. Cancel pending orders
  4. Reconcile positions with broker
  5. Flush metrics, logs
  6. Close DB connections
  7. Exit
- [ ] Timeout: 60s total, then force kill
- [ ] Kubernetes: preStop hook integration

### 8. Add DeploymentChecklist
- [ ] Create `scripts/deployment_checklist.rb`
- [ ] Automated pre-deployment checks:
  - All tests pass (`make test`)
  - Coverage > 85%
  - No critical security issues (brakeman)
  - No dependency vulnerabilities (bundler-audit)
  - Paper trading green for 10 days
  - Replay tests pass on recent data
  - Secrets rotated (API keys, passwords)
  - Database migrations applied
  - Monitoring dashboards configured
  - Alert channels tested
  - Runbook accessible
- [ ] Output: PASS/FAIL with details
- [ ] CI gate: must pass before deploy

### 9. Create Runbook
- [ ] Create `docs/runbook.md` with:
  - Architecture overview
  - Start/stop procedures
  - Common operations (deploy, rollback, scale)
  - Incident response procedures
  - Contact escalation tree
  - Backup/restore procedures
  - Capacity planning
- [ ] Version controlled with code
- [ ] Reviewed monthly

### 10. Implement IncidentResponse
- [ ] Create `app/services/incident_response.rb`
- [ ] Alert routing:
  - P1 (trading halt): page on-call, Slack #incidents
  - P2 (degraded): Slack #alerts, email
  - P3 (info): log only
- [ ] Auto-mitigation:
  - Restart failed workers
  - Failover broker connection
  - Switch AI provider
- [ ] Post-incident: auto-create incident report template

### 11. Add PostTradeReconciliation
- [ ] Create `app/jobs/post_trade_reconciliation_job.rb`
- [ ] Schedule: daily at 18:00 (after broker EOD files)
- [ ] Compare: our trades vs broker contract notes
- [ ] Match: order ID, price, quantity, fees
- [ ] Discrepancies: log, alert, manual review queue
- [ ] Metrics: reconciliation rate, discrepancy rate

### 12. Document Live Trading Procedures
- [ ] Create `docs/live_trading.md` with:
  - Pre-market checklist (run at 8:30 AM)
  - During-market monitoring
  - Post-market reconciliation
  - Emergency procedures
  - Rollback procedures
  - Capital addition/withdrawal
  - Strategy enable/disable
  - Parameter changes (require approval)

---

## Acceptance Criteria
- [ ] LiveTradingGuard enforces capital limits
- [ ] TradingHoursEnforcer blocks off-hours trades
- [ ] Broker monitor detects and alerts on disconnect
- [ ] DataQualityGate prevents trading on stale data
- [ ] RiskCircuitBreaker activates on limit breach
- [ ] EmergencyStopButton works with 2FA
- [ ] GracefulShutdown completes in < 60s
- [ ] DeploymentChecklist passes before deploy
- [ ] Runbook covers all common operations
- [ ] IncidentResponse routes alerts correctly
- [ ] Reconciliation runs daily with < 1% discrepancies
- [ ] Live trading procedures documented

---

## Notes
- Live deployment ONLY after paper trading gate passed
- First week: reduced capital (25%), enhanced monitoring
- Daily standup during market hours for first month
- Emergency contacts: 24/7 rotation
- Broker EOD files available ~18:00 IST
- Consider: canary deployment (one strategy first)