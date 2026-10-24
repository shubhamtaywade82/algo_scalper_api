# Paper Trading Mode

Complete guide to paper trading mode setup, configuration, and usage.

## Overview

Paper trading mode allows testing the trading system without placing real orders. All order placement is simulated, but the system behaves identically to live trading.

## Configuration

### Enable Paper Trading

Set environment variable:
```bash
PAPER_TRADING=true
```

Or in `config/algo.yml`:
```yaml
paper_trading:
  enabled: true
```

## Features

### Simulated Order Placement
- Orders are logged but not sent to broker
- Position tracking works normally
- PnL calculations use simulated fills

### Real Market Data
- Uses real WebSocket feeds
- Real-time tick data
- Actual option chain data

### Full System Behavior
- Signal generation works normally
- Risk management active
- Exit logic executes
- All services run normally

## Usage

### Starting Paper Trading

1. **Set Environment**
   ```bash
   export PAPER_TRADING=true
   ```

2. **Start Services**
   ```bash
   bin/dev
   ```

3. **Verify Mode**
   ```ruby
   # In Rails console
   AlgoConfig.fetch[:paper_trading][:enabled]
   ```

### Monitoring Paper Trades

1. **Check Logs**
   ```bash
   tail -f log/development.log | grep -i "paper"
   ```

2. **View Positions**
   ```ruby
   PositionTracker.active.where(paper: true)
   ```

3. **Check PnL**
   ```ruby
   PositionTracker.active.sum(:last_pnl_rupees)
   ```

## Paper Trading Console

### Access Console
```bash
bin/rails console
```

### Common Commands

```ruby
# Check paper mode status
AlgoConfig.fetch[:paper_trading][:enabled]

# View paper positions
PositionTracker.active.where(paper: true)

# Simulate order fill
tracker = PositionTracker.find(...)
tracker.mark_active!

# Check paper PnL
PositionTracker.where(paper: true).sum(:last_pnl_rupees)
```

## Testing Strategies

### Strategy Testing Workflow

1. **Enable Paper Mode**
   ```bash
   export PAPER_TRADING=true
   ```

2. **Configure Strategy**
   - Update `config/algo.yml`
   - Set strategy parameters
   - Enable strategy

3. **Run System**
   ```bash
   bin/dev
   ```

4. **Monitor Results**
   - Watch signal generation
   - Monitor entry/exit logic
   - Review PnL performance

5. **Analyze Results**
   - Review trade logs
   - Analyze entry/exit timing
   - Evaluate risk management

## Switching to Live Trading

### Pre-Switch Checklist
- [ ] Paper trading tested successfully
- [ ] Strategy parameters validated
- [ ] Risk limits reviewed
- [ ] Capital allocation verified
- [ ] Exit logic confirmed

### Switch Procedure

1. **Disable Paper Mode**
   ```bash
   unset PAPER_TRADING
   # Or set to false
   export PAPER_TRADING=false
   ```

2. **Verify Configuration**
   ```ruby
   AlgoConfig.fetch[:paper_trading][:enabled]  # Should be false
   ```

3. **Restart Services**
   ```bash
   # Stop current services
   # Restart with live mode
   bin/dev
   ```

4. **Monitor Closely**
   - Watch first few trades
   - Verify order placement
   - Check position tracking
   - Monitor risk limits

## Related Documentation

- [Usage Guide](../guides/usage.md)
- [Configuration Guide](../guides/configuration.md)

