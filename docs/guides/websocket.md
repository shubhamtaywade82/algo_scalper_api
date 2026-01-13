# WebSocket Guide

Complete guide to WebSocket setup, data modes, connection testing, and troubleshooting.

## Overview

The system uses DhanHQ WebSocket API for real-time market data. The `Live::MarketFeedHub` service manages WebSocket connections and subscriptions.

## Data Modes

### Ticker Mode (`ticker`)
- **Purpose**: Lightweight LTP updates only
- **Use Case**: Basic price tracking
- **Data**: Last traded price (LTP)
- **Bandwidth**: Minimal

### Quote Mode (`quote`) - **Recommended**
- **Purpose**: Standard market data
- **Use Case**: Most trading operations
- **Data**: LTP, bid, ask, volume, OI
- **Bandwidth**: Moderate

### Full Mode (`full`)
- **Purpose**: Complete market depth
- **Use Case**: Advanced analysis
- **Data**: Full order book, depth levels
- **Bandwidth**: High

## Configuration

Set via environment variable:
```bash
DHANHQ_WS_MODE=quote  # ticker, quote, or full
```

## Connection Testing

### Manual Test
```bash
# Check WebSocket connection status
bundle exec rails runner "puts Live::MarketFeedHub.instance.connected?"

# Get connection diagnostics
bundle exec rails runner "pp Live::MarketFeedHub.instance.diagnostics"
```

### Health Check
```bash
curl http://localhost:3000/api/health
```

## Troubleshooting

### Connection Issues

**Problem**: WebSocket not connecting
- Check `DHANHQ_WS_ENABLED=true`
- Verify credentials: `CLIENT_ID`, `ACCESS_TOKEN`
- Check network connectivity
- Review logs: `tail -f log/development.log`

**Problem**: No ticks received
- Verify watchlist is configured
- Check subscription status
- Ensure market is open
- Review feed health: `Live::FeedHealthService.instance.status`

### Subscription Issues

**Problem**: Instruments not subscribed
- Check `WatchlistItem.active` records
- Verify `DHANHQ_WS_WATCHLIST` env var format
- Ensure instruments exist in database
- Check subscription logs

### Data Issues

**Problem**: Missing or stale data
- Verify WebSocket mode matches requirements
- Check tick cache: `Live::TickCache.instance.all`
- Review Redis cache: `Live::RedisTickCache.instance`
- Check feed health status

## Common Issues

See [Troubleshooting Guide](../troubleshooting/websocket.md) for detailed solutions.

## Related Documentation

- [DhanHQ Client Guide](./dhanhq-client.md)
- [Configuration Guide](./configuration.md)
- [Services Startup](../architecture/services_startup.md)

