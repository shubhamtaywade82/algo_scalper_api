◈─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

  Code Review Report — NEMESIS V3 Trading System

  Repository: algo_scalper_api

  Review Date: 2025-12-21

  Scope: Full codebase audit (architecture, models, services, controllers, jobs, tests)

◈─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

  Executive Summary

  ┌──────────┬────────────┬──────────────┬────────────┬────────────────┐
  │ Category │ Critical   │ High         │ Medium     │ Low            │
  ├──────────┼────────────┼──────────────┼────────────┼────────────────┤
  │ Count    │ 8          │ 15           │ 23         │ 12             │
  ├──────────┼────────────┼──────────────┼────────────┼────────────────┤
  │ Priority │ 🔴 Must    │ 🟠 Should    │ 🟡         │ ⚪             │
  │          │ fix        │ fix          │ Consider   │ Nice-to-have   │
  └──────────┴────────────┴──────────────┴────────────┴────────────────┘

  Overall Assessment: Complex trading system with sophisticated domain logic. Strong event-driven architecture and comprehensive guard rail system. However, significant
  technical debt in service complexity, test coverage gaps, and several critical architectural issues.

◈─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

  🔴 CRITICAL ISSUES (Must Fix Before Production)

    1. God Class: PositionTracker Model (280+ lines)
    File: app/models/position_tracker.rb

    Issue: Violates SRP — mixes persistence, state machine, Redis caching, PnL calculation, broadcasting, subscription management, and trade analysis.

    Risk: High coupling, untestable logic, difficult to extend.

    Fix: Extract responsibilities:
    ruby
    # Extract to value objects/services
    PositionTracker::PnlCalculator
    PositionTracker::StateTransitions
    PositionTracker::RedisCacheManager
    PositionTracker::BroadcastNotifier
    PositionTracker::TradeAnalyzer


    2. Massive Service: Entries::EntryGuard (1400+ lines)
    File: app/services/entries/entry_guard.rb

    Issue: 25+ public methods, complex nested conditionals, mixed responsibilities (validation, order placement, cooldown, sizing, BOS detection).

    Risk: Cognitive overload, regression-prone, violates single responsibility.

    Fix: Decompose into focused services:
    ruby
    Entries::OrderPlacementService
    Entries::PositionSizingService
    Entries::CooldownChecker
    Entries::BosStructureValidator
    Entries::InstrumentProfileChecker


    3. Thread Safety Issues in RiskManagerService
    File: app/services/live/risk_manager_service.rb

    Issue: Instance variables (@redis_pnl_cache, @cycle_tracker_map) accessed from multiple threads without synchronization. Event handler runs in separate thread from monitor_loop.

    Risk: Race conditions, data corruption under load.

    Fix: Use Concurrent::Map for all shared state:
    ruby
    @redis_pnl_cache = Concurrent::Map.new
    @active_enforcements = Concurrent::Map.new  # ✅ Already done


    4. Missing Database Indexes
    Files: Multiple models

    Issue: No indexes on frequently queried foreign keys and filter columns.

    Risk: N+1 queries, slow lookups under load.

    Fix: Add migration:
    ruby
    add_index :position_trackers, [:status, :paper]
    add_index :position_trackers, [:security_id, :segment]
    add_index :position_trackers, [:watchable_type, :watchable_id]
    add_index :trading_signals, [:index_key, :signal_timestamp]
    add_index :trade_telemetries, [:tracker_id]


    5. Bare rescue StandardError Without Logging
    Files: Multiple services

    Issue: Silent failures in critical paths (e.g., ExitEngine#safe_ltp, EntryGuard#get_paper_ltp_for_tracker).

    Risk: Errors swallowed, debugging impossible in production.

    Fix: Always log with context:
    ```ruby
    # BAD
    rescue StandardError
      nil

GOOD
rescue StandardError => e
  Rails.logger.error(“[ExitEngine] LTP fetch failed: #{e.class} - #{e.message}”)
  nil
```

    6. No Transaction Isolation for Exit Flow
    File: app/services/live/exit_engine.rb

    Issue: Exit intent, broker order, and tracker update not in single transaction. Can leave tracker in inconsistent state if broker fails after intent persisted.

    Risk: Double exits, orphaned positions.

    Fix: Use database transaction with proper rollback:
    ruby
    PositionTracker.transaction do
      tracker.with_lock do
        prepare_exit_intent!
        # Place broker order
        # Update tracker
      end
    end


    7. Magic Numbers in Business Logic
    Files: Multiple services

    Issue: Hardcoded values like BOS_MAX_AGE_CANDLES = 8, LOOP_INTERVAL = 5, EXIT_INTENT_RETRY_AFTER_SECONDS = 15.

    Risk: Configuration drift, impossible to tune without code changes.

    Fix: Move to AlgoSetting schema:
    ruby
    # config/initializers/algo_config.rb
    ENTRY_GUARD_MAX_BOS_AGE_CANDLES: { type: :integer, default: 8 }
    RISK_MANAGER_LOOP_INTERVAL: { type: :integer, default: 5 }


    8. No Circuit Breaker for External API Calls
    Files: DhanHQ API calls throughout

    Issue: Rate limit errors handled ad-hoc with sleep(5). No exponential backoff or circuit breaker pattern.

    Risk: Cascading failures during API outages.

    Fix: Implement circuit breaker:
    ruby
    # Use existing CircuitBreaker model or gem like 'circuitbox'
    CircuitBox.circuit(:dhanhq_api, threshold: 5, timeout: 60) do
      DhanHQ::Models::Order.create(payload)
    end


◈─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

  🟠 HIGH PRIORITY (Should Fix)

    9. EntryGuardPipeline Hardcoded Handler Order
    File: app/services/entries/entry_guard_pipeline.rb

    Issue: Guard order fixed in default_handlers method. Cannot be configured per environment or strategy.

    Fix: Make configurable via dependency injection:
    ruby
    def initialize(handlers: configured_handlers)
      @handlers = handlers
    end


    10. Inconsistent Error Handling Pattern
    Files: Controllers vs Services

    Issue: Controllers use Api::ErrorHandling concern, services use mixed patterns (some log+notify, some just log).

    Fix: Standardize with ApplicationService base class already in place.

    11. Missing Test Coverage for Critical Paths
    Files: spec/ directory

    Issue: Only 2 tests for PositionTracker, no integration tests for exit flow, entry guards, or risk management.

    Fix: Add comprehensive specs:
    ruby
    # spec/services/live/exit_engine_spec.rb
    # spec/services/entries/entry_guard_spec.rb
    # spec/services/live/risk_manager_service_spec.rb


    12. ExitEngine Uses Redis for Distributed Lock Without Error Handling
    File: app/services/live/exit_engine.rb:237

    Issue: Redis connection failure silently returns true (allows exit), potentially causing dual exits.

    Fix: Fail-safe default should block exit on Redis failure:
    ruby
    def acquire_exit_lock(tracker_id, ttl: 10)
      key = "exit_lock:#{tracker_id}"
      @redis ||= Redis.new(...)
      @redis.set(key, '1', nx: true, ex: ttl)
    rescue Redis::BaseError => e
      Rails.logger.error("[ExitEngine] Redis lock failed: #{e.message}")
      false  # Block exit on Redis failure
    end


    13. Instrument Model Mixes Concerns
    File: app/models/instrument.rb

    Issue: Option chain fetching, caching, expiry logic, order placement all in one model.

    Fix: Extract:
    ruby
    OptionChain::Fetcher
    OptionChain::CacheManager
    OptionChain::ExpiryResolver


    14. No Validation on meta JSONB Column
    Files: PositionTracker, TradingSignal

    Issue: Arbitrary schema-less JSON allows inconsistent data.

    Fix: Add JSON Schema validation:
    ruby
    # Using json_schemer gem (already in Gemfile)
    validates :meta, json_schema: POSITION_TRACKER_META_SCHEMA


    15. EventBus Stats Not Thread-Safe
    File: app/services/core/event_bus.rb

    Issue: @stats hash modified from multiple threads without mutex.

    Fix: Use Concurrent::Map or mutex:
    ruby
    @stats = Concurrent::Map.new { |h, k| h[k] = Concurrent::AtomicFixnum.new(0) }


    16. SmcScannerJob Has No Timeout
    File: app/jobs/smc_scanner_job.rb

    Issue: Can run indefinitely if API hangs. No job timeout configured.

    Fix: Add Sidekiq job timeout:
    ruby
    sidekiq_options retry: 3, dead: false, timeout: 300


    17. Orders::Placer Uses Global ENV for Feature Flag
    File: app/services/orders/placer.rb:167

    Issue: ENV['PLACE_ORDER'] checked inline. Should use AlgoSetting.

    Fix: Use typed settings:
    ruby
    def order_placement_enabled?
      AlgoSetting.order_placement_enabled?
    end


    18. ApplicationService Telegram Notification Anti-Pattern
    File: app/services/application_service.rb

    Issue: Auto-sends Telegram on every log_error. Should be explicit.

    Fix: Remove auto-notify, make explicit:
    ```ruby
    # Remove automatic Telegram notification from log_error
    def log_error(msg)
      Rails.logger.error(“[#{self.class.name}] #{msg}”)
    end

Add explicit method when notification needed
def notify_error(message, tag: nil)
  # …
end
```

    19. TradingSignal#calculate_accuracy Has Logic Error
    File: app/models/trading_signal.rb:75

    Issue: Returns negative percentage for losses (e.g., -5.2%), but method name suggests 0-100 accuracy.

    Fix: Rename or fix logic:
    ```ruby
    def calculate_pnl_percentage
      # Returns signed percentage
    end

    def calculate_accuracy_percentage
      # Returns absolute value or binary correct/incorrect
    end
    ```

    20. Backtest::Engine Hardcoded Initial Capital
    File: app/services/backtest/engine.rb:10

    Issue: initial_capital: 100_000 hardcoded. Should be configurable.

    Fix: Parameterize:
    ruby
    def initialize(data:, strategy:, initial_capital: 100_000)


◈─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

  🟡 MEDIUM PRIORITY (Consider Fixing)

    21. Api::PositionsController Does N+1 in open_positions
    File: app/controllers/api/positions_controller.rb:14

    Issue: .map triggers lazy loading despite includes.

    Fix: Force eager load:
    ruby
    def open_positions
      PositionTracker
        .active
        .includes(:watchable, :instrument)
        .load  # Force eager loading
        .map { |tracker| Positions::Serializer.open(tracker) }
    end


    22. PositionTracker Callback Chain Too Complex
    File: app/models/position_tracker.rb:36-47

    Issue: 11 callbacks with complex conditions. Hard to trace execution flow.

    Fix: Extract to service object:
    ```ruby
    def mark_exited!(…)
      Positions::ExitFlow.call(…)  # Already done ✅
    end

Remove callbacks, call explicitly

### 23. **`Live::Gateway` Deprecated Wrapper Still in Use**
**File:** `app/services/live/gateway.rb`
**Issue:** Delegates to `Orders::GatewayLive` with deprecation warning. Should be removed.
**Fix:** Replace all usages with `Orders::GatewayLive`, then delete.

### 24. **`Core::EventBus` Uses String Keys for Subscription IDs**
**File:** `app/services/core/event_bus.rb`
**Issue:** `SecureRandom.uuid` generates strings. Could use more efficient integer IDs.
**Fix:** Minor optimization, low priority.

### 25. **`AlgoSetting` Schema Not Validated**
**File:** `app/models/algo_setting.rb`
**Issue:** No validation that all settings in DB match schema.
**Fix:** Add rake task to validate:
```ruby
# lib/tasks/algo_settings.rake
namespace :algo_settings do
  desc 'Validate settings against schema'
  task validate: :environment do
    # Check for orphaned settings
  end
end

    26. EntryGuard#banknifty_monthly_expiry Has Fallback Logic
    File: app/services/entries/entry_guard.rb:750

    Issue: Falls back to “last Thursday” heuristic if expiry_list unavailable. Could be wrong on holidays.

    Fix: Fail-safe: return nil and block entry rather than guess.

    27. ExitEngine#normalize_exit_reason_with_final_pnl Updates Model Twice
    File: app/services/live/exit_engine.rb:185

    Issue: Calls tracker.transaction then tracker.update!. Could be single update.

    Fix: Consolidate into one update.

    28. PositionTracker#current_pnl_rupees Has Triple Fallback
    File: app/models/position_tracker.rb:203

    Issue: Redis → DB → zero. Complex error handling.

    Fix: Extract to PnlResolver service.

    29. Instrument#fetch_option_chain Has Complex Caching Logic
    File: app/models/instrument.rb:177

    Issue: Mixes cache read/write, staleness check, fresh fetch.

    Fix: Extract to OptionChain::CacheService.

    30. RiskManagerService#start Doesn’t Check Event Subscription Cleanup
    File: app/services/live/risk_manager_service.rb:55

    Issue: If start called twice, creates duplicate subscriptions.

    Fix: Check and unsubscribe before re-subscribing.

    31. EntryGuard#try_enter Has 15+ Early Returns
    File: app/services/entries/entry_guard.rb:38

    Issue: While guard clauses are good, 15+ makes flow hard to follow.

    Fix: Extract validation pipeline:
    ruby
    def validate_entry(context)
      validators = [DrawdownGuardValidator, EntryPolicyValidator, ...]
      validators.map { |v| v.validate(context) }.compact.first
    end


    32. PositionTracker Uses store_accessor Without Validation
    File: app/models/position_tracker.rb:10

    Issue: 11 accessor keys defined but no validation of types or presence.

    Fix: Add custom validators.

    33. SmcScannerJob Uses sleep for Rate Limiting
    File: app/jobs/smc_scanner_job.rb:42

    Issue: Blocks Sidekiq thread. Should use exponential backoff with retry.

    Fix: Use Sidekiq retry with wait:
    ruby
    retry_on DhanHQ::RateLimitError, wait: ->(executions) { 2**executions * 5 }


    34. Api::ErrorHandling Returns Generic Error Message
    File: app/controllers/concerns/api/error_handling.rb:44

    Issue: Returns "internal_error" for all errors. No differentiation.

    Fix: Map exception types to messages:
    ruby
    case error
    when ActiveRecord::RecordNotFound then "not_found"
    when ActiveModel::ValidationError then "validation_error"
    else "internal_error"
    end


    35. ExitEngine#record_trade_telemetry Has 25+ Field Assignments
    File: app/services/live/exit_engine.rb:283

    Issue: Long list of meta&.dig calls. Hard to maintain.

    Fix: Extract to TradeTelemetry::Builder.

    36. Orders::Placer#with_token_auto_heal Has Retry Logic Bug
    File: app/services/orders/placer.rb:186

    Issue: retried flag set after yield, so first retry always happens.

    Fix: Move flag check before retry:
    ruby
    return nil if retried  # Check before retry
    Dhan::TokenManager.refresh!
    retried = true
    retry


    37. EntryGuard#calculate_current_pnl Mixes Paper/Live Logic
    File: app/services/entries/entry_guard.rb:523

    Issue: Large conditional branching on tracker.paper?.

    Fix: Extract to separate strategies.

    38. PositionTracker#broadcast_position_activated Has No Error Recovery
    File: app/models/position_tracker.rb:472

    Issue: Silent failure if ActionCable broadcast fails.

    Fix: At minimum, log with higher severity.

    39. Instrument#SEGMENT_FROM_EXCHANGE Hash Not Validated
    File: app/models/instrument.rb:120

    Issue: No validation that all DhanHQ segments are mapped.

    Fix: Add test to verify mapping completeness.

    40. ApplicationService#notify Has No Rate Limiting
    File: app/services/application_service.rb:16

    Issue: Could spam Telegram if called in loop.

    Fix: Add rate limiting or batch notifications.

    41. EntryGuard#exposure_ok? Uses Raw SQL
    File: app/services/entries/entry_guard.rb:425

    Issue: SQL string interpolation for polymorphic query.

    Fix: Use Arel or extract to query object:
    ruby
    Positions::ActiveForUnderlyingQuery.call(instrument: instrument, side: side)


    42. RiskManagerService#monitor_loop Not Defined in File
    File: app/services/live/risk_manager_service.rb

    Issue: Includes Runner module but method not visible in file. Hidden complexity.

    Fix: Ensure modules are well-documented or inline critical methods.

    43. TradingSignal Scope recent Uses Hardcoded 24 Hours
    File: app/models/trading_signal.rb:33

    Issue: Magic number in scope.

    Fix: Parameterize:
    ruby
    scope :recent, ->(hours = 24) { where(signal_timestamp: hours.hours.ago..) }


    44. PositionTracker::ORPHANED_CLEAR_INTERVAL Class Constant
    File: app/models/position_tracker.rb:29

    Issue: Should be configurable.

    Fix: Move to AlgoSetting.

    45. ExitEngine#deterministic_exit_coid Uses SHA256 for Short ID
    File: app/services/live/exit_engine.rb:223

    Issue: Overkill for correlation ID. Could use simpler hash.

    Fix: Minor optimization.

◈─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

  🔵 BEST PRACTICES (Architectural Improvements)

    46. Consider Command Query Responsibility Segregation (CQRS)
    Issue: PositionTracker serves both read (dashboard) and write (exit) models.

    Suggestion: Separate read models (Redis cache) from write models (PostgreSQL).

    47. Add Domain Events for Audit Trail
    Issue: No persistent event log for compliance/debugging.

    Suggestion: Store all EventBus events to domain_events table.

    48. Implement Repository Pattern for Complex Queries
    Issue: Query logic scattered in models/controllers.

    Suggestion: Extract to repositories:
    ruby
    PositionTrackerRepository
    TradingSignalRepository


    49. Use Value Objects for Domain Primitives
    Issue: Raw strings/floats for security_id, pnl, quantity.

    Suggestion: Wrap in value objects:
    ruby
    SecurityId.new(value)
    Pnl.rupees(amount)
    Quantity.lots(count)


    50. Add Health Check for External Dependencies
    Issue: No /health endpoint checking DhanHQ, Redis, DB connectivity.

    Suggestion: Add comprehensive health check endpoint.

◈─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

  ⚪ STYLE & CONSISTENCY (Low Priority)

    51-58. Minor Style Issues
    ● Inconsistent use of present? vs blank?
    ● Mixed Symbol vs String keys in hashes
    ● Some methods exceed 10 lines (solid_ruby guideline)
    ● Missing frozen_string_literal in some files
    ● Inconsistent blank line spacing
    ● Some # rubocop:disable comments without justification
    ● TODO comments without tracking

◈─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

  Testing Gaps

    Missing Test Coverage:
    1. PositionTracker — Only 2 tests, need 20+
    2. ExitEngine — Zero tests
    3. EntryGuard — Zero tests
    4. RiskManagerService — Zero tests
    5. EventBus — Zero tests
    6. Integration tests — Only 11 specs for entire system
    7. Request specs — Missing for most API endpoints
    8. Background jobs — Minimal coverage

    Recommended Test Structure:
    spec/
    ├── models/
    │   ├── position_tracker_spec.rb (needs 10x expansion)
    │   └── trading_signal_spec.rb
    ├── services/
    │   ├── live/
    │   │   ├── exit_engine_spec.rb
    │   │   ├── risk_manager_service_spec.rb
    │   │   └── entry_guard_spec.rb
    │   └── orders/
    │       └── gateway_spec.rb
    ├── integration/
    │   ├── exit_flow_spec.rb
    │   ├── entry_guard_pipeline_spec.rb
    │   └── risk_management_spec.rb
    └── requests/
        └── api/
            └── positions_spec.rb

◈─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

  Performance Recommendations

  1. Add database indexes (see Critical #4)
  2. Use find_each for batch processing in SmcScannerJob
  3. Cache AlgoConfig.fetch results — currently called repeatedly
  4. Use pluck instead of loading full objects in queries
  5. Add Redis connection pooling configuration
  6. Profile EntryGuard#try_enter — likely bottleneck
  7. Use select to limit columns in frequently queried models

◈─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

  Security Concerns

  1. No rate limiting on API endpoints
  2. Api::ErrorHandling leaks stack traces to logs (good) but should verify not in responses
  3. No input validation on API params (e.g., positions_controller.rb sort params)
  4. Credentials in config/master.key — ensure not committed
  5. No CSRF protection — acceptable for API-only, but verify
  6. SQL injection risk in EntryGuard#exposure_ok? raw SQL

◈─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

  Deployment Checklist

  ● [ ] Add database indexes (Critical #4)
  ● [ ] Configure Sidekiq timeouts (High #16)
  ● [ ] Set up monitoring for Redis/DB connections
  ● [ ] Add health check endpoint
  ● [ ] Configure log rotation
  ● [ ] Set up error tracking (Sentry/Rollbar)
  ● [ ] Add performance monitoring (New Relic/Skylight)
  ● [ ] Document environment variables
  ● [ ] Add rollback procedure for migrations
  ● [ ] Test disaster recovery (DB restore, Redis rebuild)

◈─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

  Summary

  Strengths:
  - Well-structured event-driven architecture
  - Comprehensive guard rail system for risk management
  - Good use of service objects (when not too large)
  - Strong separation of concerns in some areas (ExitEngine, EntryGuardPipeline)

  Weaknesses:
  - Several god classes violating SRP
  - Insufficient test coverage (< 10% estimated)
  - Thread safety issues in concurrent code
  - Missing database indexes
  - Inconsistent error handling

  Recommendation: Address Critical issues (1-8) before next production deployment. High priority issues (9-20) should be fixed within 2 sprints. Begin test coverage
  expansion immediately.

◈─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────◈

  Want me to:
  1. Generate fix PRs for specific issues?
  2. Create detailed refactoring plans for god classes?
  3. Write missing test specs?
  4. Add database index migration?