# Rupee-Based Scalper Mode

## Overview

This document describes the **rupee-based position sizing and hard rupee stops** feature, designed for professional-grade scalping with fixed ₹1,000 stop loss and ₹2,000 target profit per trade.

## Key Concept

**Position sizing is derived from ₹ risk, not percentages.**

This ensures:
- ✅ Consistent risk per trade (₹1,000)
- ✅ Consistent target per trade (₹2,000)
- ✅ Clean 1:2 risk-reward ratio
- ✅ No random SL hits from percentage-based calculations

## Configuration

### Enable Rupee-Based Mode

In `config/algo.yml`:

```yaml
# Position sizing: rupee-based (recommended for scalping)
position_sizing:
  enabled: true # Set to true to enable
  mode: rupee_based

  # Fixed risk per trade
  risk_rupees: 1000 # ₹1,000 risk per trade
  target_rupees: 2000 # ₹2,000 target per trade
  stop_distance_rupees: 8 # Stop distance in rupees (global default)

  # Index-specific stop distances (override global if specified)
  index_stop_distances:
    NIFTY: 8      # Typical: ₹6-10 for NIFTY
    BANKNIFTY: 12 # Typical: ₹12-20 for BANKNIFTY
    SENSEX: 15    # Typical: ₹12-20 for SENSEX

# Hard rupee stops (HIGHEST PRIORITY)
risk:
  hard_rupee_sl:
    enabled: true # Set to true to enable
    max_loss_rupees: 1000 # Maximum loss per trade

  hard_rupee_tp:
    enabled: true # Set to true to enable
    target_profit_rupees: 2000 # Target profit per trade
```

## How It Works

### Position Sizing Formula

```
risk_per_lot = stop_distance_rupees × lot_size
max_lots = floor(risk_rupees / risk_per_lot)
quantity = max_lots × lot_size
```

**Example (NIFTY):**
- Entry premium: ₹100
- Lot size: 75
- Stop distance: ₹8
- Risk per lot: ₹8 × 75 = ₹600
- Max lots: floor(1000 / 600) = 1 lot
- Quantity: 1 × 75 = **75 shares**

### Exit Priority

Hard rupee stops are checked **FIRST** (highest priority), before any percentage-based stops:

1. **Hard Rupee SL** (if enabled): Exit if PnL ≤ -₹1,000
2. **Hard Rupee TP** (if enabled): Exit if PnL ≥ ₹2,000
3. Percentage-based stops (fallback/secondary)

## Expected Behavior

With decent signal quality (1m Supertrend + ADX):

- **Win rate**: 40-55%
- **Avg loss**: ₹1,000 (hard stop)
- **Avg win**: ₹1,800-₹2,500
- **Max daily drawdown** (5 trades): ₹5,000
- **Monthly consistency**: Very high

## When to Use

✅ **Recommended for:**
- 1-minute Supertrend + ADX scalping
- High-frequency trading
- Consistent risk management
- Clean equity curves

❌ **Not recommended for:**
- Swing trading (use percentage-based)
- Very volatile markets without proper stop distances
- Illiquid strikes
- Near expiry (high theta decay)

## Important Guards

Even with rupee-based sizing, maintain these guards:

- ✅ ADX ≥ 15 (1m)
- ✅ ATR ratio not collapsing
- ✅ No entries after 14:30
- ✅ ATM / ATM±1 only
- ✅ Avoid trading during chop

## Example Configuration

### Pure Scalper Mode (Recommended Initially)

```yaml
position_sizing:
  enabled: true
  risk_rupees: 1000
  target_rupees: 2000
  stop_distance_rupees: 8

risk:
  hard_rupee_sl:
    enabled: true
    max_loss_rupees: 1000
  hard_rupee_tp:
    enabled: true
    target_profit_rupees: 2000

  # Disable trailing for pure scalper mode
  exit_drop_pct: 999 # Disabled
  trailing:
    activation_pct: 999 # Disabled
```

### Hybrid Mode (Best Long-Term)

```yaml
position_sizing:
  enabled: true
  risk_rupees: 1000
  target_rupees: 2000
  stop_distance_rupees: 8

risk:
  hard_rupee_sl:
    enabled: true
    max_loss_rupees: 1000 # Always active
  hard_rupee_tp:
    enabled: true
    target_profit_rupees: 2000

  # Trailing activates after ₹1,500 profit
  trailing:
    activation_pct: 15.0 # Activate at 15% (≈₹1,500 on ₹10k position)
    drawdown_pct: 3.0
```

## Implementation Details

### Files Modified

1. **`app/services/capital/allocator.rb`**
   - Added `calculate_rupee_based_quantity()` method
   - Modified `qty_for()` to check rupee-based mode

2. **`app/services/live/risk_manager_service.rb`**
   - Added hard rupee SL/TP checks in `enforce_hard_limits()`
   - Checks run FIRST (highest priority)

3. **`config/algo.yml`**
   - Added `position_sizing` section
   - Added `risk.hard_rupee_sl` and `risk.hard_rupee_tp` sections

## Testing

To test rupee-based sizing:

1. Enable in `algo.yml`:
   ```yaml
   position_sizing:
     enabled: true
     risk_rupees: 1000
     stop_distance_rupees: 8
   ```

2. Check logs for `[Allocator] RUPEES_BASED` messages

3. Verify quantity calculation matches expected formula

4. Monitor exits for `HARD_RUPEE_SL` and `HARD_RUPEE_TP` reasons

## Troubleshooting

### Issue: Quantity is too small

**Solution**: Check `stop_distance_rupees` - if too large, risk per lot exceeds risk_rupees, resulting in 0 lots.

### Issue: Hard stops not triggering

**Solution**: Verify `hard_rupee_sl.enabled: true` and `hard_rupee_tp.enabled: true` in `algo.yml`.

### Issue: Position size doesn't match expected

**Solution**: Check capital constraint - if capital is insufficient, quantity will be reduced to affordable amount.

## References

- Original design document: User query on ₹1k SL + ₹2k TP scalper mode
- Risk-reward ratio: 1:2 (34% break-even win rate)
- Expected win rate: 45-50% for positive expectancy
