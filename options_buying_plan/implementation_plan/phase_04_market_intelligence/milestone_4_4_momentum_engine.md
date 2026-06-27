# Milestone 4.4: Momentum Engine

**Phase:** 4 — Market Intelligence Engines  
**Goal:** Determine if price is accelerating or dying.  
**Estimated Tasks:** 10

---

## Tasks

### 1. Implement MomentumEngine
- [ ] Create `app/engines/momentum_engine.rb`
- [ ] Interface: `analyze(input) -> MomentumOutput`
- [ ] Input: `MomentumInput` with candles, indicators, volume
- [ ] Output: `MomentumOutput` with:
  - `momentum_state`: `:accelerating`, `:decelerating`, `:neutral`, `:diverging`
  - `momentum_score` (0-100)
  - `direction` (:bullish, :bearish, :neutral)
  - `persistence` (bars in current state)
  - `divergence_warning` (boolean)

### 2. Add ATRExpansionDetector
- [ ] Create `app/engines/detectors/atr_expansion_detector.rb`
- [ ] ATR rate of change: `(atr - atr_prev) / atr_prev`
- [ ] Expansion: ATR ROC > 10% over 3 periods
- [ ] Contraction: ATR ROC < -10%
- [ ] Compare to: 20-period ATR average
- [ ] Output: `atr_state`, `atr_roc`, `expansion_score`

### 3. Implement EMASlopeCalculator
- [ ] Create `app/engines/calculators/ema_slope_calculator.rb`
- [ ] Slope = (EMA_now - EMA_n_periods_ago) / n
- [ ] Periods: 5, 10, 20 (short, medium, long)
- [ ] Acceleration: slope_now - slope_prev
- [ ] Normalize by ATR: slope / ATR = slope in volatility units
- [ ] Output: `slopes`, `acceleration`, `normalized_slopes`, `trend_acceleration`

### 4. Create VWAPDistanceCalculator
- [ ] Create `app/engines/calculators/vwap_distance_calculator.rb`
- [ ] Distance = (price - VWAP) / ATR
- [ ] Mean reversion: distance > 2 ATR = extended
- [ ] Trend continuation: distance 0-1 ATR in trend direction
- [ ] VWAP slope alignment with price
- [ ] Output: `distance_atr`, `reversion_probability`, `trend_alignment`

### 5. Add ROCCalculator
- [ ] Create `app/engines/calculators/roc_calculator.rb`
- [ ] Rate of Change: `(close - close_n) / close_n * 100`
- [ ] Periods: 9 (short), 21 (medium)
- [ ] ROC acceleration: ROC_now - ROC_prev
- [ ] Compare to historical ROC distribution
- [ ] Output: `roc_values`, `roc_acceleration`, `percentile`

### 6. Implement VolumeAccelerationDetector
- [ ] Create `app/engines/detectors/volume_acceleration_detector.rb`
- [ ] Volume ROC: `(volume - volume_avg_n) / volume_avg_n`
- [ ] Volume trend: Volume trend: rising/falling/flat (5-period slope)
- [ ] Volume-price confirmation:
    - Price up + volume up = confirmation
    - Price up + volume down = divergence
- [ ] Output: `volume_state`, `volume_roc`, `confirmation`, `divergence`

### 7. Create MomentumScoreCalculator
- [ ] Create `app/engines/calculators/momentum_score_calculator.rb`
- [ ] Components (weighted):
  - ATR expansion: 20%
  - EMA slope acceleration: 25%
  - VWAP distance context: 15%
  - ROC momentum: 20%
  - Volume confirmation: 20%
- [ ] Directional: separate bullish/bearish scores
- [ ] Output: `bullish_score`, `bearish_score`, `net_score`, `state`

### 8. Add MomentumDivergenceDetector
- [ ] Create `app/engines/detectors/momentum_divergence_detector.rb`
- [ ] Price HH + Momentum LH = bearish divergence
- [ ] Price LL + Momentum HL = bullish divergence
- [ ] Momentum proxies: RSI, MACD histogram, ROC
- [ ] Hidden divergence: price HL + momentum LL (trend continuation)
- [ ] Output: `divergence_detected`, `type`, `strength`, `bars_developing`

### 9. Implement Momentum Persistence Tracking
- [ ] Create `app/engines/trackers/momentum_persistence_tracker.rb`
- [ ] Track bars in accelerating/decelerating state
- [ ] Minimum persistence: 3 bars before signaling
- [ ] Decay: score reduces if state doesn't persist
- [ ] Output: `bars_in_state`, `state_stability`, `decay_factor`

### 10. Write Tests for Acceleration/Deceleration Scenarios
- [ ] Create `spec/engines/momentum_engine_spec.rb`
- [ ] Fixtures:
  - Strong acceleration: rising ATR, steep EMA slopes, volume confirming
  - Deceleration: flattening ATR, EMA slopes decreasing, volume drying
  - Divergence: price makes HH, RSI makes LH
  - Hidden divergence: price HL, RSI LL (continuation)
  - Neutral: mixed signals, low scores
- [ ] Test persistence tracking prevents premature signals
- [ ] Test divergence detector with varying strengths

---

## Acceptance Criteria
- [ ] Engine analyzes momentum in < 30ms
- [ ] All 6 detectors integrated and tested
- [ ] Momentum score distinguishes acceleration vs deceleration
- [ ] Divergence detector catches reversals 2-3 bars early
- [ ] Volume confirmation improves signal quality
- [ ] Persistence tracking filters noise
- [ ] Output feeds Trade Scoring Engine (10% weight)
- [ ] Momentum state stored for Learning Engine

---

## Notes
- Momentum engine runs on every 5m candle (1m for execution)
- ATR expansion leads price momentum (early signal)
- EMA slope acceleration = second derivative of price
- VWAP distance gives mean-reversion context
- Divergence is warning, not entry signal
- Combine with Market Structure for higher probability