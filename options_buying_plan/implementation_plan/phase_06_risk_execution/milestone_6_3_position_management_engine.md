# Milestone 6.3: Position Management Engine

**Phase:** 6 — Risk & Execution  
**Goal:** Live monitoring and adaptive trade management.  
**Estimated Tasks:** 15

---

## Tasks

### 1. Implement PositionManagementEngine
- [ ] Create `app/engines/position_management_engine.rb`
- [ ] Interface: `monitor(input) -> ManagementActions`
- [ ] Input: `PositionManagementInput` with:
  - `positions` (array of open positions)
  - All engine outputs (regime, structure, momentum, option_intel, liquidity)
  - `account_state`, `current_time`
- [ ] Output: `ManagementActions` with:
  - `stop_loss_updates` (new SL prices)
  - `target_updates` (new target prices)
  - `partial_exits` (quantity, price, reason)
  - `full_exits` (position_id, reason, urgency)
  - `alerts` (for notification service)

### 2. Add PnLTracker
- [ ] Create `app/engines/position_management/pnl_tracker.rb`
- [ ] Real-time unrealized P&L per position:
  - `unrealized = (current_price - entry_price) * qty * lot_size` (long)
  - Update on every tick (WebSocket LTP)
- [ ] Realized P&L on partial exits
- [ ] Track: `max_favorable` (MFE), `max_adverse` (MAE) since entry
- [ ] Publish `position.pnl_update` event every 5s

### 3. Implement StructureMonitor
- [ ] Create `app/engines/position_management/structure_monitor.rb`
- [ ] Watch for structure changes affecting position:
  - BOS against position = reduce/close
  - CHOCH = close immediately
  - Key level break (PDH/PDL, VWAP, OR) = tighten stop
- [ ] Consume `market_structure.updated` events
- [ ] Per-position structure context (saved at entry)

### 4. Create IVMonitor
- [ ] Create `app/engines/position_management/iv_monitor.rb`
- [ ] Track IV change since entry per position
- [ ] IV rise > 10% = favorable for long options (vega gain)
- [ ] IV fall > 10% = unfavorable (vega loss), consider exit
- [ ] IV crush detection (earnings/events): exit before event
- [ ] Consume `option_chain.updated` events

### 5. Add OIMonitor
- [ ] Create `app/engines/position_management/oi_monitor.rb`
- [ ] Track OI change at position strike since entry
- [ ] OI rising in our direction = confirmation
- [ ] OI falling in our direction = unwinding (warning)
- [ ] OI rising against us = trapped traders (potential reversal fuel)
- [ ] Consume `option_chain.updated` events

### 6. Implement GammaMonitor
- [ ] Create `app/engines/position_management/gamma_monitor.rb`
- [ ] Track gamma at position strike
- [ ] Gamma acceleration > threshold = delta changing fast
- [ ] High gamma near expiry = rapid P&L swings
- [ ] Action: tighten stops, reduce size, or exit
- [ ] Consume `option_chain.updated` events

### 7. Add VolumeMonitor
- [ ] Create `app/engines/position_management/volume_monitor.rb`
- [ ] Volume at position strike vs entry volume
- [ ] Volume drying up = loss of interest, consider exit
- [ ] Volume spike against position = potential reversal
- [ ] Volume confirming move = hold/add
- [ ] Consume `market_ticks` and `option_chain` events

### 8. Implement StopLossManager
- [ ] Create `app/engines/position_management/stop_loss_manager.rb`
- [ ] Initial SL: set at entry (from strategy)
- [ ] Breakeven: move to entry + 1 tick after 1R profit
- [ ] Trailing: delegate to TrailingStopManager
- [ ] Structure-based: SL at last swing low/high
- [ ] Time-based: widen SL in first 15 min (noise), tighten after
- [ ] Never widen SL (only tighten)

### 9. Create TrailingStopManager
- [ ] Create `app/engines/position_management/trailing_stop_manager.rb`
- [ ] ATR trailing: `SL = highest_high - ATR * multiplier` (long)
- [ ] Multiplier: 1.5 (default), 2.0 (volatile), 1.0 (strong trend)
- [ ] Chandelier exit: `SL = highest_high - ATR * 3`
- [ ] Supertrend trailing: use Supertrend line as SL
- [ ] Step trailing: only move in increments (e.g., 5 ticks)
- [ ] Activate after: 0.5R or 1R profit (configurable)

### 10. Add PartialExitManager
- [ ] Create `app/engines/position_management/partial_exit_manager.rb`
- [ ] Scale out at predefined targets:
  - Target 1 (1R): 30% qty
  - Target 2 (2R): 30% qty
  - Target 3 (3R): 20% qty
  - Runner (trail): 20% qty
- [ ] Configurable per strategy
- [ ] Execute via ExecutionEngine (limit orders at targets)
- [ ] Update position qty and avg entry after partial

### 11. Implement TimeDecayMonitor
- [ ] Create `app/engines/position_management/time_decay_monitor.rb`
- [ ] Theta burn rate: current theta * hours_held
- [ ] Compare to: max favorable excursion (MFE)
- [ ] If theta > 50% of MFE and no momentum = exit
- [ ] Expiry day: forced exit 30 min before close (configurable)
- [ ] 0DTE: accelerated time decay, tighter management

### 12. Create EmergencyExitManager
- [ ] Create `app/engines/position_management/emergency_exit_manager.rb`
- [ ] Triggers:
  - Catastrophic move: price > 3 ATR against in 1 min
  - Circuit breaker: daily loss limit hit
  - System failure: data feed down > 30s
  - Risk breach: margin call, position limit exceeded
- [ ] Action: market order to close (or aggressive limit)
- [ ] Log: emergency_exit event with full context
- [ ] Alert: immediate notification (Telegram, PagerDuty)

### 13. Add PositionReconciliationJob
- [ ] Create `app/jobs/position_reconciliation_job.rb`
- [ ] Schedule: every 30 seconds during market hours
- [ ] Compare: local positions vs DhanHQ positions API
- [ ] Resolve discrepancies:
  - Missing locally → fetch from broker, create local
  - Extra locally → check broker, mark closed if gone
  - Qty mismatch → use broker qty, log discrepancy
- [ ] Alert on unresolved discrepancies > 1 min

### 14. Implement PositionAlertService
- [ ] Create `app/services/position_alert_service.rb`
- [ ] Alert types:
  - `position_opened` (with setup summary)
  - `stop_loss_hit` / `target_hit`
  - `partial_exit` (with remaining qty)
  - `trailing_stop_updated`
  - `structure_warning` (BOS/CHOCH against)
  - `iv_warning` (IV crush, vega loss)
  - `emergency_exit` (with reason)
  - `reconciliation_mismatch`
- [ ] Channels: Telegram (primary), Email (critical), WebSocket (dashboard)
- [ ] Throttle: max 1 alert/min per position per type

### 15. Write Tests for Each Management Action
- [ ] Create `spec/engines/position_management_engine_spec.rb`
- [ ] Test scenarios:
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
- [ ] Engine monitors all positions in < 100ms per cycle
- [ ] P&L updates real-time with < 1s latency
- [ ] Stop loss only tightens, never widens
- [ ] Trailing stop activates after configurable profit
- [ ] Partial exits execute at target prices
- [ ] Emergency exit closes position in < 2s
- [ ] Reconciliation catches 100% of test discrepancies
- [ ] Alerts delivered within 5s of trigger
- [ ] All management actions logged for audit

---

## Notes
- Position management runs on every 5m candle + tick events for SL
- WebSocket tick data drives real-time P&L and SL checks
- Engine is stateless; position state in DB, context from engines
- Multiple managers can propose actions; engine resolves conflicts
- Priority: Emergency > Structure > Trailing > Time Decay > Targets
- Paper trading validates management logic before live
- Consider position-level max hold time (e.g., 2 hours for scalps)