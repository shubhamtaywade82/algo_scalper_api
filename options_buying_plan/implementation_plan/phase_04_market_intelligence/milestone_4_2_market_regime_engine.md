# Milestone 4.2: Market Regime Engine

**Phase:** 4 — Market Intelligence Engines  
**Goal:** Classify market into trending, ranging, expanding, compressing, reversing.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Implement MarketRegimeEngine
- [ ] Create `app/engines/market_regime_engine.rb`
- [ ] Interface: `classify(input) -> RegimeOutput`
- [ ] Input: `RegimeInput` with candles (multiple timeframes), indicators, VIX
- [ ] Output: `RegimeOutput` with:
  - `regime_type`: `:trending_up`, `:trending_down`, `:ranging`, `:expanding`, `:compressing`, `:reversing`
  - `regime_score` (0-100) - confidence
  - `timeframe` (primary timeframe of classification)
  - `supporting_data` (indicators values)
  - `persistence` (bars in current regime)

### 2. Add ADXRegimeClassifier
- [ ] Create `app/engines/classifiers/adx_regime_classifier.rb`
- [ ] ADX > 25 = trending, ADX < 20 = ranging
- [ ] +DI > -DI = up, +DI < -DI = down
- [ ] ADX slope: rising = strengthening trend, falling = weakening
- [ ] Output: `trend_classification`, `adx_value`, `di_diff`, `strength`

### 3. Implement ATRRegimeClassifier
- [ ] Create `app/engines/classifiers/atr_regime_classifier.rb`
- [ ] ATR percentile (20-day): > 80 = expanding, < 20 = compressing
- [ ] ATR slope: rising = volatility expansion, falling = compression
- [ ] Compare current ATR to: 5-period, 20-period, 50-period averages
- [ ] Output: `volatility_regime`, `atr_percentile`, `atr_slope`, `expansion_score`

### 4. Create EMAAlignmentClassifier
- [ ] Create `app/engines/classifiers/ema_alignment_classifier.rb`
- [ ] Check EMA alignment: 9, 21, 50, 200
- [ ] Bullish: 9 > 21 > 50 > 200 (all aligned up)
- [ ] Bearish: 9 < 21 < 50 < 200 (all aligned down)
- [ ] Mixed: any other combination
- [ ] Slope of each EMA: rising/falling/flat
- [ ] Output: `alignment`, `ema_values`, `slopes`, `trend_direction`

### 5. Add VWAPRegimeClassifier
- [ ] Create `app/engines/classifiers/vwap_regime_classifier.rb`
- [ ] Price vs VWAP: above = bullish bias, below = bearish bias
- [ ] Distance from VWAP in ATR units
- [ ] VWAP slope: rising/falling/flat
- [ ] Mean reversion vs trend: price far from VWAP + high ADX = trend
- [ ] Output: `vwap_bias`, `distance_atr`, `vwap_slope`, `regime_hint`

### 6. Implement RangeDetector
- [ ] Create `app/engines/classifiers/range_detector.rb`
- [ ] Bollinger Band width percentile (20-day)
- [ ] BB width < 20th percentile = compressing/range-bound
- [ ] BB width > 80th percentile = expanding
- [ ] Range boundaries: recent highs/lows (20-period)
- [ ] Range quality: touches of boundaries, volume at boundaries
- [ ] Output: `range_type`, `bb_width_percentile`, `boundaries`, `quality_score`

### 7. Create ReversalDetector
- [ ] Create `app/engines/classifiers/reversal_detector.rb`
- [ ] Divergence patterns:
  - Price HH + RSI LH = bearish divergence
  - Price LL + RSI HL = bullish divergence
  - Price HH + MACD LH = bearish divergence
- [ ] Candlestick patterns: hammer, shooting star, engulfing, doji
- [ ] Volume confirmation: divergence + volume spike = higher confidence
- [ ] Output: `reversal_signal`, `divergence_type`, `confidence`, `target_zone`

### 8. Add Multi-Timeframe Regime Aggregation
- [ ] Create `app/engines/aggregators/regime_aggregator.rb`
- [ ] Timeframes: 30m (primary), 15m (confirmation), 5m (execution)
- [ ] Hierarchy: higher TF regime constrains lower TF
- [ ] Conflict resolution: 30m trending_up + 15m ranging = trending_up with caution
- [ ] Output: `primary_regime`, `confirmation_regime`, `execution_regime`, `alignment_score`

### 9. Implement RegimeScoreCalculator
- [ ] Create `app/engines/calculators/regime_score_calculator.rb`
- [ ] Component scores (0-100 each):
  - ADX trend strength
  - ATR expansion/compression
  - EMA alignment quality
  - VWAP distance consistency
  - Range/BB width context
  - Reversal signals (negative weight)
- [ ] Weighted sum with regime-specific weights
- [ ] Output: `total_score`, `component_scores`, `dominant_factors`

### 10. Create RegimeTransitionDetector
- [ ] Create `app/engines/detectors/regime_transition_detector.rb`
- [ ] Track regime history (last 50 bars per timeframe)
- [ ] Detect transitions: trending → ranging, ranging → trending, etc.
- [ ] Transition strength: based on indicator momentum
- [ ] Alert on transitions via EventBus: `regime.transition`
- [ ] Output: `transition_detected`, `from_regime`, `to_regime`, `strength`, `bars_since`

### 11. Add Regime Persistence Tracking
- [ ] Create `app/engines/trackers/regime_persistence_tracker.rb`
- [ ] Track bars in current regime per timeframe
- [ ] Minimum persistence: 5 bars (30m) before trusting regime
- [ ] Whipsaw protection: ignore regime changes < 3 bars
- [ ] Output: `bars_in_regime`, `regime_stability`, `whipsaw_count`

### 12. Write Tests for Each Regime Type
- [ ] Create `spec/engines/market_regime_engine_spec.rb`
- [ ] Fixtures for each regime:
  - Trending up: strong ADX, aligned EMAs, price > VWAP
  - Trending down: strong ADX, aligned EMAs down, price < VWAP
  - Ranging: low ADX, mixed EMAs, price near VWAP, narrow BB
  - Expanding: rising ATR, widening BB, increasing volume
  - Compressing: falling ATR, narrowing BB, decreasing volume
  - Reversing: divergences, candle patterns, volume spikes
- [ ] Test multi-timeframe aggregation logic
- [ ] Test transition detection with known sequences
- [ ] Test persistence/whipsaw filtering

---

## Acceptance Criteria
- [ ] Engine classifies regime in < 30ms
- [ ] All 6 regime types detected accurately on test fixtures
- [ ] Multi-timeframe aggregation resolves conflicts correctly
- [ ] Regime score reflects confidence (high score = high confidence)
- [ ] Transition detector catches regime changes within 2-3 bars
- [ ] Persistence tracking prevents whipsaw signals
- [ ] Output feeds into Trade Scoring Engine (20% weight)
- [ ] Regime stored in `market_regimes` table for learning

---

## Notes
- Regime engine runs on every new 5m candle (or 1m for execution TF)
- Primary timeframe: 30m for regime, 15m for confirmation, 5m for execution
- ADX period 14, ATR period 14, EMA periods 9/21/50/200
- Store regime in DB for Learning Engine analysis
- Reversal detector is early warning; not used for entry directly
- Consider adding `regime_forecast` (probability of regime continuation)