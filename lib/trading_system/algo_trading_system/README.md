# 📊 NSE/BSE Options Production Trading System

A battle-tested, professional-grade framework for intraday options trading on Indian markets (NIFTY, BANKNIFTY, SENSEX) using the DhanHQ API. This system supports both high-fidelity historical backtesting and live paper/live trading with strict risk enforcement.

## 🚀 Key Features

- **7-State Deterministic FSM**: A rigid Finite State Machine (IDLE → SIGNAL → ENTRY → OPEN → MGMT → EXIT → CLOSE) ensures zero look-ahead bias and production-safe execution.
- **DhanHQ V2 Integration**: Deep integration with DhanHQ's expired options API, featuring 30-day automatic chunking, retry logic, and support for IV, OI, and Spot data.
- **Production Risk Engine**:
  - **Dynamic Position Sizing**: Max 2.5% equity risk per trade.
  - **Regulatory Compliance**: Automatic STT (0.05%) and Margin (30%) calculation.
  - **Hard Stops**: 1.5% mandatory stop-loss and 3:15 PM IST hard market exit.
- **Greeks Engine**: Real-time Black-Scholes calculations (Delta, Gamma, Vega, Theta) via Node.js bridge.
- **Multi-Strike Analysis**: Orchestrator for simultaneous backtesting across ATM, ITM, and OTM strikes with unified reporting.

## 🛠 Tech Stack

- **Backend**: Ruby 3.2+ (Core simulation and execution logic)
- **Real-time Engine**: Node.js (High-precision Greeks and IV calculations)
- **Data**: DhanHQ API V2
- **Testing**: RSpec with VCR for reliable API mocking

## 📖 Documentation

- [00_START_HERE](00_START_HERE.txt)
- [Quick Reference](QUICK_REFERENCE.md)
- [Implementation Guide](IMPLEMENTATION_GUIDE.md)
- [Architecture Details](ARCHITECTURE.md)
- [Greeks Calculator Guide](GREEKS_GUIDE.md)
- [DHAN API Mapping](DHAN_API_MAPPING.md)
- [DHAN API Visual Guide](DHAN_API_VISUAL_GUIDE.md)

## 📖 Quick Start

### 1. Setup Environment
```bash
cp .env.example .env
# Add your AUTH_SERVER_BEARER_TOKEN (to fetch Dhan tokens)
```

### 2. Synchronize Authentication
```bash
bin/setup_auth
# This fetches the latest DhanHQ access_token and client_id automatically
```

### 3. Run a Backtest
```bash
# Run with custom capital (e.g. ₹5 Lakhs)
bin/backtest --underlying sensex --capital 500000 --strategy ema_crossover

# Compare all available strategies
rake backtest:compare

# OR use the CLI for real historical data
bin/backtest --underlying nifty --strategy rsi_macd --from 2024-01-01 --to 2024-01-31
```

## ⚙️ Configuration

The system's behavior and risk limits can be adjusted in two primary locations:

### 1. Global Settings (`config/settings.yml`)
Used for live trading and system-wide defaults:
- `capital`: Default trading equity (e.g., `5000000`).
- `risk_per_trade_pct`: Maximum equity risk per position (default `2.5%`).

### 2. Backtest CLI (`bin/backtest`)
Override defaults for specific simulation runs:
- `--capital` or `-c`: Set starting capital for the session.
- `--interval` or `-i`: Set the spot data timeframe.

### 4. Start Live Trading (Paper/Live Mode)
```bash
# Start paper trading with default settings
bin/trade --strategy ema_crossover --symbol NIFTY

# Start live trading with 5-minute interval for SENSEX
bin/trade --strategy rsi_macd --symbol SENSEX --interval 5 --env live

# List all available strategies
bin/trade --list-strategies
```

## 📊 Backtest Reports

The system generates unified reports in `backtest_results/` for every run:
- **`summary_*.json`**: Complete metrics (Win Rate, Sharpe, Max DD, etc.).
- **`trades_*.csv`**: Detailed trade journal for spreadsheet analysis.
- **`dashboard_*.html`**: Interactive visual dashboard for visual verification.

## 🎲 Available Strategies

| Strategy | Logic | Target Market |
|----------|-------|---------------|
| `rsi_macd` | Mean reversion using RSI oversold + MACD bullish crossover | Volatile sideways |
| `bollinger_breakout` | High-momentum breakout of standard deviation bands | Trending |
| `iv_spike_momentum` | Volatility expansion filter with volume confirmation | News/Earnings |
| `vwap_breakout` | Institutional trend following using volume-weighted price | High-volume index |

## 🧪 Development & Quality

```bash
# Run full test suite
bundle exec rspec

# Run code quality gate (ruby_mastery)
rake quality
```

## ⚠️ Risk Warnings
- **STT Calculation**: STT is calculated at 0.05% on total **Contract Value**, not just margin.
- **Time Cutoff**: System forces all intraday positions to close at 15:15 IST.
- **Look-ahead Bias**: The FSM is designed to fill orders only on the *next* available bar open.

---
**Version**: 1.0 Production-Ready | **Last Updated**: March 2026
