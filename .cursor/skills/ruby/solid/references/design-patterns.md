# Design Patterns

All code examples in this document are Ruby.

## WARNING: Don't Force Patterns

> "Let patterns emerge from refactoring, don't force them upfront."

Patterns should solve problems you HAVE, not problems you MIGHT have.

## Creational

- **Factory** — Object creation varies by type; use a factory method or factory object.
- **Builder** — Complex object construction step by step (e.g. test data).
- **Singleton** — One instance (use sparingly; prefer dependency injection).

## Structural

- **Adapter** — Make incompatible interfaces work together (wrap a third-party or legacy API).
- **Decorator** — Add behavior without modifying existing code (wrapper objects or modules).
- **Composite** — Treat individual objects and compositions uniformly (e.g. tree of nodes).

## Behavioral

- **Strategy** — Family of algorithms, interchangeable (inject a strategy object or use duck typing).
- **Observer** — Notify multiple objects about state changes (pub/sub, callbacks, or `ActiveSupport::Notifications`).
- **Command** — Encapsulate a request as an object (undo/redo, job queues).

## Example: Strategy (Ruby duck typing)

```ruby
# Caller depends on objects that respond to calculate_cost
class StandardShipping
  def calculate_cost(order_value)
    order_value < 50 ? 5 : 0
  end
end
class ExpressShipping
  def calculate_cost(_order_value) = 15
end
class ShoppingCart
  def initialize(pricing_strategy)
    @pricing_strategy = pricing_strategy
  end
  def total(items)
    base = items.sum(&:price)
    @pricing_strategy.calculate_cost(base)
  end
end
```

## Anti-Patterns to Avoid

| Anti-Pattern           | Solution                      |
| ---------------------- | ----------------------------- |
| God Object             | Split by responsibility (SRP) |
| Golden Hammer          | Match pattern to problem      |
| Premature Optimization | YAGNI; profile first          |
