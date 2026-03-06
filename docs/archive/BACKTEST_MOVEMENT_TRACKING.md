# Backtest Movement Tracking

**Date**: 2025-01-06
**Purpose**: Track underlying price movement and time elapsed after No-Trade Engine allows signals

---

## Overview

The No-Trade Engine backtester now tracks:
1. **Underlying Movement**: How much the underlying moved in the signal direction after entry
2. **Time Elapsed**: How much time passed from entry to exit

These metrics help evaluate the quality of signals that pass No-Trade Engine validation.

---

## Metrics Added

### Per Trade Metrics

Each trade result now includes:

1. **`underlying_movement_pct`** (Float)
   - Price movement in signal direction (percentage)
   - For CE (bullish): `(exit_price - entry_price) / entry_price * 100`
   - For PE (bearish): `(entry_price - exit_price) / entry_price * 100`
   - Same as `pnl_percent` but explicitly named for clarity

2. **`time_elapsed_minutes`** (Float)
   - Time from entry to exit in minutes
   - Calculated as: `(exit_time - entry_time) / 60.0`

### Summary Metrics

The summary now includes:

1. **`avg_underlying_movement_pct`** (Float)
   - Average underlying movement across all trades
   - Shows average price movement in signal direction

2. **`avg_time_elapsed_minutes`** (Float)
   - Average time from entry to exit
   - Shows how long positions are typically held

3. **`min_time_elapsed_minutes`** (Float)
   - Minimum time from entry to exit
   - Shortest trade duration

4. **`max_time_elapsed_minutes`** (Float)
   - Maximum time from entry to exit
   - Longest trade duration

---

## Output Format

### Console Output

The backtest summary now displays:

```
UNDERLYING MOVEMENT (After No-Trade Engine Allowed):
  Avg Movement:     +X.XX%
  Time to Exit:     XX.XX min (avg)
  Time Range:       X.XX - XX.XX min
```

### Trade Result Structure

Each trade in `@results` now includes:

```ruby
{
  signal_type: :ce,  # or :pe
  direction: :bullish,  # or :bearish
  entry_time: Time,
  entry_price: Float,
  exit_time: Time,
  exit_price: Float,
  pnl_percent: Float,
  underlying_movement_pct: Float,  # NEW
  time_elapsed_minutes: Float,      # NEW
  exit_reason: String,
  bars_held: Integer
}
```

---

## Usage Example

```ruby
# Run backtest
result = BacktestServiceWithNoTradeEngine.run(
  symbol: 'NIFTY',
  interval_1m: '1',
  interval_5m: '5',
  days_back: 30,
  supertrend_cfg: { period: 7, base_multiplier: 3.0 },
  adx_min_strength: 0
)

# Access summary metrics
summary = result.summary
puts "Avg Movement: #{summary[:avg_underlying_movement_pct]}%"
puts "Avg Time: #{summary[:avg_time_elapsed_minutes]} minutes"

# Access per-trade metrics
result.results.each do |trade|
  puts "Trade: #{trade[:underlying_movement_pct]}% movement in #{trade[:time_elapsed_minutes]} minutes"
end
```

---

## Interpretation

### Underlying Movement

- **Positive values**: Price moved in signal direction (profitable for options)
- **Negative values**: Price moved against signal direction (loss for options)
- **Average**: Shows overall signal quality after No-Trade Engine filtering

### Time Elapsed

- **Short duration (< 30 min)**: Quick moves, possibly scalping opportunities
- **Medium duration (30-120 min)**: Normal intraday trades
- **Long duration (> 120 min)**: Extended positions, possibly swing trades
- **Average**: Shows typical holding period for filtered signals

### Combined Analysis

- **High movement + Short time**: Strong momentum, quick profits
- **High movement + Long time**: Trend following, sustained moves
- **Low movement + Short time**: Choppy markets, false signals
- **Low movement + Long time**: Range-bound markets, theta decay

---

## Example Output

```
UNDERLYING MOVEMENT (After No-Trade Engine Allowed):
  Avg Movement:     +0.45%
  Time to Exit:     87.32 min (avg)
  Time Range:       5.00 - 240.00 min
```

This indicates:
- Average underlying moved **+0.45%** in signal direction
- Average trade duration: **87 minutes** (~1.5 hours)
- Shortest trade: **5 minutes**
- Longest trade: **240 minutes** (4 hours)

---

## Files Modified

1. **`app/services/backtest_service_with_no_trade_engine.rb`**
   - `build_exit_result()`: Added `underlying_movement_pct` and `time_elapsed_minutes`
   - `summary()`: Added average movement and time metrics
   - `print_summary()`: Added display of new metrics

---

## Benefits

1. **Signal Quality Assessment**: See how well signals perform after No-Trade Engine filtering
2. **Timing Analysis**: Understand typical holding periods for filtered signals
3. **Performance Correlation**: Correlate movement with time to optimize exits
4. **Strategy Refinement**: Use metrics to fine-tune No-Trade Engine thresholds

---

## Related Documentation

- [No-Trade Engine](./NO_TRADE_ENGINE.md) (includes relaxed configuration details)
- [Backtest No-Trade Engine](./BACKTEST_NO_TRADE_ENGINE.md)
- [No-Trade Engine](./NO_TRADE_ENGINE.md)

