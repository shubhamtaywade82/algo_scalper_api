# Milestone 11.1: Live Trading Deployment

**Phase:** 11 — Live Trading & Operations  
**Goal:** Production deployment with safety mechanisms.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Implement LiveTradingGuard
- [x] Implemented via `Entries::Guards::DailyLimitsGuard` and `Capital::Allocator`
- [x] Enforces strategy/instrument-specific capital caps and maximum drawdown protections

### 2. Add TradingHoursEnforcer
- [x] Implemented via `Entries::Guards::TradingTimeRestrictionGuard` and `EarliestEntryGuard`
- [x] Prevents entries before opening session range or after intraday closing cutoff

### 3. Create BrokerConnectionMonitor
- [x] Implemented inside `Live::MarketFeedHub` and WebSocket connection managers
- [x] Reconnects automatically and alerts/halts on extended broker failures

### 4. Implement DataQualityGate
- [x] Implemented via `Entries::Guards::LtpResolutionGuard` and indicators latency checks
- [x] Blocks entries if quote latencies or candle age exceed thresholds

### 5. Add RiskCircuitBreaker
- [x] Implemented via `Entries::Guards::DrawdownGuard` and `DailyLimitsGuard`
- [x] Halts trading and prevents new entries upon account loss limits activation

### 6. Create EmergencyStopButton
- [x] Controller endpoints support manual halting of trading daemons and clearing position registers

### 7. Implement GracefulShutdown
- [x] The supervisor/daemon lifecycle (`lib/trading_system/supervisor.rb`) intercepts SIGINT/SIGTERM, cancels pending orders, and exits cleanly

### 8. Add DeploymentChecklist
- [x] Pre-deployment checks integrated via Git hooks and CI configurations
- [x] Includes `rspec` test suite runs, `brakeman` security audits, and RuboCop styling checks

### 9. Create Runbook
- [x] Runbook procedures and deployment rules documented in project files

### 10. Implement IncidentResponse
- [x] Integrates Telegram alerts for high-priority trading alerts and daemon exceptions

### 11. Add PostTradeReconciliation
- [x] EOD jobs reconcile local double-entry ledger with broker balances

### 12. Document Live Trading Procedures
- [x] Documented in [GO_LIVE_PLAN.md](file:///home/nemesis/project/trading-workspace/algo_scalper_api/docs/GO_LIVE_PLAN.md)

---

## Acceptance Criteria
- [x] LiveTradingGuard enforces capital limits
- [x] TradingHoursEnforcer blocks off-hours trades
- [x] Broker monitor detects and alerts on disconnect
- [x] DataQualityGate prevents trading on stale data
- [x] RiskCircuitBreaker activates on limit breach
- [x] EmergencyStopButton works with authorized control APIs
- [x] GracefulShutdown completes cleanly
- [x] DeploymentChecklist passes before deploy
- [x] Runbook covers all common operations
- [x] IncidentResponse routes alerts correctly to Telegram channels
- [x] Reconciliation runs daily to verify balances
- [x] Live trading procedures and go-live plan documented

---

## Notes
- Live deployment ONLY after paper trading gate passed
- First week: reduced capital (25%), enhanced monitoring
- Daily standup during market hours for first month
- Emergency contacts: 24/7 rotation
- Broker EOD files available ~18:00 IST
- Consider: canary deployment (one strategy first)