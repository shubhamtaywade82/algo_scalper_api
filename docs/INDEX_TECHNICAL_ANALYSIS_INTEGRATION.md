# Index Technical Analysis Integration

## Overview

This document describes the integration of multi-timeframe technical analysis (TA) into the trading signal generation workflow. The TA step runs **before** signal generation and can filter out low-confidence or neutral market conditions.

## Architecture

### Services

1. **`IndexTechnicalAnalyzer`** (`app/services/index_technical_analyzer.rb`)
   - Performs multi-timeframe technical analysis on a single index
   - Uses DhanHQ TA modules if available, falls back to existing indicator infrastructure
   - Returns signal (`:bullish`, `:bearish`, `:neutral`), confidence score, and bias summary

2. **`MarketAnalyzer`** (`app/services/market_analyzer.rb`)
   - Analyzes multiple indices in parallel
   - Provides consolidated market view and strongest signal across indices

### Integration Points

1. **Signal::Engine** (`app/services/signal/engine.rb`)
   - TA step runs after No-Trade pre-check, before main signal analysis
   - If TA suggests neutral or low confidence, signal generation is skipped
   - TA context is passed to option chain analyzer and stored in TradingSignal metadata

2. **Options::ChainAnalyzer** (`app/services/options/chain_analyzer.rb`)
   - Accepts optional `ta_context` parameter for future enhancements
   - Currently logs TA context for debugging

## Configuration

### algo.yml

```yaml
signals:
  # Index Technical Analysis (TA) Configuration
  enable_index_ta: true # Enable index TA step (default: true)
  ta_timeframes: [5, 15, 60] # Timeframes in minutes for TA analysis (default: [5, 15, 60])
  ta_days_back: 30 # Days of historical data to fetch (default: 30)
  ta_min_confidence: 0.6 # Minimum confidence (0.0-1.0) required to proceed (default: 0.6)
```

### Behavior

- **If `enable_index_ta: false`**: TA step is skipped, signal generation proceeds normally
- **If TA signal is `:neutral`**: Signal generation is skipped
- **If TA confidence < `ta_min_confidence`**: Signal generation is skipped
- **If TA analysis fails**: Warning is logged, signal generation continues (graceful degradation)

## Usage

### Single Index Analysis

```ruby
# Analyze NIFTY
analyzer = IndexTechnicalAnalyzer.new(:nifty)
result = analyzer.call(timeframes: [5, 15, 60], days_back: 30)

if result[:success] && analyzer.success?
  puts "Signal: #{analyzer.signal}"
  puts "Confidence: #{analyzer.confidence}"
  puts "Rationale: #{analyzer.rationale}"
end
```

### Multi-Index Analysis

```ruby
# Analyze multiple indices
market = MarketAnalyzer.new
results = market.call(indices: [:nifty, :sensex, :banknifty])

if results[:success]
  puts "Overall market bias: #{results[:results][:overall][:signal]}"
  puts "Confidence: #{results[:results][:overall][:confidence]}"
end
```

## Fallback Behavior

The system gracefully handles cases where DhanHQ TA modules are not available:

1. **DhanHQ TA modules unavailable**: Falls back to existing indicator infrastructure
   - Uses `instrument.intraday_ohlc` to fetch OHLC data
   - Computes RSI, ADX, MACD, ATR using existing `CandleSeries` methods
   - Generates simple bias summary based on RSI analysis

2. **API failures**: Logs error and continues with fallback or skips TA step

3. **Token expiry**: Detects and notifies via Telegram (using `Concerns::DhanhqErrorHandler`)

## Output Structure

### IndexTechnicalAnalyzer Result

```ruby
{
  index: :nifty,
  symbol: "NIFTY",
  signal: :bullish,  # :bullish, :bearish, or :neutral
  confidence: 0.78,  # 0.0 to 1.0
  indicators: { ... },  # Raw indicator data
  bias_summary: {
    meta: { ... },
    summary: {
      bias: :bullish,
      setup: :buy_on_dip,
      confidence: 0.78,
      rationale: {
        rsi: "Upward momentum across M5–M60",
        macd: "MACD bullish signals dominant",
        adx: "Strong higher timeframe trend",
        atr: "Volatility expansion"
      }
    }
  },
  timestamp: 2025-12-20 14:30:45 +0530,
  error: nil
}
```

## Integration Flow

```
1. Signal::Engine.run_for(index_cfg)
   ↓
2. No-Trade pre-check (Phase 1)
   ↓
3. Index Technical Analysis ← NEW STEP
   ├─ If neutral/low confidence → Skip signal generation
   └─ If bullish/bearish → Continue
   ↓
4. Primary timeframe analysis (Supertrend + ADX)
   ↓
5. Confirmation timeframe analysis (if enabled)
   ↓
6. Option chain analysis (with TA context)
   ↓
7. Entry execution
```

## Design Principles

1. **Graceful Degradation**: System works even if DhanHQ TA modules aren't available
2. **Non-Blocking**: TA failures don't crash the signal generation process
3. **Configurable**: Can be enabled/disabled via config, thresholds are adjustable
4. **Observable**: TA context is logged and stored in TradingSignal metadata
5. **Production-Ready**: Follows existing patterns (ApplicationService, error handling, logging)

## Future Enhancements

1. **Strike Selection**: Use TA context to influence strike selection (e.g., prefer ATM+1 in strong trends)
2. **Position Sizing**: Adjust position size based on TA confidence
3. **Exit Timing**: Use TA context for exit decisions
4. **Market Regime Detection**: Identify volatility regimes from TA analysis

## Testing

To test the integration:

```ruby
# In Rails console
analyzer = IndexTechnicalAnalyzer.new(:nifty)
result = analyzer.call

# Check result
puts result.inspect
puts "Signal: #{analyzer.signal}"
puts "Confidence: #{analyzer.confidence}"

# Test with different indices
[:nifty, :sensex, :banknifty].each do |index|
  analyzer = IndexTechnicalAnalyzer.new(index)
  result = analyzer.call
  puts "#{index}: #{analyzer.signal} (#{analyzer.confidence.round(2)})"
end
```

## Troubleshooting

### TA Analysis Always Returns Neutral

- Check DhanHQ credentials are configured
- Verify TA modules are available in DhanHQ gem
- Check logs for fallback analysis messages
- Adjust `ta_min_confidence` threshold if too strict

### TA Analysis Fails

- Check DhanHQ API connectivity
- Verify index configuration in `INDEX_CONFIG` or `IndexConfigLoader`
- Check logs for specific error messages
- System will gracefully degrade to fallback or skip TA step

### TA Context Not Available in Option Chain

- Verify TA step completed successfully (check logs)
- Check `TradingSignal` metadata for `ta_context` field
- Ensure `Options::ChainAnalyzer.pick_strikes` is called with `ta_context` parameter
