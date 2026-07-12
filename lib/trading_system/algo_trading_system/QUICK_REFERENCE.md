# 📖 Quick Reference Guide

## 🛠 Commands

| Task | Command |
|------|---------|
| Setup Auth | `bin/setup_auth` |
| Run Backtest | `bin/backtest --underlying nifty` |
| Backtest w/ Capital | `bin/backtest -u nifty -c 500000` |
| Run Live (Paper) | `rake trade` |
| Run Code Quality | `rake quality` |
| Run Unit Tests | `bundle exec rspec` |

## 🎲 Pre-Built Strategies

### 1️⃣ RSI + MACD Reversal
- **Buy**: RSI < 30 (oversold) + MACD histogram > 0
- **Sell**: RSI > 70 (overbought) + MACD histogram < 0
- **Best for**: Mean reversion in sideways markets.

### 2️⃣ Bollinger Bands Breakout
- **Buy**: Close > Upper BB + Volume > 1.2x avg
- **Sell**: Close < Lower BB + Volume > 1.2x avg
- **Best for**: Catching high-momentum trends.

### 3️⃣ IV Spike + Volume Momentum (Recommended ⭐)
- **Trigger**: IV > 1.4x 20-day average
- **Confirm**: Volume > 1.5x + RSI neutral/strong
- **Best for**: Profiting from volatility expansions in options.

### 4️⃣ VWAP Breakout
- **Buy**: Close > VWAP + Volume increase
- **Sell**: Close < VWAP + Volume increase
- **Best for**: Institutional trend following.

## ⚠️ Risk Invariants
- **Max Risk**: 2.5% per trade.
- **Stop-Loss**: 1.5% hard limit.
- **Auto-Exit**: 3:15 PM IST.
- **STT**: 0.05% on total contract value.
