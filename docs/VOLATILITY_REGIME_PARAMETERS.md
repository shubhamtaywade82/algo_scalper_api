# Volatility Regime-Based Trading Parameters

## Overview

This system implements dynamic, volatility regime-based parameter adaptation for option trading. Parameters (Stop Loss, Take Profit, Trailing Stop, and Time-out) automatically adjust based on:

1. **Volatility Regime**: Determined by VIX levels
   - **High Volatility**: VIX > 20
   - **Medium Volatility**: VIX 15-20
   - **Low Volatility**: VIX < 15

2. **Market Condition**: Determined by trend analysis
   - **Bullish**: Strong upward trend (trend_score >= 14, ADX >= 20)
   - **Bearish**: Strong downward trend (trend_score <= 7, ADX >= 20)
   - **Neutral**: Weak or sideways trend (defaults to bullish for CE trades)

3. **Index**: Different parameters for NIFTY, BANKNIFTY, and SENSEX

## Configuration

Configuration is stored in `config/algo.yml` under `risk.volatility_regimes`:

```yaml
risk:
  volatility_regimes:
    enabled: true
    vix_thresholds:
      high: 20.0
      medium: 15.0
    
    parameters:
      NIFTY:
        high_volatility:
          bullish:
            sl_pct_range: [8, 12]
            tp_pct_range: [18, 30]
            trail_pct_range: [7, 12]
            timeout_minutes: [10, 18]
          bearish:
            sl_pct_range: [8, 12]
            tp_pct_range: [15, 28]
            trail_pct_range: [7, 12]
            timeout_minutes: [10, 18]
        # ... medium_volatility and low_volatility
```

## Services

### 1. `Risk::VolatilityRegimeService`

Detects current volatility regime based on VIX levels.

**Usage:**
```ruby
result = Risk::VolatilityRegimeService.call
# Returns: { regime: :high|:medium|:low, vix_value: Float, regime_name: String }
```

**Features:**
- Fetches VIX from INDIAVIX instrument
- Falls back to ATR-based proxy if VIX unavailable
- Configurable thresholds via `algo.yml`

### 2. `Risk::MarketConditionService`

Determines market condition (bullish/bearish) using trend analysis.

**Usage:**
```ruby
result = Risk::MarketConditionService.call(index_key: 'NIFTY')
# Returns: { condition: :bullish|:bearish|:neutral, trend_score: Float, adx_value: Float, condition_name: String }
```

**Features:**
- Uses `Signal::TrendScorer` for trend score (0-21)
- Requires ADX >= 20 for strong directional bias
- Falls back to neutral if trend is weak

### 3. `Risk::RegimeParameterResolver`

Resolves appropriate trading parameters based on regime and market condition.

**Usage:**
```ruby
result = Risk::RegimeParameterResolver.call(index_key: 'NIFTY')
# Returns: { index_key: String, regime: Symbol, condition: Symbol, parameters: Hash }

# Get specific parameter values (midpoint of range)
resolver = Risk::RegimeParameterResolver.new(index_key: 'NIFTY')
resolver.call
sl_pct = resolver.sl_pct      # Midpoint of sl_pct_range
tp_pct = resolver.tp_pct       # Midpoint of tp_pct_range
trail_pct = resolver.trail_pct # Midpoint of trail_pct_range
timeout = resolver.timeout_minutes # Midpoint of timeout_minutes

# Get random value within range (for dynamic selection)
sl_pct_random = resolver.sl_pct_random
```

**Features:**
- Auto-detects regime and condition if not provided
- Returns parameter ranges from config
- Provides helper methods for midpoint or random selection

## Integration

### Risk Manager Integration

The `Live::RiskManagerService` has been updated to use regime-based parameters:

1. **`enforce_hard_limits`**: Now uses `resolve_parameters_for_tracker` to get regime-based SL/TP for each position
2. **`resolve_parameters_for_tracker`**: Helper method that:
   - Checks if regime-based params are enabled
   - Extracts index key from tracker
   - Calls `RegimeParameterResolver` to get parameters
   - Falls back to default config values if unavailable

**Example Flow:**
```
Position Tracker → Extract Index Key → Resolve Regime & Condition → Get Parameters → Apply SL/TP
```

## Parameter Ranges

### High Volatility (VIX > 20)
- **Wide stops** (8-15% SL) to handle large moves
- **High profit targets** (15-40% TP) to capture big moves
- **Wider trailing stops** (7-15%) to allow for volatility
- **Longer timeouts** (10-20 min) to give trades time to develop

### Medium Volatility (VIX 15-20)
- **Moderate stops** (6-10% SL)
- **Moderate profit targets** (9-25% TP)
- **Moderate trailing stops** (5-10%)
- **Standard timeouts** (8-14 min)

### Low Volatility (VIX < 15)
- **Tight stops** (3-6% SL) to cut losses quickly
- **Small profit targets** (4-10% TP) for scalping
- **Tight trailing stops** (2-4%) to lock in small gains
- **Short timeouts** (3-9 min) to avoid theta decay

## Bullish vs Bearish

Parameters are symmetric for bullish and bearish conditions, with slight variations:

- **Bullish**: Slightly higher TP targets (premiums can run faster in uptrends)
- **Bearish**: Slightly lower TP targets (more cautious in downtrends)

## Fallback Behavior

If regime-based parameters are unavailable:
1. Falls back to default `risk.sl_pct` and `risk.tp_pct` from config
2. Logs warnings but continues operation
3. System remains functional with static parameters

## Monitoring

All services log their operations:
- `[VolatilityRegimeService]` - VIX detection and regime classification
- `[MarketConditionService]` - Trend analysis and condition determination
- `[RegimeParameterResolver]` - Parameter resolution
- `[RiskManager]` - Parameter application in risk checks

## Testing

To test the system:

```ruby
# Test volatility regime detection
regime_result = Risk::VolatilityRegimeService.call
puts "Current regime: #{regime_result[:regime_name]} (VIX: #{regime_result[:vix_value]})"

# Test market condition
condition_result = Risk::MarketConditionService.call(index_key: 'NIFTY')
puts "Market condition: #{condition_result[:condition_name]} (Score: #{condition_result[:trend_score]})"

# Test parameter resolution
params = Risk::RegimeParameterResolver.call(index_key: 'NIFTY')
puts "SL Range: #{params[:parameters][:sl_pct_range]}"
puts "TP Range: #{params[:parameters][:tp_pct_range]}"
```

## Future Enhancements

1. **Dynamic Range Selection**: Use random values within ranges instead of midpoints
2. **Time-of-Day Adjustments**: Different parameters for morning vs afternoon
3. **Event-Based Regimes**: Detect news/events and adjust parameters accordingly
4. **Historical Performance**: Track which parameter sets perform best
5. **VIX Proxy Improvements**: Better ATR-to-VIX conversion algorithms
