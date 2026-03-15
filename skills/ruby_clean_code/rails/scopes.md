---
name: scopes
description: Use named scopes to build composable, self-documenting query interfaces on models
tags: [rails, activerecord, scopes, queries]
applies_to: [models]
severity: warning
---

## Goal

Named scopes make queries **readable**, **composable**, and **testable**. They
are the model's public query interface — the vocabulary callers use to ask for
subsets of data without knowing the underlying SQL.

## Scope Rules

1. **Scope names are domain language**, not SQL language.
   - `active` not `where_trade_state_active`
   - `opened_today` not `created_at_gte_today`
2. **Scopes return relations**, not arrays. Never call `.to_a` inside a scope.
3. **Lambda scopes for parameters** — always use `-> { }` to defer evaluation
   (otherwise `Time.current` is evaluated at class load time, not call time).
4. **Short scopes, simple conditions** — complex logic → query object.
5. **Compose scopes** in query objects, never chain 5+ scopes in application code.

## Examples

```ruby
class PositionTracker < ApplicationRecord
  # State scopes
  scope :active,    -> { where(trade_state: 'active') }
  scope :exited,    -> { where(trade_state: 'exited') }
  scope :pending,   -> { where(trade_state: %w[init validated]) }

  # Time scopes — MUST use lambda to avoid stale time at class load
  scope :opened_today,    -> { where('created_at >= ?', Time.zone.today.beginning_of_day) }
  scope :opened_this_week, -> { where('created_at >= ?', Time.zone.now.beginning_of_week) }

  # Domain scopes
  scope :for_index,  ->(key) { joins(:instrument).where(instruments: { symbol_name: key }) }
  scope :calls,      -> { where(side: 'long_ce') }
  scope :puts,       -> { where(side: 'long_pe') }
  scope :profitable, -> { where('exit_price > entry_price') }

  # Association loading scopes
  scope :with_instrument, -> { includes(:instrument) }
  scope :with_details,    -> { includes(:instrument, :user) }
end

# Composable usage
PositionTracker.active.for_index('NIFTY').with_instrument.opened_today
```

## Detection Rules

Flag when:
- A non-lambda scope uses `Time.current`, `Date.today`, or `Time.now` — these
  will be evaluated once at class load time, becoming stale
- A scope body contains `.to_a`, `.count`, or `.pluck` — breaks composability
- A scope body contains `if`/`unless` — use a query object instead
- Inline `where` with 3+ conditions in a controller or service (→ scope or query object)

## Stale Scope Anti-pattern (common bug)

```ruby
# BAD — Time.current evaluated ONCE at class load, never changes
scope :recent, where('created_at > ?', Time.current - 1.hour)

# GOOD — evaluated on each call
scope :recent, -> { where('created_at > ?', 1.hour.ago) }
```

## Agent Instructions

1. Scan all `scope` definitions for missing lambda syntax.
2. Find repeated `where` clauses in services/controllers that should be scopes.
3. Check scope names against domain vocabulary (flag SQL-sounding names).
4. Verify no scope calls `.to_a`, `.count`, or other terminating methods.
