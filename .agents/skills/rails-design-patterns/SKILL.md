---
name: rails-design-patterns
description: >
  Framework-native Rails architectural patterns (Service Objects, Commands, Adapters, Facades,
  Presenters, ActiveSupport Observers, State Machines, Policy Objects, Middleware/Pipelines).
  Use when designing or refactoring Ruby on Rails applications to align with Rails idioms,
  decouple controllers/models, and choose appropriate Rails-native abstractions.
---

# Rails Architectural Patterns — Framework-Native Guide

This skill maps classic architectural and design patterns directly into **Ruby on Rails conventions**.

---

## Architectural Component Mapping

| Architectural Concern | Anti-Pattern / Smell | Recommended Rails Pattern |
|---|---|---|
| Controller orchestrating multi-step workflow | Fat Controller | **Command / Service Object** (`app/services/`) |
| External API/SDK integration (Dhan, Stripe, OpenAI) | Direct SDK calls in Model/Controller | **Adapter / Gateway** (`app/gateways/` or `lib/`) |
| Model containing > 200 lines of complex business rules | God Model | **Domain Service / Form Object / Policy** |
| Complex view formatting/serialization logic | Complex helpers / SQL in ERB | **Presenter / Decorator / ViewComponent** |
| Cross-cutting side effects on save/commit | Callback hell (`after_save` cascades) | **ActiveSupport::Notifications / Domain Events** |
| Lifecycle state transitions (`pending -> filled -> cancelled`) | Complex `if/else` checks on status column | **ActiveRecord Enum / State Machine Object** |
| Complex database multi-table insertion & validation | Controller transaction block | **Form Object / Use Case Service** |
| Multi-stage data processing pipeline | Long procedural script | **Pipeline / Rack Middleware** |

---

## Core Rails Pattern Specifications

### 1. Command / Application Service (`app/services/`)
- **Use Case**: Encapsulate business logic operations that cross multiple models or call external services.
- **Convention**: Single public `.call` method, returning a result object or domain model.

```ruby
# app/services/orders/place_service.rb
module Orders
  class PlaceService
    Result = Struct.new(:success?, :order, :errors, keyword_init: true)

    def self.call(user:, params:)
      new(user: user, params: params).call
    end

    def initialize(user:, params:)
      @user = user
      @params = params
    end

    def call
      order = @user.orders.build(@params)
      unless order.valid?
        return Result.new(success?: false, order: order, errors: order.errors.full_messages)
      end

      ActiveRecord::Base.transaction do
        order.save!
        OrderExecutionJob.perform_later(order.id)
      end

      Result.new(success?: true, order: order, errors: [])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, order: order, errors: [e.message])
    end
  end
end
```

---

### 2. External Adapter / Gateway (`app/gateways/`)
- **Use Case**: Shield domain models from third-party client SDK changes and external API structures.

```ruby
# app/gateways/dhan_gateway.rb
class DhanGateway
  class Error < StandardError; end

  def initialize(client: DhanHQ::Client.new)
    @client = client
  end

  def place_order(order)
    payload = {
      dhanClientId: ENV.fetch('DHAN_CLIENT_ID'),
      transactionType: order.side.upcase,
      exchangeSegment: 'NSE_FNO',
      productType: 'INTRADAY',
      orderType: 'MARKET',
      quantity: order.quantity,
      securityId: order.instrument.dhan_security_id
    }

    response = @client.place_order(payload)
    parse_response(response)
  rescue StandardError => e
    raise Error, "Dhan API failure: #{e.message}"
  end

  private

  def parse_response(res)
    {
      broker_order_id: res['orderId'],
      status: res['orderStatus'].to_s.downcase.to_sym
    }
  end
end
```

---

### 3. Presenter / Decorator Pattern
- **Use Case**: Extract view-specific formatting and presentation logic from Active Record models.
- **Convention**: Use `SimpleDelegator` or `ViewComponent`.

```ruby
# app/presenters/order_presenter.rb
class OrderPresenter < SimpleDelegator
  def status_badge_class
    case status
    when 'filled'    then 'badge-success'
    when 'rejected'  then 'badge-danger'
    when 'pending'   then 'badge-warning'
    else 'badge-secondary'
    end
  end

  def formatted_amount
    "₹#{'%.2f' % total_amount}"
  end
end
```

---

### 4. Event Observer / Decoupled Callbacks
- **Use Case**: Replace dangerous Active Record callbacks (`after_save`, `after_commit`) that trigger side-effects like external API calls or emails.

```ruby
# Preferred: Trigger event from Service Object
module Orders
  class Complete
    def self.call(order)
      order.update!(status: :completed)
      ActiveSupport::Notifications.instrument('order.completed', order_id: order.id)
    end
  end
end

# Subscriber (config/initializers/events.rb)
ActiveSupport::Notifications.subscribe('order.completed') do |_name, _start, _finish, _id, payload|
  AuditLogJob.perform_later(payload[:order_id])
  NotificationMailer.order_summary(payload[:order_id]).deliver_later
end
```

---

## Anti-Pattern Rules for Rails

> [!WARNING]
> **Avoid Speculative Layers**:
> 1. Do NOT create Repository objects over Active Record models unless supporting multiple datastores. Active Record IS already a Gateway + Data Mapper.
> 2. Do NOT create abstract base classes or Java-style interfaces for every service object.
> 3. Do NOT put API HTTP requests inside Active Record model callbacks or SQL transactions.
