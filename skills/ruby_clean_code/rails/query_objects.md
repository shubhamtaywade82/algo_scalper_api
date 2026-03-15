---
name: query_objects
description: Encapsulate complex ActiveRecord queries in dedicated query objects
tags: [rails, activerecord, queries, performance]
applies_to: [models, services]
severity: warning
---

## Goal

Move complex, multi-clause, or reusable ActiveRecord queries out of models and
controllers into **Query Objects** — plain Ruby objects that build and execute
a query, returning an ActiveRecord relation or array.

## When to Use a Query Object

- Query spans 3+ conditions or joins
- Query is reused across multiple controllers/services
- Query involves subqueries, CTEs, or raw SQL fragments
- Query parameters are dynamic (user-driven filters)
- Query needs its own test coverage independent of model tests

## Pattern

```ruby
class Queries::ActivePositionsQuery
  def initialize(relation = PositionTracker.all)
    @relation = relation
  end

  def call(index_key: nil, since: nil, limit: nil)
    scope = @relation
              .active
              .includes(:instrument)
              .order(created_at: :desc)

    scope = scope.for_index(index_key) if index_key
    scope = scope.where('created_at >= ?', since) if since
    scope = scope.limit(limit) if limit
    scope
  end
end

# Usage
positions = Queries::ActivePositionsQuery.new.call(index_key: 'NIFTY', limit: 10)
```

## Scopes vs Query Objects

| Use `scope` | Use Query Object |
|-------------|-----------------|
| Single condition | Multiple joined conditions |
| Always applied the same way | Parameterised/dynamic |
| Composable with other scopes | Requires its own test setup |
| Simple filter | Involves subqueries or raw SQL |

## Examples

### Bad — complex query in model

```ruby
class PositionTracker < ApplicationRecord
  def self.profitable_exits_for_report(user_id, from_date, to_date, min_pnl)
    joins(:instrument)
      .where(user_id: user_id, trade_state: 'exited')
      .where('exit_at BETWEEN ? AND ?', from_date, to_date)
      .where('exit_price - entry_price > ?', min_pnl)
      .order('exit_at DESC')
      .select('position_trackers.*, instruments.symbol_name')
  end
end
```

### Good — query object

```ruby
class Queries::ProfitableExitsQuery
  def initialize(relation = PositionTracker.all)
    @relation = relation
  end

  def call(user_id:, from_date:, to_date:, min_pnl: 0)
    @relation
      .joins(:instrument)
      .exited
      .where(user_id: user_id)
      .exited_between(from_date, to_date)
      .with_min_pnl(min_pnl)
      .with_instrument_name
      .order(exit_at: :desc)
  end
end

# Model keeps only simple, composable scopes
class PositionTracker < ApplicationRecord
  scope :exited, -> { where(trade_state: 'exited') }
  scope :exited_between, ->(from, to) { where('exit_at BETWEEN ? AND ?', from, to) }
  scope :with_min_pnl, ->(n) { where('exit_price - entry_price > ?', n) }
  scope :with_instrument_name, -> { joins(:instrument).select('position_trackers.*, instruments.symbol_name') }
end
```

## N+1 Detection

Always flag:
- `tracker.instrument.symbol_name` inside a loop without `includes(:instrument)`
- `position.pnl` computed in Ruby after loading all records without SQL aggregation
- Any `.count` called inside an `.each` block

## Agent Instructions

1. Find queries with 3+ conditions in models or controllers.
2. Find `includes`, `joins`, `where` chains repeated across the codebase.
3. Propose a `Queries::XxxQuery` class with `call` method and relation injection.
4. Identify N+1 patterns and suggest `includes`/`eager_load`/`preload`.
