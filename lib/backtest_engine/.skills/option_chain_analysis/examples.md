# Option Chain Analysis Examples

Here are concrete examples showing how the option chain researcher scores strikes and identifies opportunities.

## Example 1: Selecting a CE Strike during a Bullish Breakout

### Input State
* Underlying Spot: `24,215`
* Call Option Chain:
  * **24,200 CE (ATM-1)**: Delta: `0.54`, Bid: `132.10`, Ask: `132.60`, OI: `1,200,000`, Vol: `450,000`, IV: `14.8`
  * **24,250 CE (ATM)**: Delta: `0.48`, Bid: `101.40`, Ask: `101.90`, OI: `850,000`, Vol: `380,000`, IV: `14.9`
  * **24,300 CE (ATM+1)**: Delta: `0.41`, Bid: `75.20`, Ask: `76.50`, OI: `1,500,000`, Vol: `600,000`, IV: `15.2` (Call Wall)

### Scoring Calculations
1. **24,200 CE**:
   - Spread %: `0.37%` (Score: 81.5)
   - Delta Score: `100` (within optimal 0.40 - 0.55 range)
   - Liquidity: `95.0`
   - *Overall Score*: **93.8**

2. **24,250 CE**:
   - Spread %: `0.49%` (Score: 75.5)
   - Delta Score: `100`
   - Liquidity: `92.0`
   - *Overall Score*: **90.4**

3. **24,300 CE**:
   - Spread %: `1.70%` (Score: 15.0) — Widen spread penalty
   - Delta Score: `100`
   - Liquidity: `75.0`
   - *Overall Score*: **73.1**

### Recommendation
Select **24,200 CE** as the primary contract. The 24,300 CE is rejected for entry due to high spread slippage, despite being the Call Wall.
