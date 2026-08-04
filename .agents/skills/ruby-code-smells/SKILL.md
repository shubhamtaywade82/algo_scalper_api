---
name: ruby-code-smells
description: >
  Ruby and Rails code smell classification catalog combining Refactoring.Guru smells,
  Reek metrics, and Rails-specific anti-patterns (Fat Controller, God Model, Callback Chain,
  N+1 Query, Job Bloat). Use during code review, static analysis, or refactoring planning.
---

# Ruby & Rails Code Smell Catalog

This skill provides an empirical classification of code smells in Ruby and Rails codebases, featuring deterministic detection metrics and clear remediation paths.

---

## 1. Generic Ruby Smells (Refactoring.Guru + Reek)

### Bloaters
- **Long Method**: Method exceeding 25–30 lines of code. Indicates lack of Single Responsibility.
  - *Remediation*: Extract Method, Decompose Conditional.
- **Large Class / God Class**: Class exceeding 200 LOC or touching > 8 instance variables.
  - *Remediation*: Extract Class, Extract Module/PORO.
- **Primitive Obsession**: Using raw strings/integers instead of small value objects (e.g., raw currency strings instead of `Money`).
  - *Remediation*: Replace Primitive with Object.
- **Long Parameter List**: Method taking > 3 arguments.
  - *Remediation*: Introduce Parameter Object, Preserved Options Hash.

### OO Abusers
- **Switch Statements / Repeated Conditional**: Large `case/when` or `if/elsif` chains inspecting types or flags.
  - *Remediation*: Replace Conditional with Polymorphism, Strategy Pattern.
- **Refused Bequest**: Subclass inheriting methods it doesn't need or overriding them to raise `NotImplementedError`.
  - *Remediation*: Replace Inheritance with Delegation.

### Change Preventers
- **Divergent Change**: A single class is modified in different ways every time a different feature changes.
  - *Remediation*: Extract Class along responsibility boundaries.
- **Shotgun Surgery**: A single feature change requires small modifications across many different files.
  - *Remediation*: Move Method, Move Field, Inline Class into unified domain object.

### Couplers
- **Feature Envy**: Method accesses another object's fields/methods more frequently than its own.
  - *Remediation*: Move Method to target class.
- **Message Chains**: Long call chains (`order.user.account.billing_address.city`).
  - *Remediation*: Hide Delegate (`delegate :city, to: :billing_address, allow_nil: true`).

---

## 2. Rails-Specific Smells

### Fat Controller
- **Signal**: Controller action exceeding 30 lines, performing direct SQL queries, transaction management, or external HTTP requests.
- **Risk**: Untested business logic, tight coupling to HTTP context.
- **Remediation**: Extract Command / Application Service Object (`Orders::PlaceService.call`).

### God Model & Callback Cascades
- **Signal**: Model file exceeding 250 LOC with multiple `after_save`/`after_commit` hooks triggering downstream jobs or mailers.
- **Risk**: Silent side effects during unit testing, transaction deadlocks.
- **Remediation**: Remove callbacks, publish domain events from Service Objects (`ActiveSupport::Notifications`).

### N+1 Database Queries
- **Signal**: Executing a query inside an `.each` loop without preloading associations (`orders.each { |o| o.instrument.name }`).
- **Risk**: Database query explosion (100 items = 101 SQL queries).
- **Remediation**: Use `.includes`, `.preload`, or `.eager_load`.

### Business Logic in View / Serializer
- **Signal**: ERB or Jbuilder templates running database queries or complex calculations.
- **Remediation**: Extract Presenter, Decorator, or ViewComponent.

---

## Deterministic Metrics Thresholds

| Smell | Threshold Metric | Automated Detector |
|---|---|---|
| Long Method | > 30 LOC in single `def` | `ruby_prism_ast_analyzer.rb` |
| Switch Statements | > 5 branches in single method | `ruby_prism_ast_analyzer.rb` |
| High Fan-Out | > 10 distinct constants referenced | `ruby_prism_ast_analyzer.rb` |
| Reek Smell | Any Reek warning with confidence ≥ 0.85 | `ruby_reek_smell_detector.rb` |
| Fat Controller | > 100 LOC in controller file | `ruby_reek_smell_detector.rb` |
