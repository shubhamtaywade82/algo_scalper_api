# Trailing Stop Parameter Optimization

This skill sweeps parameter configurations to identify optimal trailing zones.

## Swept Parameters
* **Activation Level**: `[0.5R, 1.0R, 1.5R, 2.0R]`
* **Trail Distance**: `[1.0 * ATR, 1.5 * ATR, 2.0 * ATR, 2.5 * ATR, 3.0 * ATR]`
* **Time / Decay modifiers**: Stop tightening speed per minute held.
* **Tightening Rules**: Switch to tight trail near key walls.

## Evaluation Process
1. Run sweeps across historical trades.
2. Select parameter combinations that maximize expectancy.
3. Reject "isolated spikes" and prefer broad, stable parameter valleys.
