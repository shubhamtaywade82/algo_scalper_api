# Live::DailyLimits

## Overview

`Live::DailyLimits` enforces per-index and global daily loss limits and trade frequency limits for NEMESIS V3. It uses Redis for persistent counters with auto-lock behavior, preventing trading when limits are exceeded.

## Purpose

The DailyLimits service ensures that:
- Daily loss limits are enforced per-index and globally
- Trade frequency limits are enforced per-index and globally
- Counters persist across service restarts (via Redis)
- Auto-lock behavior prevents trading when limits are exceeded
- Counters reset automatically at the start of each trading day

## Usage

### Check if Trading is Allowed

```ruby
daily_limits = Live::DailyLimits.new

result = daily_limits.can_trade?(index_key: 'NIFTY')

# => {
#   allowed: true,
#   reason: nil
# }

# Or if limit exceeded:
# => {
#   allowed: false,
#   reason: 'daily_loss_limit_exceeded',
#   daily_loss: 6000.0,
#   max_daily_loss: 5000.0,
#   index_key: 'NIFTY'
# }
```

### Record a Loss

```ruby
daily_limits.record_loss(index_key: 'NIFTY', amount: 500.0)

# Increments both per-index and global loss counters
# Logs: "[DailyLimits] Recorded loss for NIFTY: ₹500.00 (daily: ₹1500.00, global: ₹2000.00)"
```

### Record a Trade

```ruby
daily_limits.record_trade(index_key: 'NIFTY')

# Increments both per-index and global trade counters
```

### Reset Daily Counters

```ruby
daily_limits.reset_daily_counters

# Deletes all daily limit keys for today
# Called at start of trading day (scheduled job)
```

## Configuration

Limits are configured in `config/algo.yml` under the `risk` section:

```yaml
risk:
  max_daily_loss_pct: 5000.0        # ₹5000 max loss per index
  max_global_daily_loss_pct: 10000.0 # ₹10000 max loss globally
  max_daily_trades: 10               # 10 trades per index
  max_global_daily_trades: 20        # 20 trades globally
```

Alternative config key names are also supported:
- `daily_loss_limit_pct` (instead of `max_daily_loss_pct`)
- `global_daily_loss_limit_pct` (instead of `max_global_daily_loss_pct`)
- `daily_trade_limit` (instead of `max_daily_trades`)
- `global_daily_trade_limit` (instead of `max_global_daily_trades`)

## Limit Checks

The `can_trade?` method checks limits in this order:

1. **Per-Index Daily Loss Limit**: If daily loss for index >= max_daily_loss_pct → reject
2. **Global Daily Loss Limit**: If global daily loss >= max_global_daily_loss_pct → reject
3. **Per-Index Trade Frequency Limit**: If daily trades for index >= max_daily_trades → reject
4. **Global Trade Frequency Limit**: If global daily trades >= max_global_daily_trades → reject

If all checks pass, trading is allowed.

## Redis Keys

Daily limits are stored in Redis with the following key patterns:

- **Per-Index Loss**: `daily_limits:loss:{date}:{index_key}`
  - Example: `daily_limits:loss:2024-01-15:NIFTY`
- **Global Loss**: `daily_limits:loss:{date}:global`
  - Example: `daily_limits:loss:2024-01-15:global`
- **Per-Index Trades**: `daily_limits:trades:{date}:{index_key}`
  - Example: `daily_limits:trades:2024-01-15:NIFTY`
- **Global Trades**: `daily_limits:trades:{date}:global`
  - Example: `daily_limits:trades:2024-01-15:global`

All keys have a TTL of 25 hours (slightly longer than 24h to handle timezone edge cases).

## Integration Points

### With Entries::EntryGuard

```ruby
# In EntryGuard.try_enter()
daily_limits = Live::DailyLimits.new
check_result = daily_limits.can_trade?(index_key: index_cfg[:key])

unless check_result[:allowed]
  Rails.logger.warn("[EntryGuard] Trading blocked: #{check_result[:reason]}")
  return false
end

# ... proceed with entry ...
```

### With Live::RiskManagerService

```ruby
# In RiskManagerService when position exits with loss
if pnl < 0
  daily_limits.record_loss(index_key: index_key, amount: pnl.abs)
end
```

### With Orders::EntryManager

```ruby
# In EntryManager.process_entry() after successful entry
daily_limits.record_trade(index_key: index_cfg[:key])
```

## Methods

### `can_trade?(index_key:)`

Checks if trading is allowed for the given index.

**Parameters**:
- `index_key` [Symbol, String]: Index key (e.g., :NIFTY, :BANKNIFTY)

**Returns**: Hash with:
- `:allowed` [Boolean]: True if trading is allowed
- `:reason` [String, nil]: Reason for rejection (if not allowed)
- Additional fields based on rejection reason (e.g., `:daily_loss`, `:max_daily_loss`)

### `record_loss(index_key:, amount:)`

Records a loss for the given index.

**Parameters**:
- `index_key` [Symbol, String]: Index key
- `amount` [Float, BigDecimal]: Loss amount in rupees (positive value)

**Returns**: Boolean (true if recorded successfully)

### `record_trade(index_key:)`

Records a trade for the given index.

**Parameters**:
- `index_key` [Symbol, String]: Index key

**Returns**: Boolean (true if recorded successfully)

### `reset_daily_counters`

Resets all daily counters (called at start of trading day).

**Returns**: Boolean (true if reset successfully)

### `get_daily_loss(index_key)`

Gets daily loss for index.

**Parameters**:
- `index_key` [Symbol, String]: Index key

**Returns**: Float (daily loss amount)

### `get_global_daily_loss`

Gets global daily loss.

**Returns**: Float (global daily loss amount)

### `get_daily_trades(index_key)`

Gets daily trade count for index.

**Parameters**:
- `index_key` [Symbol, String]: Index key

**Returns**: Integer (daily trade count)

### `get_global_daily_trades`

Gets global daily trade count.

**Returns**: Integer (global daily trade count)

## Error Handling

- Returns `{ allowed: false, reason: 'redis_unavailable' }` if Redis is unavailable
- Returns `false` for `record_loss`/`record_trade` if Redis is unavailable
- Catches and logs all StandardError exceptions
- Defaults to 0.0 for loss and 0 for trades if keys don't exist

## Notes

- Index keys are normalized to uppercase strings (e.g., `:NIFTY` → `'NIFTY'`)
- Loss amounts are stored as floats in Redis
- Trade counts are stored as integers in Redis
- TTL is set to 25 hours to handle timezone edge cases
- Counters persist across service restarts (via Redis)
- Auto-lock behavior: trading is blocked when limits are exceeded
- Reset should be called at start of trading day (scheduled job)

