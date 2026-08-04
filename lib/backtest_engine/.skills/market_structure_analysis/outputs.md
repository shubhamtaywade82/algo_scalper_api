# Market Structure Outputs Specification

The Market Structure Analysis skill generates the following reports and updates the structured JSON state files.

## Generated Reports

1. **`trend_analysis.md`**: Evaluation of HH/HL structure.
2. **`swing_analysis.md`**: Active swing high and low databases.
3. **`bos_report.md`**: Log of confirmed Break of Structure events.
4. **`choch_report.md`**: Log of trend reversal Character Changes.
5. **`liquidity_report.md`**: Equal highs/lows and stop hunt logs.
6. **`support_resistance.md`**: Volume, price, and OI pivots.
7. **`compression_report.md`**: Volatility and volume squeeze metrics.
8. **`expansion_report.md`**: Momentum expansion follow-through metrics.

## Stateful JSON Deliverables

1. **`market_structure.json`**: Standardized struct consumed by feature modules.
2. **`trend_score.json`**: Trend persistence and alignment score metrics.

### `market_structure.json` Schema
```json
{
  "timestamp": "2026-07-09T09:30:00+05:30",
  "symbol": "NIFTY",
  "structure": {
    "trend_direction": "BULLISH",
    "trend_phase": "EXPANSION",
    "major_swing_high": 24250.0,
    "major_swing_low": 24150.0,
    "minor_swing_high": 24220.0,
    "minor_swing_low": 24190.0
  },
  "structural_events": {
    "last_bos_type": "BULLISH",
    "last_bos_time": "2026-07-09T09:25:00+05:30",
    "last_choch_type": "BULLISH",
    "last_choch_time": "2026-07-09T09:20:00+05:30",
    "last_sweep_type": "BULLISH_LIQUIDITY_SWEEP",
    "last_sweep_price": 24185.0
  },
  "zones": {
    "compression_state": false,
    "unswept_eql": 24100.0,
    "unswept_eqh": 24320.0
  },
  "alignment": {
    "alignment_score": 85.0,
    "tf_trends": {
      "1h": "BULLISH",
      "15m": "BULLISH",
      "5m": "BULLISH",
      "1m": "NEUTRAL"
    }
  }
}
```
