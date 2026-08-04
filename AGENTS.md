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
- `bin/setup --skip-server`: install gems and initialize local dependencies.
- `bin/rails db:prepare`: create/migrate DB for current environment.
- `bin/dev`: run the API server via `Procfile.dev`.
- `ENABLE_TRADING_SERVICES=true bundle exec rake trading:daemon`: start trading services.
- `bundle exec rspec`: run full test suite.
- `bundle exec rspec spec/services/live/risk_manager_service_spec.rb`: run a focused spec file.
- `bin/rubocop`: run style/lint checks.
- `bin/brakeman --no-pager`: run security static analysis.

## Coding Style & Naming Conventions
- Ruby files should start with `# frozen_string_literal: true`.
- Use 2-space indentation; keep classes/modules namespaced by domain.
- Keep controllers thin and move logic into services.
- Place services in domain folders (for example `app/services/options/chain_analyzer.rb`).
- Follow `.rubocop.yml` and the repository rules in `CODING_CONVENTIONS.md`.

## Testing Guidelines
- Framework: RSpec (`rspec-rails`) with FactoryBot, VCR, WebMock, and Shoulda Matchers.
- Name test files as `*_spec.rb` and mirror code paths (`app/services/foo/bar.rb` -> `spec/services/foo/bar_spec.rb`).
- Default run is sequential; avoid assumptions about parallel execution.
- Coverage is tracked via SimpleCov (`coverage/`), but minimum coverage is currently set to `0`.

## Commit & Pull Request Guidelines
- Prefer short, imperative commit subjects (for example: `Add Telegram Formatter Service...`, `Refactor DhanHQ credential handling...`).
- Include issue/PR references when relevant (for example `(#87)`).
- PRs should include: purpose, scope, config changes, test evidence (`bundle exec rspec` output), and risk notes.
- For trading behavior changes, include rollback notes and whether validation was done in `PAPER_MODE=true`.

## Security & Configuration Tips
- Never commit secrets; use `.env` (based on `.env.example`).
- Validate new integrations with `DHANHQ_ENABLED=false` or `PAPER_MODE=true` before live use.

## HTTP Rate Limiting (Rack::Attack)

- **Configuration:** `config/initializers/rack_attack.rb`. Uses `Rails.cache`
  for throttle counters.
- **Test:** Rack::Attack is **disabled** after boot (`Rack::Attack.enabled =
  false`) so specs and CI are not throttled.
- **Dev / production:** Enabled by default:
  - `/api/*` — default **240 requests / 5 minutes** per IP.
  - `POST /api/analysis/:id/ai_snapshot` — **12 / minute** per IP (separate
    bucket).
- **Tuning:** `RACK_ATTACK_API_LIMIT`, `RACK_ATTACK_API_PERIOD_SECONDS`,
  `RACK_ATTACK_AI_LIMIT`, `RACK_ATTACK_AI_PERIOD_SECONDS` in `.env` (see
  `.env.example`). Raise limits for load tests. Throttled clients get **429**
  and JSON `{"error":"rate_limited"}`.
- **Bypassed:** `/up`, `/.well-known/*`.

## Tick SMC + TA AI (optional)

- **Runs only in the trading daemon** (`ENABLE_TRADING_SERVICES=true`), not in
  Puma. Registers an `on_tick` callback on `Live::MarketFeedHub` (see
  `Smc::TickAi::AnalysisService` in `lib/trading_system/bootstrap.rb`).
- **Requires:** Redis (`REDIS_URL`) for per-tick throttle + rising-edge snapshot;
  Ollama when `ai.enabled`; Telegram env vars when `tick_ai_notify_telegram` is
  true (`config/algo.yml` → `signals.tick_ai_*`).
- **Behavior:** throttle (default 15s per index) → Solid Queue job → MTF
  confluence digest → **rising-edge** LTF flags vs Redis → optional index TA →
  `Smc::AiAnalyzer` → optional Telegram. Master switch:
  `signals.tick_ai_analysis_enabled`.

## Agent-Specific Instructions
- Use `rg --files` and `rg -n` for code discovery; avoid slower recursive search tools.
- Keep change scope tight: do not refactor or rename unrelated code while fixing a targeted issue.
- Definition of done for code changes:
  - Update implementation and relevant specs.
  - Run focused tests first (for example `bundle exec rspec spec/services/orders/`).
  - Run lint on changed files (`bin/rubocop <paths>`).
- High-risk areas require extra validation: `app/services/orders/`, `app/services/risk/`, `app/services/live/`, `app/services/dhan/token_manager.rb`.
- For trading-flow changes, validate locally with safe defaults: `PAPER_MODE=true` and `DHANHQ_ENABLED=false` unless explicitly testing live integrations.
- When models or persistence logic change, include a migration and verify `db/schema.rb` updates with corresponding model/service specs.
- Never commit credentials, API tokens, or raw production data; keep `.env` and secrets out of commits.
- Agent PR summary format should always include:
  - Changed files
  - Behavioral impact
  - Tests and lint commands run
  - Remaining risks or follow-up tasks
