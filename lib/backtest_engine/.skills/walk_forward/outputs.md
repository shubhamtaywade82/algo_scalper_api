# Walk Forward Outputs Specification

The Walk Forward skill generates these report files and updates the validation dashboards.

## Generated Reports
* **`walk_forward_report.md`**: Overall walk-forward validation summary.
* **`window_results.csv`**: Performance stats per roll window.
* **`parameter_history.csv`**: Record of optimal parameters per window.
* **`parameter_stability.md`**: Evaluation of parameter drift.
* **`robustness_report.md`**: Noise and cost sensitivity results.
* **`overfitting_report.md`**: Overfitting metrics and WFE logs.
* **`regime_report.md`**: Forward results segregated by market regime.
* **`comparison_report.md`**: Metrics comparison against the baseline backtest.

## Stateful JSON Deliverable
The validator outputs **`walk_forward_dashboard.json`** for automated gates.

### Schema
```json
{
  "overall_score": 89.6,
  "status": "PASS",
  "walk_forward_efficiency": 0.87,
  "forward_profit_factor": 1.94,
  "backtest_profit_factor": 2.16,
  "performance_retention_pct": 89.8,
  "parameter_stability": 91.2,
  "overfitting_risk": "Low",
  "windows_tested": 36,
  "passed_windows": 32,
  "failed_windows": 4
}
```
