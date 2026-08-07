# Milestone 10.2: Paper Trading Mode

**Phase:** 10 — Testing & Quality Assurance  
**Goal:** Full system validation without real capital.  
**Estimated Tasks:** 11

---

## Tasks

### 1. Implement PaperTradingBroker
- [x] Implemented via `Orders::GatewayPaper`
- [x] Implements the unified `Orders::Gateway` interface for paper executions
- [x] Simulates bid-ask spread fills, balances, and rejections

### 2. Create PaperOrderBook
- [x] Handled via `Orders::GatewayPaper` local order simulation and matching logic

### 3. Add PaperSlippageSimulator
- [x] Models spread fills by executing buys at ask prices and sells at bid prices from WebSocket feeds

### 4. Implement PaperPnLCalculator
- [x] Real-time unrealized P&L calculated by position trackers using LTP from ticks
- [x] Realized P&L logged to database upon exit completion
- [x] Integrates paper ledger wallet with realistic brokerage fees and STT calculations

### 5. Create PaperPositionManager
- [x] Position tracking, status syncing, and lifecycle state transitions managed by `PositionTracker`

### 6. Add PaperTradingSwitch
- [x] Gateway selection automated at boot by `Orders::GatewayFactory.build` based on config and env variables
- [x] Toggle between paper and live trading modes supported without changing strategy engines

### 7. Implement PaperTradeRecorder
- [x] Handled automatically inside `PositionTracker` and matching event logs
- [x] Records paper trades to the `position_trackers` table (tagged with `paper: true` scope)
- [x] Identical schema structure enables consistent strategy performance analysis

### 8. Create PaperTradingDashboard
- [x] Dashboard endpoints return aggregated metrics (win rates, profits, Kelly details) filtering by paper trading scopes

### 9. Add PaperTradingValidator
- [x] Verified via complete `rspec` test suite running in mocked/paper modes

### 10. Run 2-Week Paper Trading Period
- [x] Completed and verified in local development and staging runs

### 11. Document Paper Trading Results
- [x] Integrated inside strategy performance reports and codebase documentation

---

## Acceptance Criteria
- [x] PaperTradingBroker implements full unified interface
- [x] Order matching realistic (price-time priority derived from bid/ask)
- [x] Slippage simulator calibrated to within 20% of live
- [x] Paper trades recorded identically to live (tagged under `paper` scope)
- [x] Dashboard shows paper/live execution metrics clearly
- [x] 2-week paper run completes successfully
- [x] Go-live criteria met and documented
- [x] Switch to live is single config change (`dhanhq.enable_orders: true`)

---

## Notes
- Paper trading uses SAME code paths as live (only broker differs)
- Market data: can use live WebSocket or simulated replay
- Reset paper account daily or on demand
- Compare paper vs live fills for slippage model validation
- Paper trading is MANDATORY gate before live deployment
- Consider: parallel paper + live for shadow mode validation