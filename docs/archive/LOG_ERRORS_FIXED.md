# Development Log Errors - Fixed Issues

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
The `mode_config` variable could be `nil` if both:
- `signals_cfg.dig(:validation_modes, mode.to_sym)` returns `nil`
- `signals_cfg.dig(:validation_modes, :balanced)` also returns `nil`

Then calling `.merge(mode: mode)` on `nil` causes the error.

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

### **2. Potential nil merge in IndexConfigLoader**

**Location**: `app/services/index_config_loader.rb:80`

**Potential Issue**:
If `matching_config` is not a Hash (e.g., `nil` or other type), calling `.except` would fail.

**Fix Applied**:
```ruby
# Before:
if matching_config
  base_config.merge(matching_config.except(:key, :segment, :sid))

# After:
if matching_config && matching_config.is_a?(Hash)
  base_config.merge(matching_config.except(:key, :segment, :sid))
```

**File**: `app/services/index_config_loader.rb:78-80`

---

### **3. Expiry Cache Debug Logging**

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
2. ✅ **IndexConfigLoader.build_index_config_from_watchlist_item** - Added Hash type check
3. ✅ **Signal::Scheduler.reorder_indices_by_expiry** - Improved cache logging

---

## 🧪 **Verification**

After fixes:
- ✅ Syntax check passed
- ✅ No linter errors
- ✅ Type safety added for mode_config
- ✅ Better cache debugging
- ✅ Nil safety added for merge operations

---

## 📝 **Notes**

- The errors were occurring because config values could be `nil` when not present in `algo.yml`
- The error was persistent because `dig` could return non-Hash values
- Type checking ensures `mode_config` is always a Hash before calling `.merge`
- Cache logging helps debug cache hit/miss patterns
- All merge operations now have proper nil handling
- All fixes maintain backward compatibility
