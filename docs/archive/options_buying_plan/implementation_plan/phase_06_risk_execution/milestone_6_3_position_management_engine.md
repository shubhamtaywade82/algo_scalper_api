# Milestone 6.3: Position Management Engine

**Phase:** 6 — Risk & Execution  
**Goal:** Live monitoring and adaptive trade management.  
**Estimated Tasks:** 15

---

## Tasks

### 1. Implement PositionManagementEngine
- [x] Create `app/engines/position_management_engine.rb`
- [x] Interface: `monitor(input) -> ManagementActions`
- [x] Input: `PositionManagementInput` with:
  - `positions` (array of open positions)
  - All engine outputs (regime, structure, momentum, option_intel, liquidity)
  - `account_state`, `current_time`
- [x] Output: `ManagementActions` with:
  - `stop_loss_updates` (new SL prices)
  - `target_updates` (new target prices)
  - `partial_exits` (quantity, price, reason)
  - `full_exits` (position_id, reason, urgency)
  - `alerts` (for notification service)

### 2. Add PnLTracker
- [x] Create `app/engines/position_management/pnl_tracker.rb`
- [x] Real-time unrealized P&L per position:
  - `unrealized = (current_price - entry_price) * qty * lot_size` (long)
  - Update on every tick (WebSocket LTP)
- [x] Realized P&L on partial exits
- [x] Track: `max_favorable` (MFE), `max_adverse` (MAE) since entry
- [x] Publish `position.pnl_update` event every 5s

### 3. Implement StructureMonitor
- [x] Create `app/engines/position_management/structure_monitor.rb`
- [x] Watch for structure changes affecting position:
  - BOS against position = reduce/close
  - CHOCH = close immediately
  - Key level break (PDH/PDL, VWAP, OR) = tighten stop
- [x] Consume `market_structure.updated` events
- [x] Per-position structure context (saved at entry)

### 4. Create IVMonitor
- [x] Create `app/engines/position_management/iv_monitor.rb`
- [x] Track IV change since entry per position
- [x] IV rise > 10% = favorable for long options (vega gain)
- [x] IV fall > 10% = unfavorable (vega loss), consider exit
- [x] IV crush detection (earnings/events): exit before event
- [x] Consume `option_chain.updated` events

### 5. Add OIMonitor
- [x] Create `app/engines/position_management/oi_monitor.rb`
- [x] Track OI change at position strike since entry
- [x] OI rising in our direction = confirmation
- [x] OI falling in our direction = unwinding (warning)
- [x] OI rising against us = trapped traders (potential reversal fuel)
- [x] Consume `option_chain.updated` events

### 6. Implement GammaMonitor
- [x] Create `app/engines/position_management/gamma_monitor.rb`
- [x] Track gamma at position strike
- [x] Gamma acceleration > threshold = delta changing fast
- [x] High gamma near expiry = rapid P&L swings
- [x] Action: tighten stops, reduce size, or exit
- [x] Consume `option_chain.updated` events

### 7. Add VolumeMonitor
- [x] Create `app/engines/position_management/volume_monitor.rb`
- [x] Volume at position strike vs entry volume
- [x] Volume drying up = loss of interest, consider exit
- [x] Volume spike against position = potential reversal
- [x] Volume confirming move = hold/add
- [x] Consume `market_ticks` and `option_chain` events

### 8. Implement StopLossManager
- [x] Create `app/engines/position_management/stop_loss_manager.rb`
- [x] Initial SL: set at entry (from strategy)
- [x] Breakeven: move to entry + 1 tick after 1R profit
- [x] Trailing: delegate to TrailingStopManager
- [x] Structure-based: SL at last swing low/high
- [x] Time-based: widen SL in first 15 min (noise), tighten after
- [x] Never widen SL (only tighten)

### 9. Create TrailingStopManager
- [x] Create `app/engines/position_management/trailing_stop_manager.rb`
- [x] ATR trailing: `SL = highest_high - ATR * multiplier` (long)
- [x] Multiplier: 1.5 (default), 2.0 (volatile), 1.0 (strong trend)
- [x] Chandelier exit: `SL = highest_high - ATR * 3`
- [x] Supertrend trailing: use Supertrend line as SL
- [x] Step trailing: only move in increments (e.g., 5 ticks)
- [x] Activate after: 0.5R or 1R profit (configurable)

### 10. Add PartialExitManager
- [x] Create `app/engines/position_management/partial_exit_manager.rb`
- [x] Scale out at predefined targets:
  - Target 1 (1R): 30% qty
  - Target 2 (2R): 30% qty
  - Target 3 (3R): 20% qty
  - Runner (trail): 20% qty
- [x] Configurable per strategy
- [x] Execute via ExecutionEngine (limit orders at targets)
- [x] Update position qty and avg entry after partial

### 11. Implement TimeDecayMonitor
- [x] Create `app/engines/position_management/time_decay_monitor.rb`
- [x] Theta burn rate: current theta * hours_held
- [x] Compare to: max favorable excursion (MFE)
- [x] If theta > 50% of MFE and no momentum = exit
- [x] Expiry day: forced exit 30 min before close (configurable)
- [x] 0DTE: accelerated time decay, tighter management

### 12. Create EmergencyExitManager
- [x] Create `app/engines/position_management/emergency_exit_manager.rb`
- [x] Triggers:
  - Catastrophic move: price > 3 ATR against in 1 min
  - Circuit breaker: daily loss limit hit
  - System failure: data feed down > 30s
  - Risk breach: margin call, position limit exceeded
- [x] Action: market order to close (or aggressive limit)
- [x] Log: emergency_exit event with full context
- [x] Alert: immediate notification (Telegram, PagerDuty)

### 13. Add PositionReconciliationJob
- [x] Create `app/jobs/position_reconciliation_job.rb`
- [x] Schedule: every 30 seconds during market hours
- [x] Compare: local positions vs DhanHQ positions API
- [x] Resolve discrepancies:
  - Missing locally → fetch from broker, create local
  - Extra locally → check broker, mark closed if gone
  - Qty mismatch → use broker qty, log discrepancy
- [x] Alert on unresolved discrepancies > 1 min

### 14. Implement PositionAlertService
- [x] Create `app/services/position_alert_service.rb`
- [x] Alert types:
  - `position_opened` (with setup summary)
  - `stop_loss_hit` / `target_hit`
  - `partial_exit` (with remaining qty)
  - `trailing_stop_updated`
  - `structure_warning` (BOS/CHOCH against)
  - `iv_warning` (IV crush, vega loss)
  - `emergency_exit` (with reason)
  - `reconciliation_mismatch`
- [x] Channels: Telegram (primary), Email (critical), WebSocket (dashboard)
- [x] Throttle: max 1 alert/min per position per type

### 15. Write Tests for Each Management Action
- [x] Create `spec/engines/position_management_engine_spec.rb`
- [x] Test scenarios:
  - Trailing stop activates and moves correctly
  - Partial exits at targets reduce qty correctly
  - Structure break triggers full exit
  - IV crush warning triggers before earnings
  - Emergency exit executes market order
  - Reconciliation catches broker discrepancies
  - Time decay forces exit on expiry day
  - Alert throttling prevents spam

---

## Acceptance Criteria
- [x] Engine monitors all positions in < 100ms per cycle
- [x] P&L updates real-time with < 1s latency
- [x] Stop loss only tightens, never widens
- [x] Trailing stop activates after configurable profit
- [x] Partial exits execute at target prices
- [x] Emergency exit closes position in < 2s
- [x] Reconciliation catches 100% of test discrepancies
- [x] Alerts delivered within 5s of trigger
- [x] All management actions logged for audit

---

## Notes
- Position management runs on every 5m candle + tick events for SL
- WebSocket tick data drives real-time P&L and SL checks
- Engine is stateless; position state in DB, context from engines
- Multiple managers can propose actions; engine resolves conflicts
- Priority: Emergency > Structure > Trailing > Time Decay > Targets
- Paper trading validates management logic before live
- Consider position-level max hold time (e.g., 2 hours for scalps)