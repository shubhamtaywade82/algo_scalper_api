# Risk Management Services

Detailed documentation for services within the `Risk::` namespace and related security components.

## Risk::CircuitBreaker

**File:** `app/services/risk/circuit_breaker.rb`

**Purpose:**
A global safety mechanism that can halt all trading activity system-wide. It is triggered by extreme events like excessive daily loss or multiple consecutive execution failures.

**Inputs:**
- System health events.
- Daily PnL stats.

**Outputs:**
- `tripped?`: Boolean status checked by all entry/exit logic.

**Used by:**
- `Entries::EntryGuard`
- `Live::RiskManagerService`

---

## Live::EdgeFailureDetector

**File:** `app/services/live/edge_failure_detector.rb`

**Purpose:**
Detects when a strategy has "lost its edge" during a session (e.g., hitting multiple stop losses in a row) and temporarily pauses entries for that specific index.

**Inputs:**
- Exit results from `PositionTracker`.

**Outputs:**
- Pause/Resume commands for specific indices.

**Used by:**
- `Entries::EntryGuard`

---

## Live::DailyLimits

**File:** `app/services/live/daily_limits.rb`

**Purpose:**
Enforces hard daily profit and loss targets. Once a target or limit is hit, the system prevents further entries for the rest of the day.

**Used by:**
- `Entries::EntryGuard`
- `Live::RiskManagerService`
