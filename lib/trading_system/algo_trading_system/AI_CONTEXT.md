# AI CONTEXT — Quick Reference for Agents

This file gives agents the condensed context needed to start working immediately.
Read this first, then read the referenced documents for full detail.

---

## What This Project Is

A **production Ruby algorithmic trading system** for buying NSE options intraday,
integrated with the DhanHQ brokerage API.

---

## Tech Stack

| Layer           | Technology           |
|-----------------|----------------------|
| Language        | Ruby 3.2+            |
| HTTP Client     | Faraday + faraday-retry |
| WebSocket       | websocket-client-simple |
| Config          | dry-configurable + YAML |
| Events          | dry-events (EventBus) |
| Autoloading     | Zeitwerk             |
| Testing         | RSpec + VCR + Timecop |

---

## Key Constraints (Memorize These)

1. Code lives exclusively in `src/` and `config/`
2. Do not modify `.md` files
3. Do not hardcode API keys — use `ENV[...]` via dotenv
4. Every order must have a stop-loss — `RiskEngine` enforces this
5. Backtest and live trading must use identical strategy code
6. No look-ahead bias in backtest — feed candles one at a time
7. Market hours are 09:15–15:30 IST; trading window is 09:20–15:20 IST
8. Lot sizes: NIFTY=75, BANKNIFTY=30, FINNIFTY=65

---

## File Relationships

```
AGENT.md              ← you are reading me; start here
SYSTEM_PROMPT.md      ← trading system identity and mandate
ARCHITECTURE.md       ← module design, data flows, component diagram
IMPLEMENTATION_GUIDE.md ← coding standards, data structures, contracts
DHAN_API_MAPPING.md   ← exact API payloads — do not invent fields
DOMAIN_KNOWLEDGE.md   ← NSE market facts as ground truth
STRATEGY_RULES.md     ← entry/exit rules for all strategies
TASKS.md              ← ordered implementation checklist
specs/api_contract.md ← inter-module interface contracts
specs/strategy_rules.md ← formal strategy specifications
```

---

## Module Dependency Order

Build in this order to avoid dependency issues:

```
1. utils/event_bus.rb
2. utils/logger.rb
3. utils/config.rb
4. utils/time_helpers.rb
5. api/dhan_client.rb
6. market_data/candle_loader.rb
7. indicators/* (base first, then EMA, RSI, ATR)
8. strategies/* (base first, then concrete strategies)
9. execution/* (risk_engine first, then order_manager, position_tracker)
10. backtest/*
11. live_runner.rb
```

---

## Environment Variables Required

```bash
DHAN_CLIENT_ID=your_client_id
DHAN_ACCESS_TOKEN=your_access_token
TRADING_ENV=paper        # paper | live
LOG_LEVEL=info           # debug | info | warn | error
```

---

## Quick Start After Implementation

```bash
# Run a backtest
bundle exec ruby bin/backtest --strategy ema_crossover --from 2024-01-01 --to 2024-03-31

# Start live trading (paper mode)
TRADING_ENV=paper bundle exec ruby bin/trade --strategy ema_crossover

# Run tests
bundle exec rspec
```
