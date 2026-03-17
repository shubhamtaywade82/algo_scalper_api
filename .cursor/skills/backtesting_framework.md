# Backtesting Architecture

Framework for executing deterministic backtests on historical NIFTY/SENSEX data.

## Pipeline
1. **Load Data**: Fetch OHLCV candles from DhanHQ historical intraday endpoint or local cache.
2. **Replay Engine**: Feed candles sequentially into the `CandleSeries` builder.
3. **Detection Loop**:
   - Step 1: Identify Swing Highs/Lows.
   - Step 2: Update structural state (BOS/CHoCH).
   - Step 3: Identify institutional footprints (OB/FVG/Sweeps).
4. **Execution Simulation**:
   - Entry on FVG/OB retest.
   - Trigger within Kill Zones (09:15-10:30, 14:00-15:15).
5. **PnL Computation**:
   - Account for slippage (0.1% - 0.2%) and STT/Fees.
   - Calculate performance metrics.

## Metrics
- **Win Rate**: % of profitable trades.
- **Max Drawdown**: Peak-to-trough decline.
- **Profit Factor**: Gross Profit / Gross Loss.
- **Average P&L per trade**: Total P&L / Total Trades.
- **Sharpe Ratio**: Risk-adjusted return.
