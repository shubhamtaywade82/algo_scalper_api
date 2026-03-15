---
name: domain_modeling
description: Model the core business domain with entities, value objects, aggregates, and domain services
tags: [ddd, domain, modeling, architecture]
applies_to: [models, services, strategies]
severity: major
---

## Goal

Build a domain model that speaks the language of the business — where the code
structure reflects the domain concepts, not the technology stack.

## Domain Building Blocks

### Entity

An object with a persistent identity that changes over time.

```
PositionTracker — has an ID, changes state (init → active → exited)
Instrument      — has a symbol, immutable once created
Order           — has an order number, transitions through broker states
```

### Value Object

An immutable object identified by its values, not its identity.

```
TradingSignal   — direction + confidence + regime (no DB identity)
StrikeSelection — strike + expiry + side (no DB identity)
MarketRegime    — regime + adx + confidence (snapshot)
OptionGreeks    — delta + gamma + theta + vega
```

### Aggregate

A cluster of entities + value objects with one root that enforces invariants.

```
Position Aggregate:
  Root: PositionTracker
  Parts: PositionMeta, TrailingState, ExitIntent
  Invariant: only one exit attempt at a time; qty is always positive
```

### Domain Service

Stateless operation that doesn't naturally belong to any single entity:

```
Capital::Allocator      — computes position size across instruments
Risk::CircuitBreaker    — cross-position risk enforcement
Signal::Engine          — generates signals from market data
```

### Repository (Query Object)

Abstracts data access for a domain aggregate:

```
Queries::ActivePositionsQuery
Queries::ProfitableExitsQuery
```

## Ubiquitous Language

In **algo_scalper_api**, the domain language is:

| Term | Meaning |
|------|---------|
| `signal` | A directional recommendation from the strategy engine |
| `entry` | The act of opening a new position |
| `exit` | The act of closing a position |
| `tracker` | A `PositionTracker` record — the live position object |
| `pick` | The selected option strike/instrument for entry |
| `regime` | Current market state: TRENDING_UP/DOWN, RANGING, CHOPPY |
| `side` | `:ce` (call) or `:pe` (put) |
| `ltp` | Last traded price |
| `adx` | Average Directional Index (trend strength) |
| `lot_size` | Number of units per contract |

Code should use this vocabulary. Flag any code that uses:
- `option_type` where `side` is the domain term
- `position` where `tracker` is the domain term
- `trade` where `entry` or `exit` is more precise
- `data` where a domain name applies

## Domain Invariants to Enforce

Critical business rules that must never be violated:

1. **One active position per index per side.** Two NIFTY CE positions
   simultaneously is a risk violation.
2. **Qty is always positive.** Zero or negative qty is invalid.
3. **Exit price must be set before marking exited.** `exit_price` cannot be
   null on an exited tracker.
4. **Trailing stop can only move in the favorable direction.** A trailing stop
   that moves against the position is a bug.
5. **Capital sizing must go through `Capital::Allocator`.** No inline math.

## Agent Instructions

1. Identify entities (have IDs, change over time) vs value objects (immutable,
   equality by value).
2. Find primitive clusters that should become value objects.
3. Check that model validations enforce domain invariants (not just DB constraints).
4. Verify the code uses the ubiquitous language defined above.
5. Flag any term that is synonymous with a domain term but uses a different name.
