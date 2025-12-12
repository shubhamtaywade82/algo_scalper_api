# Testing Guide for Adaptive Exit System

## Overview

This guide provides a step-by-step approach for algo traders to test the new adaptive exit system, bidirectional trailing stops, and path tracking features.

---

## Quick Start (5-Minute Checklist)

**Before Starting Trading**:
```bash
# 1. Run unit tests
bundle exec rspec spec/lib/positions/ spec/services/live/early_trend_failure* spec/integration/adaptive_exit*

# 2. Simulate drawdowns
rake drawdown:simulate

# 3. Verify config
cat config/algo.yml | grep -A 3 "paper_trading"
cat config/algo.yml | grep -A 5 "drawdown:"
cat config/algo.yml | grep -A 5 "reverse_loss:"
```

**During Paper Trading**:
```ruby
# In Rails console - Quick checks
# Entry tracking
TradingSignal.group("metadata->>'entry_path'").count

# Exit tracking  
PositionTracker.exited.group("meta->>'exit_path'").count

# Active positions
PositionTracker.active.count

# Recent exits
PositionTracker.exited.order(exited_at: :desc).limit(5).pluck(:order_no, "meta->>'exit_path'", :last_pnl_rupees)
```

**After Trading Session**:
```ruby
# Performance summary
PositionTracker.exited.group("meta->>'exit_path'")
  .select("meta->>'exit_path' as path", "COUNT(*) as count", "AVG(last_pnl_rupees) as avg_pnl")
  .each { |r| puts "#{r.path}: #{r.count} exits, Avg PnL: ₹#{r.avg_pnl.round(2)}" }
```

---

## Phase 1: Pre-Testing Setup

### 1.1 Verify Configuration

**Check `config/algo.yml`**:
```bash
# Ensure paper trading is enabled
cat config/algo.yml | grep -A 3 "paper_trading"

# Verify risk parameters are set
cat config/algo.yml | grep -A 20 "risk:"
```

**Expected Settings**:
```yaml
paper_trading:
  enabled: true
  balance: 100000

risk:
  sl_pct: 0.03
  tp_pct: 0.05
  drawdown:
    activation_profit_pct: 3.0
    # ... other settings
  reverse_loss:
    enabled: true
    # ... other settings
  etf:
    enabled: true
    # ... other settings
```

### 1.2 Run Unit Tests

**Verify all calculations work correctly**:
```bash
# Run all adaptive exit tests
bundle exec rspec spec/lib/positions/drawdown_schedule_spec.rb
bundle exec rspec spec/lib/positions/drawdown_schedule_config_spec.rb
bundle exec rspec spec/services/live/early_trend_failure_spec.rb
bundle exec rspec spec/services/live/early_trend_failure_config_spec.rb
bundle exec rspec spec/services/live/risk_manager_service_trailing_spec.rb
bundle exec rspec spec/integration/adaptive_exit_integration_spec.rb
```

**Expected**: All tests pass ✅

### 1.3 Simulate Drawdown Calculations

**Understand how the system will behave**:
```bash
rake drawdown:simulate
```

**Review Output**:
- Upward drawdown schedule (how much drawdown is allowed at each profit level)
- Reverse SL schedule (how much loss is allowed at each loss level)
- Time-based tightening effects
- ATR penalty effects

**Take Notes**: Write down expected behaviors for later validation.

---

## Phase 2: Paper Trading Testing

### 2.1 Start Paper Trading Session

**Start the trading system**:
```bash
# Start Rails console or trading service
bin/rails console

# Or start the full trading system
bin/dev
```

**Monitor Logs**:
```bash
# Watch logs in real-time
tail -f log/development.log | grep -E "RiskManager|Signal|Entry|Exit"
```

### 2.2 Monitor Entry Path Tracking

**Verify entries are being tracked**:
```ruby
# In Rails console
# Check recent entries
TradingSignal.order(created_at: :desc).limit(10).each do |signal|
  puts "Entry: #{signal.index_key} | Path: #{signal.metadata['entry_path']} | Strategy: #{signal.metadata['strategy']}"
end

# Count entries by path
TradingSignal.group("metadata->>'entry_path'").count
# Expected: {"supertrend_adx_1m_none" => X, ...}
```

**What to Verify**:
- ✅ `entry_path` is populated (format: `"strategy_timeframe_confirmation"`)
- ✅ `strategy` field matches expected strategy
- ✅ `timeframe` matches config

### 2.3 Monitor Exit Path Tracking

**Verify exits are being tracked**:
```ruby
# In Rails console
# Check recent exits
PositionTracker.exited.order(exited_at: :desc).limit(10).each do |tracker|
  puts "Exit: #{tracker.order_no} | Path: #{tracker.meta['exit_path']} | PnL: ₹#{tracker.last_pnl_rupees.round(2)} (#{tracker.last_pnl_pct.round(2)}%)"
end

# Count exits by path
PositionTracker.exited.group("meta->>'exit_path'").count
# Expected: {"trailing_stop_adaptive_upward" => X, "stop_loss_adaptive_downward" => Y, ...}
```

**What to Verify**:
- ✅ `exit_path` is populated for all exits
- ✅ `exit_direction` is set (upward/downward)
- ✅ `exit_type` is set (adaptive/fixed)
- ✅ `exit_reason` contains human-readable reason

### 2.4 Test Early Trend Failure (ETF)

**Trigger Conditions**:
- Enter a position
- Wait for profit < 7%
- Monitor for ETF triggers

**Monitor Logs**:
```bash
tail -f log/development.log | grep -i "early_trend_failure\|ETF"
```

**Verify in Console**:
```ruby
# Check if any ETF exits occurred
PositionTracker.exited.where("meta->>'exit_path' = ?", "early_trend_failure").count

# Review ETF exit details
PositionTracker.exited.where("meta->>'exit_path' = ?", "early_trend_failure").each do |t|
  puts "ETF Exit: #{t.order_no} | PnL: #{t.last_pnl_pct.round(2)}% | Reason: #{t.meta['exit_reason']}"
end
```

**What to Verify**:
- ✅ ETF triggers when profit < 7% AND trend conditions fail
- ✅ ETF doesn't trigger when profit ≥ 7% (trailing takes over)
- ✅ ETF logs show which condition triggered (trend collapse, ADX, ATR, VWAP)

### 2.5 Test Upward Trailing (Adaptive Drawdown)

**Trigger Conditions**:
- Enter a position
- Wait for profit ≥ 3% (activation threshold)
- Let profit increase (e.g., to 10%)
- Monitor drawdown behavior

**Monitor Logs**:
```bash
tail -f log/development.log | grep -i "trailing_stop\|ADAPTIVE_TRAILING"
```

**Verify in Console**:
```ruby
# Check upward trailing exits
upward_exits = PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%upward%")
puts "Upward Trailing Exits: #{upward_exits.count}"

# Analyze drawdown behavior
upward_exits.each do |t|
  peak_profit = t.meta['peak_profit_pct'] || t.high_water_mark_pnl
  current_profit = t.last_pnl_pct
  drawdown = peak_profit - current_profit if peak_profit && current_profit
  puts "Exit: #{t.order_no} | Peak: #{peak_profit.round(2)}% | Exit: #{current_profit.round(2)}% | Drawdown: #{drawdown.round(2)}%"
end
```

**What to Verify**:
- ✅ Trailing activates only when profit ≥ 3%
- ✅ Drawdown allowed decreases as profit increases (exponential curve)
- ✅ Exits occur when drawdown exceeds allowed threshold
- ✅ Index-specific floors are respected (NIFTY 1.0%, BANKNIFTY 1.2%, SENSEX 1.5%)

**Manual Calculation Check**:
```ruby
# In Rails console
include Positions::DrawdownSchedule

# For a position that exited at 10% profit
profit = 10.0
allowed_dd = allowed_upward_drawdown_pct(profit, index_key: 'NIFTY')
puts "At #{profit}% profit, allowed drawdown: #{allowed_dd.round(2)}%"

# Verify the exit was within allowed drawdown
# (Check logs or PositionTracker.meta for peak_profit and exit_profit)
```

### 2.6 Test Downward Trailing (Reverse SL)

**Trigger Conditions**:
- Enter a position
- Position goes below entry (negative PnL)
- Monitor reverse SL behavior

**Monitor Logs**:
```bash
tail -f log/development.log | grep -i "stop_loss.*downward\|REVERSE\|below_entry"
```

**Verify in Console**:
```ruby
# Check downward trailing exits
downward_exits = PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%downward%")
puts "Downward Trailing Exits: #{downward_exits.count}"

# Analyze reverse SL behavior
downward_exits.each do |t|
  loss_pct = t.last_pnl_pct.abs
  seconds_below = t.meta['seconds_below_entry'] || 0
  puts "Exit: #{t.order_no} | Loss: #{loss_pct.round(2)}% | Time Below Entry: #{seconds_below}s"
end
```

**What to Verify**:
- ✅ Reverse SL tightens as loss deepens (20% → 5%)
- ✅ Time-based tightening applies (-2% per minute)
- ✅ ATR penalties apply for low volatility
- ✅ Exits occur when loss exceeds allowed threshold

**Manual Calculation Check**:
```ruby
# In Rails console
include Positions::DrawdownSchedule

# For a position that exited at -10% loss
loss = -10.0
seconds_below = 120  # 2 minutes
atr_ratio = 0.75
allowed_loss = reverse_dynamic_sl_pct(loss, seconds_below_entry: seconds_below, atr_ratio: atr_ratio)
puts "At #{loss.abs}% loss, #{seconds_below}s below entry, ATR #{atr_ratio}: allowed loss: #{allowed_loss.round(2)}%"
```

### 2.7 Test Breakeven Locking

**Trigger Conditions**:
- Enter a position
- Reach +5% profit
- Verify breakeven is locked (no exit, just protection)

**Monitor Logs**:
```bash
tail -f log/development.log | grep -i "breakeven\|BREAKEVEN_LOCK"
```

**Verify in Console**:
```ruby
# Check if breakeven locking is working
# (Breakeven lock doesn't cause exit, but protects from going negative)
# Look for positions that reached +5% and then dropped but didn't exit until other conditions

active_positions = PositionTracker.active
active_positions.each do |t|
  snapshot = Live::RiskManagerService.new.send(:pnl_snapshot, t)
  if snapshot && snapshot[:pnl_pct] && snapshot[:pnl_pct] > 0.05
    puts "Position #{t.order_no}: Profit #{snapshot[:pnl_pct].round(2)}% - Breakeven should be locked"
  end
end
```

**What to Verify**:
- ✅ Breakeven locks at +5% profit
- ✅ Positions don't exit below entry once breakeven is locked
- ✅ Logs show breakeven lock status

---

## Phase 3: Analysis & Validation

### 3.1 Entry Path Analysis

**Compare Different Entry Paths**:
```ruby
# Count entries by path
entry_counts = TradingSignal.group("metadata->>'entry_path'").count
puts "Entry Path Distribution:"
entry_counts.each { |path, count| puts "  #{path}: #{count}" }

# Performance by entry path
TradingSignal.joins("LEFT JOIN position_trackers ON position_trackers.meta->>'index_key' = trading_signals.index_key AND position_trackers.status = 'exited'")
  .where("position_trackers.id IS NOT NULL")
  .group("trading_signals.metadata->>'entry_path'")
  .select(
    "trading_signals.metadata->>'entry_path' as entry_path",
    "COUNT(*) as count",
    "AVG(position_trackers.last_pnl_rupees) as avg_pnl",
    "AVG(position_trackers.last_pnl_pct) as avg_pnl_pct",
    "SUM(CASE WHEN position_trackers.last_pnl_rupees > 0 THEN 1 ELSE 0 END)::float / COUNT(*) * 100 as win_rate"
  )
  .each do |r|
    puts "#{r.entry_path}: Count=#{r.count}, Avg PnL=₹#{r.avg_pnl.round(2)}, Win Rate=#{r.win_rate.round(2)}%"
  end
```

**What to Look For**:
- Which entry paths are most common?
- Which entry paths have best performance?
- Are there any paths that consistently underperform?

### 3.2 Exit Path Analysis

**Compare Different Exit Paths**:
```ruby
# Count exits by path
exit_counts = PositionTracker.exited.group("meta->>'exit_path'").count
puts "Exit Path Distribution:"
exit_counts.each { |path, count| puts "  #{path}: #{count}" }

# Performance by exit path
PositionTracker.exited.group("meta->>'exit_path'")
  .select(
    "meta->>'exit_path' as exit_path",
    "COUNT(*) as count",
    "AVG(last_pnl_rupees) as avg_pnl",
    "AVG(last_pnl_pct) as avg_pnl_pct",
    "SUM(CASE WHEN last_pnl_rupees > 0 THEN 1 ELSE 0 END)::float / COUNT(*) * 100 as win_rate"
  )
  .each do |r|
    puts "#{r.exit_path}: Count=#{r.count}, Avg PnL=₹#{r.avg_pnl.round(2)}, Win Rate=#{r.win_rate.round(2)}%"
  end
```

**What to Look For**:
- Which exit paths are most common?
- Are adaptive exits working better than fixed exits?
- Is upward trailing protecting profits effectively?
- Is downward trailing limiting losses effectively?

### 3.3 Bidirectional Trailing Analysis

**Compare Upward vs Downward Trailing**:
```ruby
# Upward trailing (profit protection)
upward = PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%upward%")
puts "Upward Trailing:"
puts "  Count: #{upward.count}"
puts "  Avg PnL: ₹#{upward.average('last_pnl_rupees').round(2)}"
puts "  Avg Profit %: #{upward.average('last_pnl_pct').round(2)}%"
puts "  Win Rate: #{(upward.where('last_pnl_rupees > 0').count.to_f / upward.count * 100).round(2)}%" if upward.count > 0

# Downward trailing (loss limitation)
downward = PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%downward%")
puts "\nDownward Trailing:"
puts "  Count: #{downward.count}"
puts "  Avg PnL: ₹#{downward.average('last_pnl_rupees').round(2)}"
puts "  Avg Loss %: #{downward.average('last_pnl_pct').round(2)}%"
puts "  Avg Loss: ₹#{downward.average('last_pnl_rupees').round(2)}" if downward.count > 0
```

**What to Look For**:
- Is upward trailing protecting profits? (should see positive avg PnL)
- Is downward trailing limiting losses? (should see smaller losses than static SL)
- Are both mechanisms working as expected?

### 3.4 Complete Strategy Performance Report

**Full Analysis: Entry Strategy → Exit Path → Performance**:
```ruby
# Full analysis query
results = TradingSignal.joins("LEFT JOIN position_trackers ON position_trackers.meta->>'index_key' = trading_signals.index_key AND position_trackers.status = 'exited'")
  .where("position_trackers.id IS NOT NULL")
  .group("trading_signals.metadata->>'strategy'", "position_trackers.meta->>'exit_path'")
  .select(
    "trading_signals.metadata->>'strategy' as strategy",
    "position_trackers.meta->>'exit_path' as exit_path",
    "COUNT(*) as count",
    "AVG(position_trackers.last_pnl_rupees) as avg_pnl",
    "AVG(position_trackers.last_pnl_pct) as avg_pnl_pct",
    "SUM(CASE WHEN position_trackers.last_pnl_rupees > 0 THEN 1 ELSE 0 END)::float / COUNT(*) * 100 as win_rate"
  )
  .order("strategy", "exit_path")

puts "Strategy → Exit Path Performance:"
results.each do |r|
  puts "  #{r.strategy} → #{r.exit_path}: Count=#{r.count}, Avg PnL=₹#{r.avg_pnl.round(2)}, Win Rate=#{r.win_rate.round(2)}%"
end
```

**What to Look For**:
- Which strategy + exit path combinations work best?
- Are there any combinations that consistently lose?
- Is path tracking helping identify patterns?

---

## Phase 4: Validation Checklist

### 4.1 Entry Path Tracking ✅

- [ ] All entries have `entry_path` populated
- [ ] Entry paths match expected format (`strategy_timeframe_confirmation`)
- [ ] Strategy field matches actual strategy used
- [ ] Timeframe field matches config

### 4.2 Exit Path Tracking ✅

- [ ] All exits have `exit_path` populated
- [ ] Exit paths match expected format (`type_direction` or `type`)
- [ ] `exit_direction` is set (upward/downward)
- [ ] `exit_type` is set (adaptive/fixed)
- [ ] `exit_reason` contains readable reason

### 4.3 Early Trend Failure ✅

- [ ] ETF triggers when profit < 7% AND conditions met
- [ ] ETF doesn't trigger when profit ≥ 7%
- [ ] ETF logs show which condition triggered
- [ ] ETF exits are tracked correctly

### 4.4 Upward Trailing ✅

- [ ] Trailing activates only when profit ≥ 3%
- [ ] Drawdown allowed decreases as profit increases
- [ ] Exits occur when drawdown exceeds allowed threshold
- [ ] Index-specific floors are respected
- [ ] Breakeven locks at +5%

### 4.5 Downward Trailing ✅

- [ ] Reverse SL tightens as loss deepens (20% → 5%)
- [ ] Time-based tightening applies (-2% per minute)
- [ ] ATR penalties apply for low volatility
- [ ] Exits occur when loss exceeds allowed threshold

### 4.6 Performance Validation ✅

- [ ] Upward trailing shows positive avg PnL
- [ ] Downward trailing shows smaller losses than static SL
- [ ] Overall system performance is acceptable
- [ ] No unexpected exits or behaviors

---

## Phase 5: Gradual Rollout

### 5.1 Small Capital Test (10-20% Allocation)

**Before Live Trading**:
1. Reduce capital allocation in `config/algo.yml`:
   ```yaml
   indices:
     - {
         key: NIFTY,
         capital_alloc_pct: 0.10,  # Reduced from 0.30
         # ...
       }
   ```

2. Enable live trading (disable paper trading):
   ```yaml
   paper_trading:
     enabled: false
   ```

3. Monitor for 1-2 trading days

**What to Monitor**:
- Entry/exit path tracking
- Actual PnL vs expected
- Log errors or unexpected behaviors
- System stability

### 5.2 Full Capital Rollout

**After Small Capital Validation**:
1. Restore full capital allocation
2. Continue monitoring
3. Run analysis queries daily
4. Adjust config if needed

---

## Phase 6: Ongoing Monitoring

### 6.1 Daily Checks

**Run Analysis Queries**:
```ruby
# Daily performance summary
puts "=== Daily Performance Summary ==="
puts "Date: #{Date.today}"

# Entry paths
entry_counts = TradingSignal.where("created_at >= ?", Date.today.beginning_of_day)
  .group("metadata->>'entry_path'").count
puts "\nEntry Paths:"
entry_counts.each { |path, count| puts "  #{path}: #{count}" }

# Exit paths
exit_counts = PositionTracker.exited.where("exited_at >= ?", Date.today.beginning_of_day)
  .group("meta->>'exit_path'").count
puts "\nExit Paths:"
exit_counts.each { |path, count| puts "  #{path}: #{count}" }

# Overall PnL
total_pnl = PositionTracker.exited.where("exited_at >= ?", Date.today.beginning_of_day)
  .sum(:last_pnl_rupees)
puts "\nTotal PnL: ₹#{total_pnl.round(2)}"
```

### 6.2 Weekly Analysis

**Run Complete Performance Report** (see Phase 3.4)

**Review**:
- Which strategies are performing best?
- Which exit paths are most effective?
- Are there any patterns or anomalies?
- Should config be adjusted?

### 6.3 Monthly Review

**Comprehensive Analysis**:
- Full strategy performance report
- Bidirectional trailing effectiveness
- Entry/exit path optimization
- Config tuning based on results

---

## Troubleshooting

### Issue: Entry paths not being tracked

**Check**:
```ruby
# Verify Signal::Engine is creating paths
TradingSignal.last.metadata
# Should contain 'entry_path' field

# Check if build_entry_path_identifier is being called
# Review logs for errors in Signal::Engine
```

**Fix**: Ensure `Signal::Engine.build_entry_path_identifier()` is being called in `run_for()` method.

### Issue: Exit paths not being tracked

**Check**:
```ruby
# Verify RiskManagerService is tracking paths
PositionTracker.exited.last.meta
# Should contain 'exit_path' field

# Check if track_exit_path is being called
# Review logs for errors in RiskManagerService
```

**Fix**: Ensure `track_exit_path()` is called in all exit enforcement methods.

### Issue: Trailing not activating

**Check**:
```ruby
# Verify profit threshold
PositionTracker.active.each do |t|
  snapshot = Live::RiskManagerService.new.send(:pnl_snapshot, t)
  puts "Position #{t.order_no}: PnL #{snapshot[:pnl_pct] * 100}%"
end

# Check config
AlgoConfig.fetch[:risk][:drawdown][:activation_profit_pct]
```

**Fix**: Ensure profit ≥ activation threshold (default 3%).

### Issue: Reverse SL not tightening

**Check**:
```ruby
# Verify reverse_loss config is enabled
AlgoConfig.fetch[:risk][:reverse_loss][:enabled]
# Should be true

# Check if position is below entry
PositionTracker.active.each do |t|
  snapshot = Live::RiskManagerService.new.send(:pnl_snapshot, t)
  puts "Position #{t.order_no}: PnL #{snapshot[:pnl_pct] * 100}%"
end
```

**Fix**: Ensure `reverse_loss.enabled` is `true` in config.

---

## Quick Reference Commands

```ruby
# Check recent entries
TradingSignal.order(created_at: :desc).limit(10).pluck(:index_key, "metadata->>'entry_path'")

# Check recent exits
PositionTracker.exited.order(exited_at: :desc).limit(10).pluck(:order_no, "meta->>'exit_path'", :last_pnl_rupees)

# Count by entry path
TradingSignal.group("metadata->>'entry_path'").count

# Count by exit path
PositionTracker.exited.group("meta->>'exit_path'").count

# Check active positions
PositionTracker.active.count

# Check system health
Live::RiskManagerService.instance.running?
```

---

## Next Steps

After successful testing:

1. **Document Learnings**: Record what worked well and what didn't
2. **Optimize Config**: Adjust parameters based on results
3. **Refine Strategies**: Improve entry/exit paths based on analysis
4. **Scale Up**: Gradually increase capital allocation
5. **Continuous Monitoring**: Keep analyzing and improving

---

## Support

If you encounter issues:
1. Check logs: `tail -f log/development.log`
2. Review config: `config/algo.yml`
3. Run tests: `bundle exec rspec spec/`
4. Check documentation: `docs/TRADING_SYSTEM_GUIDE.md`
