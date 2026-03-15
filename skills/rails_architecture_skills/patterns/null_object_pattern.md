---
name: null_object_pattern
description: Replace nil checks with Null Objects to eliminate conditional clutter and nil-related bugs
tags: [patterns, null_object, nil, design]
applies_to: [models, services, strategies]
severity: warning
---

## Goal

Replace repeated `nil?` checks with a **Null Object** — an object that
implements the same interface as the real object but does nothing (or returns
safe defaults). Eliminates `NoMethodError` on nil and removes defensive
conditionals from callers.

## When to Apply

Apply when:
- The same nil check appears in 3+ places for the same object type
- A method chain is guarded by `&.` because nil is a valid "missing" case
- An object is optional and its absence changes many callers' behaviour
- You find yourself writing `if instrument; ...; end` everywhere

## Pattern

```ruby
# Real object
class Instrument
  attr_reader :symbol_name, :security_id, :lot_size

  def valid?     = true
  def tradeable? = active? && !expired?
  def last_price = TickQuery.ltp(security_id)
end

# Null Object — same interface, safe defaults
class NullInstrument
  def symbol_name  = 'UNKNOWN'
  def security_id  = nil
  def lot_size     = 1
  def valid?       = false
  def tradeable?   = false
  def last_price   = nil

  def to_s = '#<NullInstrument>'
end
```

## Before vs After

### Before — nil checks everywhere

```ruby
def try_enter(index_cfg)
  instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
  return unless instrument
  return unless instrument.valid?

  ltp = instrument.last_price
  return unless ltp

  lot_size = instrument.lot_size || 1
  # ...
end
```

### After — Null Object handles missing cases

```ruby
# IndexInstrumentCache returns NullInstrument instead of nil
def try_enter(index_cfg)
  instrument = IndexInstrumentCache.instance.get_or_fetch(index_cfg)
  return unless instrument.tradeable?   # NullInstrument#tradeable? => false

  ltp = instrument.last_price           # NullInstrument#last_price => nil
  return unless ltp

  # lot_size never nil — NullInstrument returns 1
  qty = @allocator.qty_for(instrument, ltp)
  # ...
end
```

## Null Object for Optional Collaborators

```ruby
# Optional notifier — Null Object avoids nil checks
class NullNotifier
  def notify(_message) = nil
  def send_alert(_alert) = nil
end

class EntryGuard
  def initialize(notifier: NullNotifier.new)
    @notifier = notifier
  end

  def try_enter(...)
    # ...
    @notifier.notify("Entry placed: #{order_no}")  # no nil check needed
  end
end
```

## Trading System Applications

| Object | Null Version | Return for |
|--------|-------------|-----------|
| `Instrument` | `NullInstrument` | Cache miss, disabled index |
| `CandleSeries` | `NullCandleSeries` | No OHLC data available |
| `Signal` | `NullSignal` | No actionable signal |
| `Notifier` | `NullNotifier` | Tests, paper trading |

```ruby
class NullSignal
  def actionable? = false
  def bullish?    = false
  def bearish?    = false
  def direction   = nil
  def confidence  = 0.0
  def to_s        = '#<NullSignal>'
end
```

## Detection Rules

Flag when:
- The same object is nil-checked 3+ times across the codebase
- `&.` is used on every access of the same optional object
- A method returns `nil` to mean "no result" when a Null Object would be safer

## Agent Instructions

1. Find objects that are repeatedly nil-checked.
2. Identify the interface (methods) callers use on the object.
3. Propose a Null Object implementing the same interface with safe defaults.
4. Show the before/after for the primary call site.
5. Verify the Null Object's methods are safe to call without side effects.
