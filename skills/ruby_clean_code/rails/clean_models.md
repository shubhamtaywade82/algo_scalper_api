---
name: clean_models
description: Maintain thin Rails models with domain logic, delegating orchestration to services
tags: [rails, models, activerecord, domain]
applies_to: [models]
severity: major
---

## Goal

Models own **domain state and behavior** — validations, scopes, associations,
and methods that operate on the model's own data. They do not orchestrate
workflows, call external APIs, or manage other models' lifecycles.

## What Belongs in a Model

| Belongs | Does Not Belong |
|---------|----------------|
| `validates` | HTTP/API calls |
| `scope` | Orchestration (`create_and_notify`) |
| `belongs_to`, `has_many` | Cross-model transactions |
| Domain predicates (`expired?`, `active?`) | Background job scheduling |
| Calculations on own data (`unrealized_pnl`) | Email/notification sending |
| State machine transitions | Complex query building (→ query objects) |
| Simple computed attributes | Webhook/external integration |

## Rules

1. **Scopes over class methods** for query building (scopes are composable).
2. **No `before_save` / `after_create`** that call external services — use
   service objects triggered from controllers/jobs.
3. **No `update_all` in callbacks** — silent mass-update bugs are catastrophic
   in a trading system.
4. **Validations are domain rules**, not persistence rules. Keep them.
5. **Concerns for shared behaviour** — use `ActiveSupport::Concern` to share
   logic across models, not STI.

## Examples

### Good model

```ruby
class PositionTracker < ApplicationRecord
  belongs_to :instrument
  belongs_to :user

  # Scopes — composable, lazy
  scope :active,  -> { where(trade_state: 'active') }
  scope :for_index, ->(key) { joins(:instrument).where(instruments: { symbol_name: key }) }
  scope :opened_today, -> { where('created_at >= ?', Time.zone.today.beginning_of_day) }

  # Validations — domain rules
  validates :entry_price, numericality: { greater_than: 0 }
  validates :qty, numericality: { greater_than: 0, only_integer: true }
  validates :side, inclusion: { in: %w[long_ce long_pe] }

  # Domain predicates
  def active?   = trade_state == 'active'
  def exited?   = trade_state == 'exited'
  def long_ce?  = side == 'long_ce'

  # Calculations on own data
  def entry_value
    entry_price * qty
  end

  def unrealized_pnl(current_price)
    direction_multiplier = long_ce? ? 1 : -1
    (current_price - entry_price) * qty * direction_multiplier
  end

  def risk_pct(current_price)
    return 0 if entry_value.zero?
    unrealized_pnl(current_price) / entry_value
  end
end
```

### Bad model — doing too much

```ruby
class PositionTracker < ApplicationRecord
  after_create :subscribe_to_feed        # side effect — belongs in service
  after_update :notify_telegram          # notification — belongs in job
  before_destroy :cancel_pending_orders  # orchestration — belongs in service

  def close!(exit_price)
    update!(trade_state: 'exited', exit_price: exit_price)
    Orders::GatewayLive.new.place_exit(self)   # broker call — violation
    TelegramNotifier.send_exit_message(self)    # notification — violation
    MarketFeedHub.unsubscribe(security_id)      # WebSocket — violation
  end
end
```

## Detection Rules

Flag in a model when:
- `require 'net/http'` or any HTTP library
- `after_create`/`after_save` calls a non-model method
- A method makes an external API call
- A method creates/updates other models (should be in a service)
- Business logic is duplicated from controllers/services

## Agent Instructions

1. List all methods. Flag any that call external services, send notifications,
   or orchestrate multiple records.
2. Check callbacks — any `after_*`/`before_*` that does more than set an
   attribute on `self` should be moved to a service.
3. Check scopes — named scopes should be preferred over class methods for
   chainable queries.
4. Confirm `frozen_string_literal: true` is present.
