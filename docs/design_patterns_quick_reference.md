# Design Patterns Quick Reference

## Pattern Cheat Sheet

### ✅ Currently Used (Well-Implemented)

| Pattern | Location | Purpose | Status |
|---------|----------|---------|--------|
| **Singleton** | `Core::EventBus`, `Risk::CircuitBreaker`, `Live::*` services | Single instance for shared state | ✅ Excellent |
| **Strategy** | `Signal::StrategyAdapter`, Strategy classes | Pluggable trading strategies | ✅ Excellent |
| **Template Method** | `TradingSystem::BaseService`, `Orders::Gateway` | Abstract lifecycle/interface | ✅ Good |
| **Observer** | `Core::EventBus` | Event-driven architecture | ✅ Excellent |
| **Adapter** | `Signal::StrategyAdapter`, `Live::Gateway` | Interface bridging | ✅ Good |
| **Facade** | `Orders::Manager`, `Entries::EntryGuard` | Simplified interfaces | ✅ Good |

### 🔄 Recommended Additions

| Pattern | Use Case | Priority | Benefit |
|---------|----------|----------|---------|
| **Factory** | Position tracker creation | Medium | Centralized creation |
| **Command** | Order operations | High | Audit trail, retry |
| **State** | Position lifecycle | High | Prevent invalid transitions |
| **Repository** | Data access | Medium | Testability, abstraction |
| **Specification** | Business rules | High | Clear, testable rules |
| **Builder** | Complex objects | Medium | Fluent API |
| **Decorator** | Feature addition | Low | Incremental features |
| **Proxy** | Caching layer | Low | Performance |

---

## Pattern Decision Tree

### When to Use Which Pattern?

```
Need single instance for shared state?
├─ Yes → Singleton ✅
└─ No → Continue

Need to switch algorithms at runtime?
├─ Yes → Strategy ✅
└─ No → Continue

Need to define skeleton with steps?
├─ Yes → Template Method ✅
└─ No → Continue

Need to notify multiple objects of events?
├─ Yes → Observer ✅
└─ No → Continue

Need to bridge incompatible interfaces?
├─ Yes → Adapter ✅
└─ No → Continue

Need to simplify complex subsystem?
├─ Yes → Facade ✅
└─ No → Continue

Need to create complex objects?
├─ Yes → Factory or Builder 🔄
└─ No → Continue

Need to encapsulate operations?
├─ Yes → Command 🔄
└─ No → Continue

Need to manage object state transitions?
├─ Yes → State 🔄
└─ No → Continue

Need to abstract data access?
├─ Yes → Repository 🔄
└─ No → Continue

Need to express business rules?
├─ Yes → Specification 🔄
└─ No → Continue
```

---

## Pattern Examples by Domain

### Signal Generation
```ruby
# Strategy Pattern
strategy = SimpleMomentumStrategy.new(series: series)
signal = strategy.generate_signal(index)

# Adapter Pattern
direction = StrategyAdapter.strategy_to_direction(signal)
```

### Order Management
```ruby
# Template Method
gateway = Live::Gateway.new
gateway.place_market(side: 'buy', ...)

# Facade Pattern
Orders::Manager.place_market_buy(...)
```

### Risk Management
```ruby
# Singleton Pattern
Risk::CircuitBreaker.instance.tripped?

# Observer Pattern
Core::EventBus.instance.publish(:risk_alert, { ... })
```

### Capital Allocation
```ruby
# Facade Pattern
quantity = Capital::Allocator.qty_for(
  index_cfg: index_cfg,
  entry_price: ltp,
  derivative_lot_size: lot_size
)
```

---

## Quick Implementation Templates

### Singleton Template
```ruby
require 'singleton'

class MyService
  include Singleton
  
  def initialize
    @state = {}
    @lock = Mutex.new
  end
  
  def do_something
    @lock.synchronize do
      # Thread-safe operation
    end
  end
end

# Usage
MyService.instance.do_something
```

### Strategy Template
```ruby
class BaseStrategy
  def generate_signal(index)
    raise NotImplementedError
  end
end

class MomentumStrategy < BaseStrategy
  def generate_signal(index)
    # Implementation
  end
end

# Usage
strategy = MomentumStrategy.new(series: series)
signal = strategy.generate_signal(index)
```

### Observer Template
```ruby
# Subscribe
Core::EventBus.instance.subscribe(:event_type) do |event|
  handle_event(event)
end

# Publish
Core::EventBus.instance.publish(:event_type, { data: 'value' })
```

### Factory Template
```ruby
module Factories
  class PositionTrackerFactory
    def self.create_paper_tracker(**args)
      PositionTracker.create!(**args, paper: true)
    end
    
    def self.create_live_tracker(**args)
      PositionTracker.create!(**args, paper: false)
    end
  end
end
```

### Command Template
```ruby
class PlaceOrderCommand
  attr_reader :side, :segment, :security_id, :qty
  
  def initialize(side:, segment:, security_id:, qty:)
    @side = side
    @segment = segment
    @security_id = security_id
    @qty = qty
  end
  
  def execute
    Orders::Placer.buy_market!(...)
  end
  
  def undo
    # Cancel order
  end
end
```

### State Template
```ruby
class PositionTracker < ApplicationRecord
  include AASM
  
  aasm column: :status do
    state :pending, initial: true
    state :active
    state :exited
    
    event :activate do
      transitions from: :pending, to: :active
    end
    
    event :exit do
      transitions from: :active, to: :exited
    end
  end
end
```

---

## Pattern Benefits Matrix

| Pattern | Maintainability | Testability | Flexibility | Performance |
|---------|----------------|-------------|-------------|-------------|
| Singleton | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| Strategy | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| Observer | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| Factory | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ |
| Command | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| State | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| Repository | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ |
| Specification | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |

---

## Anti-Patterns to Avoid

| Anti-Pattern | Example | Fix |
|-------------|---------|-----|
| God Object | `Signal::Engine` (730 lines) | Extract into smaller classes |
| Feature Envy | `EntryGuard` accessing many objects | Move logic closer to data |
| Primitive Obsession | Hash configurations | Use value objects |
| Long Parameter Lists | Methods with 10+ params | Use parameter objects |

---

## References

- Full analysis: `docs/design_patterns_analysis.md`
- Gang of Four patterns: https://en.wikipedia.org/wiki/Design_Patterns
- Ruby-specific patterns: https://refactoring.guru/design-patterns/ruby
