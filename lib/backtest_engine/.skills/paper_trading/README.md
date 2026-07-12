# Paper Trading Skill (Virtual Broker Runtime)

This skill executes options strategies in a production-identical environment by replacing only the broker communication adapter.

## Paper Trading Intelligence

The Paper Trading runtime maintains a virtual database under `data/knowledge_base/paper_trading/`:

```text
data/knowledge_base/paper_trading/
├── virtual_portfolio.json       # Net asset balances, margins, and cash
├── order_book_simulator.json    # Log of active limit and stop orders
├── fill_quality_database.json   # Trailing fills and slippage averages
└── trade_journal/               # Completed sessions logs
```

### Specialized Option Modules
1. **Option Lifecycle Simulator**: Handles weekly/monthly expirries, theta decay curves, and IV contraction events.
2. **Execution Quality Analyzer**: Measures price slippage by contract liquidity and time of day.
3. **Paper vs Live Validator**: Compares paper trades against actual live broker results to measure simulation divergence.
4. **Live Readiness Assessment**: Computes deployment readiness score based on target criteria (min trades, stable expectancy, and DD boundaries).
