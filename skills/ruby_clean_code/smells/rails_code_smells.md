---
name: rails_code_smells
description: Detect Rails-specific anti-patterns that harm maintainability and performance
tags: [rails, smells, activerecord, performance]
applies_to: [models, controllers, services, jobs]
severity: [warning, major, critical]
---

## Goal

Rails has specific anti-patterns beyond general Ruby smells that arise from
misusing the framework — fat models, callback hell, N+1 queries, and putting
business logic in the wrong layer.

## Rails Smell Catalogue

### 1. Fat Model (major)

**Symptom:** Model file exceeds 300 lines; contains external API calls,
notification logic, complex business orchestration.

**Refactor:** Extract orchestration to services; keep only domain behavior.

---

### 2. Fat Controller (major)

**Symptom:** Action method exceeds 15 lines; contains business logic,
direct ActiveRecord queries, or calculations.

**Refactor:** Move to service objects; controllers: receive → authorize → delegate → respond.

---

### 3. N+1 Query (critical)

**Symptom:** Iterating a collection and calling an association on each element
without eager loading.

```ruby
# Bad — N+1: one query per tracker
trackers.each { |t| puts t.instrument.symbol_name }

# Good — 2 queries total
trackers.includes(:instrument).each { |t| puts t.instrument.symbol_name }
```

**Detection:** Any `.each` or `.map` loop on a collection that calls `.association`
inside it without `includes`.

---

### 4. Callback Hell (major)

**Symptom:** Model has 5+ callbacks; callbacks call external services or
update other models; tests fail in unexpected order due to callbacks firing.

**Refactor:** Move external calls to explicit service methods (see `callbacks_vs_methods.md`).

---

### 5. Finder in Controller (major)

**Symptom:** Complex `where` clause directly in controller action.

```ruby
# Bad
def index
  @positions = PositionTracker.where(trade_state: 'active')
                               .where('created_at > ?', 1.day.ago)
                               .includes(:instrument)
                               .order(created_at: :desc)
end

# Good
def index
  @positions = Queries::ActivePositionsQuery.new.call(since: 1.day.ago)
end
```

---

### 6. Missing Scope (warning)

**Symptom:** Repeated `where(trade_state: 'active')` across codebase instead
of a named scope.

**Refactor:** Add `scope :active, -> { where(trade_state: 'active') }`.

---

### 7. Business Logic in View/Presenter (major)

**Symptom:** Conditional rendering logic based on domain state in ERB templates
or JSON serialisers.

```erb
<%# Bad — business logic in view %>
<% if order.status == 'active' && order.qty > 0 && !order.expired? %>
```

**Refactor:** Add a predicate method to the model; presenters/decorators for
display-only logic.

---

### 8. `update_column` / `update_columns` Overuse (warning)

**Symptom:** Using `update_column`/`update_columns` (skips validations and
callbacks) in normal business flows.

**When it's acceptable:** Performance-critical hot paths in trading systems
where callbacks should not fire (e.g., updating `meta` JSON on every tick).
**Must be explicitly documented with a comment.**

---

### 9. `find` Without Rescue in Hot Paths (major)

**Symptom:** `Model.find(id)` in a tick handler or job without rescue —
raises `ActiveRecord::RecordNotFound` and crashes the worker.

```ruby
# Bad
tracker = PositionTracker.find(tracker_id)  # raises if not found

# Good
tracker = PositionTracker.find_by(id: tracker_id)
return unless tracker
```

---

### 10. Ignoring `created_at` Index (warning)

**Symptom:** Queries like `where('created_at >= ?', date)` on a table with
millions of rows and no index on `created_at`.

**Refactor:** Ensure `add_index :table, :created_at` in migrations.

---

### 11. String-Based Association (warning)

**Symptom:** `has_many :instruments, class_name: 'SomeModule::Instrument'` where
constant lookup could be used instead, causing autoload issues.

---

### 12. `serialize` Without Type (major)

**Symptom:** `serialize :meta` without specifying type — stores inconsistent
Ruby objects in the column.

```ruby
# Good
serialize :meta, type: Hash, coder: JSON
# Or use jsonb column type (PostgreSQL)
```

## Agent Instructions

For each smell detected:

```
file: path/to/file.rb
line: LINE_NUMBER
severity: warning|major|critical
smell: SMELL_NAME
comment: Specific explanation in context
suggestion: Exact refactoring step
```

For N+1 violations, always show the `includes` fix alongside the detection.
