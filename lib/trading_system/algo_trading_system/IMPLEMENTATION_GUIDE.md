# 🛠 Implementation Guide

This guide explains how to set up and customize the production backtesting system.

## 🔑 Authentication
The system uses a remote auth server to fetch DhanHQ tokens.
1. Add `AUTH_SERVER_BEARER_TOKEN` to your `.env`.
2. Run `bin/setup_auth` to populate `DHAN_ACCESS_TOKEN`.

## 📈 Data Ingestion
Use `Api::DhanApiClient` to fetch historical options data.
```ruby
api = Api::DhanApiClient.new(access_token: ENV['DHAN_ACCESS_TOKEN'])
data = api.fetch_expired_options(
  underlying: :nifty,
  from_date: Date.parse('2024-01-01'),
  to_date: Date.parse('2024-01-31')
)
```

## ⚙️ Simulation Engine
The `Backtest::OptionsEngine` handles the deterministic FSM:
- `IDLE`: Watching for signals.
- `SIGNAL_DETECTED`: Validating risk rules.
- `POSITION_OPEN`: Monitoring stop-loss/target.
- `POSITION_CLOSED`: Realizing P&L.

### STT & Charges
STT is calculated at 0.05% on **Contract Value** (Price × Lot Size), not just the margin.

## ⚙️ Configuration & Risk Control

### Starting Capital
The starting capital directly affects position sizing and margin validation. It can be set in three ways (ordered by precedence):
1. **CLI Argument**: `bin/backtest --capital 500000`
2. **Backtest Script Default**: Modify the `options[:capital]` value in `bin/backtest`.
3. **Global Config**: Set the `capital` key in `config/settings.yml`.

### Risk Invariants
The `Backtest::OptionsBacktestEngine` enforces strict risk rules:
- **Position Sizing**: Automatically risks 2.5% of current equity per trade (set via `DEFAULT_POSITION_SIZE_PCT`).
- **Margin Check**: Verifies that (Premium × Quantity × 30%) + STT is less than current equity.
- **Theta Decay Exit**: A built-in safety exit that triggers if a position is held for 2+ minutes and price moves 2% against the entry.

## 🧪 Greeks Calculation
The Node.js bridge calculates Black-Scholes Greeks:
```javascript
// greeks_calculator.js
const greeks = calculateGreeks(spot, strike, t, r, iv, type);
```

## 📊 Reporting
Results are saved in `backtest_results/`:
- `summary.json`: High-level metrics.
- `trades.csv`: Detailed trade log for Excel.
- `dashboard.html`: Interactive visualization.
