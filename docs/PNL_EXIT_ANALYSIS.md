# PnL Exit Analysis Report

**Generated:** 2025-12-18
**Purpose:** Analyze PnL values at which positions are exiting and verify hard rupee stop behavior

---

## Summary

### Current Exit Behavior

Positions are currently exiting via **percentage-based stops**, not hard rupee stops. All exits are triggered by:
- **Stop Loss**: Percentage-based (e.g., "SL HIT -11.25%", "SL HIT -21.42%")
- **Take Profit**: Percentage-based (e.g., "TP HIT 13.11%", "TP HIT 59.32%")

### PnL Distribution (Last 7 Days)

#### Positive PnL Exits
- **Count**: Multiple positions
- **Range**: ₹2.75 to ₹296.75
- **Average**: ~₹160
- **Median**: ₹160.25

**Sample Positive Exits:**
- ₹2.75 (0.07% gain) - TP HIT 7.45%
- ₹20.25 (0.13% gain) - TP HIT 13.11%
- ₹160.25 (0.61% gain) - TP HIT 60.67%
- ₹163.75 (0.59% gain) - TP HIT 59.32%
- ₹296.75 (1.02% gain) - TP HIT 102.38%

#### Negative PnL Exits
- **Count**: Multiple positions
- **Range**: ₹-55.0 to ₹-126.75
- **Average**: ~₹-89.42
- **Median**: ₹-86.5

**Sample Negative Exits:**
- ₹-55.0 (-0.11% loss) - SL HIT -11.25%
- ₹-69.0 (-0.16% loss) - SL HIT -16.38%
- ₹-86.5 (-0.21% loss) - SL HIT -21.42%
- ₹-112.75 (-0.32% loss) - SL HIT -31.66%
- ₹-126.75 (-0.33% loss) - SL HIT -33.25%

---

## Hard Rupee Stop Analysis

### Configuration Status
- **Hard Rupee SL**: Check `config/algo.yml` → `risk.hard_rupee_sl.enabled`
- **Hard Rupee SL Limit**: ₹1,000 (default)
- **Hard Rupee TP**: Check `config/algo.yml` → `risk.hard_rupee_tp.enabled`
- **Hard Rupee TP Limit**: ₹2,000 (default)

### Why Hard Rupee Stops Aren't Triggering

**Current PnL values are far below hard rupee thresholds:**
- **Largest Loss**: ₹-126.75 (well above -₹1,000 threshold)
- **Largest Profit**: ₹296.75 (well below ₹2,000 threshold)

**Conclusion**: Hard rupee stops are not triggering because:
1. Positions are exiting early via percentage-based stops
2. PnL values never reach the hard rupee thresholds (₹1,000 SL / ₹2,000 TP)

---

## Exit Path Analysis

### Exit Paths Observed
1. **`stop_loss_static_downward`**: Percentage-based stop loss
2. **`take_profit`**: Percentage-based take profit
3. **`hard_rupee_stop_loss`**: **NOT OBSERVED** (0 exits)
4. **`hard_rupee_take_profit`**: **NOT OBSERVED** (0 exits)

---

## Key Findings

### 1. Early Exits
Positions are exiting at very small PnL values:
- **Smallest profit**: ₹2.75
- **Smallest loss**: ₹-55.0

This suggests percentage-based stops are very tight and trigger before hard rupee stops can activate.

### 2. Hard Rupee Stops Not Active
- **0 exits** via hard rupee stop loss
- **0 exits** via hard rupee take profit

This indicates either:
- Hard rupee stops are **disabled** in config
- Positions never reach the ₹1,000 SL / ₹2,000 TP thresholds

### 3. PnL Calculation
All PnL values shown are **net PnL** (after broker fees):
- Entry fee (₹20) already deducted
- Exit fee (₹20) will be deducted on exit
- Final net PnL = Current net PnL - ₹20 (exit fee)

---

## Recommendations

### To Enable Hard Rupee Stops

1. **Check Configuration**:
   ```yaml
   risk:
     hard_rupee_sl:
       enabled: true  # Must be true
       max_loss_rupees: 1000
     hard_rupee_tp:
       enabled: true  # Must be true
       target_profit_rupees: 2000
   ```

2. **Adjust Percentage-Based Stops**:
   - If percentage stops are too tight, positions will exit before reaching hard rupee thresholds
   - Consider widening percentage stops or disabling them when hard rupee stops are enabled

3. **Position Sizing**:
   - Ensure position sizes are large enough to generate ₹1,000+ PnL swings
   - Current positions (35 qty) generate small PnL values (~₹50-₹300 range)

### To Analyze Further

Run this query to check hard rupee stop configuration:
```ruby
config = AlgoConfig.fetch
puts "Hard Rupee SL Enabled: #{config.dig(:risk, :hard_rupee_sl, :enabled)}"
puts "Hard Rupee TP Enabled: #{config.dig(:risk, :hard_rupee_tp, :enabled)}"
```

---

## Sample Exit Data

### Recent Exits (Last 30)

| Order No             | Entry   | Exit    | Qty | PnL (₹)  | PnL (%) | Exit Reason    | Exit Path                 |
| -------------------- | ------- | ------- | --- | -------- | ------- | -------------- | ------------------------- |
| PAPER-...-1766040681 | ₹854.9  | ₹853.5  | 35  | -₹69.0   | -0.16%  | SL HIT -16.38% | stop_loss_static_downward |
| PAPER-...-1766040467 | ₹837.0  | ₹834.35 | 35  | -₹112.75 | -0.32%  | SL HIT -31.66% | stop_loss_static_downward |
| PAPER-...-1766040256 | ₹848.85 | ₹854.0  | 35  | ₹160.25  | 0.61%   | TP HIT 60.67%  | take_profit               |
| PAPER-...-1766040041 | ₹872.95 | ₹873.6  | 35  | ₹2.75    | 0.07%   | TP HIT 7.45%   | take_profit               |
| PAPER-...-1766039827 | ₹883.95 | ₹893.0  | 35  | ₹296.75  | 1.02%   | TP HIT 102.38% | take_profit               |

---

## Conclusion

**Current State:**
- Positions exit via percentage-based stops at small PnL values (₹2-₹300 range)
- Hard rupee stops (₹1,000 SL / ₹2,000 TP) are not triggering
- All exits are percentage-based, not rupee-based

**Next Steps:**
1. Verify hard rupee stops are enabled in `config/algo.yml`
2. Adjust percentage-based stops to allow positions to reach hard rupee thresholds
3. Consider increasing position sizes if hard rupee stops are desired
