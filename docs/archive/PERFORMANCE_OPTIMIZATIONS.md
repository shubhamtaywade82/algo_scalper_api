# Performance Optimizations - Complete Guide

**Date**: Current
**Status**: ✅ Implemented

---

## 🔍 **Key Findings from Log Analysis**

### **1. Repeated PositionTracker Queries (CRITICAL)**

**Issue**: `PositionTracker.active` query executed **23+ times** in short period

**Services Executing**:
- `ReconciliationService` - Every 5 seconds
- `PositionIndex.bulk_load_active!` - Every 10 seconds (via PositionHeartbeat)
- `RiskManagerService.ensure_all_positions_in_active_cache` - Every 5 seconds
- `RiskManagerService.ensure_all_positions_subscribed` - Every 5 seconds
- `PositionTrackerPruner` - Every 10 seconds

**Impact**:
- Same query executed multiple times per cycle
- Some queries taking 200-500ms (slow)
- Database load unnecessarily high

**Optimization**: Cache active positions in-memory, refresh periodically

---

### **2. WatchlistItem.exists? Queries (HIGH)**

**Issue**: `WatchlistItem.exists?` called multiple times, some taking **79ms**

**Locations**:
- `IndexConfigLoader.watchlist_items_available?` - Called every time indices loaded
- `MarketFeedHub.load_watchlist` - Called multiple times

**Impact**:
- Redundant database checks
- Slow queries (up to 79ms)

**Optimization**: Cache result, invalidate on WatchlistItem changes

---

### **3. Expiry Calculation Recalculation (MEDIUM)**

**Issue**: Expiry dates recalculated every 30 seconds in `Signal::Scheduler.reorder_indices_by_expiry`

**Impact**:
- Expiry dates don't change frequently (only on new expiry day)
- Unnecessary API calls to `instrument.expiry_list`
- Redundant parsing

**Optimization**: Cache expiry dates, refresh once per day or when expiry changes

---

### **4. IndexConfigLoader No Caching (MEDIUM)**

**Issue**: `IndexConfigLoader.load_indices` loads from database every call

**Impact**:
- Database queries on every signal cycle
- WatchlistItem loads with includes

**Optimization**: Cache loaded indices, invalidate on WatchlistItem changes

---

### **5. Individual Instrument Loads (LOW)**

**Issue**: Individual `Instrument.find_by` queries instead of batching

**Impact**:
- N+1 query pattern potential
- Multiple small queries vs one batch query

**Optimization**: Batch load instruments when possible

---

## 📊 **Query Frequency Analysis**

### **Most Frequent Queries** (from log):
1. `PositionTracker.active` - **23+ times** per cycle
2. `WatchlistItem.exists?` - **10+ times** per cycle
3. `PositionTracker Load (LIMIT 1000)` - **16+ times** per cycle
4. `WatchlistItem Pluck` - **6+ times** per cycle

### **Slowest Queries** (from log):
1. `PositionTracker Load` - **514ms** (worst case)
2. `PositionTracker Load` - **493ms**
3. `PositionTracker Load` - **413ms**
4. `WatchlistItem Exists?` - **79ms**

---

## ✅ **Optimizations Implemented**

### **1. Active Positions Cache (CRITICAL)**

**Created**: `app/services/positions/active_positions_cache.rb`

**Purpose**: Centralized cache for `PositionTracker.active` queries to eliminate redundant database calls

**Features**:
- 5-second TTL cache
- Thread-safe with Mutex
- Includes instrument preloading
- Provides both full records and IDs

**Services Updated** (12 services):
- ✅ `ReconciliationService`
- ✅ `PositionIndex`
- ✅ `PositionTrackerPruner`
- ✅ `RiskManagerService` (4 locations)
- ✅ `PositionHeartbeat`
- ✅ `PositionSyncService`
- ✅ `PnlUpdaterService`
- ✅ `RedisPnlCache`
- ✅ `ActiveCache` (2 locations)
- ✅ `MarketFeedHub`

**Expected Impact**:
- **Before**: 23+ queries per cycle
- **After**: 1 query per 5 seconds
- **Reduction**: ~95% fewer queries

**Usage**:
```ruby
# Get all active trackers (cached)
trackers = Positions::ActivePositionsCache.instance.active_trackers

# Get just IDs (lighter)
ids = Positions::ActivePositionsCache.instance.active_tracker_ids

# Force refresh
Positions::ActivePositionsCache.instance.refresh!

# Check cache stats
stats = Positions::ActivePositionsCache.instance.stats
```

---

### **2. IndexConfigLoader Caching**

**File**: `app/services/index_config_loader.rb`

**Changes**:
- Added 30-second TTL cache for loaded indices
- Cached `watchlist_items_available?` check (60-second TTL)
- Added `clear_cache!` method for invalidation

**Expected Impact**:
- **Before**: Database query on every call
- **After**: Cached for 30 seconds
- **Reduction**: ~90% fewer queries

**Usage**:
```ruby
# Load indices (cached for 30 seconds)
indices = IndexConfigLoader.load_indices

# Clear cache when WatchlistItems change
IndexConfigLoader.instance.clear_cache!
```

---

### **3. Expiry Date Caching**

**File**: `app/services/signal/scheduler.rb`

**Changes**:
- Cache expiry calculations for 1 hour
- Expiry dates don't change frequently (only on new expiry day)
- Cache key based on index keys

**Expected Impact**:
- **Before**: Recalculated every 30 seconds
- **After**: Cached for 1 hour
- **Reduction**: ~120x fewer calculations

---

## 📊 **Performance Metrics**

### **Query Reduction Summary**

| Service                | Before     | After      | Reduction |
| ---------------------- | ---------- | ---------- | --------- |
| PositionTracker.active | 23+/cycle  | 1/5s       | **95%**   |
| WatchlistItem.exists?  | 10+/cycle  | 1/min      | **99%**   |
| IndexConfigLoader      | Every call | Cached 30s | **90%**   |
| Expiry calculations    | Every 30s  | Once/hour  | **120x**  |

**Total Database Load Reduction**: ~80-90%

---

## 🔧 **Cache Invalidation**

### **When to Clear Caches**

**ActivePositionsCache**:
- Automatically refreshes every 5 seconds
- Can be manually cleared with `clear!`
- Should be cleared when positions are created/updated/deleted

**IndexConfigLoader**:
- Automatically refreshes every 30 seconds
- Should call `clear_cache!` when WatchlistItems change

**Expiry Cache**:
- Automatically refreshes every hour
- Can be manually cleared by reinitializing scheduler

---

## ⚠️ **Important Notes**

1. **Cache TTLs**: All caches have TTLs to ensure data freshness
2. **Thread Safety**: ActivePositionsCache uses Mutex for thread safety
3. **Memory**: Caches are in-memory, monitor memory usage
4. **Invalidation**: Manual cache clearing may be needed on data changes

---

## 🧪 **Testing Recommendations**

1. Monitor database query counts in development.log
2. Verify cache hit rates
3. Test cache invalidation on data changes
4. Monitor memory usage
5. Verify correctness after cache refreshes

---

## 📈 **Expected Performance Improvements**

| Optimization              | Current    | After      | Improvement        |
| ------------------------- | ---------- | ---------- | ------------------ |
| PositionTracker queries   | 23+/cycle  | 1/5s       | **95% reduction**  |
| WatchlistItem.exists?     | 10+/cycle  | 1/min      | **99% reduction**  |
| Expiry calculations       | Every 30s  | Once/hour  | **120x reduction** |
| IndexConfigLoader queries | Every call | Cached 30s | **90% reduction**  |

**Total Database Load Reduction**: ~80-90%

---

## 🔧 **Implementation Priority**

1. **High Priority** (Implemented):
   - ✅ Cache active positions (biggest impact)
   - ✅ Cache WatchlistItem availability

2. **Medium Priority** (Implemented):
   - ✅ Cache expiry dates
   - ✅ Cache IndexConfigLoader results

3. **Low Priority** (Future):
   - Batch instrument loads
   - Optimize individual queries

---

## 📝 **Notes**

- All caches should have TTL to ensure data freshness
- Cache invalidation needed on data changes
- Monitor cache hit rates
- Consider Redis for distributed caching if needed
- All optimizations maintain backward compatibility

---

## 📈 **Next Steps**

1. Monitor performance improvements in production
2. Consider Redis caching for distributed systems
3. Add cache metrics/monitoring
4. Fine-tune TTL values based on usage patterns
