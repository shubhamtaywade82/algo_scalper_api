# Rule Engine Architecture for Risk and Position Management

## Overview

The rule engine provides a flexible, extensible framework for managing risk and position exit conditions. It replaces the previous hardcoded enforcement methods with a rule-based system that is easier to maintain, test, and extend.

## Architecture Components

### 1. Base Rule (`Risk::Rules::BaseRule`)

Abstract base class for all rules. Each rule must implement:
- `evaluate(context)` - Evaluates the rule against the given context
- `priority` - Returns the priority (lower number = higher priority)

### 2. Rule Context (`Risk::Rules::RuleContext`)

Provides all necessary data for rule evaluation:
- Position data (PnL, high water mark, current LTP, etc.)
- Tracker instance
- Risk configuration
- Current time
- Trading session information

### 3. Rule Result (`Risk::Rules::RuleResult`)

Indicates the action to take:
- `exit` - Exit should be triggered
- `no_action` - No action needed, continue evaluation
- `skip` - Skip this rule, continue to next rule

### 4. Rule Engine (`Risk::Rules::RuleEngine`)

Evaluates rules in priority order:
- Rules are sorted by priority (lower = higher priority)
- First rule that returns `exit` wins, evaluation stops
- Rules can be enabled/disabled individually
- Rules can be added/removed dynamically

### 5. Rule Factory (`Risk::Rules::RuleFactory`)

Creates rule engines with default rules:
- `create_engine(risk_config:)` - Creates engine with all default rules
- `create_custom_engine(rules:, include_defaults:, risk_config:)` - Creates custom engine

## Default Rules

Rules are evaluated in priority order:

1. **SessionEndRule** (Priority: 10) - Enforces session end exit before 3:15 PM IST
2. **StopLossRule** (Priority: 20) - Triggers exit when PnL drops below stop loss threshold
3. **BracketLimitRule** (Priority: 25) - Enforces bracket limits (SL/TP) from position data
4. **TakeProfitRule** (Priority: 30) - Triggers exit when PnL exceeds take profit threshold
5. **TimeBasedExitRule** (Priority: 40) - Triggers exit at configured time if minimum profit met
6. **PeakDrawdownRule** (Priority: 45) - Triggers exit when profit drops from peak by configured percentage (with activation gating)
7. **TrailingStopRule** (Priority: 50) - Legacy trailing stop based on high water mark drop
8. **UnderlyingExitRule** (Priority: 60) - Triggers exit based on underlying instrument state

### Trailing Stop Rules

The rule engine includes comprehensive trailing stop management:

- **PeakDrawdownRule**: Monitors peak profit percentage and triggers exit when current profit drops by a configured percentage from the peak. Includes activation gating that only activates after certain profit thresholds are reached.

- **TrailingStopRule**: Legacy method that triggers exit based on high water mark drop percentage. This is kept for backwards compatibility, but `PeakDrawdownRule` is preferred for new implementations.

The tiered trailing SL offset management (updating SL prices based on profit tiers) is still handled by `TrailingEngine` and integrated with the rule engine during position processing.

## Usage

### Basic Usage

The rule engine is automatically initialized in `RiskManagerService`:

```ruby
# Rule engine is created automatically with default rules
risk_manager = Live::RiskManagerService.new

# Rules are evaluated automatically during position monitoring
# No manual intervention needed
```

### Custom Rule Engine

To use a custom rule engine:

```ruby
custom_rules = [
  MyCustomRule.new(config: risk_config),
  AnotherCustomRule.new(config: risk_config)
]

rule_engine = Risk::Rules::RuleFactory.create_custom_engine(
  rules: custom_rules,
  include_defaults: true,
  risk_config: risk_config
)

risk_manager = Live::RiskManagerService.new(rule_engine: rule_engine)
```

### Creating Custom Rules

To create a custom rule:

```ruby
module Risk
  module Rules
    class MyCustomRule < BaseRule
      PRIORITY = 35 # Between TimeBasedExitRule and TrailingStopRule

      def evaluate(context)
        return skip_result unless context.active?

        # Your custom logic here
        if some_condition_met?(context)
          return exit_result(
            reason: 'custom_exit_reason',
            metadata: { custom_data: 'value' }
          )
        end

        no_action_result
      end

      private

      def some_condition_met?(context)
        # Check your condition
        false
      end
    end
  end
end
```

### Enabling/Disabling Rules

Rules can be enabled/disabled via configuration:

```ruby
risk_config = {
  sl_pct: 2.0,
  tp_pct: 5.0,
  # Disable a specific rule
  rules: {
    trailing_stop: { enabled: false },
    underlying_exit: { enabled: true }
  }
}
```

## Integration with RiskManagerService

The rule engine is integrated into `RiskManagerService` in two places:

1. **Main monitoring loop** (`check_all_exit_conditions`):
   - Uses rule engine to evaluate all exit conditions
   - Falls back to legacy methods if rule engine unavailable

2. **Trailing position processing** (`process_trailing_for_position`):
   - Uses rule engine for underlying exits and bracket limits
   - Falls back to legacy methods if rule engine unavailable

## Backwards Compatibility

The rule engine maintains full backwards compatibility:
- Legacy enforcement methods (`enforce_hard_limits`, `enforce_trailing_stops`, etc.) are preserved
- Rule engine is optional - falls back to legacy methods if not available
- Existing code continues to work without changes

## Benefits

1. **Maintainability**: Rules are isolated and easy to understand
2. **Testability**: Each rule can be tested independently
3. **Extensibility**: New rules can be added without modifying existing code
4. **Flexibility**: Rules can be enabled/disabled, reordered, or customized
5. **Observability**: Rule evaluation results include metadata for debugging

## Future Enhancements

Potential future enhancements:
- Rule execution metrics and monitoring
- Dynamic rule configuration via API
- Rule chaining and dependencies
- Rule performance profiling
- Rule versioning and rollback
