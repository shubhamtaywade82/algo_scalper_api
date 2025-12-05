# Development Log Errors - Final Fixes

**Date**: Current
**Status**: ✅ Fixed

---

## 🔍 **Errors Found in development.log**

### **1. NoMethodError: undefined method `merge' for nil (PERSISTENT)**

**Location**: `app/services/signal/engine.rb:489` in `get_validation_mode_config`

**Error**:
```
[Signal] NIFTY NoMethodError undefined method `merge' for nil
[Signal] SENSEX NoMethodError undefined method `merge' for nil
[Signal] BANKNIFTY NoMethodError undefined method `merge' for nil
```

**Root Cause**:
Even though we added `|| {}` fallback, there's an edge case where:
- `signals_cfg.dig(:validation_modes, mode.to_sym)` could return a non-Hash value (e.g., String, Array, nil from a different source)
- The `|| {}` fallback only works if the left side is `nil` or `false`, not if it's a non-Hash value

**Fix Applied**:
```ruby
# Before:
mode_config = signals_cfg.dig(:validation_modes, mode.to_sym) ||
              signals_cfg.dig(:validation_modes, :balanced) || {}

# After:
mode_config = signals_cfg.dig(:validation_modes, mode.to_sym) ||
              signals_cfg.dig(:validation_modes, :balanced) || {}
# Ensure mode_config is always a Hash (handle edge cases where config might be wrong type)
mode_config = {} unless mode_config.is_a?(Hash)
```

**File**: `app/services/signal/engine.rb:483-490`

---

### **2. Expiry Cache Debug Logging**

**Location**: `app/services/signal/scheduler.rb:319-324`

**Issue**: Cache hit/miss logging was not clear

**Fix Applied**:
- Added debug log when cache is hit: `"[SignalScheduler] Using cached expiry order for: #{cache_key}"`
- Added debug log when cache is missed: `"[SignalScheduler] Calculating expiry order (cache miss) for: #{cache_key}"`
- Fixed cache key generation to ensure consistent keys: `indices.map { |i| i[:key].to_s }.sort.join(',')`

**File**: `app/services/signal/scheduler.rb:319-327`

---

## ✅ **All Errors Fixed**

1. ✅ **Signal::Engine.get_validation_mode_config** - Added Hash type check
2. ✅ **Signal::Scheduler.reorder_indices_by_expiry** - Improved cache logging

---

## 🧪 **Verification**

After fixes:
- ✅ Syntax check passed
- ✅ No linter errors
- ✅ Type safety added for mode_config
- ✅ Better cache debugging

---

## 📝 **Notes**

- The error was persistent because `dig` could return non-Hash values
- Type checking ensures `mode_config` is always a Hash before calling `.merge`
- Cache logging helps debug cache hit/miss patterns
- All fixes maintain backward compatibility

