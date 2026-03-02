# Object-Oriented Design

All code examples in this document are Ruby.

## Responsibility-Driven Design (RDD)

**Objects are defined by their responsibilities, not their data.**

### Object Stereotypes

| Stereotype             | Purpose                      | Example                           |
| ---------------------- | ---------------------------- | --------------------------------- |
| **Information Holder** | Holds data, minimal behavior | `User`, `Product`, `Address`      |
| **Structurer**         | Maintains relationships      | `OrderItems`, collection objects  |
| **Service Provider**   | Performs work                | `PaymentProcessor`, `EmailSender` |
| **Coordinator**        | Orchestrates workflow        | `OrderFulfillmentService`         |
| **Controller**         | Makes decisions, delegates   | `CheckoutController`              |
| **Interfacer**         | Transforms between systems   | API adapters, serializers         |

### The Two Questions

For every class:
1. **What pattern is this?** — Which stereotype?
2. **Is it doing too much?** — Check object calisthenics (small methods, few ivars).

## Tell, Don't Ask

Command objects to do work. Don't interrogate and do the work yourself.

```ruby
# BAD: Asking, then doing
if account.balance >= amount
  account.balance -= amount
end

# GOOD: Telling
result = account.withdraw(amount)
```

## Composition Over Inheritance

Prefer composing objects over extending classes. Use small modules for shared behavior; inject strategies.

```ruby
# BAD: Inheritance for behavior variation
class PremiumUser < User
  def discount; 20; end
end

# GOOD: Composition
class User
  def initialize(discount_policy:)
    @discount_policy = discount_policy
  end
  def discount
    @discount_policy.amount
  end
end
User.new(discount_policy: PremiumDiscount.new)
```

## Law of Demeter

Only talk to immediate friends. One dot per line.

```ruby
# BAD
order.customer.address.city

# GOOD
order.shipping_city
```

## Value Objects vs Entities

- **Value Objects** — Defined by attributes, immutable (e.g. `Money`, `Email`, `Address`). Use for domain primitives.
- **Entities** — Have identity; mutable via methods (e.g. `User`, `Order`). Compare by id.
