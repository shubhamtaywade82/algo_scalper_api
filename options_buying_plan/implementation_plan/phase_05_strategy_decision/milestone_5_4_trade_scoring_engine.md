# Milestone 5.4: Trade Scoring Engine

**Phase:** 5 — Strategy & Decision Layer  
**Goal:** Weighted composite score from all engines.  
**Estimated Tasks:** 10

---

## Tasks

### 1. Implement TradeScoringEngine
- [x] Create `app/services/options_buying/trade_scoring_engine.rb`
- [x] Interface: `score(input) -> TradeScoreOutput`
- [x] Input: `TradeScoreInput` with all engine outputs + strategy signal + strike selection
- [x] Output: `TradeScoreOutput` with:
  - `total_score` (0-100)
  - `component_scores` (hash)
  - `passed` (boolean, threshold check)
  - `threshold` (default 80)
  - `score_breakdown` (detailed for debugging)
  - `confidence_modifier` (data quality factor)

### 2. Create ScoreWeights Configuration
- [x] Create configuration hook via `Mode.config.dig(:scoring, :weights)`
- [x] Strategy can specify weight profile

### 3. Add ScoreAggregator
- [x] Aggregate component weights (Context, Momentum, Liquidity, Greeks)
- [x] Normalization of metrics to 0-100 scales
- [x] Apply weights: `sum(score * weight) / sum(weights)`

### 4. Implement ScoreThreshold
- [x] Enforce threshold check against `threshold` config (defaults to 80/100)

### 5. Create ScoreBreakdown
- [x] Structured breakdown hash detailing contribution of each scoring category

### 6. Add ScoreValidator
- [x] Validate inputs, fallback gracefully to neutral (50) on missing/nil indicators

### 7. Implement ScoreHistory
- [x] Persist score history events to `options_buying_signal_events` DB table

### 8. Add ScoreExplanation Generator
- [ ] Create `app/engines/explainers/score_explainer.rb`
- [ ] Generate human-readable explanation for AI Gateway
- [ ] Top 3 positive factors, top 3 negative factors
- [ ] Output: `explanation_text`, `key_factors`, `risk_warnings`

### 9. Create ScoreConfidence Modifier
- [ ] Create `app/engines/calculators/score_confidence_modifier.rb`
- [ ] Quality modifier based on tick lag and stale feeds

### 10. Write Tests Verifying Exact Math
- [x] Create `spec/services/options_buying/trade_scoring_engine_spec.rb`
- [x] Test cases with known inputs/outputs
- [x] Threshold validation at boundaries
- [x] Database persistence validation
- [x] Verify math with mocked outputse → decision

---

## Acceptance Criteria
- [ ] Engine scores trade in < 10ms
- [ ] Weighted aggregation mathematically correct
- [ ] Configurable weight profiles per strategy
- [ ] Threshold validation with strategy-specific values
- [ ] ScoreBreakdown provides full audit trail
- [ ] Confidence modifier adjusts for data quality
- [ ] Explanation generator produces readable output
- [ ] Score history tracks for learning
- [ ] All math tests pass with exact verification
- [ ] Output feeds RiskValidationEngine (gate) and AI Gateway (context)

---

## Notes
- This is the FINAL gate before RiskValidationEngine
- Score of 80+ with all gates passed = trade proceeds to risk
- Weights should be tuned via backtesting (Phase 8)
- Score components stored in `trade_scores` table for learning
- AI Gateway receives ScoreBreakdown for validation context
- Consider: minimum component scores (e.g., liquidity > 60 regardless of total)
- Threshold can be dynamic based on regime (higher in choppy markets)