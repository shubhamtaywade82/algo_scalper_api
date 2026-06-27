# Milestone 4.5: Liquidity Engine

**Phase:** 4 — Market Intelligence Engines  
**Goal:** Reject illiquid markets and estimate slippage.  
**Estimated Tasks:** 11

---

## Tasks

### 1. Implement LiquidityEngine
- [x] Create `app/engines/liquidity_engine.rb`
- [x] Interface: `assess(input) -> LiquidityOutput`
- [x] Input: `LiquidityInput` with market depth, option chain, spreads
- [x] Output: `LiquidityOutput` with:
  - `liquidity_score` (0-100)
  - `tradable?` (boolean, threshold configurable)
  - `estimated_slippage` (ticks and rupees)
  - `rejection_reasons` (array)
  - `warnings` (array)

### 2. Add SpreadAnalyzer
- [x] Create `app/engines/analyzers/spread_analyzer.rb`
- [x] Underlying spread: NIFTY/BANKNIFTY futures spread
- [x] Option spread: per strike, bid-ask %
- [x] Thresholds (configurable):
  - Underlying spread > 0.15% = reject
  - Option spread > 0.30% = reject
  - Option spread > 0.50% = warn
- [x] Spread percentile: current vs 20-day average
- [x] Output: `underlying_spread`, `option_spreads`, `percentiles`, `rejections`

### 3. Implement BidAskImbalanceCalculator
- [x] Create `app/engines/calculators/bid_ask_imbalance_calculator.rb`
- [x] Order book imbalance: `(bid_volume - ask_volume) / (bid_volume + ask_volume)`
- [x] Levels: top 1, top 3, top 5
- [x] Imbalance > 0.3 = strong directional pressure
- [x] Track imbalance trend (rising/falling)
- [x] Output: `imbalance_1`, `imbalance_3`, `imbalance_5`, `trend`, `pressure_direction`

### 4. Create OrderBookPressureAnalyzer
- [x] Create `app/engines/analyzers/order_book_pressure_analyzer.rb`
- [x] Liquidity walls: large orders at specific prices
- [x] Wall detection: size > 5x average level size
- [x] Pressure: cumulative bid vs ask volume (top 10 levels)
- [x] Absorption: large market orders hitting wall with minimal price move
- [x] Output: `walls`, `pressure_ratio`, `absorption_events`, `support_resistance_levels`

### 5. Add AbsorptionDetector
- [x] Create `app/engines/detectors/absorption_detector.rb`
- [x] Detect: aggressive orders (market) hitting passive liquidity
- [x] Signature: large volume trade, minimal price change, liquidity replenishes
- [x] Bullish absorption: selling absorbed at support
- [x] Bearish absorption: buying absorbed at resistance
- [x] Output: `absorption_events` with `type`, `price`, `volume`, `strength`

### 6. Implement SlippageEstimator
- [x] Create `app/engines/calculators/slippage_estimator.rb`
- [x] Market order slippage: walk the book for order size
- [x] Limit order slippage: probability of fill at limit
- [x] Model: `slippage = spread/2 + market_impact(size)`
- [x] Market impact: `size / avg_daily_volume * ATR * factor`
- [x] Output: `expected_slippage_ticks`, `expected_slippage_rupees`, `fill_probability`

### 7. Create LiquidityScoreCalculator
- [x] Create `app/engines/calculators/liquidity_score_calculator.rb`
- [x] Components (weighted):
  - Underlying spread: 20%
  - Option spread (ATM): 20%
  - Order book depth (top 5): 20%
  - Bid/ask imbalance stability: 15%
  - Volume/turnover: 15%
  - Absorption/pressure quality: 10%
- [x] Normalize each 0-100, weighted sum
- [x] Threshold: < 60 = not tradable (configurable)
- [x] Output: `total_score`, `component_scores`, `grade`

### 8. Add ThinBookDetector
- [x] Create `app/engines/detectors/thin_book_detector.rb`
- [x] Order book depth < threshold (configurable)
- [x] Threshold: top 5 levels total < 500 contracts (NIFTY)
- [x] Check both bid and ask sides
- [x] Output: `thin_book?`, `bid_depth`, `ask_depth`, `severity`

### 9. Implement LowOIDetector
- [x] Create `app/engines/detectors/low_oi_detector.rb`
- [x] Option OI < 20-day average * 0.5
- [x] Per strike, per expiry
- [x] Low OI = poor liquidity, wide spreads, high slippage
- [x] Output: `low_oi_strikes`, `oi_ratios`, `rejection_list`

### 10. Create LowVolumeDetector
- [x] Create `app/engines/detectors/low_volume_detector.rb`
- [x] Option volume < 20-day average * 0.3
- [x] Intraday: volume pace vs expected for time of day
- [x] Low volume = difficult to exit, unreliable Greeks
- [x] Output: `low_volume_strikes`, `volume_ratios`, `rejection_list`

### 11. Write Tests with Simulated Order Book Scenarios
- [x] Create `spec/engines/liquidity_engine_spec.rb`
- [x] Fixtures:
  - Liquid market: tight spreads, deep book, high volume
  - Illiquid market: wide spreads, thin book, low volume
  - Absorption at support/resistance
  - Liquidity wall causing rejection
  - Pre-market thin book
  - Expiry day liquidity shift
- [x] Test slippage estimator against historical fills
- [x] Test rejection logic catches known bad conditions

---

## Acceptance Criteria
- [x] Engine assesses liquidity in < 20ms
- [x] Spread analyzer rejects > 0.30% option spreads
- [x] Slippage estimator within 20% of actual fills
- [x] Thin book detector catches pre-market conditions
- [x] Low OI/Volume detectors prevent bad strike selection
- [x] Liquidity score correlates with fill quality
- [x] Output feeds Trade Scoring Engine (10% weight)
- [x] Rejection reasons logged for audit

---

## Notes
- Liquidity engine runs on every market depth update (5s) and option chain (30s)
- Critical gate: if `tradable? = false`, Trade Scoring Engine returns 0
- Slippage estimation used by Execution Engine for limit price setting
- Order book pressure feeds Market Structure (liquidity sweeps)
- Option liquidity checked per strike at trade entry time
- Cache liquidity scores in Redis (TTL: 30s)