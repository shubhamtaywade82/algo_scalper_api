---
name: immutability
description: Prefer immutable objects and frozen constants to prevent accidental mutation
tags: [ruby, immutability, frozen, thread-safety]
applies_to: [all]
severity: warning
---

## Goal

Immutable objects eliminate an entire class of bugs: unexpected mutation,
thread-safety issues in multi-threaded trading daemons, and cache poisoning.
In a system with shared Redis state and 11 concurrent service threads, mutation
bugs are especially dangerous.

## Principles

1. **Freeze all constants.** Every constant array, hash, and string must end
   with `.freeze`.
2. **Value objects are immutable by definition.** No setters.
3. **Prefer non-mutating methods.** `map` over `each + push`, `merge` over
   `[]=` in returned hashes.
4. **`frozen_string_literal: true` on every file.** This freezes all string
   literals at parse time — enforced by the `# frozen_string_literal: true`
   magic comment.
5. **Config is read-only after load.** Never modify `AlgoConfig.fetch`
   result in-place; use a local copy.

## Detection Rules

Flag when:
- A constant is defined without `.freeze` (arrays, hashes, strings)
- A method modifies a hash/array that was passed as a parameter
- `AlgoConfig.fetch[:key]` result is modified in place (`config[:key] = ...`)
- A Struct has setter methods (`attr_accessor` inside a Struct)
- A shared object (singleton, class variable `@@`) is mutated in a hot path

## Examples

### Constants

```ruby
# Bad
VALID_SIDES = ['ce', 'pe']
REGIME_LABELS = { trending: 'TRENDING', ranging: 'RANGING' }

# Good
VALID_SIDES    = %w[ce pe].freeze
REGIME_LABELS  = { trending: 'TRENDING', ranging: 'RANGING' }.freeze
```

### Config mutation — critical bug in trading systems

```ruby
# Bad — mutates the cached AlgoConfig reference shared across threads!
signals_cfg = AlgoConfig.fetch[:signals]
signals_cfg[:validation_mode] = 'conservative'  # poison the cache

# Good — use a local variable, never mutate the config
validation_mode = if ranging_market?
                   'conservative'
                 else
                   AlgoConfig.fetch.dig(:signals, :validation_mode)
                 end
```

### Immutable return values

```ruby
# Bad — caller can mutate returned internal state
def permitted_regimes
  @permitted_regimes  # exposes mutable internal array
end

# Good — return a frozen copy
def permitted_regimes
  @permitted_regimes.dup.freeze
end
# Or always store frozen:
def permitted_regimes
  @permitted_regimes ||= compute_permitted_regimes.freeze
end
```

### Struct immutability

```ruby
# Bad — Struct with setters
Signal = Struct.new(:direction, :confidence)
s = Signal.new(:bullish, 0.8)
s.direction = :bearish  # silent mutation

# Good — freeze the instance
Signal = Struct.new(:direction, :confidence, keyword_init: true) do
  def initialize(**)
    super
    freeze
  end
end
```

## Trading System Context

This codebase runs 11 services in concurrent threads sharing:
- `AlgoConfig` (30s cache — treat as read-only)
- Redis tick cache (write-through — only `Live::TickCache` should write)
- `PositionIndex` (singleton — mutations must be thread-safe)

**Never mutate objects obtained from these shared sources.**

## Agent Instructions

1. Scan all `CONSTANT =` definitions — flag any without `.freeze`.
2. Find any `config[:key] = ...` or `hash[key] = ...` where `hash` came from
   a shared source (config, cache, singleton).
3. Flag Struct definitions with `attr_accessor` or without `freeze`.
4. Flag files missing `# frozen_string_literal: true`.
