# Market Research Quality Checklist

Before completing a research run, verify that every checkbox below is satisfied. If any validation fails, stop and document the cause.

## Data Quality Gate
- [ ] Retrieve Symbol Metadata and check standard lot/tick sizes.
- [ ] Scan index candles for gaps (empty minutes/ticks).
- [ ] Check for price anomalies (e.g. price spike > 5% in a single minute).
- [ ] Confirm alignment of timestamps between index candles and option contracts.
- [ ] Verify expiry dates against the holiday calendar.

## Analysis Steps
- [ ] **Trend**: Identify slope and strength (ADX threshold checks).
- [ ] **Volatility**: Compute IV Percentile, IV Rank, and ATR band ratios.
- [ ] **Liquidity**: Measure bid-ask spread percentages and order book size depth.
- [ ] **Structure**: Map Swing Highs/Lows and trace BOS / CHOCH zones.
- [ ] **Option Chain**: Identify the Call Wall, Put Wall, and current Max Pain level.

## Deliverables & Stateful Cache
- [ ] Update state in `data/knowledge_base/` JSON files.
- [ ] Generate markdown reports in the session research output directory.
- [ ] Flag strategy recommendations based on the detected regime.
