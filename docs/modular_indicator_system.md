# Modular Indicator System

## Overview

The modular indicator system allows you to easily add, remove, and combine multiple technical indicators for signal generation. This replaces the hardcoded Supertrend+ADX combination with a flexible, configuration-driven approach.

## Architecture

### Components

1. **BaseIndicator** (`app/services/indicators/base_indicator.rb`)
   - Base interface that all indicators must implement
   - Provides common functionality like trading hours filtering

2. **Individual Indicators**
   - `SupertrendIndicator` - Supertrend trend-following indicator
   - `AdxIndicator` - Average Directional Index for trend strength
   - `RsiIndicator` - Relative Strength Index for overbought/oversold
   - `MacdIndicator` - Moving Average Convergence Divergence
   - `TrendDurationIndicator` - HMA-based trend duration forecasting

3. **MultiIndicatorStrategy** (`app/strategies/multi_indicator_strategy.rb`)
   - Combines multiple indicators using different confirmation modes
   - Supports: `all`, `majority`, `weighted`, `any`

4. **IndicatorFactory** (`app/services/indicators/indicator_factory.rb`)
   - Factory for creating indicator instances from configuration

## Configuration

### Enable Modular System

In `config/algo.yml`, set:

```yaml
signals:
  use_multi_indicator_strategy: true  # Enable modular system
  confirmation_mode: all              # Options: all, majority, weighted, any
  min_confidence: 60                  # Minimum confidence score (0-100)
```

### Configure Indicators

```yaml
signals:
  indicators:
    - type: supertrend
      enabled: true
      config:
        period: 7
        multiplier: 3.0
        trading_hours_filter: true

    - type: adx
      enabled: true
      config:
        period: 14
        min_strength: 18
        trading_hours_filter: true

    - type: rsi
      enabled: false  # Disabled by default
      config:
        period: 14
        oversold: 30
        overbought: 70
        trading_hours_filter: true

    - type: macd
      enabled: false  # Disabled by default
      config:
        fast_period: 12
        slow_period: 26
        signal_period: 9
        trading_hours_filter: true

    - type: trend_duration
      enabled: false  # Disabled by default
      config:
        hma_length: 20        # HMA period
        trend_length: 5       # Bars to confirm trend (rising/falling)
        samples: 10           # Number of historical durations to track
        trading_hours_filter: true
```

## Indicator Details

### Trend Duration Indicator

The Trend Duration Indicator uses HMA (Hull Moving Average) to detect trend direction and forecast probable trend duration. It tracks historical trend durations to predict how long current trends might last.

**Key Features:**
- Uses HMA for smooth trend detection
- Tracks trend duration (how long trends persist)
- Calculates probable duration based on historical averages
- Provides confidence scores based on trend maturity and historical patterns

**Configuration:**
- `hma_length`: HMA period (default: 20)
- `trend_length`: Number of bars to confirm trend direction (default: 5)
- `samples`: Number of historical durations to track (default: 10)

**Output:**
- `hma`: Current HMA value
- `trend_direction`: `:bullish` or `:bearish`
- `real_length`: Current trend duration in bars
- `probable_length`: Average historical duration for this trend type
- `slope`: `'up'` or `'down'`

**Use Cases:**
- Filter fake breakouts (trends that end too quickly)
- Identify trend continuation opportunities
- Combine with other indicators for entry timing
- Options trading: Use probable duration for position sizing and expiry selection

**Example:**
```yaml
- type: trend_duration
  enabled: true
  config:
    hma_length: 20
    trend_length: 5
    samples: 10
```

## Confirmation Modes

### `all` (Default)
All indicators must agree on direction. Most conservative.

**Example**: Supertrend bullish + ADX bullish + RSI bullish → CE signal

### `majority`
Majority of indicators (>50%) must agree.

**Example**: 3 indicators, 2 bullish + 1 bearish → CE signal

### `weighted`
Weighted sum of indicator confidences. Direction with higher weighted score wins.

**Example**: 
- Supertrend: bullish (confidence 80)
- ADX: bullish (confidence 70)
- RSI: bearish (confidence 60)
- Weighted: (80 + 70) vs 60 → CE signal

### `any`
Any single indicator can confirm. Most aggressive.

**Example**: Supertrend bullish (others neutral) → CE signal

## Usage Examples

### Example 1: Supertrend + ADX (Current Default)

```yaml
signals:
  use_multi_indicator_strategy: true
  confirmation_mode: all
  indicators:
    - type: supertrend
      enabled: true
      config:
        period: 7
        multiplier: 3.0
    - type: adx
      enabled: true
      config:
        min_strength: 18
```

### Example 2: Triple Confirmation (Supertrend + ADX + RSI)

```yaml
signals:
  use_multi_indicator_strategy: true
  confirmation_mode: all
  indicators:
    - type: supertrend
      enabled: true
    - type: adx
      enabled: true
    - type: rsi
      enabled: true
      config:
        oversold: 30
        overbought: 70
```

### Example 3: Weighted Multi-Indicator

```yaml
signals:
  use_multi_indicator_strategy: true
  confirmation_mode: weighted
  min_confidence: 65
  indicators:
    - type: supertrend
      enabled: true
    - type: adx
      enabled: true
    - type: macd
      enabled: true
```

### Example 4: Majority Vote

```yaml
signals:
  use_multi_indicator_strategy: true
  confirmation_mode: majority
  indicators:
    - type: supertrend
      enabled: true
    - type: adx
      enabled: true
    - type: rsi
      enabled: true
    - type: macd
      enabled: true
```

### Example 5: Trend Duration + Supertrend (Trend Continuation)

```yaml
signals:
  use_multi_indicator_strategy: true
  confirmation_mode: all
  min_confidence: 65
  indicators:
    - type: supertrend
      enabled: true
      config:
        period: 7
        multiplier: 3.0
    - type: trend_duration
      enabled: true
      config:
        hma_length: 20
        trend_length: 5
        samples: 10
```

This combination ensures:
- Supertrend confirms trend direction
- Trend Duration validates trend maturity and continuation probability
- Higher confidence signals for established trends

## Adding New Indicators

To add a new indicator:

1. Create indicator class in `app/services/indicators/`:

```ruby
# frozen_string_literal: true

module Indicators
  class YourIndicator < BaseIndicator
    def min_required_candles
      # Return minimum candles needed
    end

    def ready?(index)
      index >= min_required_candles
    end

    def calculate_at(index)
      # Calculate indicator value
      # Return: { value: ..., direction: :bullish/:bearish/:neutral, confidence: 0-100 }
    end
  end
end
```

2. Register in `IndicatorFactory`:

```ruby
case indicator_type.to_s.downcase
when 'your_indicator'
  Indicators::YourIndicator.new(series: series, config: merged_config)
```

3. Add to configuration:

```yaml
signals:
  indicators:
    - type: your_indicator
      enabled: true
      config:
        param1: value1
```

## Backward Compatibility

The existing `SupertrendAdxStrategy` now uses the modular system internally, maintaining full backward compatibility. Existing code continues to work without changes.

## Performance Considerations

- Indicators cache their calculations when possible
- Supertrend is calculated once per series (cached)
- ADX, RSI, MACD calculate on-demand for each index
- Trading hours filter is applied consistently across all indicators

## Migration Guide

### From Old System to Modular System

1. **Enable modular system**:
   ```yaml
   signals:
     use_multi_indicator_strategy: true
   ```

2. **Configure indicators** (copy from existing supertrend/adx config):
   ```yaml
   signals:
     indicators:
       - type: supertrend
         enabled: true
         config:
           period: 7  # From signals.supertrend.period
           multiplier: 3.0  # From signals.supertrend.base_multiplier
       - type: adx
         enabled: true
         config:
           min_strength: 18  # From signals.adx.min_strength
   ```

3. **Choose confirmation mode**:
   - `all` = Most conservative (like old system)
   - `majority` = More flexible
   - `weighted` = Uses confidence scores
   - `any` = Most aggressive

4. **Test thoroughly** before deploying to production

## Troubleshooting

### No signals generated
- Check that indicators are `enabled: true`
- Verify `min_confidence` is not too high
- Check that `confirmation_mode` allows signals (e.g., `all` requires all indicators to agree)

### Too many signals
- Increase `min_confidence`
- Use `all` confirmation mode for stricter requirements
- Add more indicators for additional confirmation

### Performance issues
- Reduce number of enabled indicators
- Check indicator calculation efficiency
- Monitor caching behavior
