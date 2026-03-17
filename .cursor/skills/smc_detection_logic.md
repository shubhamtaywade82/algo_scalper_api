# Algorithmic Detection of SMC Structures

Logic for deterministic detection of institutional structural elements.

## Swing Detection
- **Pivot Length**: 3-5 candles.
- **Swing High**: $High[i] > Max(High[i-1], High[i-2], High[i+1], High[i+2])$.
- **Swing Low**: $Low[i] < Min(Low[i-1], Low[i-2], Low[i+1], Low[i+2])$.

## BOS/CHoCH Detection
- **Bullish**: $Close[i] > last\_swing\_high$.
- **Bearish**: $Close[i] < last\_swing\_low$.
- **State Management**: Track `last_valid_structure` to distinguish between BOS (continuation) and CHoCH (reversal).

## FVG (Fair Value Gap)
- **Bullish**: $Candle1.High < Candle3.Low$.
- **Bearish**: $Candle1.Low > Candle3.High$.
- **Validation**: Middle candle must be a displacement candle ($Body/ATR > 0.8$).

## Liquidity Zones
- **Equal Highs**: $abs(High1 - High2) \leq 3 \times TickSize$.
- **Lookback**: 30 candles for intraday sweeps.

## Displacement Verification
- **ATR Ratio**: $Body / ATR(20) > 0.8$.
- **Volume Ratio**: $Volume / MA(Volume, 20) > 1.5$.
