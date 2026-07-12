# Virtual Portfolio Management

The paper trading runtime maintains a virtual portfolio state to track funds and equity curves.

## Tracked Parameters
* **Initial Capital**: Starting cash (default: 100,000 Rupees).
* **Current Cash**: Available funds for new trades.
* **Blocked Margin**: Margin utilized by active open positions.
* **Daily / Cumulative P&L**: Net earnings of the portfolio.
* **Equity Curve**: Recorded at the close of every 1-minute candle.
* **Maximum Drawdown**: Re-evaluated on every MTM price update.
* **Portfolio Heat**: Total risk exposure of active trades.
