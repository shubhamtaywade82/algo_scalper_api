# Unified Index Configuration - Single Source of Truth

**Date**: Current
**Status**: ✅ Implemented
**Feature**: Consolidated index loading from WatchlistItems (database) and algo.yml into a single service

---

## 🎯 **Problem**

Previously, indices were loaded from two different sources:
1. **`algo.yml` config file** - Used by `Signal::Scheduler` and other services
2. **`WatchlistItems` database table** - Used by `MarketFeedHub` for WebSocket subscriptions

This created inconsistency and duplication.

---

## ✅ **Solution**

Created `IndexConfigLoader` service that:
- **Prefers WatchlistItems** (database) as the source of truth
- **Merges with algo.yml** config to get full configuration (strategies, risk settings, etc.)
- **Falls back to algo.yml** if no WatchlistItems exist
- **Provides unified API** for all services

---

## 📝 **Implementation**

### **New Service: `IndexConfigLoader`**

**Location**: `app/services/index_config_loader.rb`

**Key Methods**:
- `IndexConfigLoader.load_indices` - Public class method to load indices
- `load_from_watchlist_items` - Loads from database, merges with algo.yml
- `load_from_config` - Fallback to algo.yml
- `build_index_config_from_watchlist_item` - Converts WatchlistItem to index config format

### **How It Works**

1. **Check WatchlistItems**:
   - Loads active `WatchlistItem` records with `kind: :index_value`
   - Gets instrument from polymorphic `watchable` association
   - Extracts `key` (symbol_name), `segment`, `security_id`

2. **Merge with algo.yml**:
   - Finds matching config from `algo.yml` by:
     - Exact key match (e.g., "NIFTY")
     - Segment + security_id match
   - Merges WatchlistItem identity (segment, sid) with algo.yml config (strategies, risk, etc.)

3. **Fallback**:
   - If no WatchlistItems exist, uses `algo.yml` directly
   - If WatchlistItem has no matching algo.yml config, uses minimal config

### **Index Config Format**

The service returns index configs in the same format as `algo.yml`:

```ruby
{
  key: "NIFTY",
  segment: "IDX_I",
  sid: "13",
  capital_alloc_pct: 0.30,
  max_same_side: 1,
  cooldown_sec: 180,
  direction: :bullish,
  premium_band: { min: 30, max: 120 },
  strategies: { ... },
  risk_model: { ... },
  # ... all other algo.yml config
}
```

---

## 🔄 **Updated Services**

All services now use `IndexConfigLoader.load_indices` instead of `AlgoConfig.fetch[:indices]`:

1. ✅ **Signal::Scheduler** - Main signal generation loop
2. ✅ **Signal::IndexSelector** - Index selection by trend score
3. ✅ **Options::DerivativeChainAnalyzer** - Option chain analysis
4. ✅ **Options::StrikeSelector** - Strike selection
5. ✅ **Positions::MetadataResolver** - Position metadata resolution
6. ✅ **Trading::AdminActions** - Admin actions
7. ✅ **TradingSystem::SignalScheduler** - Trading system scheduler

---

## 📊 **Benefits**

1. **Single Source of Truth**: WatchlistItems (database) is the primary source
2. **Consistency**: All services use the same index list
3. **Flexibility**: Can add/remove indices via database without editing config file
4. **Backward Compatible**: Falls back to algo.yml if no WatchlistItems exist
5. **Full Configuration**: Merges database identity with algo.yml settings

---

## 🔧 **Usage**

### **Before**:
```ruby
indices = Array(AlgoConfig.fetch[:indices])
```

### **After**:
```ruby
indices = IndexConfigLoader.load_indices
```

**No other changes needed** - the format is identical!

---

## 📋 **Migration Path**

### **Option 1: Use WatchlistItems (Recommended)**

1. Ensure `WatchlistItems` are seeded (via `db/seeds.rb`)
2. The system will automatically use WatchlistItems
3. Keep `algo.yml` for configuration (strategies, risk, etc.)

### **Option 2: Continue Using algo.yml**

1. If no WatchlistItems exist, system falls back to `algo.yml`
2. No changes needed - works as before

### **Option 3: Hybrid**

1. Use WatchlistItems for index list (add/remove via database)
2. Use algo.yml for per-index configuration
3. System automatically merges both

---

## 🧪 **Testing**

To verify the implementation:

1. **Check logs** for index loading:
   ```
   [IndexConfigLoader] Loaded X indices from WatchlistItems
   ```

2. **Verify indices** are loaded correctly:
   ```ruby
   IndexConfigLoader.load_indices
   # => [{ key: "NIFTY", segment: "IDX_I", sid: "13", ... }, ...]
   ```

3. **Test fallback** by temporarily disabling WatchlistItems:
   - System should fall back to algo.yml

---

## 📝 **Notes**

- **WatchlistItems** must have `kind: :index_value` to be included
- **WatchlistItems** must be `active: true` to be included
- **Matching** with algo.yml is done by key (symbol_name) or segment+sid
- **If no match** found in algo.yml, uses minimal config (key, segment, sid only)
- **All services** now use the same unified source

---

## 🎯 **Summary**

✅ **Implemented**: Unified index configuration loader
✅ **Source**: WatchlistItems (database) preferred, algo.yml fallback
✅ **Format**: Same as algo.yml (backward compatible)
✅ **Updated**: All 7 services now use unified loader
✅ **Benefits**: Single source of truth, consistency, flexibility

The system now has a single place to manage indices, with WatchlistItems as the source of truth and algo.yml providing configuration details.


