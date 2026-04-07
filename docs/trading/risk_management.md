# Risk Management & Exit Rules

The system employs a multi-layered risk management strategy, prioritizing capital preservation through a prioritized exit hierarchy. Two concurrent paths evaluate exit conditions: a per-tick high-frequency path and a 5-second enforcement loop.

> **Full reference for guard pipeline, exact exit priority order, and config keys:** `docs/trading/entry_and_exit_rules.md`

---

## The Exit Hierarchy

### Path A: Per-Tick (UnifiedExitChecker)

`Live::UnifiedExitChecker.check_exit_conditions(tracker)` is called for every LTP event via `EventBus.subscribe(:ltp)`. Priority order (first match wins):

| Priority | Exit Rule | Config Key |
|----------|-----------|------------|
| 1 | **Early Trend Failure (ETF)** | `exit.early_exit.enabled`, `exit.early_exit.profit_threshold` |
| 2 | **Hard Stop-Loss (SL)** | `exit.stop_loss.value` (DECIMAL), `exit.stop_loss.type` ('static'/'adaptive') |
| 3 | **Take-Profit (TP)** | `exit.take_profit` (DECIMAL) |
| 4 | **Trailing Stop** | `exit.trailing.*` |
| 5 | **Time-Based Exit** | `exit.time_based.exit_time` |

### Path B: 5-Second Enforcement Loop (RiskManagerService)

`RiskManagerService#run_enforcement_cycle` per tracker (first trigger exits and skips rest):

| Order | Rule | Config |
|-------|------|--------|
| 1 | Premium R-stop | `tracker.meta['premium_stop_price']` |
| 2 | Dynamic trailing stops | `Live::TrailingEngine` config |
| 3 | Profit floor | `risk.profit_floor.*` |
| 4 | Structure invalidation | `risk.exits.structure_invalidation.enabled` |
| 5 | Premium momentum failure | `risk.exits.premium_momentum_failure.enabled` |
| 6 | R:R profit booking | `risk.rr_profit_booking.*` |
| 7 | Percentage PnL exit | `risk.percentage_pnl_exit.*` |
| 8 | Time stop | `risk.exits.time_stop.enabled` |
| 9 | Time-based exit | `risk.time_exit_hhmm` |

---

## Exit Rules in Detail

### 1. Early Trend Failure (ETF)

**Path:** Per-tick (`UnifiedExitChecker`)

- Checks if the trend that triggered entry has reversed before the position has built meaningful profit
- **Condition**: `exit.early_exit.enabled: true` AND `pnl_pct < profit_threshold` AND `Live::EarlyTrendFailure.early_trend_failure?(position_data)` is true
- **Logic**: Evaluates ADX collapse, Supertrend flip, candle pattern reversal on primary timeframe
- **Purpose**: Exit early before full SL is hit when the setup has clearly failed
- **Config**:
  ```yaml
  exit:
    early_exit:
      enabled: true
      profit_threshold: 0.07  # Only check ETF if profit < 7%
  ```

### 2. Stop Loss (Static or Adaptive)

**Path:** Per-tick (`UnifiedExitChecker`)

**Static SL**: Exit when `pnl_pct <= -static_sl`
- Simple percentage floor below entry
- Config: `exit.stop_loss.value: 0.10` (10% loss)

**Adaptive SL** (`type: 'adaptive'`, only when position is losing):
- Uses `Positions::DrawdownSchedule.reverse_dynamic_sl_pct(pnl_pct, seconds_below_entry:, atr_ratio:)`
- Tightens the allowed loss as: loss deepens, time below entry increases, volatility (ATR) is low
- Prevents positions from "slow bleeding" below entry for long periods

### 3. Take Profit

**Path:** Per-tick (`UnifiedExitChecker`)

- Exit when `pnl_pct >= tp` (DECIMAL format)
- Config: `exit.take_profit: 0.25` (25% profit)
- Note: `risk.take_profit` or `exit.take_profit` — UnifiedExitChecker reads from AlgoConfig

### 4. Trailing Stop

**Path:** Per-tick (`UnifiedExitChecker`) and 5-second loop (`TrailingEngine`)

**Gamma-aware trailing** (NIFTY / BANKNIFTY / SENSEX):
- Uses `Orders::Analyzer` and `Orders::MfeExitEngine`
- Tracks Maximum Favorable Excursion (MFE) and recommends SL from option pricing dynamics
- Activates after configurable activation profit

**Adaptive trailing** (`exit.trailing.type: 'adaptive'`):
- `Positions::DrawdownSchedule` calculates allowed drawdown from HWM
- Allowed drawdown decreases exponentially as profit increases (protect larger profits more tightly)
- Index-specific minimum floors (NIFTY, BANKNIFTY, SENSEX have different defaults)
- Activation threshold: `exit.trailing.activation_profit` (DECIMAL)

**Fixed trailing** (`exit.trailing.type: 'fixed'`):
- Exit when profit drops by `exit.trailing.drop_threshold` from HWM

**Dynamic trailing** (5s loop via `Live::TrailingEngine`):
- Only runs when `trade_state == 'expansion'` or breakeven is set
- Supports tiered drawdown thresholds configured in `indices[].trailing_tiers`
- Direct trailing mode: `direct_trailing.distance_pct` from HWM (DECIMAL)

### 5. Profit Floor

**Path:** 5-second enforcement loop

- **Arm**: When net PnL >= `risk.profit_floor.lock_pct` (DECIMAL), floor is activated
- **Ratchet**: Floor rises with HWM (`trail_pct` below HWM)
- **Breakeven**: Set at `risk.profit_floor.breakeven_at` (prevents going negative once reached)
- **Time kill**: If floor has been armed for `time_kill_minutes` without exiting, force exit
- Config:
  ```yaml
  risk:
    profit_floor:
      enabled: true
      lock_pct: 0.05
      trail_pct: 0.02
      breakeven_at: 0.03
      time_kill_minutes: 15
  ```

### 6. Structure Invalidation

**Path:** 5-second enforcement loop

`Risk::Rules::StructureInvalidationRule` exits when the trade's structural thesis is invalidated:
- Price has breached key structure level
- Supertrend has flipped against position direction
- Config: `risk.exits.structure_invalidation.enabled: true`

### 7. Premium Momentum Failure

**Path:** 5-second enforcement loop

`Risk::Rules::PremiumMomentumFailureRule` exits when option premium momentum fails:
- Detects when premium is decaying/stalling without directional movement ("dead option" scenario)
- Prevents holding positions that have lost momentum but haven't hit SL yet
- Config: `risk.exits.premium_momentum_failure.enabled: true`

### 8. R:R Profit Booking

**Path:** 5-second enforcement loop

- Exit when current Risk:Reward ratio exceeds target
- `current_r = pnl_pct / stop_loss_pct`
- Exit when `current_r >= risk.rr_profit_booking.target_rr`
- Config:
  ```yaml
  risk:
    rr_profit_booking:
      enabled: true
      target_rr: 3.0
  ```

### 9. Percentage PnL Exit

**Path:** 5-second enforcement loop

`Risk::Rules::PercentagePnlRule` exits at a configurable target PnL percentage:
- Uses DECIMAL values directly (0.30 = 30%)
- Config:
  ```yaml
  risk:
    percentage_pnl_exit:
      enabled: true
      target_pct: 0.30
  ```

### 10. Time Stop

**Path:** 5-second enforcement loop

`Risk::Rules::TimeStopRule` exits based on maximum hold duration:
- Config: `risk.exits.time_stop.enabled: true`, `risk.exits.time_stop.max_hold_minutes`

### 11. Time-Based Exit

**Path:** Per-tick (`UnifiedExitChecker`) and 5-second loop

- Forces exit at configured time (default 15:20) to avoid end-of-day risk
- Optional minimum profit gate (`risk.min_profit_rupees`) before forcing exit

---

## Platform-Level Safety Mechanisms

### Circuit Breaker

`Risk::CircuitBreaker` is the system-wide kill switch:

- **State**: Persists in Redis/Cache — survives process restarts
- **Trip conditions**: Manual API call, or auto-trip on critical execution failures
- **On trip**:
  - `CircuitBreakerGuard` immediately blocks all new entries
  - `RiskManagerService` detects trip and calls `force_close_all!` — exits all active positions within seconds
- **Manual control**:
  - Trip: `POST /api/circuit_breaker/trip` with `{ reason: "..." }`
  - Reset: `DELETE /api/circuit_breaker/trip`
  - Status: `GET /api/circuit_breaker`
- **File**: `app/services/risk/circuit_breaker.rb`

### Edge Failure Detection

`Live::EdgeFailureDetector` detects when the strategy has "lost its edge" during a session:

- **Triggers** (any of):
  - 2 consecutive stop-losses for the same index
  - Rolling 5-trade net PnL <= -₹3,000 for the index
  - S3 session (11:30-13:45) + 2 SLs
- **Effect**: `entries_paused?` returns true → `EdgeFailureGuard` blocks entries for that index for 60 minutes
- **Config**: `risk.edge_failure_detector.*`

### Loss Streak Guard

`Guards::LossStreakGuard` blocks entries when consecutive losses reach threshold:
- **Config**: `loss_streak_guard.enabled: true`, `consecutive_losses_threshold: 2`
- Resets when a trade wins

### Daily Limits

`Guards::DailyLimitsGuard` enforces hard daily limits:
- Max daily loss per index
- Max daily trades per index
- Max daily profit target (stop trading after hitting target)

### Drawdown Guard

`Guards::DrawdownGuard` checks portfolio-level drawdown:
- Prevents entries when portfolio is too deep in drawdown

---

## Configuration Reference

All values use **DECIMAL format** (0.12 = 12%, not 12.0):

```yaml
risk:
  stop_loss: 0.10               # 10% stop loss
  take_profit: 0.25             # 25% take profit
  time_exit_hhmm: "15:20"
  market_close_hhmm: "15:30"
  min_profit_rupees: 0          # minimum profit before time exit

  profit_floor:
    enabled: true
    lock_pct: 0.05              # arm floor at 5% profit
    trail_pct: 0.02             # floor trails 2% below HWM
    breakeven_at: 0.03          # set breakeven at 3%
    time_kill_minutes: 15

  rr_profit_booking:
    enabled: true
    target_rr: 3.0

  percentage_pnl_exit:
    enabled: true
    target_pct: 0.30            # exit at 30% profit

  exits:
    structure_invalidation:
      enabled: true
    premium_momentum_failure:
      enabled: true
    time_stop:
      enabled: true
      max_hold_minutes: 60

exit:
  early_exit:
    enabled: true
    profit_threshold: 0.07
  stop_loss:
    value: 0.10
    type: static                 # 'static' or 'adaptive'
  take_profit: 0.25
  trailing:
    enabled: true
    type: adaptive               # 'adaptive', 'fixed', 'gamma'
    activation_profit: 0.03
    drop_threshold: 0.05
  time_based:
    enabled: true
    exit_time: "15:20"
```

---

## Exit Execution

All exits — regardless of which rule triggers them — go through `Live::ExitEngine`:

- Sets `exit_requested_at`, `exit_sent_at`, `exit_coid` (durable exit intent fields)
- Places closing order via `Orders.config.gateway` (paper or live)
- On fill: calls `PositionTracker.mark_exited!`
- `persist_final_pnl_from_cache` recalculates `last_pnl_pct` from `final_pnl / (entry_price * quantity)` — NOT from stale Redis snapshot
- Unsubscribes instrument from `MarketFeedHub`

This ensures a single audit trail for all exit decisions regardless of trigger source.
