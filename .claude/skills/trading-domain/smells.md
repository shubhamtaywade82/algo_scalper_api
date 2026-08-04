# Trading Domain Code Smells Catalog

## 1. Broker Leakage
- **Detection**: `domain/` or `services/` references a specific broker name (`Dhan`, `Zerodha`, `Upstox`) or broker-specific payload fields.
- **Threshold**: ANY occurrence outside `gateways/` is a violation.
- **Fix**: Extract to gateway, inject via interface (`BrokerPort`).
- **Pattern**: Adapter + Dependency Inversion.

## 2. Risk Bypass
- **Detection**: Order created without passing through `RiskEngine`.
- **Threshold**: ANY path creating an Order without risk evaluation.
- **Fix**: Make `RiskEngine` a required dependency of `PlaceOrder` service.
- **Pattern**: Chain of Responsibility (risk gates before execution).

## 3. Scattered State Transitions
- **Detection**: Order/Position state changed in multiple locations via direct attribute assignment (`order.status = "filled"`).
- **Threshold**: $> 1$ location changing state.
- **Fix**: Centralize in state machine, make state read-only externally.
- **Pattern**: State (`OrderState` object or `AASM`).

## 4. Strategy-Infrastructure Coupling
- **Detection**: Strategy file requires/uses ActiveRecord, Redis, HTTP, or gateway classes.
- **Threshold**: ANY occurrence in `strategies/`.
- **Fix**: Strategy receives plain value objects, emits `Signal`. Nothing else.
- **Pattern**: Dependency Inversion + Clean Boundary.

## 5. Synchronous Execution Assumption
- **Detection**: Code assuming broker fill response is immediate (places order, then immediately reads fill status).
- **Threshold**: ANY synchronous fill assumption.
- **Fix**: Submit $\rightarrow$ persist as `PENDING` $\rightarrow$ handle async callback/webhook.
- **Pattern**: Command + Async State Machine + Webhook Handler.

## 6. Position Calculation Duplication
- **Detection**: PnL/margin/quantity math in multiple files.
- **Threshold**: Same formula in $> 1$ file.
- **Fix**: Single `PositionCalculator` in `domain/`, used everywhere.
- **Pattern**: Single Responsibility (DRY).

## 7. Market Data in Request Cycle
- **Detection**: Controller or service fetches live market data synchronously during HTTP request.
- **Threshold**: ANY live data fetch in request path.
- **Fix**: Cache latest tick in Redis, read from cache. Or use ActionCable feed.
- **Pattern**: Cache-Aside + Async Feed.

## 8. Missing Idempotency
- **Detection**: Webhook/callback handler creating records without checking duplicates (`broker_order_id` not unique-checked).
- **Threshold**: ANY create without idempotency guard.
- **Fix**: Unique index on `broker_order_id` + `find_or_create_by`.
- **Pattern**: Idempotent Consumer.

## 9. Float Money
- **Detection**: Price, PnL, or margin stored or calculated as `Float`.
- **Threshold**: ANY float usage for currency.
- **Fix**: Integer paise (`price_paise = 185450`).
- **Pattern**: Value Object (`Money` type).

## 10. God Strategy
- **Detection**: Strategy file $> 150$ LOC, or strategy handling entry + exit + position sizing + risk + notification.
- **Threshold**: $> 150$ LOC or $> 2$ responsibilities.
- **Fix**: Strategy emits raw signal. Sizing/risk/notification are separate pipeline stages.
- **Pattern**: Chain of Responsibility (Signal Pipeline).
