# Strike Quality Scoring Model

To find the optimal options contract to trade, every strike is scored using a multi-factor ranking model.

## Formula

The **Overall Strike Score** (range `0` to `100`) is calculated as:

$$\text{Strike Score} = 0.25 \times L + 0.20 \times OI + 0.20 \times V + 0.15 \times IV + 0.10 \times S + 0.10 \times G$$

Where:
* **$L$ (Liquidity)**: Based on bid-ask size depth (scaled 0-100).
* **$OI$ (Open Interest)**: Open interest percentile ranking compared to other strikes in the chain (scaled 0-100).
* **$V$ (Volume)**: Traded volume percentile (scaled 0-100).
* **$IV$ (Volatility)**: How close the strike's IV is to the optimal range (avoiding over-inflated IV; scaled 0-100).
* **$S$ (Spread)**: Bid-ask spread percentage. `Score = [0, 100 - (Spread % * 50)].max`.
* **$G$ (Greeks)**: Optimal delta ranges. E.g., for long option buying, delta between `0.40` and `0.55` receives a score of `100`, decaying outside that window.

---

## Classifications

* **`90 - 100` (Excellent)**: Prime selection for naked option buying. Optimal delta, tight spreads, and heavy volume.
* **`80 - 89` (Very Good)**: Highly liquid, acceptable pricing.
* **`70 - 79` (Good)**: Tradable, but monitor execution slippage.
* **`60 - 69` (Acceptable)**: Higher slippage risk, reduce position size.
* **`Below 60` (Reject)**: DO NOT TRADE. Widening spreads, thin order books, or high decay.
