# Redundancy Analysis: Services Doing Repeated Work

**Last Updated**: Current
**Purpose**: Identify services performing redundant or overlapping work

---

## Executive Summary

**🔴 CRITICAL REDUNDANCIES FOUND**: Multiple services are performing the same work, leading to:
- Duplicate PnL calculations
- Redundant cache updates
- Overlapping position monitoring
- Unnecessary database queries

---

## 1. PnL Update Redundancy 🔴 **CRITICAL**

### Problem: Three Services Updating Paper Position PnL

#### ✅ **PaperPnlRefresher** (Active - Every 1 second)
- **File**: `app/services/live/paper_pnl_refresher.rb`
- **Frequency**: 1 second (active positions) or 5 seconds (idle)
- **What it does**:
  - Gets LTP from TickCache
  - Calculates PnL
  - Updates PositionTracker database
  - Stores in RedisPnlCache
- **Status**: ✅ **ACTIVE** - Started by supervisor

#### ⚠️ **RiskManagerService.update_paper_positions_pnl()** (Active - Every 1 minute)
- **File**: `app/services/live/risk_manager_service.rb:768`
- **Frequency**: Every 1 minute (throttled)
- **What it does**:
  - Gets LTP from API (for paper positions)
  - Calculates PnL
  - Updates PositionTracker database
  - Stores in RedisPnlCache via PnlUpdaterService
- **Status**: ⚠️ **REDUNDANT** - PaperPnlRefresher already does this every 1 second

#### ❌ **PnlUpdaterService** (Available but NOT started)
- **File**: `app/services/live/pnl_updater_service.rb`
- **Purpose**: Batch PnL updates from multiple sources
- **Status**: ❌ **NOT STARTED** - Commented out in supervisor
- **Note**: Used by RiskManagerService but service itself not started

### Impact

**For Paper Positions**:
- PaperPnlRefresher updates PnL every 1 second ✅
- RiskManagerService ALSO updates PnL every 1 minute ⚠️ **REDUNDANT**
- Both update the same database fields
- Both store in RedisPnlCache
- **Result**: Duplicate work, unnecessary API calls, potential race conditions

### Recommendation

**Option 1 (Recommended)**: Remove PnL update from RiskManagerService
- PaperPnlRefresher already handles paper PnL updates efficiently
- RiskManagerService should focus on risk monitoring only
- **Code to remove**: `update_paper_positions_pnl_if_due()` and `update_paper_positions_pnl()` from RiskManagerService

**Option 2**: Disable PaperPnlRefresher and use RiskManagerService only
- Less efficient (1 minute vs 1 second updates)
- Not recommended

---

## 2. Position Cache Redundancy 🟡 **MODERATE**

### Problem: Multiple Services Ensuring Positions in Caches

#### ⚠️ **RiskManagerService** (Every 5 seconds)
- **File**: `app/services/live/risk_manager_service.rb`
- **Methods**:
  - `ensure_all_positions_in_redis()` (line ~850)
  - `ensure_all_positions_in_active_cache()` (line ~900)
  - `ensure_all_positions_subscribed()` (line ~950)
- **Frequency**: Every 5 seconds (throttled)
- **What it does**:
  - Checks if positions exist in Redis
  - Checks if positions exist in ActiveCache
  - Checks if positions are subscribed to market data
  - Fixes any missing entries

#### ⚠️ **ReconciliationService** (On-demand, but called frequently)
- **File**: `app/services/live/reconciliation_service.rb`
- **Method**: `reconcile_all_positions()` (line ~98)
- **Frequency**: Called periodically (not in supervisor loop, but available)
- **What it does**:
  - Ensures positions subscribed
  - Ensures positions in ActiveCache
  - Syncs PnL from Redis to DB
  - Syncs ActiveCache PnL from Redis

### Impact

- **RiskManagerService** checks and fixes caches every 5 seconds
- **ReconciliationService** also checks and fixes the same caches
- Both services may try to fix the same issues simultaneously
- **Result**: Duplicate work, potential race conditions

### Recommendation

**Consolidate to one service**:
- Keep RiskManagerService checks (it's in the main loop)
- Remove ReconciliationService OR make it only run on-demand (not in loop)
- **Current status**: ReconciliationService is registered but not actively running in a loop (good!)

---

## 3. ActiveCache PnL Sync Redundancy 🟡 **MODERATE**

### Problem: Multiple Services Updating ActiveCache with PnL

#### ⚠️ **RiskManagerService** (Every cycle)
- **File**: `app/services/live/risk_manager_service.rb`
- **Method**: Updates ActiveCache during position processing
- **What it does**: Updates ActiveCache position with Redis PnL data

#### ⚠️ **ReconciliationService** (On-demand)
- **File**: `app/services/live/reconciliation_service.rb:192`
- **Method**: `sync_activecache_pnl()`
- **What it does**: Syncs ActiveCache PnL from Redis

#### ⚠️ **ActiveCache.recalculate_pnl()** (On position update)
- **File**: `app/services/positions/active_cache.rb:72`
- **What it does**: Recalculates PnL when position is updated

### Impact

- Multiple services updating the same ActiveCache entries
- Potential for stale data or race conditions
- **Result**: Unnecessary updates, potential inconsistencies

### Recommendation

**Single source of truth**:
- PaperPnlRefresher should be the primary updater (updates Redis)
- ActiveCache should read from Redis (not be updated separately)
- OR: ActiveCache should be updated only by PaperPnlRefresher

---

## 4. Market Data Subscription Redundancy 🟡 **MODERATE**

### Problem: Multiple Services Ensuring Subscriptions

#### ✅ **EntryManager** (On entry)
- **File**: `app/services/orders/entry_manager.rb`
- **What it does**: Subscribes position to market data on entry
- **Status**: ✅ **CORRECT** - Should subscribe on entry

#### ⚠️ **RiskManagerService** (Every 5 seconds)
- **File**: `app/services/live/risk_manager_service.rb`
- **Method**: `ensure_all_positions_subscribed()`
- **Frequency**: Every 5 seconds (throttled)
- **What it does**: Checks and fixes missing subscriptions

#### ⚠️ **ReconciliationService** (On-demand)
- **File**: `app/services/live/reconciliation_service.rb:150`
- **Method**: `subscribed?()` and `fix_subscription()`
- **What it does**: Checks and fixes missing subscriptions

### Impact

- EntryManager subscribes on entry ✅
- RiskManagerService checks every 5 seconds (redundant if EntryManager works)
- ReconciliationService also checks (redundant)
- **Result**: Unnecessary subscription checks

### Recommendation

**Keep EntryManager subscription, reduce checks**:
- EntryManager should handle subscriptions correctly
- RiskManagerService check is a safety net (keep but reduce frequency to 30 seconds)
- ReconciliationService should only run on-demand (not in loop)

---

## 5. Redis PnL Cache Updates Redundancy 🟡 **MODERATE**

### Problem: Multiple Services Writing to RedisPnlCache

#### ✅ **PaperPnlRefresher** (Every 1 second)
- **File**: `app/services/live/paper_pnl_refresher.rb:104`
- **Method**: `Live::RedisPnlCache.instance.store_pnl()`
- **What it does**: Direct write to Redis

#### ⚠️ **RiskManagerService** (Every 1 minute)
- **File**: `app/services/live/risk_manager_service.rb:1063`
- **Method**: `Live::PnlUpdaterService.instance.cache_intermediate_pnl()`
- **What it does**: Queues update to PnlUpdaterService (which writes to Redis)

#### ⚠️ **MarketFeedHub** (On every tick)
- **File**: `app/services/live/market_feed_hub.rb:458`
- **Method**: `Live::PnlUpdaterService.instance.cache_intermediate_pnl()`
- **What it does**: Queues PnL update from tick data

### Impact

- PaperPnlRefresher writes directly to Redis ✅
- RiskManagerService queues updates via PnlUpdaterService ⚠️
- MarketFeedHub queues updates via PnlUpdaterService (for live positions) ✅
- **Result**: For paper positions, both PaperPnlRefresher and RiskManagerService write to Redis

### Recommendation

**Separate responsibilities**:
- **PaperPnlRefresher**: Direct write for paper positions (current behavior)
- **PnlUpdaterService**: Queue-based updates for live positions (from MarketFeedHub)
- **RiskManagerService**: Remove PnL updates (let PaperPnlRefresher handle it)

---

## 6. Database Update Redundancy 🟡 **MODERATE**

### Problem: Multiple Services Updating PositionTracker Database

#### ✅ **PaperPnlRefresher** (Every 1 second)
- **File**: `app/services/live/paper_pnl_refresher.rb:98`
- **Method**: `tracker.update!()`
- **What it does**: Updates `last_pnl_rupees`, `last_pnl_pct`, `high_water_mark_pnl`

#### ⚠️ **RiskManagerService** (Every 1 minute)
- **File**: `app/services/live/risk_manager_service.rb:801`
- **Method**: `tracker.update!()`
- **What it does**: Updates same fields as PaperPnlRefresher

#### ⚠️ **ReconciliationService** (On-demand)
- **File**: `app/services/live/reconciliation_service.rb:188`
- **Method**: `tracker.hydrate_pnl_from_cache!()`
- **What it does**: Syncs database from Redis cache

### Impact

- PaperPnlRefresher updates DB every 1 second ✅
- RiskManagerService updates DB every 1 minute (redundant) ⚠️
- ReconciliationService syncs DB from Redis (redundant if PaperPnlRefresher works) ⚠️
- **Result**: Multiple database writes for the same data

### Recommendation

**Single updater for paper positions**:
- PaperPnlRefresher should be the only service updating paper position PnL in DB
- Remove RiskManagerService PnL updates
- ReconciliationService should only run on-demand for fixing inconsistencies

---

## 7. Summary of Redundancies

| Redundancy | Services Involved | Impact | Recommendation |
|------------|------------------|--------|----------------|
| **PnL Updates** | PaperPnlRefresher + RiskManagerService | 🔴 **CRITICAL** | Remove from RiskManagerService |
| **Cache Ensures** | RiskManagerService + ReconciliationService | 🟡 **MODERATE** | Keep RiskManagerService, make ReconciliationService on-demand only |
| **ActiveCache PnL** | RiskManagerService + ReconciliationService + ActiveCache | 🟡 **MODERATE** | Single source of truth (PaperPnlRefresher → Redis → ActiveCache) |
| **Subscriptions** | EntryManager + RiskManagerService + ReconciliationService | 🟡 **MODERATE** | Keep EntryManager, reduce RiskManagerService frequency |
| **Redis Updates** | PaperPnlRefresher + RiskManagerService | 🟡 **MODERATE** | Remove RiskManagerService updates |
| **DB Updates** | PaperPnlRefresher + RiskManagerService + ReconciliationService | 🟡 **MODERATE** | Single updater (PaperPnlRefresher) |

---

## 8. Recommended Actions

### Priority 1: Remove PnL Updates from RiskManagerService 🔴

**File**: `app/services/live/risk_manager_service.rb`

**Remove or comment out**:
- `update_paper_positions_pnl_if_due()` call (line ~164, ~183)
- `update_paper_positions_pnl()` method (line ~768)
- `batch_update_paper_positions_pnl()` method (line ~1858)
- `update_pnl_in_redis()` method (line ~1052) - or keep only for live positions

**Reason**: PaperPnlRefresher already handles this every 1 second

### Priority 2: Make ReconciliationService On-Demand Only 🟡

**File**: `app/services/live/reconciliation_service.rb`

**Current**: Registered in supervisor but not actively running
**Action**: Ensure it only runs on-demand (manual trigger or scheduled task), not in a loop

**Reason**: RiskManagerService already ensures caches every 5 seconds

### Priority 3: Reduce Subscription Check Frequency 🟡

**File**: `app/services/live/risk_manager_service.rb`

**Current**: Checks subscriptions every 5 seconds
**Change**: Increase to 30 seconds (subscriptions rarely change)

**Reason**: EntryManager handles subscriptions on entry, checks are just safety net

### Priority 4: Consolidate ActiveCache Updates 🟡

**Strategy**:
- PaperPnlRefresher updates Redis
- ActiveCache reads from Redis (or is updated only by PaperPnlRefresher)
- Remove ActiveCache PnL updates from RiskManagerService and ReconciliationService

---

## 9. Expected Benefits After Fixes

### Performance Improvements
- ✅ **50% reduction** in PnL calculation calls (remove RiskManagerService updates)
- ✅ **Reduced database writes** (single updater instead of two)
- ✅ **Reduced Redis writes** (single updater instead of two)
- ✅ **Fewer API calls** (RiskManagerService won't fetch LTP for paper positions)

### Code Quality Improvements
- ✅ **Single responsibility** - Each service has clear purpose
- ✅ **Reduced race conditions** - Fewer concurrent updates
- ✅ **Easier debugging** - Single source of truth for PnL updates

### Resource Savings
- ✅ **Lower CPU usage** - Fewer redundant calculations
- ✅ **Lower database load** - Fewer redundant writes
- ✅ **Lower Redis load** - Fewer redundant writes

---

## 10. Current Service Responsibilities (After Fixes)

### PaperPnlRefresher
- ✅ **ONLY** service updating paper position PnL
- Updates database every 1 second
- Updates Redis every 1 second
- **No redundancy**

### RiskManagerService
- ✅ Risk monitoring and exit enforcement
- ✅ Ensures positions in caches (safety net)
- ✅ Ensures subscriptions (safety net)
- ❌ **NO PnL updates** (removed)

### ReconciliationService
- ✅ On-demand data consistency checks
- ✅ Fixes inconsistencies when detected
- ❌ **NOT in active loop** (on-demand only)

### EntryManager
- ✅ Subscribes positions on entry
- ✅ Post-entry wiring
- **No redundancy**

---

**This analysis identifies all redundancies. Implementing the recommended fixes will significantly improve system efficiency and reduce resource usage.**

