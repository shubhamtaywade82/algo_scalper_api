# Parameter Optimization Guide

Optimize indicators systematically to discover parameter ranges that offer stable predictive value without curve-fitting.

## Optimization Process

1. **Parameter Sweeps**:
   - Define a search grid of combinations (e.g., lookback: `[10, 14, 20, 30, 50]`, multiplier: `[1.5, 2.0, 2.5, 3.0]`).
   - Run historical sweeps across different months and underlyings.

2. **Metrics to Evaluate**:
   - **Lag**: The average number of minutes/candles between a structural price event and the indicator trigger.
   - **False Positive Rate**: Signals that triggered but resulted in a reversal in the opposite direction.
   - **Stability**: The variance of indicator returns. We prefer parameter zones where nearby values (e.g. lookbacks of 19, 20, and 21) produce similar performance profiles. Avoid "isolated peaks" which are products of overfitting.
