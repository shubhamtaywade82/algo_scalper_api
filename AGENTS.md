# Repository Guidelines

## Project Structure & Module Organization
- Core Rails app code lives in `app/`:
  - `app/controllers/api/` for API endpoints
  - `app/models/` and `app/models/concerns/` for domain models
  - `app/services/` for business logic, grouped by domain (`signal/`, `options/`, `orders/`, `live/`, `risk/`, `entries/`, `capital/`, `smc/`, `indicators/`, `dhan/`, `adapters/`, `positions/`, `trading/`)
  - `app/jobs/` for background jobs (Solid Queue — not Sidekiq)
  - `app/strategies/` for trading strategy implementations
  - `app/channels/` for ActionCable channels (`positions`, `dashboard`)
  - `app/lib/` for `AlgoConfig` and supporting utilities
  - `app/domain/` for value objects (`MarketTick`)
- Library and infrastructure code in `lib/`:
  - `lib/trading_system/` — daemon, bootstrap, supervisor (trading process lifecycle)
  - `lib/services/ai/` — Ollama client (`ollama-client`) and technical analysis agent
  - `lib/notifications/` — Telegram notifier
  - `lib/tasks/` — rake tasks (`trading:daemon`, `solid_queue:load_recurring`, `ai:technical_analysis`)
- Tests in `spec/` (models, services, integration, smoke, support, VCR cassettes).
- Configuration in `config/` (`algo.yml`, `recurring.yml`, `queue.yml`, initializers, environments).
- Documentation in `docs/` (architecture, trading, services, development, integrations, archive).

## Build, Test, and Development Commands
- `bundle install`: install gem dependencies.
- `rails db:setup`: create and seed database.
- `rails db:migrate`: run pending migrations.
- `rails solid_queue:load_recurring`: populate Solid Queue recurring task schedule.
- `./bin/dev`: run all 4 processes (web, trading daemon, Solid Queue worker, dashboard) via foreman.
- `bin/jobs`: start Solid Queue worker standalone.
- `ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon`: start trading daemon standalone.
- `bundle exec rspec`: run full test suite.
- `bundle exec rspec spec/services/live/risk_manager_service_spec.rb`: run a focused spec.
- `bundle exec rubocop`: run style/lint checks.
- `bin/brakeman --no-pager`: run security static analysis.

## Process Architecture
- `bin/dev` starts 4 processes via `Procfile.dev`:
  - `web` — Rails API server on port 3001
  - `trading` — Trading daemon (11 services in Ruby threads, managed by `TradingSystem::Supervisor`)
  - `jobs` — Solid Queue worker (recurring tasks: instrument sync, SMC scanner, AI analysis)
  - `dashboard` — Next.js frontend
- Web and trading are separate OS processes; they share PostgreSQL and Redis but NOT in-process objects.
- The trading daemon only starts services when `ENABLE_TRADING_SERVICES=true` and market is open. If market is closed at boot, only the WebSocket feed starts.

## Paper vs Live Trading
- Controlled by `config/algo.yml`: `paper_trading.enabled: true/false`
- Both modes use real DhanHQ WebSocket data for market ticks
- Paper mode: simulated fills via `Orders::GatewayPaper`
- Live mode: real DhanHQ execution via `Orders::GatewayLive`
- Additional safety gate for live: `dhanhq.enable_orders: true` in `algo.yml` (or `ENABLE_ORDER=true` env)
- Gateway selected at boot time; switching requires restart

## Coding Style & Naming Conventions
- Ruby files start with `# frozen_string_literal: true`.
- 2-space indentation; classes/modules namespaced by domain.
- Controllers thin — logic in services.
- Services in domain folders (e.g. `app/services/options/chain_analyzer.rb`).
- All percentage config values use DECIMAL format (0.12 = 12%, not 12.0).
- Follow `.rubocop.yml` and `CODING_CONVENTIONS.md`.

## Testing Guidelines
- Framework: RSpec (`rspec-rails`) with FactoryBot, VCR, WebMock, Shoulda Matchers.
- Test files as `*_spec.rb` mirroring code paths (`app/services/foo/bar.rb` → `spec/services/foo/bar_spec.rb`).
- Sequential execution; no parallel assumptions.
- Coverage via SimpleCov (`coverage/`).

## Commit & Pull Request Guidelines
- Short, imperative commit subjects (e.g. `Add Telegram Formatter Service`, `Fix PnL mismatch in exit flow`).
- Include issue/PR references when relevant.
- PRs include: purpose, scope, config changes, test evidence, risk notes.
- Trading behavior changes: include rollback notes and paper mode validation.

## Security & Configuration
- Never commit secrets; use `.env` (based on `.env.example`).
- Validate with paper mode before live use.

## Agent-Specific Instructions
- Use `rg --files` and `rg -n` for code discovery; avoid slower recursive search.
- Keep change scope tight: do not refactor unrelated code.
- Definition of done:
  - Update implementation and relevant specs.
  - Run focused tests first (`bundle exec rspec spec/services/orders/`).
  - Run lint on changed files (`bundle exec rubocop <paths>`).
- High-risk areas requiring extra validation: `app/services/orders/`, `app/services/risk/`, `app/services/live/`, `app/services/dhan/token_manager.rb`, `app/services/entries/entry_guard.rb`.
- For trading-flow changes, validate with `paper_trading.enabled: true` and `dhanhq.enable_orders: false`.
- Model/persistence changes: include migration and verify `db/schema.rb`.
- Never commit credentials, API tokens, or raw production data.
- Agent PR summary format:
  - Changed files
  - Behavioral impact
  - Tests and lint commands run
  - Remaining risks or follow-up tasks
