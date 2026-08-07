# Milestone 4.3: Market Structure Engine

**Phase:** 4 — Market Intelligence Engines  
**Goal:** Detect HH, HL, LH, LL, BOS, CHOCH, liquidity sweeps, FVG, order blocks.  
**Estimated Tasks:** 14

---

## Tasks

### 1. Implement MarketStructureEngine
- [x] Create `app/engines/market_structure_engine.rb`
- [x] Interface: `analyze(input) -> StructureOutput`
- [x] Input: `StructureInput` with candles (multiple timeframes), swings
- [x] Output: `StructureOutput` with:
  - `swing_points` (highs/lows with timestamps)
  - `structure_elements` (HH, HL, LH, LL, BOS, CHOCH, FVG, OB)
  - `current_bias` (:bullish, :bearish, :neutral)
  - `key_levels` (support/resistance with strength)
  - `structure_score` (0-100)

### 2. Add SwingPointDetector
- [x] Create `app/engines/detectors/swing_point_detector.rb`
- [x] Fractal-based: 5-candle pattern (2 left, 2 right)
- [x] Configurable lookback: 5, 7, 10 candles
- [x] Filter: minimum swing size (ATR * 0.5)
- [x] Output: `SwingPoint` objects with `type` (:high/:low), `price`, `time`, `strength`

### 3. Implement HigherHighDetector
- [x] Create `app/engines/detectors/higher_high_detector.rb`
- [x] Compare current swing high to previous swing high
- [x] HH confirmed when price closes above previous swing high
- [x] Strength: (current_high - prev_high) / ATR
- [x] Output: `hh_detected`, `price`, `strength`, `confirmation_time`

### 4. Implement HigherLowDetector
- [x] Create `app/engines/detectors/higher_low_detector.rb`
- [x] Compare current swing low to previous swing low
- [x] HL confirmed when price closes above previous swing low
- [x] Strength: (prev_low - current_low) / ATR (positive = higher)
- [x] Output: `hl_detected`, `price`, `strength`, `confirmation_time`

### 5. Implement LowerHighDetector
- [x] Create `app/engines/detectors/lower_high_detector.rb`
- [x] Current swing high < previous swing high
- [x] LH confirmed on close below previous swing high
- [x] Strength: (prev_high - current_high) / ATR
- [x] Output: `lh_detected`, `price`, `strength`

### 6. Implement LowerLowDetector
- [x] Create `app/engines/detectors/lower_low_detector.rb`
- [x] Current swing low < previous swing low
- [x] LL confirmed on close below previous swing low
- [x] Strength: (current_low - prev_low) / ATR (negative = lower)
- [x] Output: `ll_detected`, `price`, `strength`

### 7. Create BreakOfStructureDetector (BOS)
- [x] Create `app/engines/detectors/bos_detector.rb`
- [x] Bullish BOS: price breaks above recent swing high in uptrend
- [x] Bearish BOS: price breaks below recent swing low in downtrend
- [x] Validation: close beyond level, not just wick
- [x] Volume confirmation: breakout volume > 1.5x average
- [x] Output: `bos_detected`, `direction`, `level`, `break_price`, `volume_confirm`

### 8. Create ChangeOfCharacterDetector (CHOCH)
- [x] Create `app/engines/detectors/choch_detector.rb`
- [x] Bullish CHOCH: in downtrend, price breaks above recent LH
- [x] Bearish CHOCH: in uptrend, price breaks below recent HL
- [x] CHOCH = potential trend reversal signal
- [x] Requires: prior trend established (min 3 swings)
- [x] Output: `choch_detected`, `direction`, `broken_level`, `prior_trend`

### 9. Implement LiquiditySweepDetector
- [x] Create `app/engines/detectors/liquidity_sweep_detector.rb`
- [x] Identify liquidity pools: equal highs/lows, swing highs/lows, session highs/lows
- [x] Sweep: price spikes beyond level then quickly reverses (within 1-3 candles)
- [x] Volume spike on sweep candle
- [x] Output: `sweep_detected`, `direction`, `level`, `sweep_depth`, `recovery_time`

### 10. Add FairValueGapDetector
- [x] Create `app/engines/detectors/fvg_detector.rb`
- [x] Bullish FVG: candle 1 low > candle 3 high (gap between 1 and 3)
- [x] Bearish FVG: candle 1 high < candle 3 low
- [x] FVG as support/resistance: price often returns to fill
- [x] Track: unfilled FVGs, filled FVGs, age
- [x] Output: `fvgs` array with `type`, `top`, `bottom`, `age`, `filled`

### 11. Implement OrderBlockDetector
- [x] Create `app/engines/detectors/order_block_detector.rb`
- [x] Bullish OB: last down candle before strong up move (engulfing)
- [x] Bearish OB: last up candle before strong down move
- [x] Strength: move distance / OB size
- [x] Mitigation: price returns to OB level
- [x] Output: `order_blocks` array with `type`, `top`, `bottom`, `strength`, `mitigated`

### 12. Add Multi-Timeframe Structure Aggregation
- [x] Create `app/engines/aggregators/structure_aggregator.rb`
- [x] Timeframes: 15m (primary), 5m (confirmation), 1m (execution)
- [x] Higher TF structure constrains lower TF
- [x] Align: 15m HH + 5m HH = strong bullish
- [x] Conflict: 15m HH + 5m LH = caution
- [x] Output: `aligned_structure`, `conflicts`, `dominant_bias`

### 13. Create StructureScoreCalculator
- [x] Create `app/engines/calculators/structure_score_calculator.rb`
- [x] Components:
  - Trend structure (HH/HL vs LH/LL): 30%
  - BOS/CHOCH signals: 25%
  - Liquidity sweeps (directional): 20%
  - FVG/Order block confluence: 15%
  - Multi-TF alignment: 10%
- [x] Score 0-100, bias direction
- [x] Output: `structure_score`, `bias`, `component_scores`

### 14. Write Tests with Hand-Constructed Swing Patterns
- [x] Create `spec/engines/market_structure_engine_spec.rb`
- [x] Test fixtures for each pattern:
  - Perfect uptrend: HH, HL, HH, HL sequence
  - Perfect downtrend: LH, LL, LH, LL sequence
  - BOS in uptrend: break of HH with volume
  - CHOCH: downtrend then break of LH
  - Liquidity sweep: spike above equal highs, immediate reversal
  - FVG formation and fill
  - Order block formation and mitigation
- [x] Test multi-TF aggregation with conflicting signals
- [x] Test scoring matches manual analysis

---

## Acceptance Criteria
- [x] Engine analyzes structure in < 50ms
- [x] All 8 structure elements detected correctly on fixtures
- [x] BOS/CHOCH require close confirmation (not wick)
- [x] Liquidity sweep detects sweep + recovery pattern
- [x] FVG and OB track age and mitigation status
- [x] Multi-TF aggregation produces coherent bias
- [x] Structure score correlates with subsequent price action
- [x] Output stored in `market_structures` table

---

## Notes
- Swing detection uses 5-candle fractal by default (configurable)
- Minimum swing size filter prevents noise (ATR * 0.5)
- BOS/CHOCH only valid in direction of existing trend
- Liquidity sweeps are high-probability reversal signals
- FVGs and OBs are institutional footprint markers
- Structure engine runs on every 5m candle close
- Key levels feed into Strike Selection and Risk engines