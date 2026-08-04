# Live & Monitoring Services

Detailed documentation for services within the `Live::` namespace — the real-time trading brain.

---

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

**Files:**
- `app/services/live/risk_manager_service.rb`
- `app/services/live/risk_manager_service/runner.rb`
- `app/services/live/risk_manager_service/exit_enforcement.rb`
- `app/services/live/risk_manager_service/exit_execution.rb`
- `app/services/live/risk_manager_service/config.rb`
- `app/services/live/risk_manager_service/pnl_cache.rb`

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

**Config**: Cached at initialization from `AlgoConfig.fetch` to avoid repeated calls during high-frequency risk checks.

**Used by:** `TradingSystem::Supervisor`

---

## Live::UnifiedExitChecker

**File:** `app/services/live/unified_exit_checker.rb`

**Purpose:**
The decision pivot for position closures. It evaluates all configured exit rules in priority order (early trend failure, stop-loss, take-profit, trailing, premium guards, time-based exits, percentage PnL, R:R booking) and returns a recommended action.

**Inputs:**
- `tracker`: The `PositionTracker` record.
- Historical and live market data from `TickQuery` and Redis.
- PnL snapshots from `Live::RedisPnlCache`.

**Config source**: `build_exit_config` reads from `AlgoConfig.fetch` → `risk` and `exit` sections. All percentage values expected in **DECIMAL format**.

**Used by:** `Live::RiskManagerService`

---

## Live::ExitEngine

**File:** `app/services/live/exit_engine.rb`

**Purpose:**
Single source of truth for placing and tracking exit orders. All exit paths (UnifiedExitChecker, RiskManagerService enforcement loop, manual) go through here.

**What it does:**
1. Guards against duplicate exit (checks `exit_requested_at` / `exit_sent_at`)
2. Sets `exit_requested_at`, `exit_coid` (deterministic client order ID)
3. Places exit via `Orders.config.gateway`
4. Sets `exit_sent_at`
5. Paper: `mark_exited!` immediately
6. Live: waits for `OrderUpdateHandler` fill event
7. `persist_final_pnl_from_cache`: recalculates `last_pnl_pct` from `final_pnl / (entry_price * quantity)` — NOT from stale Redis snapshot

**Used by:** `Live::RiskManagerService`, `Live::UnifiedExitChecker`, manual admin actions.

---

## Live::TrailingEngine

**File:** `app/services/live/trailing_engine.rb`

**Purpose:**
Trailing stop management for the 5-second enforcement loop. Supports tiered, direct, and gamma-aware trailing modes.

**Modes:**
- **Tiered**: Uses `indices[].trailing_tiers` from config — different drawdown thresholds at different profit levels
- **Direct**: `direct_trailing.distance_pct` from HWM (DECIMAL)
- **Gamma-aware**: Uses `Orders::GammaTrailingEngine` for NIFTY/BANKNIFTY/SENSEX during gamma acceleration

**When active:** Only when `trade_state == 'expansion'` or breakeven is set (`be_set?`).

---

## Live::ReconciliationService

**File:** `app/services/live/reconciliation_service.rb`

**Purpose:**
Broker/DB state synchronization every 30 seconds. Corrects ghost positions and orphan positions.

**Cadence:** 30s loop

---

## Live::PositionSyncService

**File:** `app/services/live/position_sync_service.rb`

**Purpose:**
Reconciles the internal database with the actual backlog at the broker. It is used during daemon startup and periodic reconciliation to make sure there are no "ghost trades" or untracked active positions after crashes or restarts.

**Used by:**
- `TradingSystem::Daemon` / `TradingSystem::Supervisor` during startup.
- Periodic reconciliation via `Live::ReconciliationService`.
