---
name: ruby-refactoring
description: >
  Ruby refactoring catalog derived from Refactoring.Guru. Provides step-by-step transformations
  (Extract Method, Move Method, Extract Class, Guard Clauses, Replace Conditional with Polymorphism)
  enforcing behavior preservation (behavior_before == behavior_after) and RSpec/RuboCop verification.
---

# Ruby & Rails Refactoring Catalog & Workflow

Refactoring is the process of restructuring existing code without changing its external behavior (`behavior_before == behavior_after`).

---

## 1. Primary Transformations

### Composing Methods

#### Extract Method
- **Problem**: Long, complex method body containing distinct sub-steps.
- **Transformation**: Turn a cohesive group of lines into a descriptive private helper method.

```ruby
# Before
def process_order(order)
  # calculate total
  total = order.items.sum(&:price)
  total -= order.discount if order.discount
  order.update!(total: total)
end

# After
def process_order(order)
  order.update!(total: calculate_total(order))
end

private

def calculate_total(order)
  total = order.items.sum(&:price)
  order.discount ? total - order.discount : total
end
```

---

### Simplifying Conditionals

#### Replace Conditional with Polymorphism (Strategy)
- **Problem**: `case/when` branch logic selecting behavior based on type or enum.
- **Transformation**: Extract each branch into a strategy object implementing a common interface.

```ruby
# Before
def broker_fee(broker)
  case broker
  when :dhan     then 20.0
  when :zerodha  then 20.0
  when :upstox   then 18.0
  end
end

# After
class DhanBroker
  def fee; 20.0; end
end

class UpstoxBroker
  def fee; 18.0; end
end
```

#### Guard Clauses
- **Problem**: Deeply nested `if/else` blocks making method flow unreadable.
- **Transformation**: Return early for invalid or edge-case conditions.

```ruby
# Before
def execute(order)
  if order.valid?
    if order.user.active?
      order.place!
    end
  end
end

# After
def execute(order)
  return unless order.valid?
  return unless order.user.active?

  order.place!
end
```

---

### Moving Features

#### Move Method / Move Field
- **Problem**: Method uses features of another class more than its own (Feature Envy).
- **Transformation**: Move the method to the target class and update call sites.

#### Extract Class
- **Problem**: One class is doing the work of two (God Class / Fat Model).
- **Transformation**: Move cohesive state and methods into a new PORO.

---

## 2. Refactoring Safety Workflow

> [!IMPORTANT]
> **Safety Guarantee**: Every refactoring step MUST preserve passing tests. Never perform refactoring and functional feature additions in the same commit.

```text
1. Ensure full test suite (RSpec) passes baseline.
2. Make one small micro-refactor (e.g. Extract Method).
3. Run RSpec spec for target component.
4. Run RuboCop on modified file.
5. If tests fail, IMMEDIATELY revert micro-refactor and re-evaluate.
6. Proceed to next micro-refactor only when green.
```
