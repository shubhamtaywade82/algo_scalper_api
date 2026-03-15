---
name: single_responsibility
description: Ensure each class and module has exactly one reason to change
tags: [ruby, srp, design, solid]
applies_to: [services, models, jobs]
severity: major
---

## Goal

Every class, module, and service has **one responsibility** — one reason to
change. A class that fetches data, validates it, transforms it, persists it,
and notifies on completion has five responsibilities and five reasons to break.

## Principles

1. **One actor, one responsibility.** Ask: "Who would request a change to this
   class?" If multiple stakeholders (risk team, ops team, UI team) would all
   cause changes, split it.
2. **The name reveals the boundary.** `SignalEngine` — not `SignalAndOrderEngine`.
   `PositionTracker` — not `PositionTrackerAndNotifier`.
3. **Collaborators over inheritance.** Two classes with injected collaborators
   beats one class trying to do both.
4. **Side effects belong in their own layer.** Pure computation, persistence,
   and notification are three different responsibilities.

## Detection Rules

Flag a class when:
- Class name contains `and`, `or`, `with`
- Class has both `private` methods for computation AND ActiveRecord calls
- Class initializer requires 5+ parameters covering unrelated concerns
- Class has methods from multiple abstraction levels (HTTP, domain, DB)
- A change to the notification format would require editing trading logic
- Tests require mocking 4+ collaborators for a single unit test

## Common SRP Violations in Trading Systems

### 1. Fat Service

```ruby
# Bad — one class does signal, sizing, ordering, and logging
class SignalExecutor
  def run
    signal = compute_signal      # indicator logic
    qty    = size_position(signal)  # capital logic
    place_order(qty, signal)     # broker logic
    log_to_db(signal, qty)       # persistence logic
    notify_telegram(signal)      # notification logic
  end
end
```

```ruby
# Good — each responsibility is a separate collaborator
class SignalExecutor
  def initialize(signal_engine:, capital_allocator:, order_gateway:, event_bus:)
    ...
  end

  def run
    signal = @signal_engine.run
    return unless signal.actionable?
    qty    = @capital_allocator.qty_for(signal)
    @order_gateway.place(signal, qty)
    @event_bus.publish(:signal_executed, signal)
  end
end
```

### 2. God Model

```ruby
# Bad
class PositionTracker < ApplicationRecord
  def calculate_pnl; end          # domain logic — OK
  def fetch_live_price; end       # external API — violation
  def send_exit_notification; end # notification — violation
  def update_risk_metrics; end    # risk service — violation
end
```

```ruby
# Good — model owns only domain state and behavior
class PositionTracker < ApplicationRecord
  def unrealized_pnl(current_price)
    (current_price - entry_price) * qty * direction_multiplier
  end

  def risk_pct(current_price)
    unrealized_pnl(current_price) / entry_value
  end
end
```

## Refactoring Guidance

1. List every method in the class.
2. Group them by the "actor who would request a change".
3. Extract each group into its own class.
4. Wire them together in the original class or a new orchestrator.

## Agent Instructions

1. For each class, list all public and private methods.
2. Group methods by responsibility (computation, IO, persistence, notification).
3. If more than one group exists, recommend class extraction.
4. Verify the class name matches its remaining responsibility after extraction.
