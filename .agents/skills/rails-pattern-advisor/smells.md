# Smell $\rightarrow$ Pattern Catalog (Trading & Rails Domain)

## 1. Smell: `case`/`if` branching on broker or provider type
- **Condition**: 4+ branches selecting behavior based on `:dhan`, `:zerodha`, `:upstox`, etc.
- **Threshold**: $< 3$ branches $\rightarrow$ **NO_PATTERN** (use plain `case`/`if`). $\ge 4$ branches and growing $\rightarrow$ **Strategy + Adapter**.
- **Pattern**: **Strategy** + **Adapter**
- **Rails Idiom**: Gateway class per broker in `app/gateways/brokers/` or `app/adapters/`, injected via initializer into service object.
- **Example**:
  ```ruby
  # Before
  case broker
  when :dhan     then DhanClient.new.place_order(...)
  when :zerodha  then ZerodhaClient.new.place(...)
  when :upstox   then UpstoxClient.new.submit(...)
  end

  # After
  # app/gateways/brokers/dhan_gateway.rb
  # app/services/orders/place_service.rb
  broker_gateway.place_order(order_params)
  ```

---

## 2. Smell: Order placement logic > 40 lines doing multi-step orchestration
- **Condition**: Single controller or model method handling validation, risk checks, API calls, DB saves, and notifications.
- **Threshold**: $< 20$ lines and unlikely to grow $\rightarrow$ **NO_PATTERN**. $\ge 40$ lines $\rightarrow$ **Command (Service Object)**.
- **Pattern**: **Command** (Application Service Object)
- **Rails Idiom**: `app/services/orders/place_service.rb` with a single public `.call` method returning a result struct.
- **Example**:
  ```ruby
  module Orders
    class PlaceService
      Result = Struct.new(:success?, :order_id, :errors, keyword_init: true)

      def self.call(params:, account_state:)
        new(params: params, account_state: account_state).call
      end
    end
  end
  ```

---

## 3. Smell: Risk & pre-trade checks scattered across multiple conditionals
- **Condition**: Risk rules (max loss, max drawdowns, margin check, tick age check) mixed directly inside placement code.
- **Threshold**: 1–2 simple guards $\rightarrow$ **NO_PATTERN** (use standard guard clauses). 3+ distinct risk rules $\rightarrow$ **Chain of Responsibility** / **Policy Objects**.
- **Pattern**: **Chain of Responsibility** / **Policy**
- **Rails Idiom**: `app/policies/orders/risk_policy.rb` or array of callable risk check objects (`[MaxLossCheck, MarginCheck].each(&:call)`).

---

## 4. Smell: Position state transitions guarded by `if status ==` across methods
- **Condition**: Position lifecycle (`pending` $\rightarrow$ `partially_filled` $\rightarrow$ `filled` $\rightarrow$ `closing` $\rightarrow$ `closed`) handled with manual string/symbol checks.
- **Threshold**: 2 states, 1 transition $\rightarrow$ **NO_PATTERN** (use ActiveRecord `enum`). Multi-state complex transitions $\rightarrow$ **State Machine** (`AASM` gem or explicit State Objects).
- **Pattern**: **State**
- **Rails Idiom**: ActiveRecord `enum status:` or `AASM` state machine.

---

## 5. Smell: Market data $\rightarrow$ Signal $\rightarrow$ Order $\rightarrow$ Audit Log tight coupling
- **Condition**: Direct synchronous method calls chaining from tick parser to audit logger, mailer, and Telegram bot.
- **Threshold**: 1 downstream action $\rightarrow$ **NO_PATTERN** (call directly or enqueue job). Multiple independent listeners $\rightarrow$ **Observer** (`ActiveSupport::Notifications`).
- **Pattern**: **Observer** / **Domain Events**
- **Rails Idiom**: `ActiveSupport::Notifications.instrument('order.placed', payload)` + subscriber in `config/initializers/events.rb`.

---

## 6. Smell: Complex view/serialization formatting logic in ERB or Jbuilder
- **Condition**: Templates calculating PnL percentages, status badge CSS classes, or price formatting.
- **Threshold**: 1 simple helper $\rightarrow$ **NO_PATTERN** (use view helper). Complex formatting $\rightarrow$ **Presenter / Decorator**.
- **Pattern**: **Decorator** / **Presenter**
- **Rails Idiom**: `SimpleDelegator` subclass in `app/presenters/order_presenter.rb` or `ViewComponent`.
