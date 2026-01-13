# Permission System Configuration Guide

**Purpose**: Configure SMC + AVRZ permission checks to control trade entry strictness

---

## 🔧 **Configuration Options**

### **Permission Modes**

Add `permission_mode` to `config/algo.yml` under the `signals` section:

```yaml
signals:
  permission_mode: strict  # Options: strict, lenient, bypass
```

### **Mode Options**

#### **1. `strict` (Default)**
- **Behavior**: Full SMC + AVRZ validation
- **Range Markets**: Requires displacement (FVG gaps) for `execution_only`
- **Trend Markets**: Requires BOS (Break of Structure) for any permission
- **AVRZ**: Must be `:compressed` or better (not `:dead`)
- **Use Case**: Production trading with maximum capital protection

#### **2. `lenient`**
- **Behavior**: Relaxed SMC + AVRZ validation
- **Range Markets**: Allows `execution_only` even without displacement
- **Trend Markets**: Allows `execution_only` without BOS if displacement present
- **AVRZ**: Defaults to `:compressed` when uncertain (rarely `:dead`)
- **Data Requirements**: Only requires HTF (60m) candles (MTF/LTF can be missing)
- **Use Case**: Testing, development, or when market data is incomplete

#### **3. `bypass`**
- **Behavior**: Completely bypasses SMC + AVRZ checks
- **Returns**: Always `execution_only` (1-lot trades allowed)
- **Use Case**: Testing signal generation and entry logic without permission restrictions

---

## 📝 **Configuration Examples**

### **Example 1: Strict Mode (Default - Production)**

```yaml
signals:
  permission_mode: strict
  # ... other signal config ...
```

**What this means:**
- Range markets need displacement to trade
- Trend markets need BOS to trade
- AVRZ must show compression or expansion
- Maximum capital protection

### **Example 2: Lenient Mode (Testing/Development)**

```yaml
signals:
  permission_mode: lenient
  # ... other signal config ...
```

**What this means:**
- Range markets can trade without displacement
- Trend markets can trade without BOS (if displacement present)
- AVRZ defaults to `:compressed` when uncertain
- Works with incomplete data (only needs HTF candles)
- Still limits to `execution_only` (1-lot trades)

### **Example 3: Bypass Mode (Testing Only)**

```yaml
signals:
  permission_mode: bypass
  # ... other signal config ...
```

**What this means:**
- All SMC + AVRZ checks are skipped
- Always returns `execution_only`
- Use only for testing - NOT for production!

---

## 🎯 **What Each Mode Allows**

| Condition               | Strict            | Lenient           | Bypass           |
| ----------------------- | ----------------- | ----------------- | ---------------- |
| Range + Displacement    | ✅ execution_only  | ✅ execution_only  | ✅ execution_only |
| Range (no displacement) | ❌ blocked         | ✅ execution_only  | ✅ execution_only |
| Trend + BOS             | ✅ execution_only+ | ✅ execution_only+ | ✅ execution_only |
| Trend (no BOS)          | ❌ blocked         | ✅ execution_only* | ✅ execution_only |
| Neutral structure       | ❌ blocked         | ❌ blocked         | ✅ execution_only |
| Missing LTF data        | ❌ blocked         | ✅ execution_only  | ✅ execution_only |
| AVRZ :dead              | ❌ blocked         | ✅ execution_only  | ✅ execution_only |

*Only if displacement present

---

## ⚙️ **How to Change**

### **Step 1: Edit `config/algo.yml`**

```yaml
signals:
  permission_mode: lenient  # Change from 'strict' to 'lenient' or 'bypass'
  # ... rest of signals config ...
```

### **Step 2: Restart Trading Daemon**

```bash
# Stop current daemon
# Ctrl+C in the terminal running ./bin/dev

# Restart
./bin/dev
```

### **Step 3: Verify**

```bash
bundle exec rake trading:check_smc_avrz
```

You should see permissions change based on the mode you selected.

---

## 🔍 **Current Permission Status**

Check current permissions:

```bash
bundle exec rake trading:check_smc_avrz
```

Or in Rails console:

```ruby
index_cfg = { key: 'NIFTY', segment: 'IDX_I', sid: '13' }
instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
permission = Trading::PermissionResolver.resolve(symbol: 'NIFTY', instrument: instrument)
puts "Permission: #{permission}"
```

---

## ⚠️ **Important Notes**

1. **Production**: Use `strict` mode for maximum capital protection
2. **Testing**: Use `lenient` mode when testing with incomplete data
3. **Development**: Use `bypass` mode only for debugging signal generation
4. **Rate Limiting**: `lenient` mode handles rate limiting better (works with less data)

---

## 📊 **Permission Levels Explained**

- **`:blocked`**: No trades allowed
- **`:execution_only`**: 1-lot trades only, no scaling
- **`:scale_ready`**: Can scale positions (multiple lots)
- **`:full_deploy`**: Full capital deployment allowed (rare)

---

## 🔄 **Migration Path**

If you want to gradually loosen restrictions:

1. **Start with `strict`** (current default)
2. **Move to `lenient`** if you're missing trades due to:
   - Range markets without displacement
   - Trend markets without BOS
   - Incomplete data (rate limiting)
3. **Use `bypass`** only for testing/debugging

---

## 📚 **Related Documentation**

- `docs/EXIT_MECHANISM_AND_RULES.md` - Exit system rules
- `docs/SMC_SCANNER_SUPERVISOR_INTEGRATION.md` - SMC integration
- `lib/tasks/check_smc_avrz.rake` - Permission diagnostic tool
