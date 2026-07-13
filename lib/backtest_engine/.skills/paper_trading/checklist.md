# Paper Trading Checklist

Verify these checklist items to confirm virtual broker configuration correctness.

## 1. Adapter & Feed Setup
- [ ] Connect virtual broker adapter to Dhan live WebSocket tick feed (or historical replay file).
- [ ] Verify that order routing points to `sandbox.dhan.co`.
- [ ] Confirm option chain quotes and Greeks are loaded.

## 2. Order Types & Execution
- [ ] Test Market and Limit order placements.
- [ ] Verify Stop-Loss (SL) and Stop-Loss-Market (SL-M) order matching.
- [ ] Confirm order cancellation and modification pathways.
- [ ] Enforce bid-ask spread slippage models.

## 3. Account & Sizing Limits
- [ ] Initialize starting cash balance.
- [ ] Check margin requirement values before placing orders.
- [ ] Track active realized and unrealized P&L.
- [ ] Run daily loss limit audits.
- [ ] Confirm EOD squareoff triggers at 15:15.
