# Milestone 6.2: Execution Engine

**Phase:** 6 — Risk & Execution  
**Goal:** Reliable order placement with full state tracking.  
**Estimated Tasks:** 14

---

## Tasks

### 1. Implement ExecutionEngine
- [ ] Create `app/engines/execution_engine.rb`
- [ ] Interface: `execute(input) -> ExecutionOutput`
- [ ] Input: `ExecutionInput` with:
  - `trade_setup` (validated, scored, risk-approved)
  - `selected_strike` (from StrikeSelectionEngine)
  - `position_size` (from RiskValidationEngine)
  - `account_state` (margin, positions)
- [ ] Output: `ExecutionOutput` with:
  - `order_id` (internal)
  - `broker_order_id` (DhanHQ)
  - `status` (:submitted, :partial, :filled, :rejected)
  - `fills` (array of fill prices/quantities)
  - `avg_fill_price`
  - `slippage` (expected vs actual)
  - `latency_ms`

### 2. Add LimitOrderPlacer
- [ ] Create `app/engines/execution/limit_order_placer.rb`
- [ ] Default execution method for options buying
- [ ] Price: `ask + 1 tick` for buys, `bid - 1 tick` for sells (configurable)
- [ ] Validate: price within spread, not crossing market
- [ ] Order type: LIMIT, product: INTRADAY (or CARRYFORWARD)
- [ ] Return: `OrderPlacementResult` with broker_order_id

### 3. Implement SLOrderPlacer
- [ ] Create `app/engines/execution/sl_order_placer.rb`
- [ ] For stop-loss entry (breakout strategies)
- [ ] Trigger price: breakout level
- [ ] Limit price: trigger + buffer (configurable ticks)
- [ ] Order type: SL (stop-loss limit)
- [ ] Monitor trigger via WebSocket order updates

### 4. Add SuperOrderPlacer
- [ ] Create `app/engines/execution/super_order_placer.rb`
- [ ] Bracket order (target + stop) if DhanHQ supports
- [ ] Single order with: entry, target, stop-loss
- [ ] Fallback: separate target/stop orders if not supported
- [ ] Validate: target > entry > stop (for longs)

### 5. Create OrderSlicer
- [ ] Create `app/engines/execution/order_slicer.rb`
- [ ] Split large orders (> 50 lots) into slices
- [ ] Slice size: configurable (default 25 lots)
- [ ] Delay between slices: 500ms (configurable)
- [ ] Price: same limit for all slices
- [ ] Track all slices as single logical order

### 6. Implement RetryLogic
- [ ] Create `app/engines/execution/retry_logic.rb`
- [ ] Max 3 attempts with exponential backoff (1s, 2s, 4s)
- [ ] Retry on: timeout, 5xx, 429, connection error
- [ ] Don't retry on: 4xx (invalid params), rejection
- [ ] Idempotency key: use internal order_id
- [ ] Log all attempts with latency

### 7. Add PartialFillHandler
- [ ] Create `app/engines/execution/partial_fill_handler.rb`
- [ ] On partial fill:
  - Update order with filled_qty, avg_price
  - Remaining qty: keep working at same limit
  - Timeout: cancel remaining after 30s (configurable)
  - Option: re-price remaining to market (aggressive)
- [ ] Track partial fill metrics

### 8. Implement SlippageMonitor
- [ ] Create `app/engines/execution/slippage_monitor.rb`
- [ ] Expected price: limit price at submission
- [ ] Actual price: volume-weighted avg fill price
- [ ] Slippage = (actual - expected) / expected * 10000 (bps)
- [ ] Track per instrument, per strategy, per time of day
- [ ] Alert if slippage > 5 bps average

### 9. Create OrderStateTracker
- [ ] Create `app/engines/execution/order_state_tracker.rb`
- [ ] Consume WebSocket `orders.updates` channel
- [ ] State machine: PENDING → SUBMITTED → PARTIAL → FILLED/CANCELLED/REJECTED
- [ ] Persist every state change to `orders` table
- [ ] Reconcile with broker on startup and every 30s
- [ ] Alert on stuck orders (> 60s in SUBMITTED)

### 10. Add ExecutionValidator
- [ ] Create `app/engines/execution/execution_validator.rb`
- [ ] Pre-execution checks:
  - Order params valid (price, qty, symbol)
  - Margin sufficient (re-check)
  - No duplicate pending orders for same instrument
  - Market hours (9:15-15:30)
  - Not in emergency stop
- [ ] Post-execution checks:
  - Order acknowledged by broker
  - Order ID returned
  - State transition valid

### 11. Implement ExecutionMetrics
- [ ] Create `app/engines/execution/execution_metrics.rb`
- [ ] Metrics (Prometheus):
  - `execution_latency_ms` (histogram)
  - `fill_rate` (gauge, fills/submitted)
  - `avg_slippage_bps` (gauge)
  - `partial_fill_rate` (gauge)
  - `rejection_rate` (counter by reason)
  - `retry_rate` (counter)
- [ ] Dashboard: execution quality by strategy, time, instrument

### 12. Create ExecutionJournal
- [ ] Create `app/engines/execution/execution_journal.rb`
- [ ] Complete audit trail for every order:
  - Request payload (sanitized)
  - Broker response
  - All state transitions with timestamps
  - Fills with prices, quantities, fees
  - Cancels/modifications with reasons
- [ ] Immutable append-only log (JSONL file + DB)
- [ ] Query API for compliance/audit

### 13. Add OrderCancellationService
- [ ] Create `app/engines/execution/order_cancellation_service.rb`
- [ ] Emergency cancel: all open orders (panic button)
- [ ] Selective cancel: by instrument, by strategy, by age
- [ ] Cancel on: risk breach, emergency stop, end of day
- [ ] Track: cancellation latency, success rate
- [ ] Force cancel via WebSocket if REST fails

### 14. Write Integration Tests with Mocked Broker
- [ ] Create `spec/engines/execution_engine_spec.rb`
- [ ] Mock DhanHQ REST and WebSocket
- [ ] Test scenarios:
  - Clean fill (single order)
  - Partial fill then complete
  - Partial fill then timeout cancel
  - Rejection (insufficient margin)
  - Network timeout → retry → success
  - Emergency cancel all
  - Slippage calculation accuracy
  - State machine transitions

---

## Acceptance Criteria
- [ ] ExecutionEngine places order in < 200ms (p99)
- [ ] Retry logic handles transient failures gracefully
- [ ] Partial fills managed correctly (remaining qty tracked)
- [ ] Slippage monitored and alerted
- [ ] Order state synced with broker via WebSocket
- [ ] Emergency cancel works in < 1s
- [ ] Execution journal complete for audit
- [ ] Metrics show fill rate > 95%, avg slippage < 3 bps
- [ ] Integration tests cover all failure modes

---

## Tasks — Execution Modes
*(Append after the 14 numbered tasks and before the Acceptance Criteria section)*

### Task 15. Create `ExecutionGateway` interface
- **File:** `app/engines/execution/gateway.rb`
- **Interface:** `execute(input) -> ExecutionOutput`
- **Responsibilities:**
  - Owned by ExecutionEngine; delegates to the active mode adapter.
  - Resolves adapter from container based on configured execution mode.
  - Exposes adapter needed for testing/circuit breaking.
- **Implementations:**
  - `BacktestAdapter` — consumes historical tick/candle replay; produces virtual orders/positions.
  - `PaperAdapter` — consumes live market data, runs virtual broker + matching engine; never hits real `/orders`.
  - `LiveAdapter` — delegates to DhanHQ broker gateway.
- **Deliverable:** Gateway + three adapters.
- **Acceptance Criteria:**
  - `ExecutionEngine` calls `gateway.execute(input)` in all cases.
  - Mode can be switched by config, not by changing engine code.
  - Tests swap adapters without touching engine logic.
- **Commit:** `feat: add execution gateway with live, paper, and backtest adapters`

### Task 15.1: BacktestAdapter details
- Use `ReplayClock` and historical data repositories from M0.3/M0.4.
- Queue ticks through the same EventBus channels as live/paper.
- Produce `ExecutionOutput` with fill prices derived from historical data.
- No WebSocket/REST broker calls.

### Task 15.2: PaperAdapter details
- Use `LiveClock` and live repositories (same as live mode).
- Virtual broker maintains local orderbook, queue, and fill simulation.
- Matching engine models spread, partial fills, queue position, rejections, and price improvement.
- Portfolio/pnl/positions track cash, margin, unrealized and realized PnL.
- Include realistic costs: brokerage, STT, GST, SEBI charges, stamp duty.
- No DhanHQ REST `/orders` or WebSocket order updates.

### Task 15.3: LiveAdapter details
- Thin wrapper around broker gateway from M0.4.
- Maps `ExecutionOutput` shapes to broker responses.
- Preserves all retry, partial fill, reconciliation, and journaling behavior already defined in Tasks 2–14.
- WebSocket order updates remain source of truth.

---



## Notes
- Execution Mode is selected at boot from AppConfig / ENV (`execution.mode` = `live|paper|backtest|replay`).
- Everything before the ExecutionGateway is identical across modes.
- The only code path that changes between live/paper/backtest is the adapter inside M6.2.
- Paper mode is not a best-effort simulation; it uses the same risk, scoring, and sizing as live.
- Replay mode is a first-class mode separate from backtest because it replays live-speed streams (1x/2x/5x/10x/100x/1000x) through the same intake path used by live and paper.