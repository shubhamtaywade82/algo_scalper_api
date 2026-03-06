# PnL Percentage Standardization

**Date:** 2025-12-18
**Status:** ✅ Completed
**Standard:** All `pnl_pct` values stored as **decimal** (0.0573 = 5.73%)

---

## Standard Format

**Storage Format:** Decimal (0.0573 = 5.73%)
**Display Format:** Percentage (5.73%) - multiply by 100 only when displaying

---

## Rationale

1. **Mathematical Correctness**: Decimal is the natural result of division `(exit - entry) / entry`
2. **Consistency**: Redis already stores as decimal
3. **Simplicity**: No need to divide by 100 in calculations
4. **Precision**: Avoids rounding errors from percentage conversions

---

## Storage Locations

### ✅ Redis (`Live::RedisPnlCache`)
- **Format:** Decimal (0.0573)
- **Location:** `app/services/live/pnl_updater_service.rb:240`
- **Calculation:** `((ltp_bd - entry_bd) / entry_bd)`

### ✅ Database (`PositionTracker.last_pnl_pct`)
- **Format:** Decimal (0.0573)
- **Updated in:**
  - `RiskManagerService.exit_position()` - line 765
  - `RiskManagerService.exit_position()` - line 543
  - `EntryGuard.calculate_current_pnl()` - line 237
  - `PositionSyncService.calculate_paper_pnl_before_exit()` - line 286
  - `RedisPnlCache.sync_pnl_to_database()` - line 186

### ✅ ActiveCache (`PositionData.pnl_pct`)
- **Format:** Decimal (0.0573)
- **Location:** `app/services/positions/active_cache.rb:96`
- **Calculation:** `((current_ltp - entry_price) / entry_price)`

---

## Display/Formatting

### ✅ Telegram Notifier
- **Location:** `lib/notifications/telegram_notifier.rb:168`
- **Conversion:** Multiply by 100 for display
- **Code:** `((exit_price_value - entry_price) / entry_price) * 100.0`

### ✅ Exit Reason Strings
- **Location:** `app/services/live/risk_manager_service.rb:390, 402`
- **Conversion:** Multiply by 100 for display
- **Code:** `(pnl_pct * 100).round(2)`

### ✅ Risk Rules
- **StopLossRule:** `app/services/risk/rules/stop_loss_rule.rb:24`
- **TakeProfitRule:** `app/services/risk/rules/take_profit_rule.rb:24`
- **BracketLimitRule:** `app/services/risk/rules/bracket_limit_rule.rb:19, 26`
- **Conversion:** Multiply by 100 for display in reason strings

### ✅ PositionTracker Stats
- **Location:** `app/models/position_tracker.rb:104-117`
- **Conversion:** Multiply by 100 for display
- **Code:** `(t.last_pnl_pct.to_f || 0.0) * 100.0`

---

## Comparison Logic

### Risk Rules
- **Format:** Both `pnl_pct` (decimal) and `sl_pct`/`tp_pct` (decimal) are compared directly
- **Example:** `pnl_pct <= -sl_pct` where `pnl_pct = -0.0193` and `sl_pct = 0.03`
- **No conversion needed** - both are decimals

### Config Values
- **Format:** `sl_pct: 0.03` (decimal = 3%)
- **Format:** `tp_pct: 0.05` (decimal = 5%)
- **Location:** `config/algo.yml:175-176`

---

## Migration Notes

### Before (Inconsistent)
- Redis: Decimal ✓
- Database: Sometimes decimal, sometimes percentage ✗
- Display: Sometimes multiplied, sometimes not ✗

### After (Consistent)
- Redis: Decimal ✓
- Database: Decimal ✓
- Display: Always multiply by 100 ✓

---

## Code Examples

### Storing PnL Percentage
```ruby
# Calculate as decimal
pnl_pct = entry.positive? ? ((exit_price - entry) / entry) : nil

# Store in database
tracker.update!(
  last_pnl_pct: pnl_pct ? BigDecimal(pnl_pct.to_s) : nil
)
```

### Displaying PnL Percentage
```ruby
# Get from database (decimal)
pnl_pct_decimal = tracker.last_pnl_pct.to_f  # 0.0573

# Convert to percentage for display
pnl_pct_display = pnl_pct_decimal * 100.0  # 5.73

# Format for display
"#{pnl_pct_display.round(2)}%"  # "5.73%"
```

### Comparing with Config
```ruby
# Both are decimals - compare directly
sl_pct = 0.03  # From config (3%)
pnl_pct = -0.0193  # From Redis/DB (-1.93%)

if pnl_pct <= -sl_pct
  # Exit triggered: -1.93% <= -3% (false, so no exit)
end
```

---

## Files Modified

1. ✅ `app/services/live/risk_manager_service.rb` - Store as decimal
2. ✅ `app/services/entries/entry_guard.rb` - Store as decimal
3. ✅ `app/services/live/position_sync_service.rb` - Store as decimal
4. ✅ `app/services/positions/active_cache.rb` - Store as decimal
5. ✅ `lib/notifications/telegram_notifier.rb` - Display conversion
6. ✅ `app/services/risk/rules/stop_loss_rule.rb` - Display conversion
7. ✅ `app/services/risk/rules/take_profit_rule.rb` - Display conversion
8. ✅ `app/services/risk/rules/bracket_limit_rule.rb` - Display conversion
9. ✅ `app/models/position_tracker.rb` - Display conversion

---

## Testing Checklist

- [ ] Exit reason strings show correct percentage
- [ ] Telegram notifications show correct percentage
- [ ] Database stores decimal values
- [ ] Redis stores decimal values
- [ ] Risk rules compare correctly (decimal to decimal)
- [ ] Position stats display correct percentages
- [ ] All exit paths use consistent format

---

## Summary

✅ **Standardized to decimal (0.0573) everywhere**
✅ **Display code multiplies by 100 only when showing to user**
✅ **Comparison logic uses decimals directly (no conversion)**
✅ **Consistent across Redis, Database, and all services**
