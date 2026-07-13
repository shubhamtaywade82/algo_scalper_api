# Trailing Stop Validation Protocols

Verify that trailing stop simulations are correct and free of lookahead bias.

## Validation Checks

1. **Monotonicity Verification**:
   - Asserts that the simulated stop-loss level only increases (or remains constant). Stops must never decrease during a long option trade.

2. **Intrabar High/Low Checks**:
   - For stop triggers inside a candle, do not assume execution at the high price of the candle before the low price is tested.
   - Run worst-case simulations to verify stop execution boundaries.

3. **Leakage Scan**:
   - Confirm that the trailing stop calculator does not access future prices or future ATR values.
