# Merged from `algo_trading_system/`

Options production trading framework with 7-state FSM and Node.js Greeks bridge.

**Origin:** `trading-workspace/algo_trading_system/`  
**Merged:** 2026-07-12  
**Original commits:** 11  
**Original files:** 53

## What's here

- **7-state deterministic FSM** (IDLE→SIGNAL→ENTRY→OPEN→MGMT→EXIT→CLOSE)
- **Node.js Greeks calculator bridge**
- **Risk engine** — multilevel risk gating
- **4 strategies** — RSI/MACD, Bollinger, IV Spike, VWAP

## Structure

```
lib/trading_system/
├── bin/           # CLI entry points (backtest, trade)
├── config/        # Settings
├── lib/           # Core framework code
├── spec/          # Tests
└── Gemfile
```
