# Trailing Stop-Loss Algorithms

Implement and compare these trailing algorithms to protect profits during a trend.

## Trailing Algorithms

1. **Fixed Percentage / Points**:
   - Trail a set percentage (e.g. `10%`) or points (e.g. `15 points`) behind the peak observed option premium (MFE).

2. **Average True Range (ATR)**:
   - Trail at a distance of `multiplier * ATR` below the peak price.
   - Adjusts automatically: widens in high volatility, tightens in low volatility.

3. **Chandelier Exit**:
   - Trail at a distance of `multiplier * ATR` below the highest high of the last N candles.

4. **Underlying Swing High / Low**:
   - Trail the stop behind the latest swing-low on the index (for calls) or swing-high (for puts).

5. **Adaptive Trailing**:
   - Dynamically tightens the trail distance as holding time increases or as target profit levels are reached.
