# Milestone 3.2: Option Features

**Phase:** 3 — Feature Engineering  
**Goal:** Greeks-derived and option-specific features.  
**Estimated Tasks:** 15

---

## Tasks

### 1. Implement DeltaFeature
- [x] Create `app/services/calculations/features/delta_feature.rb`
- [x] Input: option delta (from option chain)
- [x] Ideal range scoring (configurable):
  - 0.40 - 0.65: 100 (ATM sweet spot)
  - 0.30 - 0.40: 80
  - 0.65 - 0.75: 70
  - 0.20 - 0.30: 50
  - 0.75 - 0.85: 40
  - Outside: 0
- [x] Direction alignment: call delta > 0 for long, put delta < 0 for long
- [x] Return: `score` (0-100), `delta`, `in_ideal_range?`

### 2. Implement GammaFeature
- [x] Create `app/services/calculations/features/gamma_feature.rb`
- [x] Gamma velocity: rate of delta change per underlying move
- [x] Gamma acceleration: rate of gamma change (from Milestone 2.3)
- [x] Scoring:
  - High gamma (> 0.01): 80 (responsive but risky)
  - Medium gamma (0.005-0.01): 100 (balanced)
  - Low gamma (< 0.005): 40 (slow delta change)
- [x] Expiry adjustment: gamma spikes near expiry
- [x] Return: `score`, `gamma`, `velocity`, `acceleration`, `expiry_risk`

### 3. Implement ThetaFeature
- [x] Create `app/services/calculations/features/theta_feature.rb`
- [x] Daily theta decay (from option chain)
- [x] Compare to expected move: `ATR_15m * sqrt(hold_hours/24)`
- [x] Theta/Expected Move ratio:
  - < 0.3: 100 (theta favorable)
  - 0.3 - 0.5: 70
  - 0.5 - 0.8: 40
  - > 0.8: 10 (theta will likely exceed move)
- [x] Time to expiry adjustment: accelerate scoring near expiry
- [x] Return: `score`, `theta`, `expected_move`, `theta_risk_ratio`

### 4. Implement VegaFeature
- [x] Create `app/services/calculations/features/vega_feature.rb`
- [x] Vega sensitivity: P&L change per 1% IV change
- [x] IV trend context (from IVTrendFeature):
  - IV rising + long vega: positive
  - IV falling + long vega: negative
- [x] Scoring based on IV percentile:
  - IV < 30th percentile: 80 (vega cheap)
  - 30th - 70th: 100 (neutral)
  - > 70th percentile: 40 (vega expensive)
- [x] Return: `score`, `vega`, `iv_percentile`, `iv_trend`

### 5. Create IVRankFeature
- [x] Create `app/services/calculations/features/iv_rank_feature.rb`
- [x] Use IVRankCalculator from Milestone 2.3
- [x] Scoring (mean reversion assumption):
  - IV Rank < 20: 90 (IV likely to rise, good for buyers)
  - 20 - 40: 70
  - 40 - 60: 50 (neutral)
  - 60 - 80: 30
  - > 80: 10 (IV likely to fall, bad for buyers)
- [x] Adjust for earnings/events: reduce score if event pending
- [x] Return: `score`, `iv_rank`, `iv_percentile`, `event_risk`

### 6. Implement IVTrendFeature
- [x] Create `app/services/calculations/features/iv_trend_feature.rb`
- [x] IV trend over last 10 snapshots (5 minutes)
- [x] Classification: `rising`, `falling`, `flat`, `volatile`
- [x] Slope: linear regression on IV series
- [x] Scoring for buyers:
  - Falling IV: 80 (tailwind)
  - Flat: 50
  - Rising: 30 (headwind)
  - Volatile: 20 (unpredictable)
- [x] Return: `score`, `trend`, `slope`, `volatility`

### 7. Add OIFlowFeature
- [x] Create `app/services/calculations/features/oi_flow_feature.rb`
- [x] Use OIClassification from Milestone 2.3
- [x] Directional scoring:
  - Long Build-up (bullish): +80 for CE, -80 for PE
  - Short Build-up (bearish): -80 for CE, +80 for PE
  - Long Unwinding: -40 for CE, +40 for PE
  - Short Covering: +40 for CE, -40 for PE
  - Neutral: 0
- [x] Magnitude weighting: scale by OI change % vs average
- [x] Return: `score`, `classification`, `magnitude`, `direction`

### 8. Implement VolumeFlowFeature
- [x] Create `app/services/calculations/features/volume_flow_feature.rb`
- [x] Option volume vs 20-day average
- [x] CE volume vs PE volume ratio (put/call ratio)
- [x] Volume-weighted price change
- [x] Scoring:
  - High volume + price direction aligned: 80
  - High volume + divergence: 40
  - Low volume: 20 (unreliable)
- [x] Return: `score`, `ce_volume`, `pe_volume`, `pc_ratio`, `volume_trend`

### 9. Create SpreadFeature
- [x] Create `app/services/calculations/features/spread_feature.rb`
- [x] Bid-ask spread % and in ticks
- [x] Spread vs 20-day average for same strike
- [x] Scoring (lower spread = better):
  - Spread < 0.2%: 100
  - 0.2% - 0.5%: 70
  - 0.5% - 1.0%: 40
  - > 1.0%: 10 (illiquid)
- [x] Return: `score`, `spread_pct`, `spread_ticks`, `vs_average`

### 10. Implement LiquidityScoreFeature
- [x] Create `app/services/calculations/features/liquidity_score_feature.rb`
- [x] Composite of: Spread (30%), Depth (25%), Volume (20%), OI (15%), IV (10%)
- [x] Use LiquidityScoreCalculator from Milestone 2.3
- [x] Normalize 0-100
- [x] Threshold: < 50 = reject trade
- [x] Return: `score`, `components`, `grade`, `tradable?`

### 11. Add GammaScoreFeature
- [x] Create `app/services/calculations/features/gamma_score_feature.rb`
- [x] Strike responsiveness score
- [x] Factors: gamma level, gamma velocity, distance from ATM
- [x] Peak at ATM, decay symmetrically
- [x] Adjust for time to expiry (gamma higher near expiry)
- [x] Return: `score`, `gamma`, `atm_distance`, `expiry_factor`

### 12. Create OptionFeatureNormalizer
- [x] Create `app/services/calculations/features/option_feature_normalizer.rb`
- [x] Scale all feature scores to 0-100 range
- [x] Apply winsorization at 1st/99th percentile
- [x] Z-score normalization option for ML features
- [x] Output: `normalized_features` hash ready for scoring engine

### 13. Implement FeatureStore
- [x] Create `app/services/feature_store.rb`
- [x] Redis-backed real-time feature access
- [x] Key: `features:{instrument_id}:{strike}:{expiry}:{option_type}`
- [x] TTL: 30 seconds (refresh on each option chain snapshot)
- [x] Methods:
  - `write(features)`
  - `read(instrument_id, strike, expiry, type)`
  - `read_atm_range(underlying, expiry, count: 5)`
  - `all_for_expiry(underlying, expiry)`
- [x] Pub/Sub invalidation on new snapshot

### 14. Add Feature Freshness Validation
- [x] Create `app/services/validators/feature_validator.rb`
- [x] Reject features older than 5 seconds (configurable)
- [x] Check: all required features present
- [x] Check: no stale Greeks (IV, delta, gamma, theta, vega)
- [x] Check: underlying price within 1% of feature calculation price
- [x] Return: `valid?`, `stale_features`, `age_seconds`

### 15. Write Tests for Feature Accuracy
- [x] Create `spec/services/calculations/features/option_features_spec.rb`
- [x] Test each feature with known inputs/outputs
- [x] Edge cases: 0DTE, deep ITM/OTM, zero IV, missing Greeks
- [x] Integration: feature store read/write with freshness
- [x] Property tests: scores always 0-100, normalization preserves ordering

---

## Acceptance Criteria
- [x] All 11 option features implemented and tested
- [x] FeatureNormalizer produces consistent 0-100 scores
- [x] FeatureStore reads/writes at < 5ms latency
- [x] Freshness validator rejects stale data correctly
- [x] Features match Option Intelligence Engine requirements
- [x] All scores mathematically verified
- [x] Integration test: full option chain → features → scores pipeline

---

## Notes
- Features are consumed by: Strike Selection Engine, Trade Scoring Engine, Option Intelligence Engine
- Feature versions: include `feature_version` in stored hash for schema evolution
- IV Rank/Percentile need 52-week history; bootstrap with available data
- Liquidity score is critical gate: < 50 = no trade regardless of other scores
- Consider adding `feature_metadata` with calculation timestamps for debugging