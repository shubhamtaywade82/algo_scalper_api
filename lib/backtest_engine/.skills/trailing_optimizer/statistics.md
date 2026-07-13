# Trailing Stop Statistics Guide

Calculate these metrics to evaluate the performance of trailing stops:

## Metrics Definitions

1. **Trend Capture %**:
   - The percentage of the total index swing captured during the option trade.

2. **Exit Efficiency**:
   - How close the exit price was to the peak observed price (MFE).
   - `Exit Efficiency = (ExitPrice - EntryPrice) / (MFE - EntryPrice) * 100`.

3. **Average Giveback**:
   - The average amount of paper profit surrendered from peak MFE to exit execution.
   - `Giveback = (MFE - ExitPrice) / EntryPrice * 100`.
