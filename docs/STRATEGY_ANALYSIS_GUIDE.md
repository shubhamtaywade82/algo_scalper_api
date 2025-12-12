# Strategy Analysis Guide - KISS with Advanced Features

## Overview

With clear path tracking, analyzing different strategies and exit paths is now **simple and straightforward**.

---

## Entry Path Analysis

### Track Which Strategy Executed

Every entry is tracked with clear path identifier:

```ruby
# Entry path format: "strategy_timeframe_confirmation"
# Examples:
# - "recommended_5m_none" (strategy recommendations, 5m, no confirmation)
# - "supertrend_adx_1m_none" (Supertrend+ADX, 1m, no confirmation)
# - "supertrend_adx_5m_5m" (Supertrend+ADX, 5m primary, 5m confirmation)
```

### Query Entry Performance

```ruby
# All entries by strategy
TradingSignal.group("metadata->>'strategy'").count
# => { "supertrend_adx" => 50, "simple_momentum" => 30, "inside_bar" => 20 }

# All entries by path
TradingSignal.group("metadata->>'entry_path'").count
# => { "supertrend_adx_1m_none" => 30, "supertrend_adx_5m_5m" => 20, "recommended_5m_none" => 10 }

# Performance by strategy
TradingSignal.joins("LEFT JOIN position_trackers ON position_trackers.meta->>'index_key' = trading_signals.index_key")
  .where("position_trackers.status = 'exited'")
  .group("trading_signals.metadata->>'strategy'")
  .average("position_trackers.last_pnl_rupees")

# Performance by entry path
TradingSignal.joins("LEFT JOIN position_trackers ON position_trackers.meta->>'index_key' = trading_signals.index_key")
  .where("position_trackers.status = 'exited'")
  .group("trading_signals.metadata->>'entry_path'")
  .average("position_trackers.last_pnl_rupees")
```

---

## Exit Path Analysis

### Track Which Exit Path Executed

Every exit is tracked with clear path identifier:

```ruby
# Exit path format: "type_direction"
# Examples:
# - "trailing_stop_adaptive_upward" (adaptive trailing, upward/profit protection)
# - "stop_loss_adaptive_downward" (adaptive reverse SL, downward/loss limitation)
# - "stop_loss_static_downward" (static SL, downward)
# - "take_profit" (take profit)
# - "early_trend_failure" (early exit)
# - "time_based" (time-based exit)
```

### Query Exit Performance

```ruby
# All exits by path
PositionTracker.exited.group("meta->>'exit_path'").count
# => { 
#   "trailing_stop_adaptive_upward" => 20,
#   "stop_loss_adaptive_downward" => 10,
#   "take_profit" => 15,
#   "early_trend_failure" => 5
# }

# Performance by exit path
PositionTracker.exited.group("meta->>'exit_path'")
  .average("last_pnl_rupees")

# Win rate by exit path
PositionTracker.exited.group("meta->>'exit_path'")
  .average("CASE WHEN last_pnl_rupees > 0 THEN 1 ELSE 0 END")

# Average PnL by exit path
PositionTracker.exited.group("meta->>'exit_path'")
  .pluck("meta->>'exit_path'", "AVG(last_pnl_rupees)", "COUNT(*)")
```

---

## Bidirectional Trailing Analysis

### Compare Upward vs Downward Trailing

```ruby
# Upward trailing exits (profit protection)
upward_exits = PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%upward%")
upward_avg_pnl = upward_exits.average("last_pnl_rupees")
upward_count = upward_exits.count

# Downward trailing exits (loss limitation via reverse SL)
downward_exits = PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%downward%")
downward_avg_pnl = downward_exits.average("last_pnl_rupees")
downward_count = downward_exits.count

# Compare
puts "Upward Trailing: #{upward_count} exits, Avg PnL: ₹#{upward_avg_pnl.round(2)}"
puts "Downward Trailing: #{downward_count} exits, Avg PnL: ₹#{downward_avg_pnl.round(2)}"
```

### Compare Adaptive vs Fixed Trailing

```ruby
# Adaptive trailing
adaptive = PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%adaptive%")
adaptive_avg_pnl = adaptive.average("last_pnl_rupees")

# Fixed trailing
fixed = PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%fixed%")
fixed_avg_pnl = fixed.average("last_pnl_rupees")
```

---

## Strategy Comparison

### Compare Multiple Strategies

```ruby
# Get all strategies
strategies = TradingSignal.distinct.pluck("metadata->>'strategy'")

strategies.each do |strategy|
  signals = TradingSignal.where("metadata->>'strategy' = ?", strategy)
  entries = signals.count
  
  # Get associated positions
  positions = PositionTracker.joins("INNER JOIN trading_signals ON trading_signals.index_key = position_trackers.meta->>'index_key'")
    .where("trading_signals.metadata->>'strategy' = ?", strategy)
    .exited
  
  avg_pnl = positions.average("last_pnl_rupees")
  win_rate = positions.where("last_pnl_rupees > 0").count.to_f / positions.count * 100
  
  puts "#{strategy}:"
  puts "  Entries: #{entries}"
  puts "  Exits: #{positions.count}"
  puts "  Avg PnL: ₹#{avg_pnl.round(2)}"
  puts "  Win Rate: #{win_rate.round(2)}%"
end
```

### Compare Entry Paths

```ruby
# Compare different entry configurations
paths = [
  "supertrend_adx_1m_none",
  "supertrend_adx_5m_none",
  "supertrend_adx_5m_5m",
  "recommended_5m_none"
]

paths.each do |path|
  signals = TradingSignal.where("metadata->>'entry_path' = ?", path)
  positions = PositionTracker.joins("INNER JOIN trading_signals ON trading_signals.index_key = position_trackers.meta->>'index_key'")
    .where("trading_signals.metadata->>'entry_path' = ?", path)
    .exited
  
  puts "#{path}:"
  puts "  Entries: #{signals.count}"
  puts "  Exits: #{positions.count}"
  puts "  Avg PnL: ₹#{positions.average('last_pnl_rupees').round(2)}"
end
```

---

## Exit Path Comparison

### Compare All Exit Paths

```ruby
# Get all exit paths
exit_paths = PositionTracker.exited.distinct.pluck("meta->>'exit_path'").compact

exit_paths.each do |path|
  exits = PositionTracker.exited.where("meta->>'exit_path' = ?", path)
  
  avg_pnl = exits.average("last_pnl_rupees")
  avg_pnl_pct = exits.average("last_pnl_pct")
  win_rate = exits.where("last_pnl_rupees > 0").count.to_f / exits.count * 100
  count = exits.count
  
  puts "#{path}:"
  puts "  Count: #{count}"
  puts "  Avg PnL: ₹#{avg_pnl.round(2)} (#{avg_pnl_pct.round(2)}%)"
  puts "  Win Rate: #{win_rate.round(2)}%"
end
```

### Compare Bidirectional Trailing Performance

```ruby
# Upward trailing (profit protection)
upward = PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%upward%")
puts "Upward Trailing:"
puts "  Count: #{upward.count}"
puts "  Avg PnL: ₹#{upward.average('last_pnl_rupees').round(2)}"
puts "  Avg Profit %: #{upward.average('last_pnl_pct').round(2)}%"

# Downward trailing (loss limitation)
downward = PositionTracker.exited.where("meta->>'exit_path' LIKE ?", "%downward%")
puts "Downward Trailing:"
puts "  Count: #{downward.count}"
puts "  Avg PnL: ₹#{downward.average('last_pnl_rupees').round(2)}"
puts "  Avg Loss %: #{downward.average('last_pnl_pct').round(2)}%"
```

---

## Complete Analysis Query

### Full Strategy Performance Report

```ruby
# Complete analysis: Entry strategy → Exit path → Performance
TradingSignal.joins("LEFT JOIN position_trackers ON position_trackers.meta->>'index_key' = trading_signals.index_key AND position_trackers.status = 'exited'")
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
```

---

## Key Benefits

1. ✅ **Clear Tracking**: Know exactly which path executed
2. ✅ **Easy Analysis**: Simple SQL queries
3. ✅ **Compare Strategies**: Easy to compare performance
4. ✅ **Compare Exit Paths**: Easy to see which exits work best
5. ✅ **Bidirectional Analysis**: Compare upward vs downward trailing
6. ✅ **Maintain Features**: Keep all advanced features

---

## Example Analysis Output

```
Strategy: supertrend_adx
  Entry Path: supertrend_adx_1m_none
    Exits: 30
    Avg PnL: ₹250.50 (5.2%)
    Win Rate: 60%
    Exit Paths:
      - trailing_stop_adaptive_upward: 15 exits, Avg: ₹350.00
      - take_profit: 10 exits, Avg: ₹500.00
      - stop_loss_adaptive_downward: 5 exits, Avg: -₹150.00

  Entry Path: supertrend_adx_5m_5m
    Exits: 20
    Avg PnL: ₹180.30 (3.6%)
    Win Rate: 65%
    Exit Paths:
      - trailing_stop_adaptive_upward: 12 exits, Avg: ₹280.00
      - take_profit: 5 exits, Avg: ₹500.00
      - early_trend_failure: 3 exits, Avg: -₹50.00
```

This makes it **easy to see**:
- Which strategy performs best
- Which entry path performs best
- Which exit path performs best
- How bidirectional trailing performs
