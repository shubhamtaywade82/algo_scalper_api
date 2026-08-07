# Milestone 2.3: Option Chain Data Store

**Phase:** 2 — Data Platform  
**Goal:** Rich option chain analytics with derived metrics.  
**Estimated Tasks:** 13

---

## Tasks

### 1. Create OptionChainSnapshot Model
- [x] Generate model: `rails g model OptionChainSnapshot`
- [x] Columns (from migration in Milestone 0.3):
  - `instrument_id`, `snapshot_time`, `strike`, `expiry`, `option_type`
  - `ce_oi`, `pe_oi`, `ce_volume`, `pe_volume`
  - `iv`, `delta`, `gamma`, `theta`, `vega`
  - `bid`, `ask`, `spread`, `ltp`
  - `metadata` (jsonb)
- [x] Add scopes: `for_underlying`, `for_expiry`, `at_snapshot`, `near_strike`
- [x] Add `to_domain` method converting to `OptionChainSnapshot` domain object

### 2. Implement OIChangeCalculator
- [x] Create `app/services/calculations/oi_change_calculator.rb`
- [x] Compare current snapshot to previous (30s ago)
- [x] Per-strike OI change: `ce_oi_change`, `pe_oi_change`
- [x] Classify OI action:
  - `ce_oi_change > 0 && price_up` → `long_build_up`
  - `ce_oi_change > 0 && price_down` → `short_build_up`
  - `ce_oi_change < 0 && price_up` → `short_covering`
  - `ce_oi_change < 0 && price_down` → `long_unwinding`
  - Same for PE with inverted logic
- [x] Aggregate: total CE OI change, total PE OI change, net OI change

### 3. Add VolumeChangeCalculator
- [x] Create `app/services/calculations/volume_change_calculator.rb`
- [x] Per-strike volume vs 20-day average for same time of day
- [x] `relative_volume = current_volume / avg_volume_20d`
- [x] Volume trend: rising/falling/flat over last 5 snapshots
- [x] Flag unusual volume: > 3x average

### 4. Create IVRankCalculator
- [x] Create `app/services/calculations/iv_rank_calculator.rb`
- [x] IV Rank = `(current_iv - iv_52w_low) / (iv_52w_high - iv_52w_low) * 100`
- [x] Source: historical IV from `option_chain_snapshots` (daily close IV)
- [x] Maintain 52-week high/low per strike/expiry in Redis
- [x] Update daily at market close
- [x] Handle new strikes (no history): use ATM IV as proxy

### 5. Implement IVPercentileCalculator
- [x] Create `app/services/calculations/iv_percentile_calculator.rb`
- [x] IV Percentile = % of days in 52 weeks where IV < current IV
- [x] More robust than IV Rank (less sensitive to outliers)
- [x] Calculate using `percentile_rank` from Statistics module
- [x] Cache percentile per strike/expiry (update daily)

### 6. Add SpreadCalculator
- [x] Create `app/services/calculations/spread_calculator.rb`
- [x] Bid-ask spread: `ask - bid`
- [x] Spread %: `spread / mid_price * 100`
- [x] Spread in ticks: `spread / tick_size`
- [x] Track: min/avg/max spread per strike over session
- [x] Flag illiquid: spread % > 0.5% or spread > 5 ticks

### 7. Create LiquidityScoreCalculator
- [x] Create `app/services/calculations/liquidity_score_calculator.rb`
- [x] Components (weighted):
  - Spread score (30%): inverse of spread %
  - Depth score (25%): bid+ask size at top 3 levels
  - Volume score (20%): relative volume
  - OI score (15%): total OI vs 20-day average
  - IV score (10%): IV in normal range (not too high/low)
- [x] Normalize each component 0-100, compute weighted sum
- [x] Output: `liquidity_score` (0-100), `liquidity_grade` (A-F)

### 8. Implement GammaChangeCalculator (dGamma/dTime)
- [x] Create `app/services/calculations/gamma_change_calculator.rb`
- [x] Gamma velocity: `gamma_now - gamma_previous` per 30s
- [x] Gamma acceleration: `velocity_now - velocity_previous`
- [x] Identify: gamma ramp (increasing), gamma decay (decreasing)
- [x] Critical for 0DTE and expiry day trading

### 9. Add GammaAccelerationCalculator (Second Derivative)
- [x] Create `app/services/calculations/gamma_acceleration_calculator.rb`
- [x] Second derivative of gamma wrt time
- [x] Formula: `acceleration = (gamma_t - 2*gamma_t-1 + gamma_t-2) / dt^2`
- [x] Positive acceleration = gamma expanding rapidly (high convexity)
- [x] Negative acceleration = gamma compressing
- [x] Use for: entry timing (avoid negative acceleration), exit signals

### 10. Create ThetaDecayEstimator
- [x] Create `app/services/calculations/theta_decay_estimator.rb`
- [x] Expected theta decay until target exit time
- [x] `estimated_decay = theta * hours_to_exit * 3600`
- [x] Compare to expected move: `ATR * sqrt(hours_to_exit / 24)`
- [x] Ratio: `decay / expected_move` - if > 1, theta risk high
- [x] Output: `theta_risk_score` (0-100), `recommended_max_hold_hours`

### 11. Implement OIClassification
- [x] Create `app/services/calculations/oi_classification.rb`
- [x] Combine CE and PE OI changes with price action
- [x] Classifications:
  - `Long Build-up`: CE OI↑ + PE OI↓ + price↑
  - `Short Build-up`: CE OI↑ + PE OI↓ + price↓
  - `Long Unwinding`: CE OI↓ + PE OI↑ + price↓
  - `Short Covering`: CE OI↓ + PE OI↑ + price↑
  - `Neutral`: mixed or flat OI
- [x] Confidence score based on magnitude of changes

### 12. Add OptionFlowScore
- [x] Create `app/services/calculations/option_flow_score.rb`
- [x] Composite score combining:
  - OI flow direction (bullish/bearish/neutral)
  - Volume confirmation (high volume = high conviction)
  - IV trend (rising IV = uncertainty, falling = confidence)
  - Gamma profile (positive gamma = supportive for buyers)
- [x] Output: `flow_score` (-100 to +100), `flow_label`
- [x] Used by Option Intelligence Engine

### 13. Create OptionChainRepository
- [x] Create `app/services/repositories/option_chain_repository.rb`
- [x] Methods:
  - `latest_snapshot(underlying, expiry)` - full chain
  - `strike_range(underlying, expiry, from:, to:)`
  - `atm_strikes(underlying, expiry, count: 5)`
  - `greeks_at(underlying, expiry, strike, option_type)`
  - `iv_rank_at(underlying, expiry, strike, option_type)`
  - `liquidity_score_at(underlying, expiry, strike)`
  - `flow_score_at(underlying, expiry, strike)`
  - `history(underlying, expiry, strike, from:, to:)`
- [x] Optimize with composite indexes
- [x] Cache latest snapshot in Redis (TTL: 30s)

### 14. Write Tests for Option Analytics
- [x] Create `spec/services/calculations/option_analytics_spec.rb`
- [x] Test cases:
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
- [x] All 10 calculators produce mathematically correct results
- [x] OptionChainRepository queries execute in < 10ms
- [x] IV rank/percentile update daily and handle new strikes
- [x] OI classification matches manual analysis on historical data
- [x] Liquidity score correlates with actual fill rates
- [x] Gamma acceleration detects expiry-day gamma ramp
- [x] Theta decay estimator warns on high time-risk trades
- [x] Option flow score provides actionable directional bias
- [x] All tests pass with property-based verification

---

## Notes
- Greeks from DhanHQ may have different conventions; verify Delta sign (call +, put -)
- IV Rank needs 52 weeks of data; bootstrap with 30 days initially
- Liquidity score weights should be configurable via AppConfig
- Option chain snapshots every 30s → 1,440 snapshots/day per expiry
- Consider partitioning `option_chain_snapshots` by expiry date
- Cache aggressively: latest snapshot, ATM strikes, IV ranks