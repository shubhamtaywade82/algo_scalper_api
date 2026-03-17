---
name: value_objects
description: Replace primitive data clusters with value objects that encapsulate domain concepts
tags: [ruby, value_objects, domain, design]
applies_to: [models, services, strategies]
severity: warning
---

## Goal

When multiple primitives always travel together and have domain meaning, wrap
them in a **Value Object** — an immutable, equality-by-value object that
encapsulates the concept.

## Characteristics of a Value Object

1. **Immutable** — no setters, all state set at initialization
2. **Equality by value** — two VOs with the same data are equal (`==`)
3. **No identity** — no database ID, no lifecycle
4. **Self-validating** — raises on invalid construction
5. **Behavior-rich** — contains the logic that operates on its data

## When to Introduce a Value Object

Introduce when you see:
- Multiple primitives always passed together: `strike, expiry, side`
- Repeated nil-guard chains: `signal && signal[:direction] && signal[:confidence]`
- Hash-as-object patterns: `{ regime: 'TRENDING_UP', adx: 28.4, confidence: 82 }`
- Methods that accept 4+ parameters that represent one concept
- The same validation repeated across multiple classes

## Ruby Implementation Patterns

### Pattern 1: Struct-based (simple)

```ruby
# For simple data containers with no complex behavior
Signal = Struct.new(:direction, :confidence, :regime, :timestamp, keyword_init: true) do
  def actionable?
    confidence >= 0.65 && %i[bullish bearish].include?(direction)
  end

  def bullish? = direction == :bullish
  def bearish? = direction == :bearish
  def stale?   = Time.current - timestamp > 30.seconds
end
```

### Pattern 2: Class-based (rich behavior)

```ruby
class StrikeSelection
  attr_reader :strike, :expiry, :side, :instrument

  def initialize(strike:, expiry:, side:, instrument:)
    @strike     = strike.to_f
    @expiry     = expiry.is_a?(Date) ? expiry : Date.parse(expiry.to_s)
    @side       = side.to_s.downcase.to_sym
    @instrument = instrument
    validate!
  end

  def premium_estimate(spot)
    intrinsic = call? ? [spot - strike, 0].max : [strike - spot, 0].max
    intrinsic + time_value_estimate
  end

  def call? = side == :ce
  def put?  = side == :pe

  def ==(other)
    other.is_a?(StrikeSelection) &&
      strike == other.strike &&
      expiry == other.expiry &&
      side   == other.side
  end

  private

  def validate!
    raise ArgumentError, 'strike must be positive' unless strike.positive?
    raise ArgumentError, 'side must be :ce or :pe' unless %i[ce pe].include?(side)
  end
end
```

### Pattern 3: Data class (Ruby 3.2+)

```ruby
# Ruby 3.2+ Data class — immutable, equality by value, no setters
MarketRegime = Data.define(:regime, :adx, :confidence) do
  def trending? = regime.start_with?('TRENDING')
  def ranging?  = regime == 'RANGING'
  def choppy?   = regime == 'CHOPPY'
  def strong?   = adx >= 25.0
end

regime = MarketRegime.new(regime: 'TRENDING_UP', adx: 28.4, confidence: 82.0)
regime.trending? # => true
```

## Trading System Examples

### Before — hash-as-object anti-pattern

```ruby
def run_for(index_cfg)
  signal = {
    direction: :bullish,
    confidence: 0.78,
    adx: 28.4,
    regime: 'TRENDING_UP',
    entry_allowed: true,
    timestamp: Time.current
  }
  return unless signal[:entry_allowed] && signal[:confidence] > 0.65
  emit(signal)
end
```

### After — value object

```ruby
def run_for(index_cfg)
  signal = build_signal(index_cfg)
  return unless signal.actionable?
  emit(signal)
end

def build_signal(index_cfg)
  Signal.new(
    direction:  compute_direction(index_cfg),
    confidence: compute_confidence(index_cfg),
    regime:     current_regime(index_cfg),
    timestamp:  Time.current
  )
end
```

## Agent Instructions

1. Find hashes with 3+ domain keys that are passed through multiple methods.
2. Find groups of 3+ parameters that represent one concept.
3. Propose a Value Object name (noun phrase in domain language).
4. Show the Struct or Data.define skeleton.
5. Identify methods on the VO to move behavior out of callers.
