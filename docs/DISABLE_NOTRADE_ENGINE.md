# How to Disable NoTradeEngine (Phase 1 & Phase 2)

**Purpose**: Disable NoTradeEngine validation checks to test the trading system without restrictions

---

## 🔧 **Configuration**

### **Option 1: Via `config/algo.yml` (Recommended)**

Add or modify the `enable_no_trade_engine` flag in the `signals` section:

```yaml
signals:
  # Disable NoTradeEngine (both Phase 1 and Phase 2)
  enable_no_trade_engine: false  # Set to false to disable

  # ... other signal config ...
```

**Location**: `config/algo.yml` → `signals.enable_no_trade_engine`

**Default**: `true` (enabled)

---

### **Option 2: Via Environment Variable**

You can also set it via environment variable (if supported by your AlgoConfig implementation):

```bash
export ENABLE_NO_TRADE_ENGINE=false
```

---

## 📍 **What Gets Disabled**

When `enable_no_trade_engine: false`:

### **Phase 1: Quick Pre-Check** (Disabled)
- ❌ Time window checks (first 3 minutes, lunch time, post 3:05 PM)
- ❌ Basic structure checks
- ❌ Basic volatility checks
- ❌ Basic option chain checks (IV threshold, spread)

**Location**: `app/services/signal/engine.rb:21-30`

### **Phase 2: Detailed Validation** (Disabled)
- ❌ Full NoTradeEngine validation with context
- ❌ BOS (Break of Structure) checks
- ❌ Advanced volatility checks
- ❌ Option chain validation
- ❌ All 11 NoTradeEngine rules

**Location**: `app/services/signal/engine.rb:231-247`

---

## ✅ **What Still Works**

Even with NoTradeEngine disabled, the following still work:

- ✅ Signal generation (Supertrend + ADX or other strategies)
- ✅ Strike selection
- ✅ Entry execution via `Entries::EntryGuard`
- ✅ Position tracking
- ✅ Risk management
- ✅ Exit management

---

## 🧪 **Testing Without NoTradeEngine**

### **Step 1: Disable NoTradeEngine**

Edit `config/algo.yml`:

```yaml
signals:
  enable_no_trade_engine: false  # Disable both phases
```

### **Step 2: Restart Rails Server**

```bash
# Stop current server
kill -9 $(cat tmp/pids/server.pid) 2>/dev/null || true

# Start server
./bin/dev
```

### **Step 3: Monitor Logs**

You should see these log messages when NoTradeEngine is disabled:

```
[Signal] NoTradeEngine Phase 1 DISABLED for NIFTY - skipping pre-check
[Signal] NoTradeEngine Phase 2 DISABLED for NIFTY - skipping detailed validation
```

---

## ⚠️ **Important Notes**

1. **Production Warning**: Disabling NoTradeEngine removes important risk filters. Only disable for testing.

2. **EntryGuard Still Active**: Even with NoTradeEngine disabled, `Entries::EntryGuard` still performs its own validations (capital checks, position limits, etc.).

3. **Re-enable After Testing**: Remember to set `enable_no_trade_engine: true` after testing.

4. **Log Messages**: When disabled, you'll see INFO-level messages indicating the checks are skipped.

---

## 📝 **Code Locations**

- **Configuration Check**: `app/services/signal/engine.rb:21-30` (Phase 1)
- **Configuration Check**: `app/services/signal/engine.rb:231-247` (Phase 2)
- **Config File**: `config/algo.yml` → `signals.enable_no_trade_engine`

---

## 🔄 **Re-enabling NoTradeEngine**

Simply set the flag back to `true`:

```yaml
signals:
  enable_no_trade_engine: true  # Re-enable
```

Then restart the Rails server.


