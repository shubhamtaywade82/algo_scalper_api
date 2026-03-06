# Setup & Installation Guide

This guide walks you through the configuration and deployment of the Algorithmic Scalper API.

## 1. Prerequisites
- **Ruby**: 3.3.x (refer to `.ruby-version`)
- **Rails**: 7.x
- **Infrastructure**: Redis (6.0+) and PostgreSQL (13+)
- **Broker**: A valid DhanHQ account with "Data API" and "Trading API" access enabled.

## 2. Environment Configuration
Create a `.env` file in the root directory:

```bash
# Broker Credentials
DHAN_CLIENT_ID="your_client_id"
DHAN_ACCESS_TOKEN="your_access_token"

# System Control
ENABLE_TRADING_SERVICES=true
# DISABLE_TRADING_SERVICES=false # Set to true to prevent all automated trades

# Database
DATABASE_URL="postgresql://user:pass@localhost:5432/algo_scalper"
REDIS_URL="redis://localhost:6379/1"
```

## 3. Trading Configuration (`config/algo.yml`)
The `algo.yml` file is the central source of truth for trading logic.

- **Indices**: Define which indices to watch (NIFTY, BANKNIFTY).
- **Signals**: Configure Supertrend parameters, Timeframes, and ADX thresholds.
- **Exit Rules**: Settle SL, TP, and Trailing stop percentages.
- **Risk**: Global daily loss limits and exposure caps.

## 4. Running the System

### Standard Development
```bash
bundle exec rails s
```

### The Trading Daemon (Production/Live)
The trading logic runs in a separate long-running process managed by the `Supervisor`.
```bash
ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon
```

### Paper Trading Mode
To test strategies without financial risk, ensure the `paper: true` flag is set in the `config/algo.yml` or the environment.
