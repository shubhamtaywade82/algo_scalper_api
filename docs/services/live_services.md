# Live & Monitoring Services

Detailed documentation for services within the `Live::` namespace — the real-time trading brain.

---

## Live::MarketFeedHub

**Files:**
- `app/services/live/market_feed_hub.rb` — Singleton WebSocket hub
- `app/services/live/market_feed_hub_service.rb` — Supervisor adapter

**Purpose:**
The primary WebSocket gateway. `Live::MarketFeedHub` is a Singleton that manages the DhanHQ WebSocket connection, subscription lifecycle, and tick distribution. `Live::MarketFeedHubService` wraps the hub with a `start/stop` API so it can be managed by `TradingSystem::Supervisor`.

**Inputs:**
- DhanHQ WebSocket v2 feed (ticks for subscribed option and index instruments)
- Watchlist configuration (security_ids to subscribe to)
- Active positions (subscribed on startup + as new positions open)

**Outputs (per tick):**
- `Live::TickCache.put(tick)` — in-memory write-through store
- `Live::RedisTickCache.put(tick)` — Redis persistence keyed by `segment:security_id`
- `MarketData::MarketCache.update_ltp` — Rails.cache institutional layer
- `PnlUpdaterService.cache_intermediate_pnl(tracker_id:, ltp:)` — enqueued for 250ms batch flush

**Resilience:**
- **Automatic reconnection** on network drops
- **State restoration**: On reconnect, calls `resubscribe_active_positions_after_reconnect` — queries `PositionIndex` and resubscribes all active instruments
- **Feed health**: `Live::FeedHealthService` monitors tick liveness; warns if no ticks for > 30s

**Used by:** `TradingSystem::Supervisor` (via `Live::MarketFeedHubService`), `Entries::EntryGuard`, `ExitEngine`.

---

## Live::PnlUpdaterService

**Dependencies:**
- `DhanHQ::WS::Client` (market feed)
- `Live::MarketFeedHub::Parser`

**Purpose:**
250ms PnL flush service. Batches per-tick LTP updates into periodic PnL calculations.

**Flow:**
```
cache_intermediate_pnl(tracker_id:, ltp:)  [called per tick, last-wins]
  ↓
[every 250ms]
  → Batch DB load (all queued tracker IDs in single query)
  → TickQuery.for_security → TickCache.fetch → Redis
  → gross_pnl = (ltp - entry_price) * qty
  → net_pnl = gross_pnl - BrokerFeeCalculator.fees
  → pnl_pct = (ltp - entry_price) / entry_price  [DECIMAL]
  → Update HWM: max(redis_hwm, current_pnl)
  → RedisPnlCache.store_pnl
  → EventBus.publish(:ltp, { tracker_id, ltp, pnl, pnl_pct, hwm })
  → ActionCable broadcast to "positions" channel
  → tracker.cache_live_pnl  [in-memory, no DB write]
```

**Key invariants:**
- Never writes to DB from this path (uses RedisPnlCache only)
- DB sync throttled to every 30s via `sync_pnl_to_database_throttled`

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
Central risk enforcement service. Subscribes to high-frequency LTP/PnL events from EventBus and runs a 5-second enforcement loop over all active positions.

**Two paths:**

1. **Per-tick** (via `EventBus.subscribe(:ltp)`):
   - `handle_pnl_event` → `UnifiedExitChecker.check_exit_conditions(tracker)`
   - Evaluates SL, TP, trailing, early trend failure, time-based in priority order

2. **5-second enforcement loop** (`run_enforcement_cycle`):
   - Circuit breaker check (force_close_all! if tripped)
   - Per-tracker: advance_trade_state → premium_r_stop → dynamic_trailing → profit_floor → structure_invalidation → premium_momentum_failure → rr_profit_booking → percentage_pnl_exit → time_stop → time_based_exit

**Config**: Cached at initialization from `AlgoConfig.fetch` to avoid repeated calls during high-frequency risk checks.

**Used by:** `TradingSystem::Supervisor`

---

## Live::UnifiedExitChecker

**File:** `app/services/live/unified_exit_checker.rb`

**Purpose:**
The decision pivot for position closures. Evaluates all configured exit rules in priority order and returns an exit action or nil.

**Priority order (first match wins):**

| # | Rule | Config |
|---|------|--------|
| 1 | Early trend failure | `exit.early_exit.*` |
| 2 | Stop loss (static or adaptive) | `exit.stop_loss.*` |
| 3 | Take profit | `exit.take_profit` |
| 4 | Trailing stop | `exit.trailing.*` |
| 5 | Time-based | `exit.time_based.*` |

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
On-demand and startup broker/DB position reconciliation. `force_sync!` runs before service startup in `TradingSystem::Daemon` to ensure DB state matches broker before monitoring begins.

**Used by:** `TradingSystem::Daemon` (startup), `Live::ReconciliationService` (periodic)

---

## Live::RedisTickCache

**File:** `app/services/live/redis_tick_cache.rb`

**Purpose:**
Redis-backed tick store. Keyed by `"tick:#{segment}:#{security_id}"`.

- **Write-through**: Mirrors in-memory TickCache to Redis for cross-process visibility
- **Graceful degradation**: If Redis is down, in-process cache still works (no crash)

---

## Live::RedisPnlCache

**File:** `app/services/live/redis_pnl_cache.rb`

**Purpose:**
Redis-backed PnL snapshot store.

- Stores `{ pnl_rupees, pnl_pct, hwm_pnl, ltp, updated_at }` per tracker ID
- Read by `RiskManagerService`, `UnifiedExitChecker`, and dashboard API
- DB sync throttled to every 30s via `sync_pnl_to_database_throttled`

---

## Live::TickCache

**File:** `app/services/live/tick_cache.rb`

**Purpose:**
In-memory write-through tick store using `Concurrent::Map` for thread safety.

---

## Live::TickQuery

**File:** `app/services/live/tick_query.rb`

**Purpose:**
Authoritative LTP read boundary. All services should read LTP through `TickQuery`, not directly from `TickCache` or Redis.

**Critical invariant:** Returns `nil` on cache miss (not 0 or raise). All callers must treat `nil` as stale data.

---

## Live::PositionIndex

**File:** `app/services/live/position_index.rb`

**Purpose:**
In-memory `security_id → [PositionTracker]` index for O(1) lookup during tick distribution.

---

## Live::TimeRegimeService

**File:** `app/services/live/time_regime_service.rb`

**Purpose:**
Determines the current market session window (S1-S4) and whether entries are allowed.

**Sessions:**
- S1 OPEN_EXPANSION: 09:15-09:45
- S2 TREND_CONTINUATION: 09:45-11:30
- S3 CHOP_DECAY: 11:30-13:45 (entries blocked by default)
- S4 CLOSE_GAMMA: 13:45-15:15

**Used by:** `Guards::TimeRegimeGuard`

---

## Live::EdgeFailureDetector

**File:** `app/services/live/edge_failure_detector.rb`

**Purpose:**
Detects per-index strategy edge loss and pauses entries for 60 minutes.

**Triggers:** 2+ consecutive SLs, or last-5-trade rolling PnL <= -₹3,000.

**Used by:** `Guards::EdgeFailureGuard`

---

## Live::StatsNotifierService

**File:** `app/services/live/stats_notifier_service.rb`

**Purpose:**
Sends daily performance stats via Telegram at market close (configured in `risk.market_close_hhmm`).

**Cadence:** Once per session at market close.

---

## Live::OrderUpdateHub

**File:** `app/services/live/order_update_hub.rb`

**Purpose:**
DhanHQ order update WebSocket connection. Receives fill and cancel events for all orders placed in the session.

---

## Live::OrderUpdateHandler

**File:** `app/services/live/order_update_handler.rb`

**Purpose:**
Processes order fill/cancel events from `OrderUpdateHub`. Updates `PositionTracker` state on fills.

**Idempotency**: All handlers are idempotent — duplicate events from reconnects/replays are safe.
