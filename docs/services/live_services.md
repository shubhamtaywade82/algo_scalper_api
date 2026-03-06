# Live & Monitoring Services

Detailed documentation for services within the `Live::` namespace.

## Live::MarketFeedHub

**File:** `app/services/live/market_feed_hub.rb`

**Purpose:**
The primary WebSocket gateway. It manages real-time socket connections to DhanHQ, handles binary packet decoding, and distributes ticks to internal caches.

**Inputs:**
- `symbol_list`: Initial symbols to subscribe to.
- WebSocket binary feed from DhanHQ.

**Outputs:**
- Parsed ticks sent to `Live::TickCache` and `RedisTickCache`.
- Feed health status updates.

**Dependencies:**
- `DhanHQ::WebSocket`
- `Live::MarketFeedHub::Parser`

**Used by:**
- `TradingSystem::Supervisor`
- `Entries::EntryGuard` (for subscription)

---

## Live::RiskManagerService

**File:** `app/services/live/risk_manager_service.rb`

**Purpose:**
A continuous monitoring loop that iterates over all active `PositionTracker` records. It updates live PnL and evaluates if any exit rules (SL, TP, Trailing) are triggered.

**Inputs:**
- Active positions from `PositionTracker.active`.
- Live LTPs from `TickCache`.

**Outputs:**
- Updated PnL and High Water Marks in Redis.
- Calls `Live::ExitEngine` when an exit is triggered.

**Dependencies:**
- `Live::UnifiedExitChecker`
- `Live::RedisPnlCache`
- `Orders::Gateway`

**Used by:**
- `TradingSystem::Supervisor`

---

## Live::UnifiedExitChecker

**File:** `app/services/live/unified_exit_checker.rb`

**Purpose:**
The decision pivot for position closures. It evaluates a hierarchy of exit rules (Edge Failure, Stop Loss, Take Profit, Trailing Stop) and returns a recommended action.

**Inputs:**
- `tracker`: The `PositionTracker` record.
- Historical price data/indicators.

**Outputs:**
- `exit_action`: Hash containing trigger reason and recommended price.

**Used by:**
- `Live::RiskManagerService`

---

## Live::PositionSyncService

**File:** `app/services/live/position_sync_service.rb`

**Purpose:**
Reconciles the internal database with the actual backlog at the broker. This prevents "ghost trades" or untracked active positions due to process crashes.

**Used by:**
- Periodic background job / Supervisor.
