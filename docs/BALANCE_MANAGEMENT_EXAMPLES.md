# Balance Management - Detailed Examples

This document provides detailed examples of how the balance management system tracks capital through multiple trades with profits and losses.

## System Overview

**Balance Formula:**
```
Running Balance = Initial Balance - Deployed Capital + Realized Capital
```

Where:
- **Deployed Capital** = Sum of (entry_price × quantity) for all active positions
- **Realized Capital** = Sum of (entry_cost + P&L) for all exited positions
- **Entry Cost** = entry_price × quantity (capital deployed when entering)
- **Realized Capital on Exit** = entry_cost + P&L (capital returned when exiting)

---

## Example 1: Single Profitable Trade

### Initial State
- **Initial Balance**: ₹100,000
- **Active Positions**: 0
- **Exited Positions**: 0

### Trade 1: Entry (Buy Options)
- **Symbol**: NIFTY 25000 CE
- **Entry Price**: ₹100 per lot
- **Quantity**: 10 lots
- **Entry Cost**: ₹100 × 10 = ₹1,000

**Balance After Entry:**
```
Running Balance = ₹100,000 - ₹1,000 = ₹99,000
Deployed Capital = ₹1,000 (1 active position)
Realized Capital = ₹0 (no exits yet)
```

### Trade 1: Exit (Profitable)
- **Exit Price**: ₹120 per lot
- **P&L**: (₹120 - ₹100) × 10 = ₹200 profit
- **Realized Capital**: ₹1,000 (entry cost) + ₹200 (P&L) = ₹1,200

**Balance After Exit:**
```
Running Balance = ₹99,000 + ₹1,200 = ₹100,200
Deployed Capital = ₹0 (no active positions)
Realized Capital = ₹1,200 (1 exited position)
```

**Net Result:**
- Started with: ₹100,000
- Ended with: ₹100,200
- **Profit**: ₹200 ✅

---

## Example 2: Single Loss-Making Trade

### Initial State
- **Initial Balance**: ₹100,000
- **Active Positions**: 0
- **Exited Positions**: 0

### Trade 1: Entry (Buy Options)
- **Symbol**: BANKNIFTY 50000 CE
- **Entry Price**: ₹150 per lot
- **Quantity**: 5 lots
- **Entry Cost**: ₹150 × 5 = ₹750

**Balance After Entry:**
```
Running Balance = ₹100,000 - ₹750 = ₹99,250
Deployed Capital = ₹750 (1 active position)
Realized Capital = ₹0
```

### Trade 1: Exit (Loss)
- **Exit Price**: ₹120 per lot
- **P&L**: (₹120 - ₹150) × 5 = -₹150 loss
- **Realized Capital**: ₹750 (entry cost) + (-₹150) (P&L) = ₹600

**Balance After Exit:**
```
Running Balance = ₹99,250 + ₹600 = ₹99,850
Deployed Capital = ₹0
Realized Capital = ₹600 (1 exited position)
```

**Net Result:**
- Started with: ₹100,000
- Ended with: ₹99,850
- **Loss**: ₹150 ❌

---

## Example 3: Multiple Trades - Mixed Results

### Initial State
- **Initial Balance**: ₹100,000

### Trade 1: Entry
- **Symbol**: NIFTY 25000 CE
- **Entry Price**: ₹100
- **Quantity**: 10 lots
- **Entry Cost**: ₹1,000

**Balance**: ₹100,000 - ₹1,000 = **₹99,000**

### Trade 1: Exit (Profit)
- **Exit Price**: ₹120
- **P&L**: +₹200
- **Realized Capital**: ₹1,000 + ₹200 = ₹1,200

**Balance**: ₹99,000 + ₹1,200 = **₹100,200** ✅

### Trade 2: Entry
- **Symbol**: BANKNIFTY 50000 CE
- **Entry Price**: ₹150
- **Quantity**: 5 lots
- **Entry Cost**: ₹750

**Balance**: ₹100,200 - ₹750 = **₹99,450**

### Trade 2: Exit (Loss)
- **Exit Price**: ₹120
- **P&L**: -₹150
- **Realized Capital**: ₹750 + (-₹150) = ₹600

**Balance**: ₹99,450 + ₹600 = **₹100,050** ✅

### Trade 3: Entry
- **Symbol**: NIFTY 25100 CE
- **Entry Price**: ₹80
- **Quantity**: 15 lots
- **Entry Cost**: ₹1,200

**Balance**: ₹100,050 - ₹1,200 = **₹98,850**

### Trade 3: Exit (Profit)
- **Exit Price**: ₹110
- **P&L**: (₹110 - ₹80) × 15 = +₹450
- **Realized Capital**: ₹1,200 + ₹450 = ₹1,650

**Balance**: ₹98,850 + ₹1,650 = **₹100,500** ✅

### Summary
- **Initial Balance**: ₹100,000
- **Final Balance**: ₹100,500
- **Total P&L**: ₹500 profit
- **Trade 1**: +₹200
- **Trade 2**: -₹150
- **Trade 3**: +₹450

---

## Example 4: Concurrent Positions (Multiple Active Trades)

### Initial State
- **Initial Balance**: ₹100,000

### Trade 1: Entry
- **Symbol**: NIFTY 25000 CE
- **Entry Price**: ₹100
- **Quantity**: 10 lots
- **Entry Cost**: ₹1,000

**Balance**: ₹100,000 - ₹1,000 = **₹99,000**
**Deployed**: ₹1,000

### Trade 2: Entry (While Trade 1 is Active)
- **Symbol**: BANKNIFTY 50000 CE
- **Entry Price**: ₹150
- **Quantity**: 5 lots
- **Entry Cost**: ₹750

**Balance**: ₹99,000 - ₹750 = **₹98,250**
**Deployed**: ₹1,000 + ₹750 = ₹1,750

### Trade 3: Entry (While Trades 1 & 2 are Active)
- **Symbol**: NIFTY 25100 CE
- **Entry Price**: ₹80
- **Quantity**: 8 lots
- **Entry Cost**: ₹640

**Balance**: ₹98,250 - ₹640 = **₹97,610**
**Deployed**: ₹1,000 + ₹750 + ₹640 = ₹2,390

### Trade 1: Exit (Profit)
- **Exit Price**: ₹120
- **P&L**: +₹200
- **Realized Capital**: ₹1,000 + ₹200 = ₹1,200

**Balance**: ₹97,610 + ₹1,200 = **₹98,810**
**Deployed**: ₹750 + ₹640 = ₹1,390 (Trade 1 removed)

### Trade 2: Exit (Loss)
- **Exit Price**: ₹120
- **P&L**: -₹150
- **Realized Capital**: ₹750 + (-₹150) = ₹600

**Balance**: ₹98,810 + ₹600 = **₹99,410**
**Deployed**: ₹640 (only Trade 3 remains)

### Trade 3: Exit (Profit)
- **Exit Price**: ₹100
- **P&L**: (₹100 - ₹80) × 8 = +₹160
- **Realized Capital**: ₹640 + ₹160 = ₹800

**Balance**: ₹99,410 + ₹800 = **₹100,210**
**Deployed**: ₹0 (all positions closed)

### Summary
- **Initial Balance**: ₹100,000
- **Final Balance**: ₹100,210
- **Total P&L**: ₹210 profit
- **Peak Deployed**: ₹2,390 (when 3 positions were active)
- **Trade 1**: +₹200
- **Trade 2**: -₹150
- **Trade 3**: +₹160

---

## Example 5: Realistic Trading Session (150+ Trades)

### Scenario
- **Initial Balance**: ₹100,000
- **Total Trades**: 150
- **Winners**: 90 trades (60% win rate)
- **Losers**: 60 trades (40% loss rate)
- **Average Win**: ₹120 per trade
- **Average Loss**: ₹80 per trade

### Calculations

**Total Profit from Winners:**
```
90 trades × ₹120 = ₹10,800
```

**Total Loss from Losers:**
```
60 trades × ₹80 = ₹4,800
```

**Net P&L:**
```
₹10,800 - ₹4,800 = ₹6,000 profit
```

### Balance Progression (Sample)

**After 10 trades (6 winners, 4 losers):**
- Average entry cost: ₹1,000 per trade
- Deployed: ₹10,000
- Realized: ₹6,000 (winners) + ₹3,680 (losers) = ₹9,680
- **Balance**: ₹100,000 - ₹10,000 + ₹9,680 = ₹99,680

**After 50 trades (30 winners, 20 losers):**
- Deployed: ₹50,000
- Realized: ₹30,000 + ₹18,400 = ₹48,400
- **Balance**: ₹100,000 - ₹50,000 + ₹48,400 = ₹98,400

**After 100 trades (60 winners, 40 losers):**
- Deployed: ₹100,000
- Realized: ₹60,000 + ₹36,800 = ₹96,800
- **Balance**: ₹100,000 - ₹100,000 + ₹96,800 = ₹96,800

**After 150 trades (90 winners, 60 losers):**
- All positions closed
- Deployed: ₹0
- Realized: ₹90,000 + ₹55,200 = ₹145,200
- **Balance**: ₹100,000 - ₹0 + ₹145,200 = ₹245,200 ❌ **WRONG!**

### Correction: Proper Calculation

The issue above is that we're double-counting. Let's recalculate properly:

**Total Capital Deployed:**
```
150 trades × ₹1,000 average = ₹150,000 deployed
```

**Total Realized Capital Returned:**
```
Winners: 90 × (₹1,000 + ₹120) = ₹100,800
Losers: 60 × (₹1,000 - ₹80) = ₹55,200
Total Realized: ₹156,000
```

**Final Balance:**
```
Initial: ₹100,000
- Deployed: ₹150,000
+ Realized: ₹156,000
= ₹106,000 ✅
```

**Net P&L:**
```
₹106,000 - ₹100,000 = ₹6,000 profit ✅
```

---

## Example 6: Your Actual Session (18k Profit, 150+ Trades)

### Your Session Details
- **Initial Balance**: ₹100,000
- **Total Trades**: 150+
- **Realized Profit**: ₹18,000
- **Capital Per Trade**: ₹30,000 (30% of ₹100,000)

### How It Should Work Now

**Before Fix (Incorrect):**
- Each trade used ₹30,000 (30% of fixed ₹100,000)
- Balance never updated
- After 150 trades: Still using ₹30,000 per trade
- **Problem**: Not using realized profits

**After Fix (Correct):**

**Trade 1:**
- Entry: ₹100,000 - ₹30,000 = ₹70,000
- Exit (profit ₹200): ₹70,000 + ₹30,200 = ₹100,200

**Trade 2:**
- Entry: ₹100,200 - ₹30,060 (30% of ₹100,200) = ₹70,140
- Exit (profit ₹150): ₹70,140 + ₹30,210 = ₹100,350

**Trade 3:**
- Entry: ₹100,350 - ₹30,105 (30% of ₹100,350) = ₹70,245
- Exit (profit ₹180): ₹70,245 + ₹30,285 = ₹100,530

**After 150 profitable trades:**
- Each trade compounds the balance
- Position sizes grow with profits
- **Final Balance**: ₹100,000 + ₹18,000 = ₹118,000 ✅

---

## Key Formulas

### Entry
```
New Balance = Current Balance - (Entry Price × Quantity)
```

### Exit (Profit)
```
Realized Capital = Entry Cost + P&L
New Balance = Current Balance + Realized Capital
```

### Exit (Loss)
```
Realized Capital = Entry Cost + P&L (P&L is negative)
New Balance = Current Balance + Realized Capital
```

### Available Balance for Next Trade
```
Available = Running Balance - Currently Deployed Capital
```

---

## Balance Manager Methods

### `record_entry(tracker, entry_price:, quantity:)`
- Reduces balance by: `entry_price × quantity`
- Logs: Entry cost and new balance

### `record_exit(tracker)`
- Calculates: `entry_cost + P&L`
- Adds to balance: Full realized capital
- Logs: Entry cost, P&L, realized capital, new balance

### `available_balance`
- Returns: Current running balance
- For paper: Redis-stored balance
- For live: API balance + realized P&L

---

## Verification

To verify balance is correct:

```ruby
# Get current balance
balance = Capital::BalanceManager.instance.available_balance

# Get deployed capital
deployed = Capital::BalanceManager.instance.total_deployed_capital

# Get realized P&L
realized_pnl = Capital::BalanceManager.instance.total_realized_pnl

# Verify: Initial + Realized P&L - Deployed = Current Balance
initial = Capital::BalanceManager.instance.initial_balance
calculated = initial + realized_pnl - deployed

puts "Initial: ₹#{initial}"
puts "Deployed: ₹#{deployed}"
puts "Realized P&L: ₹#{realized_pnl}"
puts "Current Balance: ₹#{balance}"
puts "Calculated: ₹#{calculated}"
puts "Match: #{balance.round(2) == calculated.round(2)}"
```

---

## Important Notes

1. **Entry Cost is Deducted**: When entering a trade, the full entry cost is deducted from balance
2. **Full Exit Proceeds Added**: When exiting, entry cost + P&L is added back
3. **Net Effect**: Balance changes by exactly the P&L amount
4. **Concurrent Positions**: Multiple active positions reduce available balance accordingly
5. **Redis Persistence**: Balance is stored in Redis with daily keys for persistence
