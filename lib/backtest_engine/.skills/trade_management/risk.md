# Risk Audits for Active Positions

Verify that active trade sizes and open risk remain within standard boundaries.

## Risk Parameters

1. **R-Multiple Tracker**:
   - Track active trade PnL in terms of R-multiple (risk units, where `1R = EntryPrice - StopLossPrice`).

2. **Open Portfolio Heat**:
   - Sum the active risk of all open positions.
   - Enforce that total portfolio heat does not exceed `3%` of capital.

3. **Margin & Leverage Compliance**:
   - Check if account cash remains sufficient to cover active option margins (especially if converting positions).
