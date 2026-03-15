---
name: repository_pattern
description: Apply the Repository pattern to decouple domain logic from ActiveRecord query details
tags: [patterns, repository, activerecord, architecture]
applies_to: [services, models]
severity: warning
---

## Goal

A Repository abstracts the data access layer, giving the domain model a
collection-like interface to retrieve and store aggregates without caring
about the underlying storage mechanism.

In a Rails context, this is a lightweight version of the full DDD Repository:
a **Query Object** with a standard interface.

## When to Apply

Apply when:
- The same complex query appears in 3+ places
- Business logic and query logic are mixed in the same method
- You want to test domain logic without hitting the database
- The query is complex enough to need its own test coverage

## Interface

```ruby
# A Repository exposes a collection-like query interface
class Repositories::PositionRepository
  def initialize(relation = PositionTracker.all)
    @relation = relation
  end

  # Primary query methods
  def active_for(index_key:)
    @relation.active.for_index(index_key).with_instrument
  end

  def find_by_order_no(order_no)
    @relation.find_by(order_no: order_no)
  end

  def opened_today_for(index_key:)
    @relation.opened_today.for_index(index_key)
  end

  def all_active
    @relation.active.includes(:instrument).order(created_at: :asc)
  end

  def count_active_for(index_key:)
    active_for(index_key: index_key).count
  end
end
```

## Usage in Services

```ruby
class Entries::EntryGuard
  def initialize(index_cfg:, position_repo: Repositories::PositionRepository.new)
    @index_cfg     = index_cfg
    @position_repo = position_repo
  end

  def already_positioned?
    @position_repo.count_active_for(index_key: @index_cfg[:key]) >= MAX_POSITIONS
  end
end

# In tests — inject a stub, no DB needed
EntryGuard.new(
  index_cfg: cfg,
  position_repo: instance_double(Repositories::PositionRepository, count_active_for: 0)
)
```

## Repository vs. Scope vs. Query Object

| Concept | Scope | Query Object | Repository |
|---------|-------|-------------|------------|
| Location | Model | `app/queries/` | `app/repositories/` |
| Chainable | Yes | Yes (returns relation) | Depends |
| Injected | No | Rarely | Yes |
| Interface | AR DSL | `.call` | collection methods |
| Test isolation | Needs DB | Needs DB | Can stub |

Use **scopes** for simple, always-composable single-condition filters.
Use **query objects** for complex parameterised queries.
Use **repositories** when you want full testability without DB.

## Agent Instructions

1. Find services that call `PositionTracker.where(...)` directly.
2. If the same query appears in 2+ services, propose a Repository method.
3. Show the Repository class with the extracted query methods.
4. Show the service updated to inject and use the Repository.
5. Show the test setup with an injected stub.
