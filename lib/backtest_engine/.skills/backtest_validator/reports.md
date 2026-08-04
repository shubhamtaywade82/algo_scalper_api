# Backtest Validator Reports Specification

This skill generates structured audit logs to document the validation verdict.

## Reports List

* **`validation_report.md`**: Top-level audit report listing overall score, pass/fail status, and warnings.
* **`execution_report.md`**: Details on slippage penalties, bid-ask spreads, and partial fill simulation results.
* **`bias_report.md`**: Lookahead checks, calendar bias scans, and curve-fitting alerts.
* **`warning_report.md`**: Non-critical warnings (e.g. "Assumed fixed slippage", "OI data missing for deep OTM").
* **`robustness.md`**: Detailed metrics from Walk-Forward Analysis and Monte Carlo runs.

## Stateful JSON Deliverables

The validator outputs **`validator_score.json`** for automated CI/CD checks.

### Schema
```json
{
  "overall_score": 93.2,
  "status": "PASS",
  "confidence": 0.96,
  "warnings": [
    "Historical IV unavailable before 2022",
    "Assumed fixed slippage"
  ],
  "critical_failures": [],
  "scores": {
    "data": 98,
    "execution": 91,
    "statistics": 95,
    "risk": 90,
    "robustness": 89,
    "option_selection": 96
  }
}
```
