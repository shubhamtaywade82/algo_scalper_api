# WebSocket Troubleshooting Guide

Complete troubleshooting guide for WebSocket connection and feed issues.

## Connection Problems

### WebSocket Not Connecting

**Symptoms:**
- `Live::MarketFeedHub.instance.connected?` returns `false`
- No ticks received
- Connection state stuck at `:disconnecting` or `:disconnected`

**Solutions:**

1. **Check Environment Variables**
   ```bash
   echo $DHANHQ_WS_ENABLED      # Should be 'true'
   echo $CLIENT_ID              # Should be set
   echo $ACCESS_TOKEN           # Should be set
   ```

2. **Verify Credentials**
   - Ensure DhanHQ credentials are valid
   - Check token expiration
   - Verify client ID matches account

3. **Check Network**
   ```bash
   # Test DhanHQ API connectivity
   curl -I https://api.dhan.co/v2/funds
   ```

4. **Review Logs**
   ```bash
   tail -f log/development.log | grep -i websocket
   tail -f log/development.log | grep -i "MarketFeedHub"
   ```

### Connection Drops Frequently

**Symptoms:**
- Connection establishes then disconnects
- Frequent reconnection attempts
- Intermittent tick reception

**Solutions:**

1. **Check Network Stability**
   - Monitor network latency
   - Check for firewall issues
   - Verify proxy settings

2. **Review Error Logs**
   ```bash
   grep -i "error\|disconnect" log/development.log | tail -20
   ```

3. **Check Feed Health**
   ```ruby
   Live::FeedHealthService.instance.status
   ```

## Subscription Problems

### Instruments Not Subscribed

**Symptoms:**
- Watchlist configured but no ticks
- Subscription logs show errors
- `@watchlist` is empty

**Solutions:**

1. **Check Watchlist Configuration**
   ```ruby
   # In Rails console
   WatchlistItem.active.count
   WatchlistItem.active.each { |w| puts "#{w.segment}:#{w.security_id}" }
   ```

2. **Verify Environment Variable**
   ```bash
   echo $DHANHQ_WS_WATCHLIST
   # Format: "NSE_FNO:49081;NSE_FNO:49082"
   ```

3. **Check Instrument Data**
   ```ruby
   # Verify instruments exist
   Instrument.where(segment: 'NSE_FNO').count
   ```

### Subscription Format Errors

**Problem**: `TypeError: no implicit conversion of Symbol into Integer`

**Cause**: Incorrect `subscribe_many` parameter format

**Solution**: Ensure normalized format:
```ruby
normalized_list = [
  { ExchangeSegment: "NSE_FNO", SecurityId: "49081" },
  { ExchangeSegment: "NSE_FNO", SecurityId: "49082" }
]
@ws_client.subscribe_many(list: normalized_list)
```

## Data Problems

### No Ticks Received

**Symptoms:**
- Connection is active
- Subscriptions successful
- No tick data in cache

**Solutions:**

1. **Check Market Hours**
   - WebSocket only active during market hours
   - Verify current time is within trading hours (9:15 AM - 3:30 PM IST)

2. **Verify Subscription Status**
   ```ruby
   hub = Live::MarketFeedHub.instance
   hub.diagnostics
   ```

3. **Check Tick Cache**
   ```ruby
   Live::TickCache.instance.all
   Live::RedisTickCache.instance.all
   ```

### Stale or Missing Data

**Symptoms:**
- Ticks received but data is old
- Missing fields in tick data
- Inconsistent data updates

**Solutions:**

1. **Check WebSocket Mode**
   ```bash
   echo $DHANHQ_WS_MODE  # Should match requirements
   ```

2. **Verify Data Mode**
   - `ticker`: LTP only
   - `quote`: LTP, bid, ask, volume, OI
   - `full`: Complete order book

3. **Review Tick Processing**
   ```ruby
   # Check if ticks are being processed
   Live::FeedListener.instance.stats if defined?(Live::FeedListener)
   ```

## Performance Issues

### High Latency

**Symptoms:**
- Delayed tick reception
- Slow subscription processing
- High CPU usage

**Solutions:**

1. **Reduce Subscription Count**
   - Limit watchlist to essential instruments
   - Use `ticker` mode if full data not needed

2. **Check Thread Performance**
   ```ruby
   # Review thread status
   Thread.list.each { |t| puts "#{t.name}: #{t.status}" }
   ```

3. **Monitor Resource Usage**
   ```bash
   top -p $(pgrep -f "rails")
   ```

## Diagnostic Commands

### Connection Status
```ruby
hub = Live::MarketFeedHub.instance
hub.connected?
hub.health_status
hub.diagnostics
```

### Feed Health
```ruby
Live::FeedHealthService.instance.status
Live::FeedHealthService.instance.last_success(:market_feed)
```

### Tick Cache Status
```ruby
Live::TickCache.instance.all
Live::RedisTickCache.instance.all
```

### Watchlist Status
```ruby
WatchlistItem.active.count
WatchlistItem.active.map { |w| "#{w.segment}:#{w.security_id}" }
```

## Common Error Messages

### `TypeError: no implicit conversion of Symbol into Integer`
- **Cause**: Incorrect `subscribe_many` parameter
- **Fix**: Use `list:` parameter with normalized format

### `Connection refused` or `ECONNREFUSED`
- **Cause**: Network or firewall issue
- **Fix**: Check network connectivity, firewall rules

### `401 Unauthorized`
- **Cause**: Invalid credentials
- **Fix**: Verify `CLIENT_ID` and `ACCESS_TOKEN`

### `429 Too Many Requests`
- **Cause**: Rate limit exceeded
- **Fix**: Reduce subscription frequency, implement backoff

## Related Documentation

- [WebSocket Guide](../guides/websocket.md)
- [DhanHQ Client Guide](../guides/dhanhq-client.md)
- [Services Startup](../architecture/services_startup.md)

