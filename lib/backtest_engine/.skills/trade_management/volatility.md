# Volatility-Based Exits

Monitor changes in volatility and option pricing characteristics to verify trade viability.

## Volatility Checks

1. **IV Crush Exit**:
   - Implied Volatility (IV) spikes before news/events and crushes immediately after.
   - If IV drops by a set percentage (e.g. $> 10\%$ IV crush) while in a trade, exit immediately to limit pricing compression.

2. **ATR Volatility Squeeze**:
   - If ATR compresses to historical lows, the option is likely to decay in value due to lack of movement.
   - Exit if volatility collapses below the 20-period moving average.
