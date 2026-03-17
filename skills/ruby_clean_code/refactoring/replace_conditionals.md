---
name: replace_conditionals
description: Replace complex conditional chains with polymorphism, tables, or guard clauses
tags: [refactoring, conditionals, polymorphism, design]
applies_to: [all]
severity: major
---

## Goal

Complex `if/elsif/case` chains are a smell. They usually mean either:
- **Missing polymorphism** — different types need different behaviour
- **Missing table** — a decision that could be data-driven
- **Missing guard clauses** — precondition checks that should return early

## Technique 1: Guard Clauses (most common)

For validation/precondition chains — see `guard_clauses.md`.

## Technique 2: Lookup Table / Strategy Hash

When a conditional maps values to other values or behaviours:

```ruby
# Bad — long if/elsif
def direction_for(side)
  if side == :ce || side == 'ce'
    :bullish
  elsif side == :pe || side == 'pe'
    :bearish
  else
    :unknown
  end
end

# Good — table-driven
DIRECTION_BY_SIDE = {
  ce: :bullish, 'ce' => :bullish,
  pe: :bearish, 'pe' => :bearish
}.freeze

def direction_for(side)
  DIRECTION_BY_SIDE.fetch(side, :unknown)
end
```

## Technique 3: Polymorphism

When a `case`/`if` branches on an object type and calls different methods:

```ruby
# Bad — type-switching
def apply_exit_rule(rule, context)
  case rule.type
  when 'premium_stop'
    check_premium_stop(context)
  when 'trailing_stop'
    check_trailing_stop(context)
  when 'time_stop'
    check_time_stop(context)
  end
end

# Good — polymorphic dispatch
class PremiumStopRule
  def apply(context) = check_premium_stop(context)
end

class TrailingStopRule
  def apply(context) = check_trailing_stop(context)
end

# Calling code:
rules.each { |rule| rule.apply(context) }
```

## Technique 4: Null Object Pattern

When `nil` checks create repetitive conditionals:

```ruby
# Bad
def process(instrument)
  if instrument
    ltp = instrument.last_price
    return unless ltp
    ltp * qty
  end
end

# Good — Null Object
class NullInstrument
  def last_price = nil
  def valid?     = false
end

instrument = fetch_instrument || NullInstrument.new
return unless instrument.valid?
instrument.last_price * qty
```

## Technique 5: Decompose Complex Conditionals

Extract complex boolean conditions into predicate methods:

```ruby
# Bad — unreadable compound condition
if adx.to_f > 25 && rsi.to_f.between?(30, 70) &&
   regime == 'TRENDING_UP' && !circuit_breaker.tripped? &&
   cooldown.expired? && Time.zone.now.hour.between?(9, 15)
  enter_trade
end

# Good — named predicates
def entry_conditions_met?(adx, rsi, regime)
  trend_strong?(adx) &&
    rsi_neutral?(rsi) &&
    regime_allows_entry?(regime) &&
    operational_conditions_met?
end

private

def trend_strong?(adx)          = adx.to_f > ADX_THRESHOLD
def rsi_neutral?(rsi)           = rsi.to_f.between?(30, 70)
def regime_allows_entry?(regime) = regime == 'TRENDING_UP'
def operational_conditions_met?
  !circuit_breaker.tripped? && cooldown.expired? && within_trading_hours?
end
```

## Detection Rules

Flag when:
- `case`/`if` has 4+ branches on the same variable
- Same conditional appears in 2+ methods (→ polymorphism or table)
- A conditional returns one of two identical-typed values based on a flag
- A long boolean expression has no named predicate

## Agent Instructions

1. Identify the conditional type: validation → guard clause, type switch →
   polymorphism, value mapping → table, complex boolean → predicate extraction.
2. Choose the technique based on the type.
3. Show the full before/after transformation.
4. For polymorphism, show the interface contract (what method each type implements).
