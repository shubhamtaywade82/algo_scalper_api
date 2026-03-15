# Rails Architecture Skills

## Purpose

Teach coding agents to reason about Rails application architecture at a senior
level — domain modeling, service boundaries, query design, and ActiveRecord
best practices. This skill pack makes agents behave like a senior Rails
architect rather than a syntax assistant.

## Skill Domains

| Domain | Skills | When to Load |
|--------|--------|-------------|
| `domain/` | Domain modeling, bounded contexts, ubiquitous language | Architecture design |
| `boundaries/` | Service boundaries, anti-corruption layers, layer rules | Service design |
| `activerecord/` | AR misuse, N+1, eager loading, locking | Database reviews |
| `patterns/` | Repository, CQRS, specification, null object | Pattern application |

## Usage

### Architecture Review

```
Load rails_architecture_skills. Review the service boundary design
in app/services/entries/ and app/services/orders/. Identify boundary
violations, anemic models, and missing abstractions.
```

### Domain Modeling Session

```
Load rails_architecture_skills/domain/.
Propose a domain model for the options chain selection process,
including value objects, aggregates, and service boundaries.
```

## Codebase Context

Architecture constraints for **algo_scalper_api**:

- **Signal layer** is pure: no side effects, returns value objects
- **Entry layer** is the only layer that initiates order placement
- **ExitEngine** is the single authority for all exits
- **Capital::Allocator** is the single authority for position sizing
- **Models** own domain state; services own orchestration
- **Jobs** own async side effects; controllers own HTTP translation
