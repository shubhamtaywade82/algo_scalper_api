# System Architecture & Design Document — NSE/BSE Options Backtesting

## 🏗️ High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DhanHQ Historical API                         │
│     (Expired Options Data: 5 years rolling basis, minute-level)      │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                    (API Request with date range)
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│                    DhanAPIClient (Ruby)                              │
│                                                                       │
│  ├─ Fetch expired options (rolling basis, 30-day chunks)            │
│  ├─ Handle multi-strikes: ATM ± 1 to ± 10                          │
│  ├─ Retry logic (3 retries with exponential backoff)                │
│  ├─ Response parsing & validation                                   │
│  └─ Output: Structured hash { strike => { ohlcvs, iv, oi, spot } } │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                     (Converted to bars)
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│                 OptionsBacktestEngine (Ruby)                         │
│                                                                       │
│  ├─ 7-State FSM: IDLE → SIGNAL → ENTRY → OPEN → MGMT → EXIT → CLOSE│
│  ├─ Bar-by-bar processing with timestamp validation                 │
│  ├─ Position sizing: Max 2.5% per trade                             │
│  ├─ Bracket order simulation (entry, SL, TP)                        │
│  ├─ Risk enforcement:                                                │
│  │   ├─ Stop-loss: 1.5% minimum                                     │
│  │   ├─ Margin: 30% for index options                               │
│  │   ├─ STT: 0.05% on contract value                                │
│  │   └─ Time exit: 3:15 PM IST auto-close                           │
│  ├─ P&L calculation: (Exit - Entry) × Qty - STT - Margin            │
│  └─ Output: Trade journal with equity curve                         │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                         (Bar by bar)
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│                  TradingStrategies (Ruby)                            │
│                                                                       │
│  ├─ RSI + MACD Reversal                                              │
│  ├─ Bollinger Bands Breakout                                        │
│  ├─ IV Spike + Volume Momentum                                      │
│  └─ VWAP Breakout                                                    │
│                                                                       │
│  Each strategy:                                                       │
│  ├─ Maintains history of last 30-40 bars                            │
│  ├─ Calculates technical indicators (RSI, MACD, BB, ATR, VWAP)      │
│  ├─ Returns: { action, direction, confidence, reason }              │
│  └─ Can be used as Proc: ->(bar) { strategy.signal }                │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                   (Strategy signal result)
                               │
┌──────────────────────────────▼──────────────────────────────────────┐
│           OptionsBacktestOrchestrator (Ruby)                         │
│                                                                       │
│  ├─ Main coordinator                                                 │
│  ├─ Orchestrates: API → Conversion → Engine → Strategies             │
│  ├─ Multi-strike parallel processing                                │
│  ├─ Aggregates results across strikes                               │
│  └─ Generates reports:                                              │
│      ├─ JSON: metrics, trades, metadata                             │
│      ├─ HTML: interactive dashboard                                 │
│      └─ CSV: trade journal                                          │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                    (Backtest complete)
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
┌───────▼────────┐  ┌──────────▼────────┐  ┌────────▼──────────┐
│  JSON Summary  │  │ HTML Dashboard    │  │  CSV Trade Log    │
│                │  │                   │  │                   │
│ • Win Rate     │  │ • Equity Curve    │  │ • Entry/Exit      │
│ • Sharpe Ratio │  │ • P&L per strike  │  │ • P&L per trade   │
│ • Max DD       │  │ • Trade timeline  │  │ • Status (W/L)    │
│ • Total P&L    │  │ • Greeks heatmap  │  │ • For analysis    │
└────────────────┘  └───────────────────┘  └───────────────────┘
```

---

## 🔄 Data Flow Diagram

```
INPUT STAGE:
┌─────────────────────┐
│  DhanHQ API         │
│  ├─ exchangeSegment │  POST /charts/rollingoption
│  ├─ fromDate        │  ─────────────────────────→
│  ├─ toDate          │  
│  ├─ strikes         │  
│  ├─ interval        │  
│  └─ requiredData    │  
└─────────────────────┘

API RESPONSE:
┌──────────────────────┐
│ {                    │
│   "data": {          │
│     "ce": {          │
│       "open": [...], │
│       "high": [...], │
│       "low": [...],  │
│       "close": [...],│
│       "iv": [...],   │
│       "oi": [...],   │
│       "volume": [...],
│       "spot": [...], │
│       "timestamp": [...] ← Unix timestamps (epoch)
│     }               │
│   }                │
│ }                 │
└──────────────────────┘

CONVERSION TO BARS:
┌────────────────────────────────┐
│ For each bar at index i:       │
├────────────────────────────────┤
│ {                              │
│   timestamp: 1704067800,       │
│   open: 354.00,                │
│   high: 360.25,                │
│   low: 352.50,                 │
│   close: 359.75,               │
│   volume: 15000,               │
│   iv: 35.2,                    │
│   spot: 26500.00               │
│ }                              │
└────────────────────────────────┘

ENGINE PROCESSING (Per bar):
┌───────────────────────────────────┐
│ 1. Check current state            │
│    ├─ IDLE: Look for signal       │
│    ├─ SIGNAL: Validate & enter    │
│    ├─ OPEN: Manage position       │
│    └─ CLOSED: Reset              │
├───────────────────────────────────┤
│ 2. Check risk conditions          │
│    ├─ Hit stop-loss? → Exit      │
│    ├─ Hit profit target? → Exit  │
│    ├─ Past 3:15 PM? → Force exit │
│    └─ Continue or hold?           │
├───────────────────────────────────┤
│ 3. Calculate P&L (if exit)        │
│    ├─ (Exit Price - Entry) × Qty │
│    ├─ - STT (0.05% on contract)  │
│    ├─ Realize margin              │
│    └─ Update equity               │
├───────────────────────────────────┤
│ 4. Log trade + transition state   │
└───────────────────────────────────┘

OUTPUT STAGE:
┌──────────────────────────────┐
│ Summary Metrics              │
├──────────────────────────────┤
│ • Total trades: 24           │
│ • Win rate: 66.7%            │
│ • Total P&L: ₹45,320         │
│ • Sharpe: 1.28               │
│ • Max DD: -2.15%             │
└──────────────────────────────┘
       │
       ├─→ JSON Report
       ├─→ HTML Dashboard
       └─→ CSV Export
```

---

## 🎯 State Machine (FSM) Diagram

```
         ┌──────────────────┐
         │      IDLE        │
         └────────┬─────────┘
                  │
          Signal detected?
                  │
                  ▼
         ┌──────────────────┐
         │ SIGNAL_DETECTED  │
         └────────┬─────────┘
                  │
          Validate & place order
                  │
                  ▼
         ┌──────────────────┐
         │ ENTRY_PENDING    │
         └────────┬─────────┘
                  │
          Margin available?
                  │
        ┌─────────┴─────────┐
        │ (No)              │ (Yes)
        ▼                   ▼
    ┌──────┐        ┌──────────────┐
    │ IDLE │        │ POSITION_OPEN│
    └──────┘        └────────┬─────┘
                             │
            ┌────────────────┼────────────────┐
            │                │                │
        SL hit?         TP hit (20%)?    Time exit
            │                │            (2:45 PM)?
            │                │                │
            ▼                ▼                ▼
    ┌──────────────────────────────────────────┐
    │  POSITION_CLOSED (Exit @ Market)        │
    │  ├─ Update equity                        │
    │  ├─ Calculate P&L                        │
    │  ├─ Log trade                            │
    │  └─ Transition → IDLE                    │
    └──────────────────────────────────────────┘
            │
            └──────────┬───────────┐
                       │           │
                   Win (P&L>0)  Loss (P&L≤0)
                       │           │
                       ▼           ▼
                   ✓ Track    ✓ Track
```

---

## 💰 Position Sizing Algorithm

```
INPUT:
├─ Capital: ₹10,00,000
├─ Max risk per trade: 2.5% = ₹25,000
├─ Entry price: ₹354
├─ Stop-loss: ₹348.69 (1.5% below)
└─ SL distance: ₹5.31

CALCULATION:
├─ Position size = Max risk / SL distance
│                = ₹25,000 / ₹5.31
│                = 4,706.40 contracts
│                = 4,706 contracts (rounded down)
│
├─ Contract value = Entry price × Quantity
│                 = ₹354 × 4,706
│                 = ₹16,65,324
│
├─ Margin required = Contract value × 30%
│                  = ₹16,65,324 × 0.30
│                  = ₹4,99,597
│
├─ STT (broker fee) = Contract value × 0.05%
│                   = ₹16,65,324 × 0.0005
│                   = ₹833
│
└─ Total capital needed = Margin + STT
                        = ₹4,99,597 + ₹833
                        = ₹5,00,430

VALIDATION:
✓ Required (₹5,00,430) < Available (₹10,00,000)? YES → Proceed
✗ Required > Available? NO → Reject trade
```

---

## 🔐 Risk Management Workflow

```
ENTRY:
┌─────────────────────────────────┐
│ 1. Check available capital      │
│ 2. Calculate position size      │
│ 3. Validate stop-loss (min 1.5%)│
│ 4. Set profit target (20% gain) │
│ 5. Place bracket order          │
│ 6. Reserve margin (30%)         │
│ 7. Deduct STT                   │
└─────────────────────────────────┘

OPEN POSITION:
┌─────────────────────────────────┐
│ Every minute, check:            │
│ ├─ Price < SL? → Force close   │
│ ├─ Price > TP? → Auto-close    │
│ ├─ 2 min elapsed + declining?  │
│ │  → Theta decay exit            │
│ ├─ 3:15 PM IST? → Market close │
│ └─ Continue monitoring          │
└─────────────────────────────────┘

EXIT:
┌─────────────────────────────────┐
│ 1. Record exit price            │
│ 2. Calculate P&L:               │
│    P&L = (Exit - Entry) × Qty   │
│    P&L = P&L - STT              │
│ 3. Realize margin (return ₹)    │
│ 4. Update equity curve          │
│ 5. Log trade (WIN/LOSS)         │
│ 6. Reset state → IDLE           │
└─────────────────────────────────┘
```

---

## 📊 P&L Calculation

```
EXAMPLE TRADE:

Entry:
├─ Symbol: NIFTY-26500-CE
├─ Entry price: ₹354.00
├─ Quantity: 100 contracts
├─ Stop-loss: ₹348.69 (1.5% below)
└─ Time: 2024-01-01 09:15:00 IST

Exit:
├─ Exit price: ₹369.50
├─ Qty exited: 100
└─ Time: 2024-01-01 09:22:00 IST (7 minutes)

CALCULATION:
Step 1: Gross P&L
├─ Price movement = Exit - Entry = 369.50 - 354.00 = ₹15.50
├─ Contract P&L = Price movement × Quantity = ₹15.50 × 100 = ₹1,550
└─ Gross P&L = ₹1,550

Step 2: Deduct costs
├─ STT (entry) = 354.00 × 100 × 0.05% = ₹17.70
├─ STT (exit) = 369.50 × 100 × 0.05% = ₹18.48
├─ Total STT = ₹17.70 + ₹18.48 = ₹36.18
└─ Net STT = ₹36.18

Step 3: Net P&L
├─ Net P&L = Gross P&L - STT
│          = ₹1,550 - ₹36.18
│          = ₹1,513.82
└─ Return % = (P&L / Entry Value) × 100
            = (₹1,513.82 / ₹35,400) × 100
            = 4.28%

EQUITY UPDATE:
├─ Before: ₹10,00,000
├─ P&L: +₹1,513.82
├─ After: ₹10,01,513.82
└─ Peak equity: ₹10,01,513.82 (for max DD calculation)
```

---

## 🧮 Greeks Calculation (Black-Scholes)

```
INPUTS:
├─ Spot price (S): ₹26,500
├─ Strike price (K): ₹26,500
├─ Time to expiry (T): 7 days = 0.0192 years
├─ Volatility (σ): 35% = 0.35
├─ Risk-free rate (r): 6% = 0.06
└─ Dividend (q): 0%

CALCULATION:

d1 = [ln(S/K) + (r + σ²/2)T] / (σ√T)
   = [ln(26500/26500) + (0.06 + 0.35²/2) × 0.0192] / (0.35 × √0.0192)
   = [0 + 0.0010] / 0.1533
   = 0.0065

d2 = d1 - σ√T
   = 0.0065 - 0.35 × 0.1387
   = 0.0065 - 0.0485
   = -0.0420

N(d1) = 0.5026 (cumulative normal)
N(d2) = 0.4832

GREEKS:

Delta = N(d1) = 0.503 (50.3% stock-like)
Gamma = N'(d1) / (S × σ × √T) = 0.0042 (convexity)
Vega = S × N'(d1) × √T = 3.45 (per 1% IV change)
Theta = -S × N'(d1) × σ / (2√T) - r × K × e^(-rT) × N(d2) = -0.82 (per day)
Rho = K × T × e^(-rT) × N(d2) = 0.156 (per 1% rate change)

INTERPRETATION:
├─ Delta 0.503: For every ₹1 spot move, option price changes ₹0.50
├─ Gamma 0.0042: Delta changes 0.42% per ₹1 spot move (nonlinearity)
├─ Vega 3.45: For every 1% IV increase, option price +₹3.45
├─ Theta -0.82: Option loses ₹0.82 per day (time decay)
└─ Rho 0.156: For every 1% rate increase, option price +₹0.156
```

---

## 📈 Strategy Signal Generation

```
RSI + MACD REVERSAL STRATEGY:

Input: Bar { timestamp, open, high, low, close, volume, iv, spot }

Processing:
├─ Calculate RSI(14) on last 14 closes
├─ Calculate MACD(12,26) & histogram
├─ Check conditions:
│  ├─ RSI < 30 + MACD histogram > 0? → BUY signal
│  ├─ RSI > 70 + MACD histogram < 0? → SELL signal
│  └─ Else → HOLD
└─ Output: { action: 'BUY'|'SELL'|'HOLD', confidence: 0-10, reason }

Example:
├─ RSI = 28.5 (oversold)
├─ MACD histogram = 0.12 (bullish)
├─ Signal = { action: 'BUY', confidence: 8, reason: 'RSI oversold + MACD bullish' }
└─ Engine places bracket order
```

---

## 🔗 Integration Points

### For Live Trading

```
WebSocket Stream (DhanHQ):
NIFTY market data → JSON updates → Node.js signal processor
                                   ↓
                            Greeks Calculator
                                   ↓
                            Risk Assessment
                                   ↓
                            Order Execution
                            (DhanHQ API)
```

### Database Integration (Optional)

```
SQLite/PostgreSQL:
├─ trades_journal: { entry_time, exit_time, entry_price, ... }
├─ Greeks_history: { timestamp, delta, gamma, vega, ... }
├─ risk_events: { timestamp, risk_type, action_taken }
└─ performance_metrics: { daily_pnl, drawdown, sharpe, ... }
```

---

## 🚀 Performance Optimization

### Backtesting Speed
```
Bars to process: 10,000 (40-day backtest, 1-min bars)
Strategy calculations per bar: ~50 ops
Total ops: 500,000
Time: <5 seconds (Ruby)

Optimization techniques:
├─ Lazy calculation (only compute when needed)
├─ Array slicing (last N bars, not full history)
├─ Early exit (skip MACD if RSI not extreme)
└─ Batch processing (multi-strike parallel)
```

### Memory Usage
```
Per strategy: ~5 MB (1000 bars × fields)
Per engine: ~10 MB (position tracking, equity curve)
Total system: ~50 MB for full backtest

Optimization:
├─ Circular buffer for bar history (fixed size)
├─ Lazy Greeks calculation
└─ Stream-based reporting
```

---

## 🔐 Error Handling & Resilience

```
NETWORK ERRORS:
├─ API timeout? → Retry with exponential backoff (max 3 times)
├─ Invalid JSON response? → Log & skip bar
└─ Rate limit hit? → Wait 60s, retry

DATA ERRORS:
├─ Missing OHLC? → Reject bar, log warning
├─ Timestamp not sorted? → Sort before processing
├─ Negative volume? → Clamp to 0, continue
└─ IV < 0? → Use previous IV, flag anomaly

CALCULATION ERRORS:
├─ Division by zero? → Return null, use previous value
├─ Negative position size? → Reject trade, log
└─ Margin exceeded? → Reduce position or skip
```

---

## ✅ Testing Strategy

```
Unit Tests (RSpec):
├─ GreeksCalculator: Verify Black-Scholes accuracy
├─ Position sizing: Check margin & STT calculations
├─ State machine: All transitions validated
└─ P&L calculation: Example trades verified

Integration Tests:
├─ API client: Mock DhanHQ responses
├─ Data conversion: OHLCVS bar creation
├─ Engine → Strategy: Signal generation
└─ Full backtest: End-to-end workflow

Edge Cases:
├─ Empty data set
├─ Single bar
├─ All winning trades
├─ All losing trades
├─ Market close (3:15 PM)
└─ Overnight gap
```

---

**Last Updated**: March 2026  
**Version**: 1.0 Production
