# name: backtest-smc-strategy
description: Executes a deterministic backtest on historical NIFTY/SENSEX data.

# Backtesting Workflow

1. **Load Data:** Fetch OHLCV data for the target index (NIFTY/SENSEX) and its corresponding ATM option chain.
2. **Map Structure:** Identify Swing Highs/Lows using a pivot length of 3–5 candles.
3. **Detect Imbalance:** Locate unmitigated FVGs ($High(C_{n-2}) < Low(C_n)$ for bullish) and Order Blocks (last opposing candle).
4. **Identify Inducement:** Locate liquidity sweeps of internal highs/lows before reaching a HTF Point of Interest (POI).
5. **Simulate Execution:** Enter long on a 1m/5m CHoCH + FVG retest within the 09:15–10:30 Kill Zone.
6. **Report Metrics:** Calculate Win Rate, P&L, Max Drawdown, and Average P&L per trade.

# Verification Rules
- All structure changes must be confirmed only on candle close.
- No new entries allowed after 15:00 IST.
- Simulated slippage must be applied to all market orders.
