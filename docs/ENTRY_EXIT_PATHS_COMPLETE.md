# Complete Entry & Exit Paths

## Overview

Yes, we have **multiple paths for BOTH entry and exit**. They work as layered decision systems.

---

## ENTRY PATHS

### Entry Flow Overview

```
Signal::Scheduler (every 30s)
  ↓
Signal::Engine.run_for() [PATH SELECTION]
  ├─→ Path 1A: Strategy Recommendations (if enabled)
  └─→ Path 1B: Supertrend + ADX (default/fallback)
  ↓
Multi-Timeframe Confirmation (if enabled) [PATH 2]
  ├─→ Path 2A: With Confirmation (5m confirmation)
  └─→ Path 2B: Without Confirmation (single timeframe)
  ↓
Comprehensive Validation [PATH 3]
  ├─→ Path 3A: Conservative Mode
  ├─→ Path 3B: Balanced Mode
  └─→ Path 3C: Aggressive Mode
  ↓
Strike Selection [PATH 4]
  └─→ Options::ChainAnalyzer.pick_strikes()
  ↓
EntryGuard.try_enter() [PATH 5]
  ├─→ Path 5A: Paper Trading
  └─→ Path 5B: Live Trading
```

---

### Path 1: Signal Generation Strategy

**Two parallel paths** - one selected based on config:

#### Path 1A: Strategy Recommendations
- **When**: `use_strategy_recommendations: true`
- **Logic**: Uses backtested strategy (SimpleMomentum, InsideBar, SupertrendAdx)
- **Timeframe**: Uses recommended strategy's timeframe (5m or 15m)
- **Confirmation**: Skipped (strategies are standalone)
- **Current Status**: ❌ Disabled (`use_strategy_recommendations: false`)

#### Path 1B: Supertrend + ADX (Default)
- **When**: Strategy recommendations disabled or unavailable
- **Logic**: Traditional Supertrend + ADX analysis
- **Timeframe**: Primary timeframe (currently 1m)
- **ADX Filter**: Can be enabled/disabled
- **Current Status**: ✅ Active (default path)

---

### Path 2: Multi-Timeframe Confirmation

**Two paths** - selected based on config:

#### Path 2A: With Confirmation
- **When**: `enable_confirmation_timeframe: true` AND not using strategy recommendations
- **Logic**: Analyzes primary (1m) + confirmation (5m) timeframes
- **Decision**: Both must align (bullish/bearish) or returns `:avoid`
- **Current Status**: ❌ Disabled (`enable_confirmation_timeframe: false`)

#### Path 2B: Without Confirmation
- **When**: Confirmation disabled OR using strategy recommendations
- **Logic**: Uses primary timeframe direction only
- **Decision**: Direct from primary analysis
- **Current Status**: ✅ Active (single timeframe)

---

### Path 3: Validation Mode

**Three paths** - selected based on `validation_mode`:

#### Path 3A: Conservative Mode
- **ADX**: min_strength: 25, confirmation: 30
- **IV Rank**: 0.15 - 0.6 (tighter range)
- **Theta Risk**: Cutoff 14:00
- **Trend Confirmation**: Required
- **IV Rank Check**: Required
- **Theta Risk Check**: Required
- **Current Status**: ❌ Not Active

#### Path 3B: Balanced Mode
- **ADX**: min_strength: 18, confirmation: 20
- **IV Rank**: 0.1 - 0.8 (moderate range)
- **Theta Risk**: Cutoff 14:30
- **Trend Confirmation**: Required
- **IV Rank Check**: Required
- **Theta Risk Check**: Required
- **Current Status**: ❌ Not Active

#### Path 3C: Aggressive Mode (Current)
- **ADX**: min_strength: 15, confirmation: 18
- **IV Rank**: 0.05 - 0.9 (wide range)
- **Theta Risk**: Cutoff 15:00
- **Trend Confirmation**: ❌ Not Required
- **IV Rank Check**: ✅ Required
- **Theta Risk Check**: ❌ Not Required
- **Current Status**: ✅ Active (`validation_mode: "aggressive"`)

**Validation Checks** (in order):
1. IV Rank Check (if `require_iv_rank_check: true`)
2. Theta Risk Check (if `require_theta_risk_check: true`)
3. ADX Strength (if `enable_adx_filter: true`)
4. Trend Confirmation (if `require_trend_confirmation: true`)
5. Market Timing (always checked)

---

### Path 4: Strike Selection

**Single path** with multiple filters:

- **Expiry**: Next upcoming expiry
- **Strike Focus**: ATM, ATM±1, ATM±2, ATM±3
- **Filters**:
  - IV Range: 10% - 60%
  - OI Minimum: 50,000
  - Spread Maximum: 3%
  - Delta: Time-based (0.08 - 0.15)
- **Scoring**: Multi-factor (ATM preference, liquidity, delta, IV, price efficiency)
- **Result**: Top 2 strikes

---

### Path 5: Entry Execution

**Two paths** - selected based on trading mode:

#### Path 5A: Paper Trading
- **When**: `paper_trading.enabled: true`
- **Logic**: Creates `PositionTracker` directly (no real order)
- **Current Status**: ✅ Active

#### Path 5B: Live Trading
- **When**: Paper trading disabled
- **Logic**: Places real market order via `Orders.config.place_market()`
- **Current Status**: ⚠️ Not Active (paper trading enabled)

**EntryGuard Checks** (in order):
1. Instrument lookup
2. Exposure check (`max_same_side`)
3. Cooldown check (180 seconds)
4. LTP resolution (WebSocket → REST API fallback)
5. Capital allocation (`Capital::Allocator`)
6. Order placement / PositionTracker creation

---

## EXIT PATHS

### Exit Flow Overview

```
RiskManagerService.monitor_loop() (every 5s)
  ↓
Path 1: Early Trend Failure
  ↓
Path 2: Hard Limits
  ↓
Path 3: Adaptive Trailing Stops
  ↓
Path 4: Time-Based Exit
```

---

### Path 1: Early Trend Failure (ETF)

**When Active**: Profit < 7% (before trailing activates)

**Exit Conditions**:
- Trend score drops ≥ 30% from peak
- ADX collapses below 10
- ATR ratio drops below 0.55
- VWAP rejection

**Exit Reason**: `"EARLY_TREND_FAILURE"`

**Current Status**: ✅ Active (`etf.enabled: true`)

---

### Path 2: Hard Limits

**When Active**: Always

**Sub-paths**:

#### Path 2A: Dynamic Reverse SL (Below Entry)
- **When**: PnL < 0
- **Logic**: Adaptive tightening (20% → 5%)
- **Factors**: Loss %, time below entry, ATR ratio
- **Exit Reason**: `"DYNAMIC_LOSS_HIT"`
- **Current Status**: ✅ Active (`reverse_loss.enabled: true`)

#### Path 2B: Static Stop Loss (Fallback)
- **When**: Dynamic reverse SL disabled or not applicable
- **Logic**: Fixed -3% threshold
- **Exit Reason**: `"SL HIT"`
- **Current Status**: ✅ Active (fallback)

#### Path 2C: Take Profit
- **When**: Profit ≥ +5%
- **Logic**: Fixed threshold
- **Exit Reason**: `"TP HIT"`
- **Current Status**: ✅ Active (`tp_pct: 0.05`)

---

### Path 3: Adaptive Trailing Stops

**When Active**: Profit ≥ 3% (profitable positions)

**Sub-paths**:

#### Path 3A: Adaptive Drawdown Schedule
- **Logic**: Exponential schedule (15% → 1% as profit increases)
- **Exit Reason**: `"ADAPTIVE_TRAILING_STOP"`
- **Current Status**: ✅ Active (`drawdown` config present)

#### Path 3B: Fixed Threshold (Fallback)
- **When**: Adaptive schedule unavailable
- **Logic**: Fixed 3% drop from HWM
- **Exit Reason**: `"TRAILING_STOP"`
- **Current Status**: ✅ Active (fallback, `exit_drop_pct: 0.03`)

#### Path 3C: Breakeven Locking
- **When**: Profit reaches +5%
- **Action**: Locks breakeven (no exit, just protection)
- **Current Status**: ✅ Active (`breakeven_after_gain: 0.05`)

---

### Path 4: Time-Based Exit

**When Active**: If configured (`time_exit_hhmm`)

**Exit Condition**: Current time >= configured exit time

**Exit Reason**: `"time-based exit"`

**Current Status**: ❌ Not Configured

---

## CURRENT ACTIVE PATHS SUMMARY

### Entry Paths (Active)

| Path | Status | Description |
|------|--------|-------------|
| **1B. Supertrend+ADX** | ✅ Active | Default signal generation (1m timeframe) |
| **2B. Single Timeframe** | ✅ Active | No confirmation (confirmation disabled) |
| **3C. Aggressive Validation** | ✅ Active | Minimal validation (IV rank only) |
| **4. Strike Selection** | ✅ Active | ATM-focused with filters |
| **5A. Paper Trading** | ✅ Active | Simulated positions |

### Exit Paths (Active)

| Path | Status | Description |
|------|--------|-------------|
| **1. Early Trend Failure** | ✅ Active | Early detection (profit < 7%) |
| **2A. Dynamic Reverse SL** | ✅ Active | Adaptive loss tightening (20% → 5%) |
| **2B. Static SL** | ✅ Active | Fallback (-3%) |
| **2C. Take Profit** | ✅ Active | Fixed (+5%) |
| **3A. Adaptive Trailing** | ✅ Active | Exponential drawdown (15% → 1%) |
| **3B. Fixed Trailing** | ✅ Active | Fallback (3% drop) |
| **3C. Breakeven Lock** | ✅ Active | Locks at +5% |

---

## PATH INTERACTIONS

### Entry Path Selection

```
Config Check:
  use_strategy_recommendations?
    ├─→ YES → Path 1A (Strategy Recommendations)
    └─→ NO  → Path 1B (Supertrend+ADX) ✅ CURRENT

  enable_confirmation_timeframe?
    ├─→ YES → Path 2A (Multi-timeframe)
    └─→ NO  → Path 2B (Single timeframe) ✅ CURRENT

  validation_mode?
    ├─→ "conservative" → Path 3A
    ├─→ "balanced" → Path 3B
    └─→ "aggressive" → Path 3C ✅ CURRENT
```

### Exit Path Execution

```
Sequential Execution (first match wins):
  1. ETF? → Exit if trend failing
  2. Hard Limits? → Exit if loss/profit limits hit
  3. Trailing? → Exit if profit drops from peak
  4. Time-Based? → Exit at configured time
```

---

## KEY DIFFERENCES

### Entry Paths
- **Multiple strategies** (strategy recommendations vs Supertrend+ADX)
- **Multiple timeframes** (with/without confirmation)
- **Multiple validation modes** (conservative/balanced/aggressive)
- **Single execution path** (paper vs live)

### Exit Paths
- **Sequential execution** (first match wins)
- **Layered defense** (multiple protection layers)
- **Bidirectional** (upward trailing + downward reverse SL)
- **Adaptive** (schedules adjust based on profit/loss)

---

## SUMMARY

**Yes, we have multiple paths for BOTH entry and exit:**

### Entry: 5 Major Paths
1. ✅ Signal Strategy (Strategy Recommendations vs Supertrend+ADX)
2. ✅ Timeframe Confirmation (With/Without confirmation)
3. ✅ Validation Mode (Conservative/Balanced/Aggressive)
4. ✅ Strike Selection (Single path with filters)
5. ✅ Execution Mode (Paper vs Live)

### Exit: 4 Major Paths
1. ✅ Early Trend Failure (ETF detection)
2. ✅ Hard Limits (Dynamic Reverse SL, Static SL, TP)
3. ✅ Adaptive Trailing (Adaptive schedule, Fixed threshold, Breakeven)
4. ⚠️ Time-Based (Not configured)

**Total: 9 distinct decision paths** (5 entry + 4 exit)

All paths are **configurable** and can be enabled/disabled independently.
