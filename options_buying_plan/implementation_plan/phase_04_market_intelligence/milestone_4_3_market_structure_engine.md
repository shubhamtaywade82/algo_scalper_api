# Milestone 4.3: Market Structure Engine

**Phase:** 4 — Market Intelligence Engines  
**Goal:** Detect HH, HL, LH, LL, BOS, CHOCH, liquidity sweeps, FVG, order blocks.  
**Estimated Tasks:** 14

---

## Tasks

### 1. Implement MarketStructureEngine
- [ ] Create `app/engines/market_structure_engine.rb`
- [ ] Interface: `analyze(input) -> StructureOutput`
- [ ] Input: `StructureInput` with candles (multiple timeframes), swings
- [ ] Output: `StructureOutput` with:
  - `swing_points` (highs/lows with timestamps)
  - `structure_elements` (HH, HL, LH, LL, BOS, CHOCH, FVG, OB)
  - `current_bias` (:bullish, :bearish, :neutral)
  - `key_levels` (support/resistance with strength)
  - `structure_score` (0-100)

### 2. Add SwingPointDetector
- [ ] Create `app/engines/detectors/swing_point_detector.rb`
- [ ] Fractal-based: 5-candle pattern (2 left, 2 right)
- [ ] Configurable lookback: 5, 7, 10 candles
- [ ] Filter: minimum swing size (ATR * 0.5)
- [ ] Output: `SwingPoint` objects with `type` (:high/:low), `price`, `time`, `strength`

### 3. Implement HigherHighDetector
- [ ] Create `app/engines/detectors/higher_high_detector.rb`
- [ ] Compare current swing high to previous swing high
- [ ] HH confirmed when price closes above previous swing high
- [ ] Strength: (current_high - prev_high) / ATR
- [ ] Output: `hh_detected`, `price`, `strength`, `confirmation_time`

### 4. Implement HigherLowDetector
- [ ] Create `app/engines/detectors/higher_low_detector.rb`
- [ ] Compare current swing low to previous swing low
- [ ] HL confirmed when price closes above previous swing low
- [ ] Strength: (prev_low - current_low) / ATR (positive = higher)
- [ ] Output: `hl_detected`, `price`, `strength`, `confirmation_time`

### 5. Implement LowerHighDetector
- [ ] Create `app/engines/detectors/lower_high_detector.rb`
- [ ] Current swing high < previous swing high
- [ ] LH confirmed on close below previous swing high
- [ ] Strength: (prev_high - current_high) / ATR
- [ ] Output: `lh_detected`, `price`, `strength`

### 6. Implement LowerLowDetector
- [ ] Create `app/engines/detectors/lower_low_detector.rb`
- [ ] Current swing low < previous swing low
- [ ] LL confirmed on close below previous swing low
- [ ] Strength: (current_low - prev_low) / ATR (negative = lower)
- [ ] Output: `ll_detected`, `price`, `strength`

### 7. Create BreakOfStructureDetector (BOS)
- [ ] Create `app/engines/detectors/bos_detector.rb`
- [ ] Bullish BOS: price breaks above recent swing high in uptrend
- [ ] Bearish BOS: price breaks below recent swing low in downtrend
- [ ] Validation: close beyond level, not just wick
- [ ] Volume confirmation: breakout volume > 1.5x average
- [ ] Output: `bos_detected`, `direction`, `level`, `break_price`, `volume_confirm`

### 8. Create ChangeOfCharacterDetector (CHOCH)
- [ ] Create `app/engines/detectors/choch_detector.rb`
- [ ] Bullish CHOCH: in downtrend, price breaks above recent LH
- [ ] Bearish CHOCH: in uptrend, price breaks below recent HL
- [ ] CHOCH = potential trend reversal signal
- [ ] Requires: prior trend established (min 3 swings)
- [ ] Output: `choch_detected`, `direction`, `broken_level`, `prior_trend`

### 9. Implement LiquiditySweepDetector
- [ ] Create `app/engines/detectors/liquidity_sweep_detector.rb`
- [ ] Identify liquidity pools: equal highs/lows, swing highs/lows, session highs/lows
- [ ] Sweep: price spikes beyond level then quickly reverses (within 1-3 candles)
- [ ] Volume spike on sweep candle
- [ ] Output: `sweep_detected`, `direction`, `level`, `sweep_depth`, `recovery_time`

### 10. Add FairValueGapDetector
- [ ] Create `app/engines/detectors/fvg_detector.rb`
- [ ] Bullish FVG: candle 1 low > candle 3 high (gap between 1 and 3)
- [ ] Bearish FVG: candle 1 high < candle 3 low
- [ ] FVG as support/resistance: price often returns to fill
- [ ] Track: unfilled FVGs, filled FVGs, age
- [ ] Output: `fvgs` array with `type`, `top`, `bottom`, `age`, `filled`

### 11. Implement OrderBlockDetector
- [ ] Create `app/engines/detectors/order_block_detector.rb`
- [ ] Bullish OB: last down candle before strong up move (engulfing)
- [ ] Bearish OB: last up candle before strong down move
- [ ] Strength: move distance / OB size
- [ ] Mitigation: price returns to OB level
- [ ] Output: `order_blocks` array with `type`, `top`, `bottom`, `strength`, `mitigated`

### 12. Add Multi-Timeframe Structure Aggregation
- [ ] Create `app/engines/aggregators/structure_aggregator.rb`
- [ ] Timeframes: 15m (primary), 5m (confirmation), 1m (execution)
- [ ] Higher TF structure constrains lower TF
- [ ] Align: 15m HH + 5m HH = strong bullish
- [ ] Conflict: 15m HH + 5m LH = caution
- [ ] Output: `aligned_structure`, `conflicts`, `dominant_bias`

### 13. Create StructureScoreCalculator
- [ ] Create `app/engines/calculators/structure_score_calculator.rb`
- [ ] Components:
  - Trend structure (HH/HL vs LH/LL): 30%
  - BOS/CHOCH signals: 25%
  - Liquidity sweeps (directional): 20%
  - FVG/Order block confluence: 15%
  - Multi-TF alignment: 10%
- [ ] Score 0-100, bias direction
- [ ] Output: `structure_score`, `bias`, `component_scores`

### 14. Write Tests with Hand-Constructed Swing Patterns
- [ ] Create `spec/engines/market_structure_engine_spec.rb`
- [ ] Test fixtures for each pattern:
  - Perfect uptrend: HH, HL, HH, HL sequence
  - Perfect downtrend: LH, LL, LH, LL sequence
  - BOS in uptrend: break of HH with volume
  - CHOCH: downtrend then break of LH
  - Liquidity sweep: spike above equal highs, immediate reversal
  - FVG formation and fill
  - Order block formation and mitigation
- [ ] Test multi-TF aggregation with conflicting signals
- [ ] Test scoring matches manual analysis

---

## Acceptance Criteria
- [ ] Engine analyzes structure in < 50ms
- [ ] All 8 structure elements detected correctly on fixtures
- [ ] BOS/CHOCH require close confirmation (not wick)
- [ ] Liquidity sweep detects sweep + recovery pattern
- [ ] FVG and OB track age and mitigation status
- [ ] Multi-TF aggregation produces coherent bias
- [ ] Structure score correlates with subsequent price action
- [ ] Output stored in `market_structures` table

---

## Notes
- Swing detection uses 5-candle fractal by default (configurable)
- Minimum swing size filter prevents noise (ATR * 0.5)
- BOS/CHOCH only valid in direction of existing trend
- Liquidity sweeps are high-probability reversal signals
- FVGs and OBs are institutional footprint markers
- Structure engine runs on every 5m candle close
- Key levels feed into Strike Selection and Risk engines