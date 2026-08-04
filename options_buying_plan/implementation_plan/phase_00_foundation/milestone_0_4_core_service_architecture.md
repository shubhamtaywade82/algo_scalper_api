# Milestone 0.4: Core Service Architecture
**Sprint Duration:** 10 working days (2 weeks)
**Developer Capacity:** 1 full-time senior engineer
**Deliverable:** Clean, testable service layer with dependency injection, deterministic engines, event bus, and repository pattern.

---



## Day 29 — Service Layer Foundation

### Task 29.1: Initialize Service Layer Workshop
- **Context:** Establish the service architecture base before any engine or repository is created.
- **Deliverable:** Directory structure for services, repositories, engines, gateways, validators, calculations, errors, and event bus.
- **Acceptance Criteria:**
  - All directories exist under `app/services/`, `app/engines/`, `app/gateway/`, `app/lib/`
  - File layout follows Rails conventions (models = persistence, services = behavior)
  - No hidden or circular dependencies in initial structure

### Task 29.2: Create `app/services/result.rb`
- **Goal:** Outcome pattern to replace exception-driven flow.
- **Implementation:**
  ```ruby
  class Result
    def initialize(success, value, error)
      @success = success
      @value = value
      @error = error
    end

    def success? = @success
    def failure? = !@success
    def value = @value
    def error = @error

    def self.success(value) = new(true, value, nil)
    def self.failure(error) = new(false, nil, error)

    def and_then
      return self unless success?
      yield(value) || self
    end

    def or_else
      return self if success?
      yield(error) || self
    end
  end
  ```
- **Deliverable:** Result object with monadic chaining.
- **Acceptance Criteria:**
  - `Result.success(1).and_then { |v| Result.success(v + 1) }` returns success 2
  - `Result.failure(StandardError.new("x")).or_else { raise }` raises only in failure case
  - Fully covered in `spec/services/result_spec.rb`

### Task 29.3: Create `app/services/errors/` hierarchy
- **Base:** `ServiceError < StandardError`
- **Specializations:** `ValidationError`, `BrokerError`, `DataError`, `RiskError`
- **Each error carries:** code (symbol), message, context hash, severity (symbol :low/:medium/:high/:critical)
- **Deliverable:** Typed error classes ready for structured handling.
- **Commit:** `feat: add Result object and ServiceError hierarchy`

---



## Day 30 — BaseService Implementation

### Task 30.1: Implement `app/services/base_service.rb`
- **Interface:** `call(*args, **kwargs) -> Result`
- **Responsibilities:**
  - Start/success/failure logging with elapsed time
  - Automatic Result wrapping when subclasses return raw values
  - Optional transaction management (`use_transaction = true`)
- **Implementation sketch:**
  ```ruby
  class BaseService
    class << self
      def call(*args, **kwargs)
        new.call(*args, **kwargs)
      end
    end

    def call
      raise NotImplementedError, "#{self.class}#call must be implemented"
    end

    private

    def log_start(context = {})
      logger.info "[#{self.class}] START context=#{context.to_json}"
    end

    def log_success(result, elapsed)
      logger.info "[#{self.class}] SUCCESS elapsed=#{elapsed}ms"
      result
    end

    def log_failure(error, elapsed)
      logger.warn "[#{self.class}] FAILURE error=#{error.class} elapsed=#{elapsed}ms"
      Result.failure(error)
    end

    def logger
      @logger ||= Logger.new($stdout)
    end
  end
  ```
- **Deliverable:** BaseService everyone inherits from.
- **Commit:** `feat: add BaseService with logging and timing`

### Task 30.2: Verify BaseService contract with spec
- **File:** `spec/services/base_service_spec.rb`
- **Coverage:** success path, failure path, timing measurement, missing implementation raises.
- **Acceptance Criteria:**
  - All branches pass
  - `bundle exec rspec spec/services/base_service_spec.rb` exits 0
  - Test runs in CI without side effects

---



## Day 31 — InstrumentRepository

### Task 31.1: Implement `app/services/repositories/instrument_repository.rb`
- **Dependencies:** Database access only; no Redis yet (caching added later).
- **Methods:**
  - `find_by_symbol(symbol)`
  - `find_by_security_id(security_id)`
  - `find_atm_strikes(underlying, expiry, count: 5)`
  - `find_by_underlying_and_expiry(underlying, expiry)`
  - `active_underlyings`
  - `expiries_for(underlying)`
- **Deliverable:** InstrumentRepository implementation.
- **Acceptance Criteria:**
  - Queries use composite indexes from Milestone 0.3
  - All methods return Array or Model or nil, not raw relations
  - Methods are single-responsibility

### Task 31.2: Write instrument repository spec
- **File:** `spec/services/repositories/instrument_repository_spec.rb`
- **Coverage:** symbol lookup, security id lookup, ATM strikes, underlying queries.
- **Acceptance Criteria:**
  - Uses FactoryBot instruments from M0.1
  - Tests run against test database
  - Specs are deterministic (no network)

### Task 31.3: Implement `app/services/repositories/tick_repository.rb`
- **Methods:** `latest`, `range`, `aggregate_to_candles`, `count_gaps`
- **Goal:** TimescaleDB-aware data reader with minimal raw SQL.
- **Deliverable:** TickRepository.
- **Commit:** `feat: add instrument and tick repositories`

---



## Day 32 — CandleRepository + OptionChainRepository

### Task 32.1: Implement `app/services/repositories/candle_repository.rb`
- **Methods:** `latest`, `range`, `vwap_range`, `previous_close`, `opening_range`
- **Goal:** Multi-timeframe single-query access via hypertable indexes.
- **Deliverable:** CandleRepository.

### Task 32.2: Implement `app/services/repositories/option_chain_repository.rb`
- **Methods:** `latest_snapshot`, `snapshot_at`, `strike_range`, `atm_strikes`, `greeks_for`, `oi_change`
- **Goal:** Optimized strike-range queries for option intelligence engine.
- **Deliverable:** OptionChainRepository.

### Task 32.3: Add repository base interface contract tests
- **Shared examples:** repository returns data or Result.failure on missing records
- **Deliverable:** `spec/support/shared_examples/repositories.rb`
- **Commit:** `feat: add candle and option chain repositories`

---



## Day 33 — EventBus + Redis Pooling

### Task 33.1: Implement `app/services/event_bus.rb`
- **Goal:** Redis pub/sub bus with typed channels.
- **Channels:** `market.ticks`, `market.candles`, `orders.updates`, `positions.updates`, `engine.signals`, `risk.alerts`
- **Methods:** `publish(channel, payload)`, `subscribe(channel) { |msg| ... }`
- **Goal:** JSON serialization with schema versioning and dead letter queue.
- **Deliverable:** EventBus.

### Task 33.2: Implement `app/services/redis/pool.rb`
- **Goal:** ConnectionPool config aligned with M0.2 typed settings.
- **Requirement:** Separate pools for cache, cable, queue, pubsub.
- **Deliverable:** RedisPool wrapper.

### Task 33.3: Write EventBus spec (in-memory adapter)
- **Goal:** Keep Redis out of test environment via adapter.
- **Deliverable:** `EventBus::TestAdapter` for specs.
- **Acceptance Criteria:**
  - `EventBus.publish(:test, {foo: 1})` then `EventBus.subscribe(:test)` yields same payload in test
  - No real Redis connection required in CI
- **Commit:** `feat: add EventBus and Redis pool`

---



## Day 34 — Gateway Abstractions

### Task 34.1: Create `app/gateway/ai_gateway.rb`
- **Goal:** Multi-provider LLM abstraction for OpenAI, Anthropic, Ollama, and future providers.
- **Methods:** `complete(prompt, **options)`, `embed(text)` optional, latency and token tracking hooks.
- **Deliverable:** AiGateway.

### Task 34.2: Create `app/gateway/broker_gateway.rb`
- **Goal:** DhanHQ REST + WebSocket abstraction.
- **Responsibilities:** credentials, retries, timeouts, structured errors, request tracing.
- **Deliverable:** BrokerGateway.
- **Commit:** `feat: add AI and broker gateways`

### Task 34.3: Add gateway spec skeletons
- **Goal:** Contract tests for both gateways without real network.
- **Deliverable:** VCR/webmock-ready specs.
- **Acceptance:**
  - Specs pass without external network
  - Fake responses can be stubbed for deterministic testing

---



## Day 35 — DI Container + dry-container Integration

### Task 35.1: Create `app/container.rb`
- **Dependencies:** `dry-container`, `dry-auto_inject`
- **Registrations:**
  - `instrument_repository`
  - `tick_repository`
  - `candle_repository`
  - `option_chain_repository`
  - `event_bus`
  - `ai_gateway`
  - `broker_gateway`
  - `redis_pool`
- **Deliverable:** Container.

### Task 35.2: Add `Import` macro to services, engines, repositories
- **Goal:** Explicit dependencies only.
- **Deliverable:** Each service gets `include Import[...]` and lists dependencies.
- **Commit:** `feat: add dry-container dependency injection`

### Task 35.3: Verify container resolution in test
- **Goal:** Container resolves all dependencies.
- **Acceptance:**
  - `Container.resolve(:instrument_repository)` returns Repository instance
  - Circular dependencies raise clear `Dry::Container::Error`
  - `Container.register` is not invoked more than once in tests

---



## Day 35.5 — Execution Mode Adapter Contract
*(Insert after `Day 35 — DI Container + dry-container Integration` and before `Day 36 — Engine Interfaces`)*

### Task 35.4: Define ExecutionGateway interface and execution modes
- **Context:** Paper trading must be a mode, not a separate module. The same strategy/risk path feeds all modes.
- **File:** Define protocol in architecture docs; implementation in Phase 6.
- **Interface:** `execute(input) -> ExecutionOutput`
- **Modes:** `:live`, `:paper`, `:backtest`, `:replay`
- **Contract:**
  - Input shape is identical across modes.
  - Output shape is identical across modes.
  - Only the broker/data adapter changes.
- **Configuration:** Single source of truth for current mode (ENV / AppConfig), loaded by the DI container.
- **Deliverable:** Architecture contract that M6.2 implements.
- **Acceptance Criteria:**
  - All future engines reference `ExecutionGateway`, never a concrete broker class directly.
  - Mode switching does not require code changes.
  - Documented in `docs/architecture.md`.

### Task 35.5: Freeze shared invariants for mode parity
- **Invariants:**
  - Order model is the same across modes.
  - Risk checks run before any mode adapter.
  - Slippage model is mode-aware but schema-stable.
  - Event bus payloads for `OrderSubmitted`, `OrderFilled`, `PositionUpdated` are unaffected by mode.
- **Deliverable:** Invariants list in milestone doc.
- **Acceptance Criteria:**
  - No mode implements its own order schema.
  - No mode bypasses RiskValidationEngine.
- **Commit:** `docs: freeze execution mode parity invariants`

---



## Day 36 — Engine Interfaces

### Task 36.1: Define `app/engines/base_engine.rb`
- **Interface:** `analyze(context) -> EngineOutput`
- **EngineOutput:** structured data class with `to_h` for serialization.
- **Deliverable:** BaseEngine.

### Task 36.2: Create first engines
- **Engines:** MarketContextEngine, MarketRegimeEngine, MarketStructureEngine, MomentumEngine, LiquidityEngine, OptionIntelligenceEngine, StrikeSelectionEngine, TradeScoringEngine, RiskValidationEngine, ExecutionEngine, PositionManagementEngine
- **Deliverable:** Starter engines with pass-through or simple deterministic logic.
- **Commit:** `feat: add engine interfaces and starter engines`

### Task 36.3: Add engine interface specs
- **Goal:** Ensure all engines accept and return expected shapes.
- **Deliverable:** Shared examples for engines.
- **Acceptance Criteria:**
  - Any engine that returns `nil` fails the interface test
  - `EngineOutput` validates serialization of engine data

---



## Day 37 — Calculations Library + Validators

### Task 37.1: Implement `app/lib/calculations/statistics.rb`
- **Functions:** `sma`, `ema`, `std_dev`, `percentile`, `z_score`, `percentile_rank`, `correlation`, `covariance`
- **Goal:** Pure mathematical functions used across all engines.
- **Deliverable:** Statistics module.
- **Acceptance Criteria:**
  - All functions are pure, no side effects
  - Full coverage with small numerics

### Task 37.2: Create `app/services/validators/` directory
- **Validators:**
  - `InputValidator` - dry-validation schemas for engine inputs
  - `MarketDataValidator` - freshness, continuity checks
  - `OrderValidator` - order parameter validation
  - `RiskValidator` - pre-trade checks
- **Deliverable:** Validators.

### Task 37.3: Validator self-check spec
- **Goal:** Ensure validators produce structured errors that can be bound back to Result.
- **Deliverable:** Validators returning ServiceError/ValidationError.
- **Commit:** `feat: add calculations library and validators`

---



## Day 38 — Learning Loop & Repository Storage

### Task 38.1: Create `app/services/learning/` subdirectory
- **Goal:** Strategy metrics storage and retrieval using TradeScore/Learning tables from M0.3.
- **Deliverable:** LearningRecorder + LearningReader services.
- **Acceptance Criteria:**
  - Learning records can be written for known strategies
  - Records are queryable by time window and strategy name

### Task 38.2: Reporting and journaling hooks
- **Goal:** Hook learning logs into ExecutionEngine or ScoringEngine flows.
- **Deliverable:** Hooks in `app/services/engines/`.
- **Acceptance Criteria:**
  - One pipeline writes a learning record on trade close
  - Learning record contains all required columns from schema

### Task 38.3: Invariants verification for M0.1 / M0.2 metadata
- **Goal:** Ensure no leftover service assumptions from earlier milestones.
- **Deliverable:** Checklist and spec that guards regressions.
- **Acceptance Criteria:**
  - M0.2 env/credentials conventions are preserved by services
  - No hotfixes bypass the container / Result conventions

---



## Day 39 — Architecture Documentation + Contract Tests

### Task 39.1: Document Service Boundaries
- **File:** `docs/architecture.md`
- **Contents:**
  - Service layer diagram
  - Dependency graph (container registrations)
  - Data flow: Market Data → Engines → Strategy → Scoring → Risk → Execution
  - Event bus channels and payloads
  - Testing strategies for each layer
- **Deliverable:** Architecture document.

### Task 39.2: Contract tests for repositories and engines
- **Goal:** Ensure every repository and engine adheres to its contract.
- **Deliverable:** Contract specs in `spec/services/contracts/`.
- **Acceptance Criteria:**
  - Contract specs fail on method rename or signature change
  - CI gate prevents accidental contract drift

---



## Day 40 — Final Integration,Polish, and Sign-Off

### Task 40.1: Define lightweight implementation playbooks
- **Goal:** Reduce friction for onboarding by codifying M0.3/M0.4 conventions.
- **Deliverable:** Checklists for M0.3 and M0.4 in `docs/`.
- **Acceptance Criteria:**
  - Checklists align exactly with sprint tasks
  - Ready for engineer to follow in 10 minutes

### Task 40.2: Tech debt and robustness pass
- **Goal:** Review why M0.1 iteration was needed and harden automation for future milestones.
- **Deliverable:** Documented tech-debt items with owner and due sprint.
- **Acceptance Criteria:**
  - Tech debt is tracked in markdown, not left in abstract notes
  - Each item has clear remediation step

### Task 40.3: Architecture regression checks + tag
- **Goal:** Run final checks (`bundle exec rspec`, `bin/rails db:migrate`, seed runs, container tests).
- **Deliverable:** Git tag `m0.4-complete`, README updated with milestone cross-links.
- **Acceptance Criteria:**
  - `git tag -l` shows `m0.4-complete`
  - README links M0.4 to M1 milestone map
  - All deliverable checks in this sprint checklist are checked
- **Commit:** `chore: milestone 0.4 complete + docs polish`

---



## Sprint Checklist & Definition of Done

| # | Deliverable | Verification Method |
|---|------------|---------------------|
| 1 | Result object + ServiceError implemented | spec/service result tests pass |
| 2 | BaseService contract fulfilled | BaseService spec + timing test pass |
| 3 | InstrumentRepository works | repository spec pass |
| 4 | TickRepository works | repository spec pass |
| 5 | CandleRepository works | repository spec pass |
| 6 | OptionChainRepository works | repository spec pass |
| 7 | EventBus publish/subscribe works | EventBus in-memory spec pass |
| 8 | Redis pool separated by purpose | Redis pool spec pass |
| 9 | AI gateway abstraction ready | gateway contract spec pass |
| 10 | Broker gateway abstraction ready | broker contract spec pass |
| 11 | DI container resolves all services | container resolution test pass |
| 12 | Engines implement base interface | engine shared examples pass |
| 13 | Statistics module produces correct math | statistics spec pass |
| 14 | Validators enforce input rules | validator specs pass |
| 15 | Learning loop stores and reads records | learning spec pass |
| 16 | Architecture document complete | peer review sign-off |
| 17 | Regression checks green | full test suite pass + migrate pass |
| 18 | README updated | readable sign-off |

---

## Next Steps

After Milestone 0.4 is complete, proceed to **Milestone 1.1** or the next phase (e.g., market data ingestion, strategy execution, monitoring/observability).
