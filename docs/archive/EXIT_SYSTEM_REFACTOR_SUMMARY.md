# Exit System Refactor - Summary

## Overview

The exit system has been refactored from an over-engineered, options-misaligned system to a **clean, 5-layer exit mechanism** optimized for **intraday options buying**.

## What Changed

### Before (Over-Engineered)
- 15+ exit rules with overlapping logic
- ETF, stall detection, trailing stops, % SL/TP, rupee SL/TP, profit zones
- Checked every 5 seconds
- Optimized for linear instruments (futures)
- Contradictory signals
- Complex debugging

### After (Clean & Options-Aligned)
- **5 exit layers** with clear priorities
- Structure-first, momentum-aware, time-constrained
- Aligned with option premium behavior (gamma, theta)
- Simple, brutal, effective

---

## New 5-Layer Exit System

### LAYER 1: Hard Risk Circuit Breaker
**Priority**: Highest (checked first)

**Purpose**: Account protection ONLY - no trade logic

**Implementation**: `enforce_hard_rupee_stop_loss()`

**Exit Condition**:
- Net PnL <= (-max_loss_rupees * sl_multiplier + exit_fee)
- Default: ₹1000 (configurable)
- Time regime multiplier applied

**Exit Reason**: `"HARD_RUPEE_SL (Current net: ₹X.XX, Net after exit: ₹Y.YY, limit: -₹Z.ZZ)"`

**Exit Path**: `'hard_rupee_stop_loss'`

---

### LAYER 2: Structure Invalidation
**Priority**: High (checked after hard rupee SL)

**Purpose**: Exit when trade thesis is broken - **structure-first, not PnL-first**

**Implementation**: `enforce_structure_invalidation()` → `Risk::Rules::StructureInvalidationRule`

**Exit Condition**:
- 1m or 5m structure breaks AGAINST position direction
- BOS failure detected (price breaks swing high/low against position)
- Reclaim of broken level

**Ignores**:
- PnL
- % profit
- Trailing
- Rupee targets

**Exit Reason**: `"STRUCTURE_INVALIDATION (bullish/bearish structure broken)"`

**Exit Path**: `'structure_invalidation'`

**This is how professional options traders exit.**

---

### LAYER 3: Premium Momentum Failure
**Priority**: Medium-High (checked after structure invalidation)

**Purpose**: Kill dead option trades before theta eats them

**Implementation**: `enforce_premium_momentum_failure()` → `Risk::Rules::PremiumMomentumFailureRule`

**Exit Condition**:
- Premium does NOT make new high/low within N candles

**Index-Specific Thresholds**:
- **NIFTY**: 1m → 2 candles, 5m → 1 candle
- **BANKNIFTY**: 1m → 2 candles, 5m → 1 candle
- **SENSEX**: 1m → 3 candles, 5m → 2 candles

**Replaces**:
- Early Trend Failure (ETF)
- Stall Detection
- Most trailing stop logic

**Exit Reason**: `"PREMIUM_MOMENTUM_FAILURE (1m/5m: no progress in N candles)"`

**Exit Path**: `'premium_momentum_failure'`

**This aligns with gamma decay and theta bleed.**

---

### LAYER 4: Time Stop
**Priority**: Medium (checked after premium momentum failure)

**Purpose**: Prevent holding dead trades - exit regardless of PnL when time limit exceeded

**Implementation**: `enforce_time_stop()` → `Risk::Rules::TimeStopRule`

**Exit Condition**:
- **Scalps**: Max 2-3 minutes OR 2 candles
- **Trend trades**:
  - NIFTY: max 45 minutes
  - SENSEX: max 90 minutes

**Exit Reason**: `"TIME_STOP (scalp/trend trade exceeded X minutes/candles)"`

**Exit Path**: `'time_stop'`

**Critical for options: dead premiums don't recover.**

---

### LAYER 5: End-of-Day Flatten
**Priority**: Low (checked last)

**Purpose**: Operational safety - always exit before market close

**Implementation**: `enforce_time_based_exit()` (kept from legacy system)

**Exit Condition**:
- Current time >= time_exit_hhmm (default: 3:20 PM IST)
- Current time < market_close_hhmm (default: 3:30 PM IST)

**Exit Reason**: `"time-based exit (HH:MM)"`

**Exit Path**: `'time_based'`

---

## Files Created

1. **`app/services/risk/rules/structure_invalidation_rule.rb`**
   - Structure-first exit rule
   - Checks 1m/5m BOS failures

2. **`app/services/risk/rules/premium_momentum_failure_rule.rb`**
   - Premium momentum tracking
   - Index-specific thresholds

3. **`app/services/risk/rules/time_stop_rule.rb`**
   - Contextual time stops
   - Scalp vs trend differentiation

---

## Files Modified

1. **`app/services/live/risk_manager_service.rb`**
   - Refactored `monitor_loop()` to use new 5-layer system
   - Added new enforcement methods:
     - `enforce_hard_rupee_stop_loss()`
     - `enforce_structure_invalidation()`
     - `enforce_premium_momentum_failure()`
     - `enforce_time_stop()`
   - Legacy methods kept but not called (for reference)

---

## Legacy Rules Disabled

The following rules are **no longer called** but kept for reference:

- `enforce_early_trend_failure()` → Replaced by `premium_momentum_failure`
- `enforce_global_time_overrides()` → Replaced by `structure_invalidation` + `premium_momentum_failure`
- `enforce_hard_limits()` (rupee TP) → Removed (not aligned with options)
- `enforce_post_profit_zone()` → Removed (not aligned with options)
- `enforce_trailing_stops()` → Replaced by `premium_momentum_failure`

**Static % SL/TP** logic is also disabled (not called in new system).

---

## Configuration

### Enable/Disable New Rules

```yaml
# config/algo.yml
risk:
  exits:
    structure_invalidation:
      enabled: true  # Default: true
    premium_momentum_failure:
      enabled: true  # Default: true
    time_stop:
      enabled: true  # Default: true

  # Hard rupee SL (Layer 1) - always enabled if configured
  hard_rupee_sl:
    enabled: true
    max_loss_rupees: 1000

  # Time-based exit (Layer 5) - always enabled if configured
  time_exit_hhmm: "15:20"
  market_close_hhmm: "15:30"
```

---

## Exit Priority Order (Final)

```
1. Hard Rupee SL (Account protection)
   ↓ (if not triggered)
2. Structure Invalidation (Structure breaks)
   ↓ (if not triggered)
3. Premium Momentum Failure (Dead premium)
   ↓ (if not triggered)
4. Time Stop (Time limit exceeded)
   ↓ (if not triggered)
5. End-of-Day Flatten (3:20 PM)
```

**First-match-wins** - evaluation stops immediately on exit.

---

## Benefits

1. **Fewer Exits**: Only 5 layers vs 15+ rules
2. **Cleaner Winners**: Structure-first exits let winners run
3. **Faster Loss Cutting**: Structure invalidation exits losers fast
4. **No Contradiction**: Single, clear exit logic per layer
5. **Easy Debugging**: Clear exit reasons and paths
6. **Options-Aligned**: Matches real option premium behavior
7. **Same Logic**: Works for backtest / paper / live

---

## Migration Notes

### Backward Compatibility

- `ExitEngine.execute_exit()` API unchanged
- `OrderRouter.exit_market()` unchanged
- Telegram notifications still fire
- Redis PnL updates unchanged
- Legacy methods kept (not called) for reference

### Testing

New rules should be tested with:
- Mocked trackers
- No live market data required
- Verify each layer triggers correctly
- Verify first-match-wins behavior

---

## What This Achieves

> **In intraday options buying, the best exit system is the one you can explain in 30 seconds.**

**Before**: 20 minutes to explain
**After**: 30 seconds to explain

**Before**: Over-engineered, contradictory
**After**: Simple, brutal, effective

**Before**: Optimized for futures
**After**: Optimized for options

---

## Next Steps

1. **Test the new rules** with mocked trackers
2. **Monitor in paper trading** to verify behavior
3. **Remove legacy methods** once confident (optional)
4. **Tune thresholds** based on real trading data

---

## Related Documentation

- `docs/EXIT_MECHANISM_AND_RULES.md` - Complete exit system reference (legacy)
- `docs/EXIT_SYSTEM_FILE_REFERENCE.md` - File reference
- `docs/risk_management_rules_overview.md` - Rule engine overview
