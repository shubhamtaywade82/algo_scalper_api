# SMC Scanner Supervisor Integration

## Overview

The SMC + AVRZ Scanner has been integrated into the `TradingSystem::Supervisor` flow, allowing it to run as a managed service alongside other trading services like `Signal::Scheduler` and `RiskManagerService`.

## Architecture

### Service Pattern

The SMC Scanner follows the same pattern as `Signal::Scheduler`:

```ruby
# Service implements start/stop methods
class Smc::Scanner
  def start
    # Starts periodic scanning loop
  end

  def stop
    # Gracefully stops scanning loop
  end

  def running?
    # Returns true if scanner is active
  end
end
```

### Integration Points

1. **Bootstrap Registration** (`lib/trading_system/bootstrap.rb`)
   - Scanner is registered as `:smc_scanner` service
   - Automatically started/stopped with other services

2. **Trading Daemon** (`lib/trading_system/daemon.rb`)
   - Scanner starts automatically when daemon starts (if market is open)
   - Scanner stops automatically when daemon stops
   - Respects market closed status (skips cycles when market is closed)

3. **Supervisor Lifecycle**
   - Starts with `supervisor.start_all` when market is open
   - Stops with `supervisor.stop_all` on shutdown
   - Can be started/stopped individually: `supervisor[:smc_scanner].start`

## Features

### Market-Aware Operation

- **Market Open**: Runs periodic scans every 5 minutes (configurable)
- **Market Closed**: Skips scan cycles, sleeps until market opens
- **Dynamic Market Status**: Re-checks market status before each index to handle market closing during processing

### Expiry Filtering

- Only scans indices with expiry <= 7 days (configurable via `signals.max_expiry_days`)
- Filters out indices with distant expiries to focus on active trading opportunities

### Rate Limiting

- 2 second delay between processing different indices
- 1 second delay between candle fetches
- Automatic rate limit error handling with 5 second backoff

### Error Handling

- Graceful error handling per index (continues with next index on error)
- Rate limit detection and backoff
- Thread-safe start/stop operations

## Configuration

### Period (Scan Interval)

**Default**: 5 minutes (300 seconds)

**Configuration Options** (in priority order):

1. **Constructor Parameter** (for testing/custom instances):
   ```ruby
   Smc::Scanner.new(period: 180) # 3 minutes
   ```

2. **Config File** (`config/algo.yml`):
   ```yaml
   smc:
     scanner_period_seconds: 300  # 5 minutes
   ```

3. **Environment Variable**:
   ```bash
   SMC_SCANNER_PERIOD=300  # 5 minutes
   ```

4. **Default**: 300 seconds (5 minutes)

### Expiry Filtering

Configured via `config/algo.yml`:

```yaml
signals:
  max_expiry_days: 7  # Only scan indices with expiry <= 7 days
```

## Usage

### Automatic (Supervisor Flow)

When you start the trading daemon:

```bash
ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon
```

The SMC Scanner will:
- Start automatically when market is open
- Run periodic scans every 5 minutes
- Stop automatically when daemon stops
- Skip cycles when market is closed

### Manual Control

```ruby
# In Rails console
supervisor = Rails.application.config.x.trading_supervisor

# Start scanner manually
supervisor[:smc_scanner].start

# Check if running
supervisor[:smc_scanner].running?  # => true

# Stop scanner
supervisor[:smc_scanner].stop
```

### Health Check

```ruby
# Check scanner health
supervisor.health_check[:smc_scanner]  # => true/false
```

## Service Lifecycle

### Startup Sequence

When `trading:daemon` starts:

1. **Market Check**: `TradingSession::Service.market_closed?`
2. **If Market Open**:
   - `supervisor.start_all` is called
   - All services start, including `:smc_scanner`
   - Scanner begins periodic loop
3. **If Market Closed**:
   - Only `:market_feed` starts (WebSocket connection)
   - Scanner does NOT start (will start when market opens)

### Runtime Behavior

- **Market Open**: Scanner runs periodic scans
- **Market Closes**: Scanner detects market closed, skips cycles, sleeps
- **Market Reopens**: Scanner automatically resumes scanning

### Shutdown Sequence

When daemon receives INT/TERM signal:

1. `supervisor.stop_all` is called
2. Scanner thread receives stop signal
3. Current scan cycle completes (if in progress)
4. Thread joins gracefully (2 second timeout)
5. Thread killed if doesn't finish in time

## Comparison: Service vs Job

### Before (SolidQueue Job)

- Required separate `bin/jobs` process
- Scheduled via `config/recurring.yml`
- Database-backed scheduling
- Separate process management

### After (Supervisor Service)

- Integrated with trading daemon
- Single process management
- Automatic start/stop with market status
- No separate job queue needed

### When to Use Each

**Use Supervisor Service** (Recommended):
- When running trading daemon (`trading:daemon`)
- When you want unified service management
- When you want market-aware operation
- When you want automatic start/stop

**Use SolidQueue Job** (Alternative):
- When NOT running trading daemon
- When you want separate process management
- When you need database-backed scheduling
- When you want web UI for job monitoring

## Benefits

1. **Unified Management**: All trading services managed together
2. **Market Awareness**: Automatically respects market hours
3. **Resource Efficiency**: No separate process needed
4. **Lifecycle Management**: Automatic start/stop with daemon
5. **Health Monitoring**: Included in supervisor health checks
6. **Graceful Shutdown**: Proper thread cleanup on stop

## Migration Notes

### If You Were Using SolidQueue Job

The SolidQueue job (`SmcScannerJob`) can still be used independently. Both can run simultaneously if needed, but typically you'd use one or the other:

- **Supervisor Service**: For integrated trading daemon
- **SolidQueue Job**: For standalone operation

### Disabling SolidQueue Job

If you want to use only the Supervisor service:

1. Remove or comment out `smc_scanner` from `config/recurring.yml`
2. Reload recurring tasks: `bundle exec rake solid_queue:load_recurring`
3. Restart SolidQueue if running

### Enabling Both

Both can run simultaneously, but this may cause duplicate scans. Not recommended unless you have a specific use case.

## Logging

Scanner logs follow the pattern:

```
[Smc::Scanner] Starting scan cycle for 3 indices...
[Smc::Scanner] NIFTY: call
[Smc::Scanner] BANKNIFTY: no_trade
[Smc::Scanner] SENSEX: put
[Smc::Scanner] Scan cycle completed, sleeping for 300s
[Smc::Scanner] Market closed - skipping cycle
```

## Thread Safety

- All operations are thread-safe via mutex
- Multiple start calls are idempotent
- Stop operations are graceful with timeout
- Thread name: `'smc-scanner'` (for debugging)
