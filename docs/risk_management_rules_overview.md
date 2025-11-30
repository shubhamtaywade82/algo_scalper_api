# Risk Management Rules Overview

## Introduction

Risk management is central to trading, using automated rules to limit losses and lock in gains. Common strategies include stop-loss orders to cap downside and take-profit orders to secure gains. Advanced tactics like trailing stops adapt dynamically, letting trades run while protecting accumulated profit. In algorithmic trading, a priority-based rule engine can enforce these strategies: each rule checks conditions (e.g. loss threshold, time limit, market structure) and the first matching rule triggers an exit.

## Core Risk Management Concepts

### Stop-Loss (SL)

**Purpose:** Automatically exits a trade if loss exceeds a set percentage, limiting risk.

**How It Works:** A Stop-LossRule enforces a maximum loss per trade. For example, a 2% SL means "exit if PnL ≤ –2%". This is analogous to placing a stop-loss order at a price that limits loss.

**Example:**
- Entry: ₹100
- Current LTP: ₹96
- PnL: –4%
- SL Threshold: 2%

**Rule Evaluation:**
```
Priority 20: StopLossRule
  → PnL: -4%, Threshold: -2%
  → -4% <= -2%? YES ✅
  → Result: EXIT with reason "SL HIT -4.00%"
```

**Key Point:** Stop-loss orders automate exits and "limit losses and reduce risk". The rule engine ensures this happens automatically without constant monitoring.

---

### Take-Profit (TP)

**Purpose:** Exits a trade once a target gain is reached, securing profits.

**How It Works:** A TakeProfitRule exits when PnL ≥ target (e.g. +5%), like a take-profit order set at a profit price.

**Example:**
- Entry: ₹100
- Current LTP: ₹107
- PnL: +7%
- TP Threshold: 5%

**Rule Evaluation:**
```
Priority 30: TakeProfitRule
  → PnL: +7%, Threshold: +5%
  → +7% >= +5%? YES ✅
  → Result: EXIT with reason "TP HIT 7.00%"
```

**Key Point:** Take-profit orders "lock in gains at predetermined levels". In the rule engine, this happens automatically when the target is reached.

---

### Priority System

**How It Works:** Both rules are checked in priority order (SL typically higher priority than TP). If multiple conditions are met, the rule with higher priority executes first. For instance, even if both SL and TP conditions are satisfied, the SL may take precedence if it has higher priority in the engine.

**Example - SL Overrides TP:**
- Entry: ₹100
- Current LTP: ₹96
- PnL: –4%
- SL: 2%, TP: 5%

**Rule Evaluation:**
```
Priority 20: StopLossRule
  → -4% <= -2%? YES ✅
  → Result: EXIT (SL triggered)

[Evaluation STOPS]
[TakeProfitRule is NOT evaluated]
```

**Key Point:** The "first-match-wins" approach ensures only one exit is taken per evaluation cycle. Higher priority rules (lower number) are evaluated first.

---

## Trailing Stops and Peak-Drawdown

### Trailing Stop Concept

**Purpose:** A dynamic stop-loss that follows the price to protect gains. It moves with the market and exits only if the price reverses by a set amount.

**How It Works:** Trailing stops are adaptive stop-losses that move with favorable price moves. As price rises (for a long position), the trailing stop "locks in profits" by moving up. If price later falls by the trail amount, the position exits. This "automatically adjusts with the market price to lock in profits".

**Example:**
- Entry: ₹100
- Price peaks at ₹125 (+25% gain)
- Current price drops to ₹120 (+20% gain)
- Drop from peak: 25% – 20% = 5%
- Threshold: 5%

**Rule Evaluation:**
```
Priority 45: PeakDrawdownRule
  → Peak: 25%, Current: 20%
  → Drawdown: 5% >= 5%? YES ✅
  → Result: EXIT with reason "peak_drawdown_exit (drawdown: 5.00%, peak: 25.00%)"
```

**Key Point:** Trailing stops let profits run and exit on reversal. They are "especially useful" in trending markets to maximize gains while managing risk.

---

### PeakDrawdownRule

**Purpose:** Tracks the highest profit (%) reached and exits if current profit drops by a set percentage from that peak.

**How It Works:** This is effectively a trailing stop defined in percentages rather than price. Like all trailing stops, it "protects profits by moving with the market".

**Example:**
- Entry: ₹100
- Peak Profit: ₹125 (+25% gain)
- Current Profit: ₹120 (+20% gain)
- Drawdown Threshold: 5%

**Rule Evaluation:**
```
Priority 45: PeakDrawdownRule
  → Peak: 25%, Current: 20%
  → Drawdown: 5% >= 5%? YES ✅
  → Result: EXIT
```

**Key Point:** The peak-drawdown rule implements trailing stop logic in a custom way: it triggers on a percentage drop from peak profit.

---

### SecureProfitRule

**Purpose:** A specialized trailing strategy that activates once profit exceeds a high threshold (e.g. ₹1000), then applies a tighter drawdown limit (e.g. 3% vs a normal 5%).

**How It Works:** This secures gains while still allowing upside. For instance, after securing ₹1000 profit, if the position's profit falls by 3% from its peak, the rule exits. This ensures profits are "locked in" before letting the trade run further.

**Example:**
- Entry: ₹100
- Current Profit: ₹1200 (₹1000+ secured)
- Peak Profit: ₹1500 (+50% gain)
- Current Profit: ₹1400 (+40% gain)
- Drawdown: 50% – 40% = 10%
- Secure Threshold: ₹1000
- Tight Drawdown: 3%

**Rule Evaluation:**
```
Priority 35: SecureProfitRule
  → Profit: ₹1400 >= ₹1000? YES ✅
  → Peak: 50%, Current: 40%
  → Drawdown: 10% >= 3%? YES ✅
  → Result: EXIT with reason "secure_profit_exit"
```

**Key Point:** The secure-profit rule implements trailing stop logic with a monetary threshold: it secures a monetary profit level with a tight trailing stop.

---

## Time-Based Exits

**Purpose:** Ensures positions are closed by a certain time (e.g. market close). Often traders set daily time limits to avoid overnight/after-hours risk.

**How It Works:** A TimeBasedExitRule ensures positions are closed by a certain time (e.g. market close). For example, forcing exit at 3:20 PM means "exit by end of session if profit criteria are met".

**Example 1 - Minimum Profit Not Met:**
- Exit time: 3:20 PM
- Current Profit: ₹100
- Minimum Profit: ₹200

**Rule Evaluation:**
```
Priority 40: TimeBasedExitRule
  → Current time >= Exit time? YES
  → Profit: ₹100 >= ₹200? NO ❌
  → Result: no_action (minimum profit not met)
```

**Example 2 - Minimum Profit Met:**
- Exit time: 3:20 PM
- Current Profit: ₹300
- Minimum Profit: ₹200

**Rule Evaluation:**
```
Priority 40: TimeBasedExitRule
  → Current time >= Exit time? YES
  → Profit: ₹300 >= ₹200? YES ✅
  → Result: EXIT with reason "time-based exit (15:20)"
```

**Key Point:** Time-based exits apply an automatic close at a scheduled time if conditions (like minimum profit) are satisfied. This helps capture gains and avoid holding positions past the intended horizon. Time-based exits are simple to implement and can reduce drawdowns by limiting how long a trade is held. For intraday trading, a forced session-end exit prevents overnight risk.

---

## Underlying Market Structure and Trend Checks

**Purpose:** Monitors the broader market or underlying instrument to exit on adverse moves.

**How It Works:** Some rules monitor the broader market or underlying instrument. For instance, a Break of Structure (BOS) signal indicates a trend shift. In technical analysis, a BOS occurs when price breaks a previous high (in an uptrend) or low (in a downtrend). Such breaks often confirm a trend; conversely, a break against a trade's direction suggests weakness.

**Example - Break of Structure:**
- Position: Long (bullish)
- Market BOS State: Broken
- Market BOS Direction: Bearish

**Rule Evaluation:**
```
Priority 60: UnderlyingExitRule
  → BOS state: broken, BOS direction: bearish
  → Position direction: bullish
  → Structure break against position? YES ✅
  → Result: EXIT with reason "underlying_structure_break"
```

**Key Point:** Monitoring market structure (breaks of trend levels) helps exit if underlying conditions weaken. A break of a key level opposite to your position is a common exit signal in technical trading.

---

### ATR Collapse

**Purpose:** Signals falling volatility, which can precede reversals or illiquid moves.

**How It Works:** An ATR collapse (sharp drop in Average True Range) signals falling volatility, which can precede reversals or illiquid moves. Exiting when volatility falls below a threshold is an advanced risk check.

**Example:**
- Position: Long
- Underlying ATR Trend: Falling
- Underlying ATR Ratio: 0.60
- ATR Ratio Threshold: 0.65

**Rule Evaluation:**
```
Priority 60: UnderlyingExitRule
  → ATR trend: falling
  → ATR ratio: 0.60 < 0.65? YES ✅
  → Result: EXIT with reason "underlying_atr_collapse"
```

**Key Point:** While not directly cited, it parallels technical advice: traders often use volatility indicators (like ATR) to adjust stops and gauge risk. A break of a key level opposite to your position is a common exit signal in technical trading.

---

## Priority and Combined Rules

### Priority System

**How It Works:** The rule engine evaluates rules by priority. Higher priority rules (lower number) run first. For example, a SessionEndRule (priority 10) might force an exit at market close regardless of profit. If it triggers, no other rules (like TP or SL) are checked afterward. This "first exit wins" logic ensures critical conditions (like no overnight risk) take precedence over others.

**Rule Priority Order:**
1. **SessionEndRule** (Priority: 10) - Highest priority
2. **StopLossRule** (Priority: 20)
3. **BracketLimitRule** (Priority: 25)
4. **TakeProfitRule** (Priority: 30)
5. **SecureProfitRule** (Priority: 35)
6. **TimeBasedExitRule** (Priority: 40)
7. **PeakDrawdownRule** (Priority: 45)
8. **TrailingStopRule** (Priority: 50)
9. **UnderlyingExitRule** (Priority: 60) - Lowest priority

---

### Combined Rules Examples

#### Session End Overrides Profit

**Scenario:**
- Entry: ₹100
- Current LTP: ₹110
- PnL: +10%
- TP Threshold: 5%
- Time: 3:16 PM IST (after session end deadline)

**Rule Evaluation:**
```
Priority 10: SessionEndRule
  → Session ending? YES ✅
  → Result: EXIT with reason "session end (deadline: 3:15 PM IST)"

[Evaluation STOPS IMMEDIATELY]
[TakeProfitRule is NOT evaluated, even though TP is hit]
```

**Key Point:** Even if TP is hit (+10%), a later session end exit triggers first at 3:15 PM. Session end has highest priority - it overrides all other rules.

---

#### Stop-Loss Before Take-Profit

**Scenario:**
- Entry: ₹100
- Current LTP: ₹96
- PnL: –4%
- SL: 2%, TP: 5%

**Rule Evaluation:**
```
Priority 20: StopLossRule
  → -4% <= -2%? YES ✅
  → Result: EXIT (SL triggered)

[Evaluation STOPS]
[TakeProfitRule is NOT evaluated]
```

**Key Point:** If the price falls 4% (breaching a 2% SL) but TP would have hit, the higher-priority SL rule fires first.

---

### Rule States: Enabled, Disabled, Skip

**Enabled Rules:** Rules that are active and will be evaluated.

**Disabled Rules:** Rules can be disabled via configuration. A disabled rule is skipped entirely.

**Example - Disabled Rule:**
```yaml
risk:
  sl_pct: 0  # Zero threshold effectively disables SL rule
```

**Skip Result:** Rules can return `skip_result` when:
- Missing required data (e.g., nil PnL)
- Position already exited
- Rule conditions cannot be evaluated

**Example - Missing Data:**
```
Priority 20: StopLossRule
  → context.pnl_pct → nil
  → return skip_result ❌
  → Rule SKIPPED
```

**Error Handling:** Errors in one rule are caught and logged, letting later rules still run. This fail-safe behavior keeps the engine robust.

**Key Takeaway:** The engine's priority system ensures the most important rules fire first, and the first rule to demand exit stops further checks. This is critical in cases where multiple exit conditions coincide.

---

## Data Freshness and Live Feeds

### Importance of Live Data

**Why It Matters:** Accurate, up-to-the-minute data is vital. The system uses live market data (via WebSocket and Redis) for PnL and price, not stale database records.

**How It Works:**
1. **WebSocket Ticks:** Real-time market data arrives via WebSocket
2. **Redis Cache:** Redis is updated in real time with price ticks
3. **ActiveCache Sync:** Position's cached data is synced before rule evaluation
4. **Staleness Check:** If Redis data is older than a threshold (e.g., 30 seconds), the engine falls back to any available live feed

**Data Flow:**
```
WebSocket Tick → MarketFeedHub → Redis PnL Cache → ActiveCache → Rule Evaluation
```

**Example - Stale Data Handling:**
```
sync_position_pnl_from_redis(position, tracker)
  → redis_pnl[:timestamp] = 45 seconds ago
  → Time.current - timestamp = 45 seconds
  → 45 > 30? YES ❌
  → return (data too stale, don't use)
```

**Key Point:** Rules always use live price and PnL data (e.g. from Redis or in-memory cache) to ensure timely exits. Outdated data could cause misfires or misses of exit triggers.

---

## Complete Rule Summary

The rule engine applies prioritized, configurable rules to manage trading risk:

| Rule | Priority | Purpose | Trigger Condition |
|------|----------|---------|-------------------|
| **SessionEndRule** | 10 | Forces exit at session close | Session ending (3:15 PM IST) |
| **StopLossRule** | 20 | Limits losses | PnL ≤ –SL% |
| **BracketLimitRule** | 25 | Enforces bracket SL/TP | position.sl_hit? or position.tp_hit? |
| **TakeProfitRule** | 30 | Secures gains | PnL ≥ TP% |
| **SecureProfitRule** | 35 | Secures profits above threshold | Profit ≥ ₹1000 & drawdown ≥ 3% |
| **TimeBasedExitRule** | 40 | Closes at set time | Time ≥ exit_time & profit ≥ min |
| **PeakDrawdownRule** | 45 | Trailing stop on peak | Drawdown ≥ threshold from peak |
| **TrailingStopRule** | 50 | Legacy trailing stop | HWM drop ≥ threshold |
| **UnderlyingExitRule** | 60 | Market structure checks | BOS break, trend weak, ATR collapse |

---

## Key Principles

### 1. Priority-Based Evaluation
- Rules are evaluated in priority order (lower number = higher priority)
- First rule that triggers exit wins - evaluation stops immediately
- Critical rules (session end, stop loss) have highest priority

### 2. First-Match-Wins
- Only one exit is taken per evaluation cycle
- Higher priority rules override lower priority rules
- Prevents conflicting exit actions

### 3. Fail-Safe Behavior
- Rule errors are caught and logged
- Evaluation continues to next rule on error
- Missing data causes rules to skip (not fail)
- System remains robust even with partial failures

### 4. Live Data Requirement
- Rules use real-time market data (WebSocket, Redis)
- Stale data is rejected
- Ensures timely and accurate exits

### 5. Configurable and Extensible
- Rules can be enabled/disabled via configuration
- Thresholds are configurable per rule
- New rules can be added easily
- Custom rule engines can be created

---

## Benefits

This framework ensures each position is evaluated against robust risk rules, automating exits to **"manage risk without constant monitoring"**. The prioritized, first-hit-wins design, along with real-time data feeds, creates an extensible, testable system for systematic trade risk management.

**Key Benefits:**
- ✅ **Automated Risk Management** - No manual intervention needed
- ✅ **Prioritized Exits** - Critical rules fire first
- ✅ **Real-Time Data** - Decisions based on current market state
- ✅ **Fail-Safe Design** - Robust error handling
- ✅ **Configurable** - Adjust thresholds to match trading style
- ✅ **Extensible** - Easy to add new rules

---

## Related Documentation

- **Architecture Details:** `docs/rule_engine_architecture.md`
- **All Scenarios:** `docs/rule_engine_all_scenarios.md`
- **Secure Profit Rule:** `docs/secure_profit_rule.md`
- **Data Sources:** `docs/rule_engine_data_sources.md`
- **Examples:** `docs/rule_engine_examples.md`
