# Parameter Evolution & Stability

Audit parameter modifications across rolling walk-forward windows.

## Stability Metrics

1. **Parameter Drift**:
   - Track the values of optimized parameters (e.g. EMA lookback) from window `i` to window `i+1`.
   - Rapid or erratic changes indicate a fragile strategy that is constantly curve-fitting to recent noise.

2. **Parameter Clustering**:
   - Plot optimal parameter locations across windows.
   - We prefer clusters inside a stable zone (e.g. lookbacks consistently ranging between 18 and 22). Reject strategies with parameters jumping between extreme boundaries.
