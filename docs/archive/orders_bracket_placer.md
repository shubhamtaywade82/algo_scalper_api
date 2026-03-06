# Orders::BracketPlacer

## Overview

`Orders::BracketPlacer` places and manages SL/TP bracket orders for positions. It ensures fixed NEMESIS V3 bracket levels (SL = 30% below entry, TP = 60% above entry) and tracks peak profit percentage in `Positions::ActiveCache`.

## Purpose

The BracketPlacer ensures that:
- SL is always 30% below entry (entry * 0.70)
- TP is always 60% above entry (entry * 1.60)
- Peak profit percentage is tracked in ActiveCache (initialized to 0.0)
- Bracket levels are updated atomically in ActiveCache
- Bracket events are emitted via EventBus

## Usage

### Basic Bracket Placement

```ruby
bracket_placer = Orders::BracketPlacer.new

result = bracket_placer.place_bracket(
  tracker: tracker,
  sl_price: 105.0,
  tp_price: 240.0,
  reason: 'initial_bracket'
)

# => {
#   success: true,
#   sl_price: 105.0,
#   tp_price: 240.0,
#   reason: 'initial_bracket'
# }
```

### Auto-Calculate SL/TP (NEMESIS V3 Fixed Values)

```ruby
# SL and TP are calculated from entry price if not provided
result = bracket_placer.place_bracket(
  tracker: tracker,  # entry_price = 150.0
  sl_price: nil,    # Will calculate: 150.0 * 0.70 = 105.0
  tp_price: nil     # Will calculate: 150.0 * 1.60 = 240.0
)

# => {
#   success: true,
#   sl_price: 105.0,  # Calculated
#   tp_price: 240.0   # Calculated
# }
```

### Partial Prices (One Provided, One Calculated)

```ruby
# Provide SL, calculate TP
result = bracket_placer.place_bracket(
  tracker: tracker,
  sl_price: 100.0,  # Provided
  tp_price: nil     # Will calculate: 150.0 * 1.60 = 240.0
)

# Calculate SL, provide TP
result = bracket_placer.place_bracket(
  tracker: tracker,
  sl_price: nil,    # Will calculate: 150.0 * 0.70 = 105.0
  tp_price: 250.0   # Provided
)
```

## Bracket Calculation

### NEMESIS V3 Fixed Values

- **SL (Stop Loss)**: `entry_price * 0.70` (30% below entry)
- **TP (Take Profit)**: `entry_price * 1.60` (60% above entry)

### Examples

- **Entry = ₹150.00**:
  - SL = ₹105.00 (150.0 * 0.70)
  - TP = ₹240.00 (150.0 * 1.60)

- **Entry = ₹200.00**:
  - SL = ₹140.00 (200.0 * 0.70)
  - TP = ₹320.00 (200.0 * 1.60)

## Peak Profit Percentage Tracking

The BracketPlacer initializes `peak_profit_pct` to `0.0` when placing brackets. This field is then updated by `ActiveCache` as the position's profit percentage increases:

- Initial: `peak_profit_pct = 0.0`
- Updated: When `pnl_pct` exceeds current `peak_profit_pct`, it's updated
- Used by: TrailingEngine and RiskManager for peak drawdown checks

## Integration Points

### With Positions::ActiveCache
- Updates position with SL/TP and `peak_profit_pct`
- Uses `update_position()` to atomically update bracket levels
- Peak profit percentage is tracked in `PositionData` struct

### With Core::EventBus
- Publishes `bracket_placed` event when bracket is placed
- Publishes `bracket_modified` event when bracket is updated
- Event data includes tracker_id, SL/TP prices, reason, timestamp

## Methods

### `place_bracket(tracker:, sl_price: nil, tp_price: nil, reason: nil)`

Places bracket orders for a position.

**Parameters**:
- `tracker` [PositionTracker]: PositionTracker instance (required)
- `sl_price` [Float, nil]: Stop loss price (nil = calculate: entry * 0.70)
- `tp_price` [Float, nil]: Take profit price (nil = calculate: entry * 1.60)
- `reason` [String, nil]: Reason for bracket placement

**Returns**: Hash with `:success`, `:sl_price`, `:tp_price`, `:error`

**Behavior**:
- Calculates SL/TP from entry price if not provided
- Updates ActiveCache with SL/TP and `peak_profit_pct: 0.0`
- Emits `bracket_placed` event
- Increments statistics counters

### `update_bracket(tracker:, sl_price: nil, tp_price: nil, reason: nil)`

Updates existing bracket orders (modifies ActiveCache).

**Parameters**:
- `tracker` [PositionTracker]: PositionTracker instance (required)
- `sl_price` [Float, nil]: New stop loss price (nil = keep existing)
- `tp_price` [Float, nil]: New take profit price (nil = keep existing)
- `reason` [String, nil]: Reason for modification

**Returns**: Hash with `:success`, `:sl_price`, `:tp_price`, `:error`

**Note**: DhanHQ doesn't support modifying bracket orders directly. This method updates ActiveCache only. Actual order modification would require canceling and replacing (not implemented).

### `move_to_breakeven(tracker:, reason: 'breakeven_lock')`

Moves SL to entry price (breakeven).

**Parameters**:
- `tracker` [PositionTracker]: PositionTracker instance (required)
- `reason` [String]: Reason for breakeven move (default: 'breakeven_lock')

**Returns**: Hash with `:success`, `:sl_price`, `:tp_price`, `:error`

### `move_to_trailing(tracker:, trailing_price:, reason: 'trailing_stop')`

Moves SL to trailing stop price.

**Parameters**:
- `tracker` [PositionTracker]: PositionTracker instance (required)
- `trailing_price` [Float]: Trailing stop price (required)
- `reason` [String]: Reason for trailing move (default: 'trailing_stop')

**Returns**: Hash with `:success`, `:sl_price`, `:tp_price`, `:error`

## Error Handling

- Returns failure result if tracker is nil or not active
- Returns failure result if entry price is invalid
- Returns failure result if calculated SL/TP prices are invalid
- Catches and logs all StandardError exceptions
- Updates statistics for monitoring

## Statistics

The BracketPlacer tracks:
- `brackets_placed`: Total brackets placed
- `brackets_modified`: Total brackets modified
- `brackets_failed`: Failed bracket operations
- `sl_orders_placed`: SL orders placed
- `tp_orders_placed`: TP orders placed

## Notes

- DhanHQ bracket orders are typically placed WITH the entry order (boProfitValue, boStopLossValue)
- This service is primarily for adjustments or separate placement scenarios
- Peak profit percentage is initialized to 0.0 and updated by ActiveCache as profit increases
- Bracket levels are fixed at 30% below (SL) and 60% above (TP) entry for NEMESIS V3
- All bracket updates are atomic (single ActiveCache update call)

