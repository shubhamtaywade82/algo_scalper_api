# Setup & Installation Guide

This guide walks you through local setup and configuration of the Algo Scalper API in a way that matches the current Rails 8 trading daemon architecture.

## 1. Prerequisites

- **Ruby**: 3.3.x (see `.ruby-version`)
- **Rails**: 8.0.x (API-only)
- **Infrastructure**:
  - PostgreSQL 14+ (primary datastore + Solid Queue backend)
  - Redis 6.0+ (tick cache, PnL cache, circuit breaker, position state)
- **Broker**: DhanHQ account with v2 **Data API** and **Trading API** access enabled.

## 2. Environment Configuration

Environment is managed via standard Rails credentials and `.env` (for local development). For local runs, create a `.env` file in the project root:

```bash
# Broker Credentials (authority server or direct)
DHAN_CLIENT_ID="your_client_id"
DHAN_ACCESS_TOKEN="your_static_access_token"   # used as final fallback

# Optional TOTP-based auto-refresh
DHAN_PIN="1234"
DHAN_TOTP_SECRET="base32-totp-secret"

# Trading Daemon Control
ENABLE_TRADING_SERVICES=true                   # required for trading daemon
# DISABLE_TRADING_SERVICES=1                   # force-disable trading services if set

# Jobs Control (Solid Queue worker)
ENABLE_JOBS=true                              # controls the jobs process invoked via ./bin/dev
# ENABLE_JOBS=false                            # disable the jobs process while keeping other services running

# Database / Redis
DATABASE_URL="postgresql://user:pass@localhost:5432/algo_scalper"
REDIS_URL="redis://localhost:6379/1"
```

The DhanHQ initializer normalizes `DHAN_CLIENT_ID` / `CLIENT_ID` and `DHAN_ACCESS_TOKEN` / `ACCESS_TOKEN`, so either naming convention is accepted.

## 3. Trading Configuration (`config/algo.yml`)

`config/algo.yml` is the primary source of truth for trading behaviour. At runtime it is merged with **run-mode profiles** and overrides from the `settings` table via `AlgoConfig.fetch` (30-second cache).

- **Run mode**: Set `run_mode: production` (default), `exit_testing`, or `entry_testing` in `algo.yml`, or use `ENV RUN_MODE=...`. See [Testing profiles](../testing_profiles.md) for exit-testing (frequent entries) vs entry-testing (relaxed guards) vs production.

Key sections:

- **`indices`**: Per-index configuration for NIFTY, BANKNIFTY, SENSEX
  - segment, security_id (SID)
  - capital allocation / lot sizing
  - ADX thresholds, time filters, entry windows
- **`signals`**: Supertrend and ADX parameters, multi-timeframe settings, validation modes.
- **`risk`**: Global drawdown caps, per-trade SL/TP, premium guards, and time-based exits.
- **`position_sizing`**: Rupee-based or percentage-based sizing rules.
- **`trade_limits`**: Daily trade count, exposure and loss limits.
- **`chain_analyzer`**: Option chain scoring configuration used by `Options::ChainAnalyzer`.
- **`paper_trading`**:
  - `paper_trading.enabled: true` → paper mode (`Orders::GatewayPaper`)
  - `paper_trading.enabled: false` → live mode (`Orders::GatewayLive`)
- **`dhanhq`**:
  - `dhanhq.enable_orders: true` must be set (or `ENABLE_ORDER=true`) before any real orders are sent.

> All percentage values in `config/algo.yml` use **DECIMAL format** (`0.12` = 12%, not `12`).

## 4. Running the System

### Standard Development (All Processes)

For a development environment that matches production behaviour, run all four processes via `bin/dev`:

```bash
./bin/dev
```

The jobs process can be skipped by setting `ENABLE_JOBS=false` in your environment before running `./bin/dev`; the proc entry will log that the worker is disabled and stay idle so Foreman keeps the other services running.

This uses `Procfile.dev` to start:

- `web` — Rails API server on port 3001
- `trading` — trading daemon (`ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon`)
- `jobs` — Solid Queue worker
- `dashboard` — Next.js dashboard (in `dashboard/`)

### API-Only Development (No Trading Daemon)

If you only need the Rails API (no trading threads), you can start the web server alone:

```bash
bin/rails server -p 3001
```

In this mode the trading daemon is not started; endpoints still function for health checks, settings, dashboard reads, etc.

### Trading Daemon (Manual)

The trading logic runs in a separate long-running process managed by `TradingSystem::Supervisor`. To start it manually (outside `bin/dev`):

```bash
ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon
```

The daemon will:

- Run only the WebSocket feed if the market is closed.
- Start all 11 services when the market is open (see `lib/trading_system/bootstrap.rb`).

## 5. Paper Trading Mode

To validate strategies safely:

- Ensure `paper_trading.enabled: true` in `config/algo.yml`.
- Ensure `dhanhq.enable_orders: false` (or omit/leave `ENABLE_ORDER` unset) so that all orders are treated as dry-run in logs.

In this configuration:

- Market data and option chains are still fetched from live DhanHQ APIs.
- Order placement goes through `Orders::GatewayPaper`.
- PnL is computed from real ticks, but fills are simulated.
