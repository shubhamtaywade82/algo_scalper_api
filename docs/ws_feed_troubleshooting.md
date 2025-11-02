# WebSocket Market Feed Troubleshooting Guide

## Quick Diagnostics

Run the diagnostic tool to get a comprehensive status report:

```bash
# Using rake task
bundle exec rake ws:diagnostics

# Or directly
bundle exec rails runner "load 'lib/tasks/ws_feed_diagnostics.rb'"
```

This will show:
- Hub running/connection status
- Credentials configuration
- Last tick received
- Connection errors
- Feed health status
- Actionable recommendations

## Enhanced Monitoring in MarketFeedHub

The `MarketFeedHub` now includes enhanced monitoring and diagnostics:

### New Methods

#### `connected?`
Returns `true` if the WebSocket is actually connected (not just started).

```ruby
hub = Live::MarketFeedHub.instance
hub.connected?  # => true/false
```

#### `health_status`
Returns a hash with connection health information:

```ruby
hub.health_status
# => {
#   running: true,
#   connected: true,
#   connection_state: :connected,
#   started_at: 2025-11-02 23:00:00 UTC,
#   last_tick_at: 2025-11-02 23:05:30 UTC,
#   ticks_received: true,
#   last_error: nil,
#   watchlist_size: 3
# }
```

#### `diagnostics`
Returns comprehensive diagnostic information including credentials status:

```ruby
hub.diagnostics
# => {
#   hub_status: {...},
#   credentials: {
#     client_id: "✅ Set",
#     access_token: "✅ Set"
#   },
#   mode: :quote,
#   enabled: true,
#   last_tick: "5.2 seconds ago",
#   last_error_details: nil
# }
```

## Connection Event Monitoring

The hub now automatically tracks:
- **Connection events**: Logs when WebSocket connects/disconnects
- **Errors**: Captures and logs WebSocket errors
- **Tick activity**: Updates `last_tick_at` timestamp on each tick
- **Feed health**: Integrates with `FeedHealthService` to track feed staleness

### Event Handlers

**Note:** The DhanHQ WebSocket client only supports `:tick` events. Connection monitoring is handled via:

- `:tick` - Market data tick received (supported by DhanHQ client)
  - Updates `@connection_state` to `:connected`
  - Updates `@last_tick_at` timestamp
  - Marks FeedHealthService as healthy

Connection state is inferred from:
- **Tick reception** - First tick marks connection as `:connected`
- **Time-based fallback** - `connected?` checks if ticks received within 30 seconds
- **Explicit stop** - `stop!` sets state to `:disconnected`

The DhanHQ client handles reconnection internally - we track connection health via tick activity.

## Common Issues and Solutions

### Issue: Hub Not Starting

**Symptoms:**
- `hub.running?` returns `false`
- `hub.start!` returns `false`
- No errors in logs

**Diagnosis:**
```ruby
hub = Live::MarketFeedHub.instance
puts hub.diagnostics
```

**Solutions:**
1. Check credentials:
   ```ruby
   ENV['DHANHQ_CLIENT_ID']
   ENV['DHANHQ_ACCESS_TOKEN']
   ```
2. Verify credentials are valid and not expired
3. Check network connectivity to DhanHQ servers
4. Review application logs for startup errors

### Issue: Connection Closing Immediately

**Symptoms:**
- Hub starts but connection closes immediately
- Logs show: `[DhanHQ::WS] close 1006` or `close 1000`
- `hub.connected?` returns `false`

**Diagnosis:**
```ruby
hub = Live::MarketFeedHub.instance
status = hub.health_status
puts "Connection State: #{status[:connection_state]}"
puts "Last Error: #{status[:last_error]}"
```

**Common Causes:**
1. **Invalid credentials** - Verify `DHANHQ_CLIENT_ID` and `DHANHQ_ACCESS_TOKEN`
2. **Expired access token** - Regenerate from DhanHQ developer portal
3. **Network/firewall** - Ensure outbound WebSocket connections (port 443/80) are allowed
4. **Market closed** - Some endpoints may reject connections outside market hours
5. **Rate limiting** - Too many connection attempts

**Solutions:**
```ruby
# Stop and restart
hub.stop!
hub.start!

# Check diagnostics
hub.diagnostics
```

### Issue: No Ticks Received

**Symptoms:**
- `hub.running?` returns `true`
- `hub.connected?` returns `false` or `true` but no ticks
- `hub.health_status[:last_tick_at]` is `nil`

**Diagnosis:**
```ruby
hub = Live::MarketFeedHub.instance
status = hub.health_status

if status[:last_tick_at]
  seconds_ago = (Time.current - status[:last_tick_at]).round(1)
  puts "Last tick: #{seconds_ago} seconds ago"
else
  puts "No ticks received"
end

puts "Watchlist size: #{status[:watchlist_size]}"
puts "Connected: #{status[:connected]}"
```

**Solutions:**
1. Verify subscriptions:
   ```ruby
   # Check watchlist
   hub.instance_variable_get(:@watchlist)
   ```
2. Manually subscribe to an instrument:
   ```ruby
   hub.subscribe(segment: 'IDX_I', security_id: '13')
   ```
3. Check if market is open (some instruments only stream during market hours)
4. Verify instrument segment and security_id are correct

### Issue: Feed Health Service Reports Stale

**Symptoms:**
- `Live::FeedHealthService.instance.stale?(:ticks)` returns `true`
- Trading blocked due to stale feed

**Diagnosis:**
```ruby
health = Live::FeedHealthService.instance
status = health.status[:ticks]

puts "Stale: #{status[:stale]}"
puts "Last Seen: #{status[:last_seen_at]}"
puts "Threshold: #{status[:threshold]} seconds"
puts "Last Error: #{status[:last_error]}"
```

**Solutions:**
1. Restart the hub to re-establish connection
2. Check connection status with `hub.health_status`
3. Review last error in `hub.diagnostics[:last_error_details]`
4. Increase threshold if needed (not recommended):
   ```ruby
   Live::FeedHealthService.instance.configure_threshold(:ticks, 30.seconds)
   ```

## Manual Testing

### Test Connection
```ruby
# Start hub
hub = Live::MarketFeedHub.instance
hub.start!

# Wait a moment
sleep 2

# Check status
puts hub.health_status

# Subscribe to NIFTY
hub.subscribe(segment: 'IDX_I', security_id: '13')

# Wait for ticks
sleep 5

# Check if ticks received
puts "Last tick: #{hub.health_status[:last_tick_at]}"
puts "Connected: #{hub.connected?}"
```

### Test with Diagnostics
```ruby
# Run full diagnostics
load 'lib/tasks/ws_feed_diagnostics.rb'
WsFeedDiagnostics.run
```

## Logging

All connection events are logged:

- **INFO**: Connection established, hub started
- **WARN**: Connection disconnected (code and reason)
- **ERROR**: Connection errors, tick callback failures

Search logs for:
```
[MarketFeedHub] WebSocket connected
[MarketFeedHub] WebSocket disconnected: code=1006, reason=
[MarketFeedHub] WebSocket error: ...
```

## Integration with FeedHealthService

The hub automatically updates `FeedHealthService`:
- **On tick**: Marks feed as healthy (`mark_success!(:ticks)`)
- **On disconnect/error**: Marks feed as failed (`mark_failure!(:ticks)`)

This ensures the health service has accurate status for trading guards.

## Best Practices

1. **Always check `connected?`** after `start!` to verify actual connection
2. **Monitor `last_tick_at`** to ensure data is flowing
3. **Use diagnostics** tool for troubleshooting
4. **Check feed health** before critical trading operations
5. **Handle reconnection** - The DhanHQ client handles automatic reconnection, but monitor status

## Example: Health Check Before Trading

```ruby
def can_trade?
  hub = Live::MarketFeedHub.instance

  # Must be running and connected
  return false unless hub.running? && hub.connected?

  # Must have received ticks recently
  status = hub.health_status
  return false unless status[:last_tick_at]
  return false if (Time.current - status[:last_tick_at]) > 30.seconds

  # Feed health service must be healthy
  return false if Live::FeedHealthService.instance.stale?(:ticks)

  true
end
```

