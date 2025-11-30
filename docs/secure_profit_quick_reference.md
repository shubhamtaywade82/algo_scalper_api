# Secure Profit Rule - Quick Reference

## What It Does

**Secures profits above ₹1000 while allowing positions to ride for maximum gains.**

## How It Works

1. ✅ **Activates** when profit >= ₹1000
2. ✅ **Tracks peak** profit achieved
3. ✅ **Exits** if profit drops 3% from peak
4. ✅ **Allows riding** if drawdown < 3%

## Configuration

```yaml
risk:
  secure_profit_threshold_rupees: 1000  # Activate at ₹1000
  secure_profit_drawdown_pct: 3.0        # Exit on 3% drop from peak
```

## Example Flow

```
Entry: ₹100
₹120 → Profit: ₹1000 ✅ ACTIVATED
₹130 → Profit: ₹1500, Peak: ₹1500
₹128 → Profit: ₹1400, Peak: ₹1500
  → Drawdown: 1% < 3% → Continue riding ✅
₹125 → Profit: ₹1250, Peak: ₹1500
  → Drawdown: 5% >= 3% → EXIT ✅
```

**Result:** Secured ₹1250 profit (would have been ₹500 or less without protection)

## Adjustments

**More Conservative:**
- Lower threshold: `secure_profit_threshold_rupees: 500`
- Tighter protection: `secure_profit_drawdown_pct: 2.0`

**More Aggressive:**
- Higher threshold: `secure_profit_threshold_rupees: 2000`
- Looser protection: `secure_profit_drawdown_pct: 5.0`

## Priority

**Priority 35** - Evaluated after SL/TP but before time-based exits.

## See Also

- Full documentation: `docs/secure_profit_rule.md`
- All scenarios: `docs/rule_engine_all_scenarios.md`
