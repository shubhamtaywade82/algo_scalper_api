# algo_scalper_api

Rails 8 API backend for **fully autonomous** intraday options scalping on Indian index markets (NIFTY, BANKNIFTY, SENSEX). Self-contained pipeline: signal generation → options analysis → capital allocation → order execution → position management.

## Stack

- Ruby on Rails 8, API-only mode
- PostgreSQL
- Redis (tick cache, PnL cache, position state)
- Solid Queue (background job processing — not Sidekiq)
- Solid Cable (ActionCable WebSocket backend)
- Solid Cache (Rails.cache backend)
- DhanHQ v2 via `dhanhq` gem (broker API + WebSocket)
- Optional: Ollama (local LLM via `ollama-client`) for AI technical analysis
- Optional: Telegram Bot for notifications

## Commands

```bash
bundle install
rails db:setup
rails db:migrate
bundle exec rspec
bundle exec rspec spec/path/file_spec.rb
bundle exec rubocop
bundle exec rake rswag:specs:swaggerize # regenerate swagger/v1/swagger.yaml from RSwag specs
bin/brakeman --no-pager                # security scan
./bin/dev                              # start all processes (web + trading + jobs + dashboard)
bin/jobs                               # start Solid Queue worker standalone
ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon  # trading daemon standalone
```

## Architecture

```
app/services/
  core/
    event_bus.rb                   # internal pub/sub between subsystems
  live/                            # real-time runtime (the trading brain)
    market_feed_hub.rb             # WebSocket tick distribution
    position_tracker_pruner.rb
    risk_manager_service.rb        # PnL guard, daily limits, kill switch
    exit_engine.rb                 # unified exit logic
    trailing_engine.rb             # trailing stop management
    reconciliation_service.rb
    order_update_handler.rb
    gateway.rb                     # DhanHQ order gateway
  capital/                         # position sizing
  dhan/                            # DhanHQ integration
  indicators/                      # Supertrend, ADX, EMA stack
  entries/                         # entry guard (duplicate prevention, cooldown)
  market/                          # options chain analyzer, strike selection
  adapters/                        # broker adapters

app/jobs/
  ai_technical_analysis_job.rb
  smc_scanner_job.rb
```

## Trading flow

```
Signal Scheduler
  → Signal Engine (Supertrend + ADX)
  → Comprehensive Validation (entry guard, cooldown, daily limits)
  → Options Chain Analysis (ATM±1, liquidity scoring)
  → Capital Allocation (risk-based sizing)
  → Order Execution (DhanHQ gateway)
  → Position Management (risk_manager, trailing_engine, exit_engine)
```

## Critical rules

- **DhanHQ only** — no Delta Exchange code
- Live subsystems communicate via **direct method calls** — `event_bus.rb` exists but has zero subscribers; do not treat it as the active communication layer (it is infrastructure for future use, not current behaviour)
- `Risk::CircuitBreaker` exists (`app/services/risk/circuit_breaker.rb`) — singleton backed by Rails.cache (Solid Cache); API at `GET/POST/DELETE /api/circuit_breaker/trip`; `EntryGuard` checks it before every entry, `RiskManagerService` force-closes all positions when tripped
- WebSocket event handlers must be **idempotent** — the feed can reconnect and replay
- `exit_engine.rb` is the single source of truth for exit placement — `RiskManagerService` and `TrailingEngine` detect exit conditions and call it directly
- `TickQuery` returns `nil` on cache miss (silently) — callers that receive nil must treat it as stale data, not zero
- Position sizing must go through `capital/` — never inline the math elsewhere
- Solid Queue is the job runner (not Sidekiq) — use `ApplicationJob`, not `ApplicationWorker`
- Redis tick cache is write-through — if Redis is down, fall back gracefully, don't crash
- Never write to the DB from within WebSocket tick handlers — enqueue a job instead
