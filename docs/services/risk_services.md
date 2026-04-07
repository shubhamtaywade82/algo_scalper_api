# Risk Management Services

Detailed documentation for services within the `Risk::` namespace and related security components.

---

## Risk::CircuitBreaker

**File:** `app/services/risk/circuit_breaker.rb`

**Purpose:**
Global safety mechanism — a Redis-backed singleton kill switch that halts all trading activity system-wide.

**State storage:** Redis/Rails.cache — persists across process restarts.

**Interface:**
```ruby
Risk::CircuitBreaker.instance.tripped?        # → boolean
Risk::CircuitBreaker.instance.trip_reason     # → String or nil
Risk::CircuitBreaker.instance.trip!(reason:)  # → trips the breaker
Risk::CircuitBreaker.instance.reset!          # → clears the breaker
Risk::CircuitBreaker.instance.force_close_all!(exit_engine:, reason:)
  # → exits all active positions immediately
```

**API surface:**
- `GET /api/circuit_breaker` — check status
- `POST /api/circuit_breaker/trip` — trip with `{ reason: "..." }`
- `DELETE /api/circuit_breaker/trip` — reset

**On trip:**
1. `Guards::CircuitBreakerGuard` blocks all new entries (checked in guard pipeline position 3)
2. `RiskManagerService.run_enforcement_cycle` detects trip → calls `force_close_all!` → exits every active position

**Used by:** `Entries::EntryGuard` (via `CircuitBreakerGuard`), `Live::RiskManagerService`

---

## Live::EdgeFailureDetector

**File:** `app/services/live/edge_failure_detector.rb`

**Purpose:**
Detects when a strategy has "lost its edge" during a session for a specific index, and temporarily pauses entries for that index.

**Triggers (any of):**
- 2+ consecutive stop-losses for the index
- Rolling last-5-trade net PnL <= -₹3,000 for the index
- S3 session (11:30-13:45) + 2 SLs for the index

**Effect:**
- `entries_paused?(index_key:)` returns true for 60 minutes
- `EdgeFailureGuard` checks this before every entry

**Resume:**
- Automatically resumes after 60 minutes
- Can be manually reset

**Config:**
```yaml
risk:
  edge_failure_detector:
    enabled: true
    max_consecutive_sls: 2
    rolling_window_threshold_rupees: 3000
    pause_duration_minutes: 60
```

**Used by:** `Guards::EdgeFailureGuard`

---

## Live::DailyLimits

**File:** `app/services/live/daily_limits.rb`

**Purpose:**
Enforces hard daily profit/loss/trade limits. Once a limit is hit, the system prevents further entries for the rest of the day.

**Limits tracked:**
- Max daily loss (rupees) per index
- Max daily trades per index
- Max daily profit target per index

**Used by:** `Guards::DailyLimitsGuard`, `Live::RiskManagerService`

---

## Risk::Rules — Exit Rule Engines

Individual rule engines in `app/services/risk/rules/*.rb`. Each implements a `call(tracker, pnl_data)` interface and returns an exit decision or nil.

### Risk::Rules::StructureInvalidationRule

**File:** `app/services/risk/rules/structure_invalidation_rule.rb`

**Purpose:** Exit when trade thesis (structural level) is invalidated.

**Logic:**
- Checks if price has breached a key structure level (support/resistance)
- Checks if Supertrend has flipped against position direction

**Config:** `risk.exits.structure_invalidation.enabled: true`

---

### Risk::Rules::PremiumMomentumFailureRule

**File:** `app/services/risk/rules/premium_momentum_failure_rule.rb`

**Purpose:** Exit when option premium momentum fails (dead option scenario).

**Logic:**
- Detects when premium is decaying/stalling without corresponding spot movement
- Avoids holding positions that have lost momentum but haven't hit static SL

**Config:** `risk.exits.premium_momentum_failure.enabled: true`

---

### Risk::Rules::PercentagePnlRule

**File:** `app/services/risk/rules/percentage_pnl_rule.rb`

**Purpose:** Exit when target PnL percentage is reached.

**Logic:**
- Reads `risk.percentage_pnl_exit.target_pct` directly as DECIMAL
- Exit when `current_pnl_pct >= target_pct`

**Config:**
```yaml
risk:
  percentage_pnl_exit:
    enabled: true
    target_pct: 0.30  # 30% — DECIMAL format
```

---

### Risk::Rules::TimeStopRule

**File:** `app/services/risk/rules/time_stop_rule.rb`

**Purpose:** Exit when position has been held for maximum duration.

**Config:**
```yaml
risk:
  exits:
    time_stop:
      enabled: true
      max_hold_minutes: 60
```

---

## Positions::DrawdownSchedule

**File:** Module in `lib/positions/` or `app/services/positions/`

**Purpose:**
Calculates adaptive drawdown schedules for trailing stops and adaptive stop-loss.

**Key methods:**
```ruby
# Upward trailing: how much drawdown is allowed from HWM at current profit level
allowed_upward_drawdown_pct(pnl_pct, index_key: nil)
# → DECIMAL, tightens as profit increases

# Adaptive SL: how much loss is allowed given time below entry and volatility
reverse_dynamic_sl_pct(pnl_pct, seconds_below_entry:, atr_ratio:)
# → DECIMAL, tightens as loss deepens / time increases / volatility low
```

---

## Positions::TrailingConfig

**File:** `app/services/positions/trailing_config.rb`

**Purpose:**
Trailing stop configuration defaults (all values in DECIMAL format).

**Key defaults:**
- `DEFAULT_PEAK_DRAWDOWN_PCT: 0.05` (5% from HWM)
- `DEFAULT_ACTIVATION_PROFIT_PCT: 0.25` (activate at 25% profit)
- `DEFAULT_TIERS`: tier-based drawdown thresholds

**Note:** These defaults are overridden by `config/algo.yml` → `indices[].trailing_tiers` and `exit.trailing.*`.

---

## Portfolio::DrawdownGuard / Portfolio::ProfitLockEngine

**Files:** `app/services/portfolio/drawdown_guard.rb`, `app/services/portfolio/profit_lock_engine.rb`

**Purpose:**
Portfolio-level (not per-position) drawdown and profit protection:
- `DrawdownGuard` → blocks entries when portfolio drawdown exceeds threshold
- `ProfitLockEngine` → locks daily profits when target reached; restricts further entries

**Config:** `config/algo.yml` → `profit_lock.*`

**Used by:** `Guards::DrawdownGuard`

**Note:** Do NOT add a parallel profit protection mechanism at the market_context layer — these are the canonical portfolio-level safety guards.
