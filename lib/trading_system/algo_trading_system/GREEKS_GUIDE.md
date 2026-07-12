# 🧮 Greeks Calculator Guide

This document explains the mathematical Greeks implementation used in the NSE/BSE options system for real-time risk sensitivity analysis.

---

## 🎯 **Overview**

The Greeks quantify how an option's price responds to market changes. Our system uses the **Black-Scholes model** implemented in `src/utils/greeks_calculator.js`.

---

## 📊 **The 5 Greeks**

### **1. DELTA (δ) - Directional Exposure**
- **What it means**: Price change per ₹1 move in the underlying spot.
- **Range**: 0 to 1 (Calls), 0 to -1 (Puts).
- **Example**: ATM Call with Delta 0.50 means the option gains ₹0.50 for every ₹1 Nifty move.

### **2. GAMMA (γ) - Convexity**
- **What it means**: Rate of change of Delta per ₹1 move in spot.
- **Utility**: High Gamma means Delta changes rapidly (high sensitivity near expiry).

### **3. VEGA (ν) - Volatility Risk**
- **What it means**: Price change per 1% change in Implied Volatility (IV).
- **Strategy**: Profit from "IV expansion" or lose to "IV crush".

### **4. THETA (θ) - Time Decay**
- **What it means**: Value lost every day due to the passage of time.
- **Utility**: Crucial for short-dated options; accelerates sharply in the final 48 hours of expiry.

### **5. RHO (ρ) - Interest Rate Risk**
- **What it means**: Price change per 1% change in risk-free interest rates.
- **Relevance**: Negligible for intraday/weekly options; relevant for long-dated LEAPS.

---

## 🔢 **Real-World Example (NIFTY ATM Call)**

| Parameter | Value |
|-----------|-------|
| Spot | 26,500 |
| Strike | 26,500 |
| Expiry | 7 Days |
| IV | 35% |

**Calculated Greeks:**
- **Delta**: 0.612 (61.2% stock exposure)
- **Vega**: 3.45 (Changes ₹3.45 per 1% IV move)
- **Theta**: -0.82 (Loses ₹0.82 per day)

---

## 🎯 **System Integration**

### **1. Risk Monitoring**
The system monitors Delta drift and Gamma "explosions" to trigger re-hedging or position reduction signals.

### **2. Position Sizing**
Quantity is adjusted based on Gamma risk. High Gamma near expiry reduces the maximum allowed position size to prevent non-linear P&L swings.

### **3. Exit Signals**
Theta decay triggers are used to exit long positions that haven't moved directionally within the expected time window.

---

## 🚀 **Manual Execution**

You can test the Greeks calculator via Node.js:
```bash
node src/utils/greeks_calculator.js 26500 26500 7 6 35 CALL
# Format: Spot Strike ExpiryDays Rate% IV% Type
```
