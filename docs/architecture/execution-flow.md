# Trade Lifecycle: Signal to Execution

This document traces the end-to-end path of a trade from the initial signal trigger to the final exit order.

## End-to-End Flow

```
Signal::Scheduler (30s loop)
  │
  Step 1: Market open check (TradingSession::Service)
  │
  Step 2: Instrument resolution (IndexInstrumentCache)
  │
  Step 3: Analysis context initialization
  │   exit_testing_mode → supertrend_adx on 1m, no confirmation
  │   otherwise → entry_strategy from signals config
  │
  Step 4: Primary + confirmation analysis
  │   Supertrend + ADX on primary_tf (default 5m)
  │   Optional confirmation timeframe alignment
  │
  Step 5: Trading context gate
  │   MarketRegimeDetector, EntryFilterEngine, PermissionResolver
  │
  Step 6: Entry quality filter
  │   ADX strength, validation mode (balanced/conservative)
  │
  Step 7: Institutional and permission gates
  │   SMC decision alignment, momentum scoring
  │
  Step 8: State snapshot (Signal::StateTracker dedup)
  │
  Step 9: Options analysis
  │   Options::ChainAnalyzer.pick_strikes_with_qualification
  │   Strike scoring: liquidity, OI, spread, IV
  │   Expected move validation
  │
  Step 10: Diagnostic metadata build
  │
  Step 11: TradingSignal.create
  │
  Step 12: Optional market context gate
  │   Only if market_context.enabled: true
  │   MarketContext::RegimeComposer + ChainSignalExtractor
  │   Trading::MarketPermissionGate (if gate.enabled: true)
  │
  Step 13: Entry trigger → Entries::EntryGuard.try_enter
```

## 1. Signal Generation — `Signal::Engine`

- **Service**: `Signal::Scheduler` → `Signal::Engine`
- **Cadence**: Every 30 seconds per configured index
- **What happens**:
  - Fetches candle series for primary (and optional confirmation) timeframe
  - Computes Supertrend direction + ADX strength
  - Detects market regime (TRENDING / RANGING / CHOPPY)
  - Selects validation mode: `balanced` in trending, `conservative` in choppy
  - Runs `EntryFilterEngine` for structure/liquidity/volatility alignment
  - Checks `Trading::PermissionResolver` for SMC + AVRZ gating
  - Checks SMC decision alignment (if `signals.enable_smc_decision_alignment: true`)
  - Persists `TradingSignal` with full diagnostic metadata
- **Result**: `direction` (bullish/bearish) + `picks` from `ChainAnalyzer`, or nil (no trade)

## 2. Option Strike Selection — `Options::ChainAnalyzer`

- **Service**: `Options::ChainAnalyzer.pick_strikes_with_qualification`
- **What happens**:
  - Resolves nearest expiry from `Derivative` records
  - Fetches live option chain via `DhanAdapter` (always live, even in paper mode)
  - Scores ATM±1 strikes by: liquidity, open interest, bid-ask spread, IV proxy
  - Validates expected move, gamma conditions
  - Returns ordered `picks` list or empty (no qualified strikes)
- **Config**: `chain_analyzer` section in `config/algo.yml`

## 3. Entry Guard Pipeline — `Entries::EntryGuard`

The entry guard is the final gatekeeper. It runs a **20-guard pipeline** — first guard that blocks wins. Guards may enrich the context for later guards.

### Guard Pipeline (in order)

| # | Guard | Blocks when |
|---|-------|------------|
| 1 | `DrawdownGuard` | Portfolio drawdown limit hit |
| 2 | `EntryPolicyGuard` | Policy disallows entry |
| 3 | `CircuitBreakerGuard` | `Risk::CircuitBreaker.instance.tripped?` |
| 4 | `MiddayQualityGuard` | Quality below threshold; bypassed if ADX >= 28 (`trending_adx_bypass`) |
| 5 | `EdgeFailureGuard` | `Live::EdgeFailureDetector.instance.entries_paused?(index_key:)` |
| 6 | `LossStreakGuard` | Consecutive losses >= `loss_streak_guard.consecutive_losses_threshold` (default 2) |
| 7 | `DailyLimitsGuard` | Daily loss/profit/trade limits exceeded |
| 8 | `MaxConcurrentGuard` | Max concurrent open positions reached |
| 9 | `InstrumentLookupGuard` | Instrument not found for index; sets `context[:instrument]` |
| 10 | `LtpResolutionGuard` | No valid LTP for pick; sets `context[:ltp]` |
| 11 | `ExpiryWeekPowerTrendGuard` | Never blocks — enriches `context[:expiry_power_trend] = true` when: ADX >= 40 + within 5 days of monthly expiry + time 12:00-13:45 |
| 12 | `TimeRegimeGuard` | Time regime disallows entries; S3 chop-zone block bypassed when `context[:expiry_power_trend] = true` |
| 13 | `BankniftyLastWeekGuard` | BANKNIFTY and not within last week before monthly expiry |
| 14 | `WeeklyExpiryGuard` | Pick is not a weekly contract |
| 15 | `BosStructureGuard` | BOS contract requirement not met |
| 16 | `ExposureGuard` | `max_same_side` exceeded or Supertrend duplicate for index |
| 17 | `CooldownGuard` | Re-entry cooldown active for symbol |
| 18 | `SizingGuard` | Sizing requirements not met |
| 19 | `RiskPolicyGuard` | Risk policy blocks entry |
| 20 | `SmcNavigatorGuard` | SMC alignment not satisfied |

### Post-Pipeline Checks (EntryGuard)

After the pipeline passes:
- BOS/structure gate for non-Supertrend entries
- Cooldown re-check for pick symbol
- Weekly-only gate for NIFTY/SENSEX (non-paper, non-Supertrend)
- Execution profile check
- Sizing cap: `Capital::Allocator.qty_for(...)` must yield >= 1 lot
- Order placement: `Orders.config.gateway.place_market(...)`

## 4. Capital Allocation — `Capital::Allocator`

- Computes lot-aligned quantity based on `position_sizing` config
- Risk-based: rupee-at-risk / (premium * lot_size)
- Capped by `max_lots` from `Trading::CapitalAllocator`
- Result must be >= 1 lot (lot-aligned)

## 5. Order Placement

- **Paper mode**: `Orders::GatewayPaper` — synthetic fill at current LTP; creates `PositionTracker` in `active` state immediately
- **Live mode**: `Orders::GatewayLive` → `Orders::Placer` → DhanHQ API
  - Requires `PLACE_ORDER=true` env var (safety gate)
  - Requires `dhanhq.enable_orders: true` in config
  - Creates `PositionTracker` in `pending` state; transitions to `active` on fill confirmation via `OrderUpdateHandler`

## 6. Position Tracking

After entry:
- `PositionTracker` record created in DB with `order_no`, `entry_price`, `qty`, `direction`
- Instrument subscribed to DhanHQ WebSocket feed via `MarketFeedHub.subscribe`
- `PositionIndex` updated with `security_id → tracker` mapping

## 7. Live Monitoring

```
DhanHQ tick → MarketFeedHub
  → TickCache.put (memory + Redis write-through)
  → PnlUpdaterService [250ms flush]
    → Compute PnL: (ltp - entry_price) * qty
    → RedisPnlCache.store_pnl
    → EventBus.publish(:ltp)
      → RiskManagerService.handle_pnl_event
        → UnifiedExitChecker.check_exit_conditions
```

## 8. Exit Evaluation — `Live::UnifiedExitChecker`

**Per-tick, priority order (first match wins)**:

| Priority | Rule | Config key |
|----------|------|------------|
| 1 | Early trend failure | `exit.early_exit.enabled`, `exit.early_exit.profit_threshold` |
| 2 | Stop loss (static or adaptive) | `exit.stop_loss.value` (DECIMAL) |
| 3 | Take profit | `exit.take_profit` (DECIMAL) |
| 4 | Trailing stop (gamma-aware or adaptive) | `exit.trailing.*` |
| 5 | Time-based exit | `exit.time_based.exit_time` |

**5-second enforcement loop**, per active tracker:

| Order | Rule |
|-------|------|
| 1 | Premium R-stop (`tracker.meta['premium_stop_price']`) |
| 2 | Dynamic trailing (`Live::TrailingEngine.process_tick`) |
| 3 | Profit floor (arm at lock_pct, ratchet, time-kill) |
| 4 | Structure invalidation (`Risk::Rules::StructureInvalidationRule`) |
| 5 | Premium momentum failure (`Risk::Rules::PremiumMomentumFailureRule`) |
| 6 | R:R profit booking |
| 7 | Percentage PnL exit (`Risk::Rules::PercentagePnlRule`) |
| 8 | Time stop (`Risk::Rules::TimeStopRule`) |
| 9 | Time-based exit (default 15:20) |

## 9. Exit Execution — `Live::ExitEngine`

- **Single source of truth** for placing and tracking exit orders
- Places closing order via `Orders.config.gateway`
- Sets `exit_requested_at`, `exit_sent_at`, `exit_coid` on tracker (durable exit intent fields)
- On fill confirmation: `PositionTracker.mark_exited!`
- `persist_final_pnl_from_cache` recalculates `last_pnl_pct` from `final_pnl / (entry_price * quantity)` — not from stale Redis snapshot
- Unsubscribes instrument from `MarketFeedHub`
- Removes from `PositionIndex`

## Position State Lifecycle

```
pending  →  active  →  exited
              ↑
         (fills from DhanHQ WebSocket
          OrderUpdateHandler)
```

- `pending`: Order placed, awaiting fill confirmation
- `active`: Fill confirmed, monitoring live
- `exited`: Exit complete, final PnL persisted
- `cancelled`: Order rejected or invalidated before fill

## Reconciliation

`Live::ReconciliationService` runs every 30 seconds:
- Compares `PositionTracker.active` with DhanHQ broker positions
- Corrects "ghost positions" (tracked as active but closed at broker)
- Corrects "orphan positions" (open at broker but not tracked)

Also runs at daemon startup via `Live::PositionSyncService.force_sync!`.
