# Secure Profit Rule - Maximizing Profits in Options Trading

## Overview

The `SecureProfitRule` is designed to help traders **maximize profits** while **protecting gains** in volatile options trading. It addresses the challenge of:

- **Securing profits** when they exceed a threshold (default: ₹1000)
- **Allowing positions to ride** for maximum gains
- **Protecting against sudden reversals** that are common in options trading

## How It Works

### Strategy

1. **Activation Threshold**: When profit reaches or exceeds ₹1000, the rule activates
2. **Tighter Protection**: Uses a tighter peak drawdown threshold (default: 3% instead of 5%)
3. **Peak Tracking**: Monitors the peak profit achieved
4. **Exit Trigger**: Exits if profit drops by the drawdown threshold from the peak

### Example Scenarios

#### Scenario 1: Securing Profit Above ₹1000

**Position Flow:**
```
Entry: ₹100
Current: ₹120 → Profit: ₹1000 (10% gain)
Peak: ₹125 → Peak Profit: ₹1200 (25% gain)
Current: ₹122 → Profit: ₹1100 (22% gain)
```

**Rule Evaluation:**
```
Priority 35: SecureProfitRule
  → Profit: ₹1100 >= ₹1000? YES ✅
  → Peak: 25%, Current: 22%
  → Drawdown: 25% - 22% = 3%
  → Threshold: 3%
  → 3% >= 3%? YES ✅
  → Result: EXIT with reason "secure_profit_exit"
```

**Outcome:** Position exited at ₹1100 profit, protecting gains from potential reversal.

---

#### Scenario 2: Riding Profits Below Threshold

**Position Flow:**
```
Entry: ₹100
Current: ₹105 → Profit: ₹500 (5% gain)
Peak: ₹108 → Peak Profit: ₹800 (8% gain)
Current: ₹106 → Profit: ₹600 (6% gain)
```

**Rule Evaluation:**
```
Priority 35: SecureProfitRule
  → Profit: ₹600 >= ₹1000? NO ❌
  → Result: no_action (rule not activated)
```

**Outcome:** Position continues to ride - rule doesn't interfere with smaller profits.

---

#### Scenario 3: Protecting Against Reversal

**Position Flow:**
```
Entry: ₹100
Current: ₹130 → Profit: ₹1500 (30% gain) ✅ Secured
Peak: ₹135 → Peak Profit: ₹1750 (35% gain)
Current: ₹128 → Profit: ₹1400 (28% gain)
```

**Rule Evaluation:**
```
Priority 35: SecureProfitRule
  → Profit: ₹1400 >= ₹1000? YES ✅
  → Peak: 35%, Current: 28%
  → Drawdown: 35% - 28% = 7%
  → Threshold: 3%
  → 7% >= 3%? YES ✅
  → Result: EXIT with reason "secure_profit_exit"
```

**Outcome:** Position exited at ₹1400, protecting against further reversal. Without this rule, position might have dropped to ₹500 or lower.

---

#### Scenario 4: Allowing Further Upside

**Position Flow:**
```
Entry: ₹100
Current: ₹120 → Profit: ₹1000 (10% gain) ✅ Secured
Peak: ₹120 → Peak Profit: ₹1000 (10% gain)
Current: ₹125 → Profit: ₹1250 (25% gain)
Peak: ₹125 → Peak Profit: ₹1250 (25% gain) [Updated]
Current: ₹130 → Profit: ₹1500 (30% gain)
Peak: ₹130 → Peak Profit: ₹1500 (30% gain) [Updated]
Current: ₹128 → Profit: ₹1400 (28% gain)
```

**Rule Evaluation:**
```
Priority 35: SecureProfitRule
  → Profit: ₹1400 >= ₹1000? YES ✅
  → Peak: 30%, Current: 28%
  → Drawdown: 30% - 28% = 2%
  → Threshold: 3%
  → 2% >= 3%? NO ❌
  → Result: no_action (allows riding)
```

**Outcome:** Position continues to ride - profit can grow from ₹1000 to ₹1500, but protected if it drops 3% from peak.

---

## Configuration

### Default Settings

```yaml
risk:
  secure_profit_threshold_rupees: 1000  # Activate when profit >= ₹1000
  secure_profit_drawdown_pct: 3.0        # Exit if profit drops 3% from peak
```

### Customization Options

#### 1. Adjust Secure Profit Threshold

**For Conservative Trading:**
```yaml
risk:
  secure_profit_threshold_rupees: 500  # Activate earlier at ₹500
  secure_profit_drawdown_pct: 2.0     # Tighter 2% protection
```

**For Aggressive Trading:**
```yaml
risk:
  secure_profit_threshold_rupees: 2000  # Activate later at ₹2000
  secure_profit_drawdown_pct: 5.0       # Looser 5% protection
```

#### 2. Adjust Drawdown Threshold

**Tighter Protection (More Conservative):**
```yaml
risk:
  secure_profit_drawdown_pct: 2.0  # Exit on 2% drop from peak
```

**Looser Protection (More Aggressive):**
```yaml
risk:
  secure_profit_drawdown_pct: 5.0  # Exit on 5% drop from peak
```

---

## Rule Priority

The `SecureProfitRule` has **Priority 35**, which places it:

- **After**: StopLossRule (20), TakeProfitRule (30), BracketLimitRule (25)
- **Before**: TimeBasedExitRule (40), PeakDrawdownRule (45)

This ensures:
1. Basic SL/TP rules are checked first
2. Secure profit rule activates for positions in profit
3. Other trailing rules can still apply if secure profit doesn't trigger

---

## Interaction with Other Rules

### With PeakDrawdownRule

- **SecureProfitRule** (Priority 35): Activates when profit >= ₹1000, uses 3% drawdown
- **PeakDrawdownRule** (Priority 45): General peak drawdown with 5% threshold

**Behavior:**
- If profit >= ₹1000: SecureProfitRule triggers first with tighter protection
- If profit < ₹1000: PeakDrawdownRule provides general protection

### With TakeProfitRule

- **TakeProfitRule** (Priority 30): Fixed percentage-based exit (e.g., exit at +10%)
- **SecureProfitRule** (Priority 35): Dynamic trailing protection above ₹1000

**Behavior:**
- If TP threshold hit: TakeProfitRule exits first
- If profit grows beyond TP: SecureProfitRule takes over for trailing protection

---

## Benefits for Options Trading

### 1. Handles Volatility
Options can move 20-50% in minutes. This rule protects against sudden reversals while allowing upside.

### 2. Maximizes Profits
Unlike fixed TP rules, this allows positions to ride for maximum gains while protecting secured profits.

### 3. Reduces Emotional Decisions
Automated protection removes the need to manually monitor and decide when to exit.

### 4. Adapts to Market Conditions
Tighter protection when profits are secured, looser when building profits.

---

## Real-World Example

**Trade Setup:**
- Entry: ₹100 per option
- Quantity: 10 options
- Entry Cost: ₹1000

**Trade Flow:**
```
Time 10:00 AM: Entry at ₹100, Profit: ₹0
Time 10:15 AM: LTP ₹110, Profit: ₹500 (5% gain) - Rule inactive
Time 10:30 AM: LTP ₹120, Profit: ₹1000 (10% gain) - Rule ACTIVATED ✅
Time 10:45 AM: LTP ₹130, Profit: ₹1500 (15% gain), Peak: ₹1500
Time 11:00 AM: LTP ₹128, Profit: ₹1400 (14% gain), Peak: ₹1500
  → Drawdown: 15% - 14% = 1% < 3% threshold → Continue riding
Time 11:15 AM: LTP ₹135, Profit: ₹1750 (17.5% gain), Peak: ₹1750
Time 11:30 AM: LTP ₹130, Profit: ₹1500 (15% gain), Peak: ₹1750
  → Drawdown: 17.5% - 15% = 2.5% < 3% threshold → Continue riding
Time 11:45 AM: LTP ₹125, Profit: ₹1250 (12.5% gain), Peak: ₹1750
  → Drawdown: 17.5% - 12.5% = 5% >= 3% threshold → EXIT ✅
```

**Result:**
- **Exit Price**: ₹125
- **Exit Profit**: ₹1250
- **Maximum Peak**: ₹1750 (17.5% gain)
- **Protected**: ₹1250 profit secured (would have been ₹500 or less without protection)

---

## Best Practices

1. **Set Appropriate Threshold**: Start with ₹1000, adjust based on your capital and risk tolerance
2. **Monitor Drawdown**: 3% is good for options, adjust based on volatility
3. **Combine with Other Rules**: Works best with StopLossRule and TakeProfitRule
4. **Test in Paper Trading**: Validate settings before live trading
5. **Review Regularly**: Adjust thresholds based on market conditions and performance

---

## Troubleshooting

### Rule Not Triggering

**Check:**
- Profit is actually >= `secure_profit_threshold_rupees`
- Peak profit is being tracked correctly
- Drawdown calculation is correct

### Exiting Too Early

**Solution:**
- Increase `secure_profit_drawdown_pct` (e.g., from 3% to 5%)
- Increase `secure_profit_threshold_rupees` (e.g., from ₹1000 to ₹2000)

### Not Protecting Enough

**Solution:**
- Decrease `secure_profit_drawdown_pct` (e.g., from 3% to 2%)
- Decrease `secure_profit_threshold_rupees` (e.g., from ₹1000 to ₹500)

---

## Summary

The `SecureProfitRule` is your **profit maximization and protection tool** for options trading:

✅ **Secures profits** above ₹1000  
✅ **Allows riding** for maximum gains  
✅ **Protects against reversals** with tight trailing  
✅ **Handles volatility** common in options  
✅ **Automated** - no manual intervention needed  

Configure it to match your trading style and risk tolerance!
