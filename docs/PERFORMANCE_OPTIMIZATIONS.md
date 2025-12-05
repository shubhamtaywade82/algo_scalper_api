# Performance Optimizations - Development Log Analysis

**Date**: Current
**Analysis**: Based on development.log patterns
**Status**: Identified optimization opportunities

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

## ✅ **Recommended Optimizations**

### **Priority 1: Cache Active Positions**

**Problem**: Multiple services query `PositionTracker.active` independently

**Solution**: Create shared cache service

```ruby
# app/services/positions/active_positions_cache.rb
class Positions::ActivePositionsCache
  include Singleton

  CACHE_TTL = 5.seconds

  def active_trackers
    return @cached_trackers if cached?
    refresh!
    @cached_trackers
  end

  def refresh!
    @cached_trackers = PositionTracker.active.includes(:instrument).to_a
    @cached_at = Time.current
  end

  private

  def cached?
    @cached_at && (Time.current - @cached_at) < CACHE_TTL
  end
end
```

**Usage**: Replace all `PositionTracker.active` calls with `ActivePositionsCache.instance.active_trackers`

**Services to Update**:
- `ReconciliationService`
- `PositionIndex`
- `RiskManagerService`
- `PositionTrackerPruner`

**Expected Impact**: Reduce 23+ queries to 1 query per 5 seconds

---

### **Priority 2: Cache WatchlistItem Availability**

**Problem**: `WatchlistItem.exists?` called repeatedly

**Solution**: Cache in IndexConfigLoader

```ruby
# In IndexConfigLoader
@watchlist_available = nil
@watchlist_checked_at = nil

def watchlist_items_available?
  return @watchlist_available if @watchlist_checked_at &&
                                 (Time.current - @watchlist_checked_at) < 60.seconds

  @watchlist_available = check_watchlist_available
  @watchlist_checked_at = Time.current
  @watchlist_available
end
```

**Expected Impact**: Reduce 10+ queries to 1 query per minute

---

### **Priority 3: Cache Expiry Dates**

**Problem**: Expiry dates recalculated every 30 seconds

**Solution**: Cache expiry calculation results

```ruby
# In Signal::Scheduler
@expiry_cache = {}
@expiry_cache_ttl = 1.hour

def reorder_indices_by_expiry(indices)
  # Check cache first
  cache_key = indices.map { |i| i[:key] }.join(',')
  if @expiry_cache[cache_key] &&
     (Time.current - @expiry_cache[cache_key][:cached_at]) < @expiry_cache_ttl
    return @expiry_cache[cache_key][:sorted_indices]
  end

  # Calculate and cache
  sorted = calculate_expiry_order(indices)
  @expiry_cache[cache_key] = {
    sorted_indices: sorted,
    cached_at: Time.current
  }
  sorted
end
```

**Expected Impact**: Reduce API calls from every 30s to once per hour

---

### **Priority 4: Cache IndexConfigLoader Results**

**Problem**: Indices loaded from database every call

**Solution**: Cache loaded indices

```ruby
# In IndexConfigLoader
@cached_indices = nil
@cached_at = nil
CACHE_TTL = 30.seconds

def load_indices
  return @cached_indices if cached?

  @cached_indices = load_from_source
  @cached_at = Time.current
  @cached_indices
end
```

**Expected Impact**: Reduce database queries significantly

---

## 📈 **Expected Performance Improvements**

| Optimization | Current | After | Improvement |
|--------------|---------|-------|-------------|
| PositionTracker queries | 23+/cycle | 1/5s | **95% reduction** |
| WatchlistItem.exists? | 10+/cycle | 1/min | **99% reduction** |
| Expiry calculations | Every 30s | Once/hour | **120x reduction** |
| IndexConfigLoader queries | Every call | Cached 30s | **90% reduction** |

**Total Database Load Reduction**: ~80-90%

---

## 🔧 **Implementation Priority**

1. **High Priority** (Implement First):
   - ✅ Cache active positions (biggest impact)
   - ✅ Cache WatchlistItem availability

2. **Medium Priority**:
   - ✅ Cache expiry dates
   - ✅ Cache IndexConfigLoader results

3. **Low Priority**:
   - Batch instrument loads
   - Optimize individual queries

---

## 📝 **Notes**

- All caches should have TTL to ensure data freshness
- Cache invalidation needed on data changes
- Monitor cache hit rates
- Consider Redis for distributed caching if needed

