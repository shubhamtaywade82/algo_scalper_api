# Option Chain Analysis Outputs Specification

This document defines the structured output formats that other skills consume from the Option Chain Analysis module.

## Stateful JSON Deliverable

The primary programming output is **`best_contracts.json`** which is parsed by down-stream strategy nodes.

### Schema
```json
{
  "timestamp": "2026-07-09T09:30:00+05:30",
  "underlying": "NIFTY",
  "expiry": "2026-07-16",
  "atm_strike": 24200,
  "best_ce": {
    "strike": 24200,
    "option_symbol": "NIFTY26JUL24200CE",
    "score": 94.2,
    "liquidity": 96.0,
    "iv": 14.5,
    "delta": 0.51,
    "ask": 125.40,
    "bid": 124.90
  },
  "best_pe": {
    "strike": 24200,
    "option_symbol": "NIFTY26JUL24200PE",
    "score": 91.8,
    "liquidity": 92.5,
    "iv": 15.1,
    "delta": -0.49,
    "ask": 118.20,
    "bid": 117.70
  },
  "market_bias": "BULLISH",
  "regime": "STRONG_TREND_BULLISH",
  "call_wall": 24300,
  "put_wall": 24100,
  "max_pain": 24200,
  "risks": [
    "High theta decay on OTM strikes",
    "Spread widening on strikes outside ATM+/-2"
  ]
}
```
