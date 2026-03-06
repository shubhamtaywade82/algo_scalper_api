# DhanHQ Broker Integration

The system integrates with DhanHQ via their official APIs for order execution, position synchronization, and authentication.

## Authentication & Token Management

- **Credentials**: Managed via environment variables:
  - `DHAN_CLIENT_ID` / `CLIENT_ID`
  - `DHAN_ACCESS_TOKEN` / `ACCESS_TOKEN`
- **Token Auto-Healing**: The `Orders::Placer` and `DhanHQ::Client` are designed to detect `401 Unauthorized` errors. If an error occurs during order placement, the system attempts to refresh the session if refresh tokens are available, or logs a fatal error and trips the `CircuitBreaker`.
- **Reference**: See `app/models/dhan_access_token.rb` for persistence logic.

## Order Execution Pipeline

When the `OrderRouter` receives a live entry/exit request:
1.  **Validation**: `Orders::Placer` ensures the segment is tradable and the security ID is valid.
2.  **Payload Construction**: Builds the JSON payload for Market, Limit, or Bracket orders.
3.  **API Submission**: POSTs to the DhanHQ Order endpoint.
4.  **Error Handling**:
    -   **Insufficient Margin**: Rejects the entry and logs the reason.
    -   **Rate Limiting**: Implementation of exponential backoff.
    -   **Success**: Returns the `order_no` which is then used to track the position.

## Position Synchronization
The `Live::PositionSyncService` (invoked during `Bootstrap`) ensures that the local `PositionTracker` records match the open positions in the DhanHQ back-office. This prevents "ghost positions" where the bot thinks a trade is closed but it remains open at the broker (or vice versa).

## Performance Notes
- **Latency**: Orders are placed directly via HTTP. Typical latency is 50-200ms depending on broker response time.
- **Segment Mapping**: The system strictly maps Dhan specific segment IDs (e.g., `2` for NSE_FNO) to internal symbols.
