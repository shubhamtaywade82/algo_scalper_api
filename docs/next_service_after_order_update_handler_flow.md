# Next Service After OrderUpdateHandler - Complete Flow Analysis

## 📋 **Current Flow After OrderUpdateHandler**

After `OrderUpdateHandler` updates `PositionTracker`, the following happens:

### **Automatic Callbacks** (Not a "service" - automatic):

1. `PositionTracker.cleanup_if_exited` → `PositionIndex.remove(...)`
2. `PositionTracker.clear_redis_cache_if_exited` → `RedisPnlCache.delete(...)`
3. `PositionTracker.refresh_index_if_relevant` → `PositionIndex.update(...)`

**These are callbacks, not services that get "called next".**

---

## 🔄 **What Actually Gets Called Next?**

`OrderUpdateHandler` is **asynchronous** - it's triggered by WebSocket updates. After it updates `PositionTracker`, there isn't a direct "next service" that gets invoked.

However, the **next service that would process the updated position** is:

## 🎯 **Live::RiskManagerService**

### **Why RiskManagerService?**

`RiskManagerService` runs in a **continuous monitoring loop** (`monitor_loop`) that:
1. Fetches all active positions
2. Updates their PnL
3. Enforces risk rules
4. Triggers exits if needed

**After OrderUpdateHandler updates a position**:
- The position status changes (exited/active/cancelled)
- `RiskManagerService` will pick up this change in its **next monitoring cycle**
- It will process the updated position accordingly

### **Flow**

```
OrderUpdateHandler.handle_update(payload)
    ↓
PositionTracker.mark_exited!(exit_price: avg_price)
    ↓
[PositionTracker callbacks fire automatically]
    ↓
[Next RiskManagerService.monitor_loop cycle]
    ↓
RiskManagerService processes updated positions  ⬅️ NEXT SERVICE
```

---

## 📊 **RiskManagerService Monitoring Cycle**

`RiskManagerService` runs continuously and:
1. **Fetches active positions** - Will see updated status from OrderUpdateHandler
2. **Updates PnL** - For positions that are still active
3. **Enforces risk rules** - Checks limits, drawdowns, etc.
4. **Triggers exits** - If needed (but OrderUpdateHandler already marked as exited)

**Key Point**: `RiskManagerService` doesn't get "called" by OrderUpdateHandler - it runs independently and will process the updated position in its next cycle.

---

## 🔄 **Alternative: PositionSyncService**

`PositionSyncService` is another service that runs periodically (every 30 seconds) and:
- Syncs positions between DhanHQ and database
- Marks orphaned positions as exited
- Creates trackers for untracked positions

**But**: This is also periodic, not directly called by OrderUpdateHandler.

---

## 🎯 **Answer: No Direct "Next Service"**

After `OrderUpdateHandler` completes:
- ✅ PositionTracker is updated (via callbacks)
- ✅ PositionIndex is updated (via callbacks)
- ✅ Redis cache is cleared (via callbacks)
- ⚠️ **No service is directly called next**

The **next service that will process the updated position** is:
- **`Live::RiskManagerService`** - In its next monitoring cycle
- **`Live::PositionSyncService`** - In its next sync cycle (if applicable)

---

## 📋 **Summary**

**Question**: "Which is the next inline service after OrderUpdateHandler?"

**Answer**: There isn't a direct "next service" - OrderUpdateHandler is asynchronous and updates PositionTracker via callbacks.

**The next service that will process the updated position**:
- **`Live::RiskManagerService`** - In its continuous monitoring loop (most relevant)
- **`Live::PositionSyncService`** - In its periodic sync cycle (less relevant for OrderUpdateHandler flow)

**Recommendation**: If you want to continue reviewing services in the trading flow, the next logical service would be **`Live::RiskManagerService`** (but we already reviewed it). After that, the next services would be:
- `Live::PositionSyncService` (periodic sync)
- `Live::PnlUpdaterService` (PnL updates)
- `Live::TrailingEngine` (trailing stops)
- `Live::ExitEngine` (already reviewed)
