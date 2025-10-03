# Repository Guidelines

## Project Structure & Module Organization
- `app/` holds the Rails API surface: controllers orchestrate requests, models encapsulate domain logic, and jobs in `app/jobs/` run async work via Solid Queue.
- `config/` stores environment wiring—update `config/routes.rb` when exposing new endpoints and add initializer tweaks under `config/initializers/`.
- `db/` tracks persistence (`*_schema.rb`, seeds); create migrations under `db/migrate/` even if the directory must be added with your change.
- `bin/` bundles project scripts (`bin/setup`, `bin/dev`, linters); favor these wrappers over direct `bundle exec` calls.
- `lib/` is reserved for shared abstractions and rake tasks; keep reusable utilities here instead of bloating controllers.

## Build, Test, and Development Commands
- `bin/setup` installs gems, prepares the database, and can boot the dev server (skip with `--skip-server`).
- `bin/dev` runs `bin/rails server` with defaults suited for API development.
- `bin/rails db:prepare` (or `db:migrate`) keeps schemas up to date locally and in CI.
- `bin/rubocop` enforces house style; `bin/brakeman --no-pager` performs the security scan mirrored in CI.

## Coding Style & Naming Conventions
- Target Ruby 3.3.4 and the omakase RuboCop rules in `.rubocop.yml`; run RuboCop before pushing.
- Use two-space indentation, `snake_case` filenames, and descriptive `CamelCase` classes/modules (`OrderBookUpdater`, `SyncPricesJob`).
- Prefer PORO services under `app/services/` (create the directory if needed) when logic grows beyond controllers/models.

## Testing Guidelines
- Rails ships with Minitest; place tests under `test/` mirroring `app/` paths (e.g., `test/controllers/orders_controller_test.rb`).
- Run the suite with `bin/rails test`; target-focused runs like `bin/rails test test/models/ticker_test.rb` speed feedback.
- Exercise jobs with `ActiveJob::TestHelper`, cover edge cases around Solid Cache/Queue interactions, and keep assertions against API responses explicit.

## Commit & Pull Request Guidelines
- History currently shows concise CamelCase (`InitialCommit`); move toward imperative summaries such as `Add throttle guard to quotes API` while keeping the first line ≤ 72 chars.
- Each PR should describe intent, link tracking issues, list manual verification (`bin/rubocop`, `bin/brakeman`, `bin/rails test`), and mention schema or config impacts.
- Prefer small, reviewable changes; include request/response samples or screenshots when altering public endpoints.

## Security & Configuration Tips
- Keep secrets in `config/credentials.yml.enc`; never commit `config/master.key`. Supply `RAILS_MASTER_KEY` when using the provided Dockerfile or Kamal deploys.
- `bin/docker-entrypoint` auto-runs `db:prepare` for server boot; ensure migrations are idempotent and reversible so containers stay healthy.
