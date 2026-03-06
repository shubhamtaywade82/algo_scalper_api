# Expiry-Based Prioritization Implementation

**Date**: Current
**Status**: ✅ Implemented
**Feature**: Indices are now processed in order of expiry proximity (closer expiry = processed first)

---

## 🎯 **What Was Implemented**

### **Feature**
The `Signal::Scheduler` now automatically reorders indices based on their nearest expiry date before processing. Indices with closer expiry dates are processed first.

### **Behavior**
- **Before**: Indices processed in config order (NIFTY → BANKNIFTY → SENSEX)
- **After**: Indices processed by expiry proximity (closest expiry first)

**Example**:
- If NIFTY expiry is in **2 days** and BANKNIFTY expiry is in **15 days**, NIFTY will be processed first
- If SENSEX expiry is in **1 day**, NIFTY in **3 days**, and BANKNIFTY in **20 days**, order will be: SENSEX → NIFTY → BANKNIFTY

---

## 📝 **Implementation Details**

### **File Modified**
- `app/services/signal/scheduler.rb`

### **Changes**

1. **Added `reorder_indices_by_expiry` method** (lines 312-378):
   - Calculates days-to-expiry for each index
   - Sorts indices by expiry proximity (ascending - closer first)
   - Logs the processing order for debugging
   - Handles errors gracefully (defaults to 999 days if expiry can't be determined)

2. **Modified main processing loop** (line 55):
   - Calls `reorder_indices_by_expiry(indices)` before processing
   - Processes indices in expiry-proximity order

### **Key Logic**

```ruby
def reorder_indices_by_expiry(indices)
  # For each index:
  # 1. Get instrument from cache
  # 2. Get expiry_list from instrument
  # 3. Parse expiry dates
  # 4. Find nearest expiry >= today
  # 5. Calculate days_to_expiry
  # 6. Sort by days_to_expiry (ascending)
  # 7. Return sorted index configs
end
```

### **Error Handling**
- If instrument not found: Uses default priority (999 days)
- If expiry list empty: Uses default priority (999 days)
- If parsing fails: Uses default priority (999 days)
- All errors are logged as warnings, processing continues

---

## 🔍 **How It Works**

### **Step-by-Step**

1. **At start of each cycle** (every 30 seconds):
   ```ruby
   ordered_indices = reorder_indices_by_expiry(indices)
   ```

2. **For each index**, calculate expiry:
   - Fetch instrument via `IndexInstrumentCache`
   - Get `expiry_list` from instrument
   - Parse expiry dates (handles Date, Time, String formats)
   - Find nearest expiry >= today
   - Calculate `days_to_expiry = (nearest_expiry - today).to_i`

3. **Sort indices**:
   - Sort by `days_to_expiry` (ascending)
   - Closer expiry = lower number = processed first

4. **Log processing order**:
   ```
   [SignalScheduler] Processing order (by expiry proximity):
   NIFTY: 2024-01-15 (2d) → SENSEX: 2024-01-18 (5d) → BANKNIFTY: 2024-01-30 (17d)
   ```

5. **Process in sorted order**:
   - Process indices with closer expiry first
   - 5 second delay between each index

---

## 📊 **Example Scenarios**

### **Scenario 1: Weekly Expiries Closer**
- **NIFTY**: Weekly expiry in 2 days
- **SENSEX**: Weekly expiry in 5 days
- **BANKNIFTY**: Monthly expiry in 18 days

**Processing Order**: NIFTY → SENSEX → BANKNIFTY

### **Scenario 2: BANKNIFTY Close to Expiry**
- **BANKNIFTY**: Monthly expiry in 1 day (close to expiry)
- **NIFTY**: Weekly expiry in 3 days
- **SENSEX**: Weekly expiry in 6 days

**Processing Order**: BANKNIFTY → NIFTY → SENSEX

### **Scenario 3: All Far Expiry**
- **NIFTY**: Weekly expiry in 6 days
- **BANKNIFTY**: Monthly expiry in 20 days
- **SENSEX**: Weekly expiry in 7 days

**Processing Order**: NIFTY → SENSEX → BANKNIFTY

---

## ✅ **Benefits**

1. **Prioritizes Urgent Expiries**: Indices with expiries < 7 days get processed first
2. **Better Capital Utilization**: Focuses on near-term opportunities
3. **Automatic Reordering**: No manual config changes needed
4. **Dynamic**: Recalculates every cycle (30 seconds), adapts to changing expiry dates
5. **Graceful Degradation**: Falls back to config order if expiry calculation fails

---

## 🔧 **Configuration**

**No configuration needed** - this feature is always active.

The system automatically:
- Calculates expiry for each index every cycle
- Reorders based on proximity
- Processes in optimal order

---

## 📝 **Logging**

The implementation logs the processing order at debug level:

```
[SignalScheduler] Processing order (by expiry proximity):
NIFTY: 2024-01-15 (2d) → SENSEX: 2024-01-18 (5d) → BANKNIFTY: 2024-01-30 (17d)
```

This helps verify the ordering is working correctly.

---

## 🧪 **Testing**

To verify the implementation:

1. **Check logs** for processing order messages
2. **Monitor** which index is processed first in each cycle
3. **Verify** that indices with closer expiry are processed before those with farther expiry

---

## 🎯 **Summary**

✅ **Implemented**: Expiry-based prioritization
✅ **Behavior**: Closer expiry = processed first
✅ **Automatic**: No config needed
✅ **Dynamic**: Recalculates every cycle
✅ **Robust**: Handles errors gracefully

The system now prioritizes indices with closer expiry dates, ensuring urgent opportunities (near expiry) are processed before those with more time remaining.


