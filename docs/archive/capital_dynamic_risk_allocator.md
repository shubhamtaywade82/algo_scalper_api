# Capital::DynamicRiskAllocator

## Overview

`Capital::DynamicRiskAllocator` is a service that dynamically calculates risk percentage based on index and trend strength. It scales the base risk from `Capital::Allocator`'s deployment policy based on the trend score from `Signal::TrendScorer`.

## Purpose

The DynamicRiskAllocator ensures that:
- Higher trend scores result in higher risk allocation (up to 1.5x base risk)
- Lower trend scores result in lower risk allocation (down to 0.5x base risk)
- Risk is capped at reasonable bounds (2x base risk or 10% absolute maximum)
- Base risk is retrieved from existing `Capital::Allocator` deployment policy

## Usage

### Basic Usage

```ruby
allocator = Capital::DynamicRiskAllocator.new

# Get risk percentage for index with trend score
risk_pct = allocator.risk_pct_for(
  index_key: :NIFTY,
  trend_score: 15.0
)

# => 0.035 (example: 3% base risk scaled to 3.5% for trend_score 15)
```

### Without Trend Score

```ruby
# Returns base risk if trend_score is nil
risk_pct = allocator.risk_pct_for(
  index_key: :NIFTY,
  trend_score: nil
)

# => 0.03 (base risk from deployment policy)
```

### With Index-Specific Config

```ruby
config = {
  indices: {
    NIFTY: { risk_pct: 0.04 }
  }
}

allocator = Capital::DynamicRiskAllocator.new(config: config)
risk_pct = allocator.risk_pct_for(
  index_key: :NIFTY,
  trend_score: 18.0
)

# Uses 0.04 as base risk, scales by trend_score
```

## Risk Scaling

The risk is scaled based on trend score (0-21):

### Multiplier Calculation

- **trend_score 0-10.5** (normalized 0.0-0.5):
  - Multiplier: 0.5x to 1.0x (linear)
  - Formula: `0.5 + (normalized_score * 2.0 * 0.5)`

- **trend_score 10.5-21** (normalized 0.5-1.0):
  - Multiplier: 1.0x to 1.5x (linear)
  - Formula: `1.0 + ((normalized_score - 0.5) * 2.0 * 0.5)`

### Examples

- **trend_score = 0**: `base_risk * 0.5` (50% of base risk)
- **trend_score = 7**: `base_risk * 0.833` (83.3% of base risk)
- **trend_score = 10.5**: `base_risk * 1.0` (100% of base risk)
- **trend_score = 15**: `base_risk * 1.25` (125% of base risk)
- **trend_score = 21**: `base_risk * 1.5` (150% of base risk)

## Risk Capping

The scaled risk is capped at:
1. **2x base risk**: Maximum risk cannot exceed 2x the base risk
2. **10% absolute maximum**: Risk cannot exceed 10% regardless of base risk

The final risk is: `min(scaled_risk, 2x_base_risk, 0.10)`

## Integration Points

### With Capital::Allocator
- Uses `Capital::Allocator.deployment_policy()` to get base risk
- Uses `Capital::Allocator.available_cash()` to determine capital band

### With Signal::TrendScorer
- Accepts `trend_score` from `Signal::TrendScorer.compute_trend_score()`
- Trend score range: 0-21 (after removing volume component)

### With EntryManager (Future)
- Will be called by `Orders::EntryManager` before quantity calculation
- Risk percentage will be passed to `Capital::Allocator.qty_for()` (when supported)

## Configuration

### Index-Specific Override

You can override base risk for specific indices:

```ruby
config = {
  indices: {
    NIFTY: { risk_pct: 0.04 },
    BANKNIFTY: { risk_pct: 0.05 }
  }
}

allocator = Capital::DynamicRiskAllocator.new(config: config)
```

### Default Behavior

If no index-specific override is provided, uses `Capital::Allocator.deployment_policy()[:risk_per_trade_pct]` based on account balance.

## Error Handling

- Returns base risk (from deployment policy) on any error
- Logs errors with class context: `[DynamicRiskAllocator] Error message`
- Gracefully handles nil trend_score (returns base risk)

## Notes

- Trend score normalization: `trend_score / 21.0` (clamped to 0-1)
- Multiplier interpolation is linear between key points
- Risk capping ensures safety even with extreme trend scores
- Works with existing `Capital::Allocator` deployment policy bands

