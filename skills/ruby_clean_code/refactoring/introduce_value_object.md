---
name: introduce_value_object
description: Step-by-step process for introducing a value object to replace primitive clusters
tags: [refactoring, value_objects, primitives]
applies_to: [services, models, strategies]
severity: warning
---

## Goal

Replace a cluster of related primitives (or a hash-as-object) with an immutable
Value Object that encapsulates the concept, validates itself, and carries
domain behaviour.

## When to Introduce

**Trigger signals:**
- 3+ parameters always passed together: `(strike, expiry, side, instrument)`
- Hash accessed repeatedly: `signal[:direction]`, `signal[:confidence]`, `signal[:regime]`
- Same nil-check repeated: `result && result[:score] && result[:score] > 0`
- Same transformation repeated: `side.to_s.downcase.to_sym`

## Step-by-Step Process

### Step 1: Name the concept

What do these primitives represent as a *thing*? In a trading system:
- `strike + expiry + side` → `OptionSelection`
- `direction + confidence + regime` → `TradingSignal`
- `adx + rsi + regime + timestamp` → `MarketSnapshot`

### Step 2: Identify fields and types

```
OptionSelection:
  strike:     Float (positive)
  expiry:     Date
  side:       Symbol (:ce or :pe)
  instrument: Instrument (optional)
```

### Step 3: Create the Value Object

```ruby
# Use Data.define for simple immutable VOs (Ruby 3.2+)
OptionSelection = Data.define(:strike, :expiry, :side) do
  def initialize(strike:, expiry:, side:)
    raise ArgumentError, "strike must be positive" unless strike.to_f.positive?
    raise ArgumentError, "side must be :ce or :pe"  unless %i[ce pe].include?(side.to_sym)
    super(
      strike: strike.to_f,
      expiry: expiry.is_a?(Date) ? expiry : Date.parse(expiry.to_s),
      side:   side.to_sym
    )
  end

  def call? = side == :ce
  def put?  = side == :pe
  def otm?(spot) = call? ? strike > spot : strike < spot
end
```

### Step 4: Replace usages

```ruby
# Before
def score_strike(strike, expiry, side, iv, oi, spread)
  return 0 if side.to_s.downcase != 'ce' && side.to_s.downcase != 'pe'
  ...
end

# After
def score_strike(selection, iv, oi, spread)
  ...  # selection.call?, selection.put?, selection.strike, etc.
end
```

### Step 5: Move behaviour into the VO

Identify methods in other classes that only operate on the VO's data and move
them in:

```ruby
# Before — external logic operating on the VO's data
def otm_depth(selection, spot)
  selection.call? ? selection.strike - spot : spot - selection.strike
end

# After — behaviour on the VO itself
class OptionSelection
  def otm_depth(spot)
    call? ? strike - spot : spot - strike
  end
end
```

### Step 6: Verify

- All creation sites use the constructor
- Old parameter clusters removed
- VO validates at creation time
- Behaviour moved into the VO reduces external code

## Trading System Examples

### Before

```ruby
def pick_strike(side, spot, atm_strike, strike_interval, expiry_date)
  target = side.to_s == 'ce' ? atm_strike + strike_interval : atm_strike - strike_interval
  {
    strike: target,
    expiry: expiry_date,
    side: side,
    otm_distance: (target - spot).abs
  }
end
```

### After

```ruby
def pick_strike(side, spot, atm_strike, strike_interval, expiry_date)
  target = side == :ce ? atm_strike + strike_interval : atm_strike - strike_interval
  OptionSelection.new(strike: target, expiry: expiry_date, side: side)
end

# OptionSelection#otm_distance(spot) is now a method on the VO
```

## Agent Instructions

1. Find parameter lists of 3+ related primitives.
2. Find repeated hash access patterns (`result[:x]`, `result[:y]`, `result[:z]`).
3. Propose a VO name in domain language.
4. Show the Data.define or Struct skeleton.
5. Identify 2–3 methods from callers that should become methods on the VO.
6. Show the before/after at the primary call site.
