# Paper Trading Outputs Specification

The Paper Trading skill generates these logs and updates the session statistics.

## Generated Reports
* **`paper_trading_report.md`**: Overall session summary.
* **`trade_journal.md`**: Detailed log of executed trades.
* **`orders.csv` / `fills.csv`**: Record of placed and filled orders.
* **`portfolio.csv`**: Capital and margin history logs.

## Stateful JSON Deliverables
* **`simulation_results.json`**: Performance stats summary.
* **`portfolio_snapshot.json`**: Cash and margin balances.

### `simulation_results.json` Schema
```json
{
  "simulation": {
    "mode": "LIVE_PAPER",
    "broker_profile": "DHAN",
    "starting_capital": 100000,
    "ending_capital": 134520
  },
  "performance": {
    "net_pnl": 34520,
    "return_pct": 34.52,
    "max_drawdown_pct": 6.3,
    "profit_factor": 2.18,
    "expectancy": 412.75,
    "win_rate_pct": 48.6
  },
  "execution": {
    "orders": 182,
    "filled": 177,
    "partial_fills": 9,
    "rejected": 5,
    "average_slippage": 0.18
  }
}
```
