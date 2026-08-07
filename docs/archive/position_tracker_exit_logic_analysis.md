# PositionTracker Exit Logic — Analysis and Fixes

## Exit flow (canonical)

1. **RiskManagerService** (or EOD / BTST clear job) decides to exit → calls **ExitEngine.execute_exit(tracker, reason)**.
2. **ExitEngine.prepare_exit_intent!**  
   Sets `exit_requested_at`, `exit_coid`, meta `exit_reason`. Returns false if already exited or already requested (prevents double intent).
3. **ExitEngine** calls **router.exit_market(tracker, client_order_id: tracker.exit_coid)**.
4. **Gateway (Paper/Live)** places the order; Live gateway returns broker `order_id` → stored in **tracker.exit_order_id** via **persist_broker_ack!**.
5. **ExitEngine.finalize_exit!**  
   Calls **tracker.mark_exited!(exit_price:, exit_reason:)** → status = exited, exit_price, exited_at, PnL persisted, caches cleared, broadcast.

**Live only:** Broker sends fill/cancel via WebSocket → **OrderUpdateHandler.handle_update(payload)**. If payload refers to the **exit** order, the broker’s `order_id` is the **exit** order ID, not the entry `order_no`.

---

## Issues identified and fixes

### 1. OrderUpdateHandler could not find tracker for exit-order fills (live)

- **Problem:** Handler looked up tracker by `order_no` only. For an **exit** fill, the payload `order_no`/`order_id` is the **broker’s exit order ID**, which is stored in `tracker.exit_order_id`, not `order_no`. So exit fills never matched a tracker and were ignored.
- **Fix:** **OrderUpdateHandler** now resolves the tracker by **order_no or exit_order_id** (`find_tracker_by_order_id`), so exit-order updates from the broker correctly find the tracker and call `mark_exited!`.

### 2. No way to query “stuck” positions (exit requested but still active)

- **Problem:** Positions with `exit_requested_at` set but still `active` (e.g. order failed or never filled) were only discoverable by scanning all active trackers.
- **Fix:** **PositionTracker** scope **`active_with_exit_requested`** added: `active.where.not(exit_requested_at: nil)`. Use for monitoring, alerts, or retry (e.g. `position:force_exit` / ClearCarriedOvernightPositionsJob already clear intent and retry when they see `exit_already_requested`).

### 3. Lookup by exit_order_id not indexed

- **Problem:** `PositionTracker.find_by(exit_order_id: order_id)` could do a full table scan.
- **Fix:** Migration **20260312000000_add_index_position_trackers_exit_order_id** adds **index on exit_order_id** for fast lookup.

### 4. Not changed: clearing exit intent on router failure

- **Considered:** On `router.exit_market` failure, clear `exit_requested_at` so the next enforcement cycle can retry.
- **Decision:** Not implemented. Clearing on failure could cause a second exit order if the first was actually placed (e.g. timeout after send). Stuck positions are handled by **rake position:force_exit** and **ClearCarriedOvernightPositionsJob**, which clear intent and retry when they see `exit_already_requested` and the tracker still active.

---

## State summary

| State | exit_requested_at | exit_sent_at | status  | Meaning |
|-------|-------------------|--------------|---------|--------|
| Active, no exit   | nil   | nil   | active  | Normal open position |
| Exit requested    | set   | nil   | active  | Intent persisted; order not yet sent or send failed |
| Exit sent         | set   | set   | active  | Order sent; waiting fill (or finalize_exit! about to run) |
| Exited            | set*  | set*  | exited  | mark_exited! called (by ExitEngine or OrderUpdateHandler) |

\* When exited via ExitEngine, both are set. When exited via OrderUpdateHandler (broker fill), they may be nil.

---

## Files touched

- `app/services/live/order_update_handler.rb` — find tracker by `order_no` or `exit_order_id`.
- `app/models/position_tracker.rb` — scope `active_with_exit_requested`.
- `db/migrate/20260312000000_add_index_position_trackers_exit_order_id.rb` — index on `exit_order_id`.
