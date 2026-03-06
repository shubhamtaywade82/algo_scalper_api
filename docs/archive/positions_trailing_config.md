# Positions::TrailingConfig

## Overview

`Positions::TrailingConfig` provides configuration constants and helper methods for trailing stop management in position tracking. It defines the peak drawdown threshold and tiered SL offset mapping based on profit percentage.

## Usage

### Constants

```ruby
# Peak drawdown threshold (5.0%)
Positions::TrailingConfig::PEAK_DRAWDOWN_PCT
# => 5.0

# Tier configuration
Positions::TrailingConfig::TIERS
# => [
#   { threshold_pct: 5.0, sl_offset_pct: -15.0 },
#   { threshold_pct: 10.0, sl_offset_pct: -5.0 },
#   { threshold_pct: 15.0, sl_offset_pct: 0.0 },
#   { threshold_pct: 25.0, sl_offset_pct: 10.0 },
#   { threshold_pct: 40.0, sl_offset_pct: 20.0 },
#   { threshold_pct: 60.0, sl_offset_pct: 30.0 },
#   { threshold_pct: 80.0, sl_offset_pct: 40.0 },
#   { threshold_pct: 120.0, sl_offset_pct: 60.0 }
# ]
```

### Methods

#### `sl_offset_for(profit_pct)`

Returns the SL offset percentage for a given profit percentage.

```ruby
# Example: Profit is 7.5% (between 5% and 10% tier)
Positions::TrailingConfig.sl_offset_for(7.5)
# => -15.0  # Uses 5% tier (first tier)

# Example: Profit is 20% (between 15% and 25% tier)
Positions::TrailingConfig.sl_offset_for(20.0)
# => 0.0  # Uses 15% tier (breakeven)

# Example: Profit is 50% (between 40% and 60% tier)
Positions::TrailingConfig.sl_offset_for(50.0)
# => 20.0  # Uses 40% tier

# Example: Profit exceeds highest tier (150%)
Positions::TrailingConfig.sl_offset_for(150.0)
# => 60.0  # Uses highest tier (120%)
```

#### `peak_drawdown_triggered?(peak_profit_pct, current_profit_pct)`

Checks if the drawdown from peak triggers an immediate exit.

```ruby
# Peak was 20%, current is 10% → drawdown = 10% (>= 5%)
Positions::TrailingConfig.peak_drawdown_triggered?(20.0, 10.0)
# => true  # Exit immediately

# Peak was 20%, current is 18% → drawdown = 2% (< 5%)
Positions::TrailingConfig.peak_drawdown_triggered?(20.0, 18.0)
# => false  # Continue monitoring
```

#### `calculate_sl_price(entry_price, profit_pct)`

Calculates the SL price based on entry price and current profit percentage.

```ruby
# Entry: ₹100, Profit: 0% → SL offset: -15%
Positions::TrailingConfig.calculate_sl_price(100.0, 0.0)
# => 85.0  # SL = 100 * 0.85

# Entry: ₹100, Profit: 20% → SL offset: 0% (breakeven)
Positions::TrailingConfig.calculate_sl_price(100.0, 20.0)
# => 100.0  # SL = entry price

# Entry: ₹100, Profit: 50% → SL offset: +20%
Positions::TrailingConfig.calculate_sl_price(100.0, 50.0)
# => 120.0  # SL = 100 * 1.20
```

## Tier Logic

The tier system works as follows:

1. **Below 5% profit**: SL offset = -15% (SL below entry)
2. **5% to 9.99% profit**: SL offset = -15% (still first tier)
3. **10% to 14.99% profit**: SL offset = -5% (second tier)
4. **15% to 24.99% profit**: SL offset = 0% (breakeven - third tier)
5. **25% to 39.99% profit**: SL offset = +10% (fourth tier)
6. **40% to 59.99% profit**: SL offset = +20% (fifth tier)
7. **60% to 79.99% profit**: SL offset = +30% (sixth tier)
8. **80% to 119.99% profit**: SL offset = +40% (seventh tier)
9. **120%+ profit**: SL offset = +60% (highest tier)

## Integration

This module is used by:
- `Live::TrailingEngine` (Step 8) - For tiered SL calculations
- `Live::RiskManagerService` (Step 10) - For peak-drawdown checks
- `Orders::BracketPlacer` (Step 7) - For SL price calculations

## Testing

Run tests with:
```bash
bundle exec rspec spec/services/positions/trailing_config_spec.rb
```

All 44 test cases pass, covering:
- Tier lookup for all thresholds
- Boundary cases (between tiers, exceeding highest tier)
- Edge cases (negative profit, zero profit, nil values)
- Peak drawdown trigger logic
- SL price calculations

