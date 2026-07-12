# Trade Management Outputs Specification

The Trade Management skill generates these reports and caches structured JSON logs.

## Generated Reports
* **`trade_management_report.md`**: Overview of active tracking.
* **`stoploss_report.md`**: Log of stop modifications.
* **`trailing_report.md`**: Evaluates trailing stop performance.
* **`exit_report.md`**: Analysis of exit reasons and efficiency.

## Stateful JSON Deliverables
* **`management_score.json`**: Current trade state scorecard.
* **`trade_timeline.json`**: Historical price and action log.

### `management_score.json` Schema
```json
{
  "trade_id": "T-883719",
  "state": "TREND_FOLLOWING",
  "r_multiple": 2.4,
  "profit_locked_pct": 68.0,
  "trend_capture_pct": 82.0,
  "risk_remaining_pct": 0.0,
  "recommended_action": "TRAIL_STOP",
  "confidence": 0.91
}
```
