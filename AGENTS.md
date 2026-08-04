# Repository Guidelines

## Project Structure & Module Organization
- Core Rails app code lives in `app/`:
  - `app/controllers/api/` for API endpoints
  - `app/models/` and `app/models/concerns/` for domain models
  - `app/services/` for business logic, grouped by domain (`signal/`, `options/`, `orders/`, `live/`, `risk/`, etc.)
  - `app/jobs/` for background jobs
- Shared utilities and rake tasks are in `lib/` and `lib/tasks/`.
- Tests live in `spec/` (models, services, integration, smoke, support, and VCR cassettes).
- Runtime/config files are in `config/` (`algo.yml`, initializers, environment configs).
- Long-form architecture and operations docs are in `docs/`.

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
