# SOLID Principles

All code examples in this document are Ruby.

## Overview

SOLID helps structure software to be flexible, maintainable, and testable. These principles reduce coupling and increase cohesion.

## S - Single Responsibility Principle (SRP)

> "A class should have one, and only one, reason to change."

### Problem It Solves
God objects that do everything - hard to test, hard to change, hard to understand.

### How to Apply
Each class handles ONE responsibility. If you find yourself saying "and" when describing what a class does, split it.

```ruby
# BAD: Multiple responsibilities
class Order
  def calculate_total; end
  def save_to_database; end   # Persistence
  def generate_invoice; end   # Presentation
end

# GOOD: Single responsibility each
class Order
  def initialize
    @items = []
  end
  def add_item(item); end
  def calculate_total; end
end

class OrderRepository
  def save(order); end
end

class InvoiceGenerator
  def generate(order); end
end
```

### Detection Questions
- Does this class have multiple reasons to change?
- Can I describe it without using "and"?
- Would different stakeholders request changes to different parts?

---

## O - Open/Closed Principle (OCP)

> "Software entities should be open for extension but closed for modification."

### How to Apply
Design abstractions that allow new behavior through new classes (or modules), not edits to existing ones.

```ruby
# BAD: Must modify to add new shipping
class ShippingCalculator
  def calculate(type, value)
    case type
    when 'standard' then value < 50 ? 5 : 0
    when 'express' then 15
    # Must add more when for new types!
    end
  end
end

# GOOD: Open for extension (duck typing or module)
# Caller depends on objects that respond to calculate_cost
class StandardShipping
  def calculate_cost(order_value)
    order_value < 50 ? 5 : 0
  end
end

class ExpressShipping
  def calculate_cost(order_value)
    15
  end
end

class SameDayShipping
  def calculate_cost(order_value)
    25
  end
end
```

### Architectural Insight
OCP at architecture level: **new features = new code, not changes to existing code.**

---

## L - Liskov Substitution Principle (LSP)

> "Subtypes must be substitutable for their base types without altering program correctness."

### How to Apply
Subclasses must honor the contract of the parent. Don't strengthen preconditions or weaken postconditions.

```ruby
# BAD: Subclass breaks expectations
class DiscountPolicy
  def get_discount(value) = 0  # Non-negative expected
end
class WeirdDiscount < DiscountPolicy
  def get_discount(value) = -5  # Increases cost! Breaks expectations
end

# GOOD: Enforces contract
class DiscountPolicy
  def initialize(discount)
    raise ArgumentError, "Discount must be non-negative" if discount < 0
    @discount = discount
  end
  def get_discount = @discount
end
```

### Key Insight
You can swap `InMemoryUserRepo` for `PostgresUserRepo` because they both honor the same contract (duck type or interface).

---

## I - Interface Segregation Principle (ISP)

> "Clients should not be forced to depend on methods they do not use."

### How to Apply (Ruby: small roles, not fat interfaces)
In Ruby we use duck typing and small modules. Don't force classes to implement methods they don't need.

```ruby
# BAD: Fat role - printer forced to implement scan and package
module WarehouseDevice
  def print_label(order_id); end
  def scan_barcode; end
  def package_item(order_id); end
end
class BasicPrinter
  include WarehouseDevice
  def scan_barcode
    raise "Not supported"  # Forced!
  end
  def package_item(_) = raise "Not supported"
end

# GOOD: Small roles - depend only on what you need
module LabelPrinter
  def print_label(order_id); end
end
module BarcodeScanner
  def scan_barcode; end
end
class BasicPrinter
  include LabelPrinter
  # Only what it does
end
```

### Detection
If you see `raise "Not implemented"` or empty method bodies, the role/interface is too fat.

---

## D - Dependency Inversion Principle (DIP)

> "High-level modules should not depend on low-level modules. Both should depend on abstractions."

### How to Apply
Depend on duck types or inject dependencies. Don't instantiate concrete classes in business logic.

```ruby
# BAD: Direct dependency on concrete class
class OrderService
  def initialize
    @email_service = SendGridEmailService.new  # Locked in!
  end
  def confirm_order(email)
    @email_service.send(email, "Order confirmed")
  end
end

# GOOD: Depend on abstraction (inject dependency)
class OrderService
  def initialize(email_service:)
    @email_service = email_service  # Any object that responds to :send
  end
  def confirm_order(email)
    @email_service.send(email, "Order confirmed")
  end
end

# Inject any implementation
OrderService.new(email_service: SendGridEmailService.new)
OrderService.new(email_service: SESEmailService.new)
OrderService.new(email_service: double(send: true))  # Tests
```

### The Dependency Rule
Dependencies point **inward**: Infrastructure → Application → Domain. Domain does not depend on infrastructure.

---

## Quick Reference

| Principle | One-Liner                  | Red Flag                              |
| --------- | -------------------------- | ------------------------------------- |
| SRP       | One reason to change       | "This class handles X and Y and Z"    |
| OCP       | Add, don't modify          | `case`/`if` chains for types          |
| LSP       | Subtypes are substitutable | Type-checking in calling code         |
| ISP       | Small, focused roles       | Empty/raise in method implementations |
| DIP       | Depend on abstractions     | `SomeClass.new` in business logic     |
