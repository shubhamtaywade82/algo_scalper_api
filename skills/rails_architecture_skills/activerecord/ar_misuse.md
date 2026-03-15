---
name: ar_misuse
description: Detect and remediate common ActiveRecord misuse patterns that harm performance and correctness
tags: [rails, activerecord, performance, correctness]
applies_to: [models, services, controllers]
severity: [warning, major, critical]
---

## Goal

ActiveRecord is powerful but commonly misused in ways that cause N+1 queries,
memory blowup, incorrect counts, and silent data integrity violations.

## Misuse Pattern Catalogue

### 1. N+1 Queries (critical)

```ruby
# Bad — N+1: 1 query to load trackers + N queries for each instrument
trackers.each { |t| process(t.instrument) }

# Good — 2 queries total
trackers.includes(:instrument).each { |t| process(t.instrument) }

# For large datasets — preload for arrays, eager_load for WHERE on association
trackers.preload(:instrument)           # separate queries, no JOIN
trackers.eager_load(:instrument)        # LEFT OUTER JOIN, filterable
```

---

### 2. `count` vs `size` vs `length`

```ruby
# Bad — always fires a COUNT SQL even if records already loaded
trackers.count

# Good — uses loaded collection if available, COUNT otherwise
trackers.size

# Bad — loads all records into memory just to count
trackers.all.length

# Use count when: you explicitly want a SQL COUNT (no preloading)
# Use size when: you may or may not have a loaded collection
# Use length when: you have an Array (not AR relation)
```

---

### 3. Selecting All Columns When Only Some Needed

```ruby
# Bad — loads all 30 columns per row, all 10,000 rows
PositionTracker.active.each { |t| puts t.order_no }

# Good — only fetch needed columns
PositionTracker.active.pluck(:order_no)
# Or for a hash:
PositionTracker.active.select(:id, :order_no, :entry_price)
```

---

### 4. `find` vs `find_by` in Non-Guaranteed Contexts

```ruby
# Bad — raises ActiveRecord::RecordNotFound in background jobs, crashing the worker
tracker = PositionTracker.find(id)

# Good — returns nil, handle gracefully
tracker = PositionTracker.find_by(id: id)
return unless tracker
```

---

### 5. Instantiating Records for Existence Check

```ruby
# Bad — loads full AR objects just to check presence
if PositionTracker.where(order_no: order_no).any?

# Good — EXISTS query, no object instantiation
if PositionTracker.exists?(order_no: order_no)
```

---

### 6. `update_all` Without Scoping

```ruby
# Bad — accidentally updates ALL records if scope is wrong
PositionTracker.update_all(trade_state: 'exited')  # all positions!

# Good — explicit scope, verify before executing
PositionTracker.where(id: tracker_ids).update_all(trade_state: 'exited')
```

---

### 7. Calling ActiveRecord in Loops

```ruby
# Bad — one INSERT per iteration
signals.each do |signal|
  SignalLog.create!(signal_attrs(signal))
end

# Good — batch insert
SignalLog.insert_all(signals.map { |s| signal_attrs(s) })
```

---

### 8. Missing Database Transactions

```ruby
# Bad — if the second update fails, first is already committed
tracker.update!(trade_state: 'exited')
order.update!(status: 'filled')

# Good — atomic
ActiveRecord::Base.transaction do
  tracker.update!(trade_state: 'exited')
  order.update!(status: 'filled')
end
```

---

### 9. Optimistic vs Pessimistic Locking

In a multi-threaded trading daemon where two services might update the same
tracker simultaneously, use locking:

```ruby
# Optimistic — good for low-contention updates
class PositionTracker < ApplicationRecord
  # Add lock_version column in migration
end

tracker = PositionTracker.find(id)
tracker.update!(trade_state: 'exited')  # raises StaleObjectError if another thread updated

# Pessimistic — good for exit enforcement (only one exit attempt)
PositionTracker.transaction do
  tracker = PositionTracker.lock.find(id)  # SELECT FOR UPDATE
  return if tracker.exited?
  tracker.update!(trade_state: 'exited', exit_price: ltp)
end
```

---

### 10. `where` with String Interpolation (SQL Injection)

```ruby
# Critical — SQL injection
PositionTracker.where("symbol_name = '#{params[:symbol]}'")

# Good — parameterised
PositionTracker.where(symbol_name: params[:symbol])
# Or:
PositionTracker.where("symbol_name = ?", params[:symbol])
```

## Agent Instructions

1. Scan all loops (`.each`, `.map`) for association accesses without `includes`.
2. Check `find` calls outside of controllers (where records are expected to exist).
3. Find `create!` in loops — suggest `insert_all`.
4. Find multi-model mutations without `transaction`.
5. Find `where` with string interpolation — flag as critical.
6. In the trading daemon context, flag any missing pessimistic lock on exit-intent
   writes where two threads could race.
