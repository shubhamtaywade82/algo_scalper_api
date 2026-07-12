# Merged from `smc_signal/`

SuperTrend/RSI/ADX options signal generator with walk-forward calibration.

**Origin:** `trading-workspace/smc_signal/`  
**Merged:** 2026-07-12  
**Original commits:** 13

## What's here

- **Signal generator** — SuperTrend/RSI/ADX options buying signals
- **Walk-forward calibration** — rolling train/validate parameter search
- **Options backtester** — backtest with SL/TP/max-hold
- **Options policy calibration** — moneyness preferences from historical data

## Structure

```
lib/calibration/
├── lib/           # Libraries (signal generator, indicators, policy)
├── scripts/       # CLI tools (optimize, walk_forward, backtest options)
├── runner.rb      # Main CLI runner
├── spec/          # Tests
└── Gemfile
```
