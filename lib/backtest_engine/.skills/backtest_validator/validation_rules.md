# Backtest Validation Rules

Every backtest run must satisfy these ten validation rules:

## Rule 1: Data Integrity
All candle intervals must be uniform, timezone aligned, and contain no duplicated timestamps.

## Rule 2: Lookahead Prevention
The strategy code must never reference future indicators, future volumes, or future price values.

## Rule 3: Expiry Correctness
The contract chosen must exist on the historical date and match weekly/monthly expiry cycles.

## Rule 4: Tick & Lot Size Constraints
Simulated order prices must align with option tick sizes (0.05) and lot quantities (e.g. NIFTY: 75, BANKNIFTY: 15).

## Rule 5: Bid-Ask Slippage Model
Buy orders must execute at the simulated ask price; sell orders must execute at the bid price, including a transaction lag penalty.

## Rule 6: Monotonic Stops
Stop-loss levels must move strictly in favor of the trade (rising for long calls). Stops must never be widened during a trade.

## Rule 7: Intrabar Execution Realism
For stop triggers inside a candle, the price path sequence must assume the worst-case scenario (e.g. low hit before high) unless tick data confirms sequence.

## Rule 8: Cost Model Enforcement
Deduct Indian taxes: STT, GST, SEBI fees, exchange fees, and flat brokerage.

## Rule 9: Statistical Significance
The strategy's historical profit must exceed a random entry benchmark with a $p\text{-value} < 0.05$.

## Rule 10: Walk-Forward Efficiency (WFE)
Out-of-sample expectancy must be at least 60% of in-sample expectancy ($\text{WFE} \ge 0.6$).
