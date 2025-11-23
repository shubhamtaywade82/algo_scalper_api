# How to Test All Services Are Working

This guide explains how to verify that all services in the trading system are working correctly.

## Quick Health Check (Fastest Method)

**Run a quick health check to verify all services are initialized and can start:**

```bash
rails runner scripts/health_check_all_services.rb
```

**What it checks:**
- ✅ All services are registered in supervisor
- ✅ All services have start/stop methods
- ✅ Services can be instantiated
- ✅ Running status of each service
- ✅ Thread status for threaded services
- ✅ Specific checks for critical services (MarketFeedHub, RiskManager, etc.)

**Output:**
- ✅ Healthy services
- ⚠️  Services with warnings
- ❌ Unhealthy services (with details)

**Exit codes:**
- `0` = All healthy or only warnings
- `1` = Some services are unhealthy

---

## Comprehensive Testing (Recommended for Full Verification)

### Method 1: Run All Service Tests

**Run all service tests with summary:**

```bash
./scripts/test_services/run_all_tests.sh
```

**What it does:**
- Runs all service tests in phases (quick → long-running → integration)
- Shows summary with passed/failed/warnings
- Times out long-running tests after 60s

**Output:**
```
==========================================
  Test Summary
==========================================
✅ Passed: 15
⚠️  Warnings: 2
⏱️  Timed Out: 1
❌ Failed: 0
```

### Method 2: Generate Detailed Test Summary

**Generate a detailed report of all test results:**

```bash
ruby scripts/test_services/test_summary.rb
```

**What it does:**
- Runs all tests automatically
- Categorizes results (Passed/Warnings/Failed)
- Shows error messages for failed tests
- Exits with code 1 if any tests failed (useful for CI/CD)

**Output:**
```
✅ Passing Services
  - redis_tick_cache
  - redis_pnl_cache
  - position_index
  ...

⚠️  Services with Warnings
  - active_cache
  ...

❌ Failing Services
  - capital_allocator
    Error: undefined method 'current_capital'
```

### Method 3: Test Individual Services

**Test a specific service:**

```bash
# Quick tests (no timeout)
ruby scripts/test_services/test_redis_tick_cache.rb
ruby scripts/test_services/test_redis_pnl_cache.rb
ruby scripts/test_services/test_capital_allocator.rb
ruby scripts/test_services/test_position_index.rb
ruby scripts/test_services/test_options_services.rb
ruby scripts/test_services/test_active_cache.rb

# Long-running tests (may need longer timeout)
timeout 120 ruby scripts/test_services/test_market_feed_hub.rb
timeout 120 ruby scripts/test_services/test_signal_scheduler.rb
timeout 120 ruby scripts/test_services/test_risk_manager_service.rb
timeout 120 ruby scripts/test_services/test_trading_supervisor.rb
```

---

## Service Verification Checklist

### ✅ Basic Checks (Health Check)
- [ ] All services registered in supervisor
- [ ] All services have start/stop methods
- [ ] Services can be instantiated
- [ ] No nil service instances

### ✅ Startup Checks (When Running `./bin/dev`)
- [ ] Supervisor starts all services
- [ ] MarketFeedHub connects to WebSocket
- [ ] Watchlist items are subscribed
- [ ] All service threads are running
- [ ] No errors in logs

### ✅ Functionality Checks (Service Tests)
- [ ] Redis tick cache stores/retrieves ticks
- [ ] Redis PnL cache stores/retrieves PnL
- [ ] MarketFeedHub receives ticks
- [ ] Signal scheduler generates signals
- [ ] Entry guard validates entries
- [ ] Risk manager monitors positions
- [ ] Exit engine executes exits
- [ ] Position heartbeat syncs positions
- [ ] Paper PnL refresher updates PnL

### ✅ Integration Checks (End-to-End)
- [ ] Signal → Entry → Position → Exit flow works
- [ ] Tick cache → Risk manager → Trailing engine flow works
- [ ] ActiveCache → RiskManager → ExitEngine flow works

---

## Understanding Test Results

### Success Indicators
- ✅ **Green checkmark** = Service is working correctly
- ✅ **PASSED** = Test completed successfully
- ✅ **YES** = Service is running/connected

### Warning Indicators
- ⚠️  **Yellow warning** = Service works but has warnings
- ⚠️  **Warnings** = Non-critical issues (e.g., no data available)
- ⚠️  **NO** = Service not running (may be expected if not started)

### Error Indicators
- ❌ **Red X** = Service has errors
- ❌ **FAILED** = Test failed
- ❌ **Error** = Exception occurred
- ❌ **NoMethodError** = Method doesn't exist
- ❌ **ArgumentError** = Wrong parameters

---

## Common Issues and Solutions

### Issue: Service Not Found in Supervisor

**Symptoms:**
```
❌ Not found in supervisor
```

**Solution:**
1. Check `config/initializers/trading_supervisor.rb`
2. Verify service is registered
3. Restart server (`./bin/dev` or `rails s`)

### Issue: Service Not Running

**Symptoms:**
```
Running: ❌ NO
Thread: ❌ DEAD
```

**Solution:**
1. Check logs: `tail -f log/development.log`
2. Look for startup errors
3. Verify DhanHQ credentials (for MarketFeedHub)
4. Check if service failed to start

### Issue: Test Timeout

**Symptoms:**
```
⏱️  test_market_feed_hub.rb TIMED OUT
```

**Solution:**
1. Run with longer timeout: `timeout 120 ruby scripts/test_services/test_market_feed_hub.rb`
2. Check if service is actually running
3. Verify network connectivity (for WebSocket tests)

### Issue: Method Not Found

**Symptoms:**
```
❌ undefined method 'method_name' for ClassName
```

**Solution:**
1. Check the actual service implementation
2. Verify method name matches
3. Check if it's a class method vs instance method
4. Update test script if needed

---

## Testing Workflow

### Daily/Quick Check
```bash
# Quick health check (30 seconds)
rails runner scripts/health_check_all_services.rb
```

### Before Deployment
```bash
# Full test suite (5-10 minutes)
./scripts/test_services/run_all_tests.sh
```

### After Code Changes
```bash
# Test specific service
ruby scripts/test_services/test_<service_name>.rb
```

### CI/CD Integration
```bash
# Generate summary with exit code
ruby scripts/test_services/test_summary.rb
# Exit code 1 = failures, 0 = all passed
```

---

## Test Categories

### Phase 1: Quick Tests (Fast, No Dependencies)
- `test_redis_tick_cache.rb` - Tick storage/retrieval
- `test_redis_pnl_cache.rb` - PnL caching
- `test_capital_allocator.rb` - Position sizing
- `test_position_index.rb` - Position index
- `test_options_services.rb` - Options services
- `test_active_cache.rb` - Active cache

### Phase 2: Long-Running Tests (Require Services)
- `test_market_feed_hub.rb` - WebSocket, subscriptions
- `test_signal_scheduler.rb` - Signal generation
- `test_entry_guard.rb` - Entry validation
- `test_exit_engine.rb` - Exit execution
- `test_risk_manager_service.rb` - Risk management
- `test_trading_supervisor.rb` - Supervisor integration
- And more...

### Phase 3: Integration Tests
- `test_integration_flow.rb` - Complete flow test

---

## Prerequisites

### DhanHQ Credentials (Required for Some Tests)
```bash
export CLIENT_ID="your_client_id"
export ACCESS_TOKEN="your_access_token"
# OR
export DHANHQ_CLIENT_ID="your_client_id"
export DHANHQ_ACCESS_TOKEN="your_access_token"
```

### Environment
- Must run in `development` or `production` mode (not `test`)
- Test environment disables DhanHQ API calls
- Set `RAILS_ENV=development` if needed

### Network
- Internet connection required
- Must be able to reach DhanHQ API endpoints
- WebSocket connections require stable network

---

## Quick Reference

```bash
# Quick health check
rails runner scripts/health_check_all_services.rb

# Run all tests
./scripts/test_services/run_all_tests.sh

# Detailed summary
ruby scripts/test_services/test_summary.rb

# Test specific service
ruby scripts/test_services/test_<service_name>.rb

# Test with longer timeout
timeout 120 ruby scripts/test_services/test_<service_name>.rb
```

---

## Next Steps

1. **Start with health check**: `rails runner scripts/health_check_all_services.rb`
2. **If issues found**: Run detailed tests for specific services
3. **Before deployment**: Run full test suite
4. **Monitor in production**: Use health check endpoint (if available)

For more details, see:
- `scripts/test_services/README.md` - Full test documentation
- `scripts/test_services/HOW_TO_IDENTIFY_ISSUES.md` - Troubleshooting guide

