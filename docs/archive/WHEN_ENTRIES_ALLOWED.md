# When Will Entries Actually Be Allowed?

**Date**: 2026-01-12
**Status**: All major blocking systems disabled (DirectionGate, SMC+AVRZ, Index TA)

---

## ✅ **Current Configuration (All Blocking Systems Disabled)**

```yaml
signals:
  enable_index_ta: false                    # ✅ DISABLED
  enable_no_trade_engine: false             # ✅ DISABLED
  enable_smc_avrz_permission: false         # ✅ DISABLED
  enable_direction_gate: false              # ✅ DISABLED
  enable_adx_filter: true                   # ⚠️  ENABLED (can block weak trends)
  enable_confirmation_timeframe: false      # ✅ DISABLED (no multi-TF requirement)
```

---

## 🎯 **Entry Flow - Step by Step**

### **STEP 1: Signal Generation** (`Signal::Engine.run_for`)

#### ✅ **1.1 Primary Timeframe Analysis (1m)**
- **Requirement**: Supertrend must show `:bullish` or `:bearish` trend
- **Current Status**: ✅ Working (test showed `:bearish` with ADX 32.91)
- **Blocks If**: Supertrend is `:neutral` or `:avoid`

#### ✅ **1.2 ADX Filter** (if `enable_adx_filter: true`)
- **Requirement**: ADX >= `adx.min_strength` (default: 18-20)
- **Current Status**: ✅ Working (ADX 32.91 > 18)
- **Blocks If**: ADX < minimum strength
- **Config**: `signals.adx.min_strength` (default: 20)

#### ✅ **1.3 Confirmation Timeframe** (if `enable_confirmation_timeframe: true`)
- **Requirement**: 5m timeframe must align with 1m direction
- **Current Status**: ✅ DISABLED (no multi-TF requirement)
- **Blocks If**: Directions don't match (when enabled)

#### ✅ **1.4 DirectionGate**
- **Requirement**: Trade direction must align with market regime
- **Current Status**: ✅ DISABLED (no regime blocking)
- **Blocks If**: PE in bullish or CE in bearish (when enabled)

#### ✅ **1.5 Comprehensive Validation**
**Always Required Checks:**
- ✅ **Market Timing**: Must be trading day (Mon-Fri) and trading hours (9:15 AM - 3:30 PM IST)
- ✅ **ADX Strength**: If `enable_adx_filter: true`, ADX must meet minimum

**Optional Checks** (based on `validation_mode`):
- ⚠️ **IV Rank**: Only if `require_iv_rank_check: true` in validation mode
- ⚠️ **Theta Risk**: Only if `require_theta_risk_check: true` in validation mode
- ⚠️ **Trend Confirmation**: Only if `require_trend_confirmation: true` in validation mode

**Current Validation Mode**: `balanced` (default)
- IV Rank: **Optional** (usually disabled)
- Theta Risk: **Optional** (usually disabled)
- Trend Confirmation: **Optional** (usually disabled)

#### ✅ **1.6 Permission Resolution**
- **Requirement**: Returns permission level (`:blocked`, `:execution_only`, `:scale_ready`, `:full_deploy`)
- **Current Status**: ✅ Always returns `:scale_ready` (SMC+AVRZ disabled)
- **Blocks If**: Returns `:blocked` (not possible when SMC+AVRZ disabled)

#### ✅ **1.7 SMC Decision Alignment**
- **Requirement**: SMC decision (call/put) must align with signal direction
- **Current Status**: ✅ SKIPPED (SMC+AVRZ disabled)
- **Blocks If**: Directions don't align (when enabled)

#### ✅ **1.8 Strike Selection**
- **Requirement**: `Options::ChainAnalyzer.pick_strikes()` must return at least 1 option
- **Current Status**: ⚠️ **CRITICAL CHECK** - Must find suitable strikes
- **Blocks If**: No strikes found (empty array)
- **Common Reasons**:
  - No options available for the index
  - All options filtered out (IV too high/low, expiry too far, etc.)
  - Market data unavailable

---

### **STEP 2: EntryGuard Validation** (`Entries::EntryGuard.try_enter`)

#### ✅ **2.1 Time Regime Check**
- **Requirement**: Current time regime allows entries
- **Blocks If**:
  - After 14:50 IST (no new trades allowed)
  - Current regime doesn't allow entries (e.g., `CHOP_DECAY` without exceptional conditions)
- **Config**: `Live::TimeRegimeService` rules

#### ✅ **2.2 Edge Failure Detector**
- **Requirement**: No active pause for this index
- **Blocks If**:
  - Consecutive stop losses exceeded threshold
  - Rolling PnL window shows excessive losses
  - Manual pause active
- **Resume**: Automatic or manual override

#### ✅ **2.3 Daily Limits**
- **Requirement**: Daily loss/profit limits not exceeded
- **Blocks If**:
  - Daily loss limit reached
  - Daily profit target reached
- **Config**: `index_cfg[:daily_loss_limit]`, `index_cfg[:daily_profit_target]`

#### ✅ **2.4 Instrument Check**
- **Requirement**: Instrument must exist in database
- **Blocks If**: Instrument not found
- **Status**: Usually OK (instruments are cached)

#### ✅ **2.5 Exposure Check**
- **Requirement**: Max same-side positions not exceeded
- **Blocks If**:
  - Already have `max_same_side` positions in same direction (CE or PE)
  - Pyramiding rules violated (if second position)
- **Config**: `index_cfg[:max_same_side]` (default: 2-3)

#### ✅ **2.6 Cooldown Check**
- **Requirement**: Symbol not in cooldown period
- **Blocks If**: Symbol was recently traded (within cooldown window)
- **Config**: `index_cfg[:cooldown_sec]` (default: 60-300 seconds)

#### ✅ **2.7 LTP Resolution**
- **Requirement**: Valid LTP (Last Traded Price) must be available
- **Blocks If**:
  - LTP is nil or 0
  - WebSocket unavailable AND REST API fails
  - Market data stale
- **Fallback**: REST API if WebSocket unavailable

#### ✅ **2.8 Quantity Calculation**
- **Requirement**: Calculated quantity > 0
- **Blocks If**:
  - Capital allocation returns 0
  - Position size calculation fails
  - Insufficient capital
- **Config**: `Capital::Allocator` settings

---

## 📊 **Summary: When Entries Will Be Allowed**

### **✅ WILL ALLOW when ALL of these are true:**

1. **Market is Open**
   - ✅ Trading day (Mon-Fri, not holiday)
   - ✅ Trading hours (9:15 AM - 3:30 PM IST)
   - ✅ Before 14:50 IST (no new trades after this time)

2. **Signal Conditions Met**
   - ✅ Supertrend shows `:bullish` or `:bearish` (not `:neutral`)
   - ✅ ADX >= minimum strength (if ADX filter enabled, default: 18-20)
   - ✅ Multi-timeframe alignment (if confirmation enabled - currently disabled)

3. **Comprehensive Validation Passes**
   - ✅ Market timing valid (always required)
   - ✅ ADX strength sufficient (if ADX filter enabled)
   - ✅ IV Rank OK (if enabled in validation mode - usually disabled)
   - ✅ Theta Risk OK (if enabled in validation mode - usually disabled)
   - ✅ Trend Confirmation OK (if enabled in validation mode - usually disabled)

4. **Strike Selection Finds Options**
   - ✅ At least 1 option returned from `pick_strikes()`
   - ✅ Options meet criteria (IV, expiry, strike distance, etc.)

5. **EntryGuard Checks Pass**
   - ✅ Time regime allows entry
   - ✅ No edge failure detector pause
   - ✅ Daily limits not exceeded
   - ✅ Exposure limits OK (not at max same-side positions)
   - ✅ No cooldown active for this symbol
   - ✅ Valid LTP available
   - ✅ Quantity > 0

---

## ⚠️ **Most Likely Blocking Points (After Disabling Major Systems)**

### **1. ADX Filter Too Strict** (if enabled)
**Check**: `signals.enable_adx_filter` and `signals.adx.min_strength`
**Solution**:
```yaml
signals:
  enable_adx_filter: false  # Disable ADX requirement
  # OR
  adx:
    min_strength: 15  # Lower the minimum (default: 20)
```

### **2. No Strikes Found**
**Check**: Logs for `"No suitable strikes found"` or `pick_strikes` returning empty
**Solution**: Check `Options::ChainAnalyzer` configuration and market data availability

### **3. Market Timing**
**Check**: Current time is within trading hours (9:15 AM - 3:30 PM IST)
**Solution**: Wait for market hours or check timezone settings

### **4. EntryGuard Checks**
**Check**: Logs for specific EntryGuard blocking reasons
**Solution**: Check exposure limits, cooldown periods, LTP availability

### **5. Supertrend Not Generating Signals**
**Check**: Supertrend might be `:neutral` or `:avoid`
**Solution**: Market might be in consolidation - wait for trend to develop

---

## 🔍 **How to Diagnose Why Entries Aren't Happening**

### **1. Check Signal Generation**
```bash
tail -f log/development.log | grep -E "Signal.*Proceeding|Signal.*NOT proceeding|DirectionGate|comprehensive_validation"
```

### **2. Check Strike Selection**
```bash
tail -f log/development.log | grep -E "pick_strikes|No suitable strikes|Found.*strikes"
```

### **3. Check EntryGuard**
```bash
tail -f log/development.log | grep -E "EntryGuard.*blocked|EntryGuard.*Entry|Entry.*successful"
```

### **4. Check Market Timing**
```bash
bundle exec rails runner "
puts 'Market Open: ' + TradingSession::Service.new.market_open?.to_s
puts 'Current Time: ' + Time.current.in_time_zone('Asia/Kolkata').strftime('%H:%M:%S %Z')
"
```

### **5. Check ADX and Supertrend**
```bash
bundle exec rails runner "
index_cfg = { key: 'NIFTY', segment: 'IDX_I', sid: '13' }
instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
series = instrument.candle_series(interval: '1')
st = Indicators::Supertrend.new(series: series, period: 7, multiplier: 3).call
adx = instrument.adx(14, interval: '1')
puts \"Supertrend: #{st[:trend]}\"
puts \"ADX: #{adx}\"
"
```

---

## 🎯 **Quick Fixes to Allow More Entries**

### **Option 1: Disable ADX Filter** (Most Permissive)
```yaml
signals:
  enable_adx_filter: false
```
**Result**: Entries allowed even with weak ADX (trends)

### **Option 2: Lower ADX Minimum**
```yaml
signals:
  enable_adx_filter: true
  adx:
    min_strength: 15  # Lower from default 20
```
**Result**: Entries allowed with moderate trends

### **Option 3: Disable Confirmation Timeframe** (Already Done)
```yaml
signals:
  enable_confirmation_timeframe: false
```
**Result**: No multi-timeframe requirement (already disabled)

### **Option 4: Check Validation Mode**
```yaml
signals:
  validation_mode: aggressive  # Most permissive
  # OR
  validation_mode: balanced     # Default
  # OR
  validation_mode: conservative # Most strict
```

---

## 📝 **Expected Behavior**

With current configuration:
- ✅ **DirectionGate**: DISABLED - No regime blocking
- ✅ **SMC+AVRZ**: DISABLED - Always returns `:scale_ready`
- ✅ **Index TA**: DISABLED - No pre-filter
- ⚠️ **ADX Filter**: ENABLED - Requires ADX >= 18-20
- ⚠️ **Market Timing**: ALWAYS REQUIRED - Must be trading hours
- ⚠️ **Strike Selection**: ALWAYS REQUIRED - Must find options
- ⚠️ **EntryGuard**: ALWAYS ACTIVE - All checks must pass

**Entries will happen when**:
1. Market is open (9:15 AM - 3:30 PM IST, before 14:50)
2. Supertrend shows clear direction (`:bullish` or `:bearish`)
3. ADX >= 18-20 (if ADX filter enabled)
4. Strike selection finds suitable options
5. All EntryGuard checks pass

---

## 🚨 **If Still No Entries**

1. **Check if Signal Scheduler is running**:
   ```bash
   ps aux | grep "trading:daemon"
   ```

2. **Check recent logs for blocking reasons**:
   ```bash
   tail -200 log/development.log | grep -E "BLOCKED|NOT proceeding|blocked|Entry.*failed"
   ```

3. **Verify market is open**:
   ```bash
   bundle exec rails runner "puts TradingSession::Service.new.market_open?"
   ```

4. **Test signal generation manually**:
   ```bash
   bundle exec rails runner "
   index_cfg = { key: 'NIFTY', segment: 'IDX_I', sid: '13' }
   Signal::Engine.run_for(index_cfg)
   "
   ```

---

## ✅ **Bottom Line**

**Entries will be allowed when**:
- ✅ Market is open (trading hours)
- ✅ Supertrend + ADX generate a signal
- ✅ Strike selection finds options
- ✅ EntryGuard checks pass

**Most likely blockers** (in order):
1. **Market closed** (outside 9:15 AM - 3:30 PM IST)
2. **ADX too weak** (if ADX filter enabled and ADX < 18-20)
3. **No strikes found** (options unavailable or filtered out)
4. **EntryGuard blocking** (exposure, cooldown, LTP, etc.)
