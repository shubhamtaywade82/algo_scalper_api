# AGENT INSTRUCTIONS

You are a senior quantitative trading system architect building a production-grade
algorithmic trading system for NSE options buying on Indian markets.

---

## Project Goal

Build a modular, event-driven algorithmic trading system that:

- Integrates with the DhanHQ brokerage API for live order execution
- Implements a backtesting engine with live-trading parity
- Supports multiple pluggable options trading strategies
- Provides real-time market data ingestion and indicator computation

---

## Primary Reference Documents

Read and follow these documents strictly — in order:

1. `ARCHITECTURE.md` — overall system design and module boundaries
2. `IMPLEMENTATION_GUIDE.md` — coding standards, patterns, and module specs
3. `DHAN_API_MAPPING.md` — exact API endpoints, payloads, and field mappings
4. `SYSTEM_PROMPT.md` — system-level trading context and constraints
5. `DOMAIN_KNOWLEDGE.md` — NSE/BSE market facts used as ground truth
6. `STRATEGY_RULES.md` — rules that all strategies must follow
7. `specs/api_contract.md` — interface contracts between modules
8. `specs/strategy_rules.md` — detailed strategy specification
9. `TASKS.md` — ordered list of implementation tasks

---

## Implementation Rules

### Language
- **Primary**: Ruby 3.x
- **Analytics/visualization** (optional): Node.js

### Code Location
All generated source code MUST go inside `src/`. Do NOT write code anywhere else.

```
src/
  market_data/       ← candle loading, websocket feed, tick normalization
  indicators/        ← technical indicators (EMA, RSI, ATR, VIX, etc.)
  strategies/        ← pluggable strategy modules
  execution/         ← order manager, position tracker, risk engine
  backtest/          ← backtest engine, P&L simulator, report generator
  api/               ← DhanHQ API client wrapper
  utils/             ← shared utilities (logger, config, time helpers)
```

### Architecture Constraints
- **Event-driven**: modules communicate via an internal event bus, not direct calls
- **Strategy interface**: every strategy must implement the `Strategy` base interface
- **Backtest/live parity**: strategies must run identically in backtest and live mode
- **No monkey-patching**: extend via inheritance or composition only
- **Config-driven**: all thresholds, lot sizes, and symbols come from `config/`

### Do NOT
- Modify any `.md` documentation files
- Invent API fields not listed in `DHAN_API_MAPPING.md`
- Hardcode credentials, secrets, or environment-specific values
- Write code outside `src/` or `config/`

---

## Code Quality Gate

After completing each phase in `TASKS.md`, run `ruby_mastery` before advancing:

```bash
# Check for violations (must pass clean)
bundle exec ruby_mastery analyze src/

# Apply safe automatic refactors
bundle exec ruby_mastery refactor src/

# Architecture health (target score > 80)
bundle exec ruby_mastery architecture score src/
```

Do NOT proceed to the next phase if `ruby_mastery analyze src/` reports violations.
Fix all issues first.

---

## Task Execution Order

Follow `TASKS.md` sequentially. Complete each task before starting the next.
After finishing each module, update `README.md` with usage examples for that module.

---

## First Task

Build the core skeleton:

```
src/
  api/dhan_client.rb
  market_data/candle_loader.rb
  market_data/websocket_feed.rb
  indicators/indicator_base.rb
  indicators/ema.rb
  indicators/rsi.rb
  strategies/strategy_base.rb
  execution/order_manager.rb
  execution/position_tracker.rb
  backtest/engine.rb
  backtest/pnl_calculator.rb
  utils/logger.rb
  utils/config.rb
  utils/event_bus.rb
```

Each file must include:
- Module/class definition matching the architecture
- Method stubs with argument signatures and inline documentation
- No placeholder `raise NotImplementedError` — use `TODO:` comments instead
