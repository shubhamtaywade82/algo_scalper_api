# WebSocket Connection Test Script

## Overview

This script tests the WebSocket connection and verifies that LTPs (Last Traded Price) can be retrieved for subscribed instruments. It's useful for post-deployment verification and debugging WS connectivity issues.

## Features

- ✅ Checks if WebSocket hub is running
- ✅ Attempts to start hub if not running
- ✅ **Market hours detection** - Detects weekend/holidays and market open/close times
- ✅ **Smart expectations**:
  - **Market hours (9:15 AM - 3:30 PM IST)**: Expects live ticks (multiple ticks)
  - **After market hours/weekend**: Requires at least one tick to verify WebSocket connection is working
- ✅ Subscribes to test instruments
- ✅ Listens for incoming tick data
- ✅ Verifies LTP retrieval from multiple cache sources:
  - `Live::TickCache` (in-memory)
  - `Live::RedisPnlCache` (Redis-backed)
  - Live tick data (received during test)
- ✅ Provides detailed test report with success/failure status

## Usage

### Method 1: Rails Runner (Recommended)

```bash
# Test all instruments from config/algo.yml
rails runner lib/tasks/ws_connection_test.rb

# Test specific instruments
rails runner lib/tasks/ws_connection_test.rb NIFTY,BANKNIFTY

# Test with custom segment and wait time
rails runner lib/tasks/ws_connection_test.rb NIFTY --segment=IDX_I --wait=20
```

### Method 2: Rake Task

```bash
# Test all instruments from config
rake test:ws

# Test specific instruments
rake test:ws[NIFTY,BANKNIFTY]

# Test with segment and wait time
rake test:ws[NIFTY,IDX_I,20]
```

### Method 3: Ruby Console

```ruby
# In Rails console
load 'lib/tasks/ws_connection_test.rb'

# Run test
WsConnectionTest.run
WsConnectionTest.run(instruments: 'NIFTY,BANKNIFTY', wait_seconds: 20)
```

## Arguments

- `instruments` (optional): Comma-separated list of instrument keys (e.g., `NIFTY,BANKNIFTY`)
  - If not provided, uses instruments from `config/algo.yml`
- `segment` (optional, default: `IDX_I`): Exchange segment to use
- `wait_seconds` (optional, default: 15): How long to wait for tick data

## Example Output

### During Market Hours

```
================================================================================
WebSocket Connection & LTP Test
================================================================================

Configuration:
  Segment: IDX_I
  Wait time: 15 seconds
  Instruments: NIFTY,BANKNIFTY

Market Status:
  Trading Day: ✅ Yes
  Market Hours: Market Open (9:15 AM - 3:30 PM IST)
  Expectation: Live ticks expected (multiple ticks during wait period)

[1/5] Checking WebSocket Hub Status...
✅ WebSocket hub is running

[2/5] Determining test instruments...
✅ Found 2 instrument(s) to test:
   - NIFTY (IDX_I:13)
   - BANKNIFTY (IDX_I:25)

[3/5] Subscribing to instruments...
   ✅ Subscribed: NIFTY (IDX_I:13)
   ✅ Subscribed: BANKNIFTY (IDX_I:25)

[4/5] Waiting 15 seconds for tick data...
   (Listening for incoming ticks...)
   📊 Tick received: IDX_I:13 → LTP: 24123.45
   📊 Tick received: IDX_I:25 → LTP: 57776.35

[4/5] Waiting 15 seconds for tick data...
   (Listening for live ticks during market hours...)
   ⚠️  During market hours: Expecting multiple live ticks
   📊 Tick received: IDX_I:13 → LTP: 24123.45
   📊 Tick received: IDX_I:25 → LTP: 57776.35

[5/5] Verifying LTP retrieval from cache...
   ✅ NIFTY: LTP = 24123.45 (Live tick received)
   ✅ BANKNIFTY: LTP = 57776.35 (Live tick received)

================================================================================
Test Summary
================================================================================

WebSocket Hub: ✅ Running
Market Status: Market Open (9:15 AM - 3:30 PM IST)
Instruments Tested: 2
Instruments with LTP: 2
Success Rate: 2/2
Live Ticks Received: 2/2

Detailed Results:
  ✅ NIFTY:
     Subscribed: Yes
     Tick Received: Yes
     TickCache LTP: 24123.45
     RedisCache LTP: 24123.45
     ✅ Final LTP: 24123.45 (from TickCache (in-memory))
  ✅ BANKNIFTY:
     Subscribed: Yes
     Tick Received: Yes
     TickCache LTP: 57776.35
     RedisCache LTP: 57776.35
     ✅ Final LTP: 57776.35 (from TickCache (in-memory))

================================================================================
✅ ALL TESTS PASSED
================================================================================
```

## Exit Codes

- `0`: All tests passed
- `1`: Some tests failed or errors occurred

### After Market Hours / Weekend

```
Market Status:
  Trading Day: ❌ No (Weekend/Holiday)
  Market Hours: Weekend/Holiday (Market Closed)
  Expectation: At least one stale tick required to verify WebSocket connection (no live ticks)

[4/5] Waiting 15 seconds for tick data...
   (Market closed - verifying WebSocket connection with stale ticks...)
   ⚠️  After market hours: Need at least one tick to verify connection
   📊 Tick received: IDX_I:13 → LTP: 24123.45
   📊 Tick received: IDX_I:25 → LTP: 57776.35

[5/5] Verifying LTP retrieval from cache...
   ✅ NIFTY: LTP = 24123.45 (Stale tick received (market closed))
   ✅ BANKNIFTY: LTP = 57776.35 (Stale tick received (market closed))

Test Summary:
Market Status: Post-Market (After 3:30 PM)
Instruments Tested: 2
Instruments with LTP: 2
Success Rate: 2/2
Ticks Received (stale/cached): 2/2

================================================================================
✅ ALL TESTS PASSED
================================================================================
```

## Troubleshooting

### "WebSocket hub is NOT running"

The test will attempt to start the hub automatically. If it fails, check:

1. **Credentials are configured**:
   ```bash
   # Check if credentials are set
   echo $CLIENT_ID
   echo $DHANHQ_ACCESS_TOKEN
   ```

   The script now automatically checks for credentials and reports if they're missing.

2. **WebSocket connection issues**:
   If you see errors like:
   ```
   [DhanHQ::WS] DISCONNECT -> {:RequestCode=>12}
   [DhanHQ::WS] close 1000
   [DhanHQ::WS] close 1006
   ```

   This indicates the WebSocket is connecting but immediately disconnecting. Possible causes:
   - **Invalid credentials**: Verify `CLIENT_ID` and `DHANHQ_ACCESS_TOKEN` are correct
   - **Expired access token**: Regenerate access token from DhanHQ developer portal
   - **Network/firewall**: Ensure outbound WebSocket connections (port 443/80) are allowed
   - **DhanHQ service issues**: Check DhanHQ status page or support
   - **Market closed**: Some DhanHQ endpoints may reject connections outside market hours

3. **Manual start attempt**:
   ```ruby
   # In Rails console
   Live::MarketFeedHub.instance.start!
   # Check if running
   Live::MarketFeedHub.instance.running?
   ```

### "No LTP found in any cache"

Possible causes:
1. Instruments not subscribed successfully
2. WebSocket connection issues
3. Market is closed AND no stale ticks received (connection problem)
4. Increase `wait_seconds` to give more time for ticks

### "No ticks received - WebSocket connection may not be working"

**Critical Issue**: Even during non-market hours, we expect at least one tick to verify the WebSocket connection is working.

If this occurs:
1. **Verify hub is running**: `Live::MarketFeedHub.instance.running?`
2. **Check credentials**: Ensure `CLIENT_ID` and `DHANHQ_ACCESS_TOKEN` are set and valid
3. **Review logs**: Look for WebSocket connection/disconnection messages
4. **Check subscriptions**: Verify instruments are properly subscribed:
   ```ruby
   # In Rails console
   hub = Live::MarketFeedHub.instance
   hub.subscribe(segment: 'IDX_I', security_id: '13')
   ```
5. **Restart hub**: Try stopping and starting again:
   ```ruby
   Live::MarketFeedHub.instance.stop!
   Live::MarketFeedHub.instance.start!
   ```

### "Could not start WebSocket hub (start! returned false)"

This indicates `MarketFeedHub#start!` returned `false`, which can happen when:
- An exception was caught during startup (check logs for error details)
- `enabled?` returned false (credentials missing - now checked and reported automatically)
- WebSocket client failed to initialize or connect

The script now provides detailed diagnostics:
- ✅ Checks credentials before attempting to start
- ✅ Catches and reports exceptions with error messages
- ✅ Provides troubleshooting suggestions

### "Could not find instrument"

Check that:
- Instrument exists in database: `Instrument.find_by(symbol_name: 'NIFTY')`
- Security ID is correct in `config/algo.yml`
- Segment matches the instrument's exchange segment

## Integration with CI/CD

```bash
# In your deployment script
if rails runner lib/tasks/ws_connection_test.rb --segment=IDX_I --wait=10; then
  echo "✅ WS connection test passed"
else
  echo "❌ WS connection test failed"
  exit 1
fi
```

