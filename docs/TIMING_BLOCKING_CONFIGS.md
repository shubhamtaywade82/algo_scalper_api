# Timing-Based Blocking Configurations

**Date**: 2026-01-13
**Purpose**: List all timing-related configurations that can block trading entries

---

## 📊 **Summary: 6 Timing-Based Blocking Mechanisms**

There are **6 different timing-based configurations** that can block trading entries:

1. ✅ **Market Timing Check** (Hardcoded - Always Active)
2. ✅ **Trading Time Restrictions** (`trading_time_restrictions`)
3. ✅ **Time Overrides** (`time_overrides.no_new_trades_after`)
4. ✅ **Time Regimes** (`time_regimes`)
5. ✅ **Session-Based Pause** (`edge_failure_detector.session_based_pause`)
6. ✅ **TradingSession Entry Allowed** (Hardcoded - Always Active)

---

## 1. **Market Timing Check** (Hardcoded - Always Active)

**Location**: `app/services/signal/engine.rb` → `validate_market_timing()`

**Configuration**: ❌ **NOT configurable** - Hardcoded in code

**Blocks When**:
- Not a trading day (weekend/holiday)
- Before 9:15 AM IST
- After 3:30 PM IST

**Code**:
```ruby
# Market hours: 9:15 AM to 3:30 PM IST
market_open = hour > 9 || (hour == 9 && minute >= 15)
market_close = hour > 15 || (hour == 15 && minute >= 30)
```

**Status**: ✅ **ALWAYS ACTIVE** - Cannot be disabled

---

## 2. **Trading Time Restrictions** (Configurable)

**Location**: `config/algo.yml` → `trading_time_restrictions`

**Configuration**:
```yaml
trading_time_restrictions:
  enabled: false # Set to true to enable time-based restrictions
  avoid_periods: [] # Add time periods to avoid (e.g., ["10:30-11:30", "14:00-15:00"])
```

**Blocks When**:
- `enabled: true` AND
- Current time falls within any period in `avoid_periods`

**Example**:
```yaml
trading_time_restrictions:
  enabled: true
  avoid_periods:
    - "10:30-11:30"  # Blocks 10:30 AM - 11:30 AM IST
    - "14:00-15:00"  # Blocks 2:00 PM - 3:00 PM IST
```

**Status**: ⚠️ **DISABLED** (`enabled: false`)

**Used By**: `TradingSession::Service.entry_allowed?()`

---

## 3. **Time Overrides - No New Trades After** (Configurable)

**Location**: `config/algo.yml` → `time_overrides.no_new_trades_after`

**Configuration**:
```yaml
time_overrides:
  no_new_trades_after: "14:50" # No new trades after this time IST
```

**Blocks When**:
- Current time is after `14:50` IST (2:50 PM)
- Exception: Allows if ADX ≥ 25 and massive expansion

**Status**: ⚠️ **ENABLED** (default: `"14:50"`)

**Used By**: `Live::TimeRegimeService.allow_new_trades?()`

**Note**: This is a **global override** that blocks ALL new trades after 14:50 IST, regardless of other conditions.

---

## 4. **Time Regimes** (Configurable)

**Location**: `config/algo.yml` → `time_regimes`

**Configuration**:
```yaml
time_regimes:
  enabled: true # Set to true to enable time-regime based rules

  # S1: OPEN EXPANSION (09:15 – 09:45)
  open_expansion:
    allow_entries: true
    # ... other rules

  # S2: MOMENTUM (09:45 – 11:30)
  momentum:
    allow_entries: true
    # ... other rules

  # S3: CHOP / DECAY (11:30 – 13:45)
  chop_decay:
    allow_entries: false  # Blocks entries in this session
    # ... other rules

  # S4: CLOSE / GAMMA ZONE (13:45 – 15:15)
  close_gamma:
    allow_entries: true
    # ... other rules
```

**Blocks When**:
- `enabled: true` AND
- Current session has `allow_entries: false`

**Sessions**:
- **S1**: 09:15 – 09:45 IST (Open Expansion)
- **S2**: 09:45 – 11:30 IST (Momentum)
- **S3**: 11:30 – 13:45 IST (Chop/Decay) - **Often blocks entries**
- **S4**: 13:45 – 15:15 IST (Close/Gamma)

**Status**: ⚠️ **ENABLED** (`enabled: true`)

**Used By**: `Live::TimeRegimeService.allow_entries?()`

---

## 5. **Session-Based Pause** (Configurable)

**Location**: `config/algo.yml` → `edge_failure_detector.session_based_pause`

**Configuration**:
```yaml
edge_failure_detector:
  session_based_pause: false # Enable session-aware pause logic
  s3_max_consecutive_sls: 2 # In S3 (11:30-13:45), pause after N consecutive SLs
  s4_start_time: "13:45" # Resume entries when S4 (close/gamma) starts (IST)
```

**Blocks When**:
- `session_based_pause: true` AND
- In S3 session (11:30-13:45 IST) AND
- `s3_max_consecutive_sls` consecutive stop losses occurred

**Resumes When**:
- S4 session starts (`s4_start_time: "13:45"`)

**Status**: ✅ **DISABLED** (`session_based_pause: false`)

**Used By**: `Live::EdgeFailureDetector.entries_paused?()`

---

## 6. **TradingSession Entry Allowed** (Hardcoded - Always Active)

**Location**: `app/services/trading_session.rb` → `entry_allowed?()`

**Configuration**: ❌ **NOT configurable** - Hardcoded in code

**Blocks When**:
- Before 9:20 AM IST
- After 3:15 PM IST
- OR if `trading_time_restrictions` is enabled and current time is in restricted period

**Code**:
```ruby
ENTRY_START_HOUR = 9
ENTRY_START_MINUTE = 20
EXIT_DEADLINE_HOUR = 15
EXIT_DEADLINE_MINUTE = 15

# Entry allowed: 9:20 AM to 3:15 PM IST
```

**Status**: ✅ **ALWAYS ACTIVE** - Cannot be disabled

**Note**: This is stricter than Market Timing Check (9:20 AM vs 9:15 AM, 3:15 PM vs 3:30 PM)

---

## 📋 **Complete List with Current Status**

| #   | Configuration             | Location                                    | Status          | Blocks When                                      |
| --- | ------------------------- | ------------------------------------------- | --------------- | ------------------------------------------------ |
| 1   | Market Timing Check       | Hardcoded                                   | ✅ Always Active | Before 9:15 AM, after 3:30 PM, weekends/holidays |
| 2   | Trading Time Restrictions | `trading_time_restrictions`                 | ✅ Disabled      | When enabled + time in `avoid_periods`           |
| 3   | No New Trades After       | `time_overrides.no_new_trades_after`        | ⚠️ Enabled       | After 14:50 IST (2:50 PM)                        |
| 4   | Time Regimes              | `time_regimes`                              | ⚠️ Enabled       | When session has `allow_entries: false`          |
| 5   | Session-Based Pause       | `edge_failure_detector.session_based_pause` | ✅ Disabled      | S3 session + consecutive SLs                     |
| 6   | TradingSession Entry      | Hardcoded                                   | ✅ Always Active | Before 9:20 AM, after 3:15 PM                    |

---

## 🎯 **Effective Blocking Windows**

Based on current configuration:

### **Always Blocked** (Hardcoded):
- ❌ **Before 9:20 AM IST** (TradingSession)
- ❌ **After 3:15 PM IST** (TradingSession)
- ❌ **After 3:30 PM IST** (Market Timing Check)
- ❌ **Weekends/Holidays** (Market Timing Check)

### **Conditionally Blocked** (If Enabled):
- ⚠️ **After 14:50 IST** (Time Overrides - **Currently Enabled**)
- ⚠️ **S3 Session (11:30-13:45)** if `chop_decay.allow_entries: false` (Time Regimes - **Currently Enabled**)
- ⚠️ **Custom periods** if `trading_time_restrictions.enabled: true` (Currently Disabled)

---

## 🔍 **How to Check Current Status**

```bash
# Check all timing configurations
bundle exec rails runner "
config = AlgoConfig.fetch
puts '=== TIMING CONFIGURATIONS ==='
puts ''
puts '1. Trading Time Restrictions:'
puts \"   Enabled: #{config.dig(:trading_time_restrictions, :enabled)}\"
puts \"   Avoid Periods: #{config.dig(:trading_time_restrictions, :avoid_periods)}\"
puts ''
puts '2. Time Overrides:'
puts \"   No New Trades After: #{config.dig(:time_overrides, :no_new_trades_after)}\"
puts ''
puts '3. Time Regimes:'
puts \"   Enabled: #{config.dig(:time_regimes, :enabled)}\"
puts ''
puts '4. Session-Based Pause:'
puts \"   Enabled: #{config.dig(:edge_failure_detector, :session_based_pause)}\"
puts ''
puts '5. Market Timing (Hardcoded):'
puts '   Always Active - 9:15 AM - 3:30 PM IST'
puts ''
puts '6. TradingSession Entry (Hardcoded):'
puts '   Always Active - 9:20 AM - 3:15 PM IST'
"
```

---

## ⚠️ **Important Notes**

1. **Market Timing Check** and **TradingSession Entry** are **hardcoded** and **cannot be disabled**. They are safety mechanisms.

2. **Time Overrides** (`no_new_trades_after: "14:50"`) is **currently enabled** and will block all new trades after 2:50 PM IST.

3. **Time Regimes** is **enabled** - check if S3 session (`chop_decay.allow_entries`) is blocking entries.

4. **Trading Time Restrictions** is **disabled** - won't block unless you enable it.

5. **Session-Based Pause** is **disabled** - won't block unless you enable it.

---

## 🎯 **To Allow More Entries**

### **Disable Time Overrides**:
```yaml
time_overrides:
  no_new_trades_after: "15:30"  # Move to market close (3:30 PM)
  # OR remove the check entirely (requires code change)
```

### **Disable Time Regimes**:
```yaml
time_regimes:
  enabled: false
```

### **Allow Entries in S3 Session**:
```yaml
time_regimes:
  enabled: true
  chop_decay:
    allow_entries: true  # Allow entries in S3 (11:30-13:45)
```

---

## ✅ **Bottom Line**

**Total Timing Configs**: **6**
- **2 Hardcoded** (Always Active): Market Timing Check, TradingSession Entry
- **4 Configurable**: Trading Time Restrictions, Time Overrides, Time Regimes, Session-Based Pause

**Currently Active Blocking**:
- ✅ Market Timing Check (9:15 AM - 3:30 PM IST)
- ✅ TradingSession Entry (9:20 AM - 3:15 PM IST)
- ⚠️ Time Overrides (After 14:50 IST)
- ⚠️ Time Regimes (If S3 session blocks entries)
