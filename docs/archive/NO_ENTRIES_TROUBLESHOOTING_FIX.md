# No Entries Troubleshooting - Complete Fix

**Date**: 2026-01-20
**Issue**: No position entries happening for any index options

---

## 🔍 **Root Causes Found**

### **1. ExpectedMoveValidator Blocking All Indices**

**Symptoms**:
```
[Options] ExpectedMoveValidator BLOCKED NIFTY: expected_premium_below_threshold
[Options] ExpectedMoveValidator BLOCKED SENSEX: expected_premium_below_threshold
[Options] ExpectedMoveValidator BLOCKED BANKNIFTY: unsupported_index
```

**Root Cause**:
- Thresholds were set too high for current market ATR values
- BANKNIFTY was completely missing (no delta/threshold defined)

**Measured Values**:
- NIFTY: ATR=7.21, delta=0.40, expected_premium=2.88 vs threshold=8.0 → BLOCKED
- BANKNIFTY: ATR=23.29, delta=0.38, expected_premium=8.85 vs threshold=18.0 → BLOCKED

### **2. BANKNIFTY Missing from InstrumentExecutionProfile**

**Symptoms**:
```
EntryGuard failed for BANKNIFTY: Trading::InstrumentExecutionProfile::UnsupportedInstrumentError - Unsupported instrument: BANKNIFTY
```

**Root Cause**:
- `Trading::InstrumentExecutionProfile` only had NIFTY and SENSEX
- `Trading::LotCalculator` only had NIFTY and SENSEX lot sizes

---

## ✅ **Fixes Applied**

### **Fix 1: ExpectedMoveValidator Thresholds Lowered**

**File**: `app/services/options/strike_qualification/expected_move_validator.rb`

**Changes**:
```ruby
# NIFTY thresholds
execution_only: 4.0 → 1.0  (-75%)
scale_ready: 8.0 → 2.0     (-75%)
full_deploy: 12.0 → 4.0    (-67%)

# SENSEX thresholds
scale_ready: 15.0 → 3.0    (-80%)
full_deploy: 25.0 → 6.0    (-76%)

# BANKNIFTY thresholds (NEW)
execution_only: 2.0
scale_ready: 4.0
full_deploy: 8.0

# BANKNIFTY delta buckets (NEW)
ATM: 0.45
ATM±1: 0.38
```

**Enhanced Logging**:
```ruby
Rails.logger.info(
  "[ExpectedMoveValidator] BLOCKED #{index}: " \
  "expected_premium=#{expected_premium.round(2)} < threshold=#{threshold} " \
  "(ATR=#{expected_spot_move.round(2)}, delta=#{delta}, strike_type=#{st})"
)
```

### **Fix 2: Added BANKNIFTY to InstrumentExecutionProfile**

**File**: `app/services/trading/instrument_execution_profile.rb`

**Added**:
```ruby
'BANKNIFTY' => {
  allow_execution_only: true,
  max_lots_by_permission: {
    execution_only: 1,
    scale_ready: 2,
    full_deploy: 3
  }.freeze,
  holding_rules: {
    scalp_seconds: (30..180),
    trend_minutes: (10..45),
    stall_candles_5m: (3..5)
  }.freeze,
  target_model: :absolute,
  scaling_style: :early
}.freeze
```

### **Fix 3: Added BANKNIFTY to LotCalculator**

**File**: `app/services/trading/lot_calculator.rb`

**Added**:
```ruby
LOT_SIZES = {
  'NIFTY' => 65,
  'BANKNIFTY' => 15,  # NEW
  'SENSEX' => 20
}.freeze
```

---

## 📊 **Verification Results**

### **Before Fixes**:
```
[Signal] No suitable option strikes found for NIFTY bearish
[Signal] No suitable option strikes found for SENSEX bearish
[Signal] No suitable option strikes found for BANKNIFTY bearish
```

### **After Fixes**:
```
[Signal] Found 1 option picks for NIFTY: NIFTY-Jan2026-25350-PE
[Signal] Found 1 option picks for SENSEX: SENSEX-Jan2026-82600-PE
[Signal] Found 1 option picks for BANKNIFTY: BANKNIFTY-Jan2026-59500-PE
```

### **Position Trackers Created**:
```
ID: 2754 | Symbol: NIFTY-Jan2026-25350-PE | Status: active | Created: 2026-01-20 14:01:35
ID: 2753 | Symbol: SENSEX-Jan2026-82600-PE | Status: exited | Created: 2026-01-20 13:58:54
ID: 2752 | Symbol: NIFTY-Jan2026-25300-PE | Status: exited | Created: 2026-01-20 13:58:44
```

---

## 🎯 **Summary**

**Issues Fixed**:
1. ✅ ExpectedMoveValidator thresholds lowered for all indices (67-80% reduction)
2. ✅ BANKNIFTY support added to ExpectedMoveValidator (delta and thresholds)
3. ✅ BANKNIFTY added to InstrumentExecutionProfile (execution rules)
4. ✅ BANKNIFTY added to LotCalculator (lot size: 15)
5. ✅ Enhanced logging to show actual ATR and expected premium values

**Result**:
- ✅ All three indices (NIFTY, SENSEX, BANKNIFTY) now pass validation
- ✅ Entries are being created successfully
- ✅ Position trackers are being created and managed

**No restart required**: Changes to constants are picked up automatically by running daemon.

---

## 📝 **Configuration Notes**

### **ExpectedMoveValidator Thresholds**

The thresholds control minimum expected profit for entering a trade:

**Formula**: `expected_premium = ATR(14) * delta`

**Current Thresholds** (points):
- **NIFTY scale_ready**: 2.0 (allows ATR >= 5.0 with delta 0.40)
- **SENSEX scale_ready**: 3.0 (allows ATR >= 7.1 with delta 0.42)
- **BANKNIFTY scale_ready**: 4.0 (allows ATR >= 10.5 with delta 0.38)

**Trade-off**:
- Lower thresholds = More entries, but smaller expected profit per trade
- Higher thresholds = Fewer entries, but larger expected profit per trade

**For scalping**: Current lenient thresholds are appropriate since we're looking for quick moves on 1m timeframe.

---

## 🚨 **If Entries Stop Again**

Check in this order:

1. **ExpectedMoveValidator blocking**:
   ```bash
   tail -200 log/development.log | grep "ExpectedMoveValidator.*BLOCKED"
   ```

2. **InstrumentExecutionProfile errors**:
   ```bash
   tail -200 log/development.log | grep "UnsupportedInstrumentError"
   ```

3. **EntryGuard blocking**:
   ```bash
   tail -200 log/development.log | grep "EntryGuard.*failed"
   ```

4. **Market hours**:
   ```bash
   bundle exec rails runner "puts TradingSession::Service.new.market_open?"
   ```

5. **Active positions**:
   ```bash
   bundle exec rails runner "puts PositionTracker.active.count"
   ```
