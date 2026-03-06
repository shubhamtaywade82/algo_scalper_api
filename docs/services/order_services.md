# Order & Execution Services

Detailed documentation for services within the `Orders::` and `Entries::` namespaces.

## Entries::EntryGuard

**File:** `app/services/entries/entry_guard.rb`

**Purpose:**
Acts as the final gatekeeper for all order entries. Enforces hard safety rules like circuit breakers, exposure limits, and capital allocation.

**Inputs:**
- `index_cfg`: Configuration context.
- `pick`: The selected option strike to buy.
- `direction`: Bullish or Bearish.

**Outputs:**
- `true/false` (Success/Failure of order placement).
- Persisted `PositionTracker` record on success.

**Dependencies:**
- `Risk::CircuitBreaker`
- `Live::EdgeFailureDetector`
- `Trading::CapitalAllocator`
- `Orders::Gateway`

**Used by:**
- `Signal::Engine`
- `Entries::BosEntryEngine`

---

## Orders::Manager

**File:** `app/services/orders/manager.rb`

**Purpose:**
Simplifies the interface for placing market buy orders from signals.

**Inputs:**
- `segment`, `security_id`, `qty`.
- `reason`: String explanation for the trade.

**Outputs:**
- Calls `Orders::Placer.buy_market!`.

**Dependencies:**
- `Orders::Placer`

**Used by:**
- `Signal::Scheduler` (Legacy)
- Controllers

---

## Orders::Placer

**File:** `app/services/orders/placer.rb`

**Purpose:**
Direct interface for the DhanHQ API models. Handles the raw payload construction for broker execution.

**Inputs:**
- Raw order parameters (Symbol, Side, Qty).

**Outputs:**
- Broker response object (includes `order_id`).

**Dependencies:**
- `DhanHQ::Models::Order`

**Used by:**
- `Orders::Manager`
- `Entries::EntryGuard`
- `Live::ExitEngine`

---

## TradingSystem::OrderRouter

**File:** `app/services/trading_system/order_router.rb`

**Purpose:**
Routes order requests to the appropriate gateway implementation, allowing seamless switching between Live and Paper trading.

**Inputs:**
- Order parameters.

**Outputs:**
- Delegation to `GatewayLive` or `GatewayPaper`.

**Dependencies:**
- `Orders::GatewayLive`
- `Orders::GatewayPaper`

**Used by:**
- `Supervisor`
- `ExitEngine`
