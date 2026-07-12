# P&L Attribution Modeling

Attribute net portfolio returns to specific component decisions.

## Attribution Components

1. **Entry Edge**:
   - Return calculated assuming a fixed risk target (e.g. exit at 1.5R) without dynamic trailing.
   - Measures signal predictive power.

2. **Exit / Trailing Edge**:
   - Difference between actual returns and fixed target returns.
   - Measures the value added (or lost) due to trailing stops.

3. **Slippage & Slippage Cost**:
   - The drag on returns caused strictly by bid-ask spreads and execution delays.

4. **Transaction Cost Drag**:
   - Returns lost to brokerage, STT, and exchange fees.
