---
name: service_boundaries
description: Enforce clean service layer boundaries and prevent cross-layer contamination
tags: [architecture, boundaries, layers, services]
applies_to: [services, controllers, models]
severity: [major, critical]
---

## Goal

Service boundaries define which code is allowed to call which other code.
Violations create hidden coupling that makes services impossible to test,
refactor, or replace independently.

## Layer Dependency Rules

```
┌─────────────────────────────────┐
│  HTTP Layer (Controllers)       │  ← receives HTTP, delegates to services
├─────────────────────────────────┤
│  Application Layer (Services)   │  ← orchestrates use cases
├─────────────────────────────────┤
│  Domain Layer (Models + VOs)    │  ← owns business rules
├─────────────────────────────────┤
│  Infrastructure (DB, Redis, API)│  ← external I/O
└─────────────────────────────────┘

Rules:
- Upper layers MAY call lower layers
- Lower layers MUST NOT call upper layers
- Same-layer communication should be minimal and explicit
```

## Trading System Specific Boundaries

```
Signal Layer (pure computation)
  CALLS:     Indicators, CandleSeries, AlgoConfig, MarketRegimeDetector
  MUST NOT:  Orders::Gateway, PositionTracker (writes), Notifications

Entry Layer (orchestration)
  CALLS:     Signal Layer, Capital::Allocator, Orders::Gateway, PositionTracker
  MUST NOT:  be called from Signal Layer

Exit Layer (enforced by ExitEngine)
  CALLS:     Orders::Gateway, PositionTracker, TrailingEngine
  MUST NOT:  bypass ExitEngine — all exits go through it

Capital Layer (sizing only)
  CALLS:     AlgoConfig, account balance
  MUST NOT:  be bypassed for inline sizing math

Risk Layer
  CALLS:     All layers (reads only), ExitEngine (for emergency exits)
  MUST NOT:  modify strategy decisions
```

## Anti-Corruption Layer at Broker Boundary

All DhanHQ API responses must be normalised at the gateway boundary:

```ruby
# Bad — broker format leaks into domain
tracker.update!(order_id: response[:data][:orderId])

# Good — gateway normalises, domain uses clean keys
# In Orders::GatewayLive:
def normalise_response(raw)
  { order_id: raw.dig(:data, :orderId), status: raw.dig(:data, :orderStatus) }
end

# Domain code sees only:
tracker.update!(order_id: result[:order_id])
```

## Detecting Boundary Violations

### Cross-layer imports

```ruby
# Bad — model importing from infrastructure
class PositionTracker < ApplicationRecord
  require 'dhanhq'  # broker gem in domain model — violation!
end

# Bad — service calling controller helper
class EntryGuard
  include ActionController::Helpers  # presentation layer in service — violation!
end
```

### Upward dependencies

```ruby
# Bad — service layer calling HTTP layer
class Signal::Engine
  def run_for(index_cfg)
    render json: signal  # HTTP in signal layer — violation!
  end
end
```

### Skipping layers

```ruby
# Bad — controller directly accessing DB (skips service layer)
def create
  PositionTracker.create!(params)  # no service, no business rules
end

# Good
def create
  result = Entries::EntryGuard.new(index_cfg).try_enter(signal, pick)
  render json: result.to_h
end
```

## Dependency Inversion for Testability

High-level modules should not depend on low-level modules — both should
depend on abstractions:

```ruby
# Bad — hard dependency on concrete broker client
class Orders::GatewayLive
  def initialize
    @client = DhanHQ::Client.new(ENV['DHAN_ACCESS_TOKEN'])  # untestable!
  end
end

# Good — inject the client
class Orders::GatewayLive
  def initialize(client: DhanHQ::Client.new(ENV['DHAN_ACCESS_TOKEN']))
    @client = client
  end
end

# In tests:
gateway = Orders::GatewayLive.new(client: instance_double(DhanHQ::Client))
```

## Agent Instructions

1. For each service, map all its `require`, `include`, and method call targets.
2. Check that each target is in the same or lower layer.
3. Flag any upward dependency (service calling controller, domain calling infrastructure).
4. Check broker/external API responses are normalised at the boundary.
5. Verify entry points to the domain (gateway, signal engine) follow the layer rules.
