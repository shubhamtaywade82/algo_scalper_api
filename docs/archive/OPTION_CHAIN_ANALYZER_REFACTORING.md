# Option Chain Analyzer Refactoring

## Overview

The `Options::ChainAnalyzer` has been refactored to follow a **single configurable analyzer pattern**, similar to `IndexTechnicalAnalyzer`. This eliminates code duplication and makes index-specific behavior configurable rather than hardcoded.

## Key Changes

### Before: Separate Index Rule Classes

```ruby
# Old approach - separate classes for each index
Options::IndexRules::Nifty.new
Options::IndexRules::Sensex.new
Options::IndexRules::Banknifty.new

# Hardcoded thresholds in each class
class Nifty
  MIN_VOLUME = 30_000
  MIN_PREMIUM = 25.0
  MAX_SPREAD_PCT = 0.003
end
```

### After: Configurable Strategy Pattern

```ruby
# New approach - single analyzer with configurable strategies
BEHAVIOR_STRATEGIES = {
  strike_selection: {
    default: { offset: 2, include_atm: true },
    index_specific: {
      nifty: { offset: 2, include_atm: true },
      sensex: { offset: 3, include_atm: true },
      banknifty: { offset: 2, include_atm: false }
    }
  },
  liquidity_filter: {
    default: { min_oi: 50_000, min_volume: 10_000 },
    index_specific: {
      nifty: { min_oi: 100_000, min_volume: 50_000 },
      ...
    }
  }
}

# Uses configured values automatically
analyzer = Options::ChainAnalyzer.new(index: index_cfg, ...)
recommendation = analyzer.recommend_strikes_for_signal(:bullish)
```

## Configuration Structure

### Behavior Strategies

1. **`strike_selection`**: Strike selection parameters
   - `offset`: Number of strikes away from ATM
   - `include_atm`: Whether to include ATM strike
   - `max_otm`: Maximum OTM strikes to consider

2. **`liquidity_filter`**: Liquidity filtering criteria
   - `min_oi`: Minimum open interest
   - `min_volume`: Minimum volume
   - `max_spread_pct`: Maximum bid-ask spread percentage

3. **`volatility_assessment`**: IV-based filtering
   - `low_iv`: Low IV threshold (cheap)
   - `high_iv`: High IV threshold (expensive)
   - `min_iv`: Minimum IV to accept
   - `max_iv`: Maximum IV to accept

4. **`position_sizing`**: Position sizing parameters
   - `risk_per_trade`: Risk percentage per trade
   - `max_capital_utilization`: Maximum capital utilization

5. **`delta_filter`**: Delta filtering
   - `min_delta`: Minimum delta threshold
   - `time_based`: Whether to use time-based delta thresholds

### Index-Specific Defaults

**NIFTY:**
- Strike selection: offset 2, include ATM
- Liquidity: min_oi 100k, min_volume 50k
- IV range: 10-30%

**SENSEX:**
- Strike selection: offset 3, include ATM (wider range)
- Liquidity: min_oi 50k, min_volume 25k
- IV range: 12-40%

**BANKNIFTY:**
- Strike selection: offset 2, exclude ATM
- Liquidity: min_oi 75k, min_volume 30k
- IV range: 15-45% (more volatile)

## Usage Examples

### Instance-Based API (New)

```ruby
# Create analyzer with index configuration
analyzer = Options::ChainAnalyzer.new(
  index: index_cfg,
  data_provider: provider,
  config: {}
)

# Load chain data
analyzer.load_chain_data!

# Get recommendation
recommendation = analyzer.recommend_strikes_for_signal(:bullish)
# => { strikes: [25000.0, 25050.0], option_type: 'ce' }

# Analyze specific strike
analysis = analyzer.analyze_strike(25000.0, 'ce')
# => { strike: 25000.0, iv: 15.5, oi: 150000, ... }

# Calculate position size
position_size = analyzer.calculate_position_size(100_000, 125.05)
# => Calculated using configured risk parameters
```

### Class Method API (Backward Compatible)

```ruby
# Still works - maintains backward compatibility
picks = Options::ChainAnalyzer.pick_strikes(
  index_cfg: index_cfg,
  direction: :bullish,
  ta_context: ta_result
)
# => [{ segment: 'NFO', security_id: '...', symbol: '...', ... }, ...]
```

### Custom Configuration

```ruby
# Override configuration at runtime
custom_analyzer = Options::ChainAnalyzer.new(
  index: index_cfg,
  data_provider: provider,
  config: {
    filter_by_liquidity: { min_oi: 200_000, min_volume: 100_000 }
  }
)

recommendation = custom_analyzer.recommend_strikes_for_signal(
  :bullish,
  { offset: 1, include_atm: false } # Override strike selection
)
```

## Integration Points

### Signal::Engine Integration

The refactored analyzer maintains backward compatibility with `Signal::Engine`:

```ruby
# In Signal::Engine.run_for
picks = Options::ChainAnalyzer.pick_strikes(
  index_cfg: index_cfg,
  direction: final_direction,
  ta_context: ta_result
)
```

The class method internally uses the new instance-based approach with configured strategies.

### Other Services

- **`PremiumFilter`**: Still uses `IndexRules` classes (separate concern)
- **`StrikeSelector`**: Still uses `IndexRules` classes (separate concern)

These services can be refactored later if needed, but they're separate concerns from chain analysis.

## Benefits

1. **No Code Duplication**: Single analyzer handles all indices
2. **Centralized Configuration**: Index differences are data, not code
3. **Runtime Flexibility**: Can override configuration at runtime
4. **Easier Testing**: Test once, works for all indices
5. **Consistent Interface**: Same API pattern as `IndexTechnicalAnalyzer`
6. **Backward Compatible**: Existing code continues to work

## Migration Notes

### Backward Compatibility

✅ **Fully backward compatible:**
- `Options::ChainAnalyzer.pick_strikes` class method still works
- Return format matches existing expectations
- Integration with `Signal::Engine` unchanged

### New Features

- Instance-based API with configurable strategies
- Methods: `recommend_strikes_for_signal`, `filter_by_liquidity`, `calculate_position_size`
- Configuration access via `analyzer.config`
- Index-specific defaults applied automatically

### Configuration Priority

1. **Runtime override** (via `custom_config` parameter)
2. **algo.yml** (`option_chain` section)
3. **Index-specific defaults** (from `BEHAVIOR_STRATEGIES`)
4. **Global defaults** (from `BEHAVIOR_STRATEGIES`)

## Future Enhancements

### YAML Configuration

Could load strategies from YAML file:

```yaml
# config/option_chain_strategies.yml
strategies:
  strike_selection:
    default: { offset: 2, include_atm: true }
    nifty: { offset: 2, include_atm: true }
    sensex: { offset: 3, include_atm: true }
```

### TA Context Integration

Future enhancement to use TA context in strike selection:

```ruby
# Use TA confidence to adjust strike selection
if ta_context[:confidence] > 0.8
  # Use wider strike range for high confidence
  recommendation = analyzer.recommend_strikes_for_signal(
    direction,
    { offset: 3 } # Wider range
  )
end
```

## Testing

```ruby
# Test with default config
analyzer = Options::ChainAnalyzer.new(index: nifty_cfg, ...)
result = analyzer.recommend_strikes_for_signal(:bullish)

# Test with custom config
custom_analyzer = Options::ChainAnalyzer.new(
  index: nifty_cfg,
  config: { filter_by_liquidity: { min_oi: 200_000 } }
)

# Test backward compatibility
picks = Options::ChainAnalyzer.pick_strikes(
  index_cfg: nifty_cfg,
  direction: :bullish
)
```

## Design Principles Applied

1. **DRY**: Single analyzer, configuration-driven
2. **KISS**: Simple configuration structure
3. **YAGNI**: Only add what's needed
4. **Strategy Pattern**: Behavior configured via strategies
5. **Open/Closed Principle**: Open for extension (new indices), closed for modification
