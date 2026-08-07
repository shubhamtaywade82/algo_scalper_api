# Milestone 6.2: Execution Engine

**Phase:** 6 — Risk & Execution  
**Goal:** Reliable order placement with full state tracking.  
**Estimated Tasks:** 14

---

## Tasks

### 1. Implement ExecutionEngine
- [x] Implemented via `Orders::Gateway` & `Orders::Placer`
- [x] Resolves gateway implementation (Live or Paper) based on configuration
- [x] Tracks order state, latencies, average fill price, and status

### 2. Add LimitOrderPlacer
- [x] Implemented via `Orders::LimitChaser`
- [x] Resolves limit prices, manages limit chaser logic (asking ask + 1 tick or bid - 1 tick)
- [x] Falls back to market/cancel after timeout

### 3. Implement SLOrderPlacer
- [x] Implemented via `Orders::Placer` with trigger and stop loss fields

### 4. Add SuperOrderPlacer
- [x] Implemented via `Orders::BracketPlacer` to submit target + stop loss brackets simultaneously
- [x] Manages fallback to separate target/stop orders if brackets are rejected

### 5. Create OrderSlicer
- [x] Created `app/services/orders/slicer.rb`
- [x] Splits large orders based on exchange freeze limits (configurable per index)
- [x] Configurable limits and delay (e.g. NIFTY: 1800, delay: 500ms)
- [x] Integrates directly inside `Orders::Placer` placement methods (e.g. `buy_market!`, `buy_limit!`, etc.)
- [x] Appends numbered suffix to correlation IDs (e.g. `#{client_order_id}_1`, `#{client_order_id}_2`)

### 6. Implement RetryLogic
- [x] Implemented inside `Orders::Placer` with fallback to IOC limit on rate limit or rejection
- [x] Handles transient exceptions, unauthorized states, and automatic session token renewals

### 7. Add PartialFillHandler
- [x] Implemented in `Orders::GatewayPaper` and live WebSocket handlers
- [x] Synchronizes status based on partial updates

### 8. Implement SlippageMonitor
- [x] Tracks expected vs actual fill prices and slippage rates in logs and journal events

### 9. Create OrderStateTracker
- [x] Implemented via `Live::OrderUpdateHandler` and `PositionTracker` lifecycle events
- [x] Reconciles positions and synchronizes state machine from WS feed updates

### 10. Add ExecutionValidator
- [x] Implemented via pre-trade checks and entry guards pipeline (`EntryGuardPipeline`)

### 11. Implement ExecutionMetrics
- [x] Logs fill rates, latencies, and slippage calculations to execution reports

### 12. Create ExecutionJournal
- [x] Records order details, signal events, and transition logs in database

### 13. Add OrderCancellationService
- [x] Implemented via `Orders::Canceler` and gateway order cancel endpoints

### 14. Write Integration Tests with Mocked Broker
- [x] Verified via `placer_spec.rb` and `gateway_live_spec.rb` testing both standard and sliced placements

---

## Acceptance Criteria
- [x] ExecutionEngine places order efficiently
- [x] Retry logic handles failures and token refreshes
- [x] Partial fills correctly tracked and aggregated
- [x] Slippage monitored on fill completions
- [x] Order state synced via WebSocket updates
- [x] Emergency cancel API verified
- [x] Execution logging covers state details
- [x] Coverage suite covers multiple scenariosailure modes

---

## Tasks — Execution Modes
*(Append after the 14 numbered tasks and before the Acceptance Criteria section)*

### Task 15. Create `ExecutionGateway` interface
- [x] Implemented via `Orders::Gateway`
- [x] Routes calls to the active execution mode gateway adapter:
  - `Orders::GatewayLive` (LiveAdapter)
  - `Orders::GatewayPaper` (PaperAdapter)

### Task 15.1: BacktestAdapter details
- [x] Virtual order simulator matches pricing based on backtest ticks

### Task 15.2: PaperAdapter details
- [x] `Orders::GatewayPaper` simulates matching engine, cash, margin, and realistic transaction costs (STT, GST, SEBI)

### Task 15.3: LiveAdapter details
- [x] `Orders::GatewayLive` executes REST and WebSocket orders with DhanHQ broker API

---



## Notes
- Execution Mode is selected at boot from AppConfig / ENV (`execution.mode` = `live|paper|backtest|replay`).
- Everything before the ExecutionGateway is identical across modes.
- The only code path that changes between live/paper/backtest is the adapter inside M6.2.
- Paper mode is not a best-effort simulation; it uses the same risk, scoring, and sizing as live.
- Replay mode is a first-class mode separate from backtest because it replays live-speed streams (1x/2x/5x/10x/100x/1000x) through the same intake path used by live and paper.