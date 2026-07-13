# Regime-Specific Trailing Stop Rules

Trailing efficiency varies significantly across market conditions.

## Regime Classifications

1. **Strong Trend Regime**:
   - Best Exits: Loose trailing stops (`2.5 * ATR` or swing low) to capture maximum movement.
   - Fixed targets are disabled.

2. **Range-Bound / Consolidating Regime**:
   - Best Exits: Fixed target exits at `1.5R` or `2.0R`.
   - Trailing stops are disabled or set to activate immediately to protect capital.

3. **High Volatility / Expiry Regime**:
   - Best Exits: Volatility-adaptive stops that tighten as IV drops or as close approaches.
