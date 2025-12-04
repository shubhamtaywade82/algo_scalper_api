# Service Status Check Documentation

## Overview
The health endpoint (`/api/health`) has been enhanced to provide comprehensive status information for all trading system services.

## Services Monitored

### 1. **Market Feed Hub** (`Live::MarketFeedHub`)
- **Status**: Running/Stopped
- **Health Details**:
  - Connection state (connected/disconnected/connecting)
  - Last tick received timestamp
  - Watchlist size
  - WebSocket connection status

### 2. **Signal Scheduler** (`Signal::Scheduler`)
- **Status**: Running/Stopped
- **Health Details**:
  - Thread alive status
  - Checks for thread named 'signal-scheduler'

### 3. **Risk Manager Service** (`Live::RiskManagerService`)
- **Status**: Running/Stopped
- **Health Details**:
  - Thread alive status
  - Last cycle time
  - Active positions count
  - Circuit breaker state
  - Recent errors count
  - Uptime in seconds

### 4. **Position Heartbeat** (`TradingSystem::PositionHeartbeat`)
- **Status**: Running/Stopped/Not Registered
- Monitors position health and sends heartbeat signals

### 5. **Order Router** (`TradingSystem::OrderRouter`)
- **Status**: Running/Stopped/Not Registered
- Routes orders to appropriate gateways

### 6. **Paper PnL Refresher** (`Live::PaperPnlRefresher`)
- **Status**: Running/Stopped/Not Registered
- Updates PnL for paper trading positions

### 7. **Exit Manager** (`Live::ExitEngine`)
- **Status**: Running/Stopped/Not Registered
- Manages position exits based on risk rules

### 8. **Active Cache** (`Positions::ActiveCache`)
- **Status**: Running/Stopped/Not Registered
- In-memory cache for active positions

### 9. **Reconciliation Service** (`Live::ReconciliationService`)
- **Status**: Running/Stopped
- **Health Details**:
  - Thread alive status
  - Reconciliation statistics (reconciliations, positions fixed, subscriptions fixed, etc.)

### 10. **PnL Updater Service** (`Live::PnlUpdaterService`)
- **Status**: Running/Stopped
- **Health Details**:
  - Thread alive status
  - Updates position PnL in Redis cache

### 11. **Position Sync Service** (`Live::PositionSyncService`)
- **Status**: On-demand (not a continuously running service)
- **Health Details**:
  - Last sync timestamp
  - Sync interval configuration

### 12. **Feed Health Service** (`Live::FeedHealthService`)
- **Status**: Active
- **Health Details**:
  - Feed statuses (funds, positions, ticks)
  - Last seen timestamps
  - Staleness indicators
  - Last errors per feed

### 13. **Order Update Hub** (`Live::OrderUpdateHub`)
- **Status**: Running/Stopped
- **Health Details**:
  - Enabled status (checks if paper trading is enabled)

## Additional Status Information

### WebSocket Status
- Market Feed Hub connection status
- Order Update Hub status
- Tick cache size and sample LTPs (NIFTY, BANKNIFTY, SENSEX)

### Circuit Breaker Status
- Tripped state
- Trip timestamp and reason (if tripped)

## API Endpoint

**GET** `/api/health`

### Response Format
```json
{
  "mode": "live|paper|backtest",
  "watchlist": 3,
  "active_positions": 5,
  "services": {
    "market_feed_hub": {
      "status": "running",
      "connected": true,
      "connection_state": ":connected",
      "last_tick_at": "2024-01-15T10:30:45Z",
      "watchlist_size": 3
    },
    "signal_scheduler": {
      "status": "running",
      "thread_alive": true
    },
    "risk_manager": {
      "status": "running",
      "thread_alive": true,
      "last_cycle_time": 0.125,
      "active_positions": 5,
      "circuit_breaker_state": ":closed",
      "recent_errors": 0,
      "uptime_seconds": 3600
    },
    "reconciliation": {
      "status": "running",
      "thread_alive": true,
      "stats": {
        "reconciliations": 120,
        "positions_fixed": 5,
        "subscriptions_fixed": 2,
        "activecache_fixed": 1,
        "pnl_synced": 10,
        "errors": 0
      }
    },
    "pnl_updater": {
      "status": "running",
      "thread_alive": true
    },
    "position_sync": {
      "status": "on_demand",
      "last_sync": "2024-01-15T10:30:00Z",
      "sync_interval": 30
    },
    "feed_health": {
      "status": "active",
      "feed_statuses": {
        "funds": {
          "last_seen_at": "2024-01-15T10:30:00Z",
          "threshold": 60,
          "stale": false,
          "last_error": null
        },
        "positions": {
          "last_seen_at": "2024-01-15T10:30:00Z",
          "threshold": 30,
          "stale": false,
          "last_error": null
        },
        "ticks": {
          "last_seen_at": "2024-01-15T10:30:45Z",
          "threshold": 10,
          "stale": false,
          "last_error": null
        }
      }
    },
    "order_update_hub": {
      "status": "running",
      "enabled": true
    }
  },
  "websocket": {
    "market_feed": {
      "running": true,
      "connected": true,
      "health": {
        "running": true,
        "connected": true,
        "connection_state": ":connected",
        "started_at": "2024-01-15T09:00:00Z",
        "last_tick_at": "2024-01-15T10:30:45Z",
        "ticks_received": true,
        "last_error": null,
        "watchlist_size": 3
      }
    },
    "order_updates": {
      "running": true
    },
    "tick_cache": {
      "size": 150,
      "sample_ltps": {
        "nifty": 24500.5,
        "banknifty": 48500.25,
        "sensex": 72500.75
      }
    }
  },
  "circuit_breaker": {
    "tripped": false
  }
}
```

## Error Handling

All service status checks are wrapped in exception handling. If a service check fails, the response will include:
- `status: "error"`
- `error: "ErrorClass - Error message"`

## Usage

### Check all services status:
```bash
curl http://localhost:3000/api/health | jq '.services'
```

### Check specific service:
```bash
curl http://localhost:3000/api/health | jq '.services.risk_manager'
```

### Check WebSocket status:
```bash
curl http://localhost:3000/api/health | jq '.websocket'
```

## Service Startup

Services are managed by `TradingSystem::Supervisor` and are started automatically when the Rails application boots (in web server mode, not in rake/console/backtest mode).

Services are registered in `config/initializers/trading_supervisor.rb`:
- Market Feed Hub
- Signal Scheduler
- Risk Manager
- Position Heartbeat
- Order Router
- Paper PnL Refresher
- Exit Manager
- Active Cache
- Reconciliation Service

## Notes

1. **Position Sync Service** is not a continuously running service - it's called on-demand, so it shows as "on_demand" status.

2. **Feed Health Service** is always active (no start/stop) - it tracks feed health metrics.

3. **Circuit Breaker** status is included but was previously disabled in the health endpoint. It's now re-enabled for monitoring.

4. Services check for thread alive status where applicable to ensure the service thread hasn't crashed.

5. Some services may show "not_registered" if they're not registered with the supervisor (e.g., in test/backtest mode).
