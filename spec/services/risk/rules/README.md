# Rule Engine Specs

## Overview

Comprehensive test coverage for the Risk Management Rule Engine, covering all scenarios from the documentation.

## Test Files

### Core Components

1. **`base_rule_spec.rb`** - Tests for BaseRule abstract class
   - Initialization
   - Priority, name, enabled? methods
   - Helper methods (exit_result, no_action_result, skip_result)

2. **`rule_context_spec.rb`** - Tests for RuleContext
   - Attribute accessors (pnl_pct, pnl_rupees, peak_profit_pct, etc.)
   - Config value retrieval
   - Active? checks
   - Time parsing

3. **`rule_result_spec.rb`** - Tests for RuleResult
   - Exit, no_action, skip factory methods
   - Predicate methods (exit?, no_action?, skip?)
   - Metadata handling

### Individual Rule Specs

4. **`stop_loss_rule_spec.rb`** - StopLossRule tests
   - SL hit scenarios
   - Threshold variations
   - Missing data handling
   - Priority 20

5. **`take_profit_rule_spec.rb`** - TakeProfitRule tests
   - TP hit scenarios
   - Threshold variations
   - Missing data handling
   - Priority 30

6. **`secure_profit_rule_spec.rb`** - SecureProfitRule tests
   - Profit threshold activation (₹1000)
   - Drawdown protection (3%)
   - Riding profits scenarios
   - Priority 35

7. **`session_end_rule_spec.rb`** - SessionEndRule tests
   - Session end detection
   - Override behavior
   - Priority 10 (highest)

8. **`bracket_limit_rule_spec.rb`** - BracketLimitRule tests
   - SL/TP hit detection
   - Position data checks
   - Priority 25

9. **`time_based_exit_rule_spec.rb`** - TimeBasedExitRule tests
   - Time threshold checks
   - Minimum profit requirements
   - Market close handling
   - Priority 40

10. **`peak_drawdown_rule_spec.rb`** - PeakDrawdownRule tests
    - Peak drawdown detection
    - Activation gating
    - Priority 45

11. **`trailing_stop_rule_spec.rb`** - TrailingStopRule tests
    - HWM drop detection
    - Legacy method
    - Priority 50

12. **`underlying_exit_rule_spec.rb`** - UnderlyingExitRule tests
    - Structure break detection
    - Trend weakness checks
    - ATR collapse detection
    - Priority 60

### Integration Specs

13. **`rule_engine_spec.rb`** - RuleEngine tests
    - Priority-based evaluation
    - First-match-wins logic
    - Disabled rules handling
    - Skip results handling
    - Error handling
    - Rule management (add, remove, find)

14. **`rule_factory_spec.rb`** - RuleFactory tests
    - Default engine creation
    - Custom engine creation
    - Rule configuration

15. **`integration_scenarios_spec.rb`** - Integration scenarios
    - Scenario 1: Stop Loss Hit
    - Scenario 2: Take Profit Hit
    - Scenario 4: Session End Overrides Everything
    - Scenario 5: Stop Loss Overrides Take Profit
    - Scenario 7: Peak Drawdown Exit
    - Scenario 10: Time-Based Exit with Minimum Profit
    - Scenario 11: Time-Based Exit Triggered
    - Scenario 16: Multiple Rules Could Trigger
    - Scenario 17: Rule Disabled
    - Scenario 19: Position Already Exited
    - Scenario 20: Missing Entry Price
    - Scenario 29: Securing Profit Above ₹1000
    - Scenario 30: Riding Profits Below Threshold
    - Scenario 31: Allowing Further Upside After Securing

16. **`edge_cases_spec.rb`** - Edge cases
    - Zero thresholds
    - Invalid time formats
    - Stale data handling
    - Missing risk config
    - Rule evaluation errors
    - Concurrent evaluation
    - Very large/small profit values

17. **`data_freshness_spec.rb`** - Data freshness tests
    - Live data from ActiveCache
    - PnL recalculation
    - Peak profit tracking
    - High water mark tracking
    - Missing data handling
    - Data consistency

## Test Coverage

### Scenarios Covered

✅ **Basic Exit Scenarios**
- Stop loss hits
- Take profit hits
- No exit conditions met

✅ **Priority-Based Scenarios**
- Session end overriding other rules
- Stop loss vs take profit priority
- Bracket limit checks

✅ **Trailing Stop Scenarios**
- Peak drawdown exits
- Activation gating
- Legacy trailing stop method
- Secure profit rule

✅ **Time-Based Scenarios**
- Time-based exits with minimum profit
- After market close behavior

✅ **Underlying-Aware Scenarios**
- Structure breaks
- Trend weakness
- ATR collapse

✅ **Combined Rule Scenarios**
- Multiple rules triggering (priority wins)
- Disabled rules
- Skip results

✅ **Edge Cases**
- Already exited positions
- Missing entry price
- Stale data handling
- Zero thresholds
- Invalid data formats

✅ **Error Scenarios**
- Rule evaluation errors
- Missing config
- Invalid data formats

✅ **Data Flow Scenarios**
- WebSocket tick updates
- Redis sync updates
- Dual update handling

## Running Tests

```bash
# Run all rule engine specs
bundle exec rspec spec/services/risk/rules/

# Run specific spec file
bundle exec rspec spec/services/risk/rules/stop_loss_rule_spec.rb

# Run with documentation format
bundle exec rspec spec/services/risk/rules/ --format documentation
```

## Test Structure

Each spec file follows RSpec conventions:
- `describe` blocks for class/feature
- `context` blocks for scenarios
- `it` blocks for specific test cases
- `before` blocks for setup
- `let` blocks for test data

## Key Testing Patterns

1. **Factory Pattern**: Uses `Risk::Rules::RuleFactory.create_engine` for default engines
2. **Context Creation**: Uses `Risk::Rules::RuleContext.new` with position data and tracker
3. **Result Assertions**: Checks `result.exit?`, `result.no_action?`, `result.skip?`
4. **Priority Testing**: Verifies rules are evaluated in priority order
5. **Error Handling**: Tests that errors don't crash the engine

## Notes

- All specs use `require 'rails_helper'`
- Test data uses factories (`create(:position_tracker)`)
- Mocks are used for external dependencies (TradingSession, UnderlyingMonitor)
- Edge cases are thoroughly covered
- Integration scenarios match documentation examples
