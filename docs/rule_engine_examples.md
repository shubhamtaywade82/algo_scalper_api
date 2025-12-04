# Rule Engine Examples and Usage Guide

## How the Rule Engine Works

The rule engine evaluates risk and position management rules in priority order. Each rule checks specific conditions and returns a result indicating whether an exit should be triggered.

## Basic Flow

```
Position Data → Rule Context → Rule Engine → Rules (Priority Order) → Rule Result → Action
```

1. **Position Data** is wrapped in a **RuleContext**
2. **RuleEngine** evaluates rules in priority order (lowest number = highest priority)
3. Each **Rule** checks its conditions and returns a **RuleResult**
4. First rule that returns `exit` wins - evaluation stops
5. **RiskManagerService** executes the exit action

## Example 1: Simple Position Exit Scenario

Let's say we have a position with:
- Entry Price: ₹100
- Current LTP: ₹95
- PnL: -5% (loss)
- Stop Loss Threshold: 2%

### Step-by-Step Evaluation

```ruby
# 1. Position data is wrapped in RuleContext
context = Risk::Rules::RuleContext.new(
  position: position,           # Contains PnL, HWM, current LTP
  tracker: tracker,            # PositionTracker instance
  risk_config: {
    sl_pct: 2.0,              # 2% stop loss
    tp_pct: 5.0                # 5% take profit
  },
  current_time: Time.current
)

# 2. Rule engine evaluates rules in priority order
rule_engine = Risk::Rules::RuleFactory.create_engine(risk_config: risk_config)
result = rule_engine.evaluate(context)

# Rule evaluation order:
# Priority 10: SessionEndRule - Checks if session should end
#   → Result: no_action (session not ending)
#
# Priority 20: StopLossRule - Checks if PnL <= -2%
#   → PnL: -5%, Threshold: -2%
#   → -5% <= -2%? YES!
#   → Result: EXIT with reason "SL HIT -5.00%"
#
# Evaluation STOPS here (first exit wins)
# Remaining rules (TP, Time-based, etc.) are NOT evaluated
```

### Result
```ruby
result.exit?        # => true
result.reason       # => "SL HIT -5.00%"
result.metadata     # => { pnl_pct: -5.0, sl_pct: 2.0, ... }
```

## Example 2: Take Profit Scenario

Position with:
- Entry Price: ₹100
- Current LTP: ₹106
- PnL: +6%
- Take Profit Threshold: 5%

```ruby
context = Risk::Rules::RuleContext.new(
  position: position,
  tracker: tracker,
  risk_config: { tp_pct: 5.0, sl_pct: 2.0 }
)

# Rule evaluation:
# Priority 10: SessionEndRule
#   → no_action
#
# Priority 20: StopLossRule
#   → PnL: +6%, Threshold: -2%
#   → +6% <= -2%? NO
#   → no_action
#
# Priority 25: BracketLimitRule
#   → Checks position.sl_hit? / position.tp_hit?
#   → no_action
#
# Priority 30: TakeProfitRule
#   → PnL: +6%, Threshold: +5%
#   → +6% >= +5%? YES!
#   → Result: EXIT with reason "TP HIT 6.00%"
#
# Evaluation STOPS
```

## Example 3: Peak Drawdown Exit

Position with:
- Entry Price: ₹100
- Current LTP: ₹120
- Peak Profit: +25% (reached ₹125 at some point)
- Current Profit: +20%
- Peak Drawdown Threshold: 5%

```ruby
context = Risk::Rules::RuleContext.new(
  position: position,  # peak_profit_pct: 25.0, pnl_pct: 20.0
  tracker: tracker,
  risk_config: {
    peak_drawdown_exit_pct: 5.0,
    peak_drawdown_activation_profit_pct: 25.0
  }
)

# Rule evaluation:
# Priority 10-40: SessionEnd, SL, TP, Time-based
#   → All return no_action (conditions not met)
#
# Priority 45: PeakDrawdownRule
#   → Peak: 25%, Current: 20%
#   → Drawdown: 25% - 20% = 5%
#   → Threshold: 5%
#   → 5% >= 5%? YES!
#   → Check activation gating:
#     → Peak profit (25%) >= activation threshold (25%)? YES
#     → SL offset >= activation SL offset? YES
#   → Result: EXIT with reason "peak_drawdown_exit (drawdown: 5.00%, peak: 25.00%)"
```

## Example 4: Multiple Rules - No Exit

Position with:
- Entry Price: ₹100
- Current LTP: ₹102
- PnL: +2%
- Stop Loss: 2%, Take Profit: 5%

```ruby
# All rules evaluated, none trigger exit:
# Priority 10: SessionEndRule → no_action
# Priority 20: StopLossRule → no_action (+2% > -2%)
# Priority 25: BracketLimitRule → no_action
# Priority 30: TakeProfitRule → no_action (+2% < +5%)
# Priority 40: TimeBasedExitRule → no_action (not exit time yet)
# Priority 45: PeakDrawdownRule → skip_result (no peak yet)
# Priority 50: TrailingStopRule → skip_result (no HWM yet)
# Priority 60: UnderlyingExitRule → no_action (underlying OK)

# Final result: no_action
# Position continues to be monitored
```

## Example 5: Creating a Custom Rule

Let's create a custom rule that exits if position is held for more than 2 hours:

```ruby
module Risk
  module Rules
    class MaxHoldTimeRule < BaseRule
      PRIORITY = 35  # Between TimeBasedExitRule (40) and PeakDrawdownRule (45)

      def evaluate(context)
        return skip_result unless context.active?

        # Get position creation time from tracker
        created_at = context.tracker.created_at
        return skip_result unless created_at

        # Calculate hold time
        hold_time_hours = (context.current_time - created_at) / 3600.0
        max_hours = config.fetch(:max_hold_hours, 2.0)

        return no_action_result if hold_time_hours < max_hours

        exit_result(
          reason: "max_hold_time_exceeded (#{hold_time_hours.round(1)}h)",
          metadata: {
            hold_time_hours: hold_time_hours,
            max_hours: max_hours,
            created_at: created_at
          }
        )
      end
    end
  end
end

# Usage:
custom_rules = [
  Risk::Rules::MaxHoldTimeRule.new(config: { max_hold_hours: 2.0 })
]

rule_engine = Risk::Rules::RuleFactory.create_custom_engine(
  rules: custom_rules,
  include_defaults: true,
  risk_config: risk_config
)
```

## Example 6: Real-World Position Monitoring Flow

Here's how the rule engine is used in `RiskManagerService`:

```ruby
# In RiskManagerService.process_all_positions_in_single_loop

positions.each do |position|
  tracker = tracker_map[position.tracker_id]
  next unless tracker&.active?

  # Sync PnL from Redis cache
  sync_position_pnl_from_redis(position, tracker)

  # Create rule context
  context = Risk::Rules::RuleContext.new(
    position: position,
    tracker: tracker,
    risk_config: risk_config,
    current_time: Time.current
  )

  # Evaluate all rules
  result = rule_engine.evaluate(context)

  # If exit triggered, dispatch exit
  if result.exit?
    dispatch_exit(exit_engine, tracker, result.reason)
    next  # Skip trailing stop processing
  end

  # If no exit, continue with trailing stop management
  process_trailing_for_position(position, tracker, exit_engine)
end
```

## Rule Result Types

### Exit Result
```ruby
result = Risk::Rules::RuleResult.exit(
  reason: "SL HIT -5.00%",
  metadata: { pnl_pct: -5.0, sl_pct: 2.0 }
)

result.exit?        # => true
result.reason       # => "SL HIT -5.00%"
result.metadata     # => { pnl_pct: -5.0, sl_pct: 2.0 }
```

### No Action Result
```ruby
result = Risk::Rules::RuleResult.no_action

result.no_action?   # => true
result.exit?        # => false
result.continue?   # => true
```

### Skip Result
```ruby
result = Risk::Rules::RuleResult.skip

result.skip?        # => true
result.exit?        # => false
```

## Rule Priority System

Rules are evaluated in priority order (lower number = higher priority):

```
Priority 10: SessionEndRule          (Highest - must exit before market closes)
Priority 20: StopLossRule            (Critical - prevent large losses)
Priority 25: BracketLimitRule        (Bracket SL/TP enforcement)
Priority 30: TakeProfitRule          (Lock in profits)
Priority 35: [Custom Rules]          (Your custom rules here)
Priority 40: TimeBasedExitRule      (Time-based exits)
Priority 45: PeakDrawdownRule        (Trailing stop - peak drawdown)
Priority 50: TrailingStopRule        (Legacy trailing stop)
Priority 60: UnderlyingExitRule      (Lowest - underlying analysis)
```

**Key Point**: First rule that returns `exit` wins. Remaining rules are NOT evaluated.

## Enabling/Disabling Rules

Rules can be enabled/disabled via configuration:

```ruby
risk_config = {
  sl_pct: 2.0,
  tp_pct: 5.0,
  rules: {
    trailing_stop: { enabled: false },      # Disable trailing stop
    underlying_exit: { enabled: true },     # Enable underlying exits
    peak_drawdown: { enabled: true }       # Enable peak drawdown
  }
}

rule_engine = Risk::Rules::RuleFactory.create_engine(risk_config: risk_config)
```

## Debugging Rule Evaluation

To see which rules are being evaluated:

```ruby
# Get enabled rules
enabled_rules = rule_engine.enabled_rules
enabled_rules.each do |rule|
  puts "Rule: #{rule.name}, Priority: #{rule.priority}, Enabled: #{rule.enabled?}"
end

# Evaluate with logging
context = Risk::Rules::RuleContext.new(...)
result = rule_engine.evaluate(context)

if result.exit?
  Rails.logger.info("Exit triggered: #{result.reason}")
  Rails.logger.info("Metadata: #{result.metadata.inspect}")
end
```

## Common Patterns

### Pattern 1: Early Return for Skip Conditions
```ruby
def evaluate(context)
  return skip_result unless context.active?  # Skip if not active
  return skip_result if context.pnl_pct.nil?  # Skip if no PnL data
  
  # ... rule logic ...
end
```

### Pattern 2: Check Multiple Conditions
```ruby
def evaluate(context)
  return skip_result unless context.active?

  # Check condition 1
  return no_action_result unless condition1_met?(context)
  
  # Check condition 2
  return no_action_result unless condition2_met?(context)
  
  # All conditions met - exit
  exit_result(reason: "all_conditions_met")
end
```

### Pattern 3: Conditional Exit with Metadata
```ruby
def evaluate(context)
  return skip_result unless context.active?

  if exit_condition_met?(context)
    exit_result(
      reason: "exit_reason",
      metadata: {
        pnl_pct: context.pnl_pct,
        threshold: threshold_value,
        additional_data: calculate_additional_data(context)
      }
    )
  else
    no_action_result
  end
end
```

## Integration with RiskManagerService

The rule engine is automatically used in `RiskManagerService`:

1. **Automatic Initialization**: Rule engine is created automatically with default rules
2. **Position Monitoring**: Every position is evaluated against all rules each cycle
3. **Exit Execution**: When a rule triggers exit, `dispatch_exit` is called
4. **Backwards Compatibility**: Falls back to legacy methods if rule engine unavailable

## Best Practices

1. **Use Skip for Missing Data**: Return `skip_result` when required data is missing
2. **Use No Action for Conditions Not Met**: Return `no_action_result` when conditions aren't met
3. **Use Exit Only When Necessary**: Only return `exit_result` when exit should definitely happen
4. **Include Metadata**: Always include relevant metadata in exit results for debugging
5. **Set Appropriate Priority**: Choose priority based on rule importance (lower = more important)
6. **Handle Errors Gracefully**: Rules should handle errors and return `skip_result` or `no_action_result`

## Summary

The rule engine provides a flexible, maintainable way to manage risk and position exits:
- **Priority-based evaluation**: Rules evaluated in order of importance
- **First-match wins**: First rule that triggers exit wins
- **Extensible**: Easy to add custom rules
- **Testable**: Each rule can be tested independently
- **Observable**: Results include metadata for debugging
