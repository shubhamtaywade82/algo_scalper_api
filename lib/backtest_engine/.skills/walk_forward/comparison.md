# Walk Forward vs Backtest Comparisons

Compare performance metrics between standard backtests and Walk-Forward runs.

## Comparison Framework
* **Return Retention**: Compare net returns. Standard backtests often report inflated returns due to global parameter optimizations.
* **Drawdown Excursions**: Compare the depth and length of drawdowns. Walk-forward drawdowns are typically wider, representing a more realistic performance expectation.
* **Expectancy Retention**: Audit the decay in average trade return under rolling out-of-sample execution.
