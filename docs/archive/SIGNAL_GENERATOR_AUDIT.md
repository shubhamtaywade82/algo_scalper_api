# Signal Generator Audit & Rewrite Plan

## Executive Summary

**Current State**: Signal generator uses basic Supertrend + ADX logic with minimal confirmation. Missing critical components for production-grade directional trading.

**Required State**: Multi-factor directional confirmation with momentum validation, volatility health checks, and SMC structure alignment.

---

## Current Implementation Analysis

### ✅ What Works

1. **No-Trade Engine** - Excellent filtering of bad conditions (Phase 1 & Phase 2)
2. **Structure Detection** - Basic BOS/OB/FVG detection exists
3. **ADX Filtering** - Index-specific thresholds implemented
4. **Multi-Timeframe Support** - Primary + confirmation timeframe logic
5. **Trend Scorer** - Comprehensive scoring system (PA/IND/MTF)

### ❌ Critical Gaps

#### 1. Direction Logic Too Simple

**Current**: `decide_direction()` only checks:
- Supertrend trend (bullish/bearish)
- ADX threshold (min_strength)

**Missing**:
- ❌ HTF Supertrend confirmation (15m/30m)
- ❌ VWAP position bias check
- ❌ BOS direction alignment (not just presence)
- ❌ SMC CHOCH (Change of Character) detection
- ❌ 5m candle structure confirmation

**Impact**: Signals fire without proper directional confluence.

---

#### 2. No Momentum Confirmation

**Current**: No explicit momentum checks before entry.

**Missing**:
- ❌ LTP > last swing high/low check
- ❌ Candle body expansion detection
- ❌ Volume expansion (if available)
- ❌ Option premium speed (ΔLTP > threshold)

**Impact**: Entries occur during momentum exhaustion, not momentum initiation.

---

#### 3. Volatility Health Checks Incomplete

**Current**: Basic ATR downtrend check exists.

**Missing**:
- ❌ ATR ratio check (current/historical > 0.65)
- ❌ Inside compression detection (not just downtrend)
- ❌ Lunchtime chop filter (exists but not comprehensive)

**Impact**: Entries during volatility collapse lead to whipsaws.

---

#### 4. Structure Confirmation Missing

**Current**: BOS presence check only (no direction alignment).

**Missing**:
- ❌ BOS direction must align with trade direction
- ❌ SMC CHOCH detection (Change of Character)
- ❌ Structure break confirmation (60%+ alignment requirement)

**Impact**: Entries against structure breaks cause false signals.

---

#### 5. No HTF Trend Confirmation

**Current**: Only primary timeframe (5m) + optional confirmation (15m).

**Missing**:
- ❌ HTF Supertrend check (15m/30m) as directional filter
- ❌ HTF ADX strength requirement
- ❌ HTF structure alignment

**Impact**: Counter-trend entries during HTF reversals.

---

## Required Implementation

### Phase 1: Enhanced Direction Logic

**File**: `app/services/signal/direction_validator.rb` (NEW)

**Requirements**:
1. **Multi-Factor Direction Check** (at least 2 must agree):
   - HTF Supertrend (15m/30m) direction
   - ADX > 15 or 20 (index-specific)
   - VWAP position (above/below for bullish/bearish)
   - BOS direction alignment
   - SMC CHOCH alignment
   - 5m candle structure (higher highs/lower lows)

2. **Direction Scoring**:
   - Each factor = +1 point
   - Minimum 2 points required for direction
   - Score 4+ = strong direction
   - Score 2-3 = moderate direction (proceed with caution)

---

### Phase 2: Momentum Confirmation

**File**: `app/services/signal/momentum_validator.rb` (NEW)

**Requirements**:
1. **Momentum Checks** (at least 1 must confirm):
   - LTP > last swing high (bullish) or LTP < last swing low (bearish)
   - Candle body expansion (last candle body > previous 3 avg)
   - Volume expansion (if available, last candle volume > 1.2x avg)
   - Option premium speed (ΔLTP > threshold, e.g., 0.5% in 1m)

2. **Momentum Scoring**:
   - Each check = +1 point
   - Minimum 1 point required
   - Score 2+ = strong momentum

---

### Phase 3: Volatility Health

**File**: `app/services/signal/volatility_validator.rb` (NEW)

**Requirements**:
1. **Volatility Checks** (all must pass):
   - ATR ratio > 0.65 (current ATR / historical ATR)
   - Not inside compression (ATR not declining for 3+ bars)
   - Not inside lunchtime chop (11:20-13:30 with weak ADX)

2. **Volatility Scoring**:
   - ATR ratio > 0.65 = pass
   - ATR ratio 0.5-0.65 = warning (proceed with caution)
   - ATR ratio < 0.5 = reject

---

### Phase 4: SMC Structure Enhancement

**File**: `app/services/entries/structure_detector.rb` (ENHANCE)

**New Methods**:
1. `bos_direction(bars, lookback_minutes:)` - Returns :bullish, :bearish, or :neutral
2. `choch?(bars, lookback_minutes:)` - Detects Change of Character
3. `structure_alignment?(bars, direction:, min_alignment: 0.6)` - Checks if structure aligns with direction

**CHOCH Detection**:
- Bullish CHOCH: Price breaks above previous swing high AND closes above it
- Bearish CHOCH: Price breaks below previous swing low AND closes below it
- Must have confirmation candle (next candle maintains direction)

---

### Phase 5: Integration

**File**: `app/services/signal/engine.rb` (MODIFY)

**Changes**:
1. Replace `decide_direction()` with `DirectionValidator.validate()`
2. Add `MomentumValidator.validate()` before entry
3. Add `VolatilityValidator.validate()` before entry
4. Enhance `comprehensive_validation()` with new checks
5. Integrate SMC structure alignment checks

---

## Implementation Priority

### 🔴 CRITICAL (Must Have)

1. **Direction Logic Enhancement** - Without this, signals are unreliable
2. **Momentum Confirmation** - Prevents entries during exhaustion
3. **SMC CHOCH Detection** - Critical for structure alignment

### 🟡 HIGH (Should Have)

4. **HTF Supertrend Confirmation** - Reduces counter-trend entries
5. **VWAP Bias Check** - Improves directional accuracy
6. **Enhanced Volatility Checks** - Prevents volatility collapse entries

### 🟢 MEDIUM (Nice to Have)

7. **Option Premium Speed** - Advanced momentum confirmation
8. **Volume Expansion** - If volume data becomes available

---

## Success Criteria

### Minimum Viable Signal Generator

✅ **Direction**: At least 2 factors agree (HTF ST, ADX, VWAP, BOS, CHOCH, structure)
✅ **Momentum**: At least 1 confirmation (LTP > swing, body expansion, premium speed)
✅ **Volatility**: ATR ratio > 0.65, not in compression
✅ **Structure**: BOS direction aligns with trade direction, CHOCH detected
✅ **HTF**: Higher timeframe trend confirms direction

### Performance Targets

- **Signal Accuracy**: 40-50% directional correctness (minimum viable)
- **False Signal Reduction**: 30-40% reduction vs current
- **Entry Quality**: 70-80% of signals meet all criteria

---

## Testing Strategy

1. **Unit Tests**: Each validator class independently
2. **Integration Tests**: Full signal flow with mock data
3. **Backtest Validation**: Compare old vs new signal generator on historical data
4. **Paper Trading**: Monitor signal quality in live paper environment

---

## Migration Plan

1. **Phase 1**: Implement new validators alongside existing logic
2. **Phase 2**: Feature flag to enable/disable new logic
3. **Phase 3**: A/B test old vs new on paper trading
4. **Phase 4**: Gradual rollout (10% → 50% → 100%)
5. **Phase 5**: Remove old logic after validation

---

## Risk Management

- **Fail-Safe**: If new validators fail, fall back to existing logic
- **Logging**: Comprehensive logging for debugging
- **Monitoring**: Track signal quality metrics (accuracy, false signals)
- **Rollback**: Feature flag allows instant rollback if issues detected

---

## Next Steps

1. ✅ Create audit document (this file)
2. ⏳ Implement DirectionValidator
3. ⏳ Implement MomentumValidator
4. ⏳ Implement VolatilityValidator
5. ⏳ Enhance StructureDetector with CHOCH
6. ⏳ Integrate into Signal::Engine
7. ⏳ Add comprehensive tests
8. ⏳ Backtest validation
9. ⏳ Paper trading validation
10. ⏳ Production rollout
