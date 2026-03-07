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

**Current:** Two live-related gateway implementations:

- `Orders::GatewayLive` — used by the initializer and RiskManagerService; implements
  `place_market`, `exit_market`, `wallet_snapshot`, `cancel_order`; wraps
  `Orders::Placer` and DhanHQ APIs.
- `Live::Gateway` — also subclasses `Orders::Gateway`, wraps `Orders::Placer`, provides
  `place_market`, `flat_position`, `position`, `cancel_order`, `wallet_snapshot`;
  not used by the initializer (see CHANGELOG for cancel_order parity).

**Pattern:** Adapter is already in use (both adapt DhanHQ/Placer to `Orders::Gateway`).
The duplication is the issue: two adapters for the same "live" path.

**Suggestion:**

- Prefer one live gateway implementation. If `Orders::GatewayLive` is the one in use
  (initializer + RiskManagerService), document or deprecate `Live::Gateway` and
  migrate any remaining callers to `Orders::GatewayLive`, then remove or fold
  `Live::Gateway` into it (e.g. move `position`/`flat_position` into GatewayLive if
  still needed).
- If both are intentionally different (e.g. one for risk-manager, one for another
  subsystem), document the distinction and which to use where.

**Benefit:** Single adapter for "live" orders; less confusion and duplicate code.

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

**Current:** Many services use `include Singleton` and are accessed via `.instance`
(e.g. `Live::MarketFeedHub.instance`, `Risk::CircuitBreaker.instance`,
`Live::RedisPnlCache.instance`). Callers are tightly coupled to the concrete
singleton.

**Pattern:** Prefer dependency injection for testability and explicit dependencies.
Singleton is still valid for process-wide single instances (e.g. caches, feed hub).

**Suggestion:**

- For new code, prefer injecting dependencies (gateway, cache, event_bus) via
  constructor or `build` methods so tests can inject doubles.
- For existing singletons, consider optional constructor args that default to
  `.instance`, e.g. `def initialize(gateway: Orders.config.gateway)` so production
  stays unchanged but tests can pass a stub.
- Document which singletons are "infrastructure" (Redis, feed hub) vs "domain"
  (gateway, notifier) — inject the latter where practical.

**Benefit:** Easier unit testing; dependencies are explicit; less hidden coupling.

---

## 7. Observer — EventBus

**Current:** `Core::EventBus` is a publish/subscribe observer. Per project docs it has
zero subscribers and subsystems communicate via direct method calls.

**Pattern:** Observer is already implemented; it is underused.

**Suggestion:**

- Where "broadcast then forget" or decoupling is useful (e.g. "position closed" or
  "exit triggered"), consider publishing on EventBus and letting subscribers
  (logging, metrics, notifications) react instead of the caller invoking them
  directly.
- Migrate incrementally: one event type and a few subscribers at a time; keep
  direct calls where synchronous behavior is required.

**Benefit:** Decoupling; easier to add new reactors (e.g. audit, analytics)
without touching the core flow.

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
