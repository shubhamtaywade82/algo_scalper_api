# Merged from `backtest_engine/`

Options backtesting engine for NIFTY/SENSEX using DhanHQ v2 data.

**Origin:** `trading-workspace/backtest_engine/`  
**Merged:** 2026-07-12  
**Original commits:** 30  
**Original files:** 54

## Structure

```
lib/backtest_engine/
├── lib/           # Backtesting engine code
├── spec/          # Tests
├── backtest_engine.gemspec
└── Gemfile
```

The engine is index-driven: Index engine → Option Mapper → Strategy Engine → Execution Engine → Runner.
