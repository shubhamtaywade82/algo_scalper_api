# TASKS — Implementation Checklist

Complete tasks sequentially. Mark each task `[x]` when done.
After completing each task, update README.md with usage examples.

**Quality gate**: run `bundle exec ruby_mastery analyze src/` at the end of every
phase. Fix all violations before starting the next phase.

---

## Phase 1 — Core Infrastructure

- [x] **T01** — Create `Gemfile` with all required dependencies
- [x] **T02** — Create `src/utils/event_bus.rb` — pub/sub event bus
- [x] **T03** — Create `src/utils/logger.rb` — structured JSON logger
- [x] **T04** — Create `src/utils/config.rb` — YAML config loader
- [x] **T05** — Create `src/utils/time_helpers.rb` — IST time utilities, market hours
- [x] **T06** — Create `config/settings.yml` — default runtime config
- [x] **T07** — Create `config/strategies.yml` — default strategy parameters

---

## Phase 2 — DhanHQ API Client

- [x] **T08** — Create `src/api/dhan_client.rb` — REST client (all endpoints in DHAN_API_MAPPING.md)
- [x] **T09** — Create `src/api/websocket_feed.rb` — WebSocket subscription and tick dispatch
- [x] **T10** — Add rate limiting and retry logic to `dhan_client.rb`
- [x] **T11** — Write RSpec tests for `dhan_client.rb` using VCR cassettes

---

## Phase 3 — Market Data

- [x] **T12** — Create `src/market_data/candle_loader.rb` — loads historical + intraday candles
- [x] **T13** — Create `src/market_data/tick_normalizer.rb` — normalizes raw WebSocket ticks
- [x] **T14** — Write RSpec tests for candle loader using fixture data

---

## Phase 4 — Indicators

- [x] **T15** — Create `src/indicators/indicator_base.rb` — abstract base class
- [x] **T16** — Create `src/indicators/ema.rb` — EMA with configurable period
- [x] **T17** — Create `src/indicators/rsi.rb` — RSI with configurable period (default 14)
- [x] **T18** — Create `src/indicators/atr.rb` — ATR with configurable period (default 14)
- [x] **T19** — Create `src/indicators/vix_reader.rb` — reads India VIX from market feed
- [x] **T20** — Write RSpec tests for all indicators using known-output fixture data

---

## Phase 5 — Strategies

- [x] **T21** — Create `src/strategies/strategy_base.rb` — abstract strategy base
- [x] **T22** — Create `src/strategies/ema_crossover.rb` — EMA 9/21 crossover strategy
- [x] **T23** — Create `src/strategies/orb_strategy.rb` — Opening Range Breakout (first 30 min)
- [x] **T24** — Create `src/strategies/vix_spike_strategy.rb` — VIX spike reversal strategy
- [x] **T25** — Write RSpec tests for each strategy using replayed candle sequences

---

## Phase 6 — Execution Engine

- [x] **T26** — Create `src/execution/risk_engine.rb` — enforces all risk rules
- [x] **T27** — Create `src/execution/order_manager.rb` — order creation, modification, cancellation
- [x] **T28** — Create `src/execution/position_tracker.rb` — tracks open positions and P&L
- [x] **T29** — Wire execution engine to EventBus (subscribe to strategy signals)
- [x] **T30** — Write RSpec tests for risk engine (all edge cases)

---

## Phase 7 — Backtest Engine (V1)

- [x] **T31** — Create `src/backtest/engine.rb` — candle replay loop
- [x] **T32** — Create `src/backtest/pnl_calculator.rb` — trade-level P&L with slippage + brokerage
- [x] **T33** — Create `src/backtest/report_generator.rb` — CSV and JSON report output
- [x] **T34** — Create `examples/backtest_example.rb` — runnable backtest example
- [x] **T35** — Write RSpec tests for backtest engine (no look-ahead assertion)

---

## Phase 8 — Integration & Live Runner

- [x] **T36** — Create `src/live_runner.rb` — wires all modules for live trading session
- [x] **T37** — Create `bin/trade` — CLI entry point for live session
- [x] **T38** — Create `bin/backtest` — CLI entry point for running backtests
- [x] **T39** — End-to-end integration test with paper trading mode

---

## Phase 9 — Polish & Production Readiness

- [x] **T40** — Add Rake tasks (`rake backtest`, `rake trade`, `rake spec`)
- [x] **T41** — Update README.md with full usage instructions and examples
- [x] **T42** — Add `.env.example` with required environment variable keys
- [x] **T43** — Final code review: ensure no hardcoded secrets, all risk rules enforced
- [x] **T44** — Run `ruby_mastery analyze src/` — fix all remaining violations
- [x] **T45** — Run `ruby_mastery architecture score src/` — target score > 80
- [x] **T46** — Run `ruby_mastery refactor src/` — apply all safe automatic refactors
- [x] **T47** — Add `rake quality` task that runs `ruby_mastery analyze src/` in CI

---

## Phase 10 — Advanced Options Features (New)

- [x] **T48** — Implement 7-state FSM in `OptionsBacktestEngine` for zero-bias simulation.
- [x] **T49** — Integrate Node.js `greeks_calculator.js` for real-time Greeks (Delta, Theta, etc.).
- [x] **T50** — Implement `DhanApiClient` V2 with 30-day auto-chunking and IV/OI support.
- [x] **T51** — Implement `OptionsBacktestOrchestrator` for multi-strike parallel analysis.
- [x] **T52** — Consolidate strategies into modular `TradingStrategies` factory with indicator history.
- [x] **T53** — Professional reporting suite: Unified JSON, CSV, and interactive HTML dashboards.
- [x] **T54** — Enhanced Risk Management: 2.5% equity risk position sizing and 0.05% STT enforcement.
- [x] **T55** — Automated authentication synchronization via `bin/setup_auth`.
