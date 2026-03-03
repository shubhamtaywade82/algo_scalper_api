# Software Architecture

All code examples in this document are Ruby.

## The Goal of Architecture

Enable the team to add, change, remove, test, and deploy features with minimal friction.

## Vertical Boundaries (Features/Slices)

Organize by **feature**, not only by technical layer.

```
# BAD: Layer-first only
app/
  controllers/
  services/
  models/

# GOOD: Feature-first where it helps
app/
  orders/
    order_controller.rb
    order_service.rb
    order_repository.rb
  users/
    ...
```

## The Dependency Rule

**Dependencies point INWARD.** Domain does not depend on infrastructure.

```
Infrastructure → Application → Domain
     (outer)        (middle)     (inner)
```

- Domain (entities, value objects, domain services) has no Rails/DB/HTTP.
- Application (use cases, orchestration) depends on domain; infrastructure depends on application.
- Inject dependencies (repositories, mailers, gateways) so domain and application stay decoupled.

## Contracts (Duck Types / Interfaces)

In Ruby, use duck typing and small modules. High-level code depends on "objects that respond to :save, :find_by_id", not on `ActiveRecord::Base`.

```ruby
# Application depends on abstraction
class CreateOrder
  def initialize(order_repository:, notifier:)
    @order_repository = order_repository
    @notifier = notifier
  end
  def call(params)
    order = Order.new(params)
    @order_repository.save(order)
    @notifier.order_created(order)
    order
  end
end
# Inject PostgresOrderRepository or InMemoryOrderRepository in tests
```

## Red Flags

- Domain (or core logic) depending on Rails, DB, or HTTP
- No clear boundaries between features
- Shared mutable state across modules
