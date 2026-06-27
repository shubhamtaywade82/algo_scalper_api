# Milestone 4.5: Liquidity Engine

**Phase:** 4 — Market Intelligence Engines  
**Goal:** Reject illiquid markets and estimate slippage.  
**Estimated Tasks:** 11

---

## Tasks

### 1. Implement LiquidityEngine
- [ ] Create `app/engines/liquidity_engine.rb`
- [ ] Interface: `assess(input) -> LiquidityOutput`
- [ ] Input: `LiquidityInput` with market depth, option chain, spreads
- [ ] Output: `LiquidityOutput` with:
  - `liquidity_score` (0-100)
  - `tradable?` (boolean, threshold configurable)
  - `estimated_slippage` (ticks and rupees)
  - `rejection_reasons` (array)
  - `warnings` (array)

### 2. Add SpreadAnalyzer
- [ ] Create `app/engines/analyzers/spread_analyzer.rb`
- [ ] Underlying spread: NIFTY/BANKNIFTY futures spread
- [ ] Option spread: per strike, bid-ask %
- [ ] Thresholds (configurable):
  - Underlying spread > 0.15% = reject
  - Option spread > 0.30% = reject
  - Option spread > 0.50% = warn
- [ ] Spread percentile: current vs 20-day average
- [ ] Output: `underlying_spread`, `option_spreads`, `percentiles`, `rejections`

### 3. Implement BidAskImbalanceCalculator
- [ ] Create `app/engines/calculators/bid_ask_imbalance_calculator.rb`
- [ ] Order book imbalance: `(bid_volume - ask_volume) / (bid_volume + ask_volume)`
- [ ] Levels: top 1, top 3, top 5
- [ ] Imbalance > 0.3 = strong directional pressure
- [ ] Track imbalance trend (rising/falling)
- [ ] Output: `imbalance_1`, `imbalance_3`, `imbalance_5`, `trend`, `pressure_direction`

### 4. Create OrderBookPressureAnalyzer
- [ ] Create `app/engines/analyzers/order_book_pressure_analyzer.rb`
- [ ] Liquidity walls: large orders at specific prices
- [ ] Wall detection: size > 5x average level size
- [ ] Pressure: cumulative bid vs ask volume (top 10 levels)
- [ ] Absorption: large market orders hitting wall with minimal price move
- [ ] Output: `walls`, `pressure_ratio`, `absorption_events`, `support_resistance_levels`

### 5. Add AbsorptionDetector
- [ ] Create `app/engines/detectors/absorption_detector.rb`
- [ ] Detect: aggressive orders (market) hitting passive liquidity
- [ ] Signature: large volume trade, minimal price change, liquidity replenishes
- [ ] Bullish absorption: selling absorbed at support
- [ ] Bearish absorption: buying absorbed at resistance
- [ ] Output: `absorption_events` with `type`, `price`, `volume`, `strength`

### 6. Implement SlippageEstimator
- [ ] Create `app/engines/calculators/slippage_estimator.rb`
- [ ] Market order slippage: walk the book for order size
- [ ] Limit order slippage: probability of fill at limit
- [ ] Model: `slippage = spread/2 + market_impact(size)`
- [ ] Market impact: `size / avg_daily_volume * ATR * factor`
- [ ] Output: `expected_slippage_ticks`, `expected_slippage_rupees`, `fill_probability`

### 7. Create LiquidityScoreCalculator
- [ ] Create `app/engines/calculators/liquidity_score_calculator.rb`
- [ ] Components (weighted):
  - Underlying spread: 20%
  - Option spread (ATM): 20%
  - Order book depth (top 5): 20%
  - Bid/ask imbalance stability: 15%
  - Volume/turnover: 15%
  - Absorption/pressure quality: 10%
- [ ] Normalize each 0-100, weighted sum
- [ ] Threshold: < 60 = not tradable (configurable)
- [ ] Output: `total_score`, `component_scores`, `grade`

### 8. Add ThinBookDetector
- [ ] Create `app/engines/detectors/thin_book_detector.rb`
- [ ] Order book depth < threshold (configurable)
- [ ] Threshold: top 5 levels total < 500 contracts (NIFTY)
- [ ] Check both bid and ask sides
- [ ] Output: `thin_book?`, `bid_depth`, `ask_depth`, `severity`

### 9. Implement LowOIDetector
- [ ] Create `app/engines/detectors/low_oi_detector.rb`
- [ ] Option OI < 20-day average * 0.5
- [ ] Per strike, per expiry
- [ ] Low OI = poor liquidity, wide spreads, high slippage
- [ ] Output: `low_oi_strikes`, `oi_ratios`, `rejection_list`

### 10. Create LowVolumeDetector
- [ ] Create `app/engines/detectors/low_volume_detector.rb`
- [ ] Option volume < 20-day average * 0.3
- [ ] Intraday: volume pace vs expected for time of day
- [ ] Low volume = difficult to exit, unreliable Greeks
- [ ] Output: `low_volume_strikes`, `volume_ratios`, `rejection_list`

### 11. Write Tests with Simulated Order Book Scenarios
- [ ] Create `spec/engines/liquidity_engine_spec.rb`
- [ ] Fixtures:
  - Liquid market: tight spreads, deep book, high volume
  - Illiquid market: wide spreads, thin book, low volume
  - Absorption at support/resistance
  - Liquidity wall causing rejection
  - Pre-market thin book
  - Expiry day liquidity shift
- [ ] Test slippage estimator against historical fills
- [ ] Test rejection logic catches known bad conditions

---

## Acceptance Criteria
- [ ] Engine assesses liquidity in < 20ms
- [ ] Spread analyzer rejects > 0.30% option spreads
- [ ] Slippage estimator within 20% of actual fills
- [ ] Thin book detector catches pre-market conditions
- [ ] Low OI/Volume detectors prevent bad strike selection
- [ ] Liquidity score correlates with fill quality
- [ ] Output feeds Trade Scoring Engine (10% weight)
- [ ] Rejection reasons logged for audit

---

## Notes
- Liquidity engine runs on every market depth update (5s) and option chain (30s)
- Critical gate: if `tradable? = false`, Trade Scoring Engine returns 0
- Slippage estimation used by Execution Engine for limit price setting
- Order book pressure feeds Market Structure (liquidity sweeps)
- Option liquidity checked per strike at trade entry time
- Cache liquidity scores in Redis (TTL: 30s)