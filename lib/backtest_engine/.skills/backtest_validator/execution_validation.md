# Execution Validation Guide

Ensure simulated fills match realistic market conditions and account for latency and impact costs.

## Execution Audits

1. **Order Fills**:
   - Limit orders: Fill only if price traded *past* the limit price (not just touching it), unless queue position is modeled.
   - Market orders: Fill at the ask (for buys) and bid (for sells) at the end of the execution delay.

2. **Slippage Enforcement**:
   - Apply a baseline slippage percentage:
     - NIFTY options: `0.5%` - `1.0%` of option premium.
     - SENSEX / BANKNIFTY options: `1.0%` - `2.0%` due to wider spreads.

3. **Latency Squeeze**:
   - Apply a simulation latency delay (e.g. `200ms` for API round-trip). If the price moves against the trade during this delay, fill at the worse price.
