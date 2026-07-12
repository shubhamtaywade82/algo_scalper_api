# Performance Analysis Skill

This skill functions as a specialized quantitative performance analyst. It evaluates backtest and live trading results to attribute performance and detect bottlenecks.

## Performance Intelligence Layer

The Performance Analysis skill maintains a historical repository under `data/knowledge_base/performance/`:

```text
data/knowledge_base/performance/
├── strategy_history.json        # Performance records across strategy versions
├── drawdown_profiles.json       # Depth and duration matrices of drawdowns
├── exit_efficiencies.json       # Log of MFE/MAE and exit efficiency metrics
└── forensics_report/            # Detailed root cause failure clusters
```

### Forensic Analysis
Rather than simply reporting profit factor, the **Performance Forensics** module analyzes:
* **Failure Cluster Detection**: Isolating market conditions where consecutive losses occur.
* **Drawdown Root Cause**: Identifying whether drawdown was caused by trend failure, high slippage, or decay.
* **Opportunity Cost**: Estimating profit missed due to late entries or premature exits.
