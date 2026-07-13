# Performance Analysis Outputs Specification

The Performance Analysis skill generates these report files and updates the performance dashboards.

## Generated Reports
* **`performance_report.md`**: Overall performance summary.
* **`returns_report.md`**: CAGR and rolling returns analysis.
* **`risk_report.md`**: Downside risk and tail risk (VaR/CVaR) analysis.
* **`drawdown_report.md`**: Max DD and recovery duration logs.
* **`trade_report.md`**: Win rates, MFE/MAE excursions, and exit efficiencies.
* **`execution_report.md`**: Fill slippages and latency impact.
* **`option_report.md`**: Theta decay and IV impact logs.
* **`regime_report.md`**: Regime win rates and expectancy.
* **`benchmark_report.md`**: Comparisons against random signals.
* **`recommendations.md`**: High ROI optimization checklist.

## Stateful JSON Deliverable
The analyst outputs **`performance_dashboard.json`** for strategy comparisons.

### Schema
```json
{
  "overall_score": 91.8,
  "performance_grade": "A",
  "expectancy": 0.84,
  "profit_factor": 2.31,
  "sharpe": 2.12,
  "sortino": 3.07,
  "calmar": 1.98,
  "max_drawdown_pct": 6.8,
  "win_rate_pct": 46.3,
  "average_r_multiple": 2.74,
  "trend_capture_pct": 81.5,
  "exit_efficiency_pct": 78.9,
  "execution_efficiency_pct": 94.6
}
```
