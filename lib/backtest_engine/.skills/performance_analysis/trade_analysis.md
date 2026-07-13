# Individual Trade Analysis Guide

Audit individual trades to evaluate execution efficiency and trend capture.

## Trade Metrics

1. **MFE / MAE Excursions**:
   - **Maximum Favorable Excursion (MFE)**: Maximum unrealized profit during the trade.
   - **Maximum Adverse Excursion (MAE)**: Maximum unrealized loss during the trade.
   - Helps identify if stops are too tight or targets are too loose.

2. **Exit Efficiency**:
   - `Exit Efficiency = (ExitPrice - EntryPrice) / (MFE - EntryPrice) * 100`.
   - High exit efficiency indicates profit was locked near peak price.

3. **Trend Capture %**:
   - Measures what percentage of the underlying index swing was captured by the option trade.
