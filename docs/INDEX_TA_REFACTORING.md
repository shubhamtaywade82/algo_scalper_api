# Index Technical Analyzer Refactoring

## Overview

The `IndexTechnicalAnalyzer` has been refactored to follow a **single configurable analyzer pattern**, similar to the `Option::ChainAnalyzer` refactoring. This eliminates code duplication and makes index-specific behavior configurable rather than hardcoded.

## Key Changes

### Before: Hardcoded Configuration

```ruby
# Old approach - hardcoded INDEX_CONFIG
INDEX_CONFIG = {
  nifty: { security_id: '13', ... },
  sensex: { security_id: '51', ... },
  banknifty: { security_id: '25', ... }
}

# Hardcoded indicator periods
indicators_data[tf] = {
  rsi: series.rsi(14),      # Always 14
  adx: series.adx(14),       # Always 14
  macd: series.macd(12, 26, 9), # Always same
  atr: series.atr(14)        # Always 14
}

# Hardcoded thresholds
bullish_count += 1 if rsi < 40  # Always 40
bearish_count += 1 if rsi > 60  # Always 60
```

### After: Configurable Strategy Pattern

```ruby
# New approach - configurable strategies
ANALYSIS_STRATEGIES = {
  timeframes: {
    default: [5, 15, 60],
    index_specific: {
      nifty: [5, 15, 60],
      sensex: [5, 15, 30, 60],  # Sensex-specific
      banknifty: [5, 15, 60]
    }
  },
  indicator_periods: {
    default: { rsi: 14, adx: 14, ... },
    index_specific: { ... }
  },
  bias_thresholds: {
    default: { rsi_oversold: 30, ... },
    index_specific: {
      sensex: { rsi_oversold: 25, ... }  # Sensex-specific
    }
  }
}

# Uses configured periods
periods = @config[:indicator_periods]
indicators_data[tf] = {
  rsi: series.rsi(periods[:rsi]),
  adx: series.adx(periods[:adx]),
  ...
}

# Uses configured thresholds
thresholds = @config[:bias_thresholds]
bullish_count += 1 if rsi < thresholds[:rsi_bullish_threshold]
```

## Benefits

### 1. **No Code Duplication**
- Single analyzer class handles all indices
- Index-specific behavior is configuration, not code

### 2. **Centralized Configuration**
- All index-specific settings in one place (`ANALYSIS_STRATEGIES`)
- Easy to see differences between indices
- Easy to add new indices

### 3. **Runtime Flexibility**
- Can override configuration at runtime via `custom_config` parameter
- Can override timeframes/days_back in `call()` method
- Maintains backward compatibility

### 4. **Easier Testing**
- Test once, works for all indices
- Can test with different configurations easily
- Mock configuration for testing

### 5. **Consistent Interface**
- Same API for all indices
- Same error handling
- Same logging patterns

## Configuration Structure

### Analysis Strategies

```ruby
ANALYSIS_STRATEGIES = {
  timeframes: {
    method: :select_timeframes,
    default: [5, 15, 60],
    index_specific: { ... }
  },
  indicator_periods: {
    method: :configure_indicator_periods,
    default: { rsi: 14, adx: 14, ... },
    index_specific: { ... }
  },
  bias_thresholds: {
    method: :configure_bias_thresholds,
    default: { rsi_oversold: 30, ... },
    index_specific: { ... }
  },
  api_settings: {
    method: :configure_api_settings,
    default: { throttle_seconds: 2.5, ... },
    index_specific: { ... }
  }
}
```

### Index-Specific Defaults

**NIFTY:**
- Timeframes: `[5, 15, 60]`
- RSI thresholds: oversold 30, overbought 70
- Standard indicator periods

**SENSEX:**
- Timeframes: `[5, 15, 30, 60]` (includes 30min)
- RSI thresholds: oversold 25, overbought 75 (more sensitive)
- Higher base confidence: 0.5
- Slower API throttling: 3.0 seconds

**BANKNIFTY:**
- Timeframes: `[5, 15, 60]`
- Standard thresholds (same as NIFTY)

## Usage Examples

### Standard Usage (Uses Configured Defaults)

```ruby
analyzer = IndexTechnicalAnalyzer.new(:nifty)
result = analyzer.call
# Uses NIFTY-specific defaults automatically
```

### Runtime Override

```ruby
analyzer = IndexTechnicalAnalyzer.new(:nifty)
result = analyzer.call(
  timeframes: [5, 15, 30, 60],  # Override default
  days_back: 45                  # Override default
)
```

### Custom Configuration

```ruby
custom_analyzer = IndexTechnicalAnalyzer.new(:nifty, custom_config: {
  configure_indicator_periods: { rsi: 21, adx: 21 },
  configure_bias_thresholds: { rsi_oversold: 25, rsi_overbought: 75 }
})
result = custom_analyzer.call
```

## Migration Notes

### Backward Compatibility

✅ **Fully backward compatible:**
- Existing code using `IndexTechnicalAnalyzer.new(:nifty).call()` works unchanged
- Default behavior matches previous implementation
- Signal::Engine integration unchanged

### New Features

- Can now override configuration at runtime
- Can access configuration via `analyzer.config`
- Index-specific defaults applied automatically

### Configuration Access

```ruby
analyzer = IndexTechnicalAnalyzer.new(:nifty)
puts analyzer.config[:timeframes]              # [5, 15, 60]
puts analyzer.config[:indicator_periods][:rsi]  # 14
puts analyzer.config[:bias_thresholds]         # Hash
puts analyzer.config[:api_settings]            # Hash
```

## Future Enhancements

### YAML Configuration (Future)

Currently configuration is in Ruby constants. Future enhancement could load from YAML:

```yaml
# config/index_ta_strategies.yml
strategies:
  timeframes:
    default: [5, 15, 60]
    nifty: [5, 15, 60]
    sensex: [5, 15, 30, 60]
```

### Dynamic Configuration Loading

Could load from `algo.yml` or separate config file:

```yaml
# config/algo.yml
index_ta:
  nifty:
    timeframes: [5, 15, 60]
    indicator_periods:
      rsi: 14
      adx: 14
```

## Testing

### Test with Different Configurations

```ruby
# Test with default config
analyzer = IndexTechnicalAnalyzer.new(:nifty)
result = analyzer.call

# Test with custom config
custom_analyzer = IndexTechnicalAnalyzer.new(:nifty, custom_config: {
  configure_bias_thresholds: { rsi_oversold: 25 }
})
custom_result = custom_analyzer.call

# Test with different index
sensex_analyzer = IndexTechnicalAnalyzer.new(:sensex)
sensex_result = sensex_analyzer.call
```

## Design Principles Applied

1. **DRY (Don't Repeat Yourself)**: Single analyzer, configuration-driven
2. **KISS (Keep It Simple, Stupid)**: Simple configuration structure
3. **YAGNI (You Aren't Gonna Need It)**: Only add what's needed
4. **Strategy Pattern**: Behavior configured via strategies
5. **Open/Closed Principle**: Open for extension (new indices), closed for modification

## Comparison with Option::ChainAnalyzer

Both analyzers now follow the same pattern:

| Aspect | Option::ChainAnalyzer | IndexTechnicalAnalyzer |
|--------|----------------------|----------------------|
| Pattern | Single configurable class | Single configurable class |
| Configuration | `BEHAVIOR_STRATEGIES` | `ANALYSIS_STRATEGIES` |
| Index-specific | Via `index_specific` hash | Via `index_specific` hash |
| Runtime override | Via method params | Via `custom_config` + method params |
| Defaults | Per-index defaults | Per-index defaults |

This consistency makes the codebase easier to understand and maintain.
