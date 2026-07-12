# Options Strategy Research Notes

Working notes on strategy development, observations from backtesting,
and ideas for future strategies. Not specifications — see `specs/` for those.

---

## EMA Crossover Observations

### What works
- Works best on trending days (large directional moves > 1%)
- 5-minute timeframe outperforms 1-minute (fewer false signals)
- Adding VIX filter (< 18) significantly reduces losing trades on choppy days
- Best performance: 09:30–13:00 IST window (avoid post-lunch chop)

### What doesn't work
- Fails badly on sideways/consolidation days
- Gap-up/gap-down opens create false signals in the first 30 minutes
- Avoid trading this on expiry days (Thursday for NIFTY) — erratic behavior

### Improvement ideas
- Add Supertrend as an additional filter
- Use ADX > 25 to confirm trending condition before taking signals
- Consider exiting at 1.5× ATR instead of 2× to capture more winners

---

## Opening Range Breakout Observations

### What works
- Excellent on days with strong global cues (US futures up/down significantly)
- Works well when NIFTY gaps and continues in same direction
- Volume filter is critical — reduces false breakouts significantly

### What doesn't work
- "Fake breakout" days are common — price breaks OR, then reverses
- Budget day, RBI policy day — avoid completely

### Improvement ideas
- Use a "confirmation close" — require 2 consecutive candles above OR high
- Check if SGX Nifty / Gift Nifty aligns with the breakout direction
- Add a "retest" entry: wait for price to pull back to OR level after breakout, then enter

---

## VIX Spike Reversal Observations

### What works
- Very high-probability on "panic" days followed by recovery
- Works well when the spike is news-driven and markets overreact
- The Phase 2 (reversal/call buying) has better risk-reward than Phase 1

### What doesn't work
- Genuine trend days (e.g., budget, systemic risk events) — VIX keeps climbing
- Need strict position sizing — losses can be large when wrong

### Improvement ideas
- Add a circuit-breaker: if NIFTY drops > 3% in one day, shut down trading entirely
- Look at Put-Call Ratio as a confirming signal for the reversal phase

---

## General Research Ideas (Future Strategies)

1. **Momentum Scalping**: 1-minute chart, 5-period EMA, scalp 20–30 points on NIFTY
2. **Bank Nifty Earnings Play**: trade large moves around big bank result dates
3. **Max Pain Theory**: buy the side opposite to max pain on expiry morning
4. **PCR Contrarian**: buy calls when PCR > 1.5 (too many puts, likely reversal)
5. **VWAP Bounce**: enter when price bounces off VWAP with volume confirmation

---

## Backtest Performance Summary (Early Results)

| Strategy           | Period        | Trades | Win% | Total P&L   |
|--------------------|---------------|--------|------|-------------|
| EMA Crossover      | Q1 2024       | TBD    | TBD  | TBD         |
| ORB                | Q1 2024       | TBD    | TBD  | TBD         |
| VIX Spike Reversal | Jan–Mar 2024  | TBD    | TBD  | TBD         |

*Populate after running backtests via `examples/backtest_example.rb`*
