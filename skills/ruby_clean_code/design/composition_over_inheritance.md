---
name: composition_over_inheritance
description: Prefer composing collaborators over deep inheritance hierarchies
tags: [ruby, composition, inheritance, design, solid]
applies_to: [services, strategies, models]
severity: warning
---

## Goal

Favour **composition** (injecting collaborators) over **inheritance**
(`class Child < Parent`) except where inheritance models a true IS-A
relationship. Composition produces more flexible, testable code.

## When Inheritance Is Appropriate

- True IS-A relationship with Liskov Substitution: `GatewayPaper < GatewayBase`
- ActiveRecord models: `Order < ApplicationRecord`
- Shared interface enforcement via abstract base class

## When to Prefer Composition

- Sharing behaviour across unrelated classes
- A subclass overrides more than 2 methods from the parent
- The base class would need to know about the subclass's specific behaviour
- You need to "mix in" different behaviours at runtime

## Patterns

### 1. Module mixins for shared behaviour

```ruby
# Bad — inheritance for shared behaviour
class BaseStrategy
  def calculate_adx; end
  def calculate_rsi; end
end

class SupertrendStrategy < BaseStrategy
  # only uses calculate_adx, drags in everything else
end

# Good — mixin only what's needed
module Indicators
  module Adx
    def adx(period: 14)
      candle_series.adx(period)
    end
  end

  module Rsi
    def rsi(period: 14)
      candle_series.rsi(period)
    end
  end
end

class SupertrendStrategy
  include Indicators::Adx

  def signal
    adx > 25 ? :trend : :ranging
  end
end
```

### 2. Injected collaborators

```ruby
# Bad — hardcoded dependency
class EntryGuard
  def initialize(index_cfg)
    @gateway = Orders::GatewayLive.new  # untestable, inflexible
    @allocator = Capital::Allocator.new
  end
end

# Good — injected dependencies
class EntryGuard
  def initialize(index_cfg:, gateway:, allocator:)
    @index_cfg = index_cfg
    @gateway   = gateway
    @allocator = allocator
  end
end

# In production
EntryGuard.new(
  index_cfg: cfg,
  gateway:   Orders.config.gateway,
  allocator: Capital::Allocator.new(account)
)

# In tests
EntryGuard.new(
  index_cfg: cfg,
  gateway:   instance_double(Orders::GatewayPaper),
  allocator: instance_double(Capital::Allocator)
)
```

### 3. Strategy pattern for interchangeable algorithms

```ruby
# Instead of subclasses for each strategy variant
class SignalEngine
  def initialize(strategy:)
    @strategy = strategy
  end

  def run(candles)
    @strategy.call(candles)
  end
end

SupertrendStrategy = ->(candles) { ... }
MultiIndicatorStrategy = ->(candles) { ... }

engine = SignalEngine.new(strategy: SupertrendStrategy)
```

## Detection Rules

Flag when:
- A class inherits from a non-Rails base class and overrides >2 methods
- A base class calls `raise NotImplementedError` in more than 3 methods
- Subclasses add `attr_reader` for attributes the parent never uses
- A class inherits just to get `initialize` or `call` delegation

## Agent Instructions

1. Identify inheritance relationships in the file.
2. Check whether each `< Parent` is a true IS-A or a has-A/uses-A.
3. For has-A relationships, propose converting to composition with injected
   collaborators.
4. Preserve Rails inheritance (`< ApplicationRecord`, `< ApplicationJob`).
