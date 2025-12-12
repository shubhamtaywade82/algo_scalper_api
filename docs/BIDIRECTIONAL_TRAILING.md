# Bidirectional Trailing Stops - Integration with Adaptive Exits

## Overview

The bidirectional trailing system **works WITH** the adaptive exit system, not as a separate implementation. They complement each other:

- **Trailing Stops**: Handles upward protection (profit protection) with adaptive drawdown schedule
- **Adaptive Reverse SL**: Handles downward protection (loss limitation) in `enforce_hard_limits`
- **Early Trend Failure**: Handles early exit detection before trailing activates

## How They Work Together

### Execution Order (Every 5 seconds)

```
RiskManagerService.monitor_loop()
  ↓
1. enforce_early_trend_failure()
   └─ Early exits before trailing activates (profit < 7%)
  ↓
2. enforce_hard_limits()
   ├─ Below Entry: Dynamic reverse SL (20% → 5% adaptive)
   ├─ Above Entry: Static TP (+5%)
   └─ (Peak drawdown moved to trailing)
  ↓
3. enforce_trailing_stops() [ENHANCED - NOW ACTIVE]
   ├─ Upward: Adaptive drawdown schedule (15% → 1% exponential)
   ├─ Breakeven locking at +5% profit
   └─ Fallback: Fixed threshold (3%) if adaptive unavailable
  ↓
4. enforce_time_based_exit()
   └─ Time-based exits (if configured)
```

## Bidirectional Trailing Details

### 1. Upward Trailing (Profit Protection)

**Location**: `enforce_trailing_stops()` method

**How it works**:
- Uses **adaptive drawdown schedule** from `Positions::DrawdownSchedule`
- Activation: Only when profit >= 3% (configurable)
- Schedule: 15% → 1% allowed drawdown as profit increases from 3% → 30%
- Index-specific floors: NIFTY (1.0%), BANKNIFTY (1.2%), SENSEX (1.5%)

**Example**:
- Position reaches +10% profit (peak)
- Current profit drops to +8% (2% drop from peak)
- Allowed drawdown at 10% profit = ~8% (from schedule)
- 2% drop < 8% allowed → **No exit**
- If profit drops to +1% (9% drop from peak)
- 9% drop > 8% allowed → **Exit triggered**

**Breakeven Locking**:
- When profit reaches +5% (configurable), locks breakeven
- Prevents position from going negative after reaching profit threshold

### 2. Downward Trailing (Loss Limitation)

**Location**: `enforce_hard_limits()` method (dynamic reverse SL)

**How it works**:
- Uses **reverse dynamic SL** from `Positions::DrawdownSchedule`
- Tightens stop loss as position goes deeper into loss
- Schedule: 20% → 5% allowed loss as position goes from -0% → -30%
- Time-based tightening: -2% per minute below entry
- ATR penalties: -3% to -5% for low volatility

**Example**:
- Position goes to -10% loss
- Allowed loss at -10% = ~15% (from schedule)
- Current loss (10%) < allowed (15%) → **No exit**
- If loss reaches -16%
- Current loss (16%) > allowed (15%) → **Exit triggered**

## Configuration

### Current Active Settings

```yaml
risk:
  # Trailing Stops (Upward)
  trail_step_pct: 0.03          # 3% trailing step
  breakeven_after_gain: 0.05    # Lock breakeven at +5%
  exit_drop_pct: 0.03           # Fixed fallback threshold (3%)
  
  # Adaptive Drawdown (used by trailing)
  drawdown:
    activation_profit_pct: 3.0
    profit_min: 3.0
    profit_max: 30.0
    dd_start_pct: 15.0
    dd_end_pct: 1.0
    exponential_k: 3.0
  
  # Reverse Dynamic SL (Downward)
  reverse_loss:
    enabled: true
    max_loss_pct: 20.0
    min_loss_pct: 5.0
    loss_span_pct: 30.0
    time_tighten_per_min: 2.0
```

## Key Differences from Old System

### Old System (Disabled)
- Fixed threshold: `exit_drop_pct: 999` (disabled)
- No breakeven locking
- No adaptive schedule
- Simple: exit if drop >= threshold

### New System (Active)
- **Adaptive schedule**: Tightens as profit increases
- **Breakeven locking**: Locks in profits at +5%
- **Bidirectional**: Works above AND below entry
- **Integrated**: Works seamlessly with adaptive exits

## Integration Points

### 1. Trailing Uses Adaptive Schedule

```ruby
# In enforce_trailing_stops()
allowed_dd = Positions::DrawdownSchedule.allowed_upward_drawdown_pct(
  peak_profit_pct, 
  index_key: index_key
)
```

### 2. Reverse SL Uses Dynamic Schedule

```ruby
# In enforce_hard_limits()
dyn_loss_pct = Positions::DrawdownSchedule.reverse_dynamic_sl_pct(
  pnl_pct_value,
  seconds_below_entry: seconds_below,
  atr_ratio: atr_ratio
)
```

### 3. No Duplication

- Peak drawdown check **removed** from `enforce_hard_limits` (moved to trailing)
- Trailing now handles all upward protection
- Reverse SL handles all downward protection

## Benefits of Integration

1. **No Conflicts**: Systems work together, not against each other
2. **Consistent Logic**: Both use same calculation modules
3. **Better Protection**: Adaptive schedules provide smarter exits
4. **Bidirectional**: Protects both profits and limits losses
5. **Breakeven Safety**: Locks in profits to prevent reversals

## Testing

### Verify Trailing is Active

```ruby
# Rails console
tracker = PositionTracker.active.first
snapshot = Live::RiskManagerService.new.send(:pnl_snapshot, tracker)

# Check if trailing would trigger
hwm = snapshot[:hwm_pnl]
pnl = snapshot[:pnl]
drop_pct = (hwm - pnl) / hwm

# Check adaptive schedule
peak_profit = (hwm / (tracker.entry_price * tracker.quantity)) * 100
allowed_dd = Positions::DrawdownSchedule.allowed_upward_drawdown_pct(
  peak_profit, 
  index_key: tracker.meta['index_key']
)
```

### Monitor Logs

Look for:
- `ADAPTIVE_TRAILING_STOP` - Adaptive trailing exit
- `TRAILING_STOP` - Fixed threshold fallback
- `Breakeven locked` - Breakeven locking activated
- `DYNAMIC_LOSS_HIT` - Reverse SL exit

## Summary

✅ **Bidirectional trailing is NOW ACTIVE** and integrated with adaptive exits:
- **Upward**: Adaptive drawdown schedule (15% → 1%)
- **Downward**: Dynamic reverse SL (20% → 5%)
- **Breakeven**: Locked at +5% profit
- **Integration**: Uses same calculation modules, no conflicts

The systems work **together**, not separately. Trailing handles upward protection, reverse SL handles downward protection, and they share the same adaptive calculation logic.
