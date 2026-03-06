# Live::TrailingEngine

## Overview

`Live::TrailingEngine` provides per-tick trailing stop management with tiered SL offsets for NEMESIS V3. It updates peak profit percentage, checks for peak-drawdown exits, and applies dynamic stop-loss adjustments based on profit tiers.

## Purpose

The TrailingEngine ensures that:
- Peak profit percentage is tracked and updated as positions become more profitable
- Peak-drawdown exits are triggered immediately when drawdown exceeds threshold (5%)
- Tiered SL offsets are applied based on current profit percentage
- SL is only moved up (trailing up) for long positions
- All updates are atomic and logged for monitoring

## Usage

### Basic Per-Tick Processing

```ruby
trailing_engine = Live::TrailingEngine.new

result = trailing_engine.process_tick(position_data)

# => {
#   peak_updated: true,
#   sl_updated: true,
#   exit_triggered: false,
#   new_sl_price: 110.0,
#   reason: 'sl_updated'
# }
```

### With Peak-Drawdown Check

```ruby
exit_engine = Live::ExitEngine.new(order_router: router)

result = trailing_engine.process_tick(
  position_data,
  exit_engine: exit_engine
)

# If drawdown >= 5%, exit is triggered:
# => {
#   peak_updated: false,
#   sl_updated: false,
#   exit_triggered: true,
#   reason: 'peak_drawdown_exit'
# }
```

## Processing Flow

1. **Peak-Drawdown Check** (FIRST - before any SL adjustments):
   - Calculates drawdown: `peak_profit_pct - current_profit_pct`
   - If drawdown >= 5.0%, triggers immediate exit via ExitEngine
   - Returns early if exit is triggered

2. **Update Peak Profit Percentage**:
   - Compares `current_profit_pct` vs `peak_profit_pct`
   - Updates peak in ActiveCache if current > peak
   - Peak is used for drawdown calculations

3. **Apply Tiered SL Offsets**:
   - Calculates new SL based on current profit % using `TrailingConfig.calculate_sl_price()`
   - Only moves SL if `new_sl > current_sl` (trailing up for long positions)
   - Updates SL via `BracketPlacer.update_bracket()`
   - Updates ActiveCache with new SL

## Tiered SL Offsets

SL offsets are determined by profit percentage tiers (from `Positions::TrailingConfig`):

- **0-5% profit**: SL = entry * 0.85 (-15% offset)
- **5-10% profit**: SL = entry * 0.95 (-5% offset)
- **10-15% profit**: SL = entry * 1.00 (breakeven)
- **15-25% profit**: SL = entry * 1.10 (+10% offset)
- **25-40% profit**: SL = entry * 1.20 (+20% offset)
- **40-60% profit**: SL = entry * 1.30 (+30% offset)
- **60-80% profit**: SL = entry * 1.40 (+40% offset)
- **80-120% profit**: SL = entry * 1.60 (+60% offset)
- **120%+ profit**: SL = entry * 1.60 (+60% offset, capped)

## Peak-Drawdown Exit

The TrailingEngine checks for peak-drawdown **before** any SL adjustments:

- **Threshold**: 5.0% (from `Positions::TrailingConfig::PEAK_DRAWDOWN_PCT`)
- **Calculation**: `drawdown = peak_profit_pct - current_profit_pct`
- **Action**: Immediate market exit via `ExitEngine.execute_exit()`
- **Reason**: `"peak_drawdown_exit (drawdown: X%)"`

This ensures that if a position drops 5% or more from its peak, it exits immediately without waiting for candle close or SL hit.

## Integration Points

### With Positions::ActiveCache
- Reads position data (entry_price, pnl_pct, peak_profit_pct, sl_price)
- Updates `peak_profit_pct` when current exceeds peak
- Updates SL price via `update_position()`

### With Positions::TrailingConfig
- Uses `TrailingConfig.calculate_sl_price()` for tiered SL calculation
- Uses `TrailingConfig.peak_drawdown_triggered?()` for drawdown check
- Uses `TrailingConfig.sl_offset_for()` internally

### With Orders::BracketPlacer
- Calls `BracketPlacer.update_bracket()` to move SL
- Passes reason: `"tiered_trailing (profit: X%)"`

### With Live::ExitEngine
- Calls `ExitEngine.execute_exit()` for peak-drawdown exits
- Passes reason: `"peak_drawdown_exit (drawdown: X%)"`

### With RiskManagerService (Future)
- Will be called per-tick in `RiskManagerService.monitor_loop()`
- Processes each active position from ActiveCache

## Methods

### `process_tick(position_data, exit_engine: nil)`

Main method called per-tick for each position.

**Parameters**:
- `position_data` [PositionData]: Position data from ActiveCache (required)
- `exit_engine` [ExitEngine, nil]: Exit engine for peak-drawdown exits (optional)

**Returns**: Hash with:
- `:peak_updated` [Boolean]: True if peak was updated
- `:sl_updated` [Boolean]: True if SL was updated
- `:exit_triggered` [Boolean]: True if exit was triggered
- `:new_sl_price` [Float, nil]: New SL price (if updated)
- `:reason` [String]: Reason for update or exit
- `:error` [String, nil]: Error message (if failed)

### `check_peak_drawdown(position_data, exit_engine)`

Checks if peak drawdown threshold is breached and triggers exit.

**Parameters**:
- `position_data` [PositionData]: Position data
- `exit_engine` [ExitEngine]: Exit engine instance

**Returns**: Boolean (true if exit was triggered)

### `update_peak(position_data)`

Updates peak profit percentage if current exceeds peak.

**Parameters**:
- `position_data` [PositionData]: Position data

**Returns**: Boolean (true if peak was updated)

### `apply_tiered_sl(position_data)`

Applies tiered SL offsets based on current profit percentage.

**Parameters**:
- `position_data` [PositionData]: Position data

**Returns**: Hash with `:updated`, `:new_sl_price`, `:reason`

## Error Handling

- Returns failure result if position data is invalid
- Handles missing tracker gracefully (logs warning, returns false)
- Catches and logs all StandardError exceptions
- Logs all operations with context for debugging

## Notes

- Peak-drawdown check runs **FIRST** (before SL adjustments) to ensure immediate exit
- SL is only moved up (trailing up) - never down for long positions
- Peak profit percentage is updated in ActiveCache atomically
- All SL updates go through BracketPlacer for consistency
- TrailingEngine is stateless - can be called per-tick without side effects
- Designed to be called by RiskManagerService in a monitoring loop

