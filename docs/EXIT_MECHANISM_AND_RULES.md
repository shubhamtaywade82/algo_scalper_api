# Exit Mechanism and Rules - Complete Reference

## Overview

The exit system uses a **priority-based enforcement mechanism** where exit rules are evaluated in a specific order. The first rule that triggers an exit wins, and evaluation stops immediately. This ensures critical exits (like stop loss) take precedence over less urgent ones.

## Exit Flow Architecture

```
RiskManagerService (monitor_loop)
  ↓
  Every 5 seconds:
  1. Update PnL in Redis
  2. Enforce exit rules (priority order):
     a. Early Trend Failure
     b. Global Time Overrides (IV Collapse, Stall Detection)
     c. Hard Limits (Rupee-based SL/TP, Post-Profit Zone)
     d. Post Profit Zone
     e. Trailing Stops
     f. Time-Based Exit
  ↓
  If any rule triggers exit:
    → dispatch_exit(exit_engine, tracker, reason)
    → ExitEngine.execute_exit(tracker, reason)
    → OrderRouter.exit_market(tracker)
    → PositionTracker.mark_exited!
```

## Exit Rules (Priority Order)

### 1. Early Trend Failure (ETF)

**Priority**: Highest (checked first)

**When Applied**: Before trailing stop activation (when profit < activation threshold)

**Configuration**:
```yaml
risk:
  etf:
    enabled: true/false
    activation_profit_pct: 3.0  # Only applies before 3% profit
```

**Exit Condition**:
- Profit < activation threshold (default: 3%)
- Early trend failure detected (trend reversal before trailing activates)

**Exit Reason**: `"EARLY_TREND_FAILURE (pnl: X.XX%)"`

**Exit Path**: `'early_trend_failure'`

---

### 2. Global Time Overrides

**Priority**: High (checked after ETF)

#### 2a. IV Collapse Detection

**Status**: Currently not fully implemented (placeholder)

**When Applied**: If enabled in config

**Exit Condition**: Sudden IV collapse detected (requires IV data from option chain)

---

#### 2b. Price Stall Detection

**Configuration**:
```yaml
risk:
  stall_detection:
    enabled: true/false
    stall_candles: 3  # Number of candles with no progress
    min_profit_rupees: 2000  # Only check if profit >= ₹2000
```

**Exit Condition**:
- Profit >= min_profit_rupees (default: ₹2000)
- Price has stalled (no new HH/LL for N candles)
- Tolerance: 1% (current LTP <= previous high * 1.01)

**Exit Reason**: `"PRICE_STALL (N candles no progress, profit: ₹X.XX)"`

**Exit Path**: `'stall_detection'`

---

### 3. Hard Limits (Rupee-Based)

**Priority**: Very High (checked after global overrides)

**Configuration**:
```yaml
risk:
  hard_rupee_sl:
    enabled: true/false
    max_loss_rupees: 1000  # Base limit (multiplied by time regime)

  hard_rupee_tp:
    enabled: true/false
    target_profit_rupees: 2000  # Base target (multiplied by time regime)

  post_profit_zone:
    enabled: true/false
    secured_sl_rupees: 800  # SL after entering profit zone
```

#### 3a. Secured Profit Zone SL (Highest Priority)

**When Applied**: If position is in `secured_profit_zone` state

**Exit Condition**:
- Position is in secured profit zone
- Current net PnL < (secured_sl_rupees + exit_fee)
- Net PnL after exit = current_net_pnl - exit_fee

**Exit Reason**: `"SECURED_PROFIT_SL (Current net: ₹X.XX, Net after exit: ₹Y.YY, secured SL: ₹Z.ZZ)"`

**Exit Path**: `'secured_profit_sl'`

---

#### 3b. Hard Rupee Stop Loss

**Exit Condition**:
- Current net PnL <= (-max_loss_rupees * sl_multiplier + exit_fee)
- Time regime multiplier applied (varies by market session)
- Exit fee (₹20) accounted for

**Calculation**:
```
net_threshold = -max_loss_rupees * sl_multiplier + exit_fee
if net_pnl_rupees <= net_threshold:
  EXIT
```

**Exit Reason**: `"HARD_RUPEE_SL (Current net: ₹X.XX, Net after exit: ₹Y.YY, limit: -₹Z.ZZ)"`

**Exit Path**: `'hard_rupee_stop_loss'`

---

#### 3c. Hard Rupee Take Profit

**Behavior**:
- If runners allowed: Transitions to secured profit zone (does NOT exit immediately)
- If runners NOT allowed: Exits immediately

**Exit Condition** (when runners NOT allowed):
- Current net PnL >= (target_profit_rupees * tp_multiplier + exit_fee)
- Time regime multiplier applied
- Max TP limit per session respected

**Exit Reason**: `"SESSION_TP_HIT (Current net: ₹X.XX, Net after exit: ₹Y.YY, target: ₹Z.ZZ, regime: REGIME)"`

**Exit Path**: `'session_take_profit'`

**Transition** (when runners allowed):
- Moves SL to green (secured profit zone)
- Post-Profit Zone Rule handles subsequent exits

---

### 4. Percentage-Based Stops (Fallback)

**Priority**: Medium (checked after hard rupee limits)

#### 4a. Dynamic Reverse SL (Below Entry)

**When Applied**: When PnL is negative (below entry)

**Configuration**:
```yaml
risk:
  sl_pct: 0.30  # 30% static SL (fallback)
```

**Exit Condition**:
- PnL < 0 (below entry)
- Dynamic loss % calculated based on:
  - Time below entry (seconds)
  - ATR ratio
  - Index-specific schedule
- If dynamic loss % not available, falls back to static `sl_pct`

**Calculation**:
```ruby
dyn_loss_pct = DrawdownSchedule.reverse_dynamic_sl_pct(
  pnl_pct_value,
  seconds_below_entry: seconds_below,
  atr_ratio: atr_ratio
)
if pnl_pct_value <= -dyn_loss_pct:
  EXIT
```

**Exit Reason**: `"DYNAMIC_LOSS_HIT X.XX% (allowed: Y.YY%)"`

**Exit Path**: `'stop_loss_adaptive_downward'`

---

#### 4b. Static Stop Loss (Fallback)

**Exit Condition**:
- Dynamic reverse SL not applicable or disabled
- PnL <= -sl_pct (default: -30%)

**Exit Reason**: `"SL HIT X.XX%"`

**Exit Path**: `'stop_loss_static_downward'`

---

#### 4c. Static Take Profit

**Exit Condition**:
- PnL >= tp_pct (default: +60%)

**Exit Reason**: `"TP HIT X.XX%"`

**Exit Path**: `'take_profit_static'`

---

### 5. Post Profit Zone

**Priority**: Medium-High (checked after hard limits)

**Configuration**:
```yaml
risk:
  post_profit_zone:
    enabled: true/false
    secured_sl_rupees: 800
    # Additional config via PostProfitZoneRule
```

**When Applied**: When profit > 0 and position is in secured profit zone

**Exit Condition**: Evaluated via `PostProfitZoneRule` which checks:
- Trend/momentum conditions
- Drawdown from peak
- Time in profit zone

**Exit Reason**: `"POST_PROFIT_ZONE_EXIT"` (or rule-specific reason)

**Exit Path**: `'post_profit_zone'`

---

### 6. Trailing Stops

**Priority**: Medium (checked after hard limits and post-profit zone)

**Configuration**:
```yaml
risk:
  exit_drop_pct: 5.0  # Trailing stop threshold (default: disabled if >= 100)
  breakeven_after_gain: 2.0  # Move SL to breakeven after X% gain
  drawdown:
    activation_profit_pct: 3.0  # Activate trailing after 3% profit
```

**When Applied**:
- Only if trailing allowed in current time regime
- Only after activation profit threshold reached

**Behavior**:

#### 6a. Upward Trailing (When Profitable)

**Activation**: After reaching activation_profit_pct (default: 3%)

**Logic**: Uses adaptive drawdown schedule based on:
- Peak profit percentage
- Index-specific schedule
- Allowed drawdown increases with profit

**Exit Condition**:
```
peak_profit_pct = (hwm / (entry_price * quantity)) * 100
allowed_dd = DrawdownSchedule.allowed_upward_drawdown_pct(peak_profit_pct, index_key)
current_dd_pct = ((hwm - current_pnl) / hwm) * 100

if current_dd_pct >= allowed_dd:
  EXIT
```

**Exit Reason**: `"TRAILING_STOP (peak: X.XX%, drawdown: Y.YY%, allowed: Z.ZZ%)"`

**Exit Path**: `'trailing_stop_upward'`

---

#### 6b. Downward Trailing (When Below Entry)

**Activation**: When PnL < 0 (below entry)

**Logic**: Uses adaptive drawdown schedule for reverse positions

**Exit Condition**:
```
allowed_dd = DrawdownSchedule.allowed_downward_drawdown_pct(...)
if drawdown >= allowed_dd:
  EXIT
```

**Exit Reason**: `"TRAILING_STOP (reverse, drawdown: X.XX%)"`

**Exit Path**: `'trailing_stop_downward'`

---

#### 6c. Breakeven Protection

**When Applied**: After reaching breakeven_after_gain (default: 2%)

**Behavior**: Moves stop loss to breakeven (entry price)

**Note**: This is a protection mechanism, not an exit trigger itself

---

### 7. Time-Based Exit

**Priority**: Low (checked last)

**Configuration**:
```yaml
risk:
  time_exit_hhmm: "15:20"  # Exit time (default: 3:20 PM IST)
  market_close_hhmm: "15:30"  # Market close (default: 3:30 PM IST)
  min_profit_rupees: 0  # Minimum profit to exit (default: 0)
```

**Exit Condition**:
- Current time >= time_exit_hhmm
- Current time < market_close_hhmm
- If min_profit_rupees > 0: PnL >= min_profit_rupees (otherwise exits regardless of PnL)

**Exit Reason**: `"time-based exit (HH:MM)"`

**Exit Path**: `'time_based'`

---

## Exit Execution Flow

### 1. Rule Evaluation

```ruby
# RiskManagerService.monitor_loop (every 5 seconds)
enforce_early_trend_failure(exit_engine: exit_engine)
enforce_global_time_overrides(exit_engine: exit_engine)
enforce_hard_limits(exit_engine: exit_engine)
enforce_post_profit_zone(exit_engine: exit_engine)
enforce_trailing_stops(exit_engine: exit_engine)
enforce_time_based_exit(exit_engine: exit_engine)
```

### 2. Exit Dispatch

```ruby
# If rule triggers exit:
dispatch_exit(exit_engine, tracker, reason)
  ↓
  if exit_engine.respond_to?(:execute_exit):
    exit_engine.execute_exit(tracker, reason)  # External ExitEngine
  else:
    execute_exit(tracker, reason)  # Internal (backwards compatibility)
```

### 3. Exit Execution

```ruby
# ExitEngine.execute_exit(tracker, reason)
1. Validate tracker (active, not already exited)
2. Get current LTP
3. Call OrderRouter.exit_market(tracker)
4. If successful:
   a. Mark tracker as exited (mark_exited!)
   b. Update exit_price and exit_reason
   c. Calculate final PnL (includes broker fees)
   d. Update exit reason with final PnL %
   e. Send Telegram notification
   f. Return success
```

### 4. Order Placement

```ruby
# OrderRouter.exit_market(tracker)
1. Determine order type (MARKET order)
2. Call appropriate gateway:
   - Paper: GatewayPaper.exit_market()
   - Live: GatewayDhanHQ.exit_market()
3. Return success/failure
```

---

## Key Concepts

### Net PnL vs Gross PnL

**Gross PnL**: Profit/loss before broker fees

**Net PnL**: Profit/loss after broker fees
- Entry fee: ₹20 per order
- Exit fee: ₹20 per order
- Total trade fee: ₹40 per round trip

**For Exit Rules**:
- Rules check **net PnL** (after entry fee)
- Exit threshold accounts for **exit fee** (additional ₹20)
- Final net PnL = current net PnL - exit fee

**Example**:
```
Entry: ₹100, Quantity: 50
Current LTP: ₹105
Gross PnL: (105 - 100) * 50 = ₹250
Net PnL (current): ₹250 - ₹20 (entry fee) = ₹230
Exit threshold: ₹2000 + ₹20 (exit fee) = ₹2020
Final net PnL (after exit): ₹230 - ₹20 = ₹210
```

### Time Regime Multipliers

Exit thresholds are adjusted based on market session:

```ruby
# Example multipliers (varies by regime)
sl_multiplier = 1.0 (normal) or 0.5 (conservative session)
tp_multiplier = 1.0 (normal) or 0.8 (late session)
max_tp_rupees = varies by regime
```

### Secured Profit Zone

**Transition**: When hard rupee TP hit and runners allowed:
1. Position enters `secured_profit_zone` state
2. SL moved to green (secured_sl_rupees, default: ₹800)
3. Post-Profit Zone Rule takes over exit management
4. Exits based on trend/momentum, not fixed thresholds

**Exit Triggers** (Post-Profit Zone):
- Secured SL hit (net PnL < secured_sl_rupees + exit_fee)
- Trend reversal
- Momentum loss
- Time-based conditions

---

## Configuration Reference

### Complete Risk Config

```yaml
risk:
  # Percentage-based stops
  sl_pct: 0.30  # 30% stop loss
  tp_pct: 0.60  # 60% take profit

  # Rupee-based stops
  hard_rupee_sl:
    enabled: true
    max_loss_rupees: 1000

  hard_rupee_tp:
    enabled: true
    target_profit_rupees: 2000

  # Post-profit zone
  post_profit_zone:
    enabled: true
    secured_sl_rupees: 800

  # Trailing stops
  exit_drop_pct: 5.0  # Disabled if >= 100
  breakeven_after_gain: 2.0

  # Drawdown schedule
  drawdown:
    activation_profit_pct: 3.0

  # Early trend failure
  etf:
    enabled: true
    activation_profit_pct: 3.0

  # Stall detection
  stall_detection:
    enabled: true
    stall_candles: 3
    min_profit_rupees: 2000

  # Time-based exit
  time_exit_hhmm: "15:20"
  market_close_hhmm: "15:30"
  min_profit_rupees: 0
```

---

## Exit Paths Summary

| Exit Path                     | Trigger                        | Priority    |
| ----------------------------- | ------------------------------ | ----------- |
| `early_trend_failure`         | ETF before trailing activation | Highest     |
| `stall_detection`             | Price stall after ₹2k profit   | High        |
| `secured_profit_sl`           | Secured SL in profit zone      | Very High   |
| `hard_rupee_stop_loss`        | Hard rupee SL limit            | Very High   |
| `session_take_profit`         | Hard rupee TP (no runners)     | Very High   |
| `stop_loss_adaptive_downward` | Dynamic reverse SL             | Medium      |
| `stop_loss_static_downward`   | Static SL (30%)                | Medium      |
| `take_profit_static`          | Static TP (60%)                | Medium      |
| `post_profit_zone`            | Post-profit zone rule          | Medium-High |
| `trailing_stop_upward`        | Upward trailing stop           | Medium      |
| `trailing_stop_downward`      | Downward trailing stop         | Medium      |
| `time_based`                  | Time-based exit (3:20 PM)      | Low         |

---

## Important Notes

1. **First-Match-Wins**: Only the first rule that triggers exits. Remaining rules are not evaluated.

2. **Idempotent Exits**: If a position is already exited, exit attempts are ignored (not an error).

3. **Fee Accounting**: All exit thresholds account for exit fees (₹20 additional on exit).

4. **Time Regime Awareness**: Exit thresholds are multiplied by time regime factors.

5. **Market Closed**: Exit rules still run if positions exist (needed for after-hours exits).

6. **Real-Time Data**: Rules use Redis PnL cache (updated every 5 seconds) for real-time decisions.

7. **Fail-Safe**: If rule evaluation fails, error is logged and evaluation continues to next rule.

---

## Related Files

- `app/services/live/risk_manager_service.rb` - Main enforcement loop
- `app/services/live/exit_engine.rb` - Exit execution
- `app/services/live/trailing_engine.rb` - Trailing stop logic
- `app/services/risk/rules/` - Individual rule implementations
- `app/services/positions/drawdown_schedule.rb` - Adaptive drawdown calculations
