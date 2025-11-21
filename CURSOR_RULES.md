# Cursor Settings → Rules

Copy each rule block below and paste into Cursor Settings → Rules → New Rule.

---

## 1. Rails Backend

```
Rule Name: Rails Backend Standards

All Ruby files MUST start with `# frozen_string_literal: true` as the first line.

Controllers MUST be placed under `app/controllers/api/` and namespaced under `Api::` module. All controllers MUST inherit from `ApplicationController < ActionController::API`. Controllers MUST be thin - business logic MUST be in services, not controllers. Controllers MUST use `render json:` for all responses (no serializers).

Services MUST be organized by domain in `app/services/domain/` subdirectories: signal/, options/, capital/, entries/, orders/, live/, risk/, indicators/. Services with lifecycle (start/stop) MUST inherit from `TradingSystem::BaseService`. Stateless utility services MUST inherit from `ApplicationService` and implement `.call(*, **, &)` class method. Services managing global state MUST use `include Singleton` and be accessed via `.instance` class method.

Models MUST be placed in `app/models/` with concerns in `app/models/concerns/`. All models MUST inherit from `ApplicationRecord < ActiveRecord::Base`. Shared model logic MUST use concerns. Status/type fields MUST use `enum`, never string constants. Scopes MUST be defined as class methods. All associations MUST specify `dependent:` options.

Shared utilities MUST be placed in `lib/`, never in `app/`. Provider abstractions MUST be in `lib/providers/`. Rake tasks MUST be in `lib/tasks/`.

Code style: Always use 2 spaces for indentation, never tabs. Never exceed 120 characters per line (exceptions: comments, describe/context/it/expect patterns). Never exceed 30 lines per method (exceptions: spec files). All files MUST pass RuboCop checks before commit.

Target Ruby version: 3.3.4 (enforced via `.ruby-version`).
```

---

## 2. Node Backend

```
Rule Name: Node Backend Standards

Not applicable - this is a Rails-only API application with no Node.js backend.
```

---

## 3. React + TypeScript

```
Rule Name: React + TypeScript Standards

Not applicable - this is a Rails API-only application with no frontend code.
```

---

## 4. Database Standards

```
Rule Name: Database Standards

Migration files MUST be named with timestamp prefix: `YYYYMMDDHHMMSS_descriptive_name.rb`. Migrations MUST use `ActiveRecord::Migration[8.0]` version. Migrations MUST use `def change` method, never `up`/`down` unless necessary. Migrations MUST be reversible (idempotent). Migrations MUST add indexes with descriptive names. Composite unique indexes MUST use descriptive names ending with `_unique`. Partial indexes MUST use `where:` clause when filtering NULL values.

All tables MUST have `created_at` and `updated_at` timestamps. Decimal columns MUST specify `precision` and `scale`. Foreign keys MUST be explicitly added with `add_foreign_key`. NOT NULL constraints MUST be specified for required fields. Default values MUST be specified for status fields and numeric columns. JSONB columns MUST be used for flexible metadata (`meta`, `metadata`). Polymorphic associations MUST use `_type` and `_id` suffix pattern.

Unique constraints MUST be enforced via composite unique indexes. Partial indexes MUST be used with `where:` clauses for filtered queries. GIN indexes MUST be used for JSONB columns that are queried. Composite indexes MUST be created for common multi-column queries. Index names MUST follow pattern: `index_table_name_on_columns`.

Table names MUST be plural. Column names MUST use `snake_case`. Foreign key columns MUST end with `_id`. Polymorphic type columns MUST end with `_type`.
```

---

## 5. Testing Standards

```
Rule Name: Testing Standards (RSpec)

Test files MUST be named `*_spec.rb` and placed in `spec/` directory. Test structure MUST mirror `app/` directory structure. Tests MUST use RSpec framework (not Minitest). Test files MUST require `rails_helper.rb`. Tests MUST use FactoryBot for test data creation.

`describe` blocks MUST use `.` or `::` for class methods, `#` for instance methods. `context` blocks MUST start with: `when`, `with`, `without`, `if`, `unless`, `for`, `that`. Spec descriptions MUST NOT exceed 40 characters (split using contexts). Nested groups (describe/context) MUST NOT exceed 5 levels. Example length MUST NOT exceed 25 lines (exceptions: features, integration, system specs). Multiple memoized helpers (`let`) MUST NOT exceed 10 per spec. Multiple expectations MUST NOT exceed 4 per test (exceptions: integration, system, feature specs). Always use `expect` syntax, never `should` syntax.

Factories MUST be defined in `spec/factories/` directory. Factory attributes MUST be defined statically. Factories MUST use traits for variations (e.g., `:nifty_index`, `:banknifty_future`). Factory names MUST match model names in singular form.

Tests MUST use DatabaseCleaner with transaction strategy. Tests MUST clean database with truncation before suite. Tests MUST use VCR for external API call recording/playback. Tests MUST filter sensitive data from VCR cassettes. Tests MUST mock external API calls (DhanHQ) for reliability. Tests MUST disable DhanHQ in test environment via `ENV['DHANHQ_ENABLED'] = 'false'`. Tests MUST use WebMock for HTTP stubbing. Tests MUST use transactional fixtures disabled (`use_transactional_fixtures = false`).

Integration tests MUST be placed in `spec/integration/` directory. Integration tests MAY have multiple expectations and exceed 25 lines (excluded from respective rules).
```

---

## 6. API Standards

```
Rule Name: API Standards

All API endpoints MUST be under `/api` namespace. Routes MUST be defined in `config/routes.rb` under `namespace :api`. Health check endpoint MUST be at `/api/health`. API responses MUST use JSON format only.

Controllers MUST use `render json:` for all responses. Responses MUST be plain JSON objects (no serializers). Responses MUST use inline hash construction in controllers. Error responses MUST include error message and status. Success responses MUST include relevant data and status indicators.

CORS MUST be configured via `rack-cors` middleware. CORS MUST allow all origins in development (restrict in production).
```

---

## 7. Error & Logging Standards

```
Rule Name: Error & Logging Standards

Exception Handling:
Services MUST rescue `StandardError` explicitly, never bare `rescue`. Error handling MUST log errors with class context: `[ClassName] Error message`. Error logging MUST include exception class and message: `#{e.class} - #{e.message}`. Services MUST return `nil` or error hash on failure, never raise exceptions to callers. Custom errors MUST be defined as classes inheriting from `StandardError`. Error messages MUST be descriptive and include context.

Retry Logic:
Retry logic MUST be implemented in services when needed. Retry attempts MUST have maximum count defined as a constant (e.g., `RETRY_COUNT = 3`). Retry logic MUST use exponential backoff or fixed delay. Retry logic MUST log retry attempts.

Graceful Degradation:
Services MUST handle missing data gracefully (return `nil` or empty collections). Services MUST validate inputs before processing. Services MUST handle external API failures without crashing.

Logging:
All log messages MUST include class context in brackets: `[ClassName] Message`. Log messages MUST use structured format: `[ClassName] Action description`. Error logs MUST include exception details: `[ClassName] #{e.class} - #{e.message}`. Debug logs MUST be commented out in production code (use `# Rails.logger.debug`).

Log Levels:
`Rails.logger.info` MUST be used for normal operations. `Rails.logger.warn` MUST be used for warnings. `Rails.logger.error` MUST be used for errors. `Rails.logger.debug` MUST be used for debug information (commented in production).

Log Context:
Log messages MUST include relevant context (index key, order ID, etc.). Log messages MUST be concise but descriptive. Sensitive data MUST NOT be logged (filtered via `filter_parameter_logging.rb`).

Production Logging:
Production logs MUST use tagged logging with `:request_id`. Production logs MUST output to STDOUT. Production log level MUST be configurable via `RAILS_LOG_LEVEL` environment variable. Health check endpoints MUST be silenced in logs (`silence_healthcheck_path`).
```

---

## 8. Architecture Rules

```
Rule Name: Architecture Rules

Domain Organization:
Services MUST be organized by domain in subdirectories. Domain boundaries MUST be respected (no cross-domain dependencies). Shared logic MUST be extracted to concerns or base classes.

Service Patterns:
Business logic MUST be in services, not controllers or models. Controllers MUST only handle request/response. Models MUST only handle data persistence and validations. Services MUST be PORO (Plain Old Ruby Objects).

Configuration:
Trading parameters MUST be configurable via `config/algo.yml`. Environment-specific config MUST use environment variables. Configuration MUST be loaded via `AlgoConfig.fetch`. Secrets MUST be stored in encrypted credentials or environment variables.

Real-time Services:
Real-time services (WebSocket, market feeds) MUST use Singleton pattern. Singleton services MUST manage their own threads. Thread names MUST be descriptive (e.g., `'signal-scheduler'`, `'pnl-updater-service'`). Thread safety MUST be ensured via mutexes when needed.

External Integrations:
External API clients MUST be abstracted via provider classes in `lib/providers/`. External API calls MUST be wrapped in error handling. External API credentials MUST be loaded from environment variables.

Performance:
String matching MUST use `start_with?`/`end_with?` instead of regex when possible. String prefix/suffix removal MUST use `delete_prefix`/`delete_suffix`. Cache keys MUST use descriptive prefixes: `option_chain:`, `tick:`. Cache MUST be checked for staleness before use. Singleton services MUST be used for in-memory caches. Queries MUST use appropriate indexes. N+1 queries MUST be avoided (use `includes`/`joins`). Bulk operations MUST use `activerecord-import` for large datasets.
```

---

## 9. Naming Conventions

```
Rule Name: Naming Conventions

Files:
File names MUST use `snake_case.rb`. Service files MUST be named `service_name.rb` in `app/services/domain/`. Model files MUST be named `model_name.rb` in `app/models/`. Controller files MUST be named `resource_controller.rb` in `app/controllers/api/`. Test files MUST be named `*_spec.rb` in `spec/`.

Classes and Modules:
Class names MUST use `CamelCase`. Module names MUST use `CamelCase`. Namespaced classes MUST use `::` separator: `Domain::ServiceName`. Service classes MUST have descriptive names: `Signal::Engine`, `Capital::Allocator`. Job classes MUST have action-oriented names: `SyncPricesJob`.

Methods:
Method names MUST use `snake_case`. Predicate methods MUST end with `?`: `running?`, `active?`. Destructive methods MUST end with `!`: `save!`, `update!`. Class methods MUST be called via `.` or `::`.

Constants:
Constants MUST use `SCREAMING_SNAKE_CASE`. Constants MUST be defined at class/module level. Magic numbers MUST be extracted to named constants.

Variables:
Variable names MUST use `snake_case`. Instance variables MUST use `@variable_name`. Class variables MUST be avoided (use class instance variables instead).

Database:
Table names MUST be plural: `instruments`, `position_trackers`. Column names MUST use `snake_case`. Foreign key columns MUST end with `_id`: `instrument_id`. Polymorphic type columns MUST end with `_type`: `watchable_type`. Index names MUST follow pattern: `index_table_name_on_columns`.
```

---

## 10. Git Workflow

```
Rule Name: Git Workflow

Commit Messages:
Commit messages MUST use imperative mood: `Add feature`, `Fix bug`, `Update config`. Commit message first line MUST NOT exceed 72 characters. Commit messages MUST NOT use CamelCase (use imperative summaries). Commit messages MUST be descriptive and explain what and why.

Pull Requests:
PRs MUST include clear description of changes and purpose. PRs MUST link to tracking issues if applicable. PRs MUST include verification steps: `bin/rubocop` (code style), `bin/brakeman` (security scan), `bin/rails test` (test suite). PRs MUST mention schema or config impacts. PRs MUST include request/response samples for API changes. PRs MUST be small and reviewable (prefer small changes). PRs MUST focus on single feature or bug fix. PRs MUST include tests for new functionality. PRs MUST update relevant documentation.

Branch Naming:
Branch names MUST be descriptive and use kebab-case. Feature branches SHOULD start with `feature/`. Bug fix branches SHOULD start with `fix/`.
```

---

## 11. Documentation

```
Rule Name: Documentation Standards

Code Documentation:
Complex logic MUST be documented with comments. Public API methods MUST be documented with YARD-style comments when needed. TODO comments MUST use format: `# TODO: Description`. NOTE comments MUST use format: `# NOTE: Description`. HACK comments MUST be avoided (refactor instead).

Markdown Documentation:
Documentation files MUST use `.md` extension. Level-one and level-two headings MUST use Title Case. Sequential procedures MUST be numbered. Environment variables or configuration MUST be documented in tables. Critical warnings MUST use blockquotes starting with `> **Warning:**`. Documentation lines MUST be under 90 characters per line for readable diffs.

README:
README MUST include project overview, setup instructions, and usage examples. README MUST document all environment variables in a table. README MUST include troubleshooting section. README MUST link to additional documentation.

API Documentation:
API endpoints MUST be documented with HTTP method, path, and example response. API documentation MUST include request/response examples in JSON format.
```

---

## 12. Nemesis Architect Mode

```
Rule Name: Nemesis Architect Mode

When generating or refactoring code, always think like a production-grade systems architect:

1. Production Readiness: Every change MUST consider production implications. Error handling MUST be comprehensive. Logging MUST be structured and traceable. Performance MUST be considered (N+1 queries, caching, thread safety).

2. Trading System Safety: This is a financial trading system - errors can cost money. Always validate inputs. Always handle external API failures gracefully. Always log trading decisions. Never raise exceptions that could crash the trading loop. Always use idempotent operations for order placement.

3. Code Quality: Code MUST pass RuboCop before commit. Code MUST have appropriate test coverage. Code MUST follow domain-driven design principles. Business logic MUST be in services, never in controllers or models.

4. Observability: All critical operations MUST be logged with class context. Health endpoints MUST reflect actual system state. Thread names MUST be descriptive for debugging. Singleton services MUST provide health/status methods.

5. Maintainability: Code MUST be self-documenting with clear naming. Complex logic MUST have comments explaining the "why". Domain boundaries MUST be respected. Shared logic MUST be extracted to concerns or base classes.

6. Security: Never commit secrets. Always use environment variables for credentials. Always filter sensitive data from logs. Always validate external inputs.

7. Performance: Always consider caching for expensive operations. Always use appropriate database indexes. Always avoid N+1 queries. Always use bulk operations for large datasets.

8. Testing: Tests MUST use VCR for external API calls. Tests MUST disable external services in test environment. Tests MUST use FactoryBot with traits. Tests MUST follow Better Specs guidelines.

When in doubt, prioritize safety, observability, and maintainability over cleverness or brevity.
```

---

*Copy each rule block above and paste into Cursor Settings → Rules → New Rule.*

