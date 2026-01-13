# Security ID Fix for Paper Trading

**Date**: 2026-01-13
**Issue**: Strike selection failing with "missing tradable security_id"

---

## 🔍 **Problem**

When `filter_and_rank_from_instrument_data` processes option strikes, it requires a valid `security_id` from the `Derivative` record. However:

1. **Derivative might not exist in database** - Option chain data exists, but derivative record hasn't been created/synced
2. **Derivative exists but has no `security_id`** - Record exists but `security_id` field is blank/null
3. **`security_id` is invalid** - Starts with `TEST_` or is blank

This caused strikes to be rejected with:
```
[Options::ChainAnalyzer] Skipping SENSEX 83700.0 pe - missing tradable security_id (found=)
[Options] No legs found after filtering for SENSEX (strike: 83700, type: ATM, side: pe)
[Signal] No suitable option strikes found for SENSEX bearish
```

---

## ✅ **Solution**

### **Paper Mode: Synthetic Security ID**

For paper trading, we now generate a synthetic `security_id` when the derivative is missing or has no `security_id`:

```ruby
# If derivative exists but has no security_id
if derivative&.id.present?
  security_id = "PAPER-#{derivative.id}"
else
  # If derivative doesn't exist, use deterministic synthetic ID
  security_id = "PAPER-#{index_key}-#{strike}-#{expiry}-#{option_type}"
  # Example: "PAPER-SENSEX-83600-20260114-PE"
end
```

### **Benefits**:
1. ✅ **Paper mode works** even when derivatives aren't synced to database
2. ✅ **Deterministic IDs** - Same strike/expiry/type always gets same synthetic ID
3. ✅ **Clear identification** - `PAPER-` prefix makes it obvious it's synthetic
4. ✅ **Live mode unchanged** - Still requires real `security_id` for live trading

### **Validation Updated**:

```ruby
def valid_security_id?(value)
  id = value.to_s
  return false if id.blank?
  return false if id.start_with?('TEST_')
  # Allow synthetic PAPER- prefixed IDs for paper trading
  return true if id.start_with?('PAPER-')
  true
end
```

---

## 🧪 **Testing**

### **Test Results**:
```ruby
# Before fix:
Legs found: 0
[Options::ChainAnalyzer] Skipping SENSEX 83600.0 pe - missing tradable security_id

# After fix:
Legs found: 1
✅ SUCCESS!
  Security ID: PAPER-SENSEX-83600-20260114-PE
  Symbol: SENSEX-Jan2026-83600-PE
  Strike: 83600.0
  LTP: 228.45
```

---

## 📊 **Impact**

| Scenario | Before | After |
|----------|--------|-------|
| Derivative exists with `security_id` | ✅ Works | ✅ Works |
| Derivative exists but no `security_id` (paper) | ❌ Blocked | ✅ Synthetic ID |
| Derivative missing (paper) | ❌ Blocked | ✅ Synthetic ID |
| Derivative missing (live) | ❌ Blocked | ❌ Blocked (expected) |

---

## 🎯 **Summary**

**Fixed**: Strike selection now works in paper mode even when:
- Derivative doesn't exist in database
- Derivative exists but has no `security_id`

**Synthetic IDs**:
- Format: `PAPER-{derivative_id}` or `PAPER-{index}-{strike}-{expiry}-{type}`
- Only used in paper mode
- Clearly identifiable with `PAPER-` prefix

**Live Mode**: Unchanged - still requires real `security_id` from DhanHQ
