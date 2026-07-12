# Drawdowns & Downside Risk Guide

Analyze portfolio drawdowns to evaluate drawdown depth and duration.

## Drawdown Metrics

1. **Maximum Drawdown (Max DD)**:
   - The largest peak-to-trough drop in capital.
   - Primary metric for system risk evaluation.

2. **Time Under Water**:
   - The total number of days/candles spent below the previous equity high.
   - Measures psychological stress and recovery speed.

3. **Ulcer Index (UI)**:
   - Measures both depth and duration of drawdowns.
   - `UI = Sqrt(Sum(Drawdown_i^2) / N)`.

4. **Recovery Factor**:
   - Ratio of net profit to maximum drawdown. `Recovery Factor = NetProfit / MaxDrawdown`.
