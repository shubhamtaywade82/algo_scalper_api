# Milestone 4.2: Market Regime Engine

**Phase:** 4 — Market Intelligence Engines  
**Goal:** Classify market into trending, ranging, expanding, compressing, reversing.  
**Estimated Tasks:** 12

---

## Tasks

### 1. Implement MarketRegimeEngine
- [x] Create `app/engines/market_regime_engine.rb`
- [x] Interface: `classify(input) -> RegimeOutput`
- [x] Input: `RegimeInput` with candles (multiple timeframes), indicators, VIX
- [x] Output: `RegimeOutput` with:
  - `regime_type`: `:trending_up`, `:trending_down`, `:ranging`, `:expanding`, `:compressing`, `:reversing`
  - `regime_score` (0-100) - confidence
  - `timeframe` (primary timeframe of classification)
  - `supporting_data` (indicators values)
  - `persistence` (bars in current regime)

### 2. Add ADXRegimeClassifier
- [x] Create `app/engines/classifiers/adx_regime_classifier.rb`
- [x] ADX > 25 = trending, ADX < 20 = ranging
- [x] +DI > -DI = up, +DI < -DI = down
- [x] ADX slope: rising = strengthening trend, falling = weakening
- [x] Output: `trend_classification`, `adx_value`, `di_diff`, `strength`

### 3. Implement ATRRegimeClassifier
- [x] Create `app/engines/classifiers/atr_regime_classifier.rb`
- [x] ATR percentile (20-day): > 80 = expanding, < 20 = compressing
- [x] ATR slope: rising = volatility expansion, falling = compression
- [x] Compare current ATR to: 5-period, 20-period, 50-period averages
- [x] Output: `volatility_regime`, `atr_percentile`, `atr_slope`, `expansion_score`

### 4. Create EMAAlignmentClassifier
- [x] Create `app/engines/classifiers/ema_alignment_classifier.rb`
- [x] Check EMA alignment: 9, 21, 50, 200
- [x] Bullish: 9 > 21 > 50 > 200 (all aligned up)
- [x] Bearish: 9 < 21 < 50 < 200 (all aligned down)
- [x] Mixed: any other combination
- [x] Slope of each EMA: rising/falling/flat
- [x] Output: `alignment`, `ema_values`, `slopes`, `trend_direction`

### 5. Add VWAPRegimeClassifier
- [x] Create `app/engines/classifiers/vwap_regime_classifier.rb`
- [x] Price vs VWAP: above = bullish bias, below = bearish bias
- [x] Distance from VWAP in ATR units
- [x] VWAP slope: rising/falling/flat
- [x] Mean reversion vs trend: price far from VWAP + high ADX = trend
- [x] Output: `vwap_bias`, `distance_atr`, `vwap_slope`, `regime_hint`

### 6. Implement RangeDetector
- [x] Create `app/engines/classifiers/range_detector.rb`
- [x] Bollinger Band width percentile (20-day)
- [x] BB width < 20th percentile = compressing/range-bound
- [x] BB width > 80th percentile = expanding
- [x] Range boundaries: recent highs/lows (20-period)
- [x] Range quality: touches of boundaries, volume at boundaries
- [x] Output: `range_type`, `bb_width_percentile`, `boundaries`, `quality_score`

### 7. Create ReversalDetector
- [x] Create `app/engines/classifiers/reversal_detector.rb`
- [x] Divergence patterns:
  - Price HH + RSI LH = bearish divergence
  - Price LL + RSI HL = bullish divergence
  - Price HH + MACD LH = bearish divergence
- [x] Candlestick patterns: hammer, shooting star, engulfing, doji
- [x] Volume confirmation: divergence + volume spike = higher confidence
- [x] Output: `reversal_signal`, `divergence_type`, `confidence`, `target_zone`

### 8. Add Multi-Timeframe Regime Aggregation
- [x] Create `app/engines/aggregators/regime_aggregator.rb`
- [x] Timeframes: 30m (primary), 15m (confirmation), 5m (execution)
- [x] Hierarchy: higher TF regime constrains lower TF
- [x] Conflict resolution: 30m trending_up + 15m ranging = trending_up with caution
- [x] Output: `primary_regime`, `confirmation_regime`, `execution_regime`, `alignment_score`

### 9. Implement RegimeScoreCalculator
- [x] Create `app/engines/calculators/regime_score_calculator.rb`
- [x] Component scores (0-100 each):
  - ADX trend strength
  - ATR expansion/compression
  - EMA alignment quality
  - VWAP distance consistency
  - Range/BB width context
  - Reversal signals (negative weight)
- [x] Weighted sum with regime-specific weights
- [x] Output: `total_score`, `component_scores`, `dominant_factors`

### 10. Create RegimeTransitionDetector
- [x] Create `app/engines/detectors/regime_transition_detector.rb`
- [x] Track regime history (last 50 bars per timeframe)
- [x] Detect transitions: trending → ranging, ranging → trending, etc.
- [x] Transition strength: based on indicator momentum
- [x] Alert on transitions via EventBus: `regime.transition`
- [x] Output: `transition_detected`, `from_regime`, `to_regime`, `strength`, `bars_since`

### 11. Add Regime Persistence Tracking
- [x] Create `app/engines/trackers/regime_persistence_tracker.rb`
- [x] Track bars in current regime per timeframe
- [x] Minimum persistence: 5 bars (30m) before trusting regime
- [x] Whipsaw protection: ignore regime changes < 3 bars
- [x] Output: `bars_in_regime`, `regime_stability`, `whipsaw_count`

### 12. Write Tests for Each Regime Type
- [x] Create `spec/engines/market_regime_engine_spec.rb`
- [x] Fixtures for each regime:
  - Trending up: strong ADX, aligned EMAs, price > VWAP
  - Trending down: strong ADX, aligned EMAs down, price < VWAP
  - Ranging: low ADX, mixed EMAs, price near VWAP, narrow BB
  - Expanding: rising ATR, widening BB, increasing volume
  - Compressing: falling ATR, narrowing BB, decreasing volume
  - Reversing: divergences, candle patterns, volume spikes
- [x] Test multi-timeframe aggregation logic
- [x] Test transition detection with known sequences
- [x] Test persistence/whipsaw filtering

---

## Acceptance Criteria
- [x] Engine classifies regime in < 30ms
- [x] All 6 regime types detected accurately on test fixtures
- [x] Multi-timeframe aggregation resolves conflicts correctly
- [x] Regime score reflects confidence (high score = high confidence)
- [x] Transition detector catches regime changes within 2-3 bars
- [x] Persistence tracking prevents whipsaw signals
- [x] Output feeds into Trade Scoring Engine (20% weight)
- [x] Regime stored in `market_regimes` table for learning

---

## Notes
- Regime engine runs on every new 5m candle (or 1m for execution TF)
- Primary timeframe: 30m for regime, 15m for confirmation, 5m for execution
- ADX period 14, ATR period 14, EMA periods 9/21/50/200
- Store regime in DB for Learning Engine analysis
- Reversal detector is early warning; not used for entry directly
- Consider adding `regime_forecast` (probability of regime continuation)