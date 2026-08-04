# Quantity Sizing Analysis: Why Positions Are Small

**Generated:** 2025-12-18
**Question:** Why is quantity so small (35 qty)? Is it due to high premium?

---

## Current Situation

### Observed Position Sizes
- **Quantity**: 35 (consistent across all positions)
- **Entry Prices**: ₹837-₹883 (high premiums for BANKNIFTY options)
- **Buy Value**: ~₹29,000-₹30,000 per position
- **Capital Available**: ₹100,000 (paper trading balance)

### Key Finding
**Rupee-based position sizing is DISABLED** (`position_sizing.enabled: false`)

This means the system is using **percentage-based position sizing**, which is limiting quantity due to:
1. **High premium prices** (₹837-₹883)
2. **Capital allocation limits** (20-30% of capital)
3. **Risk percentage limits** (2.5-5% risk per trade)

---

## Why Quantity is Small (35 qty)

### 1. Percentage-Based Sizing (Currently Active)

The system uses `calculate_and_apply_quantity` which calculates quantity based on:

#### A. Capital Allocation Constraint
```ruby
# From Capital::Allocator
allocation = capital_available * effective_alloc_pct  # 20-30% of capital
cost_per_lot = entry_price * lot_size
max_by_allocation = (allocation / cost_per_lot).floor * lot_size
```

**Example with ₹100k capital:**
- Allocation: ₹100,000 × 20% = ₹20,000
- Entry Price: ₹850
- Lot Size: 15 (BANKNIFTY)
- Cost per Lot: ₹850 × 15 = ₹12,750
- Max Lots: ₹20,000 / ₹12,750 = 1.56 → **1 lot**
- Quantity: 1 × 15 = **15 qty**

#### B. Risk Percentage Constraint
```ruby
# From Capital::Allocator
risk_capital = capital_available * effective_risk_pct  # 2.5-5% of capital
stop_loss_per_share = entry_price * 0.30  # Assumes 30% stop loss
max_by_risk = (risk_capital / stop_loss_per_share).floor * lot_size
```

**Example with ₹100k capital:**
- Risk Capital: ₹100,000 × 3.5% = ₹3,500
- Stop Loss per Share: ₹850 × 0.30 = ₹255
- Max Shares: ₹3,500 / ₹255 = 13.7 → **13 shares**
- Quantity: 13 × lot_size (rounded to lot) = **~15-30 qty**

#### C. Final Quantity
```ruby
final_quantity = [max_by_allocation, max_by_risk].min
```

**Result**: Quantity is limited to the **minimum** of allocation and risk constraints, typically **15-35 qty** with high premiums.

---

## Impact of High Premiums

### With High Premiums (₹850)
- **Cost per Lot**: ₹850 × 15 = ₹12,750
- **With ₹100k capital**: Can afford ~7-8 lots max
- **With 20% allocation**: Can afford ~1-2 lots = **15-30 qty**

### With Lower Premiums (₹200)
- **Cost per Lot**: ₹200 × 15 = ₹3,000
- **With ₹100k capital**: Can afford ~33 lots max
- **With 20% allocation**: Can afford ~6-7 lots = **90-105 qty**

**Conclusion**: High premiums (₹837-₹883) are **directly limiting quantity** because:
- Each lot costs ₹12,750-₹13,245
- Capital allocation (20-30%) only allows 1-2 lots
- This results in 15-30 qty (you're seeing 35, which is ~2.3 lots)

---

## Rupee-Based Sizing Would Give Larger Quantities

### If Rupee-Based Sizing Was Enabled

**Formula:**
```
quantity = floor((risk_rupees - broker_fees) / (stop_distance_rupees × lot_size)) × lot_size
```

**Example Calculation:**
- Risk Rupees: ₹1,000
- Broker Fees: ₹40
- Net Risk: ₹960
- Stop Distance: ₹12 (BANKNIFTY)
- Lot Size: 15
- Risk per Lot: ₹12 × 15 = ₹180
- Max Lots: ₹960 / ₹180 = **5.33 → 5 lots**
- **Quantity: 5 × 15 = 75 qty** ✅

**With Capital Constraint:**
- Entry Price: ₹850
- Cost per Lot: ₹850 × 15 = ₹12,750
- Max Affordable Lots: ₹100,000 / ₹12,750 = 7.8 → **7 lots**
- **Final Quantity: min(75, 105) = 75 qty** ✅

**Result**: Rupee-based sizing would give **75 qty** (vs current 35 qty) because it's based on fixed ₹ risk, not percentage limits.

---

## Why Current System Produces Small Quantities

### Root Cause Analysis

1. **Percentage-Based Limits Are Too Conservative**
   - 20-30% capital allocation = ₹20,000-₹30,000 max per trade
   - With ₹850 premium: Only 1-2 lots affordable
   - Result: 15-30 qty

2. **High Premiums Amplify the Problem**
   - ₹850 premium × 15 lot size = ₹12,750 per lot
   - Each lot is expensive, so fewer lots fit in allocation
   - Result: Small quantities

3. **Risk Percentage Also Limits Quantity**
   - 3.5% risk = ₹3,500 risk capital
   - With 30% stop loss assumption: Only ~13 shares
   - Result: 15-30 qty (rounded to lot size)

---

## Comparison: Percentage vs Rupee-Based

| Metric            | Percentage-Based (Current) | Rupee-Based (If Enabled) |
| ----------------- | -------------------------- | ------------------------ |
| **Quantity**      | 35 qty                     | 75 qty                   |
| **Buy Value**     | ₹29,750                    | ₹63,750                  |
| **Risk**          | ~₹3,500 (3.5% of capital)  | ₹1,000 (fixed)           |
| **Stop Distance** | 30% of entry (₹255)        | ₹12 (fixed)              |
| **Target**        | Variable                   | ₹2,000 (fixed)           |

---

## Recommendations

### To Get Larger Quantities

1. **Enable Rupee-Based Position Sizing**
   ```yaml
   position_sizing:
     enabled: true  # Change to true
     risk_rupees: 1000
     stop_distance_rupees: 12  # BANKNIFTY
   ```
   - This will size positions based on fixed ₹ risk
   - Will give ~75 qty instead of 35 qty
   - Will ensure ₹1,000 risk per trade (net after fees)

2. **Increase Capital Allocation** (if staying with percentage-based)
   ```yaml
   capital:
     BANKNIFTY:
       alloc_pct: 0.40  # Increase from 20-30% to 40%
   ```
   - This allows larger positions
   - But still uses percentage-based risk (not fixed ₹)

3. **Trade Lower Premium Options**
   - Lower premiums = more lots affordable
   - But this may not align with your trading strategy

---

## Conclusion

**Yes, the small quantity (35 qty) is primarily due to high premiums combined with percentage-based position sizing.**

**Key Points:**
- High premiums (₹837-₹883) make each lot expensive (₹12,750+)
- Percentage-based sizing limits allocation to 20-30% of capital
- This results in only 1-2 lots = 15-30 qty
- **Rupee-based sizing would give ~75 qty** for the same ₹1,000 risk

**Solution**: Enable rupee-based position sizing to get larger quantities while maintaining fixed ₹ risk per trade.
