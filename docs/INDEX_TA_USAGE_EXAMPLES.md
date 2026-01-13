# Index Technical Analyzer Usage Examples

## Basic Usage

### Standard Analysis (Uses Configured Defaults)

```ruby
# Analyze NIFTY with default configuration
analyzer = IndexTechnicalAnalyzer.new(:nifty)
result = analyzer.call

if result[:success] && analyzer.success?
  puts "Signal: #{analyzer.signal}"           # :bullish, :bearish, or :neutral
  puts "Confidence: #{analyzer.confidence}"    # 0.0 to 1.0
  puts "Rationale: #{analyzer.rationale}"      # Hash with analysis details
end
```

### Runtime Override

```ruby
# Override timeframes and days_back
analyzer = IndexTechnicalAnalyzer.new(:nifty)
result = analyzer.call(
  timeframes: [5, 15, 30, 60],  # Override default [5, 15, 60]
  days_back: 45                  # Override default 30
)
```

### Custom Configuration

```ruby
# Create analyzer with custom configuration
custom_analyzer = IndexTechnicalAnalyzer.new(:nifty, custom_config: {
  configure_indicator_periods: {
    rsi: 21,        # Use 21-period RSI instead of default 14
    adx: 21,        # Use 21-period ADX instead of default 14
    macd_fast: 12,
    macd_slow: 26,
    macd_signal: 9,
    atr: 14
  },
  configure_bias_thresholds: {
    rsi_oversold: 25,           # More sensitive (default: 30)
    rsi_overbought: 75,         # More sensitive (default: 70)
    rsi_bullish_threshold: 35,  # Lower threshold (default: 40)
    rsi_bearish_threshold: 65,  # Higher threshold (default: 60)
    min_timeframes_for_signal: 2,
    confidence_base: 0.5        # Higher base confidence (default: 0.4)
  }
})

result = custom_analyzer.call
```

## Index-Specific Examples

### NIFTY Analysis

```ruby
nifty_analyzer = IndexTechnicalAnalyzer.new(:nifty)
result = nifty_analyzer.call

# Uses NIFTY-specific defaults:
# - Timeframes: [5, 15, 60]
# - RSI thresholds: oversold 30, overbought 70
# - Standard indicator periods
```

### SENSEX Analysis (More Sensitive)

```ruby
sensex_analyzer = IndexTechnicalAnalyzer.new(:sensex)
result = sensex_analyzer.call

# Uses SENSEX-specific defaults:
# - Timeframes: [5, 15, 30, 60] (includes 30min)
# - RSI thresholds: oversold 25, overbought 75 (more sensitive)
# - Higher base confidence: 0.5
# - Slower API throttling: 3.0 seconds
```

### BANKNIFTY Analysis

```ruby
banknifty_analyzer = IndexTechnicalAnalyzer.new(:banknifty)
result = banknifty_analyzer.call

# Uses BANKNIFTY-specific defaults:
# - Timeframes: [5, 15, 60]
# - Standard thresholds (same as NIFTY)
```

## Advanced Usage

### Accessing Configuration

```ruby
analyzer = IndexTechnicalAnalyzer.new(:nifty)
puts analyzer.config[:timeframes]              # [5, 15, 60]
puts analyzer.config[:indicator_periods][:rsi]  # 14
puts analyzer.config[:bias_thresholds]         # Hash of thresholds
puts analyzer.config[:api_settings]            # Hash of API settings
```

### Complete Analysis Result

```ruby
analyzer = IndexTechnicalAnalyzer.new(:nifty)
result = analyzer.call

if result[:success]
  full_result = analyzer.result
  # Returns:
  # {
  #   index: :nifty,
  #   symbol: "NIFTY",
  #   signal: :bullish,
  #   confidence: 0.78,
  #   indicators: { ... },
  #   bias_summary: { ... },
  #   timestamp: 2025-12-20 14:30:45 +0530,
  #   error: nil
  # }
end
```

### Error Handling

```ruby
analyzer = IndexTechnicalAnalyzer.new(:nifty)
result = analyzer.call

unless result[:success]
  puts "Error: #{analyzer.error}"
  # Common errors:
  # - "DhanHQ credentials not configured"
  # - API errors (handled gracefully with fallback)
end
```

## Integration with Signal Engine

The analyzer is automatically integrated into `Signal::Engine`:

```ruby
# In Signal::Engine.run_for(index_cfg)
# TA step runs automatically before signal generation

# Configuration in algo.yml:
signals:
  enable_index_ta: true
  ta_timeframes: [5, 15, 60]
  ta_days_back: 30
  ta_min_confidence: 0.6

# If TA suggests neutral or low confidence, signal generation is skipped
```

## Multi-Index Analysis

```ruby
# Use MarketAnalyzer for multiple indices
market = MarketAnalyzer.new
results = market.call(indices: [:nifty, :sensex, :banknifty])

if results[:success]
  results[:results].each do |index, analysis|
    next if index == :overall
    
    puts "#{index}: #{analysis[:signal]} (#{analysis[:confidence].round(2)})"
  end
  
  puts "Overall market bias: #{results[:results][:overall][:signal]}"
  puts "Confidence: #{results[:results][:overall][:confidence].round(2)}"
end
```

## Configuration Strategies

### Strategy 1: Conservative (Higher Confidence Required)

```ruby
conservative_config = {
  configure_bias_thresholds: {
    rsi_oversold: 25,
    rsi_overbought: 75,
    rsi_bullish_threshold: 35,
    rsi_bearish_threshold: 65,
    min_timeframes_for_signal: 3,  # Require 3 timeframes
    confidence_base: 0.6            # Higher base confidence
  }
}

analyzer = IndexTechnicalAnalyzer.new(:nifty, custom_config: conservative_config)
```

### Strategy 2: Aggressive (More Signals)

```ruby
aggressive_config = {
  configure_bias_thresholds: {
    rsi_oversold: 35,
    rsi_overbought: 65,
    rsi_bullish_threshold: 45,
    rsi_bearish_threshold: 55,
    min_timeframes_for_signal: 1,  # Only need 1 timeframe
    confidence_base: 0.3            # Lower base confidence
  }
}

analyzer = IndexTechnicalAnalyzer.new(:nifty, custom_config: aggressive_config)
```

### Strategy 3: Custom Timeframes

```ruby
# Focus on shorter timeframes for scalping
scalping_config = {
  select_timeframes: [1, 3, 5]  # 1min, 3min, 5min only
}

analyzer = IndexTechnicalAnalyzer.new(:nifty, custom_config: scalping_config)
result = analyzer.call
```

## Troubleshooting

### Check Configuration

```ruby
analyzer = IndexTechnicalAnalyzer.new(:nifty)
puts analyzer.config.inspect  # See all loaded configuration
```

### Verify Index Symbol

```ruby
# Normalize index symbol
analyzer = IndexTechnicalAnalyzer.new('NIFTY')  # String works
analyzer = IndexTechnicalAnalyzer.new(:NIFTY)   # Symbol works
analyzer = IndexTechnicalAnalyzer.new('nifty')  # Case-insensitive

puts analyzer.index_symbol  # :nifty (normalized)
```

### Fallback Behavior

```ruby
# If DhanHQ TA modules aren't available, fallback is used automatically
analyzer = IndexTechnicalAnalyzer.new(:nifty)
result = analyzer.call

# Check if fallback was used
if analyzer.bias_summary&.dig(:meta, :source) == :fallback
  puts "Using fallback analysis (DhanHQ TA modules not available)"
end
```
