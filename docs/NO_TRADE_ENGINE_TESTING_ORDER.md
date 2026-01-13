# No-Trade Engine Testing Order

**Recommended Testing Sequence** - Bottom-up approach from simplest to most complex

---

## Testing Strategy

Test in **dependency order** - start with isolated utilities, then build up to integration:

1. **Utility Classes** (Pure functions, no dependencies) ← **START HERE**
2. **Context Builder** (Depends on utilities)
3. **Core Engine** (Depends on context)
4. **Integration** (Depends on everything)

---

## Phase 1: Utility Classes (Start Here)

These are pure functions with no dependencies - easiest to test and verify.

### 1. RangeUtils ⭐ **RECOMMENDED START**
**File**: `app/services/entries/range_utils.rb`
**Test**: `spec/services/entries/range_utils_spec.rb`
**Status**: Has tests, but 1 failing test

**Why Start Here**:
- Simplest utility (just math calculations)
- Already has test file
- No dependencies on other services
- Easy to verify with manual calculations

**What to Test**:
- `range_pct()` - Calculate percentage range over candles
- `compressed?()` - Check if range is below threshold

**Fix First**: The failing `compressed?` test needs adjustment

---

### 2. StructureDetector
**File**: `app/services/entries/structure_detector.rb`
**Test**: `spec/services/entries/structure_detector_spec.rb`
**Status**: Has tests

**What to Test**:
- `bos?()` - Break of Structure detection
- `inside_opposite_ob?()` - Order Block detection
- `inside_fvg?()` - Fair Value Gap detection

---

### 3. VWAPUtils
**File**: `app/services/entries/vwap_utils.rb`
**Test**: `spec/services/entries/vwap_utils_spec.rb`
**Status**: Has tests

**What to Test**:
- `near_vwap?()` - Check if price is near VWAP (±0.1%)
- `trapped_between_vwap_avwap?()` - Check if price is trapped

---

### 4. ATRUtils
**File**: `app/services/entries/atr_utils.rb`
**Test**: Create `spec/services/entries/atr_utils_spec.rb`

**What to Test**:
- `atr_downtrend?()` - Check if ATR is decreasing (volatility compression)

---

### 5. CandleUtils
**File**: `app/services/entries/candle_utils.rb`
**Test**: `spec/services/entries/candle_utils_spec.rb`
**Status**: Has tests

**What to Test**:
- `avg_wick_ratio()` - Calculate average wick ratio
- Candle pattern detection

---

### 6. OptionChainWrapper
**File**: `app/services/entries/option_chain_wrapper.rb`
**Test**: `spec/services/entries/option_chain_wrapper_spec.rb`
**Status**: Has tests

**What to Test**:
- `atm_iv` - ATM implied volatility
- `ce_oi_rising?()` - CE OI trend
- `pe_oi_rising?()` - PE OI trend
- `spread_wide?()` - Spread detection

---

## Phase 2: Context Builder

### 7. NoTradeContextBuilder
**File**: `app/services/entries/no_trade_context_builder.rb`
**Test**: `spec/services/entries/no_trade_context_builder_spec.rb`
**Status**: Has tests

**What to Test**:
- `build()` - Builds context from market data
- All context fields populated correctly
- Uses utility classes correctly
- Handles missing data gracefully

**Dependencies**: All utility classes (test after Phase 1)

---

## Phase 3: Core Engine

### 8. NoTradeEngine
**File**: `app/services/entries/no_trade_engine.rb`
**Test**: `spec/services/entries/no_trade_engine_spec.rb`
**Status**: Has tests

**What to Test**:
- `validate()` - All 11 scoring conditions
- Score calculation (score < 3 = allowed, score ≥ 3 = blocked)
- Each condition triggers correctly
- Combined conditions work together
- Edge cases (score exactly 2, score exactly 3)

**Dependencies**: NoTradeContextBuilder (test after Phase 2)

---

## Phase 4: Integration

### 9. Signal::Engine Integration
**File**: `app/services/signal/engine.rb`
**Test**: `spec/services/signal/engine_no_trade_integration_spec.rb`
**Status**: Has tests

**What to Test**:
- **Phase 1**: `quick_no_trade_precheck()` - Fast pre-check before signal generation
- **Phase 2**: `validate_no_trade_conditions()` - Detailed validation after signal
- Data reuse between phases (no duplicate fetches)
- Integration with signal generation flow
- Logging and error handling

**Dependencies**: Everything (test after Phase 3)

---

## Recommended First Test: RangeUtils

### Why Start with RangeUtils?

1. ✅ **Simplest** - Just mathematical calculations
2. ✅ **No Dependencies** - Pure function, easy to test
3. ✅ **Already Has Tests** - Can fix and extend existing tests
4. ✅ **Quick Win** - Fix the failing test, then add more coverage
5. ✅ **Foundation** - Used by other components, so fixing it helps everything

### Quick Start

```bash
# Run existing tests
bundle exec rspec spec/services/entries/range_utils_spec.rb

# Fix the failing test
# Then add more test cases for edge cases
```

### Test Coverage Goals

- ✅ Normal range calculations
- ✅ Edge cases (nil, empty, single candle)
- ✅ Boundary conditions (exactly at threshold)
- ✅ Different candle patterns
- ✅ Large vs small ranges

---

## Testing Checklist

### Utility Classes
- [ ] RangeUtils - Fix failing test, add edge cases
- [ ] StructureDetector - Verify BOS/OB/FVG detection
- [ ] VWAPUtils - Verify VWAP calculations
- [ ] ATRUtils - Create tests if missing
- [ ] CandleUtils - Verify wick ratio calculations
- [ ] OptionChainWrapper - Verify option chain parsing

### Context Builder
- [ ] NoTradeContextBuilder - Verify context building
- [ ] All fields populated correctly
- [ ] Handles missing data

### Core Engine
- [ ] NoTradeEngine - All 11 conditions
- [ ] Score calculation
- [ ] Edge cases (score = 2, score = 3)

### Integration
- [ ] Phase 1 pre-check
- [ ] Phase 2 detailed validation
- [ ] Data reuse
- [ ] Error handling

---

## Next Steps

1. **Start with RangeUtils** - Fix failing test, verify all calculations
2. **Move to StructureDetector** - Verify market structure detection
3. **Continue up the chain** - Test each component before moving to next
4. **Integration last** - Test full flow after all components verified

---

## Running Tests

```bash
# Test single utility
bundle exec rspec spec/services/entries/range_utils_spec.rb

# Test all utilities
bundle exec rspec spec/services/entries/*_utils_spec.rb

# Test context builder
bundle exec rspec spec/services/entries/no_trade_context_builder_spec.rb

# Test core engine
bundle exec rspec spec/services/entries/no_trade_engine_spec.rb

# Test integration
bundle exec rspec spec/services/signal/engine_no_trade_integration_spec.rb

# Test everything
bundle exec rspec spec/services/entries/ spec/services/signal/engine_no_trade_integration_spec.rb
```

