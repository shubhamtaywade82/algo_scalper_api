# Regime-Adaptive Exits

Adapt the trade management parameters dynamically based on the detected market regime.

## Adaptive Rules

1. **Strong Trend Regime**:
   - Apply a loose trailing stop-loss (e.g. `3.0 * ATR` or swing low) to allow maximum trend capture.
   - Set targets to open-ended trailing targets.

2. **Range-Bound / Choppy Regime**:
   - Apply tight fixed risk targets (e.g. exit at `1.5R`).
   - Move stop-loss to breakeven quickly.

3. **High Volatility Regime**:
   - Tighten trailing stops (e.g. `1.5 * ATR`) to protect against sharp reversals.
   - Reduce position sizes.
