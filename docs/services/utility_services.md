# Indicator & Utility Services

Documentation for technical indicators and shared utility services.

## Indicators Namespace

### Indicators::Supertrend
**File:** `app/services/indicators/supertrend.rb`
Calculates the Supertrend line (Trend + Support/Resistance) using ATR and Median price.

### Indicators::ADX
**File:** `app/services/indicators/adx_indicator.rb`
Measures trend strength (Average Directional Index).

### Indicators::RSI
**File:** `app/services/indicators/rsi_indicator.rb`
Relative Strength Index for overbought/oversold conditions.

---

## Technical Utils

### SMC::Scanner
**File:** `app/services/smc/scanner.rb`
Detects Market Structure (BOS/CHoCH) and Order Blocks. Used for higher-timeframe bias.

### Market::Calendar
**File:** `app/services/market/calendar.rb`
Determines if today is a trading holiday or if the market is currently open.

### Trading::CapitalAllocator
**File:** `app/services/trading/capital_allocator.rb`
Calculates lot sizing based on available margin and configured max risk per trade.
