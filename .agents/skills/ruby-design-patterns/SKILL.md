---
name: ruby-design-patterns
description: >
  Comprehensive Ruby Design Patterns reference combining Gang of Four (GoF) patterns,
  Refactoring.Guru Ruby implementations, Design Patterns for Humans intuitive concepts,
  and Rails-native idioms. Use when designing, reviewing, or refactoring Ruby code to evaluate
  pattern candidates, prevent over-engineering, write RSpec contract specs, or issue a NO_PATTERN verdict.
---

# Ruby Design Patterns — Complete Catalog & Decision Framework

This skill provides an authoritative, Ruby-idiomatic design pattern catalog. It integrates conceptual insights from **Design Patterns for Humans**, canonical Ruby structures from **Refactoring.Guru**, and **Rails-native idioms**.

> [!IMPORTANT]
> **Rule of Design Patterns**: Do NOT force a design pattern speculatively. Patterns exist to solve observed structural problems. If standard Ruby object composition or a plain PORO is sufficient, explicitly return `NO_PATTERN`.

---

## Pattern Decision Matrix

| Problem Signal | Candidate Pattern | Category | Rails Alternative First |
|---|---|---|---|
| Interchangeable algorithms selected dynamically via `case`/`if` | **Strategy** | Behavioral | PORO callable objects (`.call`) |
| Incompatible external API/gem interface | **Adapter** | Structural | Gateway / Client PORO |
| Request encapsulated as standalone executable operation | **Command** | Behavioral | Application Service Object / ActiveJob |
| Complex multi-component subsystem API | **Facade** | Structural | Domain Service / Subsystem Coordinator |
| Dynamic additional behavior without subclassing | **Decorator** | Structural | `SimpleDelegator` / Presenter / ViewComponent |
| Event notification / multi-subscriber decoupled events | **Observer** | Behavioral | `ActiveSupport::Notifications` / Domain Events |
| Behavior changes dynamically based on state | **State** | Behavioral | ActiveRecord Enums / State Objects / AASM |
| Subclassing decides concrete object construction | **Factory Method** | Creational | Class constructor method / Dependency injection |
| Sequential handler processing chain | **Chain of Responsibility** | Behavioral | Rack Middleware / Pipeline objects |
| Shared algorithm skeleton with customizable steps | **Template Method** | Behavioral | Modules / Class inheritance |

---

## Catalog by Category

### 1. Creational Patterns

#### Factory Method / Builder / Abstract Factory
- **Intent**: Decouple object construction from business logic.
- **Ruby Idiom**: Class-level constructors (`.build`, `.for_provider`). Avoid heavy Java-style abstract factory hierarchies unless creating multi-provider object families.
- **When NOT to use**: Object instantiation requires no complex setup or conditional logic.

```ruby
# Idiomatic Ruby Factory Method
class BrokerGateway
  def self.build(provider_name, config:)
    case provider_name.to_s.downcase
    when 'dhan'     then DhanAdapter.new(config)
    when 'zerodha'  then ZerodhaAdapter.new(config)
    else raise ArgumentError, "Unsupported broker: #{provider_name}"
    end
  end
end
```

---

### 2. Structural Patterns

#### Strategy Pattern
- **Intent**: Encapsulate interchangeable families of algorithms behind a common contract.
- **Ruby Idiom**: Standard POROs responding to `.call` or `.execute`.

```ruby
# Strategy Contract
class DhanExecutionStrategy
  def execute(order)
    # Dhan-specific order execution
  end
end

class ZerodhaExecutionStrategy
  def execute(order)
    # Zerodha-specific order execution
  end
end

# Context
class OrderExecutor
  def initialize(strategy:)
    @strategy = strategy
  end

  def execute(order)
    @strategy.execute(order)
  end
end
```

- **RSpec Verification Contract**:
```ruby
RSpec.describe OrderExecutor do
  subject(:executor) { described_class.new(strategy: strategy) }
  let(:strategy) { instance_double(DhanExecutionStrategy) }
  let(:order) { build(:order) }

  it "delegates execution to the configured strategy" do
    expect(strategy).to receive(:execute).with(order).and_return(true)
    expect(executor.execute(order)).to be true
  end
end
```

#### Adapter Pattern
- **Intent**: Map an incompatible third-party or external client API into your domain's expected interface.
- **Ruby Idiom**: Gateway objects wrapping external REST/gRPC/WebSocket APIs (e.g., `DhanGateway`, `StripeAdapter`).

```ruby
class DhanAdapter
  def initialize(client: DhanHQ::Client.new)
    @client = client
  end

  def place_order(order)
    response = @client.post_order(
      security_id: order.instrument_id,
      quantity: order.quantity,
      transaction_type: order.side.upcase
    )
    translate_response(response)
  end

  private

  def translate_response(raw)
    { status: raw['status'] == 'SUCCESS' ? :filled : :rejected, order_id: raw['orderId'] }
  end
end
```

#### Facade Pattern
- **Intent**: Provide a unified, simplified interface to a complex subsystem.
- **Ruby Idiom**: Domain Service / Application Coordinator unifying multiple low-level services.

```ruby
module Trading
  class ExecutionFacade
    def initialize(risk: RiskManager.new, broker: BrokerGateway.build(:dhan), notifier: Notifier.new)
      @risk = risk
      @broker = broker
      @notifier = notifier
    end

    def process(order)
      return false unless @risk.approve?(order)

      result = @broker.place_order(order)
      @notifier.notify(result) if result[:status] == :filled
      result
    end
  end
end
```

---

### 3. Behavioral Patterns

#### Command Pattern
- **Intent**: Encapsulate a request/action as a standalone executable object.
- **Ruby Idiom**: Service Objects / Use Case POROs with `.call`.

```ruby
module Orders
  class Place
    def self.call(params)
      new(params).call
    end

    def initialize(params)
      @params = params
    end

    def call
      order = Order.create!(@params)
      ExecutionJob.perform_later(order.id)
      order
    end
  end
end
```

#### Observer Pattern
- **Intent**: Notify subscribers when state changes occur.
- **Ruby Idiom**: `ActiveSupport::Notifications` or domain event dispatchers. Avoid custom observer loops.

```ruby
# ActiveSupport::Notifications (Rails Observer Idiom)
ActiveSupport::Notifications.instrument('order.placed', order_id: order.id) do
  # order placement logic
end

# Subscriber
ActiveSupport::Notifications.subscribe('order.placed') do |name, start, finish, id, payload|
  AuditLog.create!(event: name, payload: payload)
end
```

---

## When to Return `NO_PATTERN`

Return `NO_PATTERN` when:
1. The problem can be solved cleanly with a single standard method or private helper.
2. The logic has fewer than 3 conditional branches and is unlikely to grow.
3. The abstraction introduces extra files without reducing coupling or increasing testability.

```json
{
  "verdict": "NO_PATTERN",
  "reasoning": "Conditional logic is isolated to 2 branches and does not interact with external boundaries. Standard PORO composition is sufficient."
}
```
