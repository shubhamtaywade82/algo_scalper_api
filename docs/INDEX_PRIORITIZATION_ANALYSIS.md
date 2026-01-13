# Index Prioritization & Expiry Selection Analysis

**Date**: Current
**Question**: Does the codebase prioritize NIFTY/SENSEX (weekly expiry) over BANKNIFTY (monthly expiry), especially when BANKNIFTY expiry is close to 1 week?

---

## 🔍 **Current Implementation Analysis**

### **1. Index Processing Order**

**Location**: `app/services/signal/scheduler.rb:55-65`

```ruby
indices.each_with_index do |idx_cfg, idx|
  break unless @running

  sleep(idx.zero? ? 0 : INTER_INDEX_DELAY)  # 5 second delay between indices
  process_index(idx_cfg)
end
```

**Current Behavior**:
- Indices are processed **sequentially** in the order they appear in `config/algo.yml`
- **No prioritization logic** based on expiry type (weekly vs monthly)
- **No dynamic reordering** based on expiry proximity

**Config Order** (`config/algo.yml`):
1. **NIFTY** (first - processed immediately)
2. **BANKNIFTY** (second - processed after 5 second delay)
3. **SENSEX** (third - processed after another 5 second delay)

---

### **2. Expiry Selection Logic**

**Location**: `app/services/options/derivative_chain_analyzer.rb:84-107`

```ruby
def find_nearest_expiry
  instrument = IndexInstrumentCache.instance.get_or_fetch(@index_cfg)
  return nil unless instrument

  expiry_list = instrument.expiry_list
  return nil unless expiry_list&.any?

  today = Time.zone.today
  parsed = expiry_list.compact.filter_map do |raw|
    # Parse expiry dates...
  end

  next_expiry = parsed.select { |date| date >= today }.min  # Simply picks first expiry >= today
  next_expiry&.strftime('%Y-%m-%d')
end
```

**Current Behavior**:
- ✅ Picks the **nearest expiry** (first expiry date >= today)
- ❌ **NO logic** to prefer weekly expiry over monthly expiry
- ❌ **NO logic** to consider days-to-expiry
- ❌ **NO logic** to prioritize indices based on expiry proximity

**For Each Index**:
- **NIFTY**: Picks nearest weekly expiry (typically 0-7 days)
- **SENSEX**: Picks nearest weekly expiry (typically 0-7 days)
- **BANKNIFTY**: Picks nearest monthly expiry (typically 0-30 days)

---

### **3. Expiry Type Awareness**

**Location**: `app/services/options/expired_fetcher.rb:78-88`

```ruby
def normalize_expiry_flag(symbol, requested_flag)
  return requested_flag if requested_flag.to_s.upcase == 'MONTH'

  sym = symbol.to_s.upcase
  # Only NIFTY and SENSEX support weekly expiries; BANKNIFTY is monthly-only
  if %w[NIFTY SENSEX].include?(sym)
    'WEEK'
  else
    'MONTH'
  end
end
```

**Note**: This logic is **ONLY used for fetching historical expired options data**, NOT for live trading or prioritization.

---

## ❌ **Answer: NO Prioritization Based on Expiry**

### **Current State**

1. **Index Processing**: Sequential order (NIFTY → BANKNIFTY → SENSEX)
   - No expiry-based reordering
   - No dynamic prioritization

2. **Expiry Selection**: Nearest expiry for each index
   - NIFTY: Nearest weekly expiry (0-7 days typically)
   - SENSEX: Nearest weekly expiry (0-7 days typically)
   - BANKNIFTY: Nearest monthly expiry (0-30 days typically)

3. **No Expiry-Based Logic**:
   - ❌ Does NOT prioritize weekly expiry indices
   - ❌ Does NOT deprioritize BANKNIFTY when expiry is far (>1 week)
   - ❌ Does NOT prioritize BANKNIFTY when expiry is close (<1 week)
   - ❌ Does NOT consider days-to-expiry in index selection

---

## 📊 **What Actually Happens**

### **Signal Generation Cycle** (every 30 seconds):

```
1. Process NIFTY
   └─ Find nearest expiry (e.g., weekly expiry in 3 days)
   └─ Generate signal for that expiry
   └─ Wait 5 seconds

2. Process BANKNIFTY
   └─ Find nearest expiry (e.g., monthly expiry in 15 days)
   └─ Generate signal for that expiry
   └─ Wait 5 seconds

3. Process SENSEX
   └─ Find nearest expiry (e.g., weekly expiry in 5 days)
   └─ Generate signal for that expiry
   └─ Wait 5 seconds

4. Sleep 30 seconds, repeat
```

**Key Points**:
- All indices are processed **equally** (same delay, same priority)
- Each index uses its **nearest expiry** (regardless of type)
- **No expiry-based filtering or prioritization**

---

## 🎯 **If You Want Expiry-Based Prioritization**

To implement the requested behavior (prioritize NIFTY/SENSEX when BANKNIFTY expiry > 1 week), you would need to:

### **Option 1: Dynamic Index Reordering**

Modify `Signal::Scheduler` to reorder indices based on expiry proximity:

```ruby
def reorder_indices_by_expiry(indices)
  indices.map do |idx_cfg|
    instrument = IndexInstrumentCache.instance.get_or_fetch(idx_cfg)
    expiry_list = instrument.expiry_list
    nearest_expiry = expiry_list&.select { |d| Date.parse(d.to_s) >= Date.today }&.min
    days_to_expiry = nearest_expiry ? (Date.parse(nearest_expiry.to_s) - Date.today).to_i : 999

    {
      index_cfg: idx_cfg,
      days_to_expiry: days_to_expiry,
      is_weekly: %w[NIFTY SENSEX].include?(idx_cfg[:key].to_s.upcase)
    }
  end.sort_by do |idx|
    # Prioritize weekly expiry indices (NIFTY/SENSEX)
    # Prioritize indices with expiry < 7 days
    priority = 0
    priority += 100 if idx[:is_weekly]  # Weekly expiry bonus
    priority += 50 if idx[:days_to_expiry] < 7  # Close expiry bonus
    priority -= idx[:days_to_expiry]  # Closer expiry = higher priority
    -priority  # Negative for descending sort
  end.map { |idx| idx[:index_cfg] }
end
```

### **Option 2: Skip BANKNIFTY When Expiry > 1 Week**

Modify `process_index` to skip BANKNIFTY if expiry is far:

```ruby
def process_index(index_cfg)
  # Skip BANKNIFTY if expiry is > 7 days away
  if index_cfg[:key].to_s.upcase == 'BANKNIFTY'
    instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
    expiry_list = instrument.expiry_list
    nearest_expiry = expiry_list&.select { |d| Date.parse(d.to_s) >= Date.today }&.min
    days_to_expiry = nearest_expiry ? (Date.parse(nearest_expiry.to_s) - Date.today).to_i : 999

    if days_to_expiry > 7
      Rails.logger.debug("[SignalScheduler] Skipping BANKNIFTY - expiry in #{days_to_expiry} days (> 7 days)")
      return
    end
  end

  Signal::Engine.run_for(index_cfg)
end
```

### **Option 3: Use IndexSelector for Dynamic Selection**

If `enable_trend_scorer: true` and using `IndexSelector`, you could add expiry-based tie-breakers:

```ruby
# In Signal::IndexSelector.apply_tie_breakers
def break_tie_by_expiry(candidates, current_best)
  # Prefer weekly expiry indices (NIFTY/SENSEX)
  # Prefer indices with expiry < 7 days
  # ...
end
```

---

## 📝 **Summary**

**Current Implementation**:
- ❌ **NO expiry-based prioritization**
- ✅ Processes indices in config order (NIFTY → BANKNIFTY → SENSEX)
- ✅ Each index uses nearest expiry (weekly for NIFTY/SENSEX, monthly for BANKNIFTY)
- ❌ **NO logic** to prioritize weekly expiry indices
- ❌ **NO logic** to deprioritize BANKNIFTY when expiry is far

**To Answer Your Question**:
> "Is the current code base giving high priority to NIFTY and SENSEX as these have weekly expiries and next BANK NIFTY only when the expiry is close to 1 week?"

**Answer**: **NO** - The current codebase does NOT implement this logic. All indices are processed equally in config order, regardless of expiry type or proximity.

