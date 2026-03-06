# Orders::EntryManager

## Overview

`Orders::EntryManager` orchestrates entry order placement, validation, and position tracking. It integrates with `Capital::Allocator`, `Entries::EntryGuard`, `Orders::Placer`, `Positions::ActiveCache`, and `Orders::BracketPlacer` to provide comprehensive entry management.

## Purpose

The EntryManager ensures that:
- Entry signals are validated before order placement
- Dynamic risk allocation is applied based on trend strength
- Quantity meets minimum lot size requirements
- Bracket orders (SL/TP) are placed after entry
- Positions are tracked in ActiveCache
- Entry events are emitted via EventBus

## Usage

### Basic Entry Processing

```ruby
entry_manager = Orders::EntryManager.new

result = entry_manager.process_entry(
  signal_result: {
    candidate: {
      security_id: '49081',
      segment: 'NSE_FNO',
      symbol: 'NIFTY-25Jan2024-25000-CE',
      lot_size: 75,
      ltp: 150.5
    }
  },
  index_cfg: { key: 'NIFTY', segment: 'NSE_INDEX', sid: '26000' },
  direction: :bullish
)

# => {
#   success: true,
#   tracker: <PositionTracker>,
#   sl_price: 105.35,
#   tp_price: 240.8,
#   bracket_result: { success: true, ... },
#   risk_pct: nil
# }
```

### With Trend Score (Dynamic Risk Allocation)

```ruby
result = entry_manager.process_entry(
  signal_result: { candidate: pick },
  index_cfg: index_cfg,
  direction: :bullish,
  trend_score: 18.0  # From Signal::TrendScorer
)

# => {
#   success: true,
#   tracker: <PositionTracker>,
#   risk_pct: 0.0375,  # Dynamic risk based on trend_score
#   ...
# }
```

## Entry Processing Flow

1. **Extract Pick/Candidate**: Extracts pick/candidate from signal result
2. **Calculate Dynamic Risk**: Gets risk_pct from `DynamicRiskAllocator` if trend_score provided
3. **Validate Entry**: Calls `Entries::EntryGuard.try_enter()` to:
   - Check exposure limits
   - Check cooldown periods
   - Resolve LTP
   - Calculate quantity via `Capital::Allocator`
   - Place order (or create paper tracker)
4. **Find Tracker**: Locates `PositionTracker` created by EntryGuard
5. **Validate Quantity**: Rejects if quantity < 1 lot-equivalent
6. **Calculate SL/TP**: Calculates stop loss and take profit prices
7. **Add to ActiveCache**: Adds position to in-memory cache
8. **Place Bracket Orders**: Calls `BracketPlacer.place_bracket()`
9. **Emit Event**: Publishes `entry_filled` event via EventBus
10. **Return Result**: Returns success/failure result with all details

## SL/TP Calculation

### Bullish (CE) Positions
- **SL**: `entry_price * 0.70` (30% below entry)
- **TP**: `entry_price * 1.60` (60% above entry)

### Bearish (PE) Positions
- **SL**: `entry_price * 1.30` (30% above entry)
- **TP**: `entry_price * 0.50` (50% below entry, more conservative)

## Integration Points

### With Entries::EntryGuard
- Calls `EntryGuard.try_enter()` for validation and order placement
- EntryGuard handles:
  - Exposure checks
  - Cooldown validation
  - LTP resolution
  - Quantity calculation
  - Order placement (or paper tracker creation)

### With Capital::DynamicRiskAllocator
- Gets `risk_pct` based on `index_key` and `trend_score`
- Logs risk allocation for monitoring
- Includes `risk_pct` in entry_filled event

### With Orders::BracketPlacer
- Calls `BracketPlacer.place_bracket()` after adding to ActiveCache
- Passes calculated SL/TP prices
- Handles bracket placement failures gracefully (logs warning, continues)

### With Positions::ActiveCache
- Adds position with SL/TP levels
- Updates cache with bracket information

### With Core::EventBus
- Publishes `entry_filled` event with:
  - Tracker details
  - Entry price, quantity
  - SL/TP prices
  - Risk percentage (if available)
  - Timestamp

## Quantity Validation

The EntryManager enforces minimum lot size:
- Rejects entries where `quantity < lot_size`
- Logs warning for rejected entries
- Returns failure result with descriptive error

## Return Value

Returns a result hash:

```ruby
{
  success: true/false,
  tracker: <PositionTracker> or nil,
  tracker_id: Integer or nil,
  order_no: String or nil,
  position_data: <PositionData> or nil,
  sl_price: Float,
  tp_price: Float,
  bracket_result: Hash or nil,
  risk_pct: Float or nil,
  error: String or nil
}
```

## Error Handling

- Returns failure result on validation failures
- Returns failure result if tracker not found
- Returns failure result if quantity < 1 lot
- Logs bracket placement failures but continues (non-blocking)
- Catches and logs all StandardError exceptions
- Updates statistics for monitoring

## Statistics

The EntryManager tracks:
- `entries_attempted`: Total entry attempts
- `entries_successful`: Successful entries
- `entries_failed`: Failed entries
- `validation_failures`: EntryGuard validation failures
- `allocation_failures`: Capital allocation failures

## Notes

- EntryGuard handles actual order placement (EntryManager orchestrates)
- Bracket orders are placed after entry (not with entry order)
- Dynamic risk allocation is optional (only if trend_score provided)
- Quantity validation ensures minimum lot size compliance
- All failures are logged with context for debugging

