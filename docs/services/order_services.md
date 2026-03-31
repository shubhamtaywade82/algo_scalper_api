# Order & Execution Services

Detailed documentation for services within the `Orders::` and `Entries::` namespaces.

---

## Entries::EntryGuard

**File:** `app/services/entries/entry_guard.rb`

**Purpose:**
Orchestrates the complete entry flow. Runs the 20-guard pipeline, post-pipeline checks, capital allocation, and order placement. Single entry point for all trade entries from `Signal::Engine`.

**Inputs:**
- `index_cfg`: Configuration context (key, segment, SID, limits, cooldown, etc.)
- `pick`: The selected option strike with qualification data
- `direction`: `:bullish` or `:bearish`
- `entry_metadata`: Diagnostic metadata from signal engine (includes `expiry_power_trend`, `strategy_profile`, etc.)

**Outputs:**
- Returns the created `PositionTracker` on success, or nil/false on failure
- Side effects: order placed, tracker created, WebSocket subscription added

**Flow:**
1. `EntryGuardPipeline.run(context)` — 20 guards in sequence
2. Post-pipeline: BOS gate, cooldown re-check, weekly-only check, execution profile check
3. `Capital::Allocator.qty_for(...)` — lot-aligned quantity
4. `Trading::CapitalAllocator.max_lots(...)` — quantity cap
5. `Orders.config.gateway.place_market(...)` — paper or live
6. Create `PositionTracker` + subscribe to WebSocket feed

**Dependencies:**
- `Risk::CircuitBreaker` (via `CircuitBreakerGuard`)
- `Live::EdgeFailureDetector` (via `EdgeFailureGuard`)
- `Capital::Allocator`
- `Orders.config.gateway` (paper or live)
- `Live::MarketFeedHub` (subscription)
- `PositionIndex` (registration)

**Used by:** `Signal::Engine`, `Entries::BosEntryEngine`

---

## Entries::EntryGuardPipeline

**File:** `app/services/entries/entry_guard_pipeline.rb`

**Purpose:**
Runs 20 guards in sequence. First block wins. Each guard may read or enrich the mutable `context` hash.

**Context keys set by guards:**
- `context[:instrument]` — set by `InstrumentLookupGuard` (required by subsequent guards)
- `context[:ltp]` — set by `LtpResolutionGuard`
- `context[:side]` — set by `ExposureGuard`
- `context[:is_supertrend]` — set by `ExposureGuard`
- `context[:expiry_power_trend]` — set by `ExpiryWeekPowerTrendGuard` (when pattern detected)
- `context[:entry_metadata][:expiry_power_trend]` — also set by `ExpiryWeekPowerTrendGuard`

**Return values:** `:pass` (all guards passed) or `{ blocked: "reason string" }`.

---

## Entries::BosEntryEngine

**File:** `app/services/entries/bos_entry_engine.rb`

**Purpose:**
Break-of-Structure entry state machine. Manages BOS-based entry lifecycle for structure-confirmed entries.

**Used by:** `Signal::Engine` (for BOS entry strategy)

---

## Capital::Allocator

**File:** `app/services/capital/allocator.rb`

**Purpose:**
Central position sizing authority. All sizing must go through this class — never inline the math.

**Modes:**
- **Percentage-based**: `qty = (capital * alloc_pct) / (premium * lot_size)`
- **Rupee-based**: `qty = rupees_at_risk / (premium * lot_size * sl_pct)`

**Lot alignment:** Result rounded down to nearest lot boundary.

**Used by:** `Entries::EntryGuard`, `Orders::EntryManager`

---

## Capital::DynamicRiskAllocator

**File:** `app/services/capital/dynamic_risk_allocator.rb`

**Purpose:**
Adjusts position size based on `Signal::TrendScorer` output. Higher trend score → larger allocation (within configured limits).

**Used by:** `Capital::Allocator` (composition)

---

## Orders::GatewayFactory

**File:** `app/services/orders/gateway_factory.rb`

**Purpose:**
Boot-time gateway selector. Reads `config/algo.yml` → `paper_trading.enabled` and returns the appropriate gateway instance.

```ruby
Orders::GatewayFactory.build
# → Orders::GatewayPaper  if paper_trading.enabled: true
# → Orders::GatewayLive   if paper_trading.enabled: false
```

Used once in `config/initializers/orders_gateway.rb`. Gateway cannot change without restart.

---

## Orders::GatewayLive

**File:** `app/services/orders/gateway_live.rb`

**Purpose:**
Real DhanHQ order execution. Implements the `Orders::Gateway` interface.

**Key methods:**
- `place_market(segment:, security_id:, qty:, direction:, ...)` → submits to DhanHQ
- `flat_position(tracker)` → exit the position
- `cancel_order(order_id)` → cancel pending order

**Safety gates (both required):**
- `dhanhq.enable_orders: true` in config
- `PLACE_ORDER=true` environment variable

**Resilience:**
- Exponential backoff retry on transient errors
- `401 Unauthorized` triggers `Dhan::TokenManager` token refresh
- Already-closed/duplicate exit responses normalized as successful terminal outcomes

**Used by:** `TradingSystem::OrderRouter`, `Live::ExitEngine`

---

## Orders::GatewayPaper

**File:** `app/services/orders/gateway_paper.rb`

**Purpose:**
Simulated order execution. Implements the `Orders::Gateway` interface identically to `GatewayLive` but creates synthetic fills.

**Behavior:**
- `place_market(...)` → reads current LTP from `TickQuery`, creates `PositionTracker` immediately in `:active` state
- `flat_position(tracker)` → reads exit LTP, calls `mark_exited!` immediately
- No DhanHQ API calls made

**Used by:** `TradingSystem::OrderRouter`, `Live::ExitEngine`

---

## Orders::Placer

**File:** `app/services/orders/placer.rb`

**Purpose:**
DhanHQ API wrapper for order placement. Handles payload construction, idempotency checks, and the `PLACE_ORDER` safety gate.

**Safety gate:**
```ruby
# All live buy/sell/exit calls check:
return log_dry_run unless ENV['PLACE_ORDER'] == 'true'
```

**Used by:** `Orders::GatewayLive`

---

## Orders::EntryManager

**File:** `app/services/orders/entry_manager.rb`

**Purpose:**
High-level entry orchestrator that ties together signals, `EntryGuard`, capital allocation, and `ActiveCache` updates.

**Used by:** `Signal::Engine` (alternate entry path)

---

## TradingSystem::OrderRouter

**File:** `app/services/trading_system/order_router.rb`

**Purpose:**
Routes exit and management orders through the configured gateway. Registered as service `:order_router` in the Supervisor.

**Inputs:** Exit/management order parameters
**Outputs:** Delegation to `Orders.config.gateway`

**Used by:** `TradingSystem::Supervisor` (registered service)

---

## Orders::Executor / Adjuster / Analyzer

**Files:** `app/services/orders/executor.rb`, `adjuster.rb`, `analyzer.rb`

**Purpose:**
- `Executor` — wrapper around order submission lifecycle
- `Adjuster` — modify/adjust existing orders (SL adjustment)
- `Analyzer` — analyze current position state for exit decision input

---

## Orders::GammaTrailingEngine

**File:** `app/services/orders/gamma_trailing_engine.rb`

**Purpose:**
Gamma-aware trailing stop engine for NIFTY/BANKNIFTY/SENSEX. Uses option pricing dynamics to adjust trailing SL during gamma ramp periods.

**Used by:** `Live::TrailingEngine`, `Live::UnifiedExitChecker`

---

## Orders::MfeExitEngine

**File:** `app/services/orders/mfe_exit_engine.rb`

**Purpose:**
Maximum Favorable Excursion (MFE) based exit engine. Tracks peak unrealized profit and recommends exit when drawdown from peak exceeds threshold.

**Used by:** `Live::UnifiedExitChecker` (trailing stop evaluation for index instruments)

---

## Orders::AdaptiveTrailing

**File:** `app/services/orders/adaptive_trailing.rb`

**Purpose:**
Adaptive trailing stop logic using `Positions::DrawdownSchedule` for position-specific allowed drawdown.

**Used by:** `Live::TrailingEngine`

---

## Orders::ExpiryRuleEngine

**File:** `app/services/orders/expiry_rule_engine.rb`

**Purpose:**
Applies expiry-specific exit rules (e.g., forced exit before expiry day close, expiry morning decay avoidance).

**Used by:** `Live::RiskManagerService`
