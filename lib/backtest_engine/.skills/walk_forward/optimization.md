# In-Sample Parameter Optimization Rules

Optimization must be performed strictly within the boundaries of the training partition.

## Rules
* **No Future Access**: The optimizer cannot access prices, indicator values, or volatility calculations that fall within the out-of-sample test window.
* **Objective Function**: Optimize parameters to maximize a robust utility function (e.g. `expectancy * Sharpe`) rather than simply net profit, to avoid picking fragile overfitted peaks.
