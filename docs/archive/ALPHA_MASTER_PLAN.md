# Alpha Engine Master Implementation Plan (Comprehensive)

This document provides a definitive, end-to-end technical guide for implementing the Alpha Engine, covering every specification defined in `docs/ALPHA.md`.

---

## 1. System Architecture
The Alpha Engine is a modular intelligence layer that feeds the existing `algo_scalper_api` pipeline.

```text
Alpha Signal (Engine) → AlphaExecutionService → Derivative#buy_option! → Orders::Placer → DhanHQ API
                                ↓
                          Capital::Allocator (Sizing via Kelly/Fixed Fraction)
                                ↓
                          RiskGuard (Trade Limits, Daily Caps, Kill Switch)
                                ↓
                          PositionTracker (State Management & Audit)
                                ↓
                          UnifiedExitChecker (Trailing/Breakeven/PNL)
```

---

## 2. Technical Roadmap

### Phase 1: Persistence & Data Infrastructure
- [ ] **Migration**: Create tables for `iv_snapshots` and `alpha_signals`.
- [ ] **IV Capture**: Implement `IvSnapshotJob` to pre-calculate daily ATM IV from Dhan option chains.
- [ ] **Event Store**: Implementation of a database-backed `EventCalendar` (replacing hardcoded values).

### Phase 2: Alpha Strategy Modules (The "Thinkers")
- [ ] **MomentumAlpha**: Trend-following via ATR breakouts and volume ratio.
- [ ] **VolExpansionAlpha**: Mean-reversion when IV percentile is in bottom 20th.
- [ ] **EventAlpha**: Directional plays based on high-impact calendar events (Budget, RBI).
- [ ] **GammaScalpAlpha**: Capture volatility when realized > implied (Straddle logic).
- [ ] **ExpiryAlpha**: 0DTE/1DTE micro-breakout detection with high gamma sensitivity.

### Phase 3: Risk & Sizing (The "Guardians")
- [ ] **Risk::LimitsGuard**: Extend or complement existing `DrawdownGuard` to enforce:
  - `DAILY_MAX_TRADES` (e.g., 10 per day).
  - `MAX_OPEN_POSITIONS` (e.g., 3 simultaneously).
  - `MAX_CONSECUTIVE_LOSSES` (e.g., 3 losses triggers a temporary halt).
  - `DAILY_MAX_LOSS_PCT` (e.g., halt if 2% of capital is lost).
- [ ] **PositionSizer**: Integrate Kelly Criterion or Fixed Fractional logic into `Capital::Allocator`.

### Phase 4: Orchestration & Execution (The "Bridge")
- [ ] **SignalEngine**: Orchestrate strategies and rank by Expected Value (EV).
- [ ] **AlphaExecutionService**: 
  - Gated by `CircuitBreaker` and `Risk::LimitsGuard`.
  - Enforces **No-Averaging Rule**.
  - Routes high-trailing signals to `DhanHQ::Models::SuperOrder` to mitigate the 25-mod limit.

### Phase 5: Jobs, API & UI
- [ ] **Background Jobs**: `AlphaScanJob` (Solid Queue) runs every 5 min.
- [ ] **API Controller**: `Api::AlphaController` with `/scan`, `/execute`, `/status`.
- [ ] **Dashboard Integration**: Add Alpha signal visualization to the existing SolidJS frontend.

---

## 3. Integration Matrix (File Modifications)

| Target File | Change |
| :--- | :--- |
| `app/models/position_tracker.rb` | Extend `store_accessor :meta` with `alpha_source`, `confidence`, `ev`, and `client_order_id`. |
| `app/models/concerns/instrument_helpers.rb` | Update `after_order_track!` to merge alpha metadata into the tracker. |
| `app/models/derivative.rb` / `instrument.rb` | Update `buy_option!` and `buy_market!` to pass signal metadata. |
| `app/services/capital/allocator.rb` | Add support for alpha-specific sizing (Kelly/Fixed Fraction). |
| `app/services/entries/guards/drawdown_guard.rb` | Add checks for `DAILY_MAX_TRADES` and `MAX_CONSECUTIVE_LOSSES`. |

---

## 4. ⚠️ Critical Safety & Performance Constraints

### 1. 25-Order Modification Limit
Your `PositionTracker` trails continuously. **Warning**: You will hit the DhanHQ 25-mod limit.
- **Solution**: For signals with `trailing_jump > 0`, the engine MUST use `SuperOrder`.

### 2. Real-Time Data Freshness
- Throttling: `MarketFeedHandler` must throttle tick processing to 500ms to avoid blocking the EventBus.
- Cache: Strike selection must use cached `option_chain` data (TTL: 30s) to maintain low latency.

### 3. IV Dependency
- `VolExpansionAlpha` cannot run until `IvSnapshotJob` has at least 30 days of data.
- **Solution**: Use a fallback "Cheap IV" flag if historical data is insufficient.

---

## 5. Verification Checklist
1. **Dry Run**: `LIVE_TRADING=false` + Telegram alerts for all alpha signals.
2. **Audit Check**: Query `alpha_signals` table to verify metadata (source, confidence, EV) is correctly stored.
3. **No-Averaging Test**: Verify the system blocks a second entry for the same derivative if a tracker is active.
4. **Kill Switch Test**: Manually trip `CircuitBreaker` and verify alpha signals are blocked.
