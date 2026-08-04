# Active Position Risk Audits

Monitor account-level risk constraints during the paper trading session.

## Risk Checks

1. **Daily Drawdown Limit**:
   - Calculate `Daily Drawdown = (StartingCash - CurrentCash - OpenPnL) / StartingCash * 100`.
   - If drawdown exceeds target (e.g. 2%), immediately trigger EOD exit to flatten all open trades and block new entry signals.

2. **Position Size Validation**:
   - Ensure the entry size (number of lots) does not violate the maximum risk budget (e.g. 1% of capital per trade).
