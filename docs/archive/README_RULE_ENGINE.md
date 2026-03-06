# Rule Engine Documentation Index

## Quick Start

- **New to Rule Engine?** Start with: [`risk_management_rules_overview.md`](./risk_management_rules_overview.md)
- **Want Examples?** See: [`rule_engine_examples.md`](./rule_engine_examples.md)
- **Need All Scenarios?** Check: [`rule_engine_all_scenarios.md`](./rule_engine_all_scenarios.md)

## Documentation Files

### Core Documentation

1. **[Risk Management Rules Overview](./risk_management_rules_overview.md)**
   - Comprehensive overview of all risk management rules
   - Explains concepts, examples, and priority system
   - **Start here** for understanding the complete system

2. **[Rule Engine Architecture](./rule_engine_architecture.md)**
   - Technical architecture details
   - Component descriptions
   - Integration with RiskManagerService

3. **[Rule Engine Examples](./rule_engine_examples.md)**
   - Practical code examples
   - Custom rule creation
   - Configuration examples

4. **[All Scenarios Explained](./rule_engine_all_scenarios.md)**
   - 31+ detailed scenarios
   - Step-by-step rule evaluation
   - Edge cases and error handling

### Specialized Documentation

5. **[Secure Profit Rule](./secure_profit_rule.md)**
   - Detailed guide for SecureProfitRule
   - Maximizing profits above ₹1000
   - Configuration and examples

6. **[Secure Profit Quick Reference](./secure_profit_quick_reference.md)**
   - Quick reference for SecureProfitRule
   - Configuration snippets
   - Common adjustments

7. **[Trailing Activation Rule](./trailing_activation_rule.md)**
   - Configurable trailing activation percentage
   - Gates when trailing rules become active
   - Works across any capital/allocation/lot size

8. **[Data Sources](./rule_engine_data_sources.md)**
   - How rules use live market data
   - WebSocket → Redis → ActiveCache flow
   - Data freshness guarantees

## Rule Priority Reference

| Priority | Rule | Purpose |
|----------|------|---------|
| 10 | SessionEndRule | Force exit at session close |
| 20 | StopLossRule | Limit losses (PnL ≤ -SL%) |
| 25 | BracketLimitRule | Enforce bracket SL/TP |
| 30 | TakeProfitRule | Secure gains (PnL ≥ TP%) |
| 35 | SecureProfitRule | Secure profits above ₹1000 |
| 40 | TimeBasedExitRule | Exit at set time |
| 45 | PeakDrawdownRule | Trailing stop on peak |
| 50 | TrailingStopRule | Legacy trailing stop |
| 60 | UnderlyingExitRule | Market structure checks |

## Key Concepts

### Priority System
- **Lower number = Higher priority**
- **First exit wins** - evaluation stops immediately
- Critical rules (session end, stop loss) have highest priority

### Rule States
- **Enabled**: Rule is active and evaluated
- **Disabled**: Rule skipped entirely (via config)
- **Skip**: Rule cannot evaluate (missing data, already exited)

### Data Flow
```
WebSocket Tick → MarketFeedHub → Redis PnL Cache → ActiveCache → Rule Evaluation
```

## Quick Examples

### Stop Loss
```ruby
# Config
risk:
  sl_pct: 2.0  # Exit if loss >= 2%

# Triggers when: PnL <= -2%
```

### Take Profit
```ruby
# Config
risk:
  tp_pct: 5.0  # Exit if profit >= 5%

# Triggers when: PnL >= +5%
```

### Secure Profit
```ruby
# Config
risk:
  secure_profit_threshold_rupees: 1000  # Activate at ₹1000
  secure_profit_drawdown_pct: 3.0        # Exit on 3% drop from peak

# Triggers when: Profit >= ₹1000 AND drawdown >= 3% from peak
```

### Trailing Activation
```ruby
# Config
risk:
  trailing:
    activation_pct: 10.0  # Activate trailing at 10% profit (configurable: 6%, 6.66%, 13.32%, etc.)

# Gates TrailingStopRule and PeakDrawdownRule
# Only activates when: pnl_pct >= activation_pct
```

## Configuration

All rules are configured in `config/algo.yml`:

```yaml
risk:
  sl_pct: 2.0
  tp_pct: 5.0
  secure_profit_threshold_rupees: 1000
  secure_profit_drawdown_pct: 3.0
  peak_drawdown_exit_pct: 5.0
  time_exit_hhmm: "15:20"
  min_profit_rupees: 200
  trailing:
    activation_pct: 10.0  # Configurable: 6%, 6.66%, 13.32%, etc.
    drawdown_pct: 3.0
  # ... more config options
```

## See Also

- **Implementation**: `app/services/risk/rules/`
- **Configuration**: `config/algo.yml`
- **Tests**: `spec/services/risk/rules/`
