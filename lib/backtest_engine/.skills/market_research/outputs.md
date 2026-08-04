# Market Research Outputs Specification

Every time the Market Research skill completes, it generates the following output reports and updates the structured JSON state files.

## Reports List

* **`market_summary.md`**: Top-level executive overview, SWOT analysis, and matching strategy recommendations.
* **`trend_analysis.md`**: Multi-timeframe trend analysis, EMA slope alignment, and ADX strength indicators.
* **`volatility_analysis.md`**: ATR ranges, historical volatility comparison, and IV percentile profiles.
* **`liquidity_analysis.md`**: Bid-ask spread, RVOL spikes, and order book size.
* **`market_structure.md`**: CHOCH/BOS structures and liquidity sweep markings.
* **`option_chain_analysis.md`**: Open interest transitions, PCR ratio, Call Wall, Put Wall, and Max Pain points.
* **`regime_analysis.md`**: Classification of current state with statistical confidence bounds.

## Stateful JSON Deliverable

The primary programming deliverable is **`market_research.json`** which is parsed by down-stream strategy nodes.

### Schema
```json
{
  "symbol": "NIFTY",
  "timestamp": "2026-07-09T11:00:00+05:30",
  "last_traded_price": 24215.35,
  "trend": {
    "direction": "BULLISH",
    "adx": 28.5,
    "ema_slope_bullish": true
  },
  "volatility": {
    "atr_5m": 18.5,
    "iv": 15.2,
    "iv_percentile": 42.1
  },
  "structure": {
    "bias": "BULLISH",
    "last_swing_low": 24150.0,
    "last_swing_high": 24250.0
  },
  "option_chain": {
    "pcr": 1.15,
    "call_wall": 24300,
    "put_wall": 24100,
    "max_pain": 24200
  },
  "regime": {
    "classification": "STRONG_TREND_BULLISH",
    "confidence_score": 0.85
  }
}
```
