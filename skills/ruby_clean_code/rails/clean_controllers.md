---
name: clean_controllers
description: Keep controllers as thin orchestration layers — receive, authorize, delegate, respond
tags: [rails, controllers, thin, orchestration]
applies_to: [controllers]
severity: major
---

## Goal

A controller action should do exactly four things:

1. **Receive** the request and extract parameters
2. **Authorize** the caller
3. **Delegate** to a domain service or model
4. **Respond** with the result

No business logic. No conditional branching on domain state. No DB queries
beyond what's needed to look up the domain object.

## Ideal Controller Action

```ruby
# The "four-liner" pattern
def create
  result = CreateOrderService.call(order_params, current_user)
  render json: result.to_h, status: result.status_code
end
```

## Rules

1. **No `if/elsif` chains** on business domain values (status, regime, side).
2. **No ActiveRecord queries in action body** — delegate to service or model scope.
3. **No calculations** — `total = qty * price` does not belong here.
4. **Permit params explicitly** — use strong parameters, never pass `params` directly.
5. **One `render`/`redirect_to` per action** — use early returns with `return`.
6. **Error handling via rescue or service result** — not bare `begin/rescue`.

## Examples

### Bad

```ruby
def create
  if params[:order][:side] == 'buy'
    instrument = Instrument.find_by(symbol: params[:symbol])
    if instrument
      price = instrument.last_price
      qty = (params[:capital].to_f / price).floor
      if qty > 0
        order = Order.create!(
          instrument: instrument,
          qty: qty,
          side: 'buy',
          price: price
        )
        TelegramNotifier.notify("Order placed: #{order.id}")
        render json: { success: true, order_id: order.id }
      else
        render json: { error: 'Insufficient capital' }, status: 422
      end
    else
      render json: { error: 'Instrument not found' }, status: 404
    end
  end
end
```

### Good

```ruby
def create
  result = Orders::CreateService.call(order_params, current_user: current_user)

  if result.success?
    render json: { order_id: result.order_id }, status: :created
  else
    render json: { error: result.error }, status: result.http_status
  end
end

private

def order_params
  params.require(:order).permit(:symbol, :side, :capital)
end
```

## API Controller Pattern (this codebase)

```ruby
module Api
  class CircuitBreakerController < ApplicationController
    before_action :authenticate_request

    def show
      render json: Risk::CircuitBreaker.instance.status
    end

    def create
      Risk::CircuitBreaker.instance.trip!(reason: params[:reason])
      render json: { tripped: true }
    end

    def destroy
      Risk::CircuitBreaker.instance.reset!
      render json: { reset: true }
    end
  end
end
```

## Detection Rules

Flag in a controller when:
- Action body exceeds 10 lines
- `if`/`elsif` branches on a domain value (`status`, `side`, `regime`)
- Direct ActiveRecord `find`, `create!`, `update!` in action body
- Mathematical calculation in action body
- `puts`, `Rails.logger` calls without delegation to a service
- External API call inside action body

## Agent Instructions

1. For each action, check whether it does more than: receive, authorize, delegate, respond.
2. Extract domain logic to a service class named `[Verb][Noun]Service` or `[Verb][Noun]Command`.
3. Keep the controller test thin — it should only test routing and HTTP status codes.
