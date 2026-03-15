---
name: guard_clauses
description: Replace nested conditionals with early returns to reduce nesting and improve readability
tags: [ruby, conditionals, nesting, readability]
applies_to: [all]
severity: major
---

## Goal

Eliminate the "arrow anti-pattern" — deeply nested `if/else` blocks — by
returning early when preconditions fail. The happy path should flow linearly
without indentation.

## Principles

1. **Fail fast.** Check preconditions at the top and return/raise immediately.
2. **Happy path last.** The main logic is the final un-indented block.
3. **One guard per condition.** Avoid compound guards with multiple `&&` unless
   they form a single logical concept.
4. **Use `return nil` or `return false` explicitly** in guard clauses — don't
   rely on implicit nil returns which obscure intent.
5. **`next` and `break` are guards inside loops.** Use them instead of wrapping
   loop bodies in `if`.

## Detection Rules

Flag when:
- Method body is wrapped in a single `if` that covers the whole method
- Nesting depth exceeds 2 levels inside a method
- `else` clause contains the main work (flip the condition)
- Loop body is entirely inside `if some_condition`
- Method has `return` only in the `else` branch

## Refactoring Guidance

### Pattern 1: Flip negative condition

```ruby
# Before
def process(order)
  if order.valid?
    # 30 lines of work
  end
end

# After
def process(order)
  return unless order.valid?
  # 30 lines of work
end
```

### Pattern 2: Guard multiple preconditions

```ruby
# Before
def place_entry(signal, instrument, qty)
  if signal
    if instrument
      if qty.positive?
        # place entry
      end
    end
  end
end

# After
def place_entry(signal, instrument, qty)
  return unless signal
  return unless instrument
  return unless qty.positive?
  # place entry
end
```

### Pattern 3: Guard inside loop with `next`

```ruby
# Before
trackers.each do |tracker|
  if tracker.active?
    process_exit(tracker)
  end
end

# After
trackers.each do |tracker|
  next unless tracker.active?
  process_exit(tracker)
end
```

### Pattern 4: Early raise for invalid state

```ruby
# Before
def run_optimization(instrument)
  if instrument.nil?
    raise ArgumentError, 'instrument required'
  else
    # main work
  end
end

# After
def run_optimization(instrument)
  raise ArgumentError, 'instrument required' if instrument.nil?
  # main work
end
```

## Examples

### Bad — Arrow anti-pattern in trading service

```ruby
def try_enter(signal, index_cfg)
  if signal
    instrument = fetch_instrument(index_cfg)
    if instrument
      ltp = TickQuery.ltp(instrument.security_id)
      if ltp&.positive?
        if circuit_breaker_clear?
          qty = calculate_qty(ltp)
          if qty.positive?
            place_order(instrument, qty, ltp)
          end
        end
      end
    end
  end
end
```

### Good — Guard clauses

```ruby
def try_enter(signal, index_cfg)
  return unless signal
  instrument = fetch_instrument(index_cfg) or return
  ltp = TickQuery.ltp(instrument.security_id)
  return unless ltp&.positive?
  return unless circuit_breaker_clear?
  qty = calculate_qty(ltp)
  return unless qty.positive?
  place_order(instrument, qty, ltp)
end
```

## Agent Instructions

When reviewing code:

1. Identify the deepest nesting level in each method.
2. For each `if` that wraps the entire (or majority of) method body, suggest
   flipping to a guard clause with `return`/`next`/`break`.
3. Preserve `rescue`/`ensure` blocks — don't apply guard patterns there.
4. In trading system tick handlers, be conservative: some `if ltp.present?`
   wrappers are intentional defensive programming against stale data.
