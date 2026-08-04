# Trading Time Restrictions

## Overview

This feature allows you to block trading during specific time periods within the trading session based on profitability analysis results. This helps avoid trading during periods when the supertrend + ADX strategy has historically been unprofitable.

## How It Works

1. **Run Analysis**: Use `analyze_positions_by_time_intervals.rb` to identify non-profitable time periods
2. **Configure Restrictions**: Add the non-profitable periods to `config/algo.yml`
3. **Enable Feature**: Set `trading_time_restrictions.enabled: true` in config
4. **Automatic Blocking**: The system will automatically block entries during restricted periods

## Configuration

### Step 1: Analyze Positions

Run the analysis script to identify non-profitable periods:

```bash
# Default 30-minute intervals
rails runner scripts/analyze_positions_by_time_intervals.rb

# Custom interval (e.g., 15 minutes)
rails runner scripts/analyze_positions_by_time_intervals.rb 15
```

### Step 2: Review Results

The script will show:
- **Profitable Time Periods**: When supertrend + ADX strategy works well
- **Unprofitable Time Periods**: When strategy has been losing money
- **Hourly Analysis**: Best and worst trading hours
- **High Probability Windows**: Periods with ≥70% win rate

### Step 3: Configure Restrictions

Edit `config/algo.yml` and add non-profitable periods:

```yaml
trading_time_restrictions:
  enabled: true  # Set to true to enable restrictions
  avoid_periods:
    - "10:30-11:30"  # Example: Block trading from 10:30 AM to 11:30 AM
    - "14:00-15:00"  # Example: Block trading from 2:00 PM to 3:00 PM
```

### Step 4: Restart Services

After updating the config, restart the trading services for changes to take effect.

## Time Format

- **Format**: `"HH:MM-HH:MM"` (24-hour format, IST timezone)
- **Examples**:
  - `"10:30-11:30"` - Blocks 10:30 AM to 11:30 AM
  - `"14:00-15:00"` - Blocks 2:00 PM to 3:00 PM
  - `"09:15-10:00"` - Blocks 9:15 AM to 10:00 AM

## How It Blocks Trading

When a restricted period is active:

1. **EntryGuard Check**: `TradingSession::Service.entry_allowed?` checks if current time is in a restricted period
2. **Entry Blocked**: If restricted, entry is blocked with reason: `"Entry blocked: Trading restricted during {period} (non-profitable period)"`
3. **Logging**: The block is logged for monitoring

## Example Workflow

### 1. Run Analysis

```bash
rails runner scripts/analyze_positions_by_time_intervals.rb 30
```

**Output Example:**
```
❌ UNPROFITABLE TIME PERIODS (Supertrend + ADX Strategy)
------------------------------------------------------------
  1. 10:30 | PnL: ₹-5,234.50 | Trades: 12 | Win Rate: 25.0%
  2. 14:00 | PnL: ₹-3,891.20 | Trades: 8 | Win Rate: 37.5%
```

### 2. Update Config

Based on analysis, update `config/algo.yml`:

```yaml
trading_time_restrictions:
  enabled: true
  avoid_periods:
    - "10:30-11:00"  # Block first 30 minutes of unprofitable period
    - "14:00-14:30"  # Block first 30 minutes of unprofitable period
```

### 3. Verify

Check logs to confirm restrictions are working:

```
[EntryGuard] Entry blocked: Trading restricted during 10:30-11:00 (non-profitable period)
```

## Best Practices

1. **Start Conservative**: Begin with blocking only the worst periods
2. **Monitor Results**: Track if blocking improves overall profitability
3. **Adjust Gradually**: Add more periods based on continued analysis
4. **Regular Review**: Re-run analysis weekly/monthly to update restrictions
5. **Test First**: Use paper trading to test restrictions before going live

## Disabling Restrictions

To temporarily disable restrictions without removing config:

```yaml
trading_time_restrictions:
  enabled: false  # Set to false to disable
  avoid_periods:
    - "10:30-11:30"
    - "14:00-15:00"
```

## Notes

- Restrictions only apply to **new entries** - existing positions are not affected
- Restrictions work within the normal trading session (9:20 AM - 3:15 PM IST)
- The system checks restrictions in real-time during entry attempts
- Multiple periods can be configured
- Periods can overlap (most restrictive wins)

## Troubleshooting

### Restrictions Not Working

1. Check `enabled: true` in config
2. Verify time format is correct (`"HH:MM-HH:MM"`)
3. Check logs for parsing errors
4. Restart services after config changes

### Too Many Blocks

1. Review analysis results - may be too aggressive
2. Reduce number of restricted periods
3. Use smaller time windows (e.g., 15 minutes instead of 1 hour)
4. Focus on worst periods only

### Not Enough Blocks

1. Re-run analysis with different intervals
2. Add more periods based on analysis
3. Consider blocking entire hours if consistently unprofitable

