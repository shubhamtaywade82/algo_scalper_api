# Milestone 3.2: Option Features

**Phase:** 3 — Feature Engineering  
**Goal:** Greeks-derived and option-specific features.  
**Estimated Tasks:** 15

---

## Tasks

### 1. Implement DeltaFeature
- [ ] Create `app/services/calculations/features/delta_feature.rb`
- [ ] Input: option delta (from option chain)
- [ ] Ideal range scoring (configurable):
  - 0.40 - 0.65: 100 (ATM sweet spot)
  - 0.30 - 0.40: 80
  - 0.65 - 0.75: 70
  - 0.20 - 0.30: 50
  - 0.75 - 0.85: 40
  - Outside: 0
- [ ] Direction alignment: call delta > 0 for long, put delta < 0 for long
- [ ] Return: `score` (0-100), `delta`, `in_ideal_range?`

### 2. Implement GammaFeature
- [ ] Create `app/services/calculations/features/gamma_feature.rb`
- [ ] Gamma velocity: rate of delta change per underlying move
- [ ] Gamma acceleration: rate of gamma change (from Milestone 2.3)
- [ ] Scoring:
  - High gamma (> 0.01): 80 (responsive but risky)
  - Medium gamma (0.005-0.01): 100 (balanced)
  - Low gamma (< 0.005): 40 (slow delta change)
- [ ] Expiry adjustment: gamma spikes near expiry
- [ ] Return: `score`, `gamma`, `velocity`, `acceleration`, `expiry_risk`

### 3. Implement ThetaFeature
- [ ] Create `app/services/calculations/features/theta_feature.rb`
- [ ] Daily theta decay (from option chain)
- [ ] Compare to expected move: `ATR_15m * sqrt(hold_hours/24)`
- [ ] Theta/Expected Move ratio:
  - < 0.3: 100 (theta favorable)
  - 0.3 - 0.5: 70
  - 0.5 - 0.8: 40
  - > 0.8: 10 (theta will likely exceed move)
- [ ] Time to expiry adjustment: accelerate scoring near expiry
- [ ] Return: `score`, `theta`, `expected_move`, `theta_risk_ratio`

### 4. Implement VegaFeature
- [ ] Create `app/services/calculations/features/vega_feature.rb`
- [ ] Vega sensitivity: P&L change per 1% IV change
- [ ] IV trend context (from IVTrendFeature):
  - IV rising + long vega: positive
  - IV falling + long vega: negative
- [ ] Scoring based on IV percentile:
  - IV < 30th percentile: 80 (vega cheap)
  - 30th - 70th: 100 (neutral)
  - > 70th percentile: 40 (vega expensive)
- [ ] Return: `score`, `vega`, `iv_percentile`, `iv_trend`

### 5. Create IVRankFeature
- [ ] Create `app/services/calculations/features/iv_rank_feature.rb`
- [ ] Use IVRankCalculator from Milestone 2.3
- [ ] Scoring (mean reversion assumption):
  - IV Rank < 20: 90 (IV likely to rise, good for buyers)
  - 20 - 40: 70
  - 40 - 60: 50 (neutral)
  - 60 - 80: 30
  - > 80: 10 (IV likely to fall, bad for buyers)
- [ ] Adjust for earnings/events: reduce score if event pending
- [ ] Return: `score`, `iv_rank`, `iv_percentile`, `event_risk`

### 6. Implement IVTrendFeature
- [ ] Create `app/services/calculations/features/iv_trend_feature.rb`
- [ ] IV trend over last 10 snapshots (5 minutes)
- [ ] Classification: `rising`, `falling`, `flat`, `volatile`
- [ ] Slope: linear regression on IV series
- [ ] Scoring for buyers:
  - Falling IV: 80 (tailwind)
  - Flat: 50
  - Rising: 30 (headwind)
  - Volatile: 20 (unpredictable)
- [ ] Return: `score`, `trend`, `slope`, `volatility`

### 7. Add OIFlowFeature
- [ ] Create `app/services/calculations/features/oi_flow_feature.rb`
- [ ] Use OIClassification from Milestone 2.3
- [ ] Directional scoring:
  - Long Build-up (bullish): +80 for CE, -80 for PE
  - Short Build-up (bearish): -80 for CE, +80 for PE
  - Long Unwinding: -40 for CE, +40 for PE
  - Short Covering: +40 for CE, -40 for PE
  - Neutral: 0
- [ ] Magnitude weighting: scale by OI change % vs average
- [ ] Return: `score`, `classification`, `magnitude`, `direction`

### 8. Implement VolumeFlowFeature
- [ ] Create `app/services/calculations/features/volume_flow_feature.rb`
- [ ] Option volume vs 20-day average
- [ ] CE volume vs PE volume ratio (put/call ratio)
- [ ] Volume-weighted price change
- [ ] Scoring:
  - High volume + price direction aligned: 80
  - High volume + divergence: 40
  - Low volume: 20 (unreliable)
- [ ] Return: `score`, `ce_volume`, `pe_volume`, `pc_ratio`, `volume_trend`

### 9. Create SpreadFeature
- [ ] Create `app/services/calculations/features/spread_feature.rb`
- [ ] Bid-ask spread % and in ticks
- [ ] Spread vs 20-day average for same strike
- [ ] Scoring (lower spread = better):
  - Spread < 0.2%: 100
  - 0.2% - 0.5%: 70
  - 0.5% - 1.0%: 40
  - > 1.0%: 10 (illiquid)
- [ ] Return: `score`, `spread_pct`, `spread_ticks`, `vs_average`

### 10. Implement LiquidityScoreFeature
- [ ] Create `app/services/calculations/features/liquidity_score_feature.rb`
- [ ] Composite of: Spread (30%), Depth (25%), Volume (20%), OI (15%), IV (10%)
- [ ] Use LiquidityScoreCalculator from Milestone 2.3
- [ ] Normalize 0-100
- [ ] Threshold: < 50 = reject trade
- [ ] Return: `score`, `components`, `grade`, `tradable?`

### 11. Add GammaScoreFeature
- [ ] Create `app/services/calculations/features/gamma_score_feature.rb`
- [ ] Strike responsiveness score
- [ ] Factors: gamma level, gamma velocity, distance from ATM
- [ ] Peak at ATM, decay symmetrically
- [ ] Adjust for time to expiry (gamma higher near expiry)
- [ ] Return: `score`, `gamma`, `atm_distance`, `expiry_factor`

### 12. Create OptionFeatureNormalizer
- [ ] Create `app/services/calculations/features/option_feature_normalizer.rb`
- [ ] Scale all feature scores to 0-100 range
- [ ] Apply winsorization at 1st/99th percentile
- [ ] Z-score normalization option for ML features
- [ ] Output: `normalized_features` hash ready for scoring engine

### 13. Implement FeatureStore
- [ ] Create `app/services/feature_store.rb`
- [ ] Redis-backed real-time feature access
- [ ] Key: `features:{instrument_id}:{strike}:{expiry}:{option_type}`
- [ ] TTL: 30 seconds (refresh on each option chain snapshot)
- [ ] Methods:
  - `write(features)`
  - `read(instrument_id, strike, expiry, type)`
  - `read_atm_range(underlying, expiry, count: 5)`
  - `all_for_expiry(underlying, expiry)`
- [ ] Pub/Sub invalidation on new snapshot

### 14. Add Feature Freshness Validation
- [ ] Create `app/services/validators/feature_validator.rb`
- [ ] Reject features older than 5 seconds (configurable)
- [ ] Check: all required features present
- [ ] Check: no stale Greeks (IV, delta, gamma, theta, vega)
- [ ] Check: underlying price within 1% of feature calculation price
- [ ] Return: `valid?`, `stale_features`, `age_seconds`

### 15. Write Tests for Feature Accuracy
- [ ] Create `spec/services/calculations/features/option_features_spec.rb`
- [ ] Test each feature with known inputs/outputs
- [ ] Edge cases: 0DTE, deep ITM/OTM, zero IV, missing Greeks
- [ ] Integration: feature store read/write with freshness
- [ ] Property tests: scores always 0-100, normalization preserves ordering

---

## Acceptance Criteria
- [ ] All 11 option features implemented and tested
- [ ] FeatureNormalizer produces consistent 0-100 scores
- [ ] FeatureStore reads/writes at < 5ms latency
- [ ] Freshness validator rejects stale data correctly
- [ ] Features match Option Intelligence Engine requirements
- [ ] All scores mathematically verified
- [ ] Integration test: full option chain → features → scores pipeline

---

## Notes
- Features are consumed by: Strike Selection Engine, Trade Scoring Engine, Option Intelligence Engine
- Feature versions: include `feature_version` in stored hash for schema evolution
- IV Rank/Percentile need 52-week history; bootstrap with available data
- Liquidity score is critical gate: < 50 = no trade regardless of other scores
- Consider adding `feature_metadata` with calculation timestamps for debugging