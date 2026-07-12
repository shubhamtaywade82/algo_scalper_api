# Indicator Research Outputs Specification

This skill generates the following reports and updates the structured JSON files.

## Reports List

* **`indicator_summary.md`**: Top-level rankings of indicators based on predictive metrics.
* **`trend_indicators.md`**: Performance analysis and parameter stability reports for EMAs, SMAs, Supertrend, etc.
* **`momentum_indicators.md`**: RSI and MACD lag and predictive capability evaluations.
* **`volatility_indicators.md`**: Volatility percentile performance and ATR multiplier stability sweeps.
* **`volume_indicators.md`**: VWAP and Relative Volume (RVOL) breakout validation statistics.
* **`options_indicators.md`**: OI buildup, PCR ratios, and Greeks predictive metrics.
* **`feature_importance.md`**: SHAP and Permutation importance rankings.
* **`correlation_matrix.csv`**: Tabular correlation matrix of calculated features.
* **`parameter_optimization.csv`**: Summary records of grid search runs.

## Stateful JSON Deliverables

1. **`indicator_rankings.json`**: Primary indicator profiles and recommended parameters.
2. **`research_summary.json`**: Overview stats of the indicator analysis.

### `indicator_rankings.json` Schema
```json
{
  "timestamp": "2026-07-09T09:30:00+05:30",
  "trend": [
    {
      "indicator": "EMA",
      "best_parameters": {
        "fast": 20,
        "slow": 50
      },
      "score": 91.2,
      "best_regimes": ["STRONG_TREND_BULLISH", "STRONG_TREND_BEARISH"],
      "weak_regimes": ["RANGE_BOUND"]
    }
  ],
  "momentum": [
    {
      "indicator": "RSI",
      "best_parameters": {
        "period": 14,
        "oversold": 30,
        "overbought": 70
      },
      "score": 85.5,
      "best_regimes": ["RANGE_BOUND"],
      "weak_regimes": ["STRONG_TREND_BULLISH", "STRONG_TREND_BEARISH"]
    }
  ],
  "volatility": [],
  "volume": [],
  "options": []
}
```
