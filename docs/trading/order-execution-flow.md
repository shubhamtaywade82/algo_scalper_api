# Order Execution Flow

Detailed technical trace of order placement and management.

## 1. Entry Order Placement
When a signal is validated, the `Orders::EntryManager` coordinates the placement.

1.  **Resolved Pick**: Includes segment, security_id, and calculated quantity.
2.  **Order Routing**: `OrderRouter` selects either `GatewayLive` or `GatewayPaper` based on `algo.yml`.
3.  **DhanHQ Placer**: Calls `Orders::Placer.buy_market!` or `bracket_buy!`.
4.  **Tracking**: A `PositionTracker` record is created in the database with the resulting `order_no`.

## 2. Order Types Supported
- **Market Orders**: Default for low-latency entry.
- **Bracket Orders (BO)**: Optionally used for certain instruments to place hard SL/TP on the broker's side.
- **Limit Orders**: Used primarily during manual overrides or specific strategies.

## 3. Position State Lifecycle
- **init**: Order requested but not confirmed.
- **active**: Order executed; position is live and being monitored.
- **exited**: Position closed at the broker.
- **cancelled**: Signal invalidated or order rejected before execution.

## 4. Reconciliation
`Live::PositionSyncService` runs periodically to ensure that the local `PositionTracker` status matches the actual backlog at the broker, correcting any "ghost positions".
