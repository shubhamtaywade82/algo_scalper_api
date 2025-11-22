# Ticker Troubleshooting Guide

Troubleshooting guide for ticker channel and tick data issues.

## Ticker Channel Issues

### TickerChannel Removed

**Note**: `TickerChannel` has been removed from the codebase. The system now uses:
- `Live::TickCache` for in-memory tick storage
- `Live::RedisTickCache` for Redis-backed tick storage
- Direct API access for tick data

**Migration**: If you were using `TickerChannel`, migrate to:
```ruby
# Old (removed):
TickerChannel.broadcast_to(...)

# New:
Live::TickCache.put(tick)
Live::TickCache.ltp(segment, security_id)
```

## Tick Data Issues

### Missing Tick Data

**Symptoms:**
- `Live::TickCache.ltp` returns `nil`
- No ticks in cache
- Stale data

**Solutions:**

1. **Check WebSocket Connection**
   ```ruby
   Live::MarketFeedHub.instance.connected?
   ```

2. **Verify Subscriptions**
   ```ruby
   WatchlistItem.active.count
   ```

3. **Check Tick Cache**
   ```ruby
   Live::TickCache.instance.all
   ```

### Stale Tick Data

**Symptoms:**
- Ticks received but timestamps are old
- Data not updating

**Solutions:**

1. **Check Last Tick Time**
   ```ruby
   Live::MarketFeedHub.instance.last_tick_at
   ```

2. **Verify Feed Health**
   ```ruby
   Live::FeedHealthService.instance.status
   ```

3. **Check Market Hours**
   - Ensure market is open
   - WebSocket inactive outside trading hours

## Related Documentation

- [WebSocket Troubleshooting](./websocket.md)
- [WebSocket Guide](../guides/websocket.md)

