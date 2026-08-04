# Indicator Parameter Optimization Scripts

## Overview

The `optimize_indicator_parameters.rb` script performs grid search optimization to find the best indicator parameters for each index (NIFTY, BANKNIFTY, SENSEX).

## Features

- **Grid Search**: Tests multiple parameter combinations systematically
- **Multiple Indicators**: Optimizes Supertrend, ADX, RSI, MACD parameters
- **Performance Metrics**: Evaluates win rate, profit factor, Sharpe ratio, expectancy
- **Per-Index Optimization**: Finds optimal parameters for each index separately
- **CSV Export**: Saves all results to CSV for further analysis

## Usage

### Basic Usage

The script automatically disables WebSocket connections and trading services. You can run it directly:

```bash
# Optimize for NIFTY (default: 30 days, 1m interval)
rails runner scripts/optimize_indicator_parameters.rb NIFTY

# Optimize for BANKNIFTY with 60 days of data
rails runner scripts/optimize_indicator_parameters.rb BANKNIFTY 60

# Optimize for SENSEX with 30 days, 5m interval
rails runner scripts/optimize_indicator_parameters.rb SENSEX 30 5
```

### With Environment Variables (Recommended)

To explicitly disable WebSocket and trading services, set environment variables:

```bash
# Optimize for NIFTY with explicit environment variables
SCRIPT_MODE=1 DISABLE_TRADING_SERVICES=1 BACKTEST_MODE=1 rails runner scripts/optimize_indicator_parameters.rb NIFTY 60 1

# Optimize for BANKNIFTY
SCRIPT_MODE=1 DISABLE_TRADING_SERVICES=1 BACKTEST_MODE=1 rails runner scripts/optimize_indicator_parameters.rb BANKNIFTY 60 1

# Optimize for SENSEX
SCRIPT_MODE=1 DISABLE_TRADING_SERVICES=1 BACKTEST_MODE=1 rails runner scripts/optimize_indicator_parameters.rb SENSEX 60 1
```

**Environment Variables:**
- `SCRIPT_MODE=1` - Disables trading services initialization
- `DISABLE_TRADING_SERVICES=1` - Prevents all trading services from starting
- `BACKTEST_MODE=1` - Enables backtest mode (disables WebSocket)

**Note**: The script also sets these variables internally, but setting them explicitly in the command ensures they're available before Rails initializers load.

### Parameters

1. **Index Key** (required): `NIFTY`, `BANKNIFTY`, or `SENSEX`
2. **Days Back** (optional, default: 30): Number of days of historical data to use
3. **Interval** (optional, default: 1): Candle interval in minutes (1, 5, 15, etc.)

### Quick Reference Commands

**Option 1: Direct command with environment variables (Recommended)**
```bash
SCRIPT_MODE=1 DISABLE_TRADING_SERVICES=1 BACKTEST_MODE=1 rails runner scripts/optimize_indicator_parameters.rb NIFTY 60 1
SCRIPT_MODE=1 DISABLE_TRADING_SERVICES=1 BACKTEST_MODE=1 rails runner scripts/optimize_indicator_parameters.rb BANKNIFTY 60 1
SCRIPT_MODE=1 DISABLE_TRADING_SERVICES=1 BACKTEST_MODE=1 rails runner scripts/optimize_indicator_parameters.rb SENSEX 60 1
```

**Option 2: Using wrapper script**
```bash
./scripts/run_optimization.sh NIFTY 60 1
./scripts/run_optimization.sh BANKNIFTY 60 1
./scripts/run_optimization.sh SENSEX 60 1
```

**Option 3: Direct command (script sets env vars internally)**
```bash
rails runner scripts/optimize_indicator_parameters.rb NIFTY 60 1
rails runner scripts/optimize_indicator_parameters.rb BANKNIFTY 60 1
rails runner scripts/optimize_indicator_parameters.rb SENSEX 60 1
```

### Example

```bash
# Find best parameters for NIFTY using last 60 days of 1m data
SCRIPT_MODE=1 DISABLE_TRADING_SERVICES=1 BACKTEST_MODE=1 rails runner scripts/optimize_indicator_parameters.rb NIFTY 60 1
```

## Parameters Being Optimized

### Supertrend
- **Period**: 5, 7, 10, 14
- **Base Multiplier**: 2.0, 2.5, 3.0, 3.5, 4.0

### ADX
- **Period**: 10, 14, 18
- **1m Threshold**: 12, 14, 16, 18, 20
- **5m Threshold**: 10, 12, 14, 16, 18, 20

### RSI (Future Enhancement)
- **Period**: 10, 14, 21
- **Overbought**: 65, 70, 75
- **Oversold**: 25, 30, 35

### MACD (Future Enhancement)
- **Fast Period**: 8, 12, 16
- **Slow Period**: 21, 26, 31
- **Signal Period**: 7, 9, 11

## Output

The script provides:

1. **Real-time Progress**: Shows testing progress as combinations are evaluated
2. **Top 10 Results**: Displays the best 10 parameter combinations
3. **Recommended Parameters**: Shows the optimal parameters for the index
4. **CSV Export**: Saves all results to `tmp/optimization_{INDEX}_{TIMESTAMP}.csv`

## Performance Metrics

The script evaluates each parameter combination using:

- **Total PnL %**: Total profit/loss percentage
- **Win Rate %**: Percentage of winning trades
- **Profit Factor**: Ratio of gross profit to gross loss
- **Expectancy**: Average expected return per trade
- **Sharpe Ratio**: Risk-adjusted return measure
- **Composite Score**: Weighted combination of all metrics

## Composite Score Calculation

The composite score balances multiple factors:

```
Composite Score =
  (Total PnL % × 0.4) +
  (Win Rate × 0.3) +
  (Profit Factor × 10 × 0.2) +
  (Sharpe Ratio × 5 × 0.1)
```

## Interpreting Results

### Best Parameters
- Look for high composite scores
- Prefer combinations with:
  - Positive total PnL
  - Win rate > 50%
  - Profit factor > 1.5
  - Positive expectancy

### Trade-offs
- Higher win rate often means lower average win size
- More trades may mean more noise
- Consider Sharpe ratio for risk-adjusted performance

## Limitations

1. **Sample Size**: Uses limited historical data (30-90 days typically)
2. **Simple Exit Logic**: Uses fixed stop loss (7%) and take profit (15%)
3. **No Slippage**: Assumes perfect execution
4. **No Transaction Costs**: Doesn't account for brokerage/fees
5. **Overfitting Risk**: Best parameters may not work in future

## Recommendations

1. **Run for Multiple Periods**: Test with different time ranges
2. **Walk-Forward Analysis**: Validate on out-of-sample data
3. **Paper Trading**: Test optimized parameters in paper trading first
4. **Monitor Performance**: Track how parameters perform in live trading
5. **Regular Re-optimization**: Re-run optimization periodically as market conditions change

## Future Enhancements

- [ ] Add RSI and MACD filters
- [ ] Support for multiple timeframes
- [ ] Walk-forward optimization
- [ ] Genetic algorithm optimization
- [ ] Monte Carlo simulation
- [ ] Risk-adjusted metrics (Sortino, Calmar)
- [ ] Maximum drawdown analysis

## Troubleshooting

### No Results
- Check if historical data is available for the index
- Verify the index key is correct (NIFTY, BANKNIFTY, SENSEX)
- Ensure enough candles are available (need at least 50+)

### Slow Performance
- Reduce the number of parameter combinations
- Use shorter time periods (fewer days)
- Use higher intervals (5m instead of 1m)

### Memory Issues
- Process one index at a time
- Reduce days_back parameter
- Close other applications

