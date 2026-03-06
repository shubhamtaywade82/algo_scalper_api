# Expiry Date Filtering Implementation

**Date:** 2025-12-18
**Status:** ✅ Implemented
**Feature:** Skip indices with expiry > 7 days (configurable)

---

## Overview

The system now **filters out indices** where the nearest expiry date is more than 7 days away. This prevents trading in indices with far-away expiries (e.g., monthly BANKNIFTY when expiry is > 7 days).

---

## Implementation

### Location
- **File**: `app/services/signal/scheduler.rb`
- **Method**: `reorder_indices_by_expiry`

### Changes Made

1. **Added Expiry Filtering** (lines 373-385):
   ```ruby
   # Filter out indices with expiry > max_expiry_days (default: 7 days)
   max_expiry_days = get_max_expiry_days
   filtered = indexed_with_expiry.reject do |item|
     if item[:days_to_expiry] > max_expiry_days
       Rails.logger.info(
         "[SignalScheduler] Skipping #{item[:index_cfg][:key]} - expiry in #{item[:days_to_expiry]} days " \
         "(> #{max_expiry_days} days limit)"
       )
       true
     else
       false
     end
   end
   ```

2. **Added Configuration Method** (lines 407-415):
   ```ruby
   def get_max_expiry_days
     config = AlgoConfig.fetch[:signals] || {}
     max_days = config[:max_expiry_days] || 7
     max_days.to_i
   rescue StandardError
     7 # Default to 7 days if config unavailable
   end
   ```

3. **Added Configuration** (`config/algo.yml`):
   ```yaml
   signals:
     max_expiry_days: 7 # Maximum days to expiry (indices with expiry > this will be skipped)
   ```

---

## How It Works

### Processing Flow

1. **Calculate Days to Expiry**:
   - For each index, get the nearest expiry date
   - Calculate `days_to_expiry = (expiry_date - today).to_i`

2. **Filter Indices**:
   - If `days_to_expiry > max_expiry_days` (default: 7), **skip the index**
   - Log a message: `"Skipping BANKNIFTY - expiry in 15 days (> 7 days limit)"`

3. **Sort Remaining Indices**:
   - Sort filtered indices by expiry proximity (closer expiry first)
   - Process indices in this order

### Example

**Scenario:**
- **NIFTY**: Expiry in 2 days ✅ (ALLOWED)
- **SENSEX**: Expiry in 5 days ✅ (ALLOWED)
- **BANKNIFTY**: Expiry in 15 days ❌ (SKIPPED - > 7 days)

**Result:**
- Only NIFTY and SENSEX are processed
- BANKNIFTY is skipped with log message
- Processing order: SENSEX (5d) → NIFTY (2d)

---

## Configuration

### Default Behavior
- **Default**: 7 days
- **Configurable**: Via `config/algo.yml` → `signals.max_expiry_days`

### To Change the Limit

Edit `config/algo.yml`:
```yaml
signals:
  max_expiry_days: 7  # Change to desired limit (e.g., 5, 10, 14)
```

**Examples:**
- `max_expiry_days: 5` → Only trade indices with expiry ≤ 5 days
- `max_expiry_days: 10` → Only trade indices with expiry ≤ 10 days
- `max_expiry_days: 14` → Only trade indices with expiry ≤ 14 days

---

## Logging

### When an Index is Skipped

```
[SignalScheduler] Skipping BANKNIFTY - expiry in 15 days (> 7 days limit)
```

### When Indices are Processed

```
[SignalScheduler] Processing order (by expiry proximity): SENSEX: 2025-12-23 (5d) → NIFTY: 2025-12-20 (2d)
```

---

## Benefits

1. **Prevents Far-Expiry Trading**: Avoids trading in monthly expiries when they're too far away
2. **Focuses on Near Expiry**: Prioritizes weekly expiries (NIFTY/SENSEX) when BANKNIFTY expiry is far
3. **Configurable**: Can adjust the limit based on trading strategy
4. **Clear Logging**: Easy to see which indices are being skipped and why

---

## Edge Cases

### Missing Expiry Data
- If expiry cannot be determined: Index is **not filtered** (uses default priority)
- Logs warning: `"No expiry list for #{index_key} - using default priority"`

### Invalid Expiry Dates
- If expiry parsing fails: Index is **not filtered** (uses default priority)
- Logs warning: `"Error calculating expiry for #{index_key}"`

### Configuration Missing
- If `max_expiry_days` not in config: Defaults to **7 days**
- If config unavailable: Defaults to **7 days**

---

## Testing

To verify the filter is working:

1. **Check Logs**:
   ```bash
   tail -f log/development.log | grep "Skipping.*expiry"
   ```

2. **Verify Configuration**:
   ```ruby
   config = AlgoConfig.fetch
   puts config.dig(:signals, :max_expiry_days)  # Should show 7 (or configured value)
   ```

3. **Monitor Processing**:
   - Watch for log messages indicating indices are being skipped
   - Verify only indices with expiry ≤ 7 days are processed

---

## Summary

✅ **Implemented**: Expiry date filtering now prevents trading in indices with expiry > 7 days
✅ **Configurable**: Can adjust limit via `signals.max_expiry_days` in `config/algo.yml`
✅ **Logged**: Clear log messages when indices are skipped
✅ **Default**: 7 days (matches requirement)
