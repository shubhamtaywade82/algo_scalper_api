# Market Structure Analysis Checklist

Use this checklist to verify price action structure prior to generating entry signals.

## 1. Swing Discovery Gate
- [ ] Compute local high/low points using the lookback parameter (default: 3).
- [ ] Classify peaks into Major swings (HTF) and Minor swings (LTF).
- [ ] Map active swing highs and lows to a local database.

## 2. Breakout & Reversal Gate
- [ ] Monitor price closes against active swings.
- [ ] Verify if a Break of Structure (BOS) is confirmed on a candle close.
- [ ] Scan for a Change of Character (CHOCH) to confirm trend reversal.
- [ ] Flag failed breakouts (whipsaws) where price breaks a swing but fails to hold.

## 3. Liquidity Gate
- [ ] Locate Equal Highs (EQH) and Equal Lows (EQL).
- [ ] Monitor price sweep events (price pierces EQL/EQH and reverses).
- [ ] Track internal liquidity (inside the range) vs. external liquidity (pivots).

## 4. Phase & Quality Scoring
- [ ] Classify trend phase (Accumulation, Expansion, Distribution, Range).
- [ ] Calculate the Volatility Compression score.
- [ ] Calculate the Multi-Timeframe Alignment score.
- [ ] Update the stateful Structure Database.
