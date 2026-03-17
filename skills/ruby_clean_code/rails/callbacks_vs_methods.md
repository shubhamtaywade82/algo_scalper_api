---
name: callbacks_vs_methods
description: Know when to use ActiveRecord callbacks versus explicit service method calls
tags: [rails, callbacks, activerecord, side-effects]
applies_to: [models, services]
severity: major
---

## Goal

ActiveRecord callbacks (`before_save`, `after_create`, etc.) are appropriate
for **internal model consistency** — never for cross-model orchestration,
external calls, or business workflows.

## Callback Decision Matrix

| Action | Use callback? | Why |
|--------|--------------|-----|
| Set a default attribute on `self` | ✅ Yes | Internal model consistency |
| Normalize a field value (`.downcase`) | ✅ Yes | Pure transformation on `self` |
| Validate derived attributes | ✅ Yes | Data integrity |
| Send an email after create | ❌ No | Side effect — use service + job |
| Subscribe to WebSocket feed | ❌ No | External — use service |
| Update a related model | ❌ No | Orchestration — use service |
| Call an external API | ❌ No | I/O — use service + job |
| Publish to event bus | ❌ No | Cross-cutting — use service |
| Compute cache data | ⚠️ Maybe | Use `after_commit` with a job |

## Safe Callback Examples

```ruby
class PositionTracker < ApplicationRecord
  before_validation :normalize_side
  before_create     :generate_client_order_id
  after_initialize  :set_defaults

  private

  def normalize_side
    self.side = side.to_s.downcase
  end

  def generate_client_order_id
    self.client_order_id ||= SecureRandom.hex(8)
  end

  def set_defaults
    self.meta ||= {}
  end
end
```

## Dangerous Callback Anti-patterns

```ruby
# BAD — callback calls external service
class PositionTracker < ApplicationRecord
  after_create :subscribe_to_market_feed   # external I/O in callback!
  after_update :notify_risk_manager        # cross-service call!
  before_destroy :cancel_broker_orders     # broker API in callback!
end

# GOOD — explicit service orchestration
class Entries::EntryGuard
  def try_enter(...)
    tracker = PositionTracker.create!(attrs)
    Live::MarketFeedHub.instance.subscribe(tracker)   # explicit
    Live::RiskManagerService.instance.register(tracker) # explicit
    tracker
  end
end
```

## `after_commit` vs `after_save`

```ruby
# WRONG — after_save fires inside the transaction
# If the job runs before the transaction commits, the record won't exist yet
after_save :enqueue_notification_job

# CORRECT — after_commit fires after the transaction is committed
after_commit :enqueue_notification_job, on: :create
```

## Callback Hell Detection

Flag when:
- A model has more than 3 callbacks total
- A callback calls a method outside the model (`TelegramNotifier`, `Gateway`, etc.)
- A callback calls `update!` or `save!` on another model
- A `before_save` makes a network call
- Callbacks are chained and order-dependent (fragile)

## Agent Instructions

1. List all callbacks in the model.
2. For each callback, check whether the called method is pure (operates only
   on `self`) or has side effects (external calls, other model mutations).
3. Flag side-effecting callbacks and suggest moving to explicit service calls.
4. Check `after_save` vs `after_commit` — any job enqueue should be `after_commit`.
