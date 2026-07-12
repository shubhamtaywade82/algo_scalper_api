# Trailing Optimizer Outputs Specification

The Trailing Optimizer skill generates the following reports and updates the stateful database files.

## Generated Reports
* **`trailing_report.md`**: Evaluation of trailing stop performance.
* **`activation_report.md`**: Rank of optimal activation thresholds.
* **`parameter_report.md`**: Parameter grid sweep results.
* **`regime_report.md`**: Best trailing stop configurations per regime.
* **`comparison_report.md`**: Comparative analysis of trailing stop types.
* **`statistics.csv`**: Record of calculated exit metrics.
* **`recommendations.md`**: Summary of recommendations.

## Stateful JSON Deliverable
The optimizer outputs **`optimizer_results.json`** to update active trade profiles.

### Schema
```json
{
  "winner": "Adaptive ATR + Structure",
  "activation": "1.5R",
  "distance": "2 ATR",
  "tightening": "Dynamic",
  "expectancy": 0.83,
  "profit_factor": 2.41,
  "trend_capture": 87.2,
  "profit_locked": 71.4,
  "average_giveback": 16.3,
  "best_regimes": ["STRONG_TREND_BULLISH", "BREAKOUT"]
}
```
