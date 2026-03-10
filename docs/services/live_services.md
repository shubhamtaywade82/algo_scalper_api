# Live & Monitoring Services

Detailed documentation for services within the `Live::` namespace.

## Live::MarketFeedHub

**Files:**
- `app/services/live/market_feed_hub.rb`
- `app/services/live/market_feed_hub_service.rb`

**Purpose:**
The primary WebSocket gateway and its supervisor adapter. `Live::MarketFeedHub` is a Singleton that manages the DhanHQ WebSocket connection, subscription lifecycle, and tick distribution. `Live::MarketFeedHubService` wraps the hub with a `start/stop` API so it can be managed by `TradingSystem::Supervisor`.

**Inputs:**
- WebSocket feed from DhanHQ (ticks for subscribed option and index instruments).
- Watchlist configuration (symbols/security_ids to subscribe to).

**Outputs:**
- Parsed ticks written to:
  - `Live::RedisTickCache` (Redis write-through store keyed by `segment:security_id`).
  - In-memory tick cache (`TickCache`) used by `TickQuery`.
- Per-position callbacks into the PnL pipeline (`Live::PnlUpdaterService`).
- Feed health and connection status for monitoring.

**Dependencies:**
- `DhanHQ` WebSocket client (v2 API).
- `Live::RedisTickCache`
- `TickCache` / `TickQuery`

**Used by:**
- `TradingSystem::Supervisor` (via `Live::MarketFeedHubService`).
- `Entries::EntryGuard` and other services that subscribe instruments to the feed.

---

## Live::RiskManagerService

**File:** `app/services/live/risk_manager_service.rb`

**Purpose:**
Central risk enforcement service. It subscribes to high-frequency LTP/PnL events from the EventBus and also runs a slower 5-second enforcement loop over all active positions. It evaluates configured exit rules (SL, TP, trailing, structure invalidation, time-based exits, premium guards) and triggers `Live::ExitEngine` when needed.

**Inputs:**
- `:ltp` events from `Core::EventBus` (emitted by `Live::PnlUpdaterService`).
- Active positions from `PositionTracker.active` (for the 5-second loop).
- PnL snapshots from `Live::RedisPnlCache`.

**Outputs:**
- Exit decisions forwarded to `Live::ExitEngine`.
- Enforcement logs for all applied rules (per tracker).

**Dependencies:**
- `Live::UnifiedExitChecker`
- `Live::RedisPnlCache`
- `Live::ExitEngine`
- `Orders::GatewayFactory` / `Orders.config.gateway`

**Used by:**
- `TradingSystem::Supervisor`

---

## Live::UnifiedExitChecker

**File:** `app/services/live/unified_exit_checker.rb`

**Purpose:**
The decision pivot for position closures. It evaluates all configured exit rules in priority order (early trend failure, stop-loss, take-profit, trailing, premium guards, time-based exits, percentage PnL, R:R booking) and returns a recommended action.

**Inputs:**
- `tracker`: The `PositionTracker` record.
- Historical and live market data from `TickQuery` and Redis.
- PnL snapshots from `Live::RedisPnlCache`.

**Outputs:**
- `exit_action`: Hash containing trigger reason and recommended price.

**Used by:**
- `Live::RiskManagerService`

---

## Live::PositionSyncService

**File:** `app/services/live/position_sync_service.rb`

**Purpose:**
Reconciles the internal database with the actual backlog at the broker. It is used during daemon startup and periodic reconciliation to make sure there are no "ghost trades" or untracked active positions after crashes or restarts.

**Used by:**
- `TradingSystem::Daemon` / `TradingSystem::Supervisor` during startup.
- Periodic reconciliation via `Live::ReconciliationService`.
