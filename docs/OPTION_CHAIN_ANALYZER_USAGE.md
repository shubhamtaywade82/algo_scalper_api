# Option Chain Analyzer Usage Guide

## Quick Start

### Basic Usage (Class Method - Backward Compatible)

```ruby
# Simple usage - works exactly as before
picks = Options::ChainAnalyzer.pick_strikes(
  index_cfg: index_cfg,
  direction: :bullish,
  ta_context: ta_result  # Optional TA context
)

# Returns array of strike picks:
# [{ segment: 'NFO', security_id: '...', symbol: '...', ltp: 125.5, ... }, ...]
```

### Instance-Based Usage (New Configurable API)

```ruby
# Create analyzer
analyzer = Options::ChainAnalyzer.new(
  index: index_cfg,
  data_provider: provider,  # Optional
  config: {}  # Optional custom config
)

# Load chain data
analyzer.load_chain_data!

# Get strike recommendation
recommendation = analyzer.recommend_strikes_for_signal(:bullish)
# => { strikes: [25000.0, 25050.0, 25100.0], option_type: 'ce' }

# Analyze individual strikes
recommendation[:strikes].each do |strike|
  analysis = analyzer.analyze_strike(strike, recommendation[:option_type])
  puts "Strike #{strike}: IV=#{analysis[:iv]}, OI=#{analysis[:oi]}, Liquidity=#{analysis[:liquidity_status]}"
end
```

## Configuration Examples

### Access Configuration

```ruby
analyzer = Options::ChainAnalyzer.new(index: index_cfg)
puts analyzer.config[:lot_size]              # 50 (for NIFTY)
puts analyzer.config[:filter_by_liquidity]   # { min_oi: 100000, ... }
puts analyzer.config[:assess_volatility]     # { low_iv: 10.0, high_iv: 30.0, ... }
```

### Override Configuration

```ruby
# Override at initialization
custom_analyzer = Options::ChainAnalyzer.new(
  index: index_cfg,
  config: {
    filter_by_liquidity: {
      min_oi: 200_000,      # Higher OI requirement
      min_volume: 100_000   # Higher volume requirement
    }
  }
)

# Override at method call
recommendation = custom_analyzer.recommend_strikes_for_signal(
  :bullish,
  { offset: 1, include_atm: false }  # Narrower strike range
)
```

## Index-Specific Behavior

### NIFTY

```ruby
nifty_analyzer = Options::ChainAnalyzer.new(index: nifty_cfg)
nifty_analyzer.load_chain_data!

# Uses NIFTY defaults:
# - Strike selection: offset 2, include ATM
# - Liquidity: min_oi 100k, min_volume 50k
# - IV range: 10-30%

recommendation = nifty_analyzer.recommend_strikes_for_signal(:bullish)
```

### SENSEX

```ruby
sensex_analyzer = Options::ChainAnalyzer.new(index: sensex_cfg)
sensex_analyzer.load_chain_data!

# Uses SENSEX defaults:
# - Strike selection: offset 3 (wider range), include ATM
# - Liquidity: min_oi 50k, min_volume 25k
# - IV range: 12-40%

recommendation = sensex_analyzer.recommend_strikes_for_signal(:bearish)
```

### BANKNIFTY

```ruby
banknifty_analyzer = Options::ChainAnalyzer.new(index: banknifty_cfg)
banknifty_analyzer.load_chain_data!

# Uses BANKNIFTY defaults:
# - Strike selection: offset 2, exclude ATM
# - Liquidity: min_oi 75k, min_volume 30k
# - IV range: 15-45% (more volatile)

recommendation = banknifty_analyzer.recommend_strikes_for_signal(:bullish)
```

## Advanced Usage

### Complete Trading Workflow

```ruby
def trading_workflow(index_cfg, signal_direction, capital = 100_000)
  # 1. Create analyzer
  analyzer = Options::ChainAnalyzer.new(index: index_cfg)
  
  # 2. Load chain data
  analyzer.load_chain_data!
  
  # 3. Get recommendation
  recommendation = analyzer.recommend_strikes_for_signal(signal_direction)
  
  return nil unless recommendation[:strikes]&.any?
  
  # 4. Analyze each recommended strike
  analyses = recommendation[:strikes].map do |strike|
    analyzer.analyze_strike(strike, recommendation[:option_type])
  end
  
  # 5. Calculate position sizes
  orders = recommendation[:strikes].map do |strike|
    analysis = analyzer.analyze_strike(strike, recommendation[:option_type])
    next unless analysis
    
    {
      strike: strike,
      option_type: recommendation[:option_type],
      quantity: analyzer.calculate_position_size(
        capital,
        analysis[:last_price]
      ),
      analysis: analysis
    }
  end.compact
  
  {
    recommendation: recommendation,
    analyses: analyses,
    orders: orders,
    config_used: analyzer.config
  }
end

# Use for any index
nifty_trade = trading_workflow(nifty_cfg, :bullish)
sensex_trade = trading_workflow(sensex_cfg, :bearish)
banknifty_trade = trading_workflow(banknifty_cfg, :bullish)
```

### Filtering Strikes Manually

```ruby
analyzer = Options::ChainAnalyzer.new(index: index_cfg)
analyzer.load_chain_data!

# Get all strikes in range
all_strikes = analyzer.strikes_in_range(25000, 25200, 50)

# Apply filters individually
liquid_strikes = analyzer.filter_by_liquidity(all_strikes, 'ce')
volatile_strikes = analyzer.filter_by_volatility(liquid_strikes, 'ce')
delta_filtered = analyzer.filter_by_delta(volatile_strikes, 'ce')
```

### Volatility Assessment

```ruby
analyzer = Options::ChainAnalyzer.new(index: index_cfg)
analyzer.load_chain_data!

strike = 25000.0
option_type = 'ce'

assessment = analyzer.assess_volatility(strike, option_type)
# => :cheap, :fair, or :expensive

case assessment
when :cheap
  puts "Low IV - good entry opportunity"
when :expensive
  puts "High IV - consider waiting or different strike"
when :fair
  puts "Moderate IV - acceptable"
end
```

### Position Sizing

```ruby
analyzer = Options::ChainAnalyzer.new(index: index_cfg)
analyzer.load_chain_data!

capital = 100_000
option_price = 125.50

# Uses configured risk parameters
lots = analyzer.calculate_position_size(capital, option_price)
# => Calculated based on:
#    - risk_per_trade (default: 1.0%)
#    - max_capital_utilization (default: 10%)

# Override risk parameters
conservative_lots = analyzer.calculate_position_size(
  capital,
  option_price,
  { risk_per_trade: 0.5, max_capital_utilization: 0.05 }
)
```

## Integration with Signal Engine

The analyzer is automatically integrated into `Signal::Engine`:

```ruby
# In Signal::Engine.run_for
picks = Options::ChainAnalyzer.pick_strikes(
  index_cfg: index_cfg,
  direction: final_direction,
  ta_context: ta_result  # TA context passed automatically
)
```

The class method maintains backward compatibility while using the new configurable strategies internally.

## Troubleshooting

### Chain Data Not Loaded

```ruby
analyzer = Options::ChainAnalyzer.new(index: index_cfg)

# Must load chain data before using instance methods
analyzer.load_chain_data!

# Check if loaded
puts analyzer.chain_data.present?  # Should be true
puts analyzer.sorted_strikes&.any?  # Should be true
```

### No Strikes Returned

```ruby
recommendation = analyzer.recommend_strikes_for_signal(:bullish)

if recommendation[:strikes].empty?
  # Check configuration
  puts analyzer.config[:filter_by_liquidity]
  puts analyzer.config[:assess_volatility]
  
  # Try relaxing filters
  relaxed = analyzer.recommend_strikes_for_signal(
    :bullish,
    { offset: 3 }  # Wider range
  )
end
```

### Configuration Not Applied

```ruby
# Verify configuration
puts analyzer.config.inspect

# Check index symbol
puts analyzer.index_symbol  # Should be :nifty, :sensex, or :banknifty

# Check if custom config was applied
puts analyzer.config[:filter_by_liquidity][:min_oi]
```

## Best Practices

1. **Always load chain data** before using instance methods
2. **Use class method** for simple use cases (backward compatible)
3. **Use instance methods** when you need fine-grained control
4. **Override configuration** at runtime for testing/adjustments
5. **Check chain_summary** to verify data loaded correctly

## Examples

See `docs/OPTION_CHAIN_ANALYZER_REFACTORING.md` for detailed refactoring documentation and design decisions.
