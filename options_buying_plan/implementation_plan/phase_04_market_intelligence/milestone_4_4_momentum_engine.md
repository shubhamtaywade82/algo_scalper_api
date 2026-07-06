# Milestone 4.4: Momentum Engine

**Phase:** 4 — Market Intelligence Engines  
**Goal:** Determine if price is accelerating or dying.  
**Estimated Tasks:** 10

---

## Tasks

### 1. Implement MomentumEngine
- [x] Create `app/engines/momentum_engine.rb`
- [x] Interface: `analyze(input) -> MomentumOutput`
- [x] Input: `MomentumInput` with candles, indicators, volume
- [x] Output: `MomentumOutput` with:
  - `momentum_state`: `:accelerating`, `:decelerating`, `:neutral`, `:diverging`
  - `momentum_score` (0-100)
  - `direction` (:bullish, :bearish, :neutral)
  - `persistence` (bars in current state)
  - `divergence_warning` (boolean)

### 2. Add ATRExpansionDetector
- [x] Create `app/engines/detectors/atr_expansion_detector.rb`
- [x] ATR rate of change: `(atr - atr_prev) / atr_prev`
- [x] Expansion: ATR ROC > 10% over 3 periods
- [x] Contraction: ATR ROC < -10%
- [x] Compare to: 20-period ATR average
- [x] Output: `atr_state`, `atr_roc`, `expansion_score`

### 3. Implement EMASlopeCalculator
- [x] Create `app/engines/calculators/ema_slope_calculator.rb`
- [x] Slope = (EMA_now - EMA_n_periods_ago) / n
- [x] Periods: 5, 10, 20 (short, medium, long)
- [x] Acceleration: slope_now - slope_prev
- [x] Normalize by ATR: slope / ATR = slope in volatility units
- [x] Output: `slopes`, `acceleration`, `normalized_slopes`, `trend_acceleration`

### 4. Create VWAPDistanceCalculator
- [x] Create `app/engines/calculators/vwap_distance_calculator.rb`
- [x] Distance = (price - VWAP) / ATR
- [x] Mean reversion: distance > 2 ATR = extended
- [x] Trend continuation: distance 0-1 ATR in trend direction
- [x] VWAP slope alignment with price
- [x] Output: `distance_atr`, `reversion_probability`, `trend_alignment`

### 5. Add ROCCalculator
- [x] Create `app/engines/calculators/roc_calculator.rb`
- [x] Rate of Change: `(close - close_n) / close_n * 100`
- [x] Periods: 9 (short), 21 (medium)
- [x] ROC acceleration: ROC_now - ROC_prev
- [x] Compare to historical ROC distribution
- [x] Output: `roc_values`, `roc_acceleration`, `percentile`

### 6. Implement VolumeAccelerationDetector
- [x] Create `app/engines/detectors/volume_acceleration_detector.rb`
- [x] Volume ROC: `(volume - volume_avg_n) / volume_avg_n`
- [x] Volume trend: Volume trend: rising/falling/flat (5-period slope)
- [x] Volume-price confirmation:
    - Price up + volume up = confirmation
    - Price up + volume down = divergence
- [x] Output: `volume_state`, `volume_roc`, `confirmation`, `divergence`

### 7. Create MomentumScoreCalculator
- [x] Create `app/engines/calculators/momentum_score_calculator.rb`
- [x] Components (weighted):
  - ATR expansion: 20%
  - EMA slope acceleration: 25%
  - VWAP distance context: 15%
  - ROC momentum: 20%
  - Volume confirmation: 20%
- [x] Directional: separate bullish/bearish scores
- [x] Output: `bullish_score`, `bearish_score`, `net_score`, `state`

### 8. Add MomentumDivergenceDetector
- [x] Create `app/engines/detectors/momentum_divergence_detector.rb`
- [x] Price HH + Momentum LH = bearish divergence
- [x] Price LL + Momentum HL = bullish divergence
- [x] Momentum proxies: RSI, MACD histogram, ROC
- [x] Hidden divergence: price HL + momentum LL (trend continuation)
- [x] Output: `divergence_detected`, `type`, `strength`, `bars_developing`

### 9. Implement Momentum Persistence Tracking
- [x] Create `app/engines/trackers/momentum_persistence_tracker.rb`
- [x] Track bars in accelerating/decelerating state
- [x] Minimum persistence: 3 bars before signaling
- [x] Decay: score reduces if state doesn't persist
- [x] Output: `bars_in_state`, `state_stability`, `decay_factor`

### 10. Write Tests for Acceleration/Deceleration Scenarios
- [x] Create `spec/engines/momentum_engine_spec.rb`
- [x] Fixtures:
  - Strong acceleration: rising ATR, steep EMA slopes, volume confirming
  - Deceleration: flattening ATR, EMA slopes decreasing, volume drying
  - Divergence: price makes HH, RSI makes LH
  - Hidden divergence: price HL, RSI LL (continuation)
  - Neutral: mixed signals, low scores
- [x] Test persistence tracking prevents premature signals
- [x] Test divergence detector with varying strengths

---

## Acceptance Criteria
- [x] Engine analyzes momentum in < 30ms
- [x] All 6 detectors integrated and tested
- [x] Momentum score distinguishes acceleration vs deceleration
- [x] Divergence detector catches reversals 2-3 bars early
- [x] Volume confirmation improves signal quality
- [x] Persistence tracking filters noise
- [x] Output feeds Trade Scoring Engine (10% weight)
- [x] Momentum state stored for Learning Engine

---

## Notes
- Momentum engine runs on every 5m candle (1m for execution)
- ATR expansion leads price momentum (early signal)
- EMA slope acceleration = second derivative of price
- VWAP distance gives mean-reversion context
- Divergence is warning, not entry signal
- Combine with Market Structure for higher probability