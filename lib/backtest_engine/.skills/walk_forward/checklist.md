# Walk Forward Analysis Checklist

Use this checklist to verify rolling validation runs are correctly executed.

## 1. Dataset Partitioning
- [ ] Load clean historical indexes and option candle series.
- [ ] Configure training, validation, and testing window lengths (e.g. 12m train, 3m test).
- [ ] Ensure partitions do not overlap (no data leakage).

## 2. Walk Forward Run
- [ ] Optimize parameters in the training window (in-sample).
- [ ] Store optimal parameter sets for each training window.
- [ ] Apply the parameters to the test window (out-of-sample).
- [ ] Roll the windows forward and repeat across all history segments.

## 3. Metrics & Drift Checks
- [ ] Calculate the out-of-sample Profit Factor, Expectancy, and Sharpe.
- [ ] Compute the Walk-Forward Efficiency (WFE) score.
- [ ] Map parameter values across all windows to check parameter stability.
- [ ] Confirm no lookahead bias or data leakage occurred during rolls.
