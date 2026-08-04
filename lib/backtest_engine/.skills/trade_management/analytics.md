# Trade Decisions Logging Guide

Document every trailing stop modification and exit decision for audit and AI training.

## Logged Parameters
* **Timestamp**: Epoch or ISO time of the change.
* **Prior Stop / New Stop**: Absolute price boundaries.
* **Trigger Reason**: E.g., `TRAIL_UPDATE_MFE`, `BREAKEVEN_TRIGGER`, or `TIME_LIMIT`.
* **Market Context**: Underlying spot price, ATR value, and active regime.
* **Excursion Metrics**: Current MFE and MAE.
