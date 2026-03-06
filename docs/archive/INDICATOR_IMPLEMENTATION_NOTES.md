# Indicator Implementation Notes

## Using Existing CandleSeries Methods

All indicator wrappers **leverage existing CandleSeries methods** that use proven technical analysis libraries:

### Libraries Used

1. **TechnicalAnalysis gem** (`technical-analysis`)
   - Used for: ADX, ATR, Donchian Channel, OBV
   - CandleSeries methods: `adx()`, `atr()`, `donchian_channel()`, `obv()`

2. **RubyTechnicalAnalysis gem** (`ruby-technical-analysis`)
   - Used for: RSI, MACD, Moving Averages, Bollinger Bands
   - CandleSeries methods: `rsi()`, `macd()`, `sma()`, `ema()`, `bollinger_bands()`

3. **Custom Supertrend** (`Indicators::Supertrend`)
   - Custom implementation already in the codebase
   - CandleSeries method: `supertrend_signal()`

## How Our Wrappers Work

### No Redundancy - We Use Existing Methods

Our indicator wrappers are **thin wrappers** that:
1. ✅ Use existing `CandleSeries` methods (which use the gems)
2. ✅ Add signal interpretation (direction, confidence)
3. ✅ Add trading hours filtering
4. ✅ Create partial series for index-specific calculations

### Example: ADX Indicator

```ruby
# Our wrapper uses CandleSeries#adx (which uses TechnicalAnalysis gem)
partial_series = create_partial_series(index)
adx_value = partial_series.adx(@period)  # ← Uses existing method!
```

**Not reinventing**: We're calling `CandleSeries#adx` which internally uses:
```ruby
TechnicalAnalysis::Adx.calculate(hlc, period: period)
```

### Example: RSI Indicator

```ruby
# Our wrapper uses CandleSeries#rsi (which uses RubyTechnicalAnalysis gem)
partial_series = create_partial_series(index)
rsi_value = partial_series.rsi(@period)  # ← Uses existing method!
```

**Not reinventing**: We're calling `CandleSeries#rsi` which internally uses:
```ruby
RubyTechnicalAnalysis::RelativeStrengthIndex.new(series: closes, period: period).call
```

### Example: MACD Indicator

```ruby
# Our wrapper uses CandleSeries#macd (which uses RubyTechnicalAnalysis gem)
partial_series = create_partial_series(index)
macd_result = partial_series.macd(@fast_period, @slow_period, @signal_period)  # ← Uses existing method!
```

**Not reinventing**: We're calling `CandleSeries#macd` which internally uses:
```ruby
RubyTechnicalAnalysis::Macd.new(series: closes, fast_period: fast_period, ...).call
```

## Why Partial Series?

We create partial series (`series.candles[0..index]`) because:

1. **Index-specific calculations**: For backtesting and signal generation, we need indicator values at specific historical indices, not just the latest value.

2. **Accurate historical simulation**: When generating signals at index `i`, we should only use data up to `i` (no lookahead bias).

3. **Reuses existing logic**: The partial series still uses the same `CandleSeries` methods and underlying gems - we're just limiting the data range.

## What We Add (Not Redundant)

Our wrappers add **signal interpretation logic** that doesn't exist in the raw indicator calculations:

1. **Direction determination**: 
   - ADX: Infers direction from price movement (ADX itself doesn't provide direction)
   - RSI: Interprets overbought/oversold levels
   - MACD: Interprets crossovers and histogram

2. **Confidence scoring**: Converts raw indicator values into 0-100 confidence scores

3. **Trading hours filtering**: Applies trading hours constraints

4. **Standardized interface**: Provides consistent `{ value, direction, confidence }` format

## Summary

✅ **We use existing CandleSeries methods**  
✅ **We use existing technical analysis gems**  
✅ **No redundant calculations**  
✅ **We add signal interpretation and standardization**  

The only "new" code is:
- Signal interpretation logic (direction, confidence)
- Trading hours filtering
- Standardized interface wrapper

All actual indicator calculations delegate to existing, proven implementations.
