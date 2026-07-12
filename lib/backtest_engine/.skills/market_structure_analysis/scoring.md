# Market Structure Scoring Models

This skill calculates structural scores to determine trend cleanliness and pullback health.

## 1. Trend Quality Score
The **Trend Quality Score** ($0\text{--}100$) evaluates how clean the trend is:

$$\text{Trend Score} = 0.40 \times \text{Alignment} + 0.30 \times \text{Persistence} + 0.30 \times \text{Cleanness}$$

Where:
* **Alignment (40%)**: Percent of timeframes (1H, 15m, 5m, 1m) aligned in trend direction.
* **Persistence (30%)**: Length of the current trend segment compared to its historical average.
* **Cleanness (30%)**: Measure of pullbacks. A trend that moves with shallow, consistent pullbacks scores higher than a noisy trend with overlapping swings.

---

## 2. Pullback Quality Score
The **Pullback Quality Score** ($0\text{--}100$) determines if a pullback represents a low-risk entry opportunity:
* **`80 - 100` (Healthy Pullback)**: Orderly retracement (low volume, narrow spreads) into key support (VWAP/EMA) inside a strong trend.
* **`60 - 79` (Deep Pullback)**: Retracements exceeding 61.8% of the prior leg. Higher risk of reversal.
* **`Below 60` (Exhaustion)**: Retracements breaking key support levels with volume spikes, indicating high risk of trend failure.
