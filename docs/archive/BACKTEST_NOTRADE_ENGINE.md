# NoTradeEngine Backtest Guide

## Overview

Backtest the NoTradeEngine with index-specific thresholds for NIFTY and SENSEX on 1m and 5m timeframes (intraday).

## Quick Start

### Backtest NIFTY and SENSEX on Both Timeframes

```bash
# Default: 30 days lookback
rails 'backtest:no_trade_engine:nifty_sensex_intraday'

# Specify lookback period
rails 'backtest:no_trade_engine:nifty_sensex_intraday[45]'

# Using environment variable
DAYS_BACK=60 rails backtest:no_trade_engine:nifty_sensex_intraday
```

### Backtest Single Index and Timeframe

```bash
# NIFTY 5m, 30 days
rails 'backtest:no_trade_engine:single[NIFTY,5,30]'

# SENSEX 1m, 45 days
rails 'backtest:no_trade_engine:single[SENSEX,1,45]'

# Using environment variables
INDEX=NIFTY TIMEFRAME=5 DAYS_BACK=30 rails backtest:no_trade_engine:single
```

## What Gets Tested

### Timeframes
- **1m**: Signals generated on 1m, entries on 1m
- **5m**: Signals generated on 5m, entries on 1m (for precise entry timing)

### Indices
- **NIFTY**: Uses NIFTY-specific thresholds
- **SENSEX**: Uses SENSEX-specific thresholds

### NoTradeEngine Validation
- **Phase 1**: Quick pre-check (time windows, basic volatility)
- **Phase 2**: Full validation with index-specific thresholds:
  - ADX trend strength (NIFTY < 14, SENSEX < 12)
  - DI separation (NIFTY < 2.0, SENSEX < 1.5)
  - VWAP chop detection (NIFTY: ±0.08% for 3+, SENSEX: ±0.06% for 2+)
  - Range thresholds (NIFTY < 0.06%, SENSEX < 0.04%)
  - ATR downtrend (NIFTY: 5+ bars, SENSEX: 3+ bars)
  - IV thresholds (NIFTY < 9, SENSEX < 11)
  - Spread thresholds (NIFTY > ₹3, SENSEX > ₹5)
  - Wick ratio (NIFTY > 2.2, SENSEX > 2.5)

## Output Metrics

### Trading Performance
- **Total Trades**: Number of trades executed
- **Win Rate**: Percentage of profitable trades
- **Total P&L**: Cumulative profit/loss percentage
- **Expectancy**: Average expected return per trade
- **Avg Win/Loss**: Average winning and losing trade percentages
- **Max Drawdown**: Maximum peak-to-trough decline

### NoTradeEngine Stats
- **Phase 1 Blocked**: Trades blocked before signal generation
- **Phase 2 Blocked**: Trades blocked after signal generation
- **Signals Generated**: Total signals generated
- **Trades Executed**: Trades that passed all validations
- **Block Rate**: Percentage of signals blocked by NoTradeEngine
- **Top Block Reasons**: Most common reasons for blocking trades

## Example Output

```
================================================================================
NoTradeEngine Backtest - NIFTY & SENSEX (Intraday)
================================================================================
Lookback Period: 30 days
Timeframes: 1m and 5m
Indices: NIFTY, SENSEX
================================================================================

--------------------------------------------------------------------------------
Backtesting NIFTY @ 1m (Intraday)
--------------------------------------------------------------------------------

📊 Results for NIFTY @ 1m:
   Total Trades: 45
   Win Rate: 48.89%
   Total P&L: 12.34%
   Expectancy: 0.27% per trade
   Avg Win: +2.15%
   Avg Loss: -1.88%
   Max Drawdown: -8.45%

🚫 NoTradeEngine Stats:
   Phase 1 Blocked: 123
   Phase 2 Blocked: 67
   Signals Generated: 190
   Trades Executed: 45
   Block Rate: 76.32%

   Top Phase 2 Block Reasons:
     - Weak trend: ADX < 14: 23
     - VWAP chop: price within ±0.08% for 3+ candles: 15
     - Low volatility: 10m range 0.05% < 0.06%: 12
```

## Performance Analysis

The backtest will automatically:
1. Compare performance across timeframes (1m vs 5m)
2. Compare performance across indices (NIFTY vs SENSEX)
3. Identify the best performing combination
4. Show detailed block reasons to understand what conditions are most effective

## Notes

- **Intraday Only**: Only trades during market hours (9:15 AM - 3:15 PM IST)
- **Historical Data**: Uses `instrument.intraday_ohlc()` to fetch historical data
- **Option Chain**: Simulated for historical data (IV/spread checks use defaults)
- **Index-Specific**: Automatically uses correct thresholds based on index symbol

## Troubleshooting

### No Data Available
- Check if DhanHQ API is accessible
- Verify instrument security IDs in `algo.yml`
- Check network connectivity

### No Trades Generated
- NoTradeEngine may be blocking all signals (check block reasons)
- Try increasing lookback period
- Check if historical data has sufficient volatility

### Performance Issues
- Reduce lookback period for faster testing
- Run single index/timeframe instead of all combinations

