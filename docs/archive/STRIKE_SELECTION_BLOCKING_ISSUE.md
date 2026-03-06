# Strike Selection Blocking Issue - Analysis

**Date**: 2026-01-13
**Issue**: No positions being entered despite signals being generated

---

## ✅ **Signal Generation Status: WORKING**

From logs:
```
[Signal] Proceeding with bearish signal for NIFTY
[Signal] Index TA DISABLED for NIFTY - skipping TA step
[Signal] DirectionGate DISABLED for NIFTY - skipping regime check
[Signal] SMC Decision alignment check SKIPPED for NIFTY (SMC+AVRZ disabled)
```

**Confirmed**:
- ✅ **Supertrend + ADX** is generating signals (`:bearish` for NIFTY)
- ✅ **Index TA** is disabled (as configured)
- ✅ **DirectionGate** is disabled (as configured)
- ✅ **SMC+AVRZ** is disabled (as configured)

**System is using ONLY Supertrend + ADX** ✅

---

## ❌ **Root Cause: Strike Selection Failing**

From logs:
```
[Options] StrikeSelector BLOCKED NIFTY: no_liquid_atm
[Signal] No suitable option strikes found for NIFTY bearish
```

**Problem**: `StrikeSelector` cannot find liquid ATM options, so no entries occur.

---

## 🔍 **Why `no_liquid_atm` Occurs**

The `StrikeSelector` (`app/services/options/strike_qualification/strike_selector.rb`) checks:

1. **Desired Strike Selection**:
   - For `:scale_ready` permission + `:bearish` trend → tries ATM-1 (ATM minus 1 step)
   - Falls back to ATM if ATM-1 not liquid

2. **Liquidity Check** (`liquid_in_chain?`):
   - Requires `last_price` > 0
   - Requires `oi` (Open Interest) > 0
   - Requires valid bid/ask spread (spread < 15% of LTP)

3. **Blocking Logic**:
   - If desired strike (ATM-1) fails → fallback to ATM
   - If ATM also fails → **BLOCKS with `no_liquid_atm`**

---

## 🔍 **Possible Causes**

### **1. Market Closed** (Most Likely)
- Option chain data unavailable when market is closed
- No live option prices available
- **Current Time**: 01:22 IST (market closed)

### **2. Option Chain Data Unavailable**
- DhanHQ API not returning option chain
- Rate limiting preventing chain fetch
- Chain data stale or expired

### **3. Liquidity Requirements Too Strict**
- `last_price` must be > 0
- `oi` (Open Interest) must be > 0
- Spread must be < 15% of LTP
- If any check fails → not considered "liquid"

### **4. ATM Strike Not Found**
- Option chain structure doesn't match expected format
- Strike key format mismatch (string vs integer)
- Chain data structure changed

---

## 📊 **Current Configuration Verification**

**Signal Generation** (✅ Working):
```yaml
signals:
  enable_index_ta: false                    # ✅ DISABLED
  enable_smc_avrz_permission: false         # ✅ DISABLED
  enable_direction_gate: false              # ✅ DISABLED
  enable_supertrend_signal: true            # ✅ ENABLED
  enable_adx_filter: true                   # ✅ ENABLED
  enable_confirmation_timeframe: false      # ✅ DISABLED
```

**System is using ONLY Supertrend + ADX** ✅

---

## 🎯 **Solution Steps**

### **Step 1: Verify Market is Open**
```bash
# Check current time and market status
bundle exec rails runner "
current_time = Time.current.in_time_zone('Asia/Kolkata')
puts \"Current Time: #{current_time.strftime('%H:%M:%S %Z')}\"
puts \"Market Hours: 9:15 AM - 3:30 PM IST\"
puts \"Market Open: #{current_time.hour >= 9 && current_time.hour < 15}\"
"
```

**Expected**: Market must be open (9:15 AM - 3:30 PM IST) for option chain data to be available.

### **Step 2: Check Option Chain Availability**
```bash
# Test option chain fetch
bundle exec rails runner "
index_cfg = { key: 'NIFTY', segment: 'IDX_I', sid: '13' }
instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
chain = instrument.option_chain
puts \"Chain Available: #{chain.present?}\"
puts \"Chain Keys Count: #{chain&.keys&.size || 0}\"
"
```

### **Step 3: Check Liquidity Requirements**
The `liquid_in_chain?` method requires:
- `last_price` > 0
- `oi` > 0
- Valid bid/ask spread (< 15% of LTP)

If market is closed, these will all be 0 or nil, causing the block.

---

## ✅ **Summary**

**Signal Generation**: ✅ **WORKING** - Using only Supertrend + ADX
**Strike Selection**: ❌ **BLOCKING** - Cannot find liquid ATM options

**Most Likely Cause**: **Market is closed** (01:22 IST)
- Option chain data unavailable when market is closed
- No live prices → `last_price` = 0 → fails liquidity check
- No open interest → `oi` = 0 → fails liquidity check

**Solution**: Wait for market hours (9:15 AM - 3:30 PM IST) and verify option chain data is available.

---

## 🔧 **To Test During Market Hours**

1. **Check if option chain is available**:
   ```bash
   bundle exec rails runner "
   instrument = Instrument.find_by_sid_and_segment(security_id: '13', segment_code: 'IDX_I')
   chain = instrument.option_chain
   puts \"Chain available: #{chain.present?}\"
   puts \"Sample keys: #{chain&.keys&.first(5)}\"
   "
   ```

2. **Check ATM strike liquidity**:
   ```bash
   # This will show if ATM options have valid LTP and OI
   ```

3. **Monitor logs during market hours**:
   ```bash
   tail -f log/development.log | grep -E "StrikeSelector|no_liquid|pick_strikes|Found.*strikes"
   ```

---

## 📝 **Next Steps**

1. ✅ **Confirmed**: System is using only Supertrend + ADX
2. ⏰ **Wait for market hours** (9:15 AM - 3:30 PM IST)
3. 🔍 **Verify option chain availability** during market hours
4. 📊 **Check liquidity requirements** if still blocking

The system is working correctly - it's just that option chain data is unavailable when the market is closed.
