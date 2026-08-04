# Paper Trading Execution Engine

The execution engine replicates standard live execution pathways.

## Order Types Replicated
* **Market Orders**: Executed immediately at the opposite touch price (Ask for BUY, Bid for SELL) plus execution delay.
* **Limit Orders**: Filled only if the price trades *past* the limit level (or if size is available at touch).
* **Stop-Loss Orders**: Triggered once the LTP crosses the stop price. Executed as limit (SL) or market (SL-M) orders.
* **Synthetic Trailing**: Tracks the trailing trigger locally and updates the broker stop-loss order via API modification calls.
