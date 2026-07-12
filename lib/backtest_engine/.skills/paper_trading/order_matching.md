# Order Matching Rules for Virtual Broker

Replicate real exchange order books using these matching parameters.

## Matching Parameters

1. **Touch Price Matching**:
   - Buy limit orders: Fill only if `LTP <= LimitPrice`.
   - Sell limit orders: Fill only if `LTP >= LimitPrice`.

2. **Order Book Depth & Impact**:
   - Limit order fills are capped by the quantity available at that price level in the Dhan market feed depth packet.
   - If order size exceeds depth, execute partial fills.

3. **Execution Latency**:
   - Add a default execution latency (e.g. `200ms` for API round-trip). Orders are filled at the price active *after* the latency window.
