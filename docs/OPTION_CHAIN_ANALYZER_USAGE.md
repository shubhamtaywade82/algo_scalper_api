# Option Chain Analyzer Usage Guide

## Quick Start

### Parameter Requirements Summary

| Parameter       | Required?    | How to Get                                                             | Default/Notes                                  |
| --------------- | ------------ | ---------------------------------------------------------------------- | ---------------------------------------------- |
| `index`         | **Required** | `IndexConfigLoader.load_indices.find { \|cfg\| cfg[:key] == 'NIFTY' }` | Must be a hash with `:key`, `:segment`, `:sid` |
| `data_provider` | **Optional** | `Providers::DhanhqProvider.new` or `nil`                               | Default: `nil` (spot price from chain data)    |
| `config`        | **Optional** | `{}` or hash with strategy overrides                                   | Default: `{}` (uses index-specific defaults)   |

**Minimal Example**:
```ruby
# Only index is required
indices = IndexConfigLoader.load_indices
index_cfg = indices.find { |cfg| cfg[:key] == 'NIFTY' }  # Replace 'NIFTY' with your index
analyzer = Options::ChainAnalyzer.new(index: index_cfg)
```

### Getting Required Parameters

#### 1. Getting `index_cfg` (Required)

The `index_cfg` is an index configuration hash that can be obtained from `IndexConfigLoader`:

```ruby
# Load all indices and select one
indices = IndexConfigLoader.load_indices
index_cfg = indices.find { |cfg| cfg[:key] == 'NIFTY' }  # Replace 'NIFTY' with your index key

# Or get directly by key
index_cfg = IndexConfigLoader.load_indices.find { |cfg| cfg[:key].to_s.upcase == 'NIFTY' }

# Index config format:
# {
#   key: "NIFTY",        # or "SENSEX", "BANKNIFTY", etc.
#   segment: "IDX_I",
#   sid: "13",           # Security ID for the index
#   capital_alloc_pct: 0.30,
#   # ... other config from algo.yml
# }
```

**Alternative**: You can also construct it manually if needed:
```ruby
index_cfg = {
  key: 'NIFTY',      # Replace with your index key
  segment: 'IDX_I',
  sid: '13'          # Replace with your index security ID
}
```

#### 2. Getting `data_provider` (Optional)

The `data_provider` is **optional** and only needed if you want to fetch spot prices via the provider. If omitted, the analyzer will use spot price from chain data.

```ruby
# Option 1: Use Providers::DhanhqProvider (if you need spot price fetching)
require 'providers/dhanhq_provider'
provider = Providers::DhanhqProvider.new

# Option 2: Pass nil (default - spot price comes from chain data)
provider = nil

# Option 3: Create a custom provider (must respond to underlying_spot(index_key))
class CustomProvider
  def underlying_spot(index_key)
    # Your custom spot price fetching logic
    # Returns Float or nil
  end
end
provider = CustomProvider.new
```

**Note**: The `data_provider` is only used for `fetch_spot` method. If you don't need it, you can pass `nil` or omit it entirely.

#### 3. Understanding `config` (Optional)

The `config` parameter is **optional** and allows you to override default configuration at runtime:

```ruby
# Empty config - uses defaults from BEHAVIOR_STRATEGIES and algo.yml
config = {}

# Override specific strategies
config = {
  configure_strike_selection: {
    offset: 3,           # Override strike offset
    include_atm: true,   # Override ATM inclusion
    max_otm: 3          # Override max OTM strikes
  },
  configure_liquidity_filter: {
    min_oi: 200_000,     # Override minimum OI
    min_volume: 100_000  # Override minimum volume
  }
}

# Available config keys (all optional):
# - configure_strike_selection: { offset, include_atm, max_otm }
# - configure_liquidity_filter: { min_oi, min_volume, max_spread_pct }
# - configure_volatility_assessment: { low_iv, high_iv, min_iv, max_iv }
# - configure_position_sizing: { risk_per_trade, max_capital_utilization }
# - configure_delta_filter: { min_delta, time_based }
```

**Configuration Priority** (highest to lowest):
1. `config` parameter (runtime override)
2. Index-specific defaults (from `BEHAVIOR_STRATEGIES`)
3. Global defaults (from `BEHAVIOR_STRATEGIES`)
4. `algo.yml` config (from `option_chain` section)

### Basic Usage (Class Method - Backward Compatible)

```ruby
# Get index config
indices = IndexConfigLoader.load_indices
index_cfg = indices.find { |cfg| cfg[:key] == 'NIFTY' }

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
# Get index config
indices = IndexConfigLoader.load_indices
index_cfg = indices.find { |cfg| cfg[:key] == 'NIFTY' }  # Replace 'NIFTY' with your index

# Option 1: Minimal setup (no data_provider, default config)
analyzer = Options::ChainAnalyzer.new(
  index: index_cfg
)

# Option 2: With data provider (for spot price fetching)
provider = Providers::DhanhqProvider.new
analyzer = Options::ChainAnalyzer.new(
  index: index_cfg,
  data_provider: provider
)

# Option 3: With custom config overrides
analyzer = Options::ChainAnalyzer.new(
  index: index_cfg,
  data_provider: nil,  # Optional - can be omitted
  config: {
    configure_strike_selection: { offset: 3, include_atm: true },
    configure_liquidity_filter: { min_oi: 200_000 }
  }
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
# Get index config first
indices = IndexConfigLoader.load_indices
index_cfg = indices.find { |cfg| cfg[:key] == 'NIFTY' }  # Replace 'NIFTY' with your index

# Create analyzer
analyzer = Options::ChainAnalyzer.new(index: index_cfg)

# Access loaded configuration (values vary by index)
puts analyzer.config[:lot_size]              # e.g., 50 (for NIFTY), 10 (for SENSEX)
puts analyzer.config[:strike_selection]       # { offset: 2, include_atm: true, max_otm: 2 }
puts analyzer.config[:liquidity_filter]      # { min_oi: 100000, min_volume: 50000, max_spread_pct: 3.0 }
puts analyzer.config[:volatility_assessment] # { low_iv: 10.0, high_iv: 30.0, min_iv: 10.0, max_iv: 60.0 }
puts analyzer.config[:position_sizing]       # { risk_per_trade: 0.01, max_capital_utilization: 0.10 }
puts analyzer.config[:delta_filter]          # { min_delta: 0.08, time_based: true }
```

### Override Configuration

```ruby
# Get index config
indices = IndexConfigLoader.load_indices
index_cfg = indices.find { |cfg| cfg[:key] == 'NIFTY' }  # Replace 'NIFTY' with your index

# Override at initialization
custom_analyzer = Options::ChainAnalyzer.new(
  index: index_cfg,
  config: {
    configure_liquidity_filter: {
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
# Get NIFTY config
indices = IndexConfigLoader.load_indices
index_cfg = indices.find { |cfg| cfg[:key] == 'NIFTY' }

# Create analyzer
analyzer = Options::ChainAnalyzer.new(index: index_cfg)
analyzer.load_chain_data!

# Uses NIFTY defaults:
# - Strike selection: offset 2, include ATM
# - Liquidity: min_oi 100k, min_volume 50k
# - IV range: 10-30%

recommendation = analyzer.recommend_strikes_for_signal(:bullish)
```

### SENSEX

```ruby
# Get SENSEX config
indices = IndexConfigLoader.load_indices
index_cfg = indices.find { |cfg| cfg[:key] == 'SENSEX' }

# Create analyzer
analyzer = Options::ChainAnalyzer.new(index: index_cfg)
analyzer.load_chain_data!

# Uses SENSEX defaults:
# - Strike selection: offset 3 (wider range), include ATM
# - Liquidity: min_oi 50k, min_volume 25k
# - IV range: 12-40%

recommendation = analyzer.recommend_strikes_for_signal(:bearish)
```

### BANKNIFTY

```ruby
# Get BANKNIFTY config
indices = IndexConfigLoader.load_indices
index_cfg = indices.find { |cfg| cfg[:key] == 'BANKNIFTY' }

# Create analyzer
analyzer = Options::ChainAnalyzer.new(index: index_cfg)
analyzer.load_chain_data!

# Uses BANKNIFTY defaults:
# - Strike selection: offset 2, exclude ATM
# - Liquidity: min_oi 75k, min_volume 30k
# - IV range: 15-45% (more volatile)

recommendation = analyzer.recommend_strikes_for_signal(:bullish)
```

## Advanced Usage

### Complete Trading Workflow

```ruby
def trading_workflow(index_key, signal_direction, capital = 100_000)
  # 1. Get index config
  indices = IndexConfigLoader.load_indices
  index_cfg = indices.find { |cfg| cfg[:key].to_s.upcase == index_key.to_s.upcase }
  raise "Index not found: #{index_key}" unless index_cfg

  # 2. Create analyzer
  analyzer = Options::ChainAnalyzer.new(index: index_cfg)

  # 3. Load chain data
  analyzer.load_chain_data!

  # 4. Get recommendation
  recommendation = analyzer.recommend_strikes_for_signal(signal_direction)

  return nil unless recommendation[:strikes]&.any?

  # 5. Analyze each recommended strike
  analyses = recommendation[:strikes].map do |strike|
    analyzer.analyze_strike(strike, recommendation[:option_type])
  end

  # 6. Calculate position sizes
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

# Use for any index (pass index key as string or symbol)
nifty_trade = trading_workflow('NIFTY', :bullish)
sensex_trade = trading_workflow('SENSEX', :bearish)
banknifty_trade = trading_workflow('BANKNIFTY', :bullish)
```

### Filtering Strikes Manually

```ruby
# Get index config
indices = IndexConfigLoader.load_indices
index_cfg = indices.find { |cfg| cfg[:key] == 'NIFTY' }

# Create analyzer
analyzer = Options::ChainAnalyzer.new(index: index_cfg)
analyzer.load_chain_data!

# Note: The methods strikes_in_range, filter_by_liquidity, filter_by_volatility,
# and filter_by_delta are not currently implemented. Use recommend_strikes_for_signal
# which applies all filters automatically, or use analyze_strike for individual analysis.
```

### Volatility Assessment

```ruby
# Get index config
indices = IndexConfigLoader.load_indices
index_cfg = indices.find { |cfg| cfg[:key] == 'NIFTY' }  # Replace 'NIFTY' with your index

# Create analyzer
analyzer = Options::ChainAnalyzer.new(index: index_cfg)
analyzer.load_chain_data!

strike = 25000.0  # Replace with your strike price
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
# Get index config
indices = IndexConfigLoader.load_indices
index_cfg = indices.find { |cfg| cfg[:key] == 'NIFTY' }  # Replace 'NIFTY' with your index

# Create analyzer
analyzer = Options::ChainAnalyzer.new(index: index_cfg)
analyzer.load_chain_data!

capital = 100_000
option_price = 125.50  # Replace with your option price

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
# index_cfg is already available from the method parameter
picks = Options::ChainAnalyzer.pick_strikes(
  index_cfg: index_cfg,  # Already available in Signal::Engine context
  direction: final_direction,
  ta_context: ta_result  # TA context passed automatically
)
```

The class method maintains backward compatibility while using the new configurable strategies internally.

**Note**: In `Signal::Engine`, the `index_cfg` is passed as a parameter to `run_for(index_cfg)`, so you don't need to load it separately.

## Troubleshooting

### Chain Data Not Loaded

```ruby
# Get index config
indices = IndexConfigLoader.load_indices
index_cfg = indices.find { |cfg| cfg[:key] == 'NIFTY' }

# Create analyzer
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
# Get index config
indices = IndexConfigLoader.load_indices
index_cfg = indices.find { |cfg| cfg[:key] == 'NIFTY' }  # Replace 'NIFTY' with your index

# Create analyzer with custom config
analyzer = Options::ChainAnalyzer.new(
  index: index_cfg,
  config: { configure_liquidity_filter: { min_oi: 200_000 } }
)

# Verify configuration
puts analyzer.config.inspect

# Check index symbol
puts analyzer.index_symbol  # Should be :nifty, :sensex, or :banknifty

# Check if custom config was applied
puts analyzer.config[:liquidity_filter][:min_oi]  # Should be 200000
```

## Best Practices

1. **Always load chain data** before using instance methods
2. **Use class method** for simple use cases (backward compatible)
3. **Use instance methods** when you need fine-grained control
4. **Override configuration** at runtime for testing/adjustments
5. **Check chain_summary** to verify data loaded correctly

## Quick Reference Example

```ruby
# Complete example from start to finish
# 1. Get index configuration
indices = IndexConfigLoader.load_indices
index_cfg = indices.find { |cfg| cfg[:key] == 'NIFTY' }  # Replace 'NIFTY' with your index

# 2. Create analyzer (minimal - only index required)
analyzer = Options::ChainAnalyzer.new(index: index_cfg)

# 3. Load chain data
success = analyzer.load_chain_data!
unless success
  puts "Failed to load chain data"
  exit
end

# 4. Get chain summary
summary = analyzer.chain_summary
puts "Spot: #{summary[:spot_price]}, ATM: #{summary[:atm_strike]}"

# 5. Get strike recommendation
recommendation = analyzer.recommend_strikes_for_signal(:bullish)
puts "Recommended strikes: #{recommendation[:strikes]}"

# 6. Analyze each strike
recommendation[:strikes].each do |strike|
  analysis = analyzer.analyze_strike(strike, recommendation[:option_type])
  puts "Strike #{strike}: IV=#{analysis[:iv]}, OI=#{analysis[:oi]}, Delta=#{analysis[:delta]}"
end

# 7. Calculate position size
option_price = 125.50
capital = 100_000
lots = analyzer.calculate_position_size(capital, option_price)
puts "Position size: #{lots} lots"
```

## Examples

See `docs/OPTION_CHAIN_ANALYZER_REFACTORING.md` for detailed refactoring documentation and design decisions.
