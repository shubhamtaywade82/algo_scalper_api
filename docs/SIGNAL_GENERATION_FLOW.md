# Complete Signal Generation Flow & All Checks

**Generated:** 2025-12-18
**Purpose:** Document the complete signal generation path and all validation checks

---

## Overview

The signal generation flow is executed by `Signal::Scheduler` which calls `Signal::Engine.run_for()` for each index. The flow includes multiple validation layers before a trade is executed.

---

## Complete Signal Generation Flow

### Entry Point
```
Signal::Scheduler.process_index(index_cfg)
  └─> Signal::Engine.run_for(index_cfg)
```

---

## Step-by-Step Flow with All Checks

### **STEP 1: Initial Setup & Configuration**

**Location:** `Signal::Engine.run_for()` (lines 6-23)

**Checks:**
1. ✅ **Load Configuration**
   - Primary timeframe (default: "1m")
   - Confirmation timeframe (default: "5m", if enabled)
   - Strategy recommendations flag
   - No-Trade Engine flag

2. ✅ **Fetch Instrument**
   - Get instrument from `IndexInstrumentCache`
   - **BLOCK IF**: Instrument not found → Log error, return

---

### **STEP 2: Expiry Date Filtering** ⭐ **NEW**

**Location:** `Signal::Scheduler.reorder_indices_by_expiry()` (lines 316-410)

**Checks:**
1. ✅ **Calculate Days to Expiry**
   - Get nearest expiry date from instrument
   - Calculate: `days_to_expiry = (expiry_date - today).to_i`

2. ✅ **Filter by Max Expiry Days**
   - **BLOCK IF**: `days_to_expiry > max_expiry_days` (default: 7 days)
   - Log: `"Skipping BANKNIFTY - expiry in 15 days (> 7 days limit)"`
   - **Result**: Index is skipped entirely (no signal generation)

**Configuration:**
```yaml
signals:
  max_expiry_days: 7  # Maximum days to expiry
```

---

### **STEP 3: Strategy Recommendation (Optional)**

**Location:** `Signal::Engine.run_for()` (lines 25-41)

**Checks:**
1. ✅ **Check if Strategy Recommendations Enabled**
   - If `use_strategy_recommendations: true`
   - Get best strategy for index from `StrategyRecommender`

2. ✅ **Validate Strategy Recommendation**
   - **BLOCK IF**: Strategy not recommended (negative expectancy)
   - **FALLBACK**: Use Supertrend + ADX if recommendation fails

**Result:**
- If recommended: Use strategy-based analysis
- If not: Use Supertrend + ADX (default)

---

### **STEP 4: Primary Timeframe Analysis**

**Location:** `Signal::Engine.analyze_timeframe()` (lines 231-277)

**Checks:**
1. ✅ **Validate Timeframe**
   - Parse timeframe (e.g., "1m" → interval: 1)
   - **BLOCK IF**: Invalid timeframe → Log error, return

2. ✅ **Fetch Candle Data**
   - Get candle series for timeframe
   - **BLOCK IF**: No candle data → Log warning, return

3. ✅ **Calculate Supertrend**
   - Use `Indicators::Supertrend` service
   - Apply adaptive multipliers if configured
   - Get trend direction: `:bullish`, `:bearish`, or `:avoid`

4. ✅ **Calculate ADX**
   - Get ADX value from instrument
   - Check against minimum strength threshold

5. ✅ **Decide Direction**
   - Combine Supertrend trend + ADX strength
   - **BLOCK IF**: ADX < min_strength (if ADX filter enabled)
   - **BLOCK IF**: Supertrend = `:avoid`

**Result:**
- `{ status: :ok, direction: :bullish/:bearish/:avoid, ... }`
- **BLOCK IF**: `status != :ok` → Log warning, return

---

### **STEP 5: Confirmation Timeframe Analysis** ✅ **ENABLED**

**Location:** `Signal::Engine.run_for()` (lines 84-111)

**Status:** ✅ **Currently ENABLED** (`enable_confirmation_timeframe: true`, `confirmation_timeframe: "5m"`)

**Checks:**
1. ✅ **Check if Confirmation Enabled**
   - Currently: `enable_confirmation_timeframe: true` → **ENABLED**
   - If using strategy recommendations → Skip confirmation (currently disabled)

2. ✅ **Analyze Confirmation Timeframe**
   - Same checks as Step 4 (timeframe validation, candle data, Supertrend, ADX)

3. ✅ **Multi-Timeframe Direction Decision**
   - Compare primary direction vs confirmation direction
   - **BLOCK IF**: Directions mismatch → `final_direction = :avoid`

**Result:**
- `final_direction = :bullish/:bearish/:avoid`
- **BLOCK IF**: `final_direction == :avoid` → Log info, return

---

### **STEP 6: Comprehensive Validation**

**Location:** `Signal::Engine.comprehensive_validation()` (lines 372-428)

**Checks (Based on Validation Mode):**

#### **1. IV Rank Check** (if enabled)
- **Location:** `validate_iv_rank()` (lines 445-477)
- **BLOCK IF**: Extreme volatility detected
- **BLOCK IF**: Very low volatility

#### **2. Theta Risk Assessment** (if enabled)
- **Location:** `validate_theta_risk()` (lines 480-498)
- **BLOCK IF**: After cutoff time (default: 14:30)
- **WARN IF**: After 14:00 (moderate risk)

#### **3. ADX Strength Check** (if enabled)
- **Location:** `validate_adx_strength()` (lines 501-516)
- **BLOCK IF**: ADX < min_strength threshold
- **ALLOW IF**: ADX >= 25 (strong trend)
- **ALLOW IF**: ADX >= 40 (very strong trend)

#### **4. Trend Confirmation** (if enabled)
- **Location:** `validate_trend_confirmation()` (lines 519-549)
- **BLOCK IF**: Recent price action doesn't support trend direction
- Checks last 3 candles for directional alignment

#### **5. Market Timing Check** (always required)
- **Location:** `validate_market_timing()` (lines 552-563)
- **BLOCK IF**: Not a trading day (weekend/holiday)
- **BLOCK IF**: Outside trading hours

**Result:**
- `{ valid: true/false, reason: "..." }`
- **BLOCK IF**: `valid == false` → Log warning, return

---

### **STEP 7: Strike Selection**

**Location:** `Signal::Engine.run_for()` (lines 187-192)

**Checks:**
1. ✅ **Call Chain Analyzer**
   - `Options::ChainAnalyzer.pick_strikes(index_cfg: index_cfg, direction: final_direction)`

2. ✅ **Validate Picks**
   - **BLOCK IF**: No picks returned → Log warning, return

**Result:**
- Array of option picks (CE for bullish, PE for bearish)
- Each pick contains: `symbol`, `security_id`, `segment`, `ltp`, `lot_size`

---

### **STEP 8: EntryGuard Validation**

**Location:** `Entries::EntryGuard.try_enter()` (lines 8-100)

**Checks (in order):**

#### **1. Instrument Check**
- **BLOCK IF**: Instrument not found → Log warning, return false

#### **2. Exposure Check**
- **Location:** `exposure_ok?()` (line 19)
- **BLOCK IF**: Max same-side positions reached
- **BLOCK IF**: Pyramiding rules violated (if second position)

#### **3. Cooldown Check**
- **Location:** `cooldown_active?()` (line 24)
- **BLOCK IF**: Symbol in cooldown period → Log warning, return false

#### **4. LTP Resolution**
- **Location:** `resolve_entry_ltp()` (line 41)
- Try WebSocket TickCache first
- Fallback to REST API if WebSocket unavailable
- **BLOCK IF**: LTP invalid or missing → Log warning, return false

#### **5. Quantity Calculation**
- **Location:** `Capital::Allocator.qty_for()` (line 50)
- Calculate position size based on:
  - Rupee-based sizing (if enabled)
  - Percentage-based sizing (default)
- **BLOCK IF**: Quantity <= 0 → Log warning, return false

#### **6. Daily Limits Check** ⚠️ **REMOVED** (was in code but commented out)
- **Note**: Daily limits check was removed from EntryGuard
- Daily limits are still enforced elsewhere in the system

---

### **STEP 9: Order Placement**

**Location:** `Entries::EntryGuard.try_enter()` (lines 61-100)

**Actions:**
1. ✅ **Paper Trading Mode**
   - Create `PositionTracker` directly (no real order)
   - Set status: `active`
   - Store entry metadata

2. ✅ **Live Trading Mode**
   - Place market order via `Orders.config.place_market()`
   - Extract order number from response
   - Create `PositionTracker` with order number

3. ✅ **Post-Entry Processing**
   - Call `Orders::EntryManager.process_entry()`
   - Add to `ActiveCache`
   - Subscribe to market feed
   - Place bracket orders (if configured)

---

## Validation Modes

### **Balanced Mode** (Default)
- IV Rank Check: **Optional**
- Theta Risk: **Optional**
- ADX Strength: **Required** (if ADX filter enabled)
- Trend Confirmation: **Optional**
- Market Timing: **Always Required**

### **Strict Mode**
- All checks: **Required**
- Higher thresholds
- More conservative

### **Loose Mode**
- Fewer checks required
- Lower thresholds
- More permissive

**Configuration:**
```yaml
signals:
  validation_mode: balanced  # Options: balanced, strict, loose
  validation_modes:
    balanced:
      require_iv_rank_check: false
      require_theta_risk_check: false
      require_trend_confirmation: false
```

---

## No-Trade Engine Status

**Current Status:** ⚠️ **DISABLED** (based on config)

**Configuration:**
```yaml
signals:
  enable_no_trade_engine: false  # Currently disabled
```

**If Enabled, Would Add:**
- **Phase 1**: Quick pre-check before signal generation
- **Phase 2**: Detailed validation after signal generation

**Note:** No-Trade Engine integration exists in code but is currently disabled via config.

---

## Summary of All Checks

### **Pre-Signal Generation Checks**
1. ✅ Instrument exists
2. ✅ Expiry date ≤ 7 days (NEW)
3. ✅ Strategy recommendation valid (if enabled)
4. ✅ Primary timeframe data available
5. ✅ Supertrend calculation successful
6. ✅ ADX meets minimum strength (if filter enabled)

### **Post-Signal Generation Checks**
7. ✅ Confirmation timeframe matches (if enabled)
8. ✅ Final direction != :avoid
9. ✅ IV Rank acceptable (if enabled)
10. ✅ Theta risk acceptable (if enabled)
11. ✅ ADX strength sufficient (if enabled)
12. ✅ Trend confirmed by price action (if enabled)
13. ✅ Market timing valid (always)
14. ✅ Strike picks available

### **Pre-Entry Checks (EntryGuard)**
15. ✅ Instrument found
16. ✅ Exposure limits not exceeded
17. ✅ Cooldown not active
18. ✅ LTP valid
19. ✅ Quantity > 0

### **Post-Entry Actions**
20. ✅ PositionTracker created
21. ✅ Added to ActiveCache
22. ✅ Subscribed to market feed
23. ✅ Bracket orders placed (if configured)

---

## Current Signal Generation Path

**Active Path:**
```
Signal::Scheduler.process_index()
  └─> Signal::Engine.run_for()
      ├─> Expiry Filter (NEW - skip if > 7 days)
      ├─> Strategy Recommendation (optional, currently disabled)
      ├─> Primary Timeframe Analysis (1m Supertrend + ADX)
      ├─> Confirmation Timeframe Analysis ✅ ENABLED (5m confirmation required)
      ├─> Comprehensive Validation
      ├─> Strike Selection
      └─> EntryGuard.try_enter()
          ├─> Exposure Check
          ├─> Cooldown Check
          ├─> LTP Resolution
          ├─> Quantity Calculation
          └─> Order Placement
```

**No-Trade Engine:** Currently **DISABLED** (not in active path)

---

## Configuration Summary

### **Signal Generation**
```yaml
signals:
  primary_timeframe: "1m"
  confirmation_timeframe: "5m"
  enable_confirmation_timeframe: true  # ✅ ENABLED
  max_expiry_days: 7  # NEW
  enable_no_trade_engine: false  # Currently disabled
  enable_adx_filter: false  # Currently disabled
  validation_mode: balanced
```

### **Current Active Checks**
- ✅ **Expiry Filter**: ENABLED (7 days)
- ✅ **Confirmation Timeframe**: ENABLED (5m confirmation for 1m signals)
- ❌ **No-Trade Engine**: DISABLED
- ❌ **ADX Filter**: DISABLED

### **Validation Modes**
- **balanced**: Moderate checks (default)
- **strict**: All checks required
- **loose**: Fewer checks

---

## Log Messages to Watch

### **When Signal is Blocked**
```
[Signal] NOT proceeding for NIFTY: multi-timeframe bias mismatch or weak trend
[Signal] NOT proceeding for NIFTY: Failed checks: ADX Strength, Trend Confirmation
[SignalScheduler] Skipping BANKNIFTY - expiry in 15 days (> 7 days limit)
[EntryGuard] Exposure check failed for NIFTY: max_same_side positions reached
[EntryGuard] Cooldown active for NIFTY: NIFTY25000CE
```

### **When Signal Proceeds**
```
[Signal] Proceeding with bullish signal for NIFTY
[Signal] Found 2 option picks for NIFTY: NIFTY25000CE, NIFTY25050CE
[EntryGuard] Entry successful for NIFTY: NIFTY25000CE
```

---

## Key Takeaways

1. **Expiry Filtering**: NEW - Indices with expiry > 7 days are skipped
2. **No-Trade Engine**: Currently disabled (not in active path)
3. **Validation Mode**: Uses "balanced" mode by default
4. **ADX Filter**: Currently disabled (allows weak trends)
5. **Confirmation Timeframe**: ✅ **ENABLED** - 5m confirmation required for 1m signals (both must align)
6. **EntryGuard**: Final validation layer before order placement

---

## Next Steps to Enable Additional Checks

### **To Enable No-Trade Engine:**
```yaml
signals:
  enable_no_trade_engine: true  # Enable both Phase 1 and Phase 2
```

### **To Enable ADX Filter:**
```yaml
signals:
  enable_adx_filter: true  # Block weak trends (ADX < threshold)
```

### **To Use Strict Validation:**
```yaml
signals:
  validation_mode: strict  # All checks required
```
