# PnL Percentage Consistency Fix

**Date:** 2025-12-18
**Status:** ✅ Fixed
**Issue:** Exit reason and Telegram message showed different percentages

---

## Problem

The exit reason string and Telegram message showed **inconsistent percentages**:

### Examples from User
1. **Entry ₹39.3, Exit ₹39.3, PnL ₹-3060**
   - Display: -0.1% (wrong - should be -10.25%)
   - Reason: -10.18% (correct PnL percentage)

2. **Entry ₹105.05, Exit ₹106.2, PnL ₹302**
   - Display: 1.09% (price change percentage)
   - Reason: 109.47% (wrong - decimal multiplied incorrectly)

3. **Entry ₹91.05, Exit ₹91.35, PnL ₹70**
   - Display: 0.33% (price change percentage)
   - Reason: 32.95% (wrong - decimal multiplied incorrectly)

---

## Root Cause

1. **Exit Reason**: Created using `pnl_pct` from Redis snapshot (price change percentage, decimal format)
2. **Telegram Message**: Calculated from entry/exit prices (price change percentage, not PnL percentage)
3. **Different Calculations**:
   - Price change: `(exit - entry) / entry` = 0% (when exit = entry)
   - PnL percentage: `PnL / (entry * quantity)` = -10.25% (includes broker fees)

---

## Solution

### 1. Standardized to PnL Percentage (After Fees)

Both exit reason and Telegram message now use **PnL percentage** calculated from final PnL value:

```ruby
pnl_pct_display = ((final_pnl / (entry_price * quantity)) * 100.0).round(2)
```

### 2. Exit Reason Update After Exit

After `mark_exited!`, the exit reason is updated with the final PnL percentage:

```ruby
# In ExitEngine and RiskManagerService
final_pnl = tracker.last_pnl_rupees
entry_price = tracker.entry_price
quantity = tracker.quantity

pnl_pct_display = ((final_pnl.to_f / (entry_price.to_f * quantity.to_i)) * 100.0).round(2)
base_reason = reason.split(/\s+-?\d+\.?\d*%/).first&.strip
updated_reason = "#{base_reason} #{pnl_pct_display}%"

# Update meta hash (exit_reason is store_accessor on meta)
meta = tracker.meta.is_a?(Hash) ? tracker.meta.dup : {}
meta['exit_reason'] = updated_reason
tracker.update_column(:meta, meta)
```

### 3. Telegram Notifier Uses PnL Percentage

Telegram notifier now calculates PnL percentage from PnL value (not price change):

```ruby
pnl_pct = if pnl_value.present? && entry_price.positive? && quantity.positive?
            # Calculate PnL percentage (includes fees) - matches exit reason format
            (pnl_value / (entry_price * quantity)) * 100.0
          else
            # Fallbacks...
          end
```

---

## Files Modified

1. ✅ `app/services/live/exit_engine.rb` - Update exit reason after exit
2. ✅ `app/services/live/risk_manager_service.rb` - Update exit reason after exit
3. ✅ `lib/notifications/telegram_notifier.rb` - Calculate PnL percentage from PnL value
4. ✅ `app/services/live/risk_manager_service.rb` - Store `last_pnl_pct` as decimal (not percentage)

---

## Calculation Examples

### Example 1: Entry = Exit (Broker Fees Only)
- Entry: ₹39.3, Exit: ₹39.3, Quantity: 760, PnL: ₹-3060
- Price change: `(39.3 - 39.3) / 39.3 = 0%`
- PnL percentage: `-3060 / (39.3 * 760) = -3060 / 29868 = -10.25%` ✓

### Example 2: Profitable Exit
- Entry: ₹105.05, Exit: ₹106.2, Quantity: 280, PnL: ₹302
- Price change: `(106.2 - 105.05) / 105.05 = 1.09%`
- PnL percentage: `302 / (105.05 * 280) = 302 / 29414 = 1.03%` ✓

---

## Expected Behavior After Fix

Both exit reason and Telegram message will show the **same PnL percentage**:

```
❌ EXIT
📊 Symbol: SENSEX-Dec2025-84900-CE
💰 Entry: ₹39.3
💵 Exit: ₹39.3
📦 Quantity: 760
💸 PnL: ₹-3060.0 (📉 -10.25%)
📝 Reason: SL HIT -10.25%  ← Now matches!
```

---

## Summary

✅ **Both use PnL percentage** (includes broker fees)
✅ **Exit reason updated after exit** with final PnL percentage
✅ **Telegram message calculates from PnL value** (not price change)
✅ **Consistent across all exit notifications**
