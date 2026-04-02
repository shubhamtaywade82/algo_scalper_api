# Order Execution Flow

Detailed technical trace of order placement and management.

## Overview

The order execution path has two modes — paper and live — selected once at boot by `Orders::GatewayFactory`. Both modes share the same entry guard pipeline and capital allocation logic. The difference is entirely in what happens after a validated entry reaches the gateway.

## Gateway Selection (Boot)

```ruby
# config/initializers/orders_gateway.rb
Orders.config.gateway = Orders::GatewayFactory.build
# → Orders::GatewayPaper  if paper_trading.enabled: true
# → Orders::GatewayLive   if paper_trading.enabled: false
```

Gateway is fixed at boot. Switching requires a restart.

**Live mode additional safety gates** (both required):
- `config/algo.yml` → `dhanhq.enable_orders: true`
- ENV var `PLACE_ORDER=true`

Without both set, `Orders::Placer` logs the attempt as "dry-run" and does not submit to DhanHQ.

---

## 1. Entry Order Placement

### Paper Mode Flow

```
Entries::EntryGuard.try_enter
  → Capital::Allocator.qty_for (lot-aligned quantity)
  → Orders::GatewayPaper.place_market(segment:, security_id:, qty:, direction:, ...)
    → Synthetic fill at current LTP from TickCache
    → PositionTracker.create! (status: :active, entry_price: ltp, order_no: synthetic)
    → Live::MarketFeedHub.subscribe(security_id, segment)
    → PositionIndex.register(tracker)
```

### Live Mode Flow

```
Entries::EntryGuard.try_enter
  → Capital::Allocator.qty_for (lot-aligned quantity)
  → Orders::GatewayLive.place_market(segment:, security_id:, qty:, direction:, ...)
    → Orders::Placer.buy_market!(...)
      → Check PLACE_ORDER=true (else log dry-run, return nil)
      → Build DhanHQ order payload
      → DhanHQ API POST /orders
      → Returns order_no
    → PositionTracker.create! (status: :pending, order_no: dhan_order_no)
    → Live::MarketFeedHub.subscribe(security_id, segment)
    → [Later, via OrderUpdateHandler]
      → PositionTracker.mark_active! (on fill event)
```

---

## 2. Order Types Supported

| Type | When used | Implementation |
|------|-----------|----------------|
| Market order (BUY) | Standard entry — default for low-latency fill | `Orders::Placer.buy_market!` |
| Market order (SELL) | Exit — close long position | `Orders::Placer.sell_market!` |
| Exit order | Generic exit (used by ExitEngine) | `Orders::GatewayLive.exit_position` / `GatewayPaper.flat_position` |

---

## 3. Position State Lifecycle

```
[entry request]
     │
     ▼
 pending ──────────────────────────────────────► cancelled
     │    (order rejected / guard block)
     │ (fill confirmed via OrderUpdateHandler)
     ▼
  active ──────────────────────────────────────► exited
         (exit engine places exit order → fill)
```

- **pending**: Order placed, awaiting fill confirmation from DhanHQ WebSocket
- **active**: Fill confirmed; position is live and being monitored by RiskManager
- **exited**: Exit fill confirmed; `persist_final_pnl_from_cache` recalculates realized PnL
- **cancelled**: Entry failed before order placement or order rejected by broker

Paper mode: skips `pending` — goes directly to `active` with synthetic fill.

---

## 4. Exit Order Placement

All exits flow through `Live::ExitEngine.execute_exit`:

```
ExitEngine.execute_exit(tracker:, reason:, price:)
  → Guard: skip if already exit_requested or exit_sent
  → Set: tracker.exit_requested_at = Time.current
  → Set: tracker.exit_coid = deterministic client order ID (idempotency)
  → Orders.config.gateway.flat_position(tracker) or exit_position(...)
    → [Paper] GatewayPaper.flat_position → synthetic exit at current LTP
    → [Live]  GatewayLive.flat_position → Orders::Placer.sell_market! → DhanHQ API
  → Set: tracker.exit_sent_at = Time.current
  → [Paper] PositionTracker.mark_exited! immediately
  → [Live]  OrderUpdateHandler.on_fill → PositionTracker.mark_exited! (on fill event)
  → persist_final_pnl_from_cache (recalculate from actual final_pnl, not stale Redis)
  → Live::MarketFeedHub.unsubscribe(security_id)
  → PositionIndex.deregister(tracker)
```

---

## 5. Order Fill Handling

`Live::OrderUpdateHandler` processes DhanHQ WebSocket order events:

- `order_filled` → `PositionTracker.mark_active!` (entry) or `mark_exited!` (exit)
- `order_cancelled` → `PositionTracker.mark_cancelled!`
- `order_rejected` → log + alert

Handlers are **idempotent**: duplicate events (feed reconnect, replay) are safe.

---

## 6. Reconciliation

`Live::ReconciliationService` runs every 30 seconds:
- Queries DhanHQ positions API
- Cross-references with `PositionTracker.active`
- Detects and corrects:
  - **Ghost positions**: tracked as active in DB but closed at broker
  - **Orphan positions**: open at broker but not tracked in DB

At daemon boot, `Live::PositionSyncService.force_sync!` runs a strict reconciliation before starting trading services.

---

## 7. Error Handling

| Error | Handling |
|-------|---------|
| `401 Unauthorized` from DhanHQ | `GatewayLive` detects and triggers token refresh via `Dhan::TokenManager` |
| Insufficient margin | Entry rejected; `EntryGuard` receives nil order_no → entry fails gracefully |
| Rate limit / timeout | `Orders::Placer` implements exponential backoff with up to N retries |
| Missing order_no in response | `EntryGuard` treats as failure; `PositionTracker` not created |
| Duplicate order (coid already used) | `GatewayLive` normalizes as successful terminal outcome |

---

## 8. Idempotency

- `exit_coid` — deterministic client order ID on every exit attempt; allows safe retry without double-exit
- `OrderUpdateHandler` checks current tracker state before state transitions
- `ExitEngine` checks `exit_requested_at` / `exit_sent_at` before placing another exit

---

## 9. Key Files

| File | Purpose |
|------|---------|
| `app/services/orders/gateway_factory.rb` | Boot-time gateway selection |
| `app/services/orders/gateway_live.rb` | Real DhanHQ execution |
| `app/services/orders/gateway_paper.rb` | Simulated fills |
| `app/services/orders/placer.rb` | DhanHQ API, PLACE_ORDER gate, idempotency |
| `app/services/live/exit_engine.rb` | Single source of truth for exits |
| `app/services/live/order_update_handler.rb` | WebSocket fill/cancel processing |
| `app/services/live/order_update_hub.rb` | DhanHQ order update WebSocket |
| `app/services/live/reconciliation_service.rb` | 30s broker/DB sync |
| `app/services/live/position_sync_service.rb` | Startup reconciliation |
