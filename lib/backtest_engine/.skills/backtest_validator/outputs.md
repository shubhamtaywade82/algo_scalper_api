# Backtest Validator Outputs Specification

This document defines the structured output formats for the validation reports.

## File Mappings
* **`validator_score.json`**: Primary JSON results file used by deployment triggers.
* **`trade_validation.csv`**: Record of audited entries/exits vs. spot index candles.
* **`audit_log.json`**: Detailed trace logs of lookahead checks and data scanning events.
