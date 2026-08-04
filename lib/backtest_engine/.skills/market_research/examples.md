# Market Research Examples

Here are concrete examples showing how the Market Research analyst evaluates data, writes outputs, and manages state.

## Example 1: Resolving a Volatility Expansion Regime

### Input Payload
```json
{
  "symbol": "NIFTY",
  "from": "2026-07-09T09:15:00+05:30",
  "to": "2026-07-09T11:00:00+05:30",
  "historical_days": 30
}
```

### Analysis Steps
1. **LTP check**: Fetch current NIFTY spot index close via `/marketfeed/ohlc` (LTP: 24,215).
2. **IV check**: Fetch ATM options chain via `/optionchain` (IV: 18.2%, 30-day IV Percentile: 88%).
3. **ATR expansion**: Spot 5m ATR is `28.5` points vs. 30-day baseline of `14.2` points.
4. **Conclusion**: Classified as `STRONG_TREND` (Bullish breakout with Volatility Expansion).

### MKB Output Update (`volatility_profiles.json`)
```json
{
  "symbol": "NIFTY",
  "timestamp": "2026-07-09T11:00:00+05:30",
  "current_iv": 18.2,
  "iv_rank": 82.4,
  "iv_percentile": 88.0,
  "realized_volatility_5m": 22.4,
  "volatility_regime": "EXPANDING"
}
```

---

## Example 2: Detecting a Liquidity Sweep

### Input Payload
```json
{
  "symbol": "BANKNIFTY",
  "timestamp": "2026-07-09T10:15:00+05:30"
}
```

### Analysis Steps
1. **Swing Highs/Lows**: Find previous swing low at `52,100`.
2. **Break check**: Price drops to `52,080` (breaking the swing low) but closes the 5-minute candle at `52,120` with volume expansion (`2.8x` baseline).
3. **Conclusion**: Classified as a **Liquidity Sweep** (Bullish reversal structure).
