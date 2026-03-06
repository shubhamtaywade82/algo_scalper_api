# NEMESIS V3 WIRING INTEGRITY AUDIT REPORT

**Date**: 2025-01-22
**Status**: ⚠️ **AUDIT COMPLETE - ISSUES FOUND**

---

## EXECUTIVE SUMMARY

This audit verifies that all NEMESIS V3 upgrades integrate correctly with the existing `algo_scalper_api` architecture without breaking previous flows.

**Overall Status**: ⚠️ **PARTIAL INTEGRATION - CRITICAL GAPS IDENTIFIED**

---

## 1. REPOSITORY SCAN & STRUCTURE MAP

### 1.1 New V3 Modules (7 files)

✅ **All modules found with correct file structure:**

| Module                          | File Path                                        | Status    |
| ------------------------------- | ------------------------------------------------ | --------- |
| `Positions::TrailingConfig`     | `app/services/positions/trailing_config.rb`      | ✅ Correct |
| `Signal::TrendScorer`           | `app/services/signal/trend_scorer.rb`            | ✅ Correct |
| `Signal::IndexSelector`         | `app/services/signal/index_selector.rb`          | ✅ Correct |
| `Options::PremiumFilter`        | `app/services/options/premium_filter.rb`         | ✅ Correct |
| `Capital::DynamicRiskAllocator` | `app/services/capital/dynamic_risk_allocator.rb` | ✅ Correct |
| `Live::TrailingEngine`          | `app/services/live/trailing_engine.rb`           | ✅ Correct |
| `Live::DailyLimits`             | `app/services/live/daily_limits.rb`              | ✅ Correct |

### 1.2 Updated Files (4 files)

| File                                        | Changes                                                | Status    |
| ------------------------------------------- | ------------------------------------------------------ | --------- |
| `app/services/orders/entry_manager.rb`      | Added DynamicRiskAllocator, BracketPlacer, DailyLimits | ✅ Updated |
| `app/services/orders/bracket_placer.rb`     | Added peak_profit_pct initialization                   | ✅ Updated |
| `app/services/positions/active_cache.rb`    | Added peak_profit_pct, persist_peak, reload_peaks      | ✅ Updated |
| `app/services/live/risk_manager_service.rb` | Added TrailingEngine integration, loss recording       | ✅ Updated |

---

## 2. NAMESPACE MATCHING

### 2.1 Zeitwerk Autoloading Check

✅ **All modules load correctly via Zeitwerk:**

```ruby
Signal::TrendScorer          # ✅ Loads
Signal::IndexSelector        # ✅ Loads
Options::PremiumFilter       # ✅ Loads
Capital::DynamicRiskAllocator # ✅ Loads
Live::TrailingEngine         # ✅ Loads
Live::DailyLimits            # ✅ Loads
Positions::TrailingConfig    # ✅ Loads
```

### 2.2 File Structure Validation

✅ **All namespace-to-file mappings are correct:**

- `Positions::` → `app/services/positions/`
- `Signal::` → `app/services/signal/`
- `Options::` → `app/services/options/`
- `Capital::` → `app/services/capital/`
- `Live::` → `app/services/live/`

**Status**: ✅ **PASS** - All namespaces match file structure

---

## 3. DEPENDENCY LOADING

### 3.1 Require Statements

✅ **No explicit requires needed** - Rails Zeitwerk handles autoloading

### 3.2 Redis Dependency

⚠️ **Redis gem required but not explicitly required:**
- `Live::DailyLimits` uses `Redis.new` but file doesn't have `require 'redis'`
- `Positions::ActiveCache` uses `Redis.new` but file doesn't have `require 'redis'`
- **Impact**: May fail if Redis gem not loaded (usually loaded via Gemfile)

**Status**: ⚠️ **MINOR ISSUE** - Should add `require 'redis'` for safety

---

## 4. WIRING OF NEW MODULES

### 4.1 ❌ **CRITICAL ISSUE: Signal::Scheduler Does NOT Use New V3 Modules**

**Current Flow:**
```
Signal::Scheduler
  → process_signal()
    → EntryGuard.try_enter()  [DIRECT CALL - BYPASSES V3 MODULES]
```

**Expected Flow (from upgrade plan):**
```
Signal::Scheduler
  → IndexSelector.select_best_index()
    → TrendScorer.compute_trend_score()
  → StrikeSelector.select(trend_score: ...)
    → PremiumFilter.valid?()
  → EntryManager.process_entry()
    → DynamicRiskAllocator.risk_pct_for()
    → EntryGuard.try_enter()
```

**Problem**:
- `Signal::Scheduler` (line 155) calls `EntryGuard.try_enter()` directly
- **Does NOT use**: `IndexSelector`, `TrendScorer`, `StrikeSelector`, `PremiumFilter`, `EntryManager`
- V3 modules are **orphaned** - not integrated into the signal flow

**Impact**: 🔴 **HIGH** - V3 features are not being used in production flow

**Location**: `app/services/signal/scheduler.rb:155`

---

### 4.2 ✅ EntryManager Integration (Partial)

**Status**: ✅ **CORRECTLY WIRED** (but not called from Scheduler)

**Integration Points:**
- ✅ Calls `DynamicRiskAllocator.risk_pct_for()` (line 38-42)
- ✅ Calls `EntryGuard.try_enter()` (line 54-59)
- ✅ Calls `BracketPlacer.place_bracket()` (line 95-101)
- ✅ Calls `DailyLimits.record_trade()` (line 108-109)
- ✅ Adds to `ActiveCache` (line 84-88)

**Problem**: EntryManager is **never called** from Signal::Scheduler

---

### 4.3 ✅ TrailingEngine Integration

**Status**: ✅ **CORRECTLY WIRED**

**Integration Points:**
- ✅ Called from `RiskManager.monitor_loop()` (line 113)
- ✅ Uses `Positions::TrailingConfig` for tiered SL (line 150+)
- ✅ Uses `Orders::BracketPlacer.new` (line 12) - ⚠️ **ISSUE**: Should use `.instance` if Singleton
- ✅ Uses `Positions::ActiveCache.instance` (line 9)
- ✅ Calls `exit_engine.execute_exit()` for peak-drawdown (line 73)

**Minor Issue**: `BracketPlacer` instantiation - see Section 5.3

---

### 4.4 ✅ DailyLimits Integration

**Status**: ✅ **CORRECTLY WIRED**

**Integration Points:**
- ✅ Called from `EntryGuard.try_enter()` (line 15)
- ✅ Called from `EntryManager.process_entry()` (line 108-109)
- ✅ Called from `RiskManager.record_loss_if_applicable()` (line 288)

---

### 4.5 ✅ PremiumFilter Integration

**Status**: ✅ **CORRECTLY WIRED**

**Integration Points:**
- ✅ Called from `StrikeSelector.select()` (line 70, 74)

---

### 4.6 ✅ TrailingConfig Integration

**Status**: ✅ **CORRECTLY WIRED**

**Integration Points:**
- ✅ Used by `TrailingEngine.apply_tiered_sl()` (line 150+)
- ✅ Used by `TrailingEngine.check_peak_drawdown()` (line 61)

---

### 4.7 ✅ ActiveCache Peak Persistence

**Status**: ✅ **CORRECTLY WIRED**

**Integration Points:**
- ✅ `persist_peak()` called from `recalculate_pnl()` (line 79)
- ✅ `persist_peak()` called from `update_position()` (line 232)
- ✅ `reload_peaks()` called from `start!()` (line 115)

---

## 5. METHOD SIGNATURE COMPATIBILITY

### 5.1 ✅ Capital::Allocator.qty_for

**Signature**: `qty_for(index_cfg:, entry_price:, derivative_lot_size:, scale_multiplier: 1)`

**Usage in EntryManager**: ❌ **NOT CALLED**

**Problem**: EntryManager does NOT call `Allocator.qty_for()` - it relies on EntryGuard to do it

**Location**: `app/services/orders/entry_manager.rb` - No call to `Allocator.qty_for()`

**Expected**: EntryManager should call:
```ruby
qty = Capital::Allocator.qty_for(
  index_cfg: index_cfg,
  entry_price: pick[:ltp] || tracker.entry_price,
  derivative_lot_size: lot_size,
  scale_multiplier: scale_multiplier,
  risk_pct: risk_pct  # ⚠️ MISSING PARAMETER
)
```

**Issue**: `Allocator.qty_for()` does NOT accept `risk_pct` parameter

---

### 5.2 ⚠️ EntryManager.process_entry

**Signature**: `process_entry(signal_result:, index_cfg:, direction:, scale_multiplier: 1, trend_score: nil)`

**Status**: ✅ **SIGNATURE CORRECT**

**Problem**: Method is **never called** from Signal::Scheduler

---

### 5.3 ⚠️ BracketPlacer Instantiation Inconsistency

**Issue**: Mixed usage of `.new` vs `.instance`

**Current Usage:**
- `EntryManager` (line 95): `Orders::BracketPlacer.new` ❌
- `TrailingEngine` (line 12): `Orders::BracketPlacer.new` ❌
- `RiskManager` (line 271): `Orders::BracketPlacer.instance` ✅

**Problem**: `BracketPlacer` is NOT a Singleton, but RiskManager treats it as one

**Fix Needed**: Decide on pattern:
- Option A: Make `BracketPlacer` a Singleton (add `include Singleton`)
- Option B: Use `.new` everywhere consistently

---

### 5.4 ✅ TrailingEngine.process_tick

**Signature**: `process_tick(position_data, exit_engine: nil)`

**Status**: ✅ **SIGNATURE CORRECT**

**Usage**: ✅ Called correctly from `RiskManager.process_trailing_for_all_positions()`

---

### 5.5 ✅ ActiveCache PositionData

**Status**: ✅ **STRUCTURE CORRECT**

**Fields**: All required fields present including `peak_profit_pct` (line 27)

---

## 6. EVENT FLOW COMPATIBILITY

### 6.1 Current Flow (Working)

```
Signal::Scheduler
  → EntryGuard.try_enter()
    → Orders::Placer.buy_market!()
    → PositionTracker.create!()
  → (Position added to ActiveCache via EntryManager? NO - MISSING)
  → RiskManager.monitor_loop()
    → process_trailing_for_all_positions()
      → TrailingEngine.process_tick()
        → BracketPlacer.update_bracket()
        → exit_engine.execute_exit() (if peak-drawdown)
```

### 6.2 Expected V3 Flow (NOT IMPLEMENTED)

```
Signal::Scheduler
  → IndexSelector.select_best_index()
    → TrendScorer.compute_trend_score()
  → StrikeSelector.select(trend_score: ...)
    → PremiumFilter.valid?()
  → EntryManager.process_entry()
    → DynamicRiskAllocator.risk_pct_for()
    → EntryGuard.try_enter()
    → BracketPlacer.place_bracket()
    → ActiveCache.add_position()
  → RiskManager.monitor_loop()
    → TrailingEngine.process_tick()
      → Peak-drawdown check
      → Tiered SL updates
```

### 6.3 ❌ **CRITICAL GAP**

**Problem**: Signal::Scheduler bypasses all V3 modules and goes directly to EntryGuard

**Impact**:
- IndexSelector never called
- TrendScorer never called (except by IndexSelector internally)
- StrikeSelector never called
- EntryManager never called
- DynamicRiskAllocator only called if EntryManager is used (which it's not)

**Status**: 🔴 **CRITICAL** - V3 flow not integrated

---

## 7. THREAD SAFETY & MUTEX USAGE

### 7.1 ✅ ActiveCache Thread Safety

**Status**: ✅ **THREAD-SAFE**

- Uses `Concurrent::Map` for cache (line 80)
- Uses `Mutex` for lock (line 82)
- `recalculate_pnl()` updates peak_profit_pct atomically (line 74)
- `persist_peak()` is called from within position update (safe)

---

### 7.2 ✅ RiskManager Thread Safety

**Status**: ✅ **THREAD-SAFE**

- Uses `Mutex` for service control (line 21)
- `process_trailing_for_all_positions()` iterates safely
- `record_loss_if_applicable()` is called from single thread

---

### 7.3 ✅ TrailingEngine Thread Safety

**Status**: ✅ **THREAD-SAFE**

- No shared mutable state
- Uses `tracker.with_lock` for exit (line 73)
- Idempotent exit check (line 65-68)

---

### 7.4 ✅ Exit Idempotency

**Status**: ✅ **IDEMPOTENT**

- `TrailingEngine.check_peak_drawdown()` checks `tracker.active?` before exit (line 65)
- Uses `tracker.with_lock` to prevent race conditions (line 73)
- Re-checks `tracker.active?` inside lock (line 75)

---

## 8. STATIC FLOW SIMULATION

### 8.1 Current Actual Flow (What Happens Now)

```
1. Signal::Scheduler.process_index()
   → evaluate_strategies_priority()
     → DerivativeChainAnalyzer.select_candidates()
   → process_signal()
     → EntryGuard.try_enter()  [DIRECT - BYPASSES V3]
       → Capital::Allocator.qty_for()  [Called by EntryGuard]
       → Orders::Placer.buy_market!()
       → PositionTracker.create!()

2. (EntryManager NOT CALLED - position never added to ActiveCache via EntryManager)

3. RiskManager.monitor_loop()
   → process_trailing_for_all_positions()
     → TrailingEngine.process_tick()
       → Peak-drawdown check
       → Tiered SL updates
```

**Problem**: Positions added via EntryGuard are NOT automatically in ActiveCache

---

### 8.2 Expected V3 Flow (What Should Happen)

```
1. Signal::Scheduler.process_index()
   → IndexSelector.select_best_index()
     → TrendScorer.compute_trend_score() for each index
     → Select best index with trend_score >= 15.0
   → StrikeSelector.select(index_key:, trend_score:)
     → PremiumFilter.valid?()
     → Return instrument hash
   → EntryManager.process_entry()
     → DynamicRiskAllocator.risk_pct_for()
     → EntryGuard.try_enter()
     → BracketPlacer.place_bracket()
     → ActiveCache.add_position()
     → DailyLimits.record_trade()

2. RiskManager.monitor_loop()
   → process_trailing_for_all_positions()
     → TrailingEngine.process_tick()
       → Peak-drawdown check (FIRST)
       → Update peak_profit_pct
       → Apply tiered SL
       → persist_peak() (via ActiveCache.recalculate_pnl)

3. On restart:
   → ActiveCache.start!()
     → reload_peaks()
```

**Status**: ❌ **NOT IMPLEMENTED** - Scheduler doesn't use this flow

---

## 9. PROBLEMS IDENTIFIED

### 9.1 🔴 **CRITICAL: Signal::Scheduler Does NOT Use V3 Modules**

**Problem**: Signal::Scheduler bypasses all V3 modules

**Location**: `app/services/signal/scheduler.rb:150-167`

**Current Code**:
```ruby
def process_signal(index_cfg, signal)
  pick = build_pick_from_signal(signal)
  direction = determine_direction(index_cfg)
  multiplier = signal[:meta][:multiplier] || 1

  result = Entries::EntryGuard.try_enter(  # ❌ DIRECT CALL
    index_cfg: index_cfg,
    pick: pick,
    direction: direction,
    scale_multiplier: multiplier
  )
  # ...
end
```

**Expected Code**:
```ruby
def process_signal(index_cfg, signal)
  # 1. Select best index using IndexSelector
  index_selector = Signal::IndexSelector.new
  best_index = index_selector.select_best_index
  return unless best_index

  # 2. Select strike using StrikeSelector with trend_score
  strike_selector = Options::StrikeSelector.new
  instrument_hash = strike_selector.select(
    index_key: best_index[:index_key],
    direction: determine_direction(index_cfg),
    trend_score: best_index[:trend_score]
  )
  return unless instrument_hash

  # 3. Use EntryManager instead of EntryGuard
  entry_manager = Orders::EntryManager.new
  result = entry_manager.process_entry(
    signal_result: { candidate: instrument_hash },
    index_cfg: index_cfg,
    direction: determine_direction(index_cfg),
    trend_score: best_index[:trend_score]
  )
  # ...
end
```

**Impact**: 🔴 **CRITICAL** - V3 features not used

---

### 9.2 ⚠️ **HIGH: EntryManager Not Called from Scheduler**

**Problem**: EntryManager exists but is never used

**Impact**: ⚠️ **HIGH** - EntryManager functionality unused

**Fix**: Integrate EntryManager into Signal::Scheduler (see 9.1)

---

### 9.3 ⚠️ **MEDIUM: Capital::Allocator.qty_for Missing risk_pct Parameter**

**Problem**: EntryManager wants to pass `risk_pct` to `Allocator.qty_for()`, but method doesn't accept it

**Location**:
- `app/services/orders/entry_manager.rb:38-42` (calculates risk_pct)
- `app/services/capital/allocator.rb` (qty_for signature)

**Current Signature**:
```ruby
def qty_for(index_cfg:, entry_price:, derivative_lot_size:, scale_multiplier: 1)
```

**Expected Signature**:
```ruby
def qty_for(index_cfg:, entry_price:, derivative_lot_size:, scale_multiplier: 1, risk_pct: nil)
```

**Impact**: ⚠️ **MEDIUM** - Dynamic risk allocation not applied to quantity calculation

**Note**: EntryManager doesn't actually call `qty_for()` - EntryGuard does. This is a future integration issue.

---

### 9.4 ⚠️ **MEDIUM: BracketPlacer Instantiation Inconsistency**

**Problem**: Mixed usage of `.new` vs `.instance`

**Current**:
- `EntryManager`: `BracketPlacer.new` ❌
- `TrailingEngine`: `BracketPlacer.new` ❌
- `RiskManager`: `BracketPlacer.instance` ✅ (but BracketPlacer is NOT a Singleton)

**Fix Options**:
1. Make `BracketPlacer` a Singleton (add `include Singleton`)
2. Use `.new` everywhere consistently

**Impact**: ⚠️ **MEDIUM** - Potential state inconsistency

---

### 9.5 ⚠️ **LOW: Missing require 'redis' Statements**

**Problem**: `DailyLimits` and `ActiveCache` use Redis but don't explicitly require it

**Files**:
- `app/services/live/daily_limits.rb` - Missing `require 'redis'`
- `app/services/positions/active_cache.rb` - Missing `require 'redis'`

**Impact**: ⚠️ **LOW** - Usually works via Gemfile, but explicit require is safer

---

### 9.6 ⚠️ **LOW: ActiveCache Position Not Auto-Added**

**Problem**: When EntryGuard creates a position, it's NOT automatically added to ActiveCache

**Current Flow**:
1. EntryGuard.try_enter() → Creates PositionTracker
2. EntryManager.process_entry() → Should add to ActiveCache (but EntryManager not called)

**Impact**: ⚠️ **LOW** - Positions may not be tracked in ActiveCache if EntryManager not used

**Note**: This becomes critical if EntryManager is integrated (see 9.1)

---

## 10. DEPENDENCY GRAPH

### 10.1 Old → New Module Dependencies

```
Signal::Scheduler (EXISTING)
  ❌ NOT CONNECTED → Signal::IndexSelector (NEW)
  ❌ NOT CONNECTED → Signal::TrendScorer (NEW)
  ❌ NOT CONNECTED → Options::StrikeSelector (ENHANCED)
  ❌ NOT CONNECTED → Options::PremiumFilter (NEW)
  ❌ NOT CONNECTED → Orders::EntryManager (NEW)
  ✅ CONNECTED → Entries::EntryGuard (EXISTING)

Entries::EntryGuard (EXISTING)
  ✅ CONNECTED → Live::DailyLimits.can_trade?() (NEW)
  ✅ CONNECTED → Capital::Allocator.qty_for() (EXISTING)

Orders::EntryManager (NEW)
  ✅ CONNECTED → Capital::DynamicRiskAllocator (NEW)
  ✅ CONNECTED → Entries::EntryGuard.try_enter() (EXISTING)
  ✅ CONNECTED → Orders::BracketPlacer.place_bracket() (ENHANCED)
  ✅ CONNECTED → Positions::ActiveCache.add_position() (ENHANCED)
  ✅ CONNECTED → Live::DailyLimits.record_trade() (NEW)
  ❌ NOT CALLED from Signal::Scheduler

Live::RiskManagerService (EXISTING)
  ✅ CONNECTED → Live::TrailingEngine.process_tick() (NEW)
  ✅ CONNECTED → Live::DailyLimits.record_loss() (NEW)

Live::TrailingEngine (NEW)
  ✅ CONNECTED → Positions::TrailingConfig (NEW)
  ✅ CONNECTED → Orders::BracketPlacer.update_bracket() (ENHANCED)
  ✅ CONNECTED → Positions::ActiveCache.instance (ENHANCED)
  ✅ CONNECTED → Live::ExitEngine.execute_exit() (EXISTING)

Positions::ActiveCache (ENHANCED)
  ✅ CONNECTED → Redis (for persist_peak/reload_peaks)
  ✅ CONNECTED → Positions::TrailingConfig (via TrailingEngine)

Options::StrikeSelector (ENHANCED)
  ✅ CONNECTED → Options::PremiumFilter.valid?() (NEW)
  ✅ CONNECTED → Options::DerivativeChainAnalyzer (EXISTING)
```

### 10.2 Missing Connections (Critical)

```
Signal::Scheduler
  ❌ → Signal::IndexSelector
  ❌ → Signal::TrendScorer
  ❌ → Options::StrikeSelector
  ❌ → Orders::EntryManager

Orders::EntryManager
  ❌ → Capital::Allocator.qty_for(risk_pct: ...)  [Parameter missing]
```

---

## 11. CHECKLIST

### 11.1 Namespace & File Structure

- [x] ✅ All namespaces match file structure
- [x] ✅ Zeitwerk autoloading works
- [x] ✅ No duplicate class names
- [x] ⚠️ Missing `require 'redis'` (low priority)

### 11.2 Module Wiring

- [ ] ❌ Signal::Scheduler → IndexSelector (NOT CONNECTED)
- [ ] ❌ Signal::Scheduler → TrendScorer (NOT CONNECTED)
- [ ] ❌ Signal::Scheduler → StrikeSelector (NOT CONNECTED)
- [ ] ❌ Signal::Scheduler → EntryManager (NOT CONNECTED)
- [x] ✅ EntryManager → DynamicRiskAllocator (CONNECTED)
- [x] ✅ EntryManager → BracketPlacer (CONNECTED)
- [x] ✅ EntryManager → DailyLimits (CONNECTED)
- [x] ✅ RiskManager → TrailingEngine (CONNECTED)
- [x] ✅ TrailingEngine → TrailingConfig (CONNECTED)
- [x] ✅ StrikeSelector → PremiumFilter (CONNECTED)
- [x] ✅ EntryGuard → DailyLimits (CONNECTED)

### 11.3 Method Signatures

- [x] ✅ EntryManager.process_entry signature correct
- [x] ✅ TrailingEngine.process_tick signature correct
- [ ] ⚠️ Allocator.qty_for missing risk_pct parameter
- [ ] ⚠️ BracketPlacer instantiation inconsistent

### 11.4 Event Flow

- [ ] ❌ V3 flow not integrated into Scheduler
- [x] ✅ TrailingEngine flow works
- [x] ✅ DailyLimits flow works
- [x] ✅ Peak persistence flow works

### 11.5 Thread Safety

- [x] ✅ ActiveCache thread-safe
- [x] ✅ RiskManager thread-safe
- [x] ✅ TrailingEngine thread-safe
- [x] ✅ Exit idempotent

---

## 12. REQUIRED FIXES

### 12.1 🔴 **CRITICAL: Integrate V3 Modules into Signal::Scheduler**

**File**: `app/services/signal/scheduler.rb`

**Change Required**: Modify `process_signal()` method to use V3 flow

**Steps**:
1. Add IndexSelector to select best index
2. Add StrikeSelector with trend_score
3. Replace EntryGuard call with EntryManager.process_entry()
4. Pass trend_score from IndexSelector to EntryManager

**Risk**: 🔴 **HIGH** - Changes core signal processing flow

**Testing Required**:
- Integration test for full V3 flow
- Verify backward compatibility
- Test with existing strategies

---

### 12.2 ⚠️ **HIGH: Add risk_pct Parameter to Allocator.qty_for**

**File**: `app/services/capital/allocator.rb`

**Change Required**: Add optional `risk_pct` parameter

**Steps**:
1. Add `risk_pct: nil` parameter to `qty_for()` method
2. Use `risk_pct` if provided, otherwise use default from deployment_policy
3. Update EntryManager to pass `risk_pct` when calling `qty_for()`

**Risk**: ⚠️ **MEDIUM** - Changes existing method signature (backward compatible with default)

---

### 12.3 ⚠️ **MEDIUM: Fix BracketPlacer Instantiation**

**Options**:
- **Option A**: Make BracketPlacer a Singleton
  - Add `include Singleton`
  - Update all `.new` calls to `.instance`
- **Option B**: Use `.new` everywhere
  - Update RiskManager to use `.new`

**Recommendation**: **Option A** (Singleton) - BracketPlacer manages bracket state

**Risk**: ⚠️ **LOW** - Internal change, no external API impact

---

### 12.4 ⚠️ **LOW: Add require 'redis' Statements**

**Files**:
- `app/services/live/daily_limits.rb`
- `app/services/positions/active_cache.rb`

**Change**: Add `require 'redis'` at top of file

**Risk**: ✅ **NONE** - Defensive programming

---

## 13. RISK ASSESSMENT

### 13.1 Breaking Changes

- ✅ **None identified** - All changes are additive
- ⚠️ **Potential**: Signal::Scheduler integration (12.1) changes flow but maintains backward compatibility

### 13.2 Backward Compatibility

- ✅ **Maintained** - Existing EntryGuard flow still works
- ✅ **Optional** - V3 features can be enabled/disabled via config

### 13.3 Production Readiness

- ⚠️ **NOT READY** - Critical integration missing (12.1)
- ⚠️ **PARTIAL** - TrailingEngine works, but signal flow doesn't use V3

---

## 14. RECOMMENDATIONS

### 14.1 Immediate Actions (Before Production)

1. 🔴 **CRITICAL**: Integrate V3 modules into Signal::Scheduler (Fix 12.1)
2. ⚠️ **HIGH**: Add risk_pct parameter to Allocator (Fix 12.2)
3. ⚠️ **MEDIUM**: Fix BracketPlacer instantiation (Fix 12.3)

### 14.2 Nice-to-Have (Can Be Done Later)

4. ⚠️ **LOW**: Add require 'redis' statements (Fix 12.4)

### 14.3 Testing Requirements

- Integration test for full V3 flow through Scheduler
- Test backward compatibility with existing strategies
- Test TrailingEngine with real tick sequences
- Test DailyLimits enforcement
- Test peak persistence/recovery

---

## 15. APPROVAL REQUIRED

**⚠️ NO FIXES WILL BE APPLIED UNTIL EXPLICIT APPROVAL.**

This audit report identifies critical integration gaps that must be addressed before the NEMESIS V3 upgrade can be considered production-ready.

**Critical Issues Requiring Approval**:
1. Signal::Scheduler integration (12.1) - Changes core flow
2. Allocator.qty_for enhancement (12.2) - Adds parameter
3. BracketPlacer Singleton pattern (12.3) - Architecture decision

---

**END OF AUDIT REPORT**

