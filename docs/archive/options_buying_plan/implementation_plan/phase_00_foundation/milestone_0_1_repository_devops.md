Here is the **complete, day-by-day sprint plan** for **Phase 0, Milestone 0.1 — Repository & DevOps Foundation**.

---

# Milestone 0.1: Repository & DevOps Foundation
**Sprint Duration:** 10 working days (2 weeks)
**Developer Capacity:** 1 full-time senior engineer
**Deliverable:** A production-grade Rails 8.1.3 API repository that passes CI on every commit, runs in Docker, and enforces code quality automatically.

---

## Day 1 — Rails Application Bootstrap

### Task 1.1: Initialize Repository
- **Command:** `rails new algo_scalper_api --api --database=postgresql --skip-test --skip-action-mailbox --skip-action-text --skip-active-storage`
- **Deliverable:** Clean Rails 8.1.3 app in `algo_scalper_api/` directory
- **Acceptance Criteria:**
  - `bin/rails --version` returns `Rails 8.1.3`
  - `config/application.rb` has `config.api_only = true`
  - No unused frameworks (ActionMailbox, ActionText, ActiveStorage) in `Gemfile`
  - `.gitignore` excludes `.env`, `log/`, `tmp/`, `coverage/`

### Task 1.2: Commit Initial Structure
- **Deliverable:** Initial commit with conventional commit message: `chore: bootstrap rails 8.1.3 api app`
- **Acceptance Criteria:**
  - `git log --oneline` shows clean initial commit
  - `README.md` contains project name, Ruby version, and setup instructions placeholder
  - Branch protection rules documented (to be enforced after GitHub push)

### Task 1.3: Lock Ruby Version
- **Files:** `.ruby-version`, `Gemfile`
- **Deliverable:** Ruby version pinned to `3.3.6` (or latest stable)
- **Acceptance Criteria:**
  - `cat .ruby-version` returns exact version
  - `Gemfile` contains `ruby file: ".ruby-version"`
  - `bundle install` succeeds without version warnings

---

## Day 2 — Linting & Static Analysis (RuboCop)

### Task 2.1: Install RuboCop Gems
- **Files:** `Gemfile`, `Gemfile.lock`
- **Gems to add:**
  ```ruby
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-performance", require: false
  gem "rubocop-rspec", require: false
  gem "rubocop-rake", require: false
  ```
- **Deliverable:** All rubocop gems installed and loadable
- **Acceptance Criteria:** `bundle exec rubocop -V` lists all extensions

### Task 2.2: Configure `.rubocop.yml`
- **File:** `.rubocop.yml`
- **Required configurations:**
  - `AllCops.TargetRubyVersion: 3.3`
  - `AllCops.NewCops: enable`
  - `AllCops.Exclude: [db/schema.rb, bin/**, node_modules/**]`
  - Inherit from `rubocop-rails`, `rubocop-performance`, `rubocop-rspec`
  - `Style/Documentation: Enabled: false` (for now; enforce later)
  - `Metrics/MethodLength: Max: 20`
  - `Metrics/ClassLength: Max: 150`
  - `Metrics/BlockLength: Max: 30` (exclude specs)
  - `RSpec/MultipleExpectations: Max: 5`
- **Deliverable:** Working rubocop configuration
- **Acceptance Criteria:** `bundle exec rubocop` runs without config errors

### Task 2.3: Auto-correct Initial Offenses
- **Command:** `bundle exec rubocop -A`
- **Deliverable:** All auto-correctable offenses resolved
- **Acceptance Criteria:** `bundle exec rubocop` returns 0 offenses
- **Commit:** `style: apply rubocop auto-corrections to initial codebase`

---

## Day 3 — Security Scanning (Brakeman + Bundler-Audit)

### Task 3.1: Install & Configure Brakeman
- **Gem:** `gem "brakeman", require: false`
- **File:** `config/brakeman.yml`
- **Configuration:**
  - `run_checks: all`
  - `ignore_file: config/brakeman.ignore`
  - `quiet: true`
- **Deliverable:** Brakeman runs cleanly
- **Acceptance Criteria:** `bundle exec brakeman -q -w2` returns no warnings (or documented ignores)

### Task 3.2: Install & Configure bundler-audit
- **Gem:** `gem "bundler-audit", require: false`
- **Deliverable:** Vulnerability scanning for dependencies
- **Acceptance Criteria:** `bundle exec bundler-audit check --update` runs without critical vulnerabilities

### Task 3.3: Create Security Ignore Files
- **Files:** `config/brakeman.ignore` (empty template), `.bundler-audit.yml`
- **Deliverable:** Documented process for handling false positives
- **Acceptance Criteria:**
  - If Brakeman flags a false positive, it is documented in `config/brakeman.ignore` with justification
  - `docs/security.md` explains how to update and review security scans

---

## Day 4 — GitHub Actions CI Pipeline (Part 1)

### Task 4.1: Create CI Workflow Directory
- **File:** `.github/workflows/ci.yml`
- **Deliverable:** GitHub Actions workflow file
- **Structure:**
  - Trigger: `push` to `main`, `develop`; `pull_request` to `main`
  - Jobs: `lint`, `security`, `test`, `build`

### Task 4.2: Implement Lint Job
- **Job name:** `lint`
- **Steps:**
  1. Checkout code
  2. Setup Ruby (use `ruby/setup-ruby@v1` with `.ruby-version`)
  3. `bundle install`
  4. `bundle exec rubocop --parallel`
- **Deliverable:** Lint job passes on current codebase
- **Acceptance Criteria:** CI lint job completes in <2 minutes

### Task 4.3: Implement Security Job
- **Job name:** `security`
- **Steps:**
  1. Checkout code
  2. Setup Ruby
  3. `bundle install`
  4. `bundle exec brakeman -q -w2 --no-pager`
  5. `bundle exec bundler-audit check --update`
- **Deliverable:** Security job passes
- **Acceptance Criteria:** Both scans run; job fails on any high-severity finding

---

## Day 5 — GitHub Actions CI Pipeline (Part 2)

### Task 5.1: Implement Test Job
- **Job name:** `test`
- **Dependencies:** Needs PostgreSQL service container
- **Steps:**
  1. Checkout code
  2. Setup Ruby
  3. `bundle install`
  4. Setup PostgreSQL service (`postgres:16-alpine`)
  5. `bin/rails db:create db:migrate`
  6. `bundle exec rspec`
- **Deliverable:** Test job runs (will have 0 tests initially, but infrastructure works)
- **Acceptance Criteria:** Job completes successfully even with 0 examples

### Task 5.2: Implement Build Job
- **Job name:** `build`
- **Dependencies:** Needs `lint`, `security`, `test` to pass first
- **Steps:**
  1. Checkout code
  2. Build Docker image (multi-stage, see Day 6)
  3. Verify image starts and responds to `/health`
- **Deliverable:** Build job validates Docker image integrity
- **Acceptance Criteria:** Job fails if Docker build breaks or health check fails

### Task 5.3: Add CI Status Badge
- **File:** `README.md`
- **Deliverable:** CI badge showing current build status
- **Acceptance Criteria:** Badge renders correctly on GitHub

---

## Day 6 — Docker Multi-Stage Build (Part 1)

### Task 6.1: Create Production Dockerfile
- **File:** `Dockerfile`
- **Requirements:**
  - Stage 1: `ruby:3.3.6-slim` as builder
    - Install build deps (`build-essential`, `libpq-dev`, `git`)
    - `bundle config set --local deployment true`
    - `bundle config set --local without development test`
    - `bundle install`
  - Stage 2: `ruby:3.3.6-slim` as runtime
    - Install runtime deps (`libpq5`)
    - Copy gems from builder
    - Copy application code
    - Create non-root user `appuser`
    - Set `RAILS_ENV=production`
    - `CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]`
- **Deliverable:** Working multi-stage Dockerfile
- **Acceptance Criteria:** `docker build -t algo_scalper_api .` succeeds

### Task 6.2: Create `.dockerignore`
- **File:** `.dockerignore`
- **Contents:** `.git`, `log/`, `tmp/`, `coverage/`, `.env*`, `node_modules/`, `.github/`
- **Deliverable:** Optimized build context
- **Acceptance Criteria:** `docker build` context size <50MB

### Task 6.3: Configure Puma for Production
- **File:** `config/puma.rb`
- **Requirements:**
  - `workers Integer(ENV.fetch('WEB_CONCURRENCY', 2))`
  - `threads_count = Integer(ENV.fetch('RAILS_MAX_THREADS', 5))`
  - `preload_app!`
  - `rackup DefaultRackup` if specified
- **Deliverable:** Production-ready Puma config
- **Acceptance Criteria:** Container starts without Puma errors

---

## Day 7 — Docker Multi-Stage Build (Part 2) + docker-compose

### Task 7.1: Add HEALTHCHECK to Dockerfile
- **File:** `Dockerfile` (runtime stage)
- **Add:**
  ```dockerfile
  HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1
  ```
- **Requirement:** Install `curl` in runtime stage
- **Deliverable:** Docker health check configured
- **Acceptance Criteria:** `docker inspect --format='{{.State.Health.Status}}' <container>` shows `healthy`

### Task 7.2: Create `docker-compose.yml`
- **File:** `docker-compose.yml`
- **Services:**
  - `app`: Rails app, depends on `db` and `redis`
  - `db`: `postgres:16-alpine`, volume for persistence
  - `redis`: `redis:7-alpine`
- **Environment:** `.env.docker` for compose-specific variables
- **Deliverable:** One-command local stack
- **Acceptance Criteria:** `docker-compose up` starts all services; `docker-compose ps` shows all healthy

### Task 7.3: Create `docker-compose.test.yml`
- **File:** `docker-compose.test.yml`
- **Purpose:** Isolated test database for CI
- **Deliverable:** Test environment that doesn't pollute dev data
- **Acceptance Criteria:** `docker-compose -f docker-compose.test.yml run app bundle exec rspec` passes

---

## Day 8 — Pre-commit Hooks

### Task 8.1: Install pre-commit Framework
- **Tool:** `pre-commit` (Python-based, or use `overcommit` gem)
- **Recommendation:** Use `overcommit` gem for Ruby-native hooks
- **Gem:** `gem "overcommit", require: false`
- **Command:** `overcommit --install`
- **Deliverable:** Git hooks directory configured

### Task 8.2: Configure `.overcommit.yml`
- **File:** `.overcommit.yml`
- **Pre-commit hooks:**
  - `RuboCop`: Run on staged Ruby files
  - `BundleAudit`: Check for vulnerabilities
  - `Brakeman`: Run on all files
  - `RailsSchemaUpToDate`: Ensure `db/schema.rb` matches migrations
  - `TrailingWhitespace`: Reject trailing whitespace
  - `YamlSyntax`: Validate YAML files
- **Deliverable:** Pre-commit configuration
- **Acceptance Criteria:** `git commit` fails if staged files have RuboCop offenses

### Task 8.3: Add Commit Message Validation
- **Hook:** `CommitMsg` hook in Overcommit
- **Rule:** Enforce conventional commits (`feat:`, `fix:`, `chore:`, `style:`, `refactor:`, `test:`, `docs:`)
- **Regex:** `^(feat|fix|chore|style|refactor|test|docs)(\(.+\))?: .+`
- **Deliverable:** Standardized commit messages
- **Acceptance Criteria:** `git commit -m "bad message"` is rejected; `git commit -m "feat: add health endpoint"` is accepted

---

## Day 9 — RSpec Test Suite (Part 1)

### Task 9.1: Install RSpec & Supporting Gems
- **Gems:**
  ```ruby
  group :development, :test do
    gem "rspec-rails"
    gem "factory_bot_rails"
    gem "faker"
    gem "shoulda-matchers"
    gem "database_cleaner-active_record"
  end
  ```
- **Command:** `bundle install && rails generate rspec:install`
- **Deliverable:** RSpec installed with default structure
- **Acceptance Criteria:** `spec/` directory exists with `spec_helper.rb` and `rails_helper.rb`

### Task 9.2: Configure `rails_helper.rb`
- **File:** `spec/rails_helper.rb`
- **Requirements:**
  - `require "spec_helper"`
  - `ENV["RAILS_ENV"] ||= "test"`
  - `require_relative "../config/environment"`
  - `abort` if Rails.env.production?
  - `require "rspec/rails"`
  - `require "factory_bot_rails"`
  - `require "shoulda-matchers"`
  - DatabaseCleaner config:
    - `config.before(:suite) { DatabaseCleaner.strategy = :transaction }`
    - `config.around(:each) { |example| DatabaseCleaner.cleaning { example.run } }`
  - `Shoulda::Matchers.configure` with `integrate do |with| with.test_framework :rspec; with.library :rails end`
  - `FactoryBot::Syntax::Methods` included in RSpec config
- **Deliverable:** Properly configured test harness
- **Acceptance Criteria:** `bundle exec rspec` runs without configuration errors

### Task 9.3: Create First Factory & Model Spec
- **Factory:** `spec/factories/instruments.rb` (placeholder for future Instrument mctoryBot.define do
    factory :instrument do
      trading_symbol { "NIFTY50" }
      exchange_segment { "NSE_FNO" }
      instrument_type { "INDEX" }
    end
  end
  ```
- **Spec:** `spec/models/instrument_spec.rb` (will fail now, serves as placeholder)
- **Deliverable:** Factory structure established
- **Acceptance Criteria:** `bundle exec rspec` shows 0 examples (or 1 pending)

---

## Day 10 — RSpec Test Suite (Part 2) + Coverage + Final Integration

### Task 10.1: Configure SimpleCov
- **Gem:** `gem "simplecov", require: false`
- **File:** `spec/spec_helper.rb`
- **Configuration:**
  ```ruby
  require "simplecov"
  SimpleCov.start "rails" do
    add_filter "/spec/"
    add_filter "/config/"
    add_filter "/db/"
    minimum_coverage 80
    minimum_coverage_by_file 70
    refuse_coverage_drop
  end
  ```
- **Deliverable:** Coverage tracking with 80% threshold
- **Acceptance Criteria:** `bundle exec rspec` generates `coverage/` directory; CI fails if coverage <80%

### Task 10.2: Add Bullet Gem Configuration
- **Gem:** `gem "bullet", group: :development`
- **File:** `config/environments/development.rb`
- **Configuration:**
  ```ruby
  config.after_initialize do
    Bullet.enable = true
    Bullet.alert = false
    Bullet.bullet_logger = true
    Bullet.console = true
    Bullet.rails_logger = true
    Bullet.add_footer = true
  end
  ```
- **Deliverable:** N+1 query detection in development
- **Acceptance Criteria:** Any N+1 query in development logs a warning

### Task 10.3: Configure Rack-Attack
- **Gem:** `gem "rack-attack"`
- **File:** `config/initializers/rack_attack.rb`
- **Requirements:**
  - Throttle `/api/` requests by IP: 300 requests per 5 minutes
  - Throttle login attempts (if applicable): 5 per 20 seconds
  - Block requests with suspicious user agents
  - Safe-list localhost in development
- **Deliverable:** Rate limiting and DDoS protection
- **Acceptance Criteria:** `curl -H "X-Forwarded-For: 1.2.3.4" http://localhost:3000/api/health` works; rapid requests get 429

### Task 10.4: Configure Lograge
- **Gem:** `gem "lograge"`
- **File:** `config/initializers/lograge.rb`
- **Configuration:**
  ```ruby
  Rails.application.configure do
    config.lograge.enabled = true
    config.lograge.formatter = Lograge::Formatters::Json.new
    config.lograge.custom_options = lambda do |event|
      { time: Time.now.iso8601, host: event.payload[:host], user_id: event.payload[:user_id] }
    end
  end
  ```
- **Deliverable:** Structured JSON logs in production
- **Acceptance Criteria:** Production logs are single-line JSON

### Task 10.5: Configure Error Monitoring (Sentry)
- **Gem:** `gem "sentry-ruby"`, `gem "sentry-rails"`
- **File:** `config/initializers/sentry.rb`
- **Configuration:**
  ```ruby
  Sentry.init do |config|
    config.dsn = ENV.fetch("SENTRY_DSN", nil)
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]
    config.traces_sample_rate = 0.2
    config.environment = Rails.env
  end
  ```
- **Deliverable:** Error tracking ready for DSN injection
- **Acceptance Criteria:** App boots without Sentry errors when DSN is absent

### Task 10.6: Create Makefile
- **File:** `Makefile`
- **Targets:**
  ```makefile
  .PHONY: setup test lint security console build up down logs

  setup:
  	bundle install
  	bin/rails db:setup

  test:
  	bundle exec rspec

  lint:
  	bundle exec rubocop --parallel

  security:
  	bundle exec brakeman -q -w2
  	bundle exec bundler-audit check --update

  console:
  	bin/rails console

  build:
  	docker build -t algo_scalper_api .

  up:
  	docker-compose up -d

  down:
  	docker-compose down

  logs:
  	docker-compose logs -f app
  ```
- **Deliverable:** One-command development workflow
- **Acceptance Criteria:** `make lint` runs RuboCop; `make test` runs RSpec; `make build` builds Docker image

### Task 10.7: Final Integration & Sprint Review
- **Actions:**
  1. Push all commits to `main` branch
  2. Verify GitHub Actions CI passes on all jobs (lint, security, test, build)
  3. Verify Docker image builds and health check responds
  4. Verify `make setup`, `make test`, `make lint` all pass locally
  5. Verify `docker-compose up` brings up full stack
  6. Verify pre-commit hooks block bad commits
  7. Document any deviations in `docs/milestone-0.1.md`
- **Deliverable:** Sprint completion report
- **Acceptance Criteria:** All 15 original tasks verified working end-to-end

---

## Sprint Checklist & Definition of Done

| # | Deliverable | Verification Method |
|---|------------|---------------------|
| 1 | Rails 8.1.3 API app | `bin/rails --version` |
| 2 | RuboCop with 5 extensions | `bundle exec rubocop` returns 0 |
| 3 | Brakeman security scan | `bundle exec brakeman -q -w2` clean |
| 4 | bundler-audit | `bundle exec bundler-audit check --update` clean |
| 5 | GitHub Actions CI | 4 jobs pass on `main` |
| 6 | Docker multi-stage build | `docker build -t algo_scalper_api .` succeeds |
| 7 | HEALTHCHECK | `docker inspect` shows `healthy` |
| 8 | docker-compose stack | `docker-compose up` starts app + db + redis |
| 9 | Pre-commit hooks | `git commit` blocked on bad style |
| 10 | RSpec + FactoryBot + Shoulda | `bundle exec rspec` runs |
| 11 | SimpleCov 80% threshold | CI fails if coverage <80% |
| 12 | Bullet N+1 detection | Dev logs show warnings on N+1 |
| 13 | Rack::Attack | 429 returned on excessive requests |
| 14 | Lograge JSON logs | Production logs are single-line JSON |
| 15 | Sentry error tracking | `Sentry` initialized, no boot errors |
| 16 | Makefile | `make test`, `make lint`, `make build` work |

---

## Files Created / Modified in This Sprint

```
├── .github/
│   └── workflows/
│       └── ci.yml
├── .overcommit.yml
├── .rubocop.yml
├── .ruby-version
├── .dockerignore
├── Dockerfile
├── docker-compose.yml
├── docker-compose.test.yml
├── Gemfile
├── Gemfile.lock
├── Makefile
├── README.md
├── config/
│   ├── brakeman.yml
│   ├── brakeman.ignore
│   ├── initializers/
│   │   ├── lograge.rb
│   │   ├── rack_attack.rb
│   │   └── sentry.rb
│   ├── environments/
│   │   └── development.rb  (modified)
│   └── puma.rb
├── docs/
│   ├── milestone-0.1.md
│   └── security.md
└── spec/
    ├── factories/
    │   └── instruments.rb
    ├── models/
    │   └── instrument_spec.rb
    ├── rails_helper.rb
    └── spec_helper.rb
```

---

## Next Steps

After Milestone 0.1 is complete, the next sprint is **Milestone 0.2: Configuration & Environment Management** (typed settings, credentials, Redis, Solid Queue/Cache/Cable setup).

Ready to proceed to **Milestone 0.2**, or do you want me to adjust anything in this sprint plan first?
