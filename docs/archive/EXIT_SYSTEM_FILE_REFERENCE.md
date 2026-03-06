# Exit System File Reference

**Purpose**: Complete reference of all files involved in exit logic, rules, and engine system.

---

## 📁 Core Rule Engine Files

### Base Framework

| File | Purpose | When to Change |
|------|---------|----------------|
| `app/services/risk/rules/base_rule.rb` | Abstract base class for all rules | When adding new rule types or changing rule interface |
| `app/services/risk/rules/rule_engine.rb` | Core engine that evaluates rules in priority order | When changing evaluation logic or priority system |
| `app/services/risk/rules/rule_factory.rb` | Factory that creates rule engines with default rules | **When adding/removing default rules** |
| `app/services/risk/rules/rule_context.rb` | Context object providing data to rules | When adding new data to context (position metrics, config, etc.) |
| `app/services/risk/rules/rule_result.rb` | Result types (exit, no_action, skip) | When changing result types or adding new result types |

### Individual Rules

| File | Priority | Purpose | When to Change |
|------|----------|---------|----------------|
| `app/services/risk/rules/session_end_rule.rb` | 10 | Exits before market close (3:15 PM IST) | When changing session end logic |
| `app/services/risk/rules/stop_loss_rule.rb` | 20 | Triggers exit when PnL <= stop loss threshold | **When changing SL logic or thresholds** |
| `app/services/risk/rules/bracket_limit_rule.rb` | 25 | Enforces bracket SL/TP from position data | When changing bracket limit enforcement |
| `app/services/risk/rules/take_profit_rule.rb` | 30 | Triggers exit when PnL >= take profit threshold | **When changing TP logic or thresholds** |
| `app/services/risk/rules/secure_profit_rule.rb` | 35 | Secures profits above threshold with tighter trailing | When changing secure profit logic |
| `app/services/risk/rules/time_based_exit_rule.rb` | 40 | Exits at configured time (HH:MM) | When changing time-based exit logic |
| `app/services/risk/rules/peak_drawdown_rule.rb` | 45 | Trailing stop based on peak drawdown | **When changing peak drawdown logic** |
| `app/services/risk/rules/trailing_stop_rule.rb` | 50 | Legacy trailing stop (HWM-based) | When changing legacy trailing logic |
| `app/services/risk/rules/underlying_exit_rule.rb` | 60 | Market structure-based exits (BOS, trend, ATR) | When changing underlying analysis exits |

---

## 📁 Exit Execution Files

### Exit Engine

| File | Purpose | When to Change |
|------|---------|----------------|
| `app/services/live/exit_engine.rb` | Executes exit orders and marks trackers exited | **When changing exit execution flow** |

### Risk Manager Service

| File | Purpose | When to Change |
|------|---------|----------------|
| `app/services/live/risk_manager_service.rb` | Main service that orchestrates exit checks and execution | **When changing exit orchestration or adding new exit paths** |

**Key Methods in RiskManagerService:**
- `check_all_exit_conditions()` - Main entry point for exit checks
- `check_exit_conditions_with_rule_engine()` - Rule engine evaluation
- `check_all_exit_conditions_legacy()` - Legacy fallback
- `process_trailing_for_position()` - Trailing stop processing
- `dispatch_exit()` - Dispatches exit to exit engine
- `execute_exit()` - Self-managed exit execution

---

## 📁 Trailing Stop Files

### Trailing Engine

| File | Purpose | When to Change |
|------|---------|----------------|
| `app/services/live/trailing_engine.rb` | Per-tick trailing stop management with peak drawdown | **When changing trailing stop logic** |

**Key Methods:**
- `process_tick()` - Main processing method
- `check_peak_drawdown()` - Peak drawdown exit check
- `update_peak()` - Updates peak profit percentage
- `apply_direct_trailing_sl()` - Direct trailing SL application
- `apply_tiered_sl()` - Tiered SL application

### Trailing Configuration

| File | Purpose | When to Change |
|------|---------|----------------|
| `app/services/positions/trailing_config.rb` | Configuration and calculations for trailing stops | **When changing trailing thresholds, tiers, or calculations** |

**Key Methods:**
- `peak_drawdown_triggered?()` - Checks if peak drawdown threshold breached
- `calculate_tiered_drawdown_threshold()` - Calculates tiered threshold based on peak
- `calculate_direct_trailing_sl()` - Calculates direct trailing SL price
- `sl_offset_for()` - Gets SL offset for profit percentage
- `config` - Loads and parses trailing configuration

---

## 📁 Position Data Files

### Active Cache

| File | Purpose | When to Change |
|------|---------|----------------|
| `app/services/positions/active_cache.rb` | In-memory cache of active positions with real-time PnL | When changing position data structure or PnL calculation |

**Key Components:**
- `PositionData` struct - Position data structure
- `update_ltp()` - Updates LTP and recalculates PnL
- `recalculate_pnl()` - Recalculates PnL and updates peak

### Position Tracker Model

| File | Purpose | When to Change |
|------|---------|----------------|
| `app/models/position_tracker.rb` | Database model for position tracking | When changing exit attributes or exit-related methods |

**Key Methods:**
- `mark_exited!()` - Marks tracker as exited
- `update_exit_attributes()` - Updates exit-related attributes

---

## 📁 Order Execution Files

### Order Router

| File | Purpose | When to Change |
|------|---------|----------------|
| `app/services/trading_system/order_router.rb` | Routes exit orders to appropriate gateway | When changing order routing logic |

### Order Gateways

| File | Purpose | When to Change |
|------|---------|----------------|
| `app/services/orders/gateway.rb` | Base gateway interface | When changing gateway interface |
| `app/services/orders/gateway_paper.rb` | Paper trading gateway | When changing paper exit simulation |
| `app/services/orders/gateway_live.rb` | Live trading gateway | When changing live exit execution |

### Order Placer

| File | Purpose | When to Change |
|------|---------|----------------|
| `app/services/orders/placer.rb` | Order placement logic | When changing order placement flow |

---

## 📁 Configuration Files

### Risk Configuration

| File | Purpose | When to Change |
|------|---------|----------------|
| `config/algo.yml` | Risk configuration (SL, TP, thresholds, etc.) | **When changing exit thresholds or rule settings** |

**Key Sections:**
- `risk.sl_pct` - Stop loss percentage
- `risk.tp_pct` - Take profit percentage
- `risk.peak_drawdown_exit_pct` - Peak drawdown threshold
- `risk.trailing_mode` - Trailing mode (tiered/direct)
- `risk.trailing_tiers` - Trailing tier configuration
- `risk.direct_trailing` - Direct trailing configuration
- `feature_flags` - Feature flags for enabling/disabling rules

### Initializers

| File | Purpose | When to Change |
|------|---------|----------------|
| `config/initializers/trading_supervisor.rb` | Initializes services including RiskManagerService | When changing service initialization |

---

## 📁 Supporting Files

### Trading Session

| File | Purpose | When to Change |
|------|---------|----------------|
| `app/services/trading_session.rb` | Trading session management | When changing session end logic |

### High Water Mark

| File | Purpose | When to Change |
|------|---------|----------------|
| `app/services/positions/high_water_mark.rb` | HWM calculations for trailing stops | When changing HWM calculations |

### Underlying Monitor

| File | Purpose | When to Change |
|------|---------|----------------|
| `app/services/live/underlying_monitor.rb` | Monitors underlying instrument for structure breaks | When changing underlying analysis logic |

### Redis PnL Cache

| File | Purpose | When to Change |
|------|---------|----------------|
| `app/services/live/redis_pnl_cache.rb` | Redis cache for position PnL | When changing PnL caching logic |

---

## 📁 Test Files

### Rule Tests

| Directory | Purpose |
|-----------|---------|
| `spec/services/risk/rules/` | Unit tests for individual rules |

**Key Test Files:**
- `spec/services/risk/rules/peak_drawdown_rule_spec.rb`
- `spec/services/risk/rules/stop_loss_rule_spec.rb`
- `spec/services/risk/rules/take_profit_rule_spec.rb`
- `spec/services/risk/rules/rule_engine_spec.rb`

### Integration Tests

| Directory | Purpose |
|-----------|---------|
| `spec/services/live/` | Integration tests for exit flow |

---

## 🔄 Exit Flow Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ 1. RiskManagerService.process_all_positions_in_single_loop │
│    File: app/services/live/risk_manager_service.rb          │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. check_all_exit_conditions()                               │
│    File: app/services/live/risk_manager_service.rb          │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. check_exit_conditions_with_rule_engine()                 │
│    File: app/services/live/risk_manager_service.rb          │
│    Creates: Risk::Rules::RuleContext                         │
│    Calls: rule_engine.evaluate(context)                     │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. RuleEngine.evaluate()                                     │
│    File: app/services/risk/rules/rule_engine.rb              │
│    Evaluates rules in priority order:                        │
│    - SessionEndRule (10)                                     │
│    - StopLossRule (20)                                       │
│    - BracketLimitRule (25)                                    │
│    - TakeProfitRule (30)                                     │
│    - SecureProfitRule (35)                                   │
│    - TimeBasedExitRule (40)                                  │
│    - PeakDrawdownRule (45)                                   │
│    - TrailingStopRule (50)                                   │
│    - UnderlyingExitRule (60)                                 │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Rule.evaluate(context)                                   │
│    Files: app/services/risk/rules/*_rule.rb                  │
│    Returns: RuleResult.exit() or RuleResult.no_action()      │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. dispatch_exit(exit_engine, tracker, reason)              │
│    File: app/services/live/risk_manager_service.rb           │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. ExitEngine.execute_exit(tracker, reason)                  │
│    File: app/services/live/exit_engine.rb                    │
│    - Gets LTP from cache                                     │
│    - Calls OrderRouter.exit_market()                          │
│    - Marks tracker as exited                                 │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 8. OrderRouter.exit_market(tracker)                          │
│    File: app/services/trading_system/order_router.rb          │
│    Routes to: GatewayPaper or GatewayLive                     │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 9. Gateway.exit_market(tracker)                              │
│    Files: app/services/orders/gateway_paper.rb               │
│           app/services/orders/gateway_live.rb                │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 Common Change Scenarios

### Scenario 1: Add a New Exit Rule

**Files to Change:**
1. Create new rule file: `app/services/risk/rules/your_new_rule.rb`
   - Inherit from `BaseRule`
   - Set `PRIORITY` constant
   - Implement `evaluate(context)` method

2. Add to factory: `app/services/risk/rules/rule_factory.rb`
   - Add rule to `create_engine()` method

3. Add tests: `spec/services/risk/rules/your_new_rule_spec.rb`

4. Update config: `config/algo.yml` (if rule needs configuration)

---

### Scenario 2: Change Stop Loss Threshold

**Files to Change:**
1. **Configuration**: `config/algo.yml`
   - Change `risk.sl_pct` value

2. **Rule Logic** (if needed): `app/services/risk/rules/stop_loss_rule.rb`
   - Modify threshold calculation logic

3. **Tests**: `spec/services/risk/rules/stop_loss_rule_spec.rb`
   - Update tests with new threshold

---

### Scenario 3: Change Peak Drawdown Logic

**Files to Change:**
1. **Rule**: `app/services/risk/rules/peak_drawdown_rule.rb`
   - Modify `evaluate()` method

2. **Trailing Config**: `app/services/positions/trailing_config.rb`
   - Modify `peak_drawdown_triggered?()` or `calculate_tiered_drawdown_threshold()`

3. **Trailing Engine**: `app/services/live/trailing_engine.rb`
   - Modify `check_peak_drawdown()` if needed

4. **Configuration**: `config/algo.yml`
   - Change `risk.peak_drawdown_exit_pct` or tiered thresholds

5. **Tests**: `spec/services/risk/rules/peak_drawdown_rule_spec.rb`

---

### Scenario 4: Change Exit Execution Flow

**Files to Change:**
1. **Exit Engine**: `app/services/live/exit_engine.rb`
   - Modify `execute_exit()` method

2. **Risk Manager**: `app/services/live/risk_manager_service.rb`
   - Modify `dispatch_exit()` or `execute_exit()` methods

3. **Order Router**: `app/services/trading_system/order_router.rb`
   - Modify `exit_market()` if routing logic changes

4. **Gateways**: `app/services/orders/gateway_*.rb`
   - Modify exit order execution

---

### Scenario 5: Change Rule Priority

**Files to Change:**
1. **Rule File**: `app/services/risk/rules/your_rule.rb`
   - Change `PRIORITY` constant

2. **Factory** (if reordering): `app/services/risk/rules/rule_factory.rb`
   - Reorder rules in `create_engine()` method

3. **Documentation**: Update priority documentation

---

### Scenario 6: Add New Data to Rule Context

**Files to Change:**
1. **Rule Context**: `app/services/risk/rules/rule_context.rb`
   - Add new attribute/accessor

2. **Risk Manager**: `app/services/live/risk_manager_service.rb`
   - Update `check_exit_conditions_with_rule_engine()` to pass new data

3. **All Rules**: Update rules that need the new data

4. **Tests**: Update rule context tests

---

## 📋 Quick Reference Checklist

When making exit logic changes, check these files:

- [ ] `app/services/risk/rules/rule_factory.rb` - If adding/removing rules
- [ ] `app/services/risk/rules/rule_engine.rb` - If changing evaluation logic
- [ ] `app/services/risk/rules/rule_context.rb` - If adding new context data
- [ ] `app/services/live/risk_manager_service.rb` - If changing orchestration
- [ ] `app/services/live/exit_engine.rb` - If changing exit execution
- [ ] `app/services/live/trailing_engine.rb` - If changing trailing stops
- [ ] `app/services/positions/trailing_config.rb` - If changing trailing config
- [ ] `config/algo.yml` - If changing thresholds or configuration
- [ ] `app/models/position_tracker.rb` - If changing exit attributes
- [ ] `app/services/positions/active_cache.rb` - If changing position data structure

---

## 🔍 Finding Related Code

### Search Patterns

```bash
# Find all exit-related methods
grep -r "def.*exit" app/services/

# Find all rule evaluations
grep -r "rule_engine.evaluate" app/services/

# Find all exit dispatches
grep -r "dispatch_exit\|execute_exit" app/services/

# Find all rule result usage
grep -r "result.exit?" app/services/
```

---

## 📚 Related Documentation

- `docs/rule_engine_architecture.md` - Architecture overview
- `docs/rule_engine_examples.md` - Usage examples
- `docs/RULE_ENGINE_EFFECTIVENESS_ANALYSIS.md` - Performance analysis
- `docs/risk_management_rules_overview.md` - Rules overview

---

## ⚠️ Important Notes

1. **Rule Priority**: Lower number = higher priority. First rule that returns `exit` wins.

2. **Rule Evaluation Order**: Rules are evaluated in priority order. Evaluation stops at first `exit` result.

3. **Context Data**: All rules receive the same `RuleContext` object. Ensure context has all needed data.

4. **Exit Execution**: Exit execution is separate from rule evaluation. Rules only decide WHEN to exit, not HOW.

5. **Configuration**: Most thresholds are in `config/algo.yml`. Check there before changing code.

6. **Testing**: Always update tests when changing rules. Rules should have comprehensive test coverage.

7. **Legacy Code**: Some legacy exit methods exist in `RiskManagerService`. Rule engine is preferred.

---

## 🚀 Getting Started

To modify exit logic:

1. **Identify the change type** (new rule, modify existing rule, change threshold, etc.)
2. **Find the relevant files** using this reference
3. **Make the changes** following the architecture
4. **Update tests** to cover the changes
5. **Update configuration** if thresholds changed
6. **Test thoroughly** before deploying

---

**Last Updated**: 2025-12-09


