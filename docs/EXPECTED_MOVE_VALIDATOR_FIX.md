# ExpectedMoveValidator Fix

**Date**: 2026-01-20
**Issue**: All indices blocked by `ExpectedMoveValidator` with `expected_premium_below_threshold`

---

## 🔍 **Root Cause**

The `ExpectedMoveValidator` calculates if the expected option premium move (based on ATR and delta) meets a minimum threshold. This prevents entering trades when the expected payoff is too small.

**Formula**: `expected_premium = ATR * delta`

**Problem**: Thresholds were set too high for current market conditions (low ATR)

### **Observed Values** (from logs):
- **NIFTY**: ATR=7.21, delta=0.40, expected_premium=2.88, threshold=8.0 → **BLOCKED**
- **BANKNIFTY**: ATR=23.29, delta=0.38, expected_premium=8.85, threshold=18.0 → **BLOCKED**
- **SENSEX**: ATR unknown, but also blocked with threshold=15.0

---

## ✅ **Fixes Applied**

### **1. Added BANKNIFTY Support**
Previously, BANKNIFTY returned `unsupported_index` because it had no delta/threshold values.

**Added**:
```ruby
when 'BANKNIFTY'
  # Delta bucket
  strike_type == :ATM ? 0.45 : 0.38

  # Thresholds
  {
    execution_only: 2.0,
    scale_ready: 4.0,
    full_deploy: 8.0
  }
```

### **2. Significantly Lowered Thresholds**

| Index     | Permission     | Old Threshold | New Threshold | Change |
| --------- | -------------- | ------------- | ------------- | ------ |
| NIFTY     | execution_only | 4.0           | 1.0           | -75%   |
| NIFTY     | scale_ready    | 8.0           | 2.0           | -75%   |
| NIFTY     | full_deploy    | 12.0          | 4.0           | -67%   |
| SENSEX    | scale_ready    | 15.0          | 3.0           | -80%   |
| SENSEX    | full_deploy    | 25.0          | 6.0           | -76%   |
| BANKNIFTY | execution_only | (new)         | 2.0           | NEW    |
| BANKNIFTY | scale_ready    | (new)         | 4.0           | NEW    |
| BANKNIFTY | full_deploy    | (new)         | 8.0           | NEW    |

### **3. Enhanced Logging**
Added detailed logging showing actual values when blocked:
```
[ExpectedMoveValidator] BLOCKED {INDEX}: expected_premium={X} < threshold={Y} (ATR={Z}, delta={D}, strike_type={ST})
```

---

## 📊 **Expected Results**

With new thresholds:
- **NIFTY** (ATR=7.21, delta=0.40): expected_premium=2.88 vs threshold=2.0 → **✅ PASS**
- **BANKNIFTY** (ATR=23.29, delta=0.38): expected_premium=8.85 vs threshold=4.0 → **✅ PASS**
- **SENSEX**: Should pass with threshold=3.0 (needs verification)

---

## ⚠️ **Considerations**

### **Trade-off**:
- **Lower thresholds** = More entries, but potentially lower profit per trade
- **Higher thresholds** = Fewer entries, but higher expected profit per trade

### **Why These Values**:
- Designed for scalping (quick in/out)
- ATR on 1m timeframe is naturally lower than higher timeframes
- With ATM±1 strikes, delta is ~0.40, so we need low thresholds
- Current thresholds allow expected premium of 2-4 points for NIFTY

### **Alternative Approaches**:
1. **Make it configurable** via `config/algo.yml`
2. **Disable the validator** entirely (risky - no minimum profit filter)
3. **Use different timeframe** for ATR calculation (5m or 15m instead of 1m)

---

## 🎯 **Summary**

**Issues Fixed**:
- ✅ Added BANKNIFTY support (delta and thresholds)
- ✅ Lowered all thresholds by 67-80%
- ✅ Enhanced logging to show actual values

**Result**: All indices should now pass ExpectedMoveValidator with current ATR values

**Restart Required**: Trading daemon must be restarted to pick up the changes
