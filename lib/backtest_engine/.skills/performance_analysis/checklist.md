# Performance Analysis Checklist

Use this checklist to verify the quantitative performance audit is complete.

## 1. Data Verification
- [ ] Load completed trade log file.
- [ ] Load corresponding order details and fills.
- [ ] Load portfolio equity curve data.
- [ ] Verify dataset contains no duplicated trade records.

## 2. Metric Calculations
- [ ] Compute Net Return, CAGR, and monthly profit distributions.
- [ ] Calculate Maximum Drawdown, Average Drawdown, and Ulcer Index.
- [ ] Calculate Sharpe, Sortino, and Calmar ratios.
- [ ] Calculate Expectancy, Profit Factor, and System Quality Number (SQN).

## 3. Trade & Execution Analysis
- [ ] Calculate average MFE and MAE for all trades.
- [ ] Calculate average Exit Efficiency.
- [ ] Calculate average Trend Capture %.
- [ ] Measure average slippage and fill delays.

## 4. Attribution & Benchmarking
- [ ] Run benchmark comparisons against Buy & Hold and random entry baselines.
- [ ] Isolate performance by market regime and expiry days.
- [ ] Document forensic failure clusters and update `data/knowledge_base/performance/`.
