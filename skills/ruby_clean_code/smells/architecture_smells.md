---
name: architecture_smells
description: Detect structural and architectural smells that indicate boundary violations and design debt
tags: [architecture, design, boundaries, coupling]
applies_to: [services, models, jobs, strategies]
severity: [major, critical]
---

## Goal

Architecture smells reveal **structural violations** — the wrong code in the
wrong layer, hidden dependencies, violated boundaries, and accidental coupling
that makes the system brittle at scale.

## Architecture Smell Catalogue

### 1. Boundary Violation (critical)

**Symptom:** A layer accesses internals of another layer it should not know
about. In a trading system: a strategy directly calling a broker API, a model
fetching WebSocket data, a controller importing `Capital::Allocator`.

**Rule:** Each layer should only call the layer immediately below it.

```
Controller → Service → Domain Model → DB
Strategy   → Signal  → Gateway
```

---

### 2. Circular Dependency (critical)

**Symptom:** Module A requires Module B which requires Module A. In Rails,
often hidden until production boot.

**Refactor:** Introduce an interface/abstraction between the two — or re-assign
one responsibility to a third module.

---

### 3. God Object / God Service (critical)

**Symptom:** One class (typically named `Engine`, `Manager`, `Processor`,
`Handler`) knows about and orchestrates everything. Change one thing, everything
breaks.

**Detection:** Class file > 500 lines; > 20 public methods; > 10 dependencies.

**Refactor:** Decompose by responsibility. Each extracted class should be
independently testable.

---

### 4. Anemic Domain Model (major)

**Symptom:** Models are data containers (only attributes). All logic lives in
services. Models have no behavior.

**Consequence:** Logic is scattered; models cannot enforce their own invariants.

**Refactor:** Move domain behavior back into models — predicates, calculations,
state transitions that operate on the model's own data.

---

### 5. Service Layer Bloat (major)

**Symptom:** Hundreds of one-line services that just delegate to models.
Service layer became a second model layer.

**Refactor:** Delete trivial services. Models should own their domain behavior.

---

### 6. Leaky Abstraction (major)

**Symptom:** An abstraction's internals leak through its interface. E.g., a
service that returns raw SQL results instead of domain objects, or a gateway
that exposes broker-specific response structures.

**Refactor:** Transform to domain objects at the boundary.

---

### 7. Smart UI / Logic in Serialiser (major)

**Symptom:** Business rules embedded in JSON serialisers, Jbuilder templates,
or view helpers.

**Refactor:** Move to model predicates or presenter objects.

---

### 8. Temporal Coupling (major)

**Symptom:** Method A must be called before Method B. No enforcement.

```ruby
# Bad — must call setup before process
service.setup(config)
service.process(data)

# Good — enforce in initializer
service = Service.new(config)
service.process(data)
```

---

### 9. Hidden Global State (critical)

**Symptom:** Behaviour changes based on class variables (`@@`), global
variables (`$var`), or mutable constants. Especially dangerous in a
multi-threaded trading daemon.

**Refactor:** Pass state explicitly; use thread-local storage when necessary;
prefer singleton pattern with explicit methods over mutable class variables.

---

### 10. Missing Abstraction at Integration Points (major)

**Symptom:** DhanHQ broker API response format is referenced directly throughout
the codebase — no adapter/anti-corruption layer.

**Consequence:** Changing broker requires changes everywhere.

**Refactor:** All broker responses should be mapped to internal domain objects
at the gateway boundary:

```ruby
# Bad — broker format leaks into domain
signal[:dhan_order_id] = response[:data][:orderId]

# Good — adapter normalises at the boundary
result = Adapters::DhanResponse.normalise(response)
signal.order_id = result.order_id
```

## Trading System Specific Smells

### Strategy → Order Direct Coupling

```
# Smell: strategy directly places orders
class SupertrendStrategy
  def run
    signal = compute_signal
    Orders::GatewayLive.new.place_market(...)  # WRONG
  end
end

# Correct: strategy emits signal, executor places order
class SupertrendStrategy
  def run
    compute_signal  # returns Signal value object only
  end
end
```

### Exit Logic Spread Across Multiple Locations

```
# Smell: exit decisions in RiskManager AND TrailingEngine AND EntryGuard
# Rule: ExitEngine is the SINGLE source of truth for exit placement
# All exit detectors call ExitEngine.execute_exit — they don't place orders directly
```

## Agent Instructions

1. Map the dependency graph: which class calls which?
2. Flag any direction that violates layer ordering.
3. Identify god objects by file size and method count.
4. In trading system context, verify:
   - Strategies do not place orders
   - Models do not call external APIs
   - `ExitEngine` is the only entry point for exit placement
   - `Capital::Allocator` is the only entry point for position sizing
