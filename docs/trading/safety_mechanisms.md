# Safety Mechanisms & Resilience

Beyond individual trade risk, the system implements platform-level safety mechanisms to protect the entire capital base from extreme market events or technical failures.

## 1. System Circuit Breaker

`Risk::CircuitBreaker` is the global emergency kill switch.

- **Implementation**: `app/services/risk/circuit_breaker.rb` — singleton backed by Redis/Rails.cache
- **State**: Persists across process restarts (Redis-backed)
- **On trip**:
  - `Guards::CircuitBreakerGuard` immediately blocks all new trade signals
  - `RiskManagerService.run_enforcement_cycle` detects trip state and calls `Risk::CircuitBreaker.instance.force_close_all!(exit_engine:, reason:)` — exits every open position within seconds
- **Manual control via API**:
  - `POST /api/circuit_breaker/trip` — trip with reason
  - `DELETE /api/circuit_breaker/trip` — reset
  - `GET /api/circuit_breaker` — check status
- **Manual control via code**:
  ```ruby
  Risk::CircuitBreaker.instance.trip!(reason: 'Manual halt — unusual market conditions')
  Risk::CircuitBreaker.instance.reset!
  Risk::CircuitBreaker.instance.tripped?
  ```

## 2. Edge Failure Detection

`Live::EdgeFailureDetector` monitors for strategy edge loss on a per-index basis.

- **Implementation**: `app/services/live/edge_failure_detector.rb`
- **Trigger conditions** (any of):
  - 2+ consecutive stop-losses for the same index
  - Rolling last-5-trade net PnL <= -₹3,000 for the index
  - S3 session (11:30-13:45) + 2 SLs for the index
- **Effect**: `entries_paused?(index_key:)` returns true → `EdgeFailureGuard` blocks new entries for 60 minutes for that index
- **Config**: `risk.edge_failure_detector.*` (thresholds and pause duration)
- **Purpose**: Prevents repeated SL hits during degraded market conditions without halting the entire system

## 3. Loss Streak Guard

`Guards::LossStreakGuard` enforces a consecutive loss threshold across all indices.

- **Implementation**: `app/services/entries/guards/loss_streak_guard.rb`
- **Default threshold**: 2 consecutive losses
- **Effect**: Blocks all new entries until the streak is broken by a winning trade
- **Config**: `loss_streak_guard.enabled: true`, `consecutive_losses_threshold: 2`

## 4. Daily Limits & Exposure Controls

Enforced by `Guards::DailyLimitsGuard` and `Guards::ExposureGuard` before every entry.

- **Max Daily Loss**: Stops further entries if day's total realized loss exceeds configured limit
- **Max Daily Trades**: Hard cap on trades per index per day
- **Max Daily Profit Target**: Stops entries once daily profit target is reached
- **Max Same-Side Positions**: `max_same_side` per index (default 1) — prevents pyramiding
- **Max Concurrent Positions**: `Guards::MaxConcurrentGuard` global cap

## 5. Portfolio Drawdown Guard

`Guards::DrawdownGuard` checks portfolio-level drawdown before any new entry.

- **Implementation**: `app/services/entries/guards/drawdown_guard.rb`
- Reads from `Portfolio::DrawdownGuard` / `Portfolio::ProfitLockEngine`
- Blocks entries when portfolio is in excessive drawdown
- Config: `config/algo.yml` → `profit_lock` section

## 6. Time Regime Gating

`Guards::TimeRegimeGuard` restricts entries by market session window.

**Sessions** (configured in `risk.time_regimes`):
- **S1 OPEN_EXPANSION** (09:15-09:45): High volatility open. Entries allowed with caution.
- **S2 TREND_CONTINUATION** (09:45-11:30): Best conditions. Entries allowed.
- **S3 CHOP_DECAY** (11:30-13:45): Lunch. `allow_entries: false` by default. **Exception**: `ExpiryWeekPowerTrendGuard` sets `context[:expiry_power_trend] = true` when ADX >= 40 + near monthly expiry → S3 block bypassed.
- **S4 CLOSE_GAMMA** (13:45-15:15): Gamma-aware entries. Entries allowed with higher exit scrutiny.

## 7. Expiry Week Power Trend Guard

`Guards::ExpiryWeekPowerTrendGuard` enables entries in the normally-blocked S3 session during high-probability expiry week conditions.

- **Pattern**: ADX >= 40 (strong trend) + within 5 days of monthly expiry + time 12:00-13:45
- **Effect**: Sets `context[:expiry_power_trend] = true` — does NOT block by itself
- **Downstream**: `TimeRegimeGuard` bypasses S3/S4 chop-zone block when flag is set
- **Config**: `expiry_week_power_trend.enabled: true`, `adx_min: 40`, `expiry_days_max: 5`

## 8. Automatic Token Healing

- **Problem**: DhanHQ access tokens expire daily
- **Solution**: 3-tier token provisioning in `Dhan::TokenManager`:
  1. **Authority server** — HTTP GET to `$TRADER_API_BASE_URL/auth/dhan/token` (60s cache)
  2. **TOTP auto-refresh** — generates new token via `DHAN_PIN` + `DHAN_TOTP_SECRET`
  3. **Static fallback** — `ENV['DHAN_ACCESS_TOKEN']`
- **On 401 Unauthorized**: `Orders::GatewayLive` detects and triggers token refresh
- **After refresh**: `Dhan::TokenManager` restarts `Live::MarketFeedHub` to reconnect with new token
- **Config**: `config/initializers/dhanhq_config.rb` and `config/initializers/dhan_token_bootstrap.rb`

## 9. WebSocket Resilience

- **Automatic reconnection**: `Live::MarketFeedHub` reconnects on network drops
- **State restoration**: On reconnect, auto-resubscribes all instruments required by active positions (via `resubscribe_active_positions_after_reconnect`)
- **Feed health**: `Live::FeedHealthService` tracks tick liveness; logs warning if no ticks for > 30s
- **Idempotency**: All WebSocket event handlers are idempotent — reconnects and replays are safe

## 10. Reconciliation

`Live::ReconciliationService` runs every 30 seconds to detect state divergence:
- Compares `PositionTracker.active` records with DhanHQ broker positions
- Corrects "ghost positions" (tracked active but closed at broker)
- Corrects "orphan positions" (open at broker but not tracked in DB)

At daemon startup: `Live::PositionSyncService.force_sync!` aligns DB with broker before any services start.

## 11. Exit Intent Durability

Exit placement uses durable fields on `PositionTracker`:
- `exit_requested_at` — when exit was decided
- `exit_sent_at` — when exit order was sent to broker
- `exit_coid` — deterministic client order ID for retry idempotency

If the daemon crashes after requesting an exit, reconciliation will detect the broker state and complete the exit lifecycle correctly.

## 12. Live Order Safety Gates

Two explicit safety gates are required before any live order reaches the broker:

1. `config/algo.yml` → `dhanhq.enable_orders: true`
2. Environment variable `PLACE_ORDER=true`

`Orders::Placer` checks both before every live BUY, SELL, or EXIT call. Without both set, orders are logged as "dry-run" but not submitted.

## 13. PnL Integrity

`PositionTracker.persist_final_pnl_from_cache` recalculates `last_pnl_pct` from:
```ruby
final_pnl / (entry_price * quantity)
```

**Not** from the Redis PnL snapshot (which may be stale from a different tick than the actual exit price). This ensures `last_pnl_pct` reflects actual realized P&L.
