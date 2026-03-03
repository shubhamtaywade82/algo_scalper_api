# Code Smells & Anti-Patterns

All code examples in this document are Ruby.

## What Are Code Smells?

Indicators that something MAY be wrong. Not bugs, but design problems that make code hard to understand, change, or test.

## Key Smells and Refactorings

| Smell                      | Symptom                                      | Refactoring                                       |
| -------------------------- | -------------------------------------------- | ------------------------------------------------- |
| **Long Method**            | > 10 lines                                   | Extract Method                                    |
| **Large Class**            | > 50 lines, multiple responsibilities        | Extract Class                                     |
| **Long Parameter List**    | > 3 parameters                               | Introduce Parameter Object                        |
| **Data Clumps**            | Same group of variables appear together      | Extract Class                                     |
| **Primitive Obsession**    | Primitives instead of small objects          | Wrap in Value Object                              |
| **Switch/case on type**    | Large case/if on type                        | Replace with Polymorphism (duck typing, strategy) |
| **Feature Envy**           | Method uses another class's data extensively | Move Method                                       |
| **Speculative Generality** | "Just in case" code                          | Delete (YAGNI)                                    |

## Example: Long Method → Extract Method

```ruby
# SMELL
def process_order(order)
  raise 'Empty' if order.items.empty?
  raise 'No customer' unless order.customer
  total = order.items.sum { |i| i.price * i.quantity - (i.discount || 0) }
  total *= (1 + tax_rate(order.customer.state))
  db.insert_order(order, total)
  email_service.send(order.customer.email, 'Order confirmed')
end

# REFACTORED
def process_order(order)
  validate_order(order)
  total = calculate_total(order)
  save_order(order, total)
  notify_customer(order)
end
```

## Example: Primitive Obsession → Value Objects

```ruby
# SMELL
def create_user(email, age)
  raise unless email.include?('@')
  raise if age < 0
end

# REFACTORED
class Email
  def initialize(value)
    raise InvalidEmail unless value.match?(/\A[^@]+@[^@]+\z/)
    @value = value.freeze
  end
  attr_reader :value
end
def create_user(email:, age:)
  # Type and validation in value objects
end
```

## Prevention

- Follow object calisthenics
- Practice TDD
- Refactor continuously
- Apply SOLID
