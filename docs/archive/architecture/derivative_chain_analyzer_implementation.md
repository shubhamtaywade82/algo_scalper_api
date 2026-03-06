# DerivativeChainAnalyzer Implementation Summary

## Overview

The `Options::DerivativeChainAnalyzer` has been implemented to provide a repository-compatible option chain analysis system that uses existing `Derivative` records instead of raw option chain APIs.

## Key Features

### ✅ Uses Existing Infrastructure

- **Derivative Records**: Uses existing `Derivative` model records (no duplicate storage)
- **Tick Cache Integration**: Merges data from `Live::TickCache` and `Live::RedisTickCache`
- **DhanHQ API**: Uses existing `Instrument.fetch_option_chain` method (rate-limited, cached)
- **IndexInstrumentCache**: Uses existing cache for index instruments

### ✅ Data Merging Strategy

The analyzer merges three data sources:

1. **Derivative Records** (Database):
   - `security_id`, `segment`, `strike_price`, `option_type`, `expiry_date`, `lot_size`

2. **API Option Chain** (DhanHQ):
   - `implied_volatility`, `greeks` (delta, gamma, theta, vega), `previous_close_price`

3. **Live Tick Data** (WebSocket/Redis):
   - `ltp`, `bid`, `ask`, `oi`, `oi_change`, `volume`

**Priority**: Live tick data > API data > Derivative defaults

### ✅ Scoring System

Heuristic scoring based on:
- **Open Interest** (40% weight): Log-normalized, higher OI = better
- **Spread** (25% weight): Lower spread = better (inverted)
- **IV** (20% weight): Prefers moderate IV (15-25% sweet spot)
- **Volume** (15% weight): Log-normalized, higher volume = better
- **ATM Bonus** (0-20%): Extra points for strikes near ATM

**Important**: Scoring weights are heuristic and must be backtested.

## Integration

### Signal Scheduler

The `Signal::Scheduler` has been updated to use `DerivativeChainAnalyzer`:

```ruby
analyzer = Options::DerivativeChainAnalyzer.new(
  index_key: index_cfg[:key],
  expiry: nil, # Auto-selects nearest expiry
  config: chain_cfg
)

candidates = analyzer.select_candidates(limit: 2, direction: :bullish)
```

### Strategy Engines

All existing strategy engines work seamlessly:

- `OpenInterestBuyingEngine` - Uses OI change from tick data
- `MomentumBuyingEngine` - Uses day_high and RSI from tick data
- `BtstMomentumEngine` - Uses VWAP and volume from tick data
- `SwingOptionBuyingEngine` - Uses HTF Supertrend and EMAs from tick data

### Candidate Format

Candidates returned by `DerivativeChainAnalyzer` include:

```ruby
{
  derivative: #<Derivative>,      # Full ActiveRecord record
  security_id: "12345",           # For order placement
  segment: "NSE_FNO",             # Exchange segment
  strike: 25000.0,                 # Strike price
  type: "CE",                      # Option type
  score: 0.85,                     # Combined score
  ltp: 150.5,                      # Last traded price
  iv: 22.5,                        # Implied volatility (%)
  oi: 500000,                      # Open interest
  oi_change: 10000,                # OI change
  spread: 0.02,                    # Bid-ask spread (2%)
  delta: 0.45,                     # Delta (if available)
  lot_size: 50,                    # Lot size
  symbol: "NIFTY-Nov2024-25000-CE", # Human-readable symbol
  derivative_id: 123,              # Derivative record ID
  reason: "Score:0.85 IV:22.5% OI:500000..." # Selection reason
}
```

## Configuration

### `config/algo.yml`

```yaml
chain_analyzer:
  max_candidates: 2
  strike_distance_pct: 0.02      # Max 2% from spot
  min_oi: 10000                  # Minimum OI
  min_iv: 5.0                     # Minimum IV (%)
  max_iv: 60.0                    # Maximum IV (%)
  max_spread_pct: 0.03            # Max 3% spread
  scoring_weights:
    oi: 0.4                       # OI weight (40%)
    spread: 0.25                  # Spread weight (25%)
    iv: 0.2                       # IV weight (20%)
    volume: 0.15                  # Volume weight (15%)
```

## Usage Example

```ruby
# In a strategy or service
analyzer = Options::DerivativeChainAnalyzer.new(
  index_key: :NIFTY,
  expiry: nil, # Auto-select nearest
  config: AlgoConfig.fetch[:chain_analyzer]
)

candidates = analyzer.select_candidates(limit: 1, direction: :bullish)
return if candidates.empty?

best = candidates.first
derivative = best[:derivative]

# Place order using derivative record
order = derivative.buy_option!(
  qty: best[:lot_size],
  index_cfg: @index_cfg,
  meta: { reason: best[:reason] }
)
```

## Benefits

1. **No Duplicate Storage**: Uses existing Derivative records
2. **Type Safety**: Full ActiveRecord records with validations
3. **Easy Order Placement**: Direct access to `security_id`, `segment`, `lot_size`
4. **Cached & Rate-Limited**: Respects DhanHQ rate limits via Instrument caching
5. **Real-Time Data**: Merges live ticks for up-to-date LTP/OI
6. **Backward Compatible**: Works with existing strategy engines

## Important Notes

### Scoring Function

- **Heuristic**: Must be backtested before production use
- **Weights**: Default weights are starting points only
- **Adjustment**: Tune based on historical performance and market conditions

### Data Quality

- **Provider Quality**: Noisy or stale OI/volume will degrade ranking
- **WebSocket Feed**: Ensure OI/volume are populated reliably
- **Rate Limits**: Cache option chain (5s-30s), use incremental WS updates

### Risk Management

- **Thin Strikes**: Always check OI and volume before placing orders
- **Lot Size**: Enforce exchange lot sizes (handled by Derivative records)
- **IV Units**: IV is in percent (e.g., 20.5 = 20.5%)

## Testing

```bash
# Test the analyzer
bundle exec rspec spec/services/options/derivative_chain_analyzer_spec.rb

# Test integration
bundle exec rspec spec/integration/options_buying_strategies_spec.rb
```

## Files Created/Modified

1. **Created**: `app/services/options/derivative_chain_analyzer.rb`
2. **Modified**: `app/services/signal/scheduler.rb` - Uses DerivativeChainAnalyzer
3. **Modified**: `config/algo.yml` - Added chain_analyzer configuration
4. **Created**: `docs/options_buying_strategies.md` - Full documentation
5. **Created**: `docs/derivative_chain_analyzer_implementation.md` - This file

## Next Steps

1. **Backtesting**: Implement backtesting for scoring weights
2. **IV Rank**: Add IV rank calculation for better filtering
3. **Greeks Analysis**: Use delta/gamma/theta for better selection
4. **Multi-Expiry**: Support weekly + monthly expiry selection
5. **Strategy-Specific Filters**: Allow each strategy to specify its own chain filters

