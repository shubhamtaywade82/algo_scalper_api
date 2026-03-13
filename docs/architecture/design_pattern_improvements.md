# Design Pattern Improvements

Recommendations for applying design patterns from the ruby-design-patterns skill to
improve clarity, testability, and extensibility. Apply when you recognize the problem;
do not force patterns speculatively.

---

## 1. Chain of Responsibility — EntryGuard.try_enter

**Current:** `Entries::EntryGuard.try_enter` is a long method with sequential guard
clauses (circuit breaker → BOS contract → time regime → BANKNIFTY last week →
edge failure → daily limits → instrument lookup → exposure → cooldown → LTP fallback).
Each "return false unless" is effectively a handler; order is implicit and hard to test in isolation.

**Pattern:** Extract each guard into a handler that either blocks (return false) or calls
the next handler. The pipeline becomes explicit and each handler is unit-testable.

**Suggestion:**

- Introduce `Entries::EntryGuardPipeline` (or `EntryGuardChain`) that holds an ordered
  list of handler objects.
- Each handler implements `call(context) → :pass | :block(reason)`.
- Handlers: `CircuitBreakerHandler`, `BosContractHandler`, `TimeRegimeHandler`,
  `BankniftyLastWeekHandler`, `EdgeFailureHandler`, `DailyLimitsHandler`,
  `InstrumentLookupHandler`, `ExposureHandler`, `CooldownHandler`.
- `EntryGuard.try_enter` builds the chain once (or from config) and runs the request
  through it. Post-guard logic (sizing, gateway call, tracker creation) stays in
  EntryGuard or a dedicated "ExecutionStep" after the chain passes.

**Benefit:** Single responsibility per handler; easy to add/remove/reorder guards;
test each guard in isolation; pipeline order is explicit.

---

## 2. Factory for Gateway Selection

**Current:** Gateway creation is duplicated:

- `config/initializers/orders_gateway.rb`: `paper_enabled ? GatewayPaper.new : GatewayLive.new`
- `Live::RiskManagerService`: `@paper_mode ? Orders::GatewayPaper.new : Orders::GatewayLive.new`

**Pattern:** Centralize creation in one place (Factory Method or simple factory object)
so adding a new gateway type (e.g. backtest, another broker) does not require
search-and-replace.

**Suggestion:**

- Add `Orders::GatewayFactory` (or `Orders::Config.gateway_factory`) with a method
  like `build(paper_mode: nil)` that reads paper mode from argument or
  `AlgoConfig.fetch.dig(:paper_trading, :enabled)` and returns the appropriate
  `Orders::Gateway` instance.
- Initializer and RiskManagerService call the factory instead of inline conditionals.
- Optionally, make `Orders.config.gateway` the single source of truth and have
  RiskManagerService accept `gateway: Orders.config.gateway` by default so it
  does not construct its own.

**Benefit:** Single place to change gateway selection; easier to add new gateway types
or feature flags.

---

## 3. Adapter / Unify Live Gateway Abstractions

**Status:** Implemented. Live orders use **Orders::GatewayLive** only.

- `Orders::GatewayLive` is the single live implementation: used by the initializer and
  RiskManagerService; implements `place_market`, `exit_market`, `flat_position`,
  `position`, `wallet_snapshot`, `cancel_order`; wraps `Orders::Placer` and DhanHQ APIs.
- `Live::Gateway` is **deprecated**: it now delegates to `Orders::GatewayLive` and logs
  a deprecation warning. It remains for backward compatibility only and will be removed
  in a future release.
- No app code referenced `Live::Gateway` for routing; only docs and CHANGELOG mentioned it.

---

## 4. Strategy — Risk Rules (Already in Good Shape)

**Current:** `Risk::Rules::BaseRule` and concrete rules (StopLoss, TakeProfit, etc.)
are strategies; `RuleEngine` evaluates them in priority order and returns the first
non-skip result. `RuleFactory` builds the default engine.

**Pattern:** Strategy + optional Composite. No change required for current behavior.

**Optional:** If you later need AND/OR rule groups (e.g. "exit only if StopLoss AND
session end"), introduce a Composite rule that holds child rules and evaluates them
as a group (see Composite in structural patterns).

---

## 5. Template Method — Risk Manager Exit Enforcement

**Current:** The risk manager runner loop calls multiple `enforce_*` methods in
sequence. The order and set of steps are implicit in the loop body.

**Pattern:** Define a template method that encodes the enforcement skeleton and
overridable/hook steps so the order is explicit and new layers can be added by
adding a step.

**Suggestion:**

- In the runner (or a dedicated "EnforcementOrchestrator"), introduce something like:
  `run_enforcement_cycle` that calls in order: `enforce_circuit_breaker`,
  `enforce_daily_limits`, `enforce_exit_rules`, … (match current method names).
- Make each step a private method (or a small object) so the template is readable:
  "run step 1, step 2, step 3." New enforcement layers become new steps.

**Benefit:** Explicit sequence; easier to reason about and test the cycle; simpler
to add new enforcement layers.

---

## 6. Singleton vs Dependency Injection

**Status:** Applied incrementally. No blanket refactor.

- **New code:** Prefer constructor injection (e.g. `Orders::EntryManager`, `Orders::BracketPlacer` inject
  `event_bus:` and `active_cache:`; `RiskManagerService` uses `Orders.config.gateway` or
  `Orders::GatewayFactory.build`).
- **Existing singletons:** When touching a service, add optional constructor args that default to `.instance`
  so tests can inject doubles without changing production call sites.
- **Infrastructure vs domain:** Prefer injecting domain singletons (gateway, notifier, event_bus) over
  infrastructure (MarketFeedHub, RedisPnlCache); document which is which when adding new code.

---

## 7. Observer — EventBus

**Status:** In use incrementally. `Core::EventBus` has defined event types; `Orders::EntryManager` and
`Orders::BracketPlacer` publish `entry_filled`, `bracket_placed`, `bracket_modified`; `Positions::ActiveCache`
publishes `sl_hit`, `tp_hit`. Exit path: `Live::ExitEngine` publishes `exit_triggered` after an exit is
executed; a logging subscriber is registered in `config/initializers/event_bus_subscribers.rb`.

- Prefer publishing for "broadcast then forget" (e.g. position closed, exit triggered) so subscribers
  (logging, metrics, notifications) can react without the caller invoking them directly.
- Add new event types and subscribers incrementally; keep direct calls where synchronous behavior is required.

---

## 8. Facade — EntryGuard

**Current:** `Entries::EntryGuard` is already a facade: it hides instrument lookup,
limits, BOS gate, exposure, cooldown, sizing, gateway, and tracker creation behind
`try_enter`.

**Pattern:** Document it as the single entry-point facade for "attempt an entry."
Keep the single public entry (`try_enter`) and avoid adding more entry points that
bypass the guard pipeline.

**Suggestion:** In code or docs, state that EntryGuard is the facade for the entry
subsystem; all external callers should use `try_enter` (or the pipeline, once
extracted) and not bypass it.

---

## 9. Command — Order Placement (Optional)

**Current:** Order placement is done by calling `Orders.config.gateway.place_market(...)`
or `Orders::Placer.buy_market!` directly. There is no first-class "command" object.

**Pattern:** Command would encapsulate a placement request (side, segment, security_id,
qty, meta) and expose `execute` (and optionally `undo`/cancel). Useful for audit
trails, replay, or centralized logging/metrics.

**Suggestion:** Lower priority. If you add an audit log or replay system, introduce
something like `Orders::PlaceMarketCommand.new(...).execute` that wraps the gateway
call and records the command. Otherwise, current approach is acceptable.

---

## 10. Decorator — Gateway / Placer (Optional)

**Current:** Retries and logging are embedded in `Orders::GatewayLive` and
`Orders::Placer`.

**Pattern:** A decorator wrapping the gateway could add logging, metrics, or
retries without changing the core class. Ruby’s use of modules and `prepend` makes
decorators easy.

**Suggestion:** If you want to add cross-cutting behavior (e.g. request timing,
structured logs for every order), consider a `Orders::GatewayLoggingDecorator` or
`Orders::GatewayMetricsDecorator` that wraps `Orders::Gateway` and delegates
to the inner gateway after logging. Apply in the factory so production gets the
decorated instance.

---

## Summary Table

| Area              | Pattern                 | Priority | Action |
|-------------------|-------------------------|----------|--------|
| EntryGuard        | Chain of Responsibility | High     | Extract guard pipeline into handlers |
| Gateway selection | Factory                 | Medium   | Centralize in Orders::GatewayFactory |
| Live gateway      | Adapter (consolidate)   | Medium   | Unify or document Live:: vs Orders:: |
| Risk rules        | Strategy                | —        | Already good; optional Composite later |
| Risk manager      | Template Method         | Low      | Explicit enforcement cycle steps |
| Singletons        | DI where possible       | Medium   | Prefer inject in new code; optional args |
| EventBus          | Observer                | Low      | Use for more events where decoupling helps |
| EntryGuard        | Facade                  | —        | Document as facade; keep single entry |
| Order placement   | Command                 | Optional | Consider for audit/replay |
| Gateway           | Decorator               | Optional | Consider for logging/metrics |

Reference: `.cursor/skills/ruby-design-patterns` (SKILL.md, creational/structural/
behavioral pattern docs).
