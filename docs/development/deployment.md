# Deployment Guide

This document covers deployment setup and operational procedures for the Algo Scalper API trading system.

## Production Environment

- **OS**: Linux (Ubuntu 22.04+ recommended)
- **Ruby**: 3.3.4
- **Rails**: 8.0.2 (API-only)
- **Process Manager**: `systemd` for managing the 4 processes (web, trading, jobs, dashboard)
- **Reverse Proxy**: Nginx (serves Rails API and proxies to Next.js dashboard)
- **Containerization**: Kamal + Docker supported (see `config/deploy.yml` and `Dockerfile`)

## Infrastructure Requirements

### PostgreSQL

- 14+ recommended
- Ensure `pg_hba.conf` allows connections from the application server
- All Solid Queue job tables live here (no separate Redis-based job queue)
- Run `rails db:migrate` after every deploy

### Redis

- Enable persistence (`appendonly yes`) to prevent loss of circuit breaker state and PnL caches during restarts
- Redis keys used:
  - Tick cache: `segment:security_id` (TTL-based)
  - PnL cache: per tracker ID
  - Circuit breaker: `risk:circuit_breaker` (must survive restarts)
  - Position HWM: per tracker ID

### DhanHQ API Access

- Production server IP must be whitelisted if DhanHQ requires IP-based security
- TOTP credentials required for token auto-refresh: `DHAN_PIN`, `DHAN_TOTP_SECRET`

### WSL2 (Development on Windows)

- Default WSL2 memory limit is 8 GB even on 32 GB systems
- Set `memory=16GB` in `~/.wslconfig` to prevent OOM kills of the trading daemon

## Environment Variables

### Required

| Variable | Purpose |
|----------|---------|
| `DHAN_CLIENT_ID` | DhanHQ client ID |
| `DHAN_ACCESS_TOKEN` | DhanHQ access token (static fallback) |
| `DATABASE_URL` | PostgreSQL connection string |
| `REDIS_URL` | Redis connection (default: `redis://127.0.0.1:6379/0`) |
| `RAILS_MASTER_KEY` | Rails credentials master key (for secrets) |

### Required for Live Trading (in addition to above)

| Variable | Purpose |
|----------|---------|
| `DHAN_PIN` | For TOTP auto-refresh |
| `DHAN_TOTP_SECRET` | For TOTP auto-refresh |
| `PLACE_ORDER` | Set to `"true"` to allow live broker order placement (safety gate in `Orders::Placer`) |

### Optional

| Variable | Default | Purpose |
|----------|---------|---------|
| `ENABLE_TRADING_SERVICES` | — | Set to `"true"` to start trading daemon |
| `LIVE_TRADING` | — | Set `"true"` for live gateway path at boot; unset/false forces paper |
| `SIGNAL_TIER` | `standard` (via YAML if unset) | `exploratory` / `standard` / `selective` — merges `config/signal_tier_presets.yml` |
| `RAILS_ENV` | `development` | Rails environment |
| `OLLAMA_MODEL` | `llama3.2:3b` | Ollama model for AI analysis |
| `OLLAMA_BASE_URL` / `OLLAMA_HOST_URL` | `http://localhost:11434` | Ollama server URL |
| `OLLAMA_TIMEOUT` | `120` | Ollama request timeout (seconds) |
| `TELEGRAM_BOT_TOKEN` | — | Telegram bot token for notifications |
| `TELEGRAM_CHAT_ID` | — | Telegram chat ID for notifications |
| `TRADER_API_BASE_URL` | — | Authority server for token provisioning (tier 1) |

## Deployment Steps

### Standard Deploy

```bash
# 1. Clone and install
git clone ...
bundle install

# 2. Configure environment
cp .env.example .env
# Edit .env with your values

# 3. Set up database
RAILS_ENV=production bundle exec rails db:setup
# (or db:migrate if database already exists)

# 4. Load recurring jobs schedule
RAILS_ENV=production bundle exec rails solid_queue:load_recurring

# 5. Start all processes
./bin/dev    # development
# or via systemd/pm2 in production
```

### Kamal Deploy (Docker)

```bash
# First-time setup
kamal setup

# Deploy
kamal deploy

# Check status
kamal status

# View logs
kamal app logs
```

### Docker Compose (Local Stack)

```bash
cp .env.example .env
# set RAILS_MASTER_KEY in .env
docker compose build
docker compose up -d
docker compose ps
docker compose logs -f web jobs trading
```

## Process Management

### Starting Individual Processes

```bash
# Web server
bin/rails server -p 3011

# Trading daemon
ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon

# Live gateway path (restart required); still needs dhanhq.enable_orders + PLACE_ORDER for broker
LIVE_TRADING=true ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon

# Solid Queue worker
bin/jobs

# Jobs standalone (alternative)
RAILS_ENV=production bundle exec rails solid_queue:start
```

### Graceful Shutdown

The trading daemon handles `SIGINT` and `SIGTERM` for graceful `stop_all`:

- Stops `Signal::Scheduler` (no new entries)
- Waits for in-flight PnL flushes
- Stops all 11 supervised services in reverse order

### Restarting After Config Changes

`AlgoConfig.fetch` has a 30-second in-process cache. For `config/algo.yml` changes:

- DB `settings` table overrides take effect within 30 seconds (no restart needed)
- Direct `algo.yml` changes require trading daemon restart

For `config/recurring.yml` changes:

```bash
rails solid_queue:load_recurring
# Restart jobs process
```

## Pre-Live Checklist

Before enabling live execution:

- [ ] `LIVE_TRADING=true` in process environment (trading daemon restart after change)
- [ ] DhanHQ credentials: `DHAN_CLIENT_ID`, `DHAN_ACCESS_TOKEN`
- [ ] TOTP credentials: `DHAN_PIN`, `DHAN_TOTP_SECRET`
- [ ] Live order gate: `PLACE_ORDER=true` env var
- [ ] Config gate: `dhanhq.enable_orders: true` in `config/algo.yml`
- [ ] Instruments synced: `rails runner 'puts Derivative.count'` (should be > 0)
- [ ] Database migrated: `rails db:migrate:status` (all up)
- [ ] Redis running: `redis-cli ping` returns PONG
- [ ] Recurring jobs loaded: `rails solid_queue:load_recurring`
- [ ] Circuit breaker not tripped: `GET /api/circuit_breaker`
- [ ] Position index clean: no phantom active positions from paper runs
- [ ] Paper test complete: run paper mode for at least 1 session to verify all systems work

## Monitoring

### Logs

```bash
# Development
tail -f log/development.log | grep -E "Signal|Entry|Exit|Risk|ERROR|FATAL"

# Production
tail -f log/production.log

# Trading-specific
grep "\[Signal\]\|\[Risk\]\|\[Exit\]\|\[Entry\]" log/production.log
```

### Health Check

```
GET /api/health
```

Returns system health including:

- Trading daemon status
- WebSocket feed health
- Circuit breaker status
- Active position count
- Recent PnL

### Key Metrics to Monitor

- Active positions count (`PositionTracker.active.count`)
- Daily PnL (`PositionTracker.exited.where("exited_at >= ?", Date.today).sum(:last_pnl_rupees)`)
- Exit path distribution (`PositionTracker.exited.group("meta->>'exit_path'").count`)
- Circuit breaker status
- Edge failure detector status per index

### Telegram Alerts

If configured (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`):

- Circuit breaker trips
- Daily stats at market close
- PnL milestones
- SMC signals

## Code Quality Checks

```bash
bundle exec rubocop                    # style/lint
bin/brakeman --no-pager                # security scan
bundle exec rspec                      # full test suite
bundle exec rspec spec/path/file_spec.rb  # single spec
```
