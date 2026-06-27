# Milestone 5.3: Strike Selection Engine

**Phase:** 5 — Strategy & Decision Layer  
**Goal:** Score every strike and pick the optimal one.  
**Estimated Tasks:** 14

---

## Tasks

### 1. Implement StrikeSelectionEngine
- [ ] Create `app/engines/strike_selection_engine.rb`
- [ ] Interface: `select(input) -> StrikeSelectionOutput`
- [ ] Input: `StrikeSelectionInput` with:
  - `underlying_price`, `expiry`, `direction` (:long_call, :long_put)
  - `option_chain` (current snapshot)
  - `market_context`, `regime`, `structure`, `option_intelligence`
  - `account_state` (capital, risk limits)
- [ ] Output: `StrikeSelectionOutput` with:
  - `selected_strike` (strike price, option_type)
  - `alternative_strikes` (ranked array)
  - `strike_scores` (hash strike -> score)
  - `selection_reasoning` (text for AI Gateway)
  - `fallback_used` (boolean)

### 2. Create StrikeScorer
- [ ] Create `app/engines/scorers/strike_scorer.rb`
- [ ] Evaluates strikes from ATM-3 to ATM+3 (configurable range)
- [ ] For each strike, computes all component scores
- [ ] Returns `StrikeScore` with component breakdown
- [ ] Handles both CE and PE based on direction

### 3. Add DeltaScorer
- [ ] Create `app/engines/scorers/delta_scorer.rb`
- [ ] Ideal delta range for buying: 0.40 - 0.65 (configurable)
- [ ] Scoring:
  - 0.40-0.65: 100
  - 0.30-0.40: 80 (slightly OTM, cheaper)
  - 0.65-0.75: 70 (ITM, more expensive)
  - 0.20-0.30: 50
  - Outside: linear decay to 0
- [ ] Direction alignment: call delta > 0 for long, put delta < 0 for long
- [ ] Output: `score`, `delta`, `in_ideal_range`

### 4. Add LiquidityScorer
- [ ] Create `app/engines/scorers/liquidity_scorer.rb`
- [ ] Uses LiquidityEngine output per strike
- [ ] Components:
  - Spread score (tight = high)
  - Depth score (top 5 levels)
  - Volume score (relative to avg)
  - OI score (relative to avg)
- [ ] Weighted composite (configurable weights)
- [ ] Threshold: score < 50 = reject strike
- [ ] Output: `score`, `components`, `tradable`

### 5. Add GammaScorer
- [ ] Create `app/engines/scorers/gamma_scorer.rb`
- [ ] Gamma responsiveness scoring:
  - Moderate gamma (0.005-0.015): 100
  - High gamma (>0.015): 80 (responsive but risky near expiry)
  - Low gamma (<0.005): 40 (slow delta change)
- [ ] Gamma velocity bonus: positive velocity +10
- [ ] Expiry adjustment: 0DTE gamma spike penalty
- [ ] Output: `score`, `gamma`, `velocity`, `expiry_factor`

### 6. Add OIScorer
- [ ] Create `app/engines/scorers/oi_scorer.rb`
- [ ] Institutional interest proxy:
  - High OI + rising = 100
  - High OI + falling = 60 (unwinding)
  - Low OI + rising = 70 (building)
  - Low OI + falling = 30
- [ ] OI concentration: % of total OI at this strike
- [ ] Output: `score`, `oi`, `oi_change`, `concentration`

### 7. Add IVScorer
- [ ] Create `app/engines/scorers/iv_scorer.rb`
- [ ] Favorable IV conditions for buyers:
  - IV Rank < 40: 100 (cheap volatility)
  - IV Rank 40-60: 70
  - IV Rank 60-80: 40
  - IV Rank > 80: 10 (expensive)
- [ ] IV Trend bonus: falling IV +10, rising IV -10
- [ ] IV vs HV: IV < HV = favorable
- [ ] Output: `score`, `iv_rank`, `iv_percentile`, `trend`, `iv_hv_ratio`

### 8. Add VolumeScorer
- [ ] Create `app/engines/scorers/volume_scorer.rb`
- [ ] Activity confirmation:
  - Volume > 2x avg: 100
  - Volume 1-2x avg: 70
  - Volume 0.5-1x avg: 40
  - Volume < 0.5x avg: 10
- [ ] Volume trend: rising volume on price move = confirmation
- [ ] Output: `score`, `volume`, `relative_volume`, `trend`

### 9. Add ThetaScorer
- [ ] Create `app/engines/scorers/theta_scorer.rb`
- [ ] Time decay risk for expected hold time:
  - Theta/Expected_Move < 0.3: 100
  - 0.3-0.5: 70
  - 0.5-0.8: 40
  - > 0.8: 10
- [ ] Days to expiry factor: < 3 days = penalty
- [ ] Output: `score`, `theta`, `expected_move`, `ratio`, `dte`

### 10. Implement SpreadScorer
- [ ] Create `app/engines/scorers/spread_scorer.rb`
- [ ] Execution cost scoring:
  - Spread < 0.2%: 100
  - 0.2-0.5%: 70
  - 0.5-1.0%: 40
  - > 1.0%: 10
- [ ] Spread in ticks: < 3 ticks = 100, 3-5 = 70, > 5 = 30
- [ ] Output: `score`, `spread_pct`, `spread_ticks`, `vs_avg`

### 11. Create Composite StrikeQualityScore
- [ ] Create `app/engines/calculators/strike_quality_calculator.rb`
- [ ] Weights (configurable):
  - Delta: 20%
  - Liquidity: 25%
  - Gamma: 15%
  - OI: 10%
  - IV: 15%
  - Volume: 10%
  - Theta: 5%
  - Spread: optional (gate)
- [ ] Normalize each 0-100, weighted sum
- [ ] Penalty: any component < 30 reduces total by 20%
- [ ] Output: `total_score`, `component_scores`, `penalties`

### 12. Add StrikeSelector
- [ ] Create `app/engines/selectors/strike_selector.rb`
- [ ] Select highest scoring strike
- [ ] Tie-breaker: prefer ATM (lower absolute strike distance)
- [ ] Fallback logic:
  1. Try ATM ± 1
  2. Try ATM ± 2
  3. Try ATM ± 3
  4. If none tradable, return `:no_strike_available`
- [ ] Validate: selected strike passes LiquidityEngine tradable check
- [ ] Output: `selected`, `alternatives`, `fallback_used`

### 13. Implement Fallback Logic
- [ ] Create `app/engines/fallback/strike_fallback.rb`
- [ ] Scenarios:
  - Ideal strike illiquid → try adjacent strikes
  - All strikes illiquid → return `:no_trade`
  - IV too high on all → return `:no_trade`
  - Expiry today (0DTE) → prefer ATM ± 1 with high gamma
- [ ] Log fallback reason for AI Gateway analysis
- [ ] Metrics: fallback rate, fallback strike performance

### 14. Write Tests with Real Option Chain Snapshots
- [ ] Create `spec/engines/strike_selection_engine_spec.rb`
- [ ] Fixtures: real option chain snapshots (saved from paper trading)
- [ ] Test cases:
  - Normal day: ATM strike scores highest
  - High IV day: OTM strike preferred (cheaper vega)
  - Expiry day: ATM ± 1 with high gamma
  - Illiquid ATM: fallback to ATM+1
  - Direction alignment: CE for long, PE for short
  - Score breakdown matches manual calculation
- [ ] Property tests: scores always 0-100, fallback never crashes

---

## Acceptance Criteria
- [ ] Engine selects strike in < 20ms
- [ ] All 8 scorers integrated and tested
- [ ] Composite score weights configurable
- [ ] Fallback logic handles all illiquid scenarios
- [ ] Selected strike passes liquidity gate
- [ ] Score breakdown available for AI Gateway
- [ ] Output feeds Trade Scoring Engine (5% weight)
- [ ] Tests pass with real market data fixtures

---

## Notes
- Strike range: ATM ± 3 by default, configurable ± 5
- Score weights adjustable per strategy (e.g., scalpers weight gamma higher)
- Liquidity is hard gate: score < 50 = not tradable regardless of total
- 0DTE special handling: gamma/theta dominate, delta less important
- Strike selection runs after strategy signals direction
- Consider skew: sometimes PE strikes more liquid than CE