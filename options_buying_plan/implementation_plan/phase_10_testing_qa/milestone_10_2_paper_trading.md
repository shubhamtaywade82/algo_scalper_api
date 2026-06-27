# Milestone 10.2: Paper Trading Mode

**Phase:** 10 — Testing & Quality Assurance  
**Goal:** Full system validation without real capital.  
**Estimated Tasks:** 11

---

## Tasks

### 1. Implement PaperTradingBroker
- [ ] Create `app/gateway/paper_trading_broker.rb`
- [ ] Implements same interface as `DhanHQ::RestClient`
- [ ] In-memory order book with price-time priority
- [ ] Simulate: fills, partial fills, rejections, slippage
- [ ] Configurable: fill probability, latency, spread widening

### 2. Create PaperOrderBook
- [ ] Create `app/gateway/paper_order_book.rb`
- [ ] Separate books per instrument
- [ ] Order types: LIMIT, MARKET, SL, SL_M
- [ ] Matching engine: price-time priority
- [ ] Market orders: cross spread, walk book
- [ ] Limit orders: queue at price level

### 3. Add PaperSlippageSimulator
- [ ] Create `app/gateway/paper_slippage_simulator.rb`
- [ ] Models realistic fills:
  - Spread cost: always pay half spread
  - Market impact: `size / avg_volume * ATR * factor`
  - Timing slippage: random walk during order latency
  - Queue position: partial fills if not at front
- [ ] Configurable per instrument/regime
- [ ] Calibrate against historical DhanHQ fills

### 4. Implement PaperPnLCalculator
- [ ] Create `app/services/paper_pnl_calculator.rb`
- [ ] Real-time unrealized P&L from paper positions
- [ ] Mark-to-market: use simulated LTP
- [ ] Realized P&L on paper exits
- [ ] Fees: STT, exchange charges, brokerage, GST
- [ ] Margin: SPAN + exposure simulation

### 5. Create PaperPositionManager
- [ ] Create `app/services/paper_position_manager.rb`
- [ ] Tracks paper positions (separate from live)
- [ ] Sync with PaperBroker on every fill
- [ ] Handles: corporate actions (split, bonus - adjust qty/price)
- [ ] Expiry: auto-close ITM options at intrinsic value

### 6. Add PaperTradingSwitch
- [ ] Create `AppConfig.trading.mode` (:live, :paper, :backtest)
- [ ] Environment variable: `TRADING_MODE=paper`
- [ ] Container registration: `broker_gateway` → PaperTradingBroker in paper mode
- [ ] All engines unchanged (they use broker_gateway interface)
- [ ] Dashboard shows [PAPER] badge

### 7. Implement PaperTradeRecorder
- [ ] Create `app/services/paper_trade_recorder.rb`
- [ ] Records paper trades to same tables (`trades`, `trade_features`)
- [ ] Tag: `source: 'paper'` for filtering
- [ ] Identical data structure as live trades
- [ ] Enables: same learning, performance, analytics

### 8. Create PaperTradingDashboard
- [ ] Extend DashboardController with paper mode
- [ ] Paper-specific metrics:
  - Simulated vs theoretical fills
  - Slippage model accuracy
  - Queue position distribution
- [ ] Comparison: paper vs live (when both running)
- [ ] Reset button: clear paper account, restart

### 9. Add PaperTradingValidator
- [ ] Create `app/services/paper_trading_validator.rb`
- [ ] Validates system behavior in paper mode:
  - Engine outputs match expectations
  - Risk rules enforced
  - Position management actions logged
  - No live API calls made
- [ ] Run: automated test suite in paper mode

### 10. Run 2-Week Paper Trading Period
- [ ] Schedule: 10 trading days minimum
- [ ] Criteria for go-live:
  - Zero critical bugs
  - Paper Sharpe > 1.0
  - Max drawdown < 5%
  - Fill rate > 95%
  - Slippage model within 20% of actual
  - All alerts functioning
  - Reconciliation clean daily
- [ ] Document results in `docs/paper_trading_results.md`

### 11. Document Paper Trading Results
- [ ] Create `docs/paper_trading.md` with:
  - Configuration used
  - Daily P&L log
  - Strategy performance breakdown
  - Execution quality metrics
  - Issues found and fixed
  - Go/No-go decision with rationale

---

## Acceptance Criteria
- [ ] PaperTradingBroker implements full DhanHQ interface
- [ ] Order matching realistic (price-time priority)
- [ ] Slippage simulator calibrated to within 20% of live
- [ ] Paper trades recorded identically to live
- [ ] Dashboard shows paper mode clearly
- [ ] 2-week paper run completes successfully
- [ ] Go-live criteria met and documented
- [ ] Switch to live is single config change

---

## Notes
- Paper trading uses SAME code paths as live (only broker differs)
- Market data: can use live WebSocket or simulated replay
- Reset paper account daily or on demand
- Compare paper vs live fills for slippage model validation
- Paper trading is MANDATORY gate before live deployment
- Consider: parallel paper + live for shadow mode validation