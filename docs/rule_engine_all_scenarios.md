# Rule Engine - All Scenarios Explained

## Table of Contents
1. [Basic Exit Scenarios](#basic-exit-scenarios)
2. [Priority-Based Scenarios](#priority-based-scenarios)
3. [Trailing Stop Scenarios](#trailing-stop-scenarios)
4. [Time-Based Scenarios](#time-based-scenarios)
5. [Underlying-Aware Scenarios](#underlying-aware-scenarios)
6. [Combined Rule Scenarios](#combined-rule-scenarios)
7. [Edge Cases](#edge-cases)
8. [Error Scenarios](#error-scenarios)
9. [Data Flow Scenarios](#data-flow-scenarios)

---

## Basic Exit Scenarios

### Scenario 1: Stop Loss Hit

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹97
- PnL: -3%
- Stop Loss Threshold: 2%

**Rule Evaluation:**
```
Priority 10: SessionEndRule
  → Session ending? NO
  → Result: no_action

Priority 20: StopLossRule
  → PnL: -3%, Threshold: -2%
  → -3% <= -2%? YES ✅
  → Result: EXIT with reason "SL HIT -3.00%"

[Evaluation STOPS - remaining rules not checked]
```

**Outcome:** Position exited immediately at -3% loss.

---

### Scenario 2: Take Profit Hit

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹107
- PnL: +7%
- Take Profit Threshold: 5%

**Rule Evaluation:**
```
Priority 10: SessionEndRule
  → no_action

Priority 20: StopLossRule
  → PnL: +7%, Threshold: -2%
  → +7% <= -2%? NO
  → Result: no_action

Priority 25: BracketLimitRule
  → position.tp_hit? → NO
  → Result: no_action

Priority 30: TakeProfitRule
  → PnL: +7%, Threshold: +5%
  → +7% >= +5%? YES ✅
  → Result: EXIT with reason "TP HIT 7.00%"

[Evaluation STOPS]
```

**Outcome:** Position exited at +7% profit.

---

### Scenario 3: No Exit Conditions Met

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹101.5
- PnL: +1.5%
- Stop Loss: 2%, Take Profit: 5%

**Rule Evaluation:**
```
Priority 10: SessionEndRule → no_action
Priority 20: StopLossRule → no_action (+1.5% > -2%)
Priority 25: BracketLimitRule → no_action
Priority 30: TakeProfitRule → no_action (+1.5% < +5%)
Priority 40: TimeBasedExitRule → no_action (not exit time)
Priority 45: PeakDrawdownRule → skip_result (no peak yet)
Priority 50: TrailingStopRule → skip_result (no HWM yet)
Priority 60: UnderlyingExitRule → no_action (underlying OK)

Final Result: no_action
```

**Outcome:** Position continues to be monitored, no exit triggered.

---

## Priority-Based Scenarios

### Scenario 4: Session End Overrides Everything

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹110
- PnL: +10%
- Stop Loss: 2%, Take Profit: 5%
- Time: 3:16 PM IST (after session end deadline)

**Rule Evaluation:**
```
Priority 10: SessionEndRule
  → TradingSession::Service.should_force_exit?
  → should_exit: true ✅
  → Result: EXIT with reason "session end (deadline: 3:15 PM IST)"

[Evaluation STOPS IMMEDIATELY]
[TakeProfitRule (Priority 30) is NOT evaluated, even though TP is hit]
```

**Outcome:** Position exited due to session end, regardless of profit/loss.

**Key Learning:** Session end has highest priority - it overrides all other rules.

---

### Scenario 5: Stop Loss Overrides Take Profit

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹96
- PnL: -4%
- Stop Loss: 2%, Take Profit: 5%

**Rule Evaluation:**
```
Priority 10: SessionEndRule → no_action
Priority 20: StopLossRule
  → PnL: -4%, Threshold: -2%
  → -4% <= -2%? YES ✅
  → Result: EXIT with reason "SL HIT -4.00%"

[Evaluation STOPS]
[TakeProfitRule is NOT evaluated]
```

**Outcome:** Stop loss triggered first (higher priority than take profit).

---

### Scenario 6: Bracket Limit Check Before Take Profit

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹108
- PnL: +8%
- Position has bracket TP set at ₹107
- Take Profit Threshold: 5%

**Rule Evaluation:**
```
Priority 10: SessionEndRule → no_action
Priority 20: StopLossRule → no_action
Priority 25: BracketLimitRule
  → position.tp_hit? → YES (₹108 >= ₹107) ✅
  → Result: EXIT with reason "TP HIT 8.00%"

[Evaluation STOPS]
[TakeProfitRule (Priority 30) is NOT evaluated]
```

**Outcome:** Bracket limit triggered first (higher priority than percentage-based TP).

---

## Trailing Stop Scenarios

### Scenario 7: Peak Drawdown Exit

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹120
- Peak Profit: +25% (reached ₹125 at some point)
- Current Profit: +20%
- Peak Drawdown Threshold: 5%

**Rule Evaluation:**
```
Priority 10-40: SessionEnd, SL, TP, Time-based
  → All return no_action

Priority 45: PeakDrawdownRule
  → Peak: 25%, Current: 20%
  → Drawdown: 25% - 20% = 5%
  → Threshold: 5%
  → 5% >= 5%? YES ✅
  → Check activation gating:
    → Peak profit (25%) >= activation threshold (25%)? YES
    → SL offset >= activation SL offset? YES
  → Result: EXIT with reason "peak_drawdown_exit (drawdown: 5.00%, peak: 25.00%)"

[Evaluation STOPS]
```

**Outcome:** Position exited due to peak drawdown - profit dropped 5% from peak.

---

### Scenario 8: Peak Drawdown Not Activated

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹120
- Peak Profit: +20% (reached ₹120)
- Current Profit: +15%
- Peak Drawdown: 5%
- Activation Threshold: 25% profit required

**Rule Evaluation:**
```
Priority 45: PeakDrawdownRule
  → Peak: 20%, Current: 15%
  → Drawdown: 5% >= 5%? YES
  → Check activation gating:
    → Peak profit (20%) >= activation threshold (25%)? NO ❌
  → Result: no_action (gating prevents exit)

[Evaluation CONTINUES]
```

**Outcome:** Peak drawdown threshold met, but activation gating prevents exit (peak profit not high enough).

---

### Scenario 9: Trailing Stop (Legacy Method)

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹110
- PnL: ₹1000
- High Water Mark: ₹1200
- Exit Drop Threshold: 10%

**Rule Evaluation:**
```
Priority 10-45: All other rules → no_action or skip

Priority 50: TrailingStopRule
  → PnL: ₹1000, HWM: ₹1200
  → Drop: (1200 - 1000) / 1200 = 16.67%
  → Threshold: 10%
  → 16.67% >= 10%? YES ✅
  → Result: EXIT with reason "TRAILING STOP drop=0.167"

[Evaluation STOPS]
```

**Outcome:** Position exited due to trailing stop - profit dropped 16.67% from high water mark.

---

## Time-Based Scenarios

### Scenario 10: Time-Based Exit with Minimum Profit

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹101
- PnL: +1% (₹100 profit)
- Time: 3:20 PM IST
- Exit Time: 3:20 PM
- Minimum Profit: ₹200

**Rule Evaluation:**
```
Priority 10-30: SessionEnd, SL, TP → no_action

Priority 40: TimeBasedExitRule
  → Current time: 3:20 PM, Exit time: 3:20 PM
  → 3:20 PM >= 3:20 PM? YES
  → Check minimum profit:
    → PnL: ₹100, Min profit: ₹200
    → ₹100 < ₹200? YES ❌
  → Result: no_action (minimum profit not met)

[Evaluation CONTINUES]
```

**Outcome:** Exit time reached, but minimum profit threshold not met - position continues.

---

### Scenario 11: Time-Based Exit Triggered

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹103
- PnL: +3% (₹300 profit)
- Time: 3:20 PM IST
- Exit Time: 3:20 PM
- Minimum Profit: ₹200

**Rule Evaluation:**
```
Priority 40: TimeBasedExitRule
  → Current time >= Exit time? YES
  → Check minimum profit:
    → PnL: ₹300, Min profit: ₹200
    → ₹300 >= ₹200? YES ✅
  → Result: EXIT with reason "time-based exit (15:20)"

[Evaluation STOPS]
```

**Outcome:** Position exited at exit time because minimum profit threshold was met.

---

### Scenario 12: Time-Based Exit After Market Close

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹105
- PnL: +5%
- Time: 3:35 PM IST
- Exit Time: 3:20 PM
- Market Close: 3:30 PM

**Rule Evaluation:**
```
Priority 40: TimeBasedExitRule
  → Current time: 3:35 PM, Exit time: 3:20 PM
  → 3:35 PM >= 3:20 PM? YES
  → Market close: 3:30 PM
  → 3:35 PM >= 3:30 PM? YES ❌
  → Result: no_action (after market close)

[Evaluation CONTINUES]
```

**Outcome:** Exit time passed, but current time is after market close - time-based exit skipped.

---

## Underlying-Aware Scenarios

### Scenario 13: Underlying Structure Break

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹105
- PnL: +5%
- Position Direction: Bullish (long)
- Underlying BOS State: Broken
- Underlying BOS Direction: Bearish

**Rule Evaluation:**
```
Priority 10-45: All other rules → no_action

Priority 60: UnderlyingExitRule
  → Underlying exits enabled? YES
  → UnderlyingMonitor.evaluate(position)
  → BOS state: broken, BOS direction: bearish
  → Position direction: bullish
  → Structure break against position? YES ✅
  → Result: EXIT with reason "underlying_structure_break"

[Evaluation STOPS]
```

**Outcome:** Position exited due to underlying structure break - market structure broke against position direction.

---

### Scenario 14: Underlying Trend Weakness

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹102
- PnL: +2%
- Underlying Trend Score: 8.0
- Trend Score Threshold: 10.0

**Rule Evaluation:**
```
Priority 60: UnderlyingExitRule
  → Underlying trend score: 8.0
  → Threshold: 10.0
  → 8.0 < 10.0? YES ✅
  → Result: EXIT with reason "underlying_trend_weak"

[Evaluation STOPS]
```

**Outcome:** Position exited due to underlying trend weakness - trend score below threshold.

---

### Scenario 15: Underlying ATR Collapse

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹101
- PnL: +1%
- Underlying ATR Trend: Falling
- Underlying ATR Ratio: 0.60
- ATR Ratio Threshold: 0.65

**Rule Evaluation:**
```
Priority 60: UnderlyingExitRule
  → ATR trend: falling
  → ATR ratio: 0.60
  → Threshold: 0.65
  → 0.60 < 0.65? YES ✅
  → Result: EXIT with reason "underlying_atr_collapse"

[Evaluation STOPS]
```

**Outcome:** Position exited due to underlying ATR collapse - volatility collapsed below threshold.

---

## Combined Rule Scenarios

### Scenario 16: Multiple Rules Could Trigger (Priority Wins)

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹97
- PnL: -3%
- Time: 3:20 PM IST
- Stop Loss: 2%, Take Profit: 5%

**Rule Evaluation:**
```
Priority 10: SessionEndRule
  → Session ending? NO
  → Result: no_action

Priority 20: StopLossRule
  → PnL: -3%, Threshold: -2%
  → -3% <= -2%? YES ✅
  → Result: EXIT with reason "SL HIT -3.00%"

[Evaluation STOPS]
[TimeBasedExitRule (Priority 40) is NOT evaluated, even though exit time reached]
```

**Outcome:** Stop loss triggered first (higher priority) - time-based exit not evaluated.

**Key Learning:** When multiple rules could trigger, highest priority rule wins.

---

### Scenario 17: Rule Disabled

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹97
- PnL: -3%
- Stop Loss: 2%
- Stop Loss Rule: Disabled

**Rule Evaluation:**
```
Priority 10: SessionEndRule → no_action

Priority 20: StopLossRule
  → Rule enabled? NO ❌
  → Rule SKIPPED (not evaluated)

Priority 25: BracketLimitRule → no_action
Priority 30: TakeProfitRule → no_action
...

[Evaluation CONTINUES to next rules]
```

**Outcome:** Stop loss rule disabled - position not exited even though loss exceeds threshold.

---

### Scenario 18: Rule Returns Skip

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹102
- PnL: nil (data not available)
- Stop Loss: 2%

**Rule Evaluation:**
```
Priority 20: StopLossRule
  → context.pnl_pct → nil
  → return skip_result ❌
  → Rule SKIPPED

Priority 25: BracketLimitRule → no_action
Priority 30: TakeProfitRule
  → context.pnl_pct → nil
  → return skip_result ❌
  → Rule SKIPPED

[Evaluation CONTINUES]
```

**Outcome:** Rules that require PnL data skip when data unavailable - evaluation continues to other rules.

---

## Edge Cases

### Scenario 19: Position Already Exited

**Position State:**
- Status: Exited
- Entry Price: ₹100
- Exit Price: ₹105

**Rule Evaluation:**
```
Priority 10: SessionEndRule
  → context.active? → NO (tracker.exited?)
  → return skip_result ❌

[All rules check context.active? first]
[All rules return skip_result]
[Final result: no_action]
```

**Outcome:** No rules evaluated - position already exited.

---

### Scenario 20: Missing Entry Price

**Position State:**
- Entry Price: nil
- Current LTP: ₹105
- PnL: Cannot calculate

**Rule Evaluation:**
```
Priority 20: StopLossRule
  → context.pnl_pct → nil (cannot calculate without entry)
  → return skip_result ❌

Priority 30: TakeProfitRule
  → context.pnl_pct → nil
  → return skip_result ❌

[Most rules skip - cannot evaluate without entry price]
```

**Outcome:** Rules that require PnL skip - position cannot be properly evaluated.

---

### Scenario 21: Stale Redis Data

**Position State:**
- Entry Price: ₹100
- Redis PnL Timestamp: 45 seconds ago (stale)
- Current LTP: Unknown

**Data Sync:**
```
sync_position_pnl_from_redis(position, tracker)
  → redis_pnl[:timestamp] = 45 seconds ago
  → Time.current - timestamp = 45 seconds
  → 45 > 30? YES ❌
  → return (data too stale, don't use)
```

**Rule Evaluation:**
```
Rules use ActiveCache position data (updated from WebSocket)
→ If WebSocket data available, rules use that
→ If not, rules may skip due to missing data
```

**Outcome:** Stale Redis data rejected - rules use WebSocket-updated ActiveCache data or skip.

---

### Scenario 22: Zero Stop Loss Threshold

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹95
- PnL: -5%
- Stop Loss Threshold: 0% (disabled)

**Rule Evaluation:**
```
Priority 20: StopLossRule
  → sl_pct = 0
  → return skip_result (threshold is zero) ❌

[Rule skipped - stop loss effectively disabled]
```

**Outcome:** Zero threshold means rule is effectively disabled - no stop loss enforcement.

---

## Error Scenarios

### Scenario 23: Rule Evaluation Error

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹105
- PnL: +5%

**Rule Evaluation:**
```
Priority 20: StopLossRule
  → evaluate(context)
  → StandardError raised ❌
  → Error logged: "[RuleEngine] Error evaluating rule stop_loss: ..."
  → Evaluation CONTINUES to next rule

Priority 25: BracketLimitRule
  → Evaluates normally
  → Result: no_action
```

**Outcome:** Rule error caught and logged - evaluation continues to next rule (fail-safe behavior).

---

### Scenario 24: Missing Risk Config

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹97
- PnL: -3%
- Risk Config: nil or empty

**Rule Evaluation:**
```
Priority 20: StopLossRule
  → context.config_bigdecimal(:sl_pct, BigDecimal('0'))
  → config_value(:sl_pct) → nil
  → default: BigDecimal('0')
  → sl_pct = 0
  → return skip_result ❌
```

**Outcome:** Rules use defaults when config missing - effectively disabled if default is zero.

---

### Scenario 25: Invalid Time Format

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹102
- PnL: +2%
- Time Exit Config: "invalid_time"

**Rule Evaluation:**
```
Priority 40: TimeBasedExitRule
  → context.config_time(:time_exit_hhmm)
  → Time.zone.parse("invalid_time") → nil
  → return skip_result ❌
```

**Outcome:** Invalid time format causes rule to skip - time-based exit not enforced.

---

## Data Flow Scenarios

### Scenario 26: WebSocket Tick Updates ActiveCache

**Flow:**
```
1. WebSocket tick arrives: { segment: 'NSE_FNO', security_id: '12345', ltp: 105.50 }
2. MarketFeedHub.on_tick callback fires
3. ActiveCache.handle_tick(tick)
   → position.update_ltp(105.50)
   → position.recalculate_pnl()
   → position.pnl_pct = +5.5%
4. Rule evaluation uses updated position data
```

**Outcome:** ActiveCache updated in real-time from WebSocket - rules use latest data.

---

### Scenario 27: Redis Sync Updates ActiveCache

**Flow:**
```
1. Redis PnL Cache has: { pnl: 550, pnl_pct: 5.5, ltp: 105.50, timestamp: now }
2. sync_position_pnl_from_redis(position, tracker)
   → Fetches from Redis
   → Updates position.pnl = 550
   → Updates position.pnl_pct = 5.5
   → Updates position.current_ltp = 105.50
3. Rule evaluation uses synced data
```

**Outcome:** Redis sync ensures ActiveCache has latest PnL data before rule evaluation.

---

### Scenario 28: Both WebSocket and Redis Update

**Flow:**
```
1. WebSocket tick updates ActiveCache: ltp = 105.50
2. Redis sync also updates ActiveCache: pnl_pct = 5.5
3. Rule evaluation uses most recent data from both sources
```

**Outcome:** Dual updates ensure data consistency - rules use freshest available data.

---

## Secure Profit Scenarios

### Scenario 29: Securing Profit Above ₹1000

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹120
- PnL: ₹1000 (10% gain)
- Peak Profit: ₹1250 (25% gain)
- Current Profit: ₹1100 (22% gain)
- Secure Threshold: ₹1000
- Drawdown Threshold: 3%

**Rule Evaluation:**
```
Priority 10-30: SessionEnd, SL, TP, BracketLimit → no_action

Priority 35: SecureProfitRule
  → Profit: ₹1100 >= ₹1000? YES ✅
  → Peak: 25%, Current: 22%
  → Drawdown: 25% - 22% = 3%
  → Threshold: 3%
  → 3% >= 3%? YES ✅
  → Result: EXIT with reason "secure_profit_exit (profit: ₹1100, drawdown: 3% from peak 25%)"

[Evaluation STOPS]
```

**Outcome:** Position exited at ₹1100, securing profit above ₹1000 threshold while protecting against reversal.

---

### Scenario 30: Riding Profits Below Threshold

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹105
- PnL: ₹500 (5% gain)
- Secure Threshold: ₹1000

**Rule Evaluation:**
```
Priority 35: SecureProfitRule
  → Profit: ₹500 >= ₹1000? NO ❌
  → Result: no_action (rule not activated)

[Evaluation CONTINUES]
```

**Outcome:** Position continues to ride - rule doesn't interfere with profits below threshold.

---

### Scenario 31: Allowing Further Upside After Securing

**Position State:**
- Entry Price: ₹100
- Current LTP: ₹130
- PnL: ₹1500 (30% gain)
- Peak Profit: ₹1500 (30% gain)
- Current Profit: ₹1500 (30% gain)
- Secure Threshold: ₹1000
- Drawdown Threshold: 3%

**Rule Evaluation:**
```
Priority 35: SecureProfitRule
  → Profit: ₹1500 >= ₹1000? YES ✅
  → Peak: 30%, Current: 30%
  → Drawdown: 30% - 30% = 0%
  → Threshold: 3%
  → 0% >= 3%? NO ❌
  → Result: no_action (allows riding)

[Evaluation CONTINUES]
```

**Outcome:** Position continues to ride - profit can grow further, protected if it drops 3% from peak.

---

## Summary Table

| Scenario        | Triggering Rule | Priority | Key Condition  |
| --------------- | --------------- | -------- | -------------- |
| Stop Loss Hit   | StopLossRule    | 20       | PnL <= -SL%    |
| Take Profit Hit | TakeProfitRule  | 30       | PnL >= +TP%    |
| Session End     | SessionEndRule  | 10       | Session ending |
| Secure Profit | SecureProfitRule | 35 | Profit >= ₹1000 & drawdown >= 3% |
| Time-Based Exit | TimeBasedExitRule | 40 | Time >= exit_time & profit >= min |
| Peak Drawdown | PeakDrawdownRule | 45 | Drawdown >= threshold |
| Trailing Stop | TrailingStopRule | 50 | HWM drop >= threshold |
| Underlying Break | UnderlyingExitRule | 60 | Structure break against position |
| Bracket Limit | BracketLimitRule | 25 | position.sl_hit? or position.tp_hit? |
3. **Skip vs No Action**: Skip = can't evaluate, No Action = evaluated but conditions not met
4. **Live Data**: Rules use Redis PnL cache (synced with WebSocket) for real-time data
5. **Fail-Safe**: Rule errors don't crash system - evaluation continues to next rule
6. **Configurable**: Rules can be enabled/disabled via configuration
7. **Extensible**: Easy to add custom rules with appropriate priority
