# Milestone 5.4: Trade Scoring Engine

**Phase:** 5 — Strategy & Decision Layer  
**Goal:** Weighted composite score from all engines.  
**Estimated Tasks:** 10

---

## Tasks

### 1. Implement TradeScoringEngine
- [ ] Create `app/engines/trade_scoring_engine.rb`
- [ ] Interface: `score(input) -> TradeScoreOutput`
- [ ] Input: `TradeScoreInput` with all engine outputs + strategy signal + strike selection
- [ ] Output: `TradeScoreOutput` with:
  - `total_score` (0-100)
  - `component_scores` (hash)
  - `passed` (boolean, threshold check)
  - `threshold` (default 80)
  - `score_breakdown` (detailed for debugging)
  - `confidence_modifier` (data quality factor)

### 2. Create ScoreWeights Configuration
- [ ] Create `config/score_weights.yml`:
  ```yaml
  default:
    market_context: 10
    market_regime: 20
    market_structure: 20
    momentum: 10
    liquidity: 10
    option_flow: 15
    greeks: 10
    strike_quality: 5
  conservative:
    market_context: 15
    market_regime: 25
    market_structure: 20
    momentum: 5
    liquidity: 15
    option_flow: 10
    greeks: 5
    strike_quality: 5
  aggressive:
    market_context: 5
    market_regime: 15
    market_structure: 15
    momentum: 20
    liquidity: 5
    option_flow: 20
    greeks: 15
    strike_quality: 5
  ```
- [ ] Load via `AppConfig.score_weights`
- [ ] Strategy can specify weight profile

### 3. Add ScoreAggregator
- [ ] Create `app/engines/calculators/score_aggregator.rb`
- [ ] Normalize each engine output to 0-100:
  - Market Context: context_score (already 0-100)
  - Market Regime: regime_score (already 0-100)
  - Market Structure: structure_score (already 0-100)
  - Momentum: momentum_score (already 0-100)
  - Liquidity: liquidity_score (already 0-100)
  - Option Flow: option_intelligence.composite_score (0-100)
  - Greeks: weighted avg of delta/gamma/theta/vega feature scores
  - Strike Quality: strike_selection.composite_score (0-100)
- [ ] Apply weights: `sum(score * weight) / sum(weights)`
- [ ] Handle missing components (use default weight redistribution)

### 4. Implement ScoreThreshold
- [ ] Create `app/engines/validators/score_threshold_validator.rb`
- [ ] Default threshold: 80/100 (configurable per strategy)
- [ ] Threshold profiles:
  - `conservative`: 85
  - `default`: 80
  - `aggressive`: 70
  - `paper`: 75 (lower for validation)
- [ ] Dynamic adjustment: reduce threshold in high-opportunity regimes
- [ ] Output: `passed`, `threshold_used`, `margin_above_threshold`

### 5. Create ScoreBreakdown
- [ ] Create `app/engines/value_objects/score_breakdown.rb`
- [ ] Detailed breakdown for debugging and AI Gateway:
  ```ruby
  {
    market_context: { score: 85, weight: 10, weighted: 8.5, details: {...} },
    market_regime: { score: 90, weight: 20, weighted: 18.0, details: {...} },
    },
    },
    ...
    total: 87.5,
    passed: true,
    threshold: 80
  }
  ```
- [ ] Include: raw engine outputs, weight applied, contribution
- [ ] Serialization: `to_json` for logging

### 6. Add ScoreValidator
- [ ] Create `app/engines/validators/score_validator.rb`
- [ ] Validations:
  - All required engine outputs present
  - No stale data (> 5s old)
  - Scores within 0-100 range
  - Weights sum to 100
  - Threshold within 50-95 range
- [ ] On failure: return `Result.failure` with specific errors
- [ ] Log validation failures for monitoring

### 7. Implement ScoreHistory
- [ ] Create `app/engines/trackers/score_history_tracker.rb`
- [ ] Track last 100 scores per strategy
- [ ] Metrics: avg score, score distribution, pass rate
- [ ] Detect: score drift, threshold effectiveness
- [ ] Store in Redis (list, max 1000) and periodically flush to DB
- [ ] Used by LearningEngine for threshold optimization

### 8. Add ScoreExplanation Generator
- [ ] Create `app/engines/explainers/score_explainer.rb`
- [ ] Generate human-readable explanation for AI Gateway:
  - "Score 87/100: Strong regime (90) and structure (85) offset by moderate liquidity (65)"
  - Top 3 positive factors, top 3 negative factors
  - "Risk: IV rank elevated (75), consider smaller size"
- [ ] Template-based with ERB
- [ ] Output: `explanation_text`, `key_factors`, `risk_warnings`

### 9. Create ScoreConfidence Modifier
- [ ] Create `app/engines/calculators/score_confidence_modifier.rb`
- [ ] Data quality factors:
  - All engines fresh (< 2s): 1.0
  - One engine stale (2-5s): 0.95
  - Multiple stale: 0.85
  - Missing optional engine: 0.9
  - Low tick volume: 0.9
- [ ] Apply: `final_score = raw_score * confidence_modifier`
- [ ] Output: `modifier`, `raw_score`, `adjusted_score`, `quality_flags`

### 10. Write Tests Verifying Exact Math
- [ ] Create `spec/engines/trade_scoring_engine_spec.rb`
- [ ] Test cases with known inputs/outputs:
  - All engines perfect (100) → total 100
  - All engines 80 with default weights → total 80
  - One engine 0, others 100 → verify weight impact
  - Missing engine → weight redistribution correct
  - Confidence modifier applies correctly
  - Threshold validation at boundaries
- [ ] Property tests: score always 0-100, weights sum to 100
- [ ] Integration: full pipeline from engines → score → decision

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