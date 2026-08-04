# Position Scaling and Partial Profit Rules

Maximize expectancy by adjusting position size dynamically during the trade.

## Scaling Rules

1. **Partial Exits (Scaling Out)**:
   - Sell `50%` of the position at `1.5R` or `2.0R` to lock in profits and cover transaction costs.
   - Trail the remaining `50%` using a loose trailing stop to capture extended moves.

2. **Pyramiding (Scaling In)**:
   - Add size (e.g. `25%` of initial quantity) on a successful breakout pullback, provided the trade is already in profit and the stop-loss has been moved to breakeven.
   - **Crucial Rule**: Never add size to a losing option position.
