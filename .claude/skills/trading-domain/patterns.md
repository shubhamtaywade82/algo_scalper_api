# Trading Domain Patterns (Ruby & Rails Implementation)

## 1. Broker Adapter

**Intent**: Encapsulate broker API differences behind a unified domain interface.  
**Rails Idiom**: `app/gateways/brokers/`

```ruby
# Shared Interface
module Domain
  module BrokerPort
    def place_order(order_params) # -> BrokerResponse
    def cancel_order(broker_order_id) # -> BrokerResponse
    def get_positions # -> [BrokerPosition]
    def get_order_status(broker_order_id) # -> BrokerOrderStatus
  end
end

# Implementation
class Gateways::Brokers::DhanGateway
  include Domain::BrokerPort

  def place_order(order_params)
    response = @client.post("/orders", body: transform(order_params))
    BrokerResponse.from_dhan(response)
  end

  private

  def transform(order_params)
    {
      dhanClientId: @config.client_id,
      transactionType: order_params.side.upcase,
      exchangeSegment: map_exchange(order_params.exchange),
      productType: "INTRADAY",
      orderType: map_order_type(order_params.type),
      securityId: order_params.instrument.broker_security_id,
      quantity: order_params.quantity,
      price: order_params.price_paise / 100.0
    }
  end
end
```

---

## 2. Order State Machine

**Intent**: Enforce valid transitions in the order lifecycle.  
**Rails Idiom**: `domain/orders/order_state.rb` (pure Ruby) or `AASM` on model.

```ruby
class Domain::Orders::OrderState
  TRANSITIONS = {
    created: [:validated, :rejected],
    validated: [:submitted, :rejected],
    submitted: [:acknowledged, :rejected],
    acknowledged: [:partially_filled, :filled, :cancelled],
    partially_filled: [:filled, :cancelled]
  }.freeze

  TERMINAL = [:filled, :cancelled, :rejected, :expired].freeze

  def initialize(current)
    @current = current.to_sym
  end

  def can_transition_to?(next_state)
    TRANSITIONS.fetch(@current, []).include?(next_state.to_sym)
  end

  def transition!(next_state)
    unless can_transition_to?(next_state)
      raise InvalidTransition, "#{@current} -> #{next_state}"
    end
    @current = next_state.to_sym
  end

  def terminal?
    TERMINAL.include?(@current)
  end
end
```

---

## 3. Risk Pipeline (Chain of Responsibility)

**Intent**: Evaluate multiple risk rules in sequence, stopping on first failure.  
**Rails Idiom**: `domain/risk/risk_engine.rb`

```ruby
class Domain::Risk::RiskEngine
  def initialize(rules:)
    @rules = rules # array of rule objects
  end

  def evaluate(signal, portfolio_state)
    @rules.each do |rule|
      result = rule.check(signal, portfolio_state)
      return RiskResult.reject(rule.name, result.reason) unless result.passed?
    end
    RiskResult.pass
  end
end
```

---

## 4. Signal Pipeline

**Intent**: Transform raw strategy output into a validated order.  
**Rails Idiom**: `services/strategies/evaluate_signal.rb`

```ruby
class Services::Strategies::EvaluateSignal
  def initialize(pipeline:)
    @pipeline = pipeline # array of stage objects
  end

  def call(signal)
    context = SignalContext.new(signal: signal)

    @pipeline.each do |stage|
      context = stage.call(context)
      return context.result if context.halted?
    end

    context.result
  end
end
```

---

## 5. Market Data Observer

**Intent**: Notify multiple decoupled subscribers about price ticks/candles.  
**Rails Idiom**: `ActiveSupport::Notifications`

```ruby
# Publisher
ActiveSupport::Notifications.publish(
  "tick.received",
  instrument_id: tick.instrument_id,
  price_paise: tick.price_paise,
  volume: tick.volume,
  timestamp: tick.timestamp
)

# Subscriber in config/initializers/events.rb
ActiveSupport::Notifications.subscribe("tick.received") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  StrategyRunner.evaluate(event.payload)
end
```

---

## 6. Position Reconciliation

**Intent**: Reconcile local position records against broker position API periodically.  
**Rails Idiom**: `jobs/position_reconciliation_job.rb` $\rightarrow$ `services/positions/reconcile.rb`

```ruby
class Services::Positions::Reconcile
  def initialize(broker_gateway:, position_repo:)
    @gateway = broker_gateway
    @repo = position_repo
  end

  def call
    broker_positions = @gateway.get_positions
    local_positions = @repo.open_positions

    broker_positions.each do |bp|
      local = local_positions.find { |lp| lp.instrument_id == bp.instrument_id }

      if local.nil?
        create_from_broker(bp)
      elsif local.quantity != bp.quantity
        correct_drift(local, bp)
      end
    end
  end
end
```
