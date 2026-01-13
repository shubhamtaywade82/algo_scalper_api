# Service Testing Guide

This directory contains tools for testing services in the Rails console.

## Quick Start

### 1. Start Rails Console

```bash
bin/rails console
```

### 2. Load the Test Runner

```ruby
load 'lib/testing/service_test_runner.rb'
```

### 3. Run Individual Tests

```ruby
# Test a single service
test_market_feed_hub
test_risk_manager_service
test_tick_cache

# Or run all tests
test_all_services
```

## Available Test Methods

### Independent Services (Singleton/Threaded)

- `test_market_feed_hub` - Tests WebSocket market feed connection
- `test_risk_manager_service` - Tests position monitoring and risk management
- `test_pnl_updater_service` - Tests PnL update batching
- `test_paper_pnl_refresher` - Tests paper position PnL refresh
- `test_exit_engine` - Tests exit order execution
- `test_trailing_engine` - Tests trailing stop logic

### Signal Services

- `test_signal_scheduler` - Tests signal generation loop

### Utility Services (Stateless)

- `test_tick_cache` - Tests in-memory tick cache
- `test_redis_pnl_cache` - Tests Redis PnL cache
- `test_active_cache` - Tests active position cache
- `test_underlying_monitor` - Tests underlying health checks

### Order Services

- `test_order_router` - Tests order routing logic

## Helper Methods

- `show_service_status` - Shows running status of all services
- `show_active_positions` - Lists all active positions
- `monitor_logs(seconds)` - Monitors logs for specified duration

## Testing Workflow

### 1. Check Service Status

```ruby
show_service_status
```

### 2. Test Individual Services

Start with utility services (they have no dependencies):

```ruby
test_tick_cache
test_redis_pnl_cache
test_active_cache
```

Then test independent services:

```ruby
test_market_feed_hub
test_order_router
test_exit_engine
test_trailing_engine
```

Finally test integrated services:

```ruby
test_risk_manager_service
test_pnl_updater_service
test_paper_pnl_refresher
test_signal_scheduler
```

### 3. Observe Logs

Each test method includes automatic log observation, but you can also monitor manually:

```ruby
monitor_logs(30)  # Monitor for 30 seconds
```

### 4. Check Active Positions

```ruby
show_active_positions
```

## What to Look For

### Successful Service Start

- Service reports `running? = true`
- Thread is alive
- No error messages in logs
- Service-specific metrics are updating

### MarketFeedHub

- WebSocket connection established
- Subscribed to watchlist instruments
- Receiving ticks (check logs for tick events)
- Connection health is good

### RiskManagerService

- Monitoring loop is running
- Processing active positions
- PnL updates are happening
- Circuit breaker is in `:closed` state

### Signal::Scheduler

- Generating signals periodically (every 30 seconds)
- Processing indices (NIFTY, BANKNIFTY, SENSEX)
- No errors in signal evaluation

### Cache Services

- Cache size > 0 (if market data available)
- Lookups return valid data
- Updates are working

## Troubleshooting

### Service Won't Start

1. Check if service is already running: `service.running?`
2. Check for errors in logs
3. Verify dependencies are available
4. Check database connection

### No Market Data

1. Ensure MarketFeedHub is running
2. Check if market is open: `TradingSession::Service.market_open?`
3. Verify DhanHQ credentials are set
4. Check WebSocket connection status

### No Active Positions

- This is normal if no trades have been placed
- Some services will skip work if no positions exist
- Use `show_active_positions` to verify

## Environment Considerations

### Paper Mode

- Most services support paper mode
- Paper positions are tracked separately
- Check `paper: true` flag on PositionTracker

### Test Environment

- Services may behave differently in test
- External API calls may be disabled
- Check `ENV['DHANHQ_ENABLED']` setting

## Running Comprehensive Tests

To test all services in sequence:

```ruby
test_all_services
```

This will:
1. Test each service individually
2. Wait for logs between tests
3. Report success/failure for each
4. Provide a summary at the end

## Manual Service Testing

If you prefer to test services manually:

```ruby
# Get service instance
service = Live::MarketFeedHub.instance

# Check status
service.running?
service.connected?

# Start service
service.start!

# Monitor logs in another terminal
tail -f log/development.log

# Stop service
service.stop!
```

## Next Steps

After testing services individually:

1. Test service interactions (e.g., MarketFeedHub → TickCache → ActiveCache)
2. Test error scenarios (disconnect, invalid data, etc.)
3. Test performance under load
4. Test recovery from failures

