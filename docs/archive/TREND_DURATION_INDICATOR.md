# Trend Duration Indicator Implementation

## Overview

The Trend Duration Indicator has been successfully integrated into the modular indicator system. It uses HMA (Hull Moving Average) to detect trend direction and forecast probable trend duration based on historical patterns.

## Implementation Details

### Core Components

1. **`Indicators::TrendDurationIndicator`** (`app/services/indicators/trend_duration_indicator.rb`)
   - Implements `BaseIndicator` interface
   - Calculates HMA using two-step process:
     - Step 1: Calculate raw HMA series (2 * WMA(half) - WMA(full))
     - Step 2: Apply WMA to raw HMA series with period sqrt(length)
   - Detects trend direction using rising/falling HMA patterns
   - Tracks trend durations and calculates probable durations

2. **Integration Points**
   - Added to `IndicatorFactory` (supports: `trend_duration`, `trend_duration_forecast`, `tdf`)
   - Added to `MultiIndicatorStrategy` for combination with other indicators
   - Configuration support in `config/algo.yml`

### Key Features

- **HMA Calculation**: Implements proper Hull Moving Average algorithm
- **Trend Detection**: Uses configurable `trend_length` bars to confirm trend direction
- **Duration Tracking**: Maintains separate arrays for bullish/bearish durations
- **Probable Duration**: Calculates average historical duration for trend forecasting
- **Confidence Scoring**: Based on trend maturity and historical pattern matching

### Configuration

```yaml
signals:
  indicators:
    - type: trend_duration
      enabled: true
      config:
        hma_length: 20        # HMA period (default: 20)
        trend_length: 5       # Bars to confirm trend (default: 5)
        samples: 10           # Historical durations to track (default: 10)
        trading_hours_filter: true
```

### Output Format

```ruby
{
  value: {
    hma: 22050.5,                    # Current HMA value
    trend_direction: :bullish,       # :bullish or :bearish
    real_length: 12,                 # Current trend duration in bars
    probable_length: 15.3,           # Average historical duration
    slope: 'up'                      # 'up' or 'down'
  },
  direction: :bullish,               # Signal direction
  confidence: 75                     # Confidence score (0-100)
}
```

## Technical Implementation

### HMA Algorithm

The HMA calculation follows the standard formula:

1. **Raw HMA**: `raw_hma = 2 * WMA(close, length/2) - WMA(close, length)`
2. **Final HMA**: `hma = WMA(raw_hma_series, sqrt(length))`

### Trend Detection

- **Rising Trend**: Last `trend_length` HMA values are all increasing
- **Falling Trend**: Last `trend_length` HMA values are all decreasing
- **Neutral**: Neither rising nor falling consistently

### Duration Tracking

- Maintains separate arrays for bullish and bearish durations
- When trend changes, previous duration is saved to appropriate array
- Arrays are limited to `samples` size (FIFO)
- Probable duration = average of historical durations for current trend type

### Confidence Calculation

Confidence is calculated based on:
- Base confidence: 50
- +20 if trend is established (real_length >= trend_length)
- +15 if current duration matches probable duration (within 80-120%)
- +10 if current duration is early (<50% of probable)
- +10 if sufficient historical data (>=5 samples)

## Testing

### Unit Tests (`spec/services/indicators/trend_duration_indicator_spec.rb`)

- Initialization with default and custom config
- Minimum required candles calculation
- Ready state checking
- HMA calculation correctness
- Trend detection (bullish/bearish)
- Duration tracking
- Edge cases (empty series, nil values)

### Integration Tests (`spec/integration/trend_duration_indicator_integration_spec.rb`)

- End-to-end trend duration calculation
- Multiple trend changes tracking
- Integration with `MultiIndicatorStrategy`
- Combination with other indicators
- Real-world scenario testing

## Usage Examples

### Standalone Usage

```ruby
indicator = Indicators::TrendDurationIndicator.new(
  series: candle_series,
  config: { hma_length: 20, trend_length: 5, samples: 10 }
)

result = indicator.calculate_at(index)
if result && result[:direction] == :bullish && result[:confidence] >= 60
  # Generate CE buy signal
end
```

### With MultiIndicatorStrategy

```ruby
strategy = MultiIndicatorStrategy.new(
  series: candle_series,
  indicators: [
    { type: 'supertrend', config: { period: 7, multiplier: 3.0 } },
    { type: 'trend_duration', config: { hma_length: 20, trend_length: 5 } }
  ],
  confirmation_mode: :all,
  min_confidence: 65
)

signal = strategy.generate_signal(index)
```

### Configuration-Based Usage

Enable in `config/algo.yml`:

```yaml
signals:
  use_multi_indicator_strategy: true
  confirmation_mode: all
  indicators:
    - type: trend_duration
      enabled: true
      config:
        hma_length: 20
        trend_length: 5
        samples: 10
```

## Integration with Existing System

The indicator is fully integrated with:
- ✅ `Signal::Engine` - Can be used via multi-indicator system
- ✅ `MultiIndicatorStrategy` - Can combine with other indicators
- ✅ `IndicatorFactory` - Factory pattern for instantiation
- ✅ Configuration system - YAML-based configuration
- ✅ Trading hours filter - Respects trading hours if enabled

## Performance Considerations

- **HMA Calculation**: O(n) where n is number of candles
- **Trend Detection**: O(trend_length) per calculation
- **Duration Tracking**: O(1) for updates, O(samples) for averages
- **Memory**: Stores `samples` durations per trend type (minimal)

## Use Cases

1. **Trend Continuation Signals**: Identify established trends likely to continue
2. **Fake Breakout Filter**: Filter out trends that end too quickly
3. **Options Trading**: Use probable duration for expiry selection and position sizing
4. **Entry Timing**: Combine with other indicators for optimal entry points

## Future Enhancements

Potential improvements:
- Add support for different HMA periods per timeframe
- Implement trend strength scoring
- Add support for trend exhaustion detection
- Integrate with position sizing based on probable duration

## References

- Pine Script implementation analyzed for requirements
- DhanHQ API v2 provides all required OHLC data
- HMA formula: Standard Hull Moving Average algorithm
- No external dependencies beyond existing technical analysis infrastructure
