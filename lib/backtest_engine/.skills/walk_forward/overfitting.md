# Overfitting and Curve-Fitting Detection

Identify signs of curve-fitting during rolling optimizations.

## Detection Rules

1. **Expectancy Degradation**:
   - Compare in-sample (optimized) expectancy vs out-of-sample (forward) expectancy.
   - If forward expectancy decays by more than 40% (i.e. $\text{WFE} < 0.60$), flag the strategy as **overfitted**.

2. **Parameter Count Penalty**:
   - Apply a penalty score for each additional free parameter optimized. Strategies with $> 4$ parameters optimized simultaneously are at high risk of curve-fitting.
