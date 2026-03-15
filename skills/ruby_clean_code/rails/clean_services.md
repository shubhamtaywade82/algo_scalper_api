---
name: clean_services
description: Design service objects as focused, single-purpose workflow orchestrators
tags: [rails, services, orchestration, command]
applies_to: [services]
severity: major
---

## Goal

Service objects orchestrate workflows that span multiple domain objects,
external systems, or side effects. They are not a catch-all for "code that
doesn't fit in a model."

## When to Use a Service

| Use a service | Don't use a service |
|--------------|---------------------|
| Multi-step workflow | Wrapping a single model method |
| External API integration | Simple attribute transformation |
| Transaction spanning multiple models | Delegating directly to ActiveRecord |
| Complex business rules with side effects | Getter/formatter helpers |

## Service Design Rules

1. **Single public method: `call`.** Services are callable — `OrderService.call(params)`.
2. **Return a result object**, not a boolean or raw model.
3. **Inject dependencies** — gateway, notifier, allocator are collaborators, not
   hardcoded constants.
4. **No presentation logic** — services don't format output for JSON/HTML.
5. **Transactional boundaries** — wrap multi-model mutations in `ActiveRecord::Base.transaction`.
6. **Services are stateless across calls** — re-instantiate per invocation.

## Result Object Pattern

```ruby
class ServiceResult
  attr_reader :success, :payload, :error

  def initialize(success:, payload: nil, error: nil)
    @success = success
    @payload = payload
    @error   = error
    freeze
  end

  def success? = @success
  def failure? = !@success

  def self.ok(payload = nil)   = new(success: true,  payload: payload)
  def self.fail(error)         = new(success: false, error: error)
end
```

## Example: Clean Service

```ruby
class Entries::EntryGuard
  def initialize(index_cfg:, gateway: Orders.config.gateway, allocator: Capital::Allocator.new)
    @index_cfg = index_cfg
    @gateway   = gateway
    @allocator = allocator
  end

  def try_enter(signal, pick)
    return ServiceResult.fail('circuit_breaker_tripped') unless circuit_clear?
    return ServiceResult.fail('cooldown_active')         if cooldown_active?

    instrument = fetch_instrument or return ServiceResult.fail('instrument_not_found')
    ltp        = current_ltp(instrument) or return ServiceResult.fail('stale_price')
    qty        = @allocator.qty_for(instrument, ltp) or return ServiceResult.fail('sizing_failed')

    ActiveRecord::Base.transaction do
      response = @gateway.place_market(side: :buy, qty: qty, security_id: instrument.security_id)
      tracker  = PositionTracker.create!(build_tracker_attrs(instrument, response, ltp, qty))
      ServiceResult.ok(tracker)
    end
  rescue StandardError => e
    Rails.logger.error("[EntryGuard] #{e.class}: #{e.message}")
    ServiceResult.fail(e.message)
  end

  private

  def circuit_clear?
    !Risk::CircuitBreaker.instance.tripped?
  end
end
```

## Anti-patterns

### Trivial Service (don't do this)

```ruby
# Wraps a single method call — no reason to exist
class UserNameService
  def call(user)
    user.name
  end
end
```

### Procedural Service (extract into smaller collaborators)

```ruby
# Does too much — should decompose into sub-services
class MegaOrderService
  def call(params)
    validate_params(params)    # → validation service or model
    fetch_instrument(params)   # → repository / query object
    compute_sizing(params)     # → Capital::Allocator
    place_order(params)        # → Orders::Gateway
    notify_telegram(params)    # → notification job
    update_risk_cache(params)  # → risk service
  end
end
```

## Detection Rules

Flag a service when:
- It has more than one public method (besides `initialize`)
- It has no `call` method but has 5+ public methods doing different things
- It directly instantiates collaborators without injection
- It renders or formats output for HTTP responses
- `call` method is longer than 20 lines of meaningful code

## Agent Instructions

1. Check each service for a single `call` entry point.
2. Verify collaborators are injected (not hardcoded).
3. Check that `call` returns a consistent result object or the domain object.
4. Identify services that are actually multiple services concatenated together.
