# Execution Quality Audits

Analyze execution costs and fill slippage to identify execution bottlenecks.

## Execution Metrics
* **Average Slippage %**: `(ActualFillPrice - RequestedPrice) / RequestedPrice * 100`.
* **Slippage by Time of Day**: Audit if slippage increases during opening range settlement (`09:15` - `09:30`) or near market close.
* **Order Rejection Rate**: Percentage of orders rejected by the broker.
* **Fill Ratio**: Executed quantity vs. requested quantity.
