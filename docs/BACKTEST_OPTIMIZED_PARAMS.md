# Backtest Optimized Parameters Integration

**Date**: 2025-01-06
**Purpose**: Automatically load optimized indicator parameters from `BestIndicatorParam` in backtesting scripts

---

## Overview

Backtesting scripts now automatically load optimized parameters from the `BestIndicatorParam` database table when available. This ensures backtests use the best-performing parameters discovered through optimization, while maintaining fallback to defaults and support for manual overrides.

---

## How It Works

### Priority Order (Highest to Lowest)

1. **Manual Override**: If parameters are explicitly provided, they are used
2. **Optimized Parameters**: If `BestIndicatorParam` has optimized params for the instrument/interval, they are loaded
3. **Default Parameters**: Falls back to hardcoded defaults if no optimization found

### Parameter Loading Flow

```
Backtest Script
  ↓
OptimizedParamsLoader.load_for_backtest()
  ↓
Check for manual override → Use if provided
  ↓
Check BestIndicatorParam table → Load if found
  ↓
Fall back to defaults → Use hardcoded values
```

---

## Implementation

### 1. OptimizedParamsLoader Module

**File**: `app/services/backtest/optimized_params_loader.rb`

A helper module that:
- Loads optimized parameters from `BestIndicatorParam` table
- Handles multiple parameter naming conventions
- Falls back to defaults if not found
- Supports manual override

**Key Method**:
```ruby
Backtest::OptimizedParamsLoader.load_for_backtest(
  instrument: instrument,
  interval: '5',
  supertrend_cfg: nil,      # nil = auto-load, Hash = manual override
  adx_min_strength: nil     # nil = auto-load, Integer = manual override
)
```

**Returns**:
```ruby
{
  supertrend_cfg: { period: 7, base_multiplier: 3.0 },
  adx_min_strength: 0,
  source: :optimized | :manual | :default,
  score: Float,      # Only if :optimized
  metrics: Hash      # Only if :optimized
}
```

### 2. Parameter Name Mapping

The loader handles multiple naming conventions from different optimization scripts:

#### Supertrend Parameters
- `st_atr` / `st_mult` (from `IndicatorOptimizer`)
- `supertrend_period` / `supertrend_multiplier` (from `optimize_indicator_parameters.rb`)
- `period` / `base_multiplier` (standard format)

#### ADX Parameters
- `adx_thresh` (from `IndicatorOptimizer`)
- `adx_1m_threshold` / `adx_5m_threshold` (from `optimize_indicator_parameters.rb`)
- `adx_min_strength` (standard format)

### 3. Updated Services

#### `Backtest::SignalGeneratorBacktester`
- Now accepts `nil` for `supertrend_cfg` and `adx_min_strength` to trigger auto-loading
- Automatically loads optimized parameters before initialization
- Logs which parameter source is being used

#### `BacktestServiceWithNoTradeEngine`
- Same auto-loading behavior as `SignalGeneratorBacktester`
- Normalizes `multiplier` → `base_multiplier` for consistency

### 4. Updated Rake Tasks

All backtest rake tasks now use `nil` for parameters to enable auto-loading:

- `rake backtest:signal_generator:nifty_sensex`
- `rake backtest:signal_generator:single`
- `rake backtest:no_trade_engine:nifty_sensex_intraday`
- `rake backtest:no_trade_engine:single`

---

## Usage Examples

### Automatic Loading (Recommended)

```ruby
# Automatically loads optimized params if available
result = Backtest::SignalGeneratorBacktester.run(
  symbol: 'NIFTY',
  interval_1m: '1',
  interval_5m: '5',
  days_back: 30,
  supertrend_cfg: nil,      # Auto-load from BestIndicatorParam
  adx_min_strength: nil     # Auto-load from BestIndicatorParam
)
```

### Manual Override

```ruby
# Override with specific parameters
result = Backtest::SignalGeneratorBacktester.run(
  symbol: 'NIFTY',
  interval_1m: '1',
  interval_5m: '5',
  days_back: 30,
  supertrend_cfg: { period: 10, base_multiplier: 2.5 },  # Manual override
  adx_min_strength: 20                                    # Manual override
)
```

### Via Rake Task

```bash
# Uses optimized parameters automatically
rake backtest:signal_generator:single[NIFTY,30]

# Output will show:
# [SignalBacktest] Using optimized parameters (Score: 1.234)
# or
# [SignalBacktest] Using default parameters (no optimization found)
```

---

## Output Indicators

The backtest output now shows:

1. **Parameter Source**:
   - `[SignalBacktest] Using optimized parameters (Score: 1.234)` - Using DB params
   - `[SignalBacktest] Using manual override parameters` - Using provided params
   - `[SignalBacktest] Using default parameters (no optimization found)` - Using defaults

2. **Parameter Values** in summary:
   ```
   Supertrend: period=7, multiplier=3.0
   ADX Min Strength: 0
   ```

---

## Database Requirements

For optimized parameters to be loaded:

1. **Table must exist**: `best_indicator_params` table
2. **Data must exist**: Row with `indicator: 'combined'` for the instrument/interval
3. **Params structure**: Must contain Supertrend and/or ADX parameters

### Check if Optimized Params Exist

```ruby
instrument = Instrument.segment_index.find_by(symbol_name: 'NIFTY')
best = BestIndicatorParam.best_for(instrument.id, '5').first

if best
  puts "Optimized params found: #{best.params}"
  puts "Score: #{best.score}"
else
  puts "No optimized params found - will use defaults"
end
```

---

## Benefits

1. **Automatic Optimization**: Backtests automatically use best-performing parameters
2. **No Manual Configuration**: No need to manually specify parameters after optimization
3. **Flexible Override**: Can still override for testing specific parameter sets
4. **Backward Compatible**: Falls back to defaults if no optimization exists
5. **Clear Logging**: Shows which parameter source is being used

---

## Migration Path

### Before
```ruby
# Hardcoded parameters
Backtest::SignalGeneratorBacktester.run(
  symbol: 'NIFTY',
  supertrend_cfg: { period: 7, base_multiplier: 3.0 },
  adx_min_strength: 0
)
```

### After
```ruby
# Auto-loads optimized parameters
Backtest::SignalGeneratorBacktester.run(
  symbol: 'NIFTY',
  supertrend_cfg: nil,  # Auto-load
  adx_min_strength: nil # Auto-load
)
```

---

## Files Modified

1. **New**: `app/services/backtest/optimized_params_loader.rb`
   - Parameter loading and normalization logic

2. **Modified**: `app/services/backtest/signal_generator_backtester.rb`
   - Added auto-loading in `.run()` method
   - Updated parameter display in summary

3. **Modified**: `app/services/backtest_service_with_no_trade_engine.rb`
   - Added auto-loading in `.run()` method
   - Added parameter normalization
   - Updated parameter display in summary

4. **Modified**: `lib/tasks/backtest_signal_generator.rake`
   - Changed to use `nil` for auto-loading

5. **Modified**: `lib/tasks/backtest_no_trade_engine.rake`
   - Changed to use `nil` for auto-loading

---

## Testing

### Test with Optimized Params

1. **Run optimization**:
   ```bash
   rake optimization:run[NIFTY,5,30]
   ```

2. **Run backtest** (should use optimized params):
   ```bash
   rake backtest:signal_generator:single[NIFTY,30]
   ```

3. **Verify output**:
   - Should show: `[SignalBacktest] Using optimized parameters (Score: X.XXX)`
   - Summary should show optimized parameter values

### Test with Defaults

1. **Delete optimized params** (or use instrument without optimization):
   ```ruby
   BestIndicatorParam.where(instrument_id: instrument.id, interval: '5').delete_all
   ```

2. **Run backtest**:
   ```bash
   rake backtest:signal_generator:single[NIFTY,30]
   ```

3. **Verify output**:
   - Should show: `[SignalBacktest] Using default parameters (no optimization found)`
   - Summary should show default parameter values

### Test Manual Override

```ruby
result = Backtest::SignalGeneratorBacktester.run(
  symbol: 'NIFTY',
  supertrend_cfg: { period: 10, base_multiplier: 2.5 },
  adx_min_strength: 20
)
# Should show: [SignalBacktest] Using manual override parameters
```

---

## Related Documentation

- [Indicator Optimization](./INDICATOR_OPTIMIZATION.md)
- [Backtest Signal Generator](./BACKTEST_SIGNAL_GENERATOR.md)
- [Backtest No-Trade Engine](./BACKTEST_NO_TRADE_ENGINE.md)

