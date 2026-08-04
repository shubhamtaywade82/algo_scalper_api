# Time-Based Exit Strategies

Time is the option buyer's greatest enemy due to decay.

## Time Rules

1. **Max Holding Period**:
   - Exit the position if price fails to reach the target or trigger a trailing stop within a set period (e.g. 20-30 minutes).

2. **Session / Intra-day Filter**:
   - Close positions prior to lunch hours (`11:45` - `13:15`) to avoid sideways decay chop.
   - Force flatten all intraday positions before market close (scheduled exit at `15:15`).

3. **Expiry Proximity Exit**:
   - On expiry days, exit positions at least 1-2 hours before close to avoid extreme gamma whipsaws and liquidity collapse.
