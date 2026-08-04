# Signal::IndexSelector

## Overview

`Signal::IndexSelector` selects the best index for trading by computing trend scores for all configured indices using `Signal::TrendScorer`, applying minimum thresholds, and using tie-breakers when scores are close.

## Usage

### Basic Usage

```ruby
selector = Signal::IndexSelector.new(
  config: {
    min_trend_score: 15.0,  # Minimum trend score threshold (default: 15.0)
    primary_tf: '1m',        # Primary timeframe for TrendScorer (default: '1m')
    confirmation_tf: '5m'    # Confirmation timeframe for TrendScorer (default: '5m')
  }
)

result = selector.select_best_index
# => {
#   index_key: :NIFTY,
#   trend_score: 20.0,
#   breakdown: { pa: 5, ind: 6, mtf: 6, vol: 3 },
#   reason: 'highest_trend_score'
# }
```

### Default Configuration

```ruby
selector = Signal::IndexSelector.new
# Uses:
# - min_trend_score: 15.0
# - primary_tf: '1m' (from TrendScorer defaults)
# - confirmation_tf: '5m' (from TrendScorer defaults)
```

## Selection Process

### 1. Score All Indices

For each index in `AlgoConfig.fetch[:indices]`:
- Fetch instrument via `IndexInstrumentCache.instance.get_or_fetch()`
- Create `TrendScorer` with instrument and timeframes
- Compute trend score (0-26)
- Return scored indices with breakdown

### 2. Filter by Minimum Score

Only indices with `trend_score >= min_trend_score` are considered.

### 3. Apply Tie-Breakers

If multiple indices qualify:

1. **Clear Winner**: If score difference >= 2.0, return highest score
2. **Momentum Tie-Breaker**: Compare PA score (higher = better momentum)
3. **Liquidity Tie-Breaker**: Compare IND score (higher = better trend strength)

**Note**: Volume is not used as a tie-breaker since it's not available in OHLC data for indices/underlying spots.

## Return Value

Returns `nil` if:
- No indices configured
- No indices score above minimum threshold
- All scoring fails

Returns hash with:
- `index_key`: Symbol (e.g., `:NIFTY`)
- `trend_score`: Float (0-26)
- `breakdown`: Hash with `{ pa, ind, mtf, vol }` scores
- `reason`: String indicating selection reason

## Integration

This service is used by:
- `Signal::Scheduler` (future) - To select which index to trade
- Entry flow (future) - To determine which index to generate signals for

## Dependencies

- `Signal::TrendScorer` (Step 1) - For computing trend scores
- `IndexInstrumentCache` - For fetching instrument data
- `AlgoConfig.fetch[:indices]` - For index configuration

## Error Handling

The service handles errors gracefully:
- Missing instruments: Skips that index
- Scoring failures: Logs warning and continues
- Configuration errors: Returns `nil`

## Testing

Run tests with:
```bash
bundle exec rspec spec/services/signal/index_selector_spec.rb
```

Test coverage includes:
- Initialization with various configs
- Selection with single qualified index
- Selection with multiple qualified indices
- Tie-breaker scenarios
- Edge cases (no indices, all below threshold, errors)

## Configuration

Minimum trend score can be configured:
- Default: 15.0 (moderate trend strength)
- Recommended: 18.0+ for stronger trends
- Lower: 12.0 for more opportunities (higher risk)

## Notes

- Scores are computed synchronously for all indices
- Tie-breakers are applied in order (volume → momentum → liquidity)
- Selection is deterministic (same scores = same result)
- All scores are rounded to 1 decimal place

