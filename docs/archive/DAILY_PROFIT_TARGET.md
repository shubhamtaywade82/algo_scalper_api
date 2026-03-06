# Daily Profit Target Feature

## Overview

The system now includes a **daily profit target** that automatically stops trading when ₹20,000 profit is reached for the day. This prevents overtrading and locks in profits.

## Configuration

In `config/algo.yml`:

```yaml
risk:
  # Daily profit target: Stop trading when daily profit reaches this amount
  max_daily_profit: 20000 # ₹20,000 daily profit target (trading stops when reached)
  # Alternative config key: daily_profit_target (also supported)
```

## How It Works

### 1. Profit Tracking

- **Automatic Recording**: When a position exits, profit/loss is automatically recorded in Redis
- **Global Tracking**: Tracks cumulative daily profit across all indices
- **Net After Fees**: Profit is recorded after broker fees (₹40 per trade)

### 2. Entry Blocking

- **EntryGuard Check**: Before every trade entry, the system checks if daily profit target is reached
- **Automatic Stop**: If daily profit ≥ ₹20,000, all new trades are blocked
- **Logging**: Clear warning messages when trading is blocked due to profit target

### 3. Profit Recording

When a position exits:
- **Profit** (positive PnL): Recorded via `DailyLimits.record_profit()`
- **Loss** (negative PnL): Recorded via `DailyLimits.record_loss()`
- **Index Tracking**: Tracks profit per index and globally

## Implementation Details

### Files Modified

1. **`app/services/live/daily_limits.rb`**
   - Added `record_profit()` method
   - Added `get_daily_profit()` and `get_global_daily_profit()` methods
   - Added daily profit target check in `can_trade?()` method
   - Added Redis keys for profit tracking

2. **`app/models/position_tracker.rb`**
   - Added `record_daily_pnl()` method
   - Called automatically when position exits via `mark_exited!()`

3. **`app/services/entries/entry_guard.rb`**
   - Added daily limits check before trade entry
   - Blocks trading when profit target reached

4. **`config/algo.yml`**
   - Added `max_daily_profit` configuration

## Redis Keys

Daily profit is tracked in Redis with these keys:

- **Per-Index Profit**: `daily_limits:profit:{date}:{index_key}`
  - Example: `daily_limits:profit:2025-12-18:NIFTY`
- **Global Profit**: `daily_limits:profit:{date}:global`
  - Example: `daily_limits:profit:2025-12-18:global`

All keys have a TTL of 25 hours (auto-expire after trading day).

## Example Flow

1. **Trade 1**: Profit ₹2,000 → Daily profit: ₹2,000
2. **Trade 2**: Profit ₹1,500 → Daily profit: ₹3,500
3. **Trade 3**: Profit ₹3,000 → Daily profit: ₹6,500
4. **... continues ...**
5. **Trade 10**: Profit ₹2,500 → Daily profit: ₹20,000
6. **Trade 11**: **BLOCKED** - Daily profit target reached
7. **System stops trading** for the day

## Log Messages

### When Profit Target Reached

```
[DailyLimits] ⚠️ DAILY PROFIT TARGET REACHED: ₹20000.00 >= ₹20000 - Trading will be stopped for the day
[EntryGuard] Trading blocked for NIFTY: daily_profit_target_reached (daily profit: ₹20000.00)
```

### When Profit Recorded

```
[DailyLimits] Recorded profit for NIFTY: ₹2000.00 (daily: ₹2000.00, global: ₹2000.00)
```

## Integration with Broker Fees

- Profit is recorded **net after broker fees** (₹40 per trade)
- Daily profit target of ₹20,000 is **net profit**, not gross
- This ensures you actually have ₹20k profit after all fees

## Testing

To test the daily profit target:

1. Set a lower target for testing:
   ```yaml
   risk:
     max_daily_profit: 1000 # ₹1,000 for testing
   ```

2. Make a profitable trade

3. Check logs for:
   - `[DailyLimits] Recorded profit for...`
   - `[DailyLimits] ⚠️ DAILY PROFIT TARGET REACHED...`
   - `[EntryGuard] Trading blocked...`

4. Verify no new trades are allowed

## Reset

Daily profit counters reset automatically:
- **TTL**: 25 hours (keys expire automatically)
- **Manual Reset**: Call `DailyLimits.new.reset_daily_counters`

## Notes

- Profit target is **global** (across all indices)
- Losses are tracked separately (don't reduce profit)
- Active positions don't count toward daily profit until exited
- System automatically resumes trading next day (after TTL expires)
