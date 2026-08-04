# Service Test Scripts

This directory contains executable test scripts for each service in the trading system. These scripts verify functionality, check outputs, and test integration between services.

## ⚠️ IMPORTANT: Real API Calls

**These test scripts use ACTUAL DhanHQ API calls** - they are NOT mocked or stubbed.

### What This Means:
- ✅ **Real WebSocket connections** to DhanHQ market feed
- ✅ **Real REST API calls** for orders, positions, funds, option chains
- ✅ **Real market data** from DhanHQ servers (when available)
- ✅ **Real order placement** (if enabled in config)

### Test Data Strategy:
- **Primary**: Scripts attempt to fetch **real data from DhanHQ API** first
- **Fallback**: If API call fails or credentials are missing, scripts use **test data** to verify functionality
- **Output**: Shows whether data came from "API" or "test data" in the logs

### Prerequisites:
1. **DhanHQ Credentials Required:**
   ```bash
   export CLIENT_ID="your_client_id"
   export ACCESS_TOKEN="your_access_token"
   # OR
   export DHAN_CLIENT_ID="your_client_id"
   export DHAN_ACCESS_TOKEN="your_access_token"
   ```

2. **Environment:**
   - Scripts run in `development` or `production` mode (not `test`)
   - Test environment disables DhanHQ API calls
   - Set `RAILS_ENV=development` if needed

3. **Network Access:**
   - Must have internet connection
   - Must be able to reach DhanHQ API endpoints
   - WebSocket connections require stable network

### Services Using Real API Calls:
- `MarketFeedHub` → `DhanHQ::WS::Client` (WebSocket)
- `OrderUpdateHub` → `DhanHQ::WS::Orders::Client` (WebSocket)
- `Orders::Placer` → `DhanHQ::Models::Order.create` (REST API)
- `Capital::Allocator` → `DhanHQ::Models::Funds.fetch` (REST API)
- `Providers::DhanhqProvider` → `DhanHQ::Client` (REST API)
- `Options::DerivativeChainAnalyzer` → Uses `DhanhqProvider` (REST API)
- `Live::PositionSyncService` → `DhanHQ::Models::Position.active` (REST API)

## Quick Start

```bash
# 1. Set DhanHQ credentials (REQUIRED)
export CLIENT_ID="your_client_id"
export ACCESS_TOKEN="your_access_token"

# 2. Ensure you're in development mode (not test)
export RAILS_ENV=development  # Optional, defaults to development

# 3. Run all tests with summary (quick + long-running + integration)
./scripts/test_services/run_all_tests.sh

# 4. Generate detailed summary report
ruby scripts/test_services/test_summary.rb

# 5. Run individual tests
ruby scripts/test_services/test_<service_name>.rb
```

### Credential Check:
The test scripts automatically check for DhanHQ credentials on startup. If credentials are missing, you'll see:
```
⚠️  DhanHQ credentials not found in environment variables!
   Required: CLIENT_ID (or DHAN_CLIENT_ID) and ACCESS_TOKEN (or DHAN_ACCESS_TOKEN)
```

## Identifying Issues

### Method 1: Run All Tests with Summary

```bash
./scripts/test_services/run_all_tests.sh
```

This will:
- **Phase 1**: Run quick tests (no timeout)
- **Phase 2**: Run long-running tests (60s timeout each)
- **Phase 3**: Run integration tests (60s timeout)
- Show a summary with:
  - ✅ Passed tests count
  - ⚠️  Warnings count
  - ⏱️  Timed out tests count
  - ❌ Failed tests count
  - List of failed/timed-out tests

**Note:** Long-running tests may timeout if services are not running. Run them individually with longer timeout if needed.

### Method 2: Generate Detailed Summary Report

```bash
ruby scripts/test_services/test_summary.rb
```

This will:
- Run all tests
- Analyze each test's output
- Categorize results (Passed/Warnings/Failed)
- Show error messages for failed tests
- Exit with code 1 if any tests failed

### Method 3: Check Individual Test Output

Each test script provides clear indicators:

- ✅ **Green checkmark** = Success
- ❌ **Red X** = Error/Failure
- ⚠️  **Yellow warning** = Warning (non-critical)
- ℹ️  **Blue info** = Information

Look for:
- `❌` or `Error` or `NoMethodError` = Service has issues
- `⚠️` = Service works but has warnings
- `✅` = Service is working correctly

### Method 4: Common Error Patterns

**NoMethodError / undefined method**
```
❌ undefined method 'method_name' for ClassName
```
→ Test script is calling a method that doesn't exist. Check the actual service API.

**ArgumentError / missing keyword**
```
❌ ArgumentError - missing keyword: :param_name
```
→ Test script is passing wrong parameters. Check the service method signature.

**LoadError / cannot load such file**
```
❌ cannot load such file -- config/environment
```
→ Path issue. Should be fixed in base.rb.

## Available Tests

### Phase 1: Quick Tests (Fast, No Dependencies)
1. **test_redis_tick_cache.rb** - Tick storage/retrieval
2. **test_redis_pnl_cache.rb** - PnL caching
3. **test_capital_allocator.rb** - Position sizing, capital allocation
4. **test_position_index.rb** - Position index management
5. **test_options_services.rb** - StrikeSelector, IndexRules, DerivativeChainAnalyzer
6. **test_active_cache.rb** - In-memory position cache, SL/TP detection

### Phase 2: Long-Running Tests (60s Timeout)
7. **test_market_feed_hub.rb** - WebSocket, subscriptions, TickCache
8. **test_signal_scheduler.rb** - Signal generation (staggered)
9. **test_entry_guard.rb** - Entry permissions, duplicate prevention
10. **test_exit_engine.rb** - Exit conditions, execution flow
11. **test_paper_pnl_refresher.rb** - Paper PnL refresh cycle
12. **test_pnl_updater_service.rb** - Batch PnL updates
13. **test_position_sync_service.rb** - DhanHQ sync
14. **test_risk_manager_service.rb** - Risk checks and limits
15. **test_orders_services.rb** - OrderRouter, Placer, Gateway, EntryManager, BracketPlacer
16. **test_position_heartbeat.rb** - Position heartbeat service (bulk load, pruner)
17. **test_trading_supervisor.rb** - Trading supervisor integration

### Phase 3: Integration Tests (60s Timeout)
18. **test_integration_flow.rb** - Complete flow: Signals → Entries → Exits

### Utilities
19. **base.rb** - Helper utilities for all tests
20. **test_summary.rb** - Generate detailed test summary report

## Test Output

Each test script provides:
- ✅ Success indicators
- ❌ Error indicators
- ⚠️  Warning indicators
- ℹ️  Information messages
- Detailed output for debugging

## Notes

- Tests are designed to be non-destructive (no actual trades in production)
- Some tests require active watchlist items or positions
- Tests may need to wait for WebSocket connections or data updates
- Press CTRL+C to stop long-running tests

## Troubleshooting

### Test fails with "undefined method"
1. Check the actual service implementation
2. Verify method names match
3. Check if it's a class method vs instance method
4. Update the test script to match the actual API

### Test fails with "missing keyword"
1. Check the service method signature
2. Verify parameter names match
3. Check if parameters are required or optional
4. Update the test script to pass correct parameters

### Test shows warnings but passes
- Warnings are non-critical
- Service is working but may have limitations
- Check the warning message for details

## Adding New Tests

To add a new test script:

1. Create `test_<service_name>.rb` in this directory
2. Include the base helper: `require_relative 'base'`
3. Setup Rails: `ServiceTestHelper.setup_rails`
4. Use helper methods for consistent output
5. Make executable: `chmod +x test_<service_name>.rb`

Example template:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'base'
ServiceTestHelper.setup_rails

ServiceTestHelper.print_header('Service Name Test')

# Your tests here

ServiceTestHelper.print_success('Test completed')
```
