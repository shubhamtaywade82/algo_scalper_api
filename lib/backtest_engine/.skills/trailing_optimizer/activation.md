# Trailing Activation Rules

Trailing stops should not activate immediately. This researcher optimizes activation thresholds:

## Activation Rules

1. **R-Multiple Activation**:
   - Delay trailing stop until the trade reaches `0.5R`, `1.0R`, `1.5R`, or `2.0R` open profit.
   - Prevents early exit due to minor pricing pullback fluctuations near entry.

2. **Structural Activation**:
   - Delay trailing until the underlying index confirms a Break of Structure (BOS) or volume spike in the trade direction.

3. **IV Expansion Activation**:
   - Activate or tighten trailing stops as soon as Implied Volatility (IV) begins to contract, locking in premium gains.
