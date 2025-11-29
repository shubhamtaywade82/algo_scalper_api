# Next Service After OrderUpdateHandler

## 📋 **Flow After OrderUpdateHandler**

After `OrderUpdateHandler` updates `PositionTracker` (via `mark_exited!`, `mark_active!`, `mark_cancelled!`), the following happens:

### **1. PositionTracker Callbacks** (Automatic)

`PositionTracker` has several callbacks that fire automatically:

```ruby
after_commit :register_in_index, on: %i[create update]
after_commit :unregister_from_index, on: :destroy
after_update_commit :refresh_index_if_relevant
after_update_commit :cleanup_if_exited
after_update_commit :clear_redis_cache_if_exited
```

**These callbacks update**:
- `Live::PositionIndex` - In-memory index of active positions
- Redis PnL cache (cleared when exited)

---

## 🎯 **Next Service: Live::PositionIndex**

### **Purpose**

`Live::PositionIndex` is an **in-memory index** that tracks active positions by `security_id`. It's updated automatically via `PositionTracker` callbacks.

**Key Features**:
- Fast lookups: `security_id` → Array of tracker metadata
- Used by `RiskManagerService` for efficient position queries
- Thread-safe (uses `Concurrent::Map` and `Concurrent::Array`)

### **Flow**

```
OrderUpdateHandler.handle_update(payload)
    ↓
PositionTracker.mark_exited!(exit_price: avg_price)
    ↓
PositionTracker.save! (commits transaction)
    ↓
after_update_commit :cleanup_if_exited
    ↓
PositionTracker.cleanup_if_exited
    ↓
Live::PositionIndex.remove(tracker.id, tracker.security_id)  ⬅️ NEXT SERVICE
```

---

## 📊 **PositionIndex Details**

### **Architecture**

- **Pattern**: Singleton with in-memory index
- **Data Structure**: `Concurrent::Map` (security_id → Concurrent::Array of metadata)
- **Thread Safety**: Uses `Concurrent::Map` and `Monitor` for synchronization

### **Key Methods**

1. **`add(metadata)`** - Adds tracker metadata to index
2. **`remove(tracker_id, security_id)`** - Removes tracker from index
3. **`update(metadata)`** - Updates tracker metadata
4. **`trackers_for(security_id)`** - Returns all trackers for a security_id
5. **`bulk_load_active!`** - Loads all active positions from DB on startup

### **Metadata Structure**

```ruby
{
  id: tracker.id,
  security_id: tracker.security_id,
  entry_price: tracker.entry_price.to_s,
  quantity: tracker.quantity.to_i,
  segment: tracker.segment
}
```

---

## 🔄 **Complete Flow After OrderUpdateHandler**

```
OrderUpdateHandler.handle_update(payload)
    ↓
PositionTracker.mark_exited!(exit_price: avg_price)
    ↓
PositionTracker.save! (commits transaction)
    ↓
after_update_commit callbacks:
    ├─ cleanup_if_exited
    │   └─ Live::PositionIndex.remove(...)  ⬅️ NEXT SERVICE
    ├─ clear_redis_cache_if_exited
    │   └─ Live::RedisPnlCache.delete(...)
    └─ refresh_index_if_relevant
        └─ Live::PositionIndex.update(...)  ⬅️ NEXT SERVICE
```

---

## 📋 **PositionIndex Status**

### **Current State**: ✅ **Stable**

- ✅ Well-designed (thread-safe, efficient)
- ✅ Used by `RiskManagerService` for position lookups
- ✅ Updated automatically via callbacks
- ✅ Has `bulk_load_active!` for startup

### **Potential Issues**:

1. ⚠️ **No explicit paper mode handling** - But should work fine (just indexes by security_id)
2. ⚠️ **No specs** - Needs comprehensive test coverage
3. ⚠️ **No health monitoring** - Could add metrics

---

## 🎯 **Recommendation**

**Next Service to Review**: `Live::PositionIndex`

**Why**:
- Directly updated by `PositionTracker` callbacks after `OrderUpdateHandler`
- Critical for `RiskManagerService` performance
- Simple, focused service (good candidate for review)
- No specs currently (needs test coverage)

**Review Focus**:
1. Verify thread safety
2. Verify paper mode compatibility
3. Add comprehensive specs
4. Verify callback integration

---

## 📊 **Alternative: Positions::ActiveCache**

**Note**: `Positions::ActiveCache` is another service that tracks positions, but it's:
- Updated manually (not via callbacks)
- More complex (handles LTP updates, SL/TP triggers)
- Used by different parts of the system

**PositionIndex** is the more direct next service after OrderUpdateHandler.
