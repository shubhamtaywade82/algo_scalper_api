# Trailing Activation Implementation Summary

## ✅ Implementation Status: COMPLETE

The configurable trailing activation percentage feature is **fully implemented** and ready for use.

---

## Implementation Details

### 1. Configuration (`config/algo.yml`)

```yaml
risk:
  trailing:
    activation_pct: 10.0  # Configurable: 6%, 6.66%, 9.99%, 10%, 13.32%, 15%, 20%, etc.
    drawdown_pct: 3.0
```

**Alternative Format:**
```yaml
risk:
  trailing_activation_pct: 10.0
```

---

### 2. RuleContext Methods (`app/services/risk/rules/rule_context.rb`)

**`trailing_activation_pct(default = BigDecimal('10.0'))`**
- Reads from nested config: `risk[:trailing][:activation_pct]`
- Falls back to flat config: `risk[:trailing_activation_pct]`
- Returns default `10.0` if not configured

**`trailing_activated?`**
- Checks if `pnl_pct >= trailing_activation_pct`
- Returns `false` if `pnl_pct` is `nil` or `activation_pct` is zero
- Used by trailing rules to gate activation

---

### 3. TrailingStopRule (`app/services/risk/rules/trailing_stop_rule.rb`)

**Lines 19-26:**
```ruby
# Check trailing activation threshold (pnl_pct >= trailing_activation_pct)
unless context.trailing_activated?
  Rails.logger.debug(
    "[TrailingStopRule] Trailing not activated: pnl_pct=#{context.pnl_pct&.round(2)}% " \
    "< activation_pct=#{context.trailing_activation_pct.to_f.round(2)}%"
  )
  return skip_result
end
```

**Behavior:**
- Checks `context.trailing_activated?` before evaluation
- Returns `skip_result` if not activated
- Includes activation percentage in exit metadata

---

### 4. PeakDrawdownRule (`app/services/risk/rules/peak_drawdown_rule.rb`)

**Lines 14-22:**
```ruby
# Check trailing activation threshold (pnl_pct >= trailing_activation_pct)
# Peak drawdown rule only activates after trailing activation threshold is met
unless context.trailing_activated?
  Rails.logger.debug(
    "[PeakDrawdownRule] Trailing not activated: pnl_pct=#{context.pnl_pct&.round(2)}% " \
    "< activation_pct=#{context.trailing_activation_pct.to_f.round(2)}%"
  )
  return skip_result
end
```

**Behavior:**
- Checks `context.trailing_activated?` before evaluation
- Returns `skip_result` if not activated
- Includes activation percentage in exit metadata

---

### 5. SecureProfitRule (`app/services/risk/rules/secure_profit_rule.rb`)

**Note:** SecureProfitRule does **NOT** use trailing activation threshold because it has its own independent threshold (₹1000 in rupees, not percentage-based).

**Behavior:**
- Activates when `pnl_rupees >= secure_profit_threshold_rupees` (default ₹1000)
- Uses tighter drawdown threshold (`secure_profit_drawdown_pct`, default 3%)
- Independent of trailing activation percentage

---

## How It Works

### Formula

```
buy_value = premium × lot_size × lots
pnl_pct = (profit / buy_value) × 100

if pnl_pct >= trailing_activation_pct
    start trailing (TrailingStopRule, PeakDrawdownRule become active)
```

### Key Discovery

**The activation percentage always equals the points needed from entry premium.**

**Examples:**
- Entry premium = ₹100
  - 10% → +10 points
  - 6% → +6 points
  - 6.66% → +6.66 points
  - 13.32% → +13.32 points

- Entry premium = ₹150
  - 10% → +15 points
  - 6% → +9 points
  - 13.32% → +19.98 points

---

## Configuration Examples

### Conservative (Early Activation)
```yaml
risk:
  trailing:
    activation_pct: 6.0  # Activate at 6%
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
    activation_pct: 15.0  # Activate at 15%
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

## Test Coverage

### Comprehensive Specs

1. **`spec/services/risk/rules/trailing_activation_spec.rb`**
   - Config parsing (nested and flat)
   - Various activation percentages (6%, 6.66%, 10%, 13.32%, etc.)
   - Activation threshold checks
   - TrailingStopRule integration
   - PeakDrawdownRule integration
   - Real-world scenarios (A, B, C, D, E)

2. **`spec/services/risk/rules/rule_context_spec.rb`**
   - Tests for `trailing_activation_pct` method
   - Tests for `trailing_activated?` method

3. **`spec/services/risk/rules/trailing_stop_rule_spec.rb`**
   - Activation threshold tests
   - Different activation percentages

4. **`spec/services/risk/rules/peak_drawdown_rule_spec.rb`**
   - Activation threshold tests
   - Different activation percentages

5. **`spec/services/risk/rule_engine_simulation_spec.rb`** (NEW)
   - Full integration test with real `Live::RiskManagerService` and `Risk::Rules::RuleEngine`
   - Complete position lifecycle simulation
   - All scenarios: SL, TP, trailing activation, secure profit, time-based, session end, underlying break, stale data, etc.

---

## What It Affects

✅ **TrailingStopRule** - Gates when this rule becomes active  
✅ **PeakDrawdownRule** - Gates when this rule becomes active  
✅ **When trailing starts** - Controls activation threshold  

---

## What It Does NOT Affect

✘ **SecureProfitRule** - Has its own independent threshold (₹1000)  
✘ **StopLossRule** - Always active (no activation threshold)  
✘ **TakeProfitRule** - Always active (no activation threshold)  
✘ **Total capital** - Not based on total capital  
✘ **Allocated capital** - Not based on allocated capital  
✘ **Lot buying** - Does not affect how lots are bought  
✘ **SL/TP behavior** - Does not affect stop loss or take profit rules  

---

## Usage

### In Code

```ruby
# Check if trailing is activated
context = Risk::Rules::RuleContext.new(
  position: position,
  tracker: tracker,
  risk_config: risk_config
)

if context.trailing_activated?
  # Trailing rules are active
  # pnl_pct >= trailing_activation_pct
end

# Get activation percentage
activation_pct = context.trailing_activation_pct
# => BigDecimal('10.0')
```

### In Rules

```ruby
def evaluate(context)
  return skip_result unless context.active?
  
  # Check trailing activation threshold
  unless context.trailing_activated?
    return skip_result
  end
  
  # Continue with trailing logic...
end
```

---

## Summary

✅ **Fully Implemented** - All code is in place  
✅ **Fully Tested** - Comprehensive test coverage  
✅ **Fully Documented** - Complete documentation  
✅ **Production Ready** - Ready for use  

The configurable trailing activation percentage feature is **complete and ready for production use**.
