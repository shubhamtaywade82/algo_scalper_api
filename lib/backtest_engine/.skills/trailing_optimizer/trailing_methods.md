# Evaluated Trailing stop Methodologies

This researcher evaluates the following trailing stops:

## 1. Fixed Premium Stops
* **Fixed %**: Trails by 5%, 10%, 15%, 20%, or 25% behind the highest option premium.
* **Fixed Points**: Trails by a set number of premium points (e.g. 15 points).

## 2. Option Premium Features
* **Premium ATR**: Trails at `multiplier * ATR(14)` below highest premium.
* **Premium EMA**: Exit if option closes below its EMA (e.g. EMA 20).

## 3. Underlying Index Features
* **Swing Lows**: Exit CALL if underlying index closes below the last swing-low.
* **EMA / VWAP**: Exit if underlying index closes below EMA 20 or VWAP.
* **Supertrend**: Exit CALL if underlying index flips to bearish Supertrend.
* **Donchian Channel**: Exit CALL if index closes below the lower Donchian boundary.

## 4. Volatility Adaptive Stops
* **Adaptive ATR**: Shrinks trailing distance as IV rank increases or DTE declines.
* **Chandelier Exit**: Trails `Lookback * ATR` below highest high of the lookback.
