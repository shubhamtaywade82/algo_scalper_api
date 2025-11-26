# Complete Repository Analysis - NEMESIS V3 Trading System

## Executive Summary

This is a **production-grade algorithmic trading system** for Indian index options (NIFTY, BANKNIFTY, SENSEX) built on Rails 8. The system implements a complete end-to-end trading flow from signal generation to position management with sophisticated risk controls.

**Key Strengths:**
- ✅ Comprehensive risk management with underlying-aware exits
- ✅ Real-time market data integration via WebSocket
- ✅ Paper trading mode for safe testing
- ✅ Well-structured domain-driven architecture
- ✅ Feature flags for gradual rollout
- ✅ Comprehensive test coverage

**Architecture Status:** Production-ready with all critical components implemented and wired correctly.

---

## 1. System Architecture Overview

### 1.1 Core Components

| Component | Purpose | Status | Key Files |
|-----------|---------|--------|-----------|
| **Signal Generation** | Generate trading signals using technical indicators | ✅ Complete | `app/services/signal/` |
| **Chain Analysis** | Select optimal option strikes | ✅ Complete | `app/services/options/` |
| **Entry Management** | Place orders and track positions | ✅ Complete | `app/services/orders/entry_manager.rb` |
| **Risk Management** | Monitor positions and enforce exits | ✅ Complete | `app/services/live/risk_manager_service.rb` |
| **Market Feed** | Real-time WebSocket data streaming | ✅ Complete | `app/services/live/market_feed_hub.rb` |
| **Position Cache** | Ultra-fast in-memory position tracking | ✅ Complete | `app/services/positions/active_cache.rb` |

### 1.2 Trading Flow

```
┌─────────────────┐
│   Scheduler     │ → Loops indices, generates signals
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  TrendScorer    │ → Computes direction/trend (0-21 score)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ ChainAnalyzer   │ → Selects ATM strikes with liquidity scoring
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  EntryManager   │ → Validates, places order, adds to ActiveCache
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  MarketFeedHub  │ → Subscribes to option + underlying ticks
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  ActiveCache    │ → Updates PnL, peak, SL offsets in real-time
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ RiskManager     │ → Checks underlying exits → SL/TP → trailing → peak-drawdown
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  ExitEngine     │ → Executes exit orders
└─────────────────┘
```

---

## 2. Critical Implementation Details

### 2.1 Signal Generation (`Signal::Scheduler`)

**Current Implementation:**
- ✅ Direction-first logic (when `enable_direction_before_chain: true`)
- ✅ Uses `TrendScorer` to compute trend score (0-21)
- ✅ Skips chain analysis if trend_score < min_trend_score (default: 14)
- ✅ Falls back to legacy `Signal::Engine` path if flag disabled

**Key Methods:**
- `evaluate_supertrend_signal(index_cfg)` - Main signal evaluation
- `direction_before_chain_enabled?` - Feature flag check
- `select_candidate_from_chain()` - Chain analysis (only if direction confirmed)

**Status:** ✅ Fully implemented and tested

---

### 2.2 Entry Management (`Orders::EntryManager`)

**Current Implementation:**
- ✅ Validates entry via `EntryGuard`
- ✅ Creates `PositionTracker` (paper/live)
- ✅ Adds to `ActiveCache` with SL/TP metadata
- ✅ Places bracket orders via `BracketPlacer`
- ✅ Records trade in `DailyLimits`

**Wiring Status:**
- ✅ ActiveCache integration: `add_position()` called
- ✅ MarketFeedHub subscription: Handled by `ActiveCache` (auto-subscribe enabled)
- ✅ Underlying metadata: Attached via `attach_underlying_metadata()`

**Key Methods:**
- `process_entry()` - Main entry orchestration
- `calculate_sl_tp()` - SL/TP calculation (30% below, 60% above for CE)
- `emit_entry_filled_event()` - Event bus notification

**Status:** ✅ Fully wired and operational

---

### 2.3 Risk Management (`Live::RiskManagerService`)

**Current Implementation:**

#### 2.3.1 Underlying-Aware Exits (Feature Flag: `enable_underlying_aware_exits`)

**Priority Order:**
1. **Structure Break** - Exit if underlying structure breaks against position direction
2. **Weak Trend** - Exit if underlying trend_score < threshold (default: 10)
3. **ATR Collapse** - Exit if ATR ratio < multiplier (default: 0.65) and ATR trending down

**Implementation:**
```ruby
def handle_underlying_exit(position, tracker, exit_engine)
  return false unless underlying_exits_enabled?
  
  underlying_state = Live::UnderlyingMonitor.evaluate(position)
  
  # Check structure break
  if structure_break_against_position?(position, tracker, underlying_state)
    guarded_exit(tracker, 'underlying_structure_break', exit_engine)
    return true
  end
  
  # Check weak trend
  if underlying_state.trend_score < underlying_trend_score_threshold
    guarded_exit(tracker, 'underlying_trend_weak', exit_engine)
    return true
  end
  
  # Check ATR collapse
  if atr_collapse?(underlying_state)
    guarded_exit(tracker, 'underlying_atr_collapse', exit_engine)
    return true
  end
  
  false
end
```

**Status:** ✅ Fully implemented with comprehensive logging

#### 2.3.2 Peak-Drawdown Gating (Feature Flag: `enable_peak_drawdown_activation`)

**Activation Conditions:**
- Peak profit % >= `peak_drawdown_activation_profit_pct` (default: 25%)
- Current SL offset % >= `peak_drawdown_activation_sl_offset_pct` (default: 10%)

**Exit Trigger:**
- Only if activation conditions met AND drawdown >= `peak_drawdown_exit_pct` (default: 5%)

**Implementation:**
```ruby
def check_peak_drawdown(position_data, exit_engine)
  peak = position_data.peak_profit_pct.to_f
  current = position_data.pnl_pct.to_f
  
  return false unless Positions::TrailingConfig.peak_drawdown_triggered?(peak, current)
  
  if peak_drawdown_activation_enabled?
    activation_ready = Positions::TrailingConfig.peak_drawdown_active?(
      profit_pct: peak, # Use peak, not current
      current_sl_offset_pct: current_sl_offset_pct(position_data)
    )
    return false unless activation_ready
  end
  
  # Exit logic...
end
```

**Status:** ✅ Fully implemented with idempotent exits (tracker.with_lock)

#### 2.3.3 Risk Manager Loop Priority

**Processing Order (per position):**
1. Recalculate PnL and peak metrics
2. Check underlying-aware exits (if enabled)
3. Enforce hard SL/TP limits (always active)
4. Apply tiered trailing SL offsets
5. Process trailing with peak-drawdown gating

**Status:** ✅ Correctly ordered and tested

---

### 2.4 Underlying Monitor (`Live::UnderlyingMonitor`)

**Purpose:** Evaluate underlying index health for position exit decisions

**Metrics Computed:**
- `trend_score` - Composite trend score (0-21) via `TrendScorer`
- `bos_state` - Structure state (`:broken`, `:intact`, `:unknown`)
- `bos_direction` - Structure break direction (`:bullish`, `:bearish`, `:neutral`)
- `atr_trend` - ATR trend (`:falling`, `:rising`, `:flat`)
- `atr_ratio` - Current ATR / Previous ATR
- `mtf_confirm` - Multi-timeframe confirmation (boolean)

**Caching:** 250ms TTL to avoid CPU spikes

**Status:** ✅ Fully implemented and tested

---

### 2.5 ActiveCache (`Positions::ActiveCache`)

**Purpose:** Ultra-fast in-memory position cache with Redis persistence

**Key Features:**
- ✅ Real-time LTP updates via `MarketFeedHub` callbacks
- ✅ Peak profit persistence to Redis (7-day TTL)
- ✅ Peak reload on startup
- ✅ Auto-subscribe/unsubscribe to market data
- ✅ Underlying metadata attachment

**PositionData Fields:**
- `sl_offset_pct` - Current trailing SL offset %
- `peak_profit_pct` - Highest profit % achieved
- `underlying_segment`, `underlying_security_id` - Underlying metadata
- `underlying_trend_score`, `underlying_ltp` - Underlying metrics

**Status:** ✅ Fully implemented with Redis persistence

---

### 2.6 Trailing Engine (`Live::TrailingEngine`)

**Purpose:** Per-tick trailing stop management with tiered SL offsets

**Tiered SL Offsets:**
```
Profit % → SL Offset %
5%   → -15%
10%  → -5%
15%  → 0%
25%  → +10%
40%  → +20%
60%  → +30%
80%  → +40%
120% → +60%
```

**Peak-Drawdown Integration:**
- Checks peak-drawdown FIRST (before SL updates)
- Uses peak profit % (not current) for activation gating
- Idempotent exits via `tracker.with_lock`

**Status:** ✅ Fully implemented with peak-drawdown gating

---

## 3. Configuration (`config/algo.yml`)

### 3.1 Feature Flags

```yaml
feature_flags:
  enable_direction_before_chain: true      # Direction-first signal generation
  enable_demand_driven_services: true       # Sleep when no positions
  enable_underlying_aware_exits: false     # Underlying-aware exit logic
  enable_peak_drawdown_activation: false    # Peak-drawdown gating
  enable_auto_subscribe_unsubscribe: true   # Auto market data subscription
```

**Status:** ✅ All flags implemented and tested

### 3.2 Risk Configuration

```yaml
risk:
  sl_pct: 0.30                              # 30% fixed SL
  tp_pct: 0.60                              # 60% fixed TP
  peak_drawdown_exit_pct: 5                 # 5% drawdown threshold
  peak_drawdown_activation_profit_pct: 25.0  # Activation: profit >= 25%
  peak_drawdown_activation_sl_offset_pct: 10.0 # Activation: SL offset >= 10%
  underlying_trend_score_threshold: 10.0    # Exit if trend < 10
  underlying_atr_collapse_multiplier: 0.65  # Exit if ATR ratio < 0.65
```

**Status:** ✅ All thresholds configurable and tested

---

## 4. Testing Status

### 4.1 Test Coverage

| Component | Test File | Status |
|-----------|-----------|--------|
| RiskManager | `spec/services/live/risk_manager_underlying_spec.rb` | ✅ Comprehensive |
| TrailingEngine | `spec/services/live/trailing_engine_spec.rb` | ✅ Comprehensive |
| UnderlyingMonitor | `spec/services/live/underlying_monitor_spec.rb` | ✅ Complete |
| ActiveCache | `spec/services/positions/active_cache_spec.rb` | ✅ Complete |
| MarketFeedHub | `spec/services/live/market_feed_hub_spec.rb` | ✅ Complete |

### 4.2 Test Scenarios Covered

**Underlying Exits:**
- ✅ Structure break against position direction
- ✅ Weak trend score (< threshold)
- ✅ ATR collapse (falling volatility)

**Peak-Drawdown Gating:**
- ✅ Exit when activation conditions met
- ✅ No exit when profit < activation threshold
- ✅ No exit when SL offset < activation threshold
- ✅ Idempotent exits (multiple triggers → single exit)

**Integration:**
- ✅ End-to-end position lifecycle
- ✅ MarketFeedHub subscription/unsubscription
- ✅ ActiveCache persistence and reload

**Status:** ✅ Comprehensive test coverage

---

## 5. Wiring Verification

### 5.1 Entry Flow

```
Scheduler → TrendScorer → ChainAnalyzer → EntryManager
                                                      │
                                                      ▼
                                    ActiveCache.add_position()
                                                      │
                                                      ▼
                                    MarketFeedHub.subscribe_instrument()
                                                      │
                                                      ▼
                                    BracketPlacer.place_bracket()
```

**Status:** ✅ Fully wired

### 5.2 Monitoring Flow

```
MarketFeedHub.on_tick() → ActiveCache.handle_tick()
                                              │
                                              ▼
                                    PositionData.update_ltp()
                                              │
                                              ▼
                                    RiskManager.monitor_loop()
                                              │
                                              ▼
                                    process_trailing_for_all_positions()
                                              │
                                              ├─→ UnderlyingMonitor.evaluate()
                                              ├─→ enforce_bracket_limits()
                                              ├─→ TrailingEngine.process_tick()
                                              └─→ ExitEngine.execute_exit()
```

**Status:** ✅ Fully wired

---

## 6. Known Issues & Limitations

### 6.1 Current Limitations

1. **UnderlyingMonitor Caching:** 250ms cache may miss rapid structure breaks
   - **Mitigation:** Cache TTL is configurable, can be reduced if needed

2. **Peak Persistence:** Redis TTL is 7 days (may lose peaks for very long positions)
   - **Mitigation:** TTL can be increased, or persistence moved to DB

3. **Concurrent Exits:** Multiple exit triggers checked sequentially
   - **Mitigation:** Idempotent exits via `tracker.with_lock` prevent double-exits

### 6.2 Production Readiness Checklist

- ✅ Error handling comprehensive
- ✅ Logging structured with context
- ✅ Feature flags for gradual rollout
- ✅ Idempotent operations (tracker locks)
- ✅ Redis fallback handling
- ✅ WebSocket reconnection logic
- ✅ Rate limiting for API calls
- ✅ Test coverage comprehensive

**Status:** ✅ Production-ready

---

## 7. Deployment Guide

### 7.1 Staging Deployment (Gradual Rollout)

**Step 1: Enable Direction-First**
```yaml
feature_flags:
  enable_direction_before_chain: true
```

**Step 2: Enable Demand-Driven Services**
```yaml
feature_flags:
  enable_demand_driven_services: true
```

**Step 3: Enable Underlying-Aware Exits**
```yaml
feature_flags:
  enable_underlying_aware_exits: true
```

**Step 4: Enable Peak-Drawdown Activation**
```yaml
feature_flags:
  enable_peak_drawdown_activation: true
```

### 7.2 Monitoring

**Key Metrics to Monitor:**
- `underlying_exit_count` - Count of underlying-triggered exits
- `peak_drawdown_exit_count` - Count of peak-drawdown exits
- `signals_processed` - Signal generation rate
- `entries_created` - Entry success rate

**Log Patterns:**
- `[UNDERLYING_EXIT]` - Underlying-aware exit decisions
- `[PEAK_DRAWDOWN]` - Peak-drawdown exit decisions
- `[RiskManager]` - Risk management operations

### 7.3 Rollback Plan

**Quick Rollback (Disable Features):**
```yaml
feature_flags:
  enable_underlying_aware_exits: false
  enable_peak_drawdown_activation: false
```

**Full Rollback (Code):**
- Revert RiskManagerService changes
- Revert TrailingEngine changes
- Revert config/algo.yml changes

---

## 8. Code Quality

### 8.1 Standards Compliance

- ✅ RuboCop compliance (2-space indentation, 120-char lines)
- ✅ RSpec test structure (Better Specs guidelines)
- ✅ YARD documentation for public methods
- ✅ Error handling with structured logging
- ✅ Feature flags for all new behavior

### 8.2 Architecture Compliance

- ✅ Services organized by domain
- ✅ Controllers thin (business logic in services)
- ✅ Models handle only persistence
- ✅ Shared utilities in `lib/`
- ✅ Singleton pattern for global state

**Status:** ✅ Fully compliant

---

## 9. Summary

### 9.1 Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| Signal Generation | ✅ Complete | Direction-first logic implemented |
| Entry Management | ✅ Complete | ActiveCache + MarketFeedHub wired |
| Risk Management | ✅ Complete | Underlying-aware + peak-drawdown gating |
| Market Feed | ✅ Complete | WebSocket with reconnection |
| Position Cache | ✅ Complete | Redis persistence + reload |
| Testing | ✅ Complete | Comprehensive coverage |

### 9.2 Next Steps

1. **Enable in Staging:** Gradually enable feature flags
2. **Monitor Metrics:** Track exit counts and performance
3. **Tune Thresholds:** Adjust based on paper trading results
4. **Production Rollout:** Enable flags in production after validation

### 9.3 Conclusion

**The system is production-ready** with all critical components implemented, tested, and wired correctly. The implementation follows best practices with feature flags for safe gradual rollout.

**Key Achievements:**
- ✅ Complete end-to-end trading flow
- ✅ Underlying-aware risk management
- ✅ Peak-drawdown gating with activation conditions
- ✅ Comprehensive test coverage
- ✅ Production-grade error handling and logging

---

**Document Version:** 1.0  
**Last Updated:** 2025-01-XX  
**Author:** AI Assistant (Composer)
