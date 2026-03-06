# Trailing Activation Percentage Rule

## Overview

The trailing activation percentage rule provides a **configurable threshold** that determines when trailing stop rules become active. This ensures trailing protection only activates after a position reaches a specified profit percentage, based on the buy value.

## Key Features

✅ **Fully Configurable** - Set any activation percentage (6%, 6.66%, 9.99%, 10%, 13.32%, 15%, 20%, etc.)  
✅ **Buy Value Based** - Works with `pnl_pct` calculated from buy value (premium × lot_size × lots)  
✅ **Universal** - Works across any capital, allocation percentage, lot size, or entry premium  
✅ **Gates Trailing Rules** - Controls when `TrailingStopRule` and `PeakDrawdownRule` become active  

## Configuration

### YAML Config

```yaml
risk:
  trailing:
    activation_pct: 10.0     # Activate trailing when profit >= 10% of buy value
    drawdown_pct: 3.0        # Exit if price drops this % from peak
```

### Configurable Values

You can set **any** activation percentage:

- `6.0` - Activate at 6% profit
- `6.66` - Activate at 6.66% profit
- `9.99` - Activate at 9.99% profit
- `10.0` - Activate at 10% profit (default)
- `13.32` - Activate at 13.32% profit
- `15.0` - Activate at 15% profit
- `20.0` - Activate at 20% profit

### Alternative Config Format

You can also use flat config format:

```yaml
risk:
  trailing_activation_pct: 10.0
```

## How It Works

### Formula

**Buy Value:**
```
buy_value = premium × lot_size × lots
```

**PnL Percentage:**
```
pnl_pct = (profit / buy_value) × 100
```

**Trailing Activation:**
```
if pnl_pct >= trailing_activation_pct
    start trailing
```

### Rule Behavior

1. **Before Activation**: Trailing rules (`TrailingStopRule`, `PeakDrawdownRule`) return `skip_result`
2. **After Activation**: Trailing rules evaluate normally and can trigger exits
3. **Based on Live Data**: Uses `pnl_pct` from `ActiveCache` (updated from WebSocket/Redis)

## Real-World Examples

### Scenario A: 10% Activation (Default)

**Setup:**
- Total Capital: ₹1,00,000
- Allocation: 30%
- Premium: ₹100
- Lot Size: 75

**Calculation:**
```
Entry Budget: ₹30,000
Lots: 4 lots
Buy Value: 4 × 100 × 75 = ₹30,000
Activation: 10% of ₹30,000 = ₹3,000 profit
Points Needed: ₹3,000 / (75 × 4) = 10 points
```

**Result:** Trailing activates when price moves from ₹100 → ₹110 (+10 points)

---

### Scenario B: 6% Activation

**Same Setup as Above:**

**Calculation:**
```
Activation: 6% of ₹30,000 = ₹1,800 profit
Points Needed: ₹1,800 / 300 = 6 points
```

**Result:** Trailing activates when price moves from ₹100 → ₹106 (+6 points)

---

### Scenario C: 6.66% Activation

**Calculation:**
```
Activation: 6.66% × ₹30,000 = ₹1,998 profit
Points Needed: ₹1,998 / 300 = 6.66 points
```

**Result:** Trailing activates when price moves from ₹100 → ₹106.66 (+6.66 points)

---

### Scenario D: 13.32% Activation

**Calculation:**
```
Activation: 13.32% × ₹30,000 = ₹3,996 profit
Points Needed: ₹3,996 / 300 = 13.32 points
```

**Result:** Trailing activates when price moves from ₹100 → ₹113.32 (+13.32 points)

---

### Scenario E: 20% Allocation Example

**Setup:**
- Total Capital: ₹2,10,000
- Allocation: 20%
- Premium: ₹100
- Lot Size: 75

**Calculation:**
```
Entry Budget: ₹42,000
Lots: 5 lots
Buy Value: 5 × 100 × 75 = ₹37,500

If activation_pct = 10%:
  10% × ₹37,500 = ₹3,750 profit
  Points: ₹3,750 / 375 = 10 points

If activation_pct = 6%:
  6% × ₹37,500 = ₹2,250 profit
  Points: ₹2,250 / 375 = 6 points

If activation_pct = 13.32%:
  13.32% × ₹37,500 = ₹4,995 profit
  Points: ₹4,995 / 375 = 13.32 points
```

**Key Discovery:** The activation percentage always equals the points needed from entry premium.

---

## Key Discovery

**Your % activation ALWAYS becomes points equal to that % of the entry premium.**

**Examples:**

**Entry Premium = ₹100:**
- 10% → +10 points
- 6% → +6 points
- 6.66% → +6.66 points
- 13.32% → +13.32 points

**Entry Premium = ₹150:**
- 10% → +15 points
- 6% → +9 points
- 13.32% → +19.98 points

---

## Implementation Details

### RuleContext Methods

**`trailing_activation_pct`** - Returns configured activation percentage (default: 10.0%)

```ruby
context.trailing_activation_pct
# => BigDecimal('10.0')
```

**`trailing_activated?`** - Checks if trailing should be active

```ruby
context.trailing_activated?
# => true if pnl_pct >= trailing_activation_pct
```

### Rule Integration

**TrailingStopRule:**
- Checks `context.trailing_activated?` before evaluation
- Returns `skip_result` if not activated
- Evaluates normally if activated

**PeakDrawdownRule:**
- Checks `context.trailing_activated?` before evaluation
- Returns `skip_result` if not activated
- Evaluates normally if activated

---

## Benefits

1. **Flexible Configuration** - Set any activation percentage to match your trading style
2. **Capital Agnostic** - Works with any capital amount or allocation percentage
3. **Lot Size Independent** - Works with any lot size (50, 75, 100, etc.)
4. **Premium Independent** - Works with any entry premium
5. **Prevents Early Exits** - Trailing only activates after reaching profit threshold
6. **Based on Buy Value** - Uses actual position PnL percentage, not capital-based calculations

---

## Configuration Examples

### Conservative (Early Activation)
```yaml
risk:
  trailing:
    activation_pct: 6.0  # Activate early at 6%
```

### Moderate (Default)
```yaml
risk:
  trailing:
    activation_pct: 10.0  # Activate at 10%
```

### Aggressive (Late Activation)
```yaml
risk:
  trailing:
    activation_pct: 15.0  # Activate later at 15%
```

### Custom Precision
```yaml
risk:
  trailing:
    activation_pct: 6.66   # Activate at 6.66%
    # or
    activation_pct: 13.32  # Activate at 13.32%
```

---

## Important Notes

### What It Affects

✅ **When trailing starts** - Controls activation threshold  
✅ **TrailingStopRule** - Gates when this rule becomes active  
✅ **PeakDrawdownRule** - Gates when this rule becomes active  

### What It Does NOT Affect

✘ **Total capital** - Not based on total capital  
✘ **Allocated capital** - Not based on allocated capital  
✘ **Lot buying** - Does not affect how lots are bought  
✘ **SL/TP behavior** - Does not affect stop loss or take profit rules  

### Based On

✔ **Buy value** - Calculated from premium × lot_size × lots  
✔ **PnL percentage** - From live Redis + WebSocket data  
✔ **Position data** - Uses `pnl_pct` from `ActiveCache`  

---

## Testing

Comprehensive test coverage in `spec/services/risk/rules/trailing_activation_spec.rb`:

- ✅ Config parsing (nested and flat formats)
- ✅ Various activation percentages (6%, 6.66%, 10%, 13.32%, etc.)
- ✅ Activation threshold checks
- ✅ TrailingStopRule integration
- ✅ PeakDrawdownRule integration
- ✅ Real-world scenarios

---

## Summary

The trailing activation percentage rule provides **flexible, configurable control** over when trailing stop protection becomes active. Set any percentage (6%, 6.66%, 10%, 13.32%, etc.) and the system will activate trailing rules only after that profit threshold is reached, based on buy value and live PnL data.

**Key Takeaway:** The activation percentage always equals the points needed from entry premium, making it easy to understand and configure.
