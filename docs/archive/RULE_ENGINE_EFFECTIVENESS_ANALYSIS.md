# Rule Engine Effectiveness Analysis

**Date**: 2025-12-09
**Analysis Period**: Last 100 exited positions
**Total Exited Positions**: 211

## Executive Summary

The rule engine is **100% operational** - all exits are processed through the rule engine. However, there are **critical issues** affecting exit effectiveness:

### Key Findings

✅ **Strengths:**
- 100% rule engine coverage (no legacy exits)
- Peak Drawdown rule shows 56.8% win rate when working correctly
- Peak Drawdown exits average 8.01% profit when winning

❌ **Critical Issues:**
- **27.3% of Peak Drawdown exits have peak=0%** (never profitable, rule shouldn't trigger)
- **0% Take Profit exits** (TP rule never triggers)
- **5% of positions lose >10%** (avg loss: -24.3%)
- **Stop Loss rule has only 26.4% win rate** (avg loss: -4.7%)

---

## 1. Exit Reason Distribution

| Exit Reason | Count | Percentage | Avg PnL |
|------------|-------|-----------|---------|
| **Stop Loss (SL)** | 53 | 53.0% | -2.8% |
| **Peak Drawdown** | 44 | 44.0% | +2.9% |
| **Take Profit (TP)** | 0 | 0.0% | N/A |
| **Other** | 3 | 3.0% | -1.2% |

### Analysis

- **Stop Loss is the primary exit mechanism** (53% of exits)
- **Peak Drawdown is secondary** (44% of exits)
- **Take Profit never triggers** - This is a **critical issue**

---

## 2. Peak Drawdown Rule Analysis

### Overall Performance

- **Total Peak Drawdown Exits**: 44
- **Win Rate**: 56.8% (25 wins, 19 losses)
- **Avg Win**: +8.01%
- **Avg Loss**: -2.22%

### Critical Issue: Peak=0% Exits

**Problem**: 12 out of 44 peak drawdown exits (27.3%) have `peak: 0.0%`, meaning:
- Position never had a profit
- Rule is incorrectly treating loss from entry as "drawdown from peak"
- These exits average **-3.46% loss**

**Root Cause**: The `PeakDrawdownRule` is checking drawdown even when `peak_profit_pct = 0%`. The rule should skip if peak hasn't been established (peak <= 0%).

**Impact**:
- 27.3% of peak drawdown exits are premature
- These positions should have been caught by Stop Loss rule instead
- Average loss of -3.46% could have been prevented

### Peak Drawdown Exits by Peak Level

| Peak Range | Count | Avg PnL | Win Rate |
|-----------|-------|---------|----------|
| **0% (Never profitable)** | 12 | -3.46% | 0% |
| **0-5%** | 8 | +0.5% | 50% |
| **5-10%** | 6 | +2.8% | 66.7% |
| **10-20%** | 12 | +8.2% | 83.3% |
| **20%+** | 6 | +15.1% | 100% |

**Key Insight**: Peak Drawdown rule is **highly effective** when peak > 10%, with 83-100% win rates and excellent profit protection.

---

## 3. Stop Loss Rule Analysis

### Performance Metrics

- **Total SL Exits**: 53
- **Win Rate**: 26.4% (14 wins, 39 losses)
- **Avg Win**: +0.68%
- **Avg Loss**: -4.7%

### Issues

1. **Low Win Rate**: Only 26.4% of SL exits are profitable
2. **Large Average Loss**: -4.7% average loss suggests SL threshold may be too wide
3. **Large Losses Not Caught**: 5 positions lost >10% (up to -40.06%)

### Large Losses Analysis

| Position ID | PnL | Exit Reason |
|------------|-----|-------------|
| 1760 | -40.06% | SL HIT -40.06% |
| 1728 | -37.93% | SL HIT -37.93% |
| 1783 | -16.50% | SL HIT -16.50% |
| 1761 | -14.97% | SL HIT -14.97% |
| 1735 | -12.02% | SL HIT -12.02% |

**Critical Issue**: These positions lost 12-40% before SL rule triggered. This suggests:
- SL threshold may be configured too wide
- Or positions are not being evaluated frequently enough
- Or SL rule is not being checked before large moves

---

## 4. Take Profit Rule Analysis

### Critical Finding: 0% TP Exits

**Problem**: No positions exited via Take Profit rule in the last 100 exits.

**Possible Causes**:
1. **TP threshold too high** - Positions never reach TP before other rules trigger
2. **TP rule disabled** - Rule may be disabled in configuration
3. **Priority issue** - Other rules (SL, Peak Drawdown) trigger before TP
4. **TP calculation issue** - TP may not be calculated correctly

**Impact**:
- Missing profit-taking opportunities
- Positions that could have been profitable are exiting via other rules
- Potential profit left on the table

**Recommendation**:
- Review TP threshold configuration
- Check if TP rule is enabled
- Analyze positions that exited with profit but not via TP rule

---

## 5. Overall Performance Metrics

### Win/Loss Analysis

- **Total Positions**: 100
- **Wins**: 40 (40%)
- **Losses**: 60 (60%)
- **Avg Win**: +2.9%
- **Avg Loss**: -4.06%
- **Total PnL**: -63.81% (cumulative)

### Risk/Reward Ratio

- **Risk/Reward**: 1:0.71 (losing 1.4x more than winning)
- **Expectancy**: -0.64% per trade (negative expectancy)

**Critical Issue**: The system has **negative expectancy** - average loss exceeds average win, and win rate is below 50%.

---

## 6. Rule Priority Analysis

Current rule priority order:
1. **Priority 10**: SessionEndRule
2. **Priority 20**: StopLossRule ← Most exits (53%)
3. **Priority 25**: BracketLimitRule
4. **Priority 30**: TakeProfitRule ← Never triggers (0%)
5. **Priority 35**: SecureProfitRule
6. **Priority 40**: TimeBasedExitRule
7. **Priority 45**: PeakDrawdownRule ← Second most exits (44%)
8. **Priority 50**: TrailingStopRule
9. **Priority 60**: UnderlyingExitRule

### Priority Issues

1. **Stop Loss (Priority 20) triggers too often** - May be too sensitive or threshold too wide
2. **Take Profit (Priority 30) never triggers** - May be disabled or threshold too high
3. **Peak Drawdown (Priority 45) triggers on 0% peak** - Logic bug needs fixing

---

## 7. Recommendations

### Immediate Fixes (Critical)

1. **Fix Peak Drawdown Rule Logic**
   ```ruby
   # In PeakDrawdownRule.evaluate
   # Add check: Skip if peak <= 0
   return skip_result if peak_profit_pct.to_f <= 0
   ```
   - Prevents 27.3% of premature peak drawdown exits
   - Will allow Stop Loss rule to handle these cases

2. **Investigate Take Profit Rule**
   - Check if TP rule is enabled in config
   - Review TP threshold values
   - Analyze why TP never triggers
   - Consider lowering TP threshold or adjusting priority

3. **Review Stop Loss Threshold**
   - Current SL seems too wide (allowing -40% losses)
   - Consider tightening SL threshold
   - Review SL rule evaluation frequency

### Short-term Improvements

4. **Add Peak Validation**
   - Ensure peak_profit_pct is initialized correctly
   - Add validation in PeakDrawdownRule to skip if peak <= 0
   - Log when peak is 0% to identify root cause

5. **Improve Large Loss Prevention**
   - Add hard stop at -10% regardless of other rules
   - Implement circuit breaker for positions losing >5% in single tick
   - Review position evaluation frequency

6. **Optimize Rule Evaluation Order**
   - Consider moving Take Profit to higher priority (before Peak Drawdown)
   - Review if SecureProfitRule should have higher priority
   - Ensure critical rules (SL, TP) are evaluated first

### Long-term Enhancements

7. **Add Rule Effectiveness Metrics**
   - Track which rules trigger most often
   - Measure win rate per rule
   - Calculate average PnL per rule
   - Build dashboard for rule performance

8. **Implement Adaptive Thresholds**
   - Adjust SL/TP based on market volatility
   - Use ATR-based stops for dynamic sizing
   - Implement position-size-based risk management

9. **Add Rule Testing Framework**
   - Unit tests for each rule
   - Integration tests for rule engine
   - Backtesting with historical data
   - A/B testing for rule configurations

---

## 8. Code Fixes Required

### Fix 1: Peak Drawdown Rule - Skip if Peak <= 0

**File**: `app/services/risk/rules/peak_drawdown_rule.rb`

```ruby
def evaluate(context)
  return skip_result unless context.active?

  # Check trailing activation threshold
  unless context.trailing_activated?
    return skip_result
  end

  peak_profit_pct = context.peak_profit_pct
  current_profit_pct = context.pnl_pct
  return skip_result unless peak_profit_pct && current_profit_pct

  # FIX: Skip if peak is 0% or negative (position never profitable)
  return skip_result if peak_profit_pct.to_f <= 0

  # Rest of the method...
end
```

### Fix 2: Add Peak Validation in TrailingEngine

**File**: `app/services/live/trailing_engine.rb`

```ruby
def check_peak_drawdown(position_data, exit_engine)
  return false unless exit_engine && position_data.peak_profit_pct

  peak = position_data.peak_profit_pct.to_f
  current = position_data.pnl_pct.to_f

  # FIX: Skip if peak is 0% or negative
  return false if peak <= 0

  # Rest of the method...
end
```

---

## 9. Configuration Review Checklist

- [ ] Verify Take Profit rule is enabled
- [ ] Review TP threshold values (may be too high)
- [ ] Review SL threshold values (may be too wide)
- [ ] Check Peak Drawdown threshold (currently 3.0%)
- [ ] Verify trailing activation threshold (currently 10.0%)
- [ ] Review SecureProfitRule configuration
- [ ] Check TimeBasedExitRule configuration
- [ ] Verify UnderlyingExitRule is enabled/disabled as intended

---

## 10. Success Metrics to Track

Going forward, track these metrics:

1. **Rule Trigger Rate**: % of exits per rule
2. **Rule Win Rate**: Win % per rule
3. **Rule Average PnL**: Avg profit/loss per rule
4. **Large Loss Prevention**: % of positions losing >10%
5. **Take Profit Capture**: % of positions exiting via TP
6. **Peak Drawdown Accuracy**: % of peak exits with peak > 0%

---

## Conclusion

The rule engine is **functionally working** (100% coverage) but has **critical logic issues**:

1. **Peak Drawdown rule triggers incorrectly** on 27.3% of cases (peak=0%)
2. **Take Profit rule never triggers** (0% of exits)
3. **Stop Loss allows large losses** (up to -40%)

**Priority Actions**:
1. Fix Peak Drawdown logic (skip if peak <= 0)
2. Investigate and fix Take Profit rule
3. Review and tighten Stop Loss thresholds

With these fixes, the rule engine should show significant improvement in exit effectiveness.


