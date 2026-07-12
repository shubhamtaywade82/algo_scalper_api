# Indicator Research Checklist

Use this checklist to ensure all indicators are validated and free of lookahead/redundancy bias.

## 1. Calculation & Verification Gate
- [ ] Code the indicator formula in a modular, independent class.
- [ ] Check output values against TradingView, TA-Lib, or pandas-ta.
- [ ] Ensure correct warmup handling (ignore first N index candles).
- [ ] Check NaN, division-by-zero, and boundary condition handling.
- [ ] Verify there is no lookahead bias (indicator must only use prior completed candles).

## 2. Parameter Sweep Gate
- [ ] Perform a parameter grid search across periods, multipliers, and smoothing windows.
- [ ] Calculate Profit Factor, Expectancy, Sharpe, and Sortino for each parameter set.
- [ ] Identify the optimal parameter range (avoiding over-fitted peaks).
- [ ] Assess parameter stability (returns should decline smoothly, not drop off a cliff).

## 3. Correlation & Redundancy Gate
- [ ] Compute the correlation matrix against all existing indicators.
- [ ] Measure mutual information and Variance Inflation Factor (VIF).
- [ ] Reject any indicators with correlation $> 0.70$ to avoid redundant signals.

## 4. Deliverables & Knowledge Base Update
- [ ] Save optimal parameter ranges to the database.
- [ ] Map indicators to suitable market regimes.
- [ ] Generate rankings and update `data/knowledge_base/indicators/`.
