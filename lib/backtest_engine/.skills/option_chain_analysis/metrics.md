# Option Chain Analysis Metrics

The research agent computes the following metrics across the options chain:

## 1. Liquidity Metrics
* **Bid-Ask Spread %**: `(AskPrice - BidPrice) / BidPrice * 100`.
* **Top 5 Bid-Ask Size**: Total quantity available at the best 5 depth levels.
* **Volume Velocity**: Rate of volume accumulation (volume change per minute).
* **Relative Volume (RVOL)**: Ratio of current volume to the 10-period SMA volume.

## 2. Open Interest Metrics
* **OI Change (OI Velocity)**: Net change in OI over the last 15 minutes.
* **OI Acceleration**: Rate of change of OI Velocity.
* **OI Migration**: The shift of the peak OI strike over time.
* **OI Concentration**: Percentage of total chain OI concentrated in the top 3 strikes.

## 3. Volatility Metrics
* **Implied Volatility (IV)**: Derived from Black-Scholes using spot price and interest rate.
* **IV Skew**: Difference between put IV and call IV at equivalent deltas.
* **IV Smile**: IV curvature across strike prices.
* **Term Structure**: Ratio of near-week IV to next-week and monthly IV.

## 4. Greeks Metrics
* **Delta ($\Delta$)**: Option price sensitivity to underlying change.
* **Gamma ($\Gamma$)**: Delta sensitivity.
* **Theta ($\Theta$)**: Daily time decay.
* **Vega ($\mathcal{V}$)**: Volatility sensitivity.
* **Gamma Exposure (GEX)**: `OI * Gamma * 100 * Spot` (measures dealer hedging exposure).
