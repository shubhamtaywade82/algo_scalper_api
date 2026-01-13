# Services Startup Guide

This document describes all services that start automatically when running `bin/dev`.

**📖 For complete system flow from initialization to exit, see:** [`../COMPLETE_SYSTEM_FLOW.md`](../COMPLETE_SYSTEM_FLOW.md)

## Overview

When you run `bin/dev`, it executes `bin/rails server`, which triggers Rails initialization. During initialization, several automated trading services are started via initializers.

## Startup Sequence

### 1. Rails Server
- **Command**: `bin/rails server`
- **Purpose**: Starts the Puma web server on port 3000 (default)
- **Routes**: Serves API endpoints (`/api/health`, `/api/test_broadcast`, `/up`)

### 2. Initializers Load

#### `config/initializers/market_stream.rb`
This is the main initializer that starts all trading services. Services start in this order:

##### 2.1. **Live::MarketFeedHub** (Primary WebSocket Feed)
- **Service**: `Live::MarketFeedHub.instance.start!`
- **Purpose**:
  - Connects to DhanHQ WebSocket for real-time market data
  - Subscribes to watchlist instruments (from `WatchlistItem` or `DHANHQ_WS_WATCHLIST` env var)
  - Receives and processes live ticks (LTP updates)
  - Stores ticks in `Live::TickCache` (in-memory) and `Live::RedisPnlCache` (Redis)
  - Emits `ActiveSupport::Notifications` events for `"dhanhq.tick"`
- **Dependencies**: Requires `DHANHQ_WS_ENABLED=true` and valid DhanHQ credentials
- **Status**: ✅ **ACTIVE**

##### 2.2. **Signal::Scheduler** (Trading Signal Generator)
- **Service**: `Signal::Scheduler.instance.start!`
- **Purpose**:
  - Periodically analyzes market data using technical indicators (Supertrend, ADX)
  - Generates trading signals (bullish/bearish) for configured indices (NIFTY, BANKNIFTY, SENSEX)
  - Triggers entry logic when signals are detected
  - Manages signal state and scaling logic
- **Frequency**: Runs analysis on configured timeframes (default: 1-minute candles)
- **Status**: ✅ **ACTIVE**

##### 2.3. **Live::RiskManagerService** (Risk & Position Management)
- **Service**: `Live::RiskManagerService.instance.start!`
- **Purpose**:
  - Monitors all active positions continuously
  - Enforces risk limits (stop-loss, take-profit, trailing stops)
  - Updates PnL in Redis cache for real-time tracking
  - Executes exits when risk conditions are met
  - Manages high-water marks and breakeven locks
  - Updates paper position PnL periodically (every 1 minute)
- **Frequency**: Continuous monitoring loop (default: 5-second intervals)
- **Status**: ✅ **ACTIVE**

##### 2.4. **Position Resubscription**
- **Service**: `resubscribe_active_positions`
- **Purpose**:
  - After server restart, resubscribes to WebSocket feed for all active positions
  - Ensures existing positions continue receiving real-time tick updates
  - Only runs if there are active `PositionTracker` records
- **Status**: ✅ **ACTIVE**

##### 2.5. **Live::PositionSyncService** (Position Synchronization)
- **Service**: `Live::PositionSyncService.instance.force_sync!`
- **Purpose**:
  - Initial sync: Ensures all DhanHQ positions are tracked in database
  - Creates `PositionTracker` records for untracked positions
  - Marks orphaned positions as exited
  - Runs periodically (every 30 seconds) after initial sync
- **Mode Handling**:
  - **Paper Mode**: Only syncs paper positions from database (no DhanHQ API calls)
  - **Live Mode**: Syncs live positions from DhanHQ API
- **Status**: ✅ **ACTIVE**

##### 2.6. **Live::OrderUpdateHandler** (Order Updates - DISABLED)
- **Service**: `Live::OrderUpdateHandler.instance.start!` (commented out)
- **Purpose**: Would receive real-time order updates via WebSocket
- **Status**: ❌ **DISABLED** (using `PositionSyncService` polling instead)
- **Reason**: Simpler, more reliable, sufficient for use case (30s polling is acceptable)

#### `config/initializers/mock_data_service.rb` (Conditional)
- **Service**: `Live::MockDataService.instance.start!`
- **Purpose**: Generates mock market data when WebSocket is disabled
- **Conditions**:
  - Only in development environment
  - Only if `DHANHQ_WS_ENABLED=false`
- **Status**: ⚠️ **CONDITIONAL** (only if WebSocket disabled)

## Service Dependencies

```
Rails Server
  └── MarketFeedHub (WebSocket connection)
      ├── TickCache (in-memory tick storage)
      ├── RedisPnlCache (Redis tick/PnL storage)
      └── ActiveSupport::Notifications (event system)
  ├── Signal::Scheduler
  │   └── Signal::Engine (technical analysis)
  │       └── Options::ChainAnalyzer (option selection)
  │           └── Entries::EntryGuard (entry validation)
  │               └── Orders::Placer (order placement)
  ├── RiskManagerService
  │   ├── PositionSyncService (position tracking)
  │   └── RedisPnlCache (PnL updates)
  └── PositionSyncService
      └── MarketFeedHub (position subscriptions)
```

## Service Status Summary

| Service | Status | Purpose |
|---------|--------|---------|
| **Rails Server** | ✅ Active | Web API server |
| **MarketFeedHub** | ✅ Active | WebSocket market data feed |
| **Signal::Scheduler** | ✅ Active | Trading signal generation |
| **RiskManagerService** | ✅ Active | Risk management & exits |
| **PositionSyncService** | ✅ Active | Position synchronization |
| **OrderUpdateHandler** | ❌ Disabled | Real-time order updates (using polling instead) |
| **MockDataService** | ⚠️ Conditional | Mock data (only if WS disabled) |

## Startup Conditions

Services are **NOT** started in:
- **Console mode** (`rails console`, `rails runner`)
- **Test environment** (`RAILS_ENV=test`)

This prevents services from interfering with:
- Database migrations
- Test execution
- Manual console operations

## Graceful Shutdown

All services are automatically stopped when:
- **Ctrl+C** (SIGINT) is pressed
- **SIGTERM** signal is received
- Rails server exits (via `at_exit` hook)

Shutdown order (reverse of startup):
1. `RiskManagerService.stop!`
2. `Signal::Scheduler.stop!`
3. `MarketFeedHub.stop!`
4. `DhanHQ::WS.disconnect_all_local!`

## Manual Service Control

You can manually start/stop services in Rails console:

```ruby
# Start services
Live::MarketFeedHub.instance.start!
Signal::Scheduler.instance.start!
Live::RiskManagerService.instance.start!

# Stop services
Live::RiskManagerService.instance.stop!
Signal::Scheduler.instance.stop!
Live::MarketFeedHub.instance.stop!
```

## Monitoring

Check service status via API:
```bash
curl http://localhost:3000/api/health
```

Response includes:
- WebSocket connection status
- Active positions count
- Tick cache size
- Sample LTPs for indices

## Troubleshooting

### Services Not Starting
- Check logs for initialization errors
- Verify `DHANHQ_WS_ENABLED` and credentials are set
- Ensure database is accessible
- Check if running in console/test mode (services won't start)

### WebSocket Connection Issues
- Verify DhanHQ credentials are valid
- Check network connectivity
- Review `MarketFeedHub` logs for connection errors
- If WebSocket disabled, `MockDataService` should start instead

### Position Sync Issues
- Check `PositionSyncService` logs
- Verify DhanHQ API access
- Ensure `PositionTracker` model is working correctly


