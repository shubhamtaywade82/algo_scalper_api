# Milestone 4.6: Option Intelligence Engine

**Phase:** 4 — Market Intelligence Engines  
**Goal:** Transform raw option chain into actionable intelligence.  
**Estimated Tasks:** 14

---

## Tasks

### 1. Implement OptionIntelligenceEngine
- [x] Create `app/engines/option_intelligence_engine.rb`
- [x] Interface: `analyze(input) -> OptionIntelligenceOutput`
- [x] Input: `OptionIntelligenceInput` with full option chain snapshot, underlying price, time
- [x] Output: `OptionIntelligenceOutput` with:
  - `composite_score` (0-100)
  - `component_scores` (hash)
  - `strike_analysis` (per strike scores)
  - `expiry_analysis` (per expiry scores)
  - `directional_bias` (:bullish, :bearish, :neutral)
  - `key_levels` (support/resistance from OI)
  - `warnings` (array)

### 2. Add OIFlowClassifier
- [x] Create `app/engines/classifiers/oi_flow_classifier.rb`
- [x] Classify per strike and aggregate:
  - `Long Build-up`: CE OI↑ + price↑ (bullish)
  - `Short Build-up`: CE OI↑ + price↓ (bearish)
  - `Long Unwinding`: CE OI↓ + price↓ (bearish)
  - `Short Covering`: CE OI↓ + price↑ (bullish)
  - Same for PE with inverted logic
- [x] Aggregate: net bullish/bearish OI flow
- [x] Weight by volume and proximity to ATM
- [x] Output: `classification`, `net_flow`, `confidence`, `per_strike`

### 3. Implement GammaVelocityCalculator
- [x] Create `app/engines/calculators/gamma_velocity_calculator.rb`
- [x] Gamma velocity = d(gamma)/dt per strike
- [x] Track gamma change per 30s snapshot
- [x] Identify: gamma ramp (accelerating), gamma decay (decelerating)
- [x] Gamma center of mass: volume-weighted average strike of gamma
- [x] Output: `gamma_velocity`, `gamma_acceleration`, `gamma_com`, `ramp_detected`

### 4. Create GammaAccelerationCalculator
- [x] Create `app/engines/calculators/gamma_acceleration_calculator.rb`
- [x] Second derivative: d²(gamma)/dt²
- [x] High acceleration = convexity increasing rapidly
- [x] Critical for 0DTE and expiry day
- [x] Threshold: acceleration > 2x average = alert
- [x] Output: `acceleration`, `acceleration_zscore`, `convexity_alert`

### 5. Add IVRankCalculator
- [x] Create `app/engines/calculators/iv_rank_calculator.rb`
- [x] IV Rank per strike/expiry: `(IV - IV_52w_low) / (IV_52w_high - IV_52w_low) * 100`
- [x] ATM IV Rank (most important for strategy)
- [x] IV Rank trend: rising/falling over 5 days
- [x] Skew: IV Rank ATM vs OTM (put/call skew)
- [x] Output: `atm_iv_rank`, `iv_rank_trend`, `skew`, `percentile`

### 6. Implement IVPercentileCalculator
- [x] Create `app/engines/calculators/iv_percentile_calculator.rb`
- [x] IV Percentile = % days in 52w where IV < current IV
- [x] More robust than IV Rank (less sensitive to outliers)
- [x] Calculate per strike, aggregate ATM
- [x] Output: `iv_percentile`, `vs_rank_difference`, `interpretation`

### 7. Create IVTrendAnalyzer
- [x] Create `app/engines/analyzers/iv_trend_analyzer.rb`
- [x] IV trend over last 20 snapshots (10 minutes)
- [x] Classification: `rising`, `falling`, `elevated_stable`, `crushing`
- [x] IV Crush detection: IV drop > 10% in 30 min (earnings/events)
- [x] Event-adjusted: compare to expected move
- [x] Output: `trend`, `slope`, `crush_detected`, `event_risk`

### 8. Add ThetaDecayAnalyzer
- [x] Create `app/engines/analyzers/theta_decay_analyzer.rb`
- [x] Theta per strike (from chain)
- [x] Expected decay until target exit: `theta * hours_to_exit`
- [x] Compare to expected move: `ATR_15m * sqrt(hours_to_exit / 24)`
- [x] Theta/Expected Move ratio:
  - < 0.3: favorable (theta tailwind)
  - 0.3-0.6: neutral
  - > 0.6: unfavorable (theta headwind)
- [x] Output: `theta_per_strike`, `decay_estimate`, `move_estimate`, `ratio`, `assessment`

### 9. Implement GammaScoreCalculator
- [x] Create `app/engines/calculators/gamma_score_calculator.rb`
- [x] Strike selection score based on gamma profile
- [x] Factors:
  - Gamma level (moderate ideal, not too high/low)
  - Gamma velocity (positive = improving responsiveness)
  - Distance from ATM (gamma peaks at ATM)
  - Time to expiry (gamma spikes near expiry)
- [x] Output: `gamma_score` per strike (0-100), `optimal_strike_range`

### 10. Create IVScoreCalculator
- [x] Create `app/engines/calculators/iv_score_calculator.rb`
- [x] Entry timing score based on IV
- [x] Favor: low IV Rank (< 40), falling IV trend, IV < HV (historical vol)
- [x] Penalize: high IV Rank (> 70), rising IV, IV >> HV
- [x] Event adjustment: reduce score if binary event pending
- [x] Output: `iv_score` (0-100), `entry_timing` (:favorable, :neutral, :unfavorable)

### 11. Add FlowScoreCalculator
- [x] Create `app/engines/calculators/flow_score_calculator.rb`
- [x] Directional conviction from option flow
- [x] Components:
  - OI flow direction (30%)
  - Volume flow direction (25%)
  - Gamma flow (gamma * volume * price change) (25%)
  - IV flow (IV change * OI change) (20%)
- [x] Net score: -100 (bearish) to +100 (bullish)
- [x] Output: `flow_score`, `components`, `conviction` (high/med/low)

### 12. Implement ThetaScoreCalculator
- [x] Create `app/engines/calculators/theta_score_calculator.rb`
- [x] Time risk score for holding period
- [x] Factors:
  - Theta/Expected Move ratio (40%)
  - Days to expiry (30%) - less days = higher risk
  - Gamma acceleration (20%) - high accel = theta risk increases
  - IV trend (10%) - falling IV helps theta
- [x] Output: `theta_score` (0-100), `max_recommended_hold_hours`, `decay_warning`

### 13. Create Composite OptionIntelligenceScore
- [x] Create `app/engines/calculators/option_intelligence_score_calculator.rb`
- [x] Weighted composite:
  - OI Flow: 20%
  - Gamma: 20%
  - IV Rank/Percentile: 15%
  - IV Trend: 10%
  - Theta Decay: 15%
  - Flow Score: 20%
- [x] Directional adjustment: align with Market Structure bias
- [x] Output: `composite_score` (0-100), `directional_bias`, `confidence`, `component_breakdown`

### 14. Write Tests for All OI Flow Classifications
- [x] Create `spec/engines/option_intelligence_engine_spec.rb`
- [x] Fixtures for each OI classification:
  - Long Build-up: CE OI +50k, price +1%
  - Short Build-up: CE OI +50k, price -1%
  - Long Unwinding: CE OI -30k, price -0.5%
  - Short Covering: CE OI -30k, price +0.5%
  - Mixed/conflicting signals
- [x] Test gamma velocity/acceleration with known sequences
- [x] Test IV rank/percentile with synthetic 52-week data
- [x] Test theta decay vs expected move ratios
- [x] Test composite score integrates all components correctly
- [x] Test directional bias matches known market scenarios

---

## Acceptance Criteria
- [x] Engine analyzes full chain in < 100ms
- [x] OI classifier matches manual analysis on historical data
- [x] Gamma velocity detects expiry-day ramp 30 min early
- [x] IV rank/percentile accurate vs manual calculation
- [x] Theta decay analyzer warns on unfavorable time risk
- [x] Flow score correlates with next 30-min price direction
- [x] Composite score feeds Trade Scoring Engine (15% weight)
- [x] Strike analysis output used by Strike Selection Engine
- [x] All tests pass with property-based verification

---

## Notes
- Option Intelligence runs on every chain snapshot (30s)
- Most compute-heavy engine; optimize with incremental updates
- Gamma calculations critical for 0DTE and expiry day
- IV metrics need 52-week history; bootstrap initially
- Flow score is directional; combine with Market Structure for confirmation
- Theta score prevents holding into excessive decay
- Output structure designed for AI Gateway context enrichment