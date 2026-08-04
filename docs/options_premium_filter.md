# Options::PremiumFilter

## Overview

`Options::PremiumFilter` is a service that enforces index-specific premium bands, liquidity checks, and spread validation for option candidates. It integrates with existing `Options::IndexRules` classes (Nifty, Banknifty, Sensex) to apply index-specific validation rules.

## Purpose

The PremiumFilter ensures that option candidates meet minimum quality standards before being considered for entry:

- **Premium Validation**: Ensures premium/LTP is above index-specific minimum
- **Liquidity Check**: Ensures sufficient volume/open interest
- **Spread Validation**: Ensures bid-ask spread is within acceptable range

## Usage

### Basic Validation

```ruby
filter = Options::PremiumFilter.new(index_key: :NIFTY)

candidate = {
  premium: 50.0,
  ltp: 50.0,
  bid: 49.85,
  ask: 50.0,
  volume: 50_000,
  oi: 100_000
}

if filter.valid?(candidate)
  # Candidate passes all checks
end
```

### Detailed Validation

```ruby
result = filter.validate_with_details(candidate)
# => {
#   valid: true,
#   premium_check: true,
#   liquidity_check: true,
#   spread_check: true,
#   premium_value: 50.0,
#   min_premium: 25.0,
#   volume: 50000,
#   min_volume: 30000,
#   spread_pct: 0.003,
#   max_spread_pct: 0.003,
#   reason: "valid"
# }
```

## Index-Specific Rules

The filter automatically loads index-specific rules from `Options::IndexRules`:

### NIFTY
- `MIN_PREMIUM`: 25.0
- `MIN_VOLUME`: 30,000
- `MAX_SPREAD_PCT`: 0.003 (0.3%)

### BANKNIFTY
- `MIN_PREMIUM`: 40.0
- `MIN_VOLUME`: 50,000
- `MAX_SPREAD_PCT`: 0.005 (0.5%)

### SENSEX
- `MIN_PREMIUM`: 30.0
- `MIN_VOLUME`: 20,000
- `MAX_SPREAD_PCT`: 0.003 (0.3%)

## Validation Checks

### Premium Check
- Uses `premium` or `ltp` from candidate
- Must be >= `MIN_PREMIUM` for the index

### Liquidity Check
- Uses `volume` or `oi` from candidate
- Must be >= `MIN_VOLUME` for the index

### Spread Check
- Calculates spread as: `(ask - bid) / ask`
- Must be <= `MAX_SPREAD_PCT` for the index
- Returns `false` if bid/ask are missing or zero

## Integration Points

### With StrikeSelector
The PremiumFilter is designed to be used by `Options::StrikeSelector` to filter candidates:

```ruby
selector = Options::StrikeSelector.new
filter = Options::PremiumFilter.new(index_key: index_key)

candidates.each do |candidate|
  next unless filter.valid?(candidate)
  # Process valid candidate
end
```

### With EntryGuard
The PremiumFilter can be integrated into `Entries::EntryGuard` to add an additional validation layer before entry.

## Error Handling

- Returns `false` for invalid candidates (nil, non-hash)
- Logs errors with class context: `[PremiumFilter] Error message`
- Gracefully handles missing data (returns `false` for missing bid/ask/premium)

## Notes

- Spread calculation matches `IndexRules` formula: `(ask - bid) / ask`
- Premium fallback: Uses `ltp` if `premium` is missing
- Liquidity fallback: Uses `oi` if `volume` is missing
- All validation checks must pass for candidate to be valid

