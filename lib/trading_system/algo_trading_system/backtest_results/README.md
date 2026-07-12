# 📊 Options Backtest Report - Sample Results

This directory contains the results of your backtests.

## File Formats
- `backtest_summary_*.json`: High-level metrics across all strikes (Win Rate, Total P&L, Sharpe Ratio, etc.).
- `trades_*.json`: Detailed JSON list of every entry and exit.
- `trades_*.csv`: Flat file for analysis in Excel or Google Sheets.
- `dashboard_*.html`: Interactive visual summary of the backtest run.

## Example Usage
```bash
# Run a multi-strike backtest using the orchestrator
ruby bin/backtest
```
