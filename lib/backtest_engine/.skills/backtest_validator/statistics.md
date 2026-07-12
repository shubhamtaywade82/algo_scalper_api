# Backtest Statistical Metrics Guide

Verify the formulas used to calculate strategy metrics to ensure mathematical consistency.

## Metrics Definitions

1. **Expectancy (R-Multiplier)**:
   - Average trade return. `Expectancy = (WinRate * AvgWin) - (LossRate * AvgLoss)`.

2. **Sharpe & Sortino Ratios**:
   - Sharpe: Average excess return divided by standard deviation of returns.
   - Sortino: Average excess return divided by standard deviation of *negative* returns (downside deviation).

3. **Calmar Ratio**:
   - CAGR (Compound Annual Growth Rate) divided by Maximum Drawdown.

4. **Ulcer Index (UI)**:
   - Measures drawdown depth and duration. `UI = Sqrt(Sum(Drawdown_i^2) / N)`.

5. **System Quality Number (SQN)**:
   - Evaluates system viability. `SQN = (Expectancy / StdDev_PnL) * Sqrt(N)`. An SQN $> 3.0$ indicates a highly robust system.
