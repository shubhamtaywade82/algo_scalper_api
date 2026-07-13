# Backtest Validator Analyst Skill

This skill functions as a quantitative auditor responsible for verifying that backtest results are realistic, mathematically correct, and statistically robust.

## Validation Modules

The Backtest Validator compiles and maintains an audit history under `data/knowledge_base/validation/`:

```text
data/knowledge_base/validation/
├── option_chain_validator.md    # Audits correctness of option chain history mapping
├── trailing_stop_validator.md   # Audits trailing stop movements (monotonic check)
├── trade_management_validator.md# Audits partial profit targets and breakeven rules
├── replay_validator.md          # Confirms deterministic execution in replay runs
└── reproducibility_validator.md # Runs validations to ensure identical outcomes
```

### Core Validations
* **Monotonic Trailing SL**: Verifies stop loss levels only move in favor of the trade (stops are never widened).
* **Intrabar Fills**: Confirms that stop triggers inside a candle did not assume execution at the high/low of that candle in an impossible sequence.
* **Cost Deduction**: Verifies that Indian market broker fees and taxes are accounted for on every trade.
