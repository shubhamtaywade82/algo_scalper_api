# Options::StrikeSelector

## Overview

`Options::StrikeSelector` is an enhanced service that selects the best option strike for a given index and direction, with support for ATM/1OTM/2OTM selection based on trend strength. It integrates with `DerivativeChainAnalyzer`, `PremiumFilter`, and `IndexRules` to provide comprehensive strike selection.

## Purpose

The StrikeSelector ensures that:
- Only ATM, 1OTM, or 2OTM strikes are selected (no deeper OTM)
- OTM depth is determined by trend strength (higher trend scores allow deeper OTM)
- Selected strikes pass premium, liquidity, and spread validation
- Returns normalized instrument hash ready for order placement

## Usage

### Basic Selection

```ruby
selector = Options::StrikeSelector.new

# Select strike with default (ATM only)
result = selector.select(
  index_key: :NIFTY,
  direction: :bullish
)

# => {
#   index: "NIFTY",
#   strike: 25000,
#   option_type: "CE",
#   ltp: 150.5,
#   otm_depth: 0,        # 0=ATM, 1=1OTM, 2=2OTM
#   max_otm_allowed: 0,
#   ...
# }
```

### With Trend Score

```ruby
# Allow 1OTM if trend_score >= 12
result = selector.select(
  index_key: :NIFTY,
  direction: :bullish,
  trend_score: 15.0
)
# => { ..., otm_depth: 1, max_otm_allowed: 1 }

# Allow 2OTM if trend_score >= 18
result = selector.select(
  index_key: :NIFTY,
  direction: :bullish,
  trend_score: 20.0
)
# => { ..., otm_depth: 2, max_otm_allowed: 2 }
```

## Trend Score Thresholds

The OTM depth is determined by trend score thresholds:

- **trend_score < 12**: ATM only (max_otm_allowed = 0)
- **trend_score >= 12**: ATM + 1OTM (max_otm_allowed = 1)
- **trend_score >= 18**: ATM + 1OTM + 2OTM (max_otm_allowed = 2)

These thresholds are defined as constants:
- `TREND_THRESHOLD_1OTM = 12.0`
- `TREND_THRESHOLD_2OTM = 18.0`

## Strike Selection Process

1. **Get Spot Price**: Fetches current spot price for the index
2. **Calculate ATM Strike**: Uses `IndexRules.atm(spot)` to round to nearest strike
3. **Determine Allowed Strikes**: Based on trend_score and direction:
   - Bullish (CE): ATM, ATM+increment, ATM+2*increment
   - Bearish (PE): ATM, ATM-increment, ATM-2*increment
4. **Filter Candidates**: Only candidates with strikes in allowed list
5. **Validate**: Applies `IndexRules` validation + `PremiumFilter` validation
6. **Return Best**: Returns first valid candidate (already sorted by score)

## Integration Points

### With DerivativeChainAnalyzer
- Uses `DerivativeChainAnalyzer.select_candidates()` to get scored candidates
- Candidates are already sorted by score (best first)

### With PremiumFilter
- Applies `PremiumFilter.valid?()` to each candidate
- Ensures premium, liquidity, and spread meet index-specific requirements

### With IndexRules
- Uses `IndexRules.atm()` for ATM calculation
- Uses `IndexRules.candidate_strikes()` to infer strike increment
- Uses `IndexRules.valid_liquidity?()`, `valid_spread?()`, `valid_premium?()`

### With TrendScorer
- Accepts `trend_score` parameter from `Signal::TrendScorer`
- Uses trend score to determine allowed OTM depth

## Return Value

Returns a normalized instrument hash with:

```ruby
{
  index: "NIFTY",                    # Index key
  exchange_segment: "NSE_FNO",      # Exchange segment
  security_id: "49081",             # Security ID
  strike: 25000,                    # Strike price
  option_type: "CE",                # "CE" or "PE"
  ltp: 150.5,                       # Last traded price
  lot_size: 75,                     # Lot size
  multiplier: 1,                    # Multiplier
  derivative: <Derivative>,         # Derivative record
  derivative_id: 123,               # Derivative ID
  symbol: "NIFTY-25Jan2024-25000-CE",
  iv: 20.5,                         # Implied volatility
  oi: 500000,                       # Open interest
  score: 0.85,                      # Selection score
  reason: "High score",             # Selection reason
  otm_depth: 0,                     # 0=ATM, 1=1OTM, 2=2OTM
  max_otm_allowed: 0                # Maximum OTM depth allowed
}
```

## Error Handling

- Returns `nil` if no valid strike found
- Logs warnings for empty candidates or filtered-out strikes
- Catches and logs `SelectionError` (returns nil)
- Catches and logs `StandardError` (returns nil)

## Notes

- Strike increment is inferred from `IndexRules.candidate_strikes()` (e.g., 50 for NIFTY, 100 for BANKNIFTY)
- Float comparison uses tolerance (0.01) for strike matching
- LTP resolution: tries tick cache first, falls back to candidate LTP
- PremiumFilter validation is applied after IndexRules validation
- Only ATM/1OTM/2OTM strikes are considered (deeper OTM are filtered out)

