# Stop-Loss Methodologies

Options buying requires structured stops to manage high volatility and decay.

## Stop Types

1. **Initial Fixed % Stop**:
   - Exit when option premium drops by a set percentage (e.g. `20%` or `30%`).
   - Default fallback safety net.

2. **Underlying Swing Low Stop**:
   - For CALL: exit if the underlying spot index closes below the swing low.
   - For PUT: exit if the underlying spot index closes above the swing high.
   - Prevents premature option exits due to temporary premium implied volatility shifts.

3. **Time-Based Stop**:
   - Option premiums lose value over time (theta decay).
   - If the trade does not develop in our favor within a set timeframe (e.g. 15-25 minutes), exit immediately to preserve capital.

4. **Volatility Stop**:
   - Exit if Average True Range (ATR) compresses or if Implied Volatility (IV) crushes.
