# Slippage Modeling in Virtual Exchange

Replicate pricing slippage to ensure paper trading performance matches live execution.

## Slippage Models

1. **Spread-Based Slippage**:
   - Executes market orders at the opposite touch price (Ask for BUY, Bid for SELL) using the active bid-ask spread.

2. **Volatility-Adaptive Slippage**:
   - Multiplies slippage by an ATR factor. High-volatility breakout fills suffer higher slippage penalties than pullback fills.

3. **Liquidity-Based Slippage**:
   - Increases slippage dynamically when order size exceeds the average size available at the top depth levels.
