# Milestone 2.3: Option Chain Data Store

**Phase:** 2 — Data Platform  
**Goal:** Rich option chain analytics with derived metrics.  
**Estimated Tasks:** 13

---

## Tasks

### 1. Create OptionChainSnapshot Model
- [ ] Generate model: `rails g model OptionChainSnapshot`
- [ ] Columns (from migration in Milestone 0.3):
  - `instrument_id`, `snapshot_time`, `strike`, `expiry`, `option_type`
  - `ce_oi`, `pe_oi`, `ce_volume`, `pe_volume`
  - `iv`, `delta`, `gamma`, `theta`, `vega`
  - `bid`, `ask`, `spread`, `ltp`
  - `metadata` (jsonb)
- [ ] Add scopes: `for_underlying`, `for_expiry`, `at_snapshot`, `near_strike`
- [ ] Add `to_domain` method converting to `OptionChainSnapshot` domain object

### 2. Implement OIChangeCalculator
- [ ] Create `app/services/calculations/oi_change_calculator.rb`
- [ ] Compare current snapshot to previous (30s ago)
- [ ] Per-strike OI change: `ce_oi_change`, `pe_oi_change`
- [ ] Classify OI action:
  - `ce_oi_change > 0 && price_up` → `long_build_up`
  - `ce_oi_change > 0 && price_down` → `short_build_up`
  - `ce_oi_change < 0 && price_up` → `short_covering`
  - `ce_oi_change < 0 && price_down` → `long_unwinding`
  - Same for PE with inverted logic
- [ ] Aggregate: total CE OI change, total PE OI change, net OI change

### 3. Add VolumeChangeCalculator
- [ ] Create `app/services/calculations/volume_change_calculator.rb`
- [ ] Per-strike volume vs 20-day average for same time of day
- [ ] `relative_volume = current_volume / avg_volume_20d`
- [ ] Volume trend: rising/falling/flat over last 5 snapshots
- [ ] Flag unusual volume: > 3x average

### 4. Create IVRankCalculator
- [ ] Create `app/services/calculations/iv_rank_calculator.rb`
- [ ] IV Rank = `(current_iv - iv_52w_low) / (iv_52w_high - iv_52w_low) * 100`
- [ ] Source: historical IV from `option_chain_snapshots` (daily close IV)
- [ ] Maintain 52-week high/low per strike/expiry in Redis
- [ ] Update daily at market close
- [ ] Handle new strikes (no history): use ATM IV as proxy

### 5. Implement IVPercentileCalculator
- [ ] Create `app/services/calculations/iv_percentile_calculator.rb`
- [ ] IV Percentile = % of days in 52 weeks where IV < current IV
- [ ] More robust than IV Rank (less sensitive to outliers)
- [ ] Calculate using `percentile_rank` from Statistics module
- [ ] Cache percentile per strike/expiry (update daily)

### 6. Add SpreadCalculator
- [ ] Create `app/services/calculations/spread_calculator.rb`
- [ ] Bid-ask spread: `ask - bid`
- [ ] Spread %: `spread / mid_price * 100`
- [ ] Spread in ticks: `spread / tick_size`
- [ ] Track: min/avg/max spread per strike over session
- [ ] Flag illiquid: spread % > 0.5% or spread > 5 ticks

### 7. Create LiquidityScoreCalculator
- [ ] Create `app/services/calculations/liquidity_score_calculator.rb`
- [ ] Components (weighted):
  - Spread score (30%): inverse of spread %
  - Depth score (25%): bid+ask size at top 3 levels
  - Volume score (20%): relative volume
  - OI score (15%): total OI vs 20-day average
  - IV score (10%): IV in normal range (not too high/low)
- [ ] Normalize each component 0-100, compute weighted sum
- [ ] Output: `liquidity_score` (0-100), `liquidity_grade` (A-F)

### 8. Implement GammaChangeCalculator (dGamma/dTime)
- [ ] Create `app/services/calculations/gamma_change_calculator.rb`
- [ ] Gamma velocity: `gamma_now - gamma_previous` per 30s
- [ ] Gamma acceleration: `velocity_now - velocity_previous`
- [ ] Identify: gamma ramp (increasing), gamma decay (decreasing)
- [ ] Critical for 0DTE and expiry day trading

### 9. Add GammaAccelerationCalculator (Second Derivative)
- [ ] Create `app/services/calculations/gamma_acceleration_calculator.rb`
- [ ] Second derivative of gamma wrt time
- [ ] Formula: `acceleration = (gamma_t - 2*gamma_t-1 + gamma_t-2) / dt^2`
- [ ] Positive acceleration = gamma expanding rapidly (high convexity)
- [ ] Negative acceleration = gamma compressing
- [ ] Use for: entry timing (avoid negative acceleration), exit signals

### 10. Create ThetaDecayEstimator
- [ ] Create `app/services/calculations/theta_decay_estimator.rb`
- [ ] Expected theta decay until target exit time
- [ ] `estimated_decay = theta * hours_to_exit * 3600`
- [ ] Compare to expected move: `ATR * sqrt(hours_to_exit / 24)`
- [ ] Ratio: `decay / expected_move` - if > 1, theta risk high
- [ ] Output: `theta_risk_score` (0-100), `recommended_max_hold_hours`

### 11. Implement OIClassification
- [ ] Create `app/services/calculations/oi_classification.rb`
- [ ] Combine CE and PE OI changes with price action
- [ ] Classifications:
  - `Long Build-up`: CE OI↑ + PE OI↓ + price↑
  - `Short Build-up`: CE OI↑ + PE OI↓ + price↓
  - `Long Unwinding`: CE OI↓ + PE OI↑ + price↓
  - `Short Covering`: CE OI↓ + PE OI↑ + price↑
  - `Neutral`: mixed or flat OI
- [ ] Confidence score based on magnitude of changes

### 12. Add OptionFlowScore
- [ ] Create `app/services/calculations/option_flow_score.rb`
- [ ] Composite score combining:
  - OI flow direction (bullish/bearish/neutral)
  - Volume confirmation (high volume = high conviction)
  - IV trend (rising IV = uncertainty, falling = confidence)
  - Gamma profile (positive gamma = supportive for buyers)
- [ ] Output: `flow_score` (-100 to +100), `flow_label`
- [ ] Used by Option Intelligence Engine

### 13. Create OptionChainRepository
- [ ] Create `app/services/repositories/option_chain_repository.rb`
- [ ] Methods:
  - `latest_snapshot(underlying, expiry)` - full chain
  - `strike_range(underlying, expiry, from:, to:)`
  - `atm_strikes(underlying, expiry, count: 5)`
  - `greeks_at(underlying, expiry, strike, option_type)`
  - `iv_rank_at(underlying, expiry, strike, option_type)`
  - `liquidity_score_at(underlying, expiry, strike)`
  - `flow_score_at(underlying, expiry, strike)`
  - `history(underlying, expiry, strike, from:, to:)`
- [ ] Optimize with composite indexes
- [ ] Cache latest snapshot in Redis (TTL: 30s)

### 14. Write Tests for Option Analytics
- [ ] Create `spec/services/calculations/option_analytics_spec.rb`
- [ ] Test cases:
  - OI classification with known scenarios
  - IV rank/percentile with synthetic 52-week data
  - Spread calculation edge cases (zero bid, wide spread)
  - Liquidity score components and weighting
  - Gamma velocity/acceleration with known sequences
  - Theta decay vs expected move ratio
  - Option flow score direction and magnitude
  - Repository queries return correct data shapes

---

## Acceptance Criteria
- [ ] All 10 calculators produce mathematically correct results
- [ ] OptionChainRepository queries execute in < 10ms
- [ ] IV rank/percentile update daily and handle new strikes
- [ ] OI classification matches manual analysis on historical data
- [ ] Liquidity score correlates with actual fill rates
- [ ] Gamma acceleration detects expiry-day gamma ramp
- [ ] Theta decay estimator warns on high time-risk trades
- [ ] Option flow score provides actionable directional bias
- [ ] All tests pass with property-based verification

---

## Notes
- Greeks from DhanHQ may have different conventions; verify Delta sign (call +, put -)
- IV Rank needs 52 weeks of data; bootstrap with 30 days initially
- Liquidity score weights should be configurable via AppConfig
- Option chain snapshots every 30s → 1,440 snapshots/day per expiry
- Consider partitioning `option_chain_snapshots` by expiry date
- Cache aggressively: latest snapshot, ATM strikes, IV ranks