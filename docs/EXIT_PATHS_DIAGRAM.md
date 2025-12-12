# Exit Paths - Complete Flow Diagram

## Overview

Yes, we have **multiple exit paths** that execute in sequence. Each path checks different conditions and can trigger an exit independently. They work together as a **layered defense system**.

## Execution Order (Every 5 seconds)

```
RiskManagerService.monitor_loop()
  ↓
1. enforce_early_trend_failure()     [PATH 1: Early Detection]
  ↓
2. enforce_hard_limits()              [PATH 2: Hard Limits]
  ↓
3. enforce_trailing_stops()           [PATH 3: Adaptive Trailing]
  ↓
4. enforce_time_based_exit()          [PATH 4: Time-Based]
```

## Path 1: Early Trend Failure (ETF)

**Purpose**: Exit early when trend shows signs of failure (before trailing activates)

**When Active**: 
- Only when profit < 7% (configurable: `etf.activation_profit_pct`)
- Before trailing stops become active

**Exit Conditions**:
- ✅ Trend score drops ≥ 30% from peak
- ✅ ADX collapses below 10
- ✅ ATR ratio drops below 0.55
- ✅ VWAP rejection (price moves against position)

**Exit Reason**: `"EARLY_TREND_FAILURE (pnl: X%)"`

**Example**:
- Position at +5% profit
- Trend score drops from 100 → 60 (40% drop)
- → **Exit triggered** (prevents winner from turning into loser)

---

## Path 2: Hard Limits

**Purpose**: Static and dynamic stop-loss/take-profit enforcement

**When Active**: Always

**Exit Conditions** (checked in order):

### 2A. Dynamic Reverse SL (Below Entry)
- **When**: Position is losing money (PnL < 0)
- **Logic**: Adaptive tightening (20% → 5% as loss deepens)
- **Factors**: 
  - Current loss percentage
  - Time spent below entry (2% per minute)
  - ATR ratio penalties (-3% to -5%)
- **Exit Reason**: `"DYNAMIC_LOSS_HIT X% (allowed: Y%)"`

**Example**:
- Position at -10% loss
- Allowed loss at -10% = ~15% (from schedule)
- Time below entry: 2 minutes → -4% tightening
- ATR ratio 0.6 → -5% penalty
- Final allowed: ~6%
- Current loss 10% > 6% → **Exit triggered**

### 2B. Static Stop Loss (Fallback)
- **When**: Dynamic reverse SL disabled or not applicable
- **Logic**: Fixed threshold (-3% default)
- **Exit Reason**: `"SL HIT X%"`

### 2C. Take Profit
- **When**: Profit reaches +5% (configurable)
- **Logic**: Fixed threshold
- **Exit Reason**: `"TP HIT X%"`

**Example**:
- Position at +5.5% profit
- → **Exit triggered** (take profit)

---

## Path 3: Adaptive Trailing Stops

**Purpose**: Protect profits with adaptive drawdown schedule

**When Active**: 
- When profit ≥ 3% (configurable: `drawdown.activation_profit_pct`)
- Only for profitable positions (PnL > 0)

**Exit Conditions**:

### 3A. Adaptive Drawdown Schedule (Primary)
- **Logic**: Exponential schedule (15% → 1% as profit increases)
- **Calculation**: Uses `Positions::DrawdownSchedule.allowed_upward_drawdown_pct()`
- **Exit Reason**: `"ADAPTIVE_TRAILING_STOP (peak: X%, drop: Y%, allowed: Z%)"`

**Example**:
- Position peak: +10% profit
- Current profit: +1% (9% drop from peak)
- Allowed drawdown at 10% profit: ~8%
- 9% drop > 8% allowed → **Exit triggered**

### 3B. Fixed Threshold (Fallback)
- **When**: Adaptive schedule unavailable
- **Logic**: Fixed 3% drop from HWM
- **Exit Reason**: `"TRAILING_STOP (fixed threshold: 3%, drop: X%)"`

### 3C. Breakeven Locking
- **When**: Profit reaches +5% (configurable: `breakeven_after_gain`)
- **Action**: Locks breakeven (prevents going negative)
- **Note**: Doesn't exit, but protects position

**Example**:
- Position reaches +5% profit
- → **Breakeven locked** (position protected from going negative)

---

## Path 4: Time-Based Exit

**Purpose**: Exit all positions at specific time

**When Active**: 
- Only if configured (`time_exit_hhmm`)
- Currently **NOT CONFIGURED** (disabled)

**Exit Conditions**:
- Current time >= configured exit time
- Current time < market close time
- Position is profitable (or meets `min_profit_rupees`)

**Exit Reason**: `"time-based exit (HH:MM)"`

---

## Path Interaction & Priority

### Priority Order (First Match Wins)

1. **Early Trend Failure** (if profit < 7%)
   - Fastest exit for failing trends
   - Prevents winners from turning into losers

2. **Hard Limits** (always checked)
   - **Below Entry**: Dynamic Reverse SL (takes precedence over static SL)
   - **Above Entry**: Static TP (+5%)

3. **Trailing Stops** (if profit ≥ 3%)
   - Adaptive drawdown schedule
   - Protects profits as they grow

4. **Time-Based** (if configured)
   - End-of-day exit

### Important Notes

- **No Duplication**: Peak drawdown moved from `enforce_hard_limits` to `enforce_trailing_stops`
- **Shared Logic**: Trailing and Reverse SL use same calculation modules
- **Sequential Execution**: Paths execute in order, first match exits
- **Independent Checks**: Each path can trigger independently

## Visual Flow

```
Position Monitoring (Every 5 seconds)
  │
  ├─→ [Path 1] Early Trend Failure?
  │   └─→ YES → Exit ("EARLY_TREND_FAILURE")
  │   └─→ NO  → Continue
  │
  ├─→ [Path 2] Hard Limits?
  │   ├─→ Below Entry: Dynamic Reverse SL?
  │   │   └─→ YES → Exit ("DYNAMIC_LOSS_HIT")
  │   │   └─→ NO  → Static SL?
  │   │       └─→ YES → Exit ("SL HIT")
  │   ├─→ Above Entry: Take Profit?
  │   │   └─→ YES → Exit ("TP HIT")
  │   └─→ NO → Continue
  │
  ├─→ [Path 3] Trailing Stops? (if profit ≥ 3%)
  │   ├─→ Adaptive Drawdown?
  │   │   └─→ YES → Exit ("ADAPTIVE_TRAILING_STOP")
  │   ├─→ Fixed Threshold? (fallback)
  │   │   └─→ YES → Exit ("TRAILING_STOP")
  │   └─→ Breakeven Lock? (if profit ≥ 5%)
  │       └─→ Lock breakeven (no exit)
  │
  └─→ [Path 4] Time-Based? (if configured)
      └─→ YES → Exit ("time-based exit")
```

## Example Scenarios

### Scenario 1: Position Goes Negative
```
Position: -5% loss
  ↓
Path 1: ETF? → NO (profit < 7%, but we're losing)
  ↓
Path 2: Hard Limits
  ├─→ Below Entry: Dynamic Reverse SL?
  │   └─→ Allowed loss at -5% = ~18%
  │   └─→ Current loss 5% < 18% → NO EXIT
  └─→ Continue
  ↓
Path 3: Trailing? → NO (not profitable)
  ↓
Result: No exit (within allowed loss)
```

### Scenario 2: Position Profitable, Trend Fails
```
Position: +6% profit, trend score drops 35%
  ↓
Path 1: ETF? → YES (profit < 7%, trend failed)
  └─→ EXIT ("EARLY_TREND_FAILURE")
  ↓
Result: Exited early (prevents reversal)
```

### Scenario 3: Position Profitable, Drops from Peak
```
Position: Peak +10%, Current +1% (9% drop)
  ↓
Path 1: ETF? → NO (profit < 7%, but no trend failure)
  ↓
Path 2: Hard Limits
  └─→ TP? → NO (current +1% < +5% TP)
  ↓
Path 3: Trailing Stops
  ├─→ Adaptive Drawdown?
  │   └─→ Allowed DD at 10% profit = ~8%
  │   └─→ Current drop 9% > 8% → YES
  └─→ EXIT ("ADAPTIVE_TRAILING_STOP")
  ↓
Result: Exited (protected profit)
```

### Scenario 4: Position Hits Take Profit
```
Position: +5.5% profit
  ↓
Path 1: ETF? → NO (profit < 7%, no failure)
  ↓
Path 2: Hard Limits
  └─→ TP? → YES (+5.5% ≥ +5%)
  └─→ EXIT ("TP HIT")
  ↓
Result: Exited (take profit)
```

## Summary

**Yes, we have 4 distinct exit paths:**

1. ✅ **Early Trend Failure** - Early detection (profit < 7%)
2. ✅ **Hard Limits** - Static/dynamic SL/TP (always active)
3. ✅ **Adaptive Trailing** - Profit protection (profit ≥ 3%)
4. ⚠️ **Time-Based** - End-of-day (not configured)

**They work together** as a layered defense:
- Path 1 catches failing trends early
- Path 2 enforces hard limits (losses and profits)
- Path 3 protects growing profits adaptively
- Path 4 handles end-of-day (if configured)

**No conflicts** - they execute sequentially, first match wins.
