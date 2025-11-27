# Design Patterns Analysis: Algo Scalper API

## Executive Summary

This document analyzes design patterns currently used in the algo scalper API application and recommends best practices for a production-grade trading system. The analysis covers existing patterns, their relevance, and recommendations for improvement.

---

## 1. Existing Design Patterns

### 1.1 Singleton Pattern ✅ **WELL IMPLEMENTED**

**Current Usage:**
- `Core::EventBus` - Central event broadcasting
- `Risk::CircuitBreaker` - Risk management state
- `Live::MarketFeedHub` - WebSocket connection management
- `Live::TickCache` - Real-time price cache
- `Live::RedisPnlCache` - PnL cache
- `IndexInstrumentCache` - Instrument data cache
- `Positions::ActiveCache` - Active positions cache
- Multiple live services (17+ singletons)

**Relevance:**
- ✅ **Critical for trading systems** - Ensures single source of truth for:
  - Market data feeds (prevent duplicate subscriptions)
  - Risk state (circuit breaker must be global)
  - Cache consistency (single cache instance)
  - Thread safety (shared state management)

**Best Practices Applied:**
```ruby
# Example: Core::EventBus
include Singleton
@subscribers = Concurrent::Map.new { |h, k| h[k] = Concurrent::Array.new }
@lock = Mutex.new
```
- ✅ Thread-safe collections (`Concurrent::Map`, `Concurrent::Array`)
- ✅ Mutex for critical sections
- ✅ Proper initialization

**Recommendations:**
- ✅ **Keep as-is** - Singleton pattern is essential for trading systems
- Consider adding health check methods to all singletons:
  ```ruby
  def health
    { running: @running, connected: @connected, stats: @stats }
  end
  ```

---

### 1.2 Strategy Pattern ✅ **WELL IMPLEMENTED**

**Current Usage:**
- `Signal::StrategyAdapter` - Adapts different strategies to common interface
- Strategy classes: `SimpleMomentumStrategy`, `SupertrendAdxStrategy`, `InsideBarStrategy`
- `Signal::Engine` - Uses strategy recommendations dynamically

**Relevance:**
- ✅ **Essential for trading** - Allows switching strategies without code changes
- ✅ Enables A/B testing of strategies
- ✅ Strategy recommender selects best strategy per index

**Implementation:**
```ruby
# Signal::StrategyAdapter
def analyze_with_strategy(strategy_class:, series:, index:, strategy_config: {})
  strategy = strategy_class.new(series: series, **strategy_config)
  signal = strategy.generate_signal(index)
  # Convert to standard format
end
```

**Recommendations:**
- ✅ **Well-designed** - Strategy pattern correctly implemented
- Consider adding strategy registry:
  ```ruby
  module Signal
    class StrategyRegistry
      STRATEGIES = {
        momentum: SimpleMomentumStrategy,
        supertrend_adx: SupertrendAdxStrategy,
        inside_bar: InsideBarStrategy
      }.freeze
      
      def self.get(name)
        STRATEGIES[name.to_sym]
      end
    end
  end
  ```

---

### 1.3 Template Method Pattern ✅ **IMPLICITLY USED**

**Current Usage:**
- `TradingSystem::BaseService` - Defines lifecycle (`start`, `stop`)
- `Orders::Gateway` - Abstract base with `place_market`, `exit_market`, `position`
- Concrete implementations: `Live::Gateway`, `Orders::GatewayPaper`

**Relevance:**
- ✅ **Critical for abstraction** - Separates interface from implementation
- ✅ Enables paper/live trading switch
- ✅ Ensures consistent API across implementations

**Implementation:**
```ruby
# Orders::Gateway (Abstract)
class Gateway
  def place_market(side:, segment:, security_id:, qty:, meta: {})
    raise NotImplementedError, "#{self.class} must implement place_market"
  end
end

# Live::Gateway (Concrete)
class Live::Gateway < Orders::Gateway
  def place_market(...)
    Orders::Placer.buy_market!(...)
  end
end
```

**Recommendations:**
- ✅ **Good pattern** - Template method correctly used
- Consider adding default implementations for optional methods:
  ```ruby
  def on_tick(segment:, security_id:, ltp:)
    nil # Default: no-op
  end
  ```

---

### 1.4 Observer Pattern (Pub/Sub) ✅ **WELL IMPLEMENTED**

**Current Usage:**
- `Core::EventBus` - Central pub/sub system
- Event types: `:ltp`, `:entry_filled`, `:sl_hit`, `:tp_hit`, `:risk_alert`, etc.
- Thread-safe subscription/unsubscription

**Relevance:**
- ✅ **Essential for real-time trading** - Decouples event producers from consumers
- ✅ Enables reactive architecture (event-driven)
- ✅ Multiple services can react to same event (PnL updates, risk checks, logging)

**Implementation:**
```ruby
# Subscribe
Core::EventBus.instance.subscribe(:sl_hit) do |event|
  RiskManagerService.instance.handle_stop_loss(event)
end

# Publish
Core::EventBus.instance.publish(:sl_hit, { tracker_id: 123, price: 100.0 })
```

**Recommendations:**
- ✅ **Excellent implementation** - Thread-safe, well-designed
- Consider adding event filtering:
  ```ruby
  subscribe(:ltp, filter: ->(e) { e[:index_key] == 'NIFTY' })
  ```
- Add event replay capability for debugging

---

### 1.5 Factory Pattern ⚠️ **PARTIALLY IMPLEMENTED**

**Current Usage:**
- `PositionTracker.build_or_average!` - Factory method for position creation
- `Capital::Allocator.qty_for` - Factory-like quantity calculation
- No explicit factory classes

**Relevance:**
- ⚠️ **Could be improved** - Complex object creation scattered across codebase
- ✅ Current approach works but lacks centralization

**Current Implementation:**
```ruby
# EntryGuard creates trackers directly
def create_tracker!(instrument:, order_no:, pick:, side:, quantity:, index_cfg:, ltp:)
  watchable = find_watchable_for_pick(pick: pick, instrument: instrument)
  PositionTracker.build_or_average!(...)
end
```

**Recommendations:**
- 🔄 **Add explicit factory** for complex object creation:
  ```ruby
  module Factories
    class PositionTrackerFactory
      def self.create_paper_tracker(instrument:, pick:, side:, quantity:, ltp:)
        # Centralized paper tracker creation logic
      end
      
      def self.create_live_tracker(instrument:, order_no:, pick:, side:, quantity:, ltp:)
        # Centralized live tracker creation logic
      end
    end
  end
  ```
- Benefits:
  - Single responsibility
  - Easier testing
  - Consistent creation logic

---

### 1.6 Adapter Pattern ✅ **WELL IMPLEMENTED**

**Current Usage:**
- `Signal::StrategyAdapter` - Adapts strategy signals to engine format
- `Live::Gateway` - Adapter between `Orders::Gateway` interface and `Orders::Placer`

**Relevance:**
- ✅ **Essential for integration** - Bridges incompatible interfaces
- ✅ Enables strategy pluggability
- ✅ Abstracts external API differences

**Implementation:**
```ruby
# Signal::StrategyAdapter
def strategy_to_direction(strategy_signal)
  case strategy_signal[:type]
  when :ce then :bullish
  when :pe then :bearish
  else :avoid
  end
end
```

**Recommendations:**
- ✅ **Well-implemented** - Adapter pattern correctly used
- Consider adapter for external broker APIs (future-proofing)

---

### 1.7 Facade Pattern ✅ **IMPLICITLY USED**

**Current Usage:**
- `Orders::Manager` - Simplified interface for order placement
- `Entries::EntryGuard` - Facade for complex entry logic
- `Capital::Allocator` - Simplified capital allocation interface

**Relevance:**
- ✅ **Good for API simplification** - Hides complexity from callers
- ✅ Provides high-level operations

**Implementation:**
```ruby
# Orders::Manager (Facade)
class Manager
  def self.place_market_buy(segment:, security_id:, qty:, reason:, metadata: {})
    client_order_id = build_client_order_id(...)
    Orders::Placer.buy_market!(...)
  end
end
```

**Recommendations:**
- ✅ **Good pattern** - Facade simplifies complex operations
- Keep facades thin - delegate to services, don't contain business logic

---

### 1.8 Command Pattern ⚠️ **NOT EXPLICITLY USED**

**Current Usage:**
- Order placement is direct method calls
- No command objects for order operations

**Relevance:**
- ⚠️ **Could be beneficial** - Enables:
  - Order queuing
  - Undo/redo (for paper trading)
  - Order history/audit trail
  - Retry logic

**Recommendations:**
- 🔄 **Consider adding** for order operations:
  ```ruby
  module Orders
    class PlaceMarketOrderCommand
      attr_reader :side, :segment, :security_id, :qty, :metadata
      
      def initialize(side:, segment:, security_id:, qty:, metadata: {})
        @side = side
        @segment = segment
        @security_id = security_id
        @qty = qty
        @metadata = metadata
      end
      
      def execute
        Orders::Placer.buy_market!(...)
      end
      
      def undo
        # Cancel order if possible
      end
    end
  end
  ```
- Benefits:
  - Order queuing
  - Retry with exponential backoff
  - Audit trail
  - Testing isolation

---

### 1.9 State Pattern ⚠️ **PARTIALLY IMPLEMENTED**

**Current Usage:**
- `PositionTracker` has status field (`active`, `exited`, etc.)
- `Signal::StateTracker` - Tracks signal state
- No explicit state machine

**Relevance:**
- ⚠️ **Could be improved** - Position lifecycle has clear states
- ✅ Current approach works but could be more robust

**Recommendations:**
- 🔄 **Consider state machine** for position lifecycle:
  ```ruby
  # Using AASM gem or similar
  class PositionTracker < ApplicationRecord
    include AASM
    
    aasm column: :status do
      state :pending, initial: true
      state :active
      state :exited
      state :cancelled
      
      event :activate do
        transitions from: :pending, to: :active
      end
      
      event :exit do
        transitions from: :active, to: :exited
      end
    end
  end
  ```
- Benefits:
  - Prevents invalid state transitions
  - Clear state lifecycle
  - Easier debugging

---

### 1.10 Chain of Responsibility ⚠️ **PARTIALLY IMPLEMENTED**

**Current Usage:**
- `Entries::EntryGuard` - Multiple validation checks (chain-like)
- `Signal::Engine.comprehensive_validation` - Multiple validation checks

**Relevance:**
- ⚠️ **Could be formalized** - Validation logic is sequential but not explicit chain

**Current Implementation:**
```ruby
# EntryGuard (implicit chain)
def try_enter(...)
  return false unless session_check[:allowed]
  return false unless limit_check[:allowed]
  return false unless exposure_ok?(...)
  return false unless cooldown_active?(...)
  # ... more checks
end
```

**Recommendations:**
- 🔄 **Consider explicit chain** for validations:
  ```ruby
  module Entries
    class ValidationChain
      def initialize
        @validators = []
      end
      
      def add_validator(validator)
        @validators << validator
      end
      
      def validate(context)
        @validators.each do |validator|
          result = validator.validate(context)
          return result unless result[:valid]
        end
        { valid: true }
      end
    end
    
    class SessionValidator
      def validate(context)
        TradingSession::Service.entry_allowed? ? { valid: true } : { valid: false, reason: 'session' }
      end
    end
  end
  ```
- Benefits:
  - Easier to add/remove validators
  - Testable validators in isolation
  - Clear validation flow

---

## 2. Recommended Patterns for Trading Systems

### 2.1 Repository Pattern 🔄 **RECOMMENDED**

**Relevance:**
- ✅ **High value** - Abstracts data access
- ✅ Enables testing with in-memory repositories
- ✅ Centralizes query logic

**Where to Apply:**
- `PositionTracker` queries (currently scattered)
- `Instrument` queries
- `Derivative` queries

**Implementation:**
```ruby
module Repositories
  class PositionTrackerRepository
    def find_active_by_segment_and_security(segment:, security_id:)
      PositionTracker.active.where(segment: segment, security_id: security_id)
    end
    
    def find_by_order_no(order_no)
      PositionTracker.find_by(order_no: order_no)
    end
    
    def active_count_by_side(side:)
      PositionTracker.active.where(side: side).count
    end
  end
end
```

---

### 2.2 Decorator Pattern 🔄 **RECOMMENDED**

**Relevance:**
- ✅ **Useful for** - Adding features to existing objects without modification
- ✅ Example: Add logging/metrics to order placement

**Where to Apply:**
- Order placement (add logging/metrics)
- Strategy signals (add confidence scoring)
- Position tracking (add PnL calculation)

**Implementation:**
```ruby
module Orders
  class LoggingOrderDecorator
    def initialize(order_placer)
      @order_placer = order_placer
    end
    
    def buy_market!(...)
      Rails.logger.info("[Orders] Placing buy order: #{...}")
      result = @order_placer.buy_market!(...)
      Rails.logger.info("[Orders] Order placed: #{result.inspect}")
      result
    end
  end
end
```

---

### 2.3 Builder Pattern 🔄 **RECOMMENDED**

**Relevance:**
- ✅ **Useful for** - Complex object construction
- ✅ Example: Building bracket orders with multiple parameters

**Where to Apply:**
- Bracket order construction
- Position tracker creation
- Strategy configuration

**Implementation:**
```ruby
module Orders
  class BracketOrderBuilder
    def initialize(tracker)
      @tracker = tracker
      @sl_price = nil
      @tp_price = nil
      @trailing_config = nil
    end
    
    def with_stop_loss(price)
      @sl_price = price
      self
    end
    
    def with_take_profit(price)
      @tp_price = price
      self
    end
    
    def with_trailing(config)
      @trailing_config = config
      self
    end
    
    def build
      BracketPlacer.place_bracket(
        tracker: @tracker,
        sl_price: @sl_price,
        tp_price: @tp_price,
        trailing_config: @trailing_config
      )
    end
  end
end
```

---

### 2.4 Proxy Pattern 🔄 **RECOMMENDED**

**Relevance:**
- ✅ **Useful for** - Lazy loading, caching, access control
- ✅ Example: Proxy for external API calls with caching

**Where to Apply:**
- External API calls (DhanHQ) with caching
- Instrument data loading
- Market data fetching

**Implementation:**
```ruby
module Proxies
  class CachedMarketDataProxy
    def initialize(api_client)
      @api_client = api_client
      @cache = {}
    end
    
    def ltp(segment:, security_id:)
      cache_key = "#{segment}:#{security_id}"
      return @cache[cache_key] if @cache[cache_key] && fresh?(@cache[cache_key])
      
      result = @api_client.ltp(segment: segment, security_id: security_id)
      @cache[cache_key] = { value: result, timestamp: Time.current }
      result
    end
  end
end
```

---

### 2.5 Specification Pattern 🔄 **RECOMMENDED**

**Relevance:**
- ✅ **Useful for** - Complex business rules
- ✅ Example: Entry eligibility rules, exit conditions

**Where to Apply:**
- Entry validation rules
- Exit condition evaluation
- Risk checks

**Implementation:**
```ruby
module Specifications
  class EntryEligibilitySpecification
    def initialize(index_cfg:, pick:, direction:)
      @index_cfg = index_cfg
      @pick = pick
      @direction = direction
    end
    
    def satisfied?
      session_spec.satisfied? &&
        limit_spec.satisfied? &&
        exposure_spec.satisfied? &&
        cooldown_spec.satisfied?
    end
    
    private
    
    def session_spec
      TradingSessionSpecification.new
    end
    
    def limit_spec
      DailyLimitSpecification.new(index_key: @index_cfg[:key])
    end
    
    def exposure_spec
      ExposureSpecification.new(instrument: @pick[:instrument], side: @direction)
    end
    
    def cooldown_spec
      CooldownSpecification.new(symbol: @pick[:symbol], cooldown: @index_cfg[:cooldown_sec])
    end
  end
end
```

---

## 3. Pattern Usage by Domain

### 3.1 Signal Generation (`app/services/signal/`)
- ✅ **Strategy Pattern** - Multiple strategy implementations
- ✅ **Adapter Pattern** - Strategy adapter
- ✅ **Template Method** - Signal engine structure
- 🔄 **Chain of Responsibility** - Validation chain (recommended)

### 3.2 Order Management (`app/services/orders/`)
- ✅ **Template Method** - Gateway abstraction
- ✅ **Facade Pattern** - Orders::Manager
- 🔄 **Command Pattern** - Order commands (recommended)
- 🔄 **Builder Pattern** - Bracket order builder (recommended)

### 3.3 Risk Management (`app/services/risk/`)
- ✅ **Singleton Pattern** - Circuit breaker
- 🔄 **State Pattern** - Risk state machine (recommended)
- 🔄 **Specification Pattern** - Risk rules (recommended)

### 3.4 Capital Allocation (`app/services/capital/`)
- ✅ **Strategy Pattern** - Capital bands (implicit)
- ✅ **Facade Pattern** - Allocator interface
- 🔄 **Repository Pattern** - Balance repository (recommended)

### 3.5 Live Trading (`app/services/live/`)
- ✅ **Singleton Pattern** - Multiple services
- ✅ **Observer Pattern** - Event bus integration
- ✅ **Template Method** - Service lifecycle
- 🔄 **Proxy Pattern** - Cached API calls (recommended)

---

## 4. Anti-Patterns to Avoid

### 4.1 ❌ God Object
- **Current Risk:** `Signal::Engine` is large (730 lines)
- **Recommendation:** Extract validation, analysis, and strategy selection into separate classes

### 4.2 ❌ Feature Envy
- **Current Risk:** `EntryGuard` accesses multiple other objects
- **Recommendation:** Use facade or move logic closer to data

### 4.3 ❌ Primitive Obsession
- **Current Risk:** Using hashes for configuration (`index_cfg`, `pick`)
- **Recommendation:** Create value objects:
  ```ruby
  class IndexConfiguration
    attr_reader :key, :segment, :sid, :max_same_side
    
    def initialize(hash)
      @key = hash[:key]
      @segment = hash[:segment]
      # ...
    end
  end
  ```

### 4.4 ❌ Long Parameter Lists
- **Current Risk:** Methods with many parameters
- **Recommendation:** Use parameter objects or builder pattern

---

## 5. Summary & Recommendations

### ✅ Well-Implemented Patterns (Keep)
1. **Singleton Pattern** - Critical for trading systems
2. **Strategy Pattern** - Excellent for strategy switching
3. **Observer Pattern** - Well-designed event bus
4. **Template Method** - Good abstraction for gateways
5. **Adapter Pattern** - Properly bridges interfaces
6. **Facade Pattern** - Simplifies complex operations

### 🔄 Recommended Additions
1. **Factory Pattern** - Centralize object creation
2. **Command Pattern** - For order operations
3. **State Pattern** - For position lifecycle
4. **Repository Pattern** - Abstract data access
5. **Specification Pattern** - For business rules
6. **Builder Pattern** - For complex object construction

### ⚠️ Areas for Improvement
1. **Extract large classes** - `Signal::Engine` (730 lines)
2. **Add value objects** - Replace hash configurations
3. **Formalize validation chains** - Make explicit
4. **Add state machines** - For position lifecycle

---

## 6. Implementation Priority

### High Priority (Trading Safety)
1. **State Pattern** - Prevent invalid position transitions
2. **Command Pattern** - Order audit trail and retry
3. **Specification Pattern** - Clear business rules

### Medium Priority (Code Quality)
1. **Factory Pattern** - Centralize creation logic
2. **Repository Pattern** - Abstract data access
3. **Builder Pattern** - Complex object construction

### Low Priority (Nice to Have)
1. **Decorator Pattern** - Add features incrementally
2. **Proxy Pattern** - Caching layer
3. **Value Objects** - Type safety

---

## Conclusion

The codebase demonstrates **strong architectural patterns** appropriate for a trading system. The Singleton, Strategy, Observer, and Template Method patterns are well-implemented and critical for the system's operation.

**Key Strengths:**
- ✅ Thread-safe singletons for shared state
- ✅ Strategy pattern enables flexible trading strategies
- ✅ Event-driven architecture via Observer pattern
- ✅ Clean abstractions via Template Method

**Key Opportunities:**
- 🔄 Add explicit patterns for complex operations (Factory, Command, Builder)
- 🔄 Formalize state management (State Pattern)
- 🔄 Extract large classes for maintainability
- 🔄 Add value objects for type safety

The recommended patterns will improve **maintainability**, **testability**, and **safety** of the trading system without requiring major refactoring.
