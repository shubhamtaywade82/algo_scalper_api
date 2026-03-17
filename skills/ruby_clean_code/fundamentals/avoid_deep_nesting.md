---
name: avoid_deep_nesting
description: Reduce block nesting depth to improve readability and testability
tags: [ruby, nesting, complexity, refactoring]
applies_to: [all]
severity: major
---

## Goal

Limit block nesting to **3 levels maximum** inside any method. Beyond 3 levels,
the code becomes difficult to reason about, test, and modify safely.

## Nesting Level Reference

```ruby
def method_name          # Level 0 (method definition)
  if condition_a         # Level 1
    array.each do |x|   # Level 2
      if condition_b     # Level 3  ← limit here
        if condition_c   # Level 4  ← VIOLATION
```

## Causes of Deep Nesting

1. **Conditional chains** — cascading `if/unless` without guard clauses
2. **Nested iterators** — `each` inside `each` inside `each`
3. **Mixed concerns** — data fetching + validation + transformation in one block
4. **Missing method extraction** — inner blocks that should be private methods

## Detection Rules

Flag when any method has:
- Block nesting deeper than 3 levels
- An `each` block containing another `each` block containing logic
- A `rescue` block nested inside a conditional inside a loop
- More than 2 `end` keywords on consecutive lines

## Refactoring Techniques

### Technique 1: Guard clause (see guard_clauses.md)

Eliminate the outermost `if` by using `next`/`return`/`break`.

### Technique 2: Extract inner block to method

```ruby
# Before — 4 levels deep
option_chain.each do |strike, data|
  [:ce, :pe].each do |side|
    if data[side]
      if data[side][:oi] > MIN_OI
        process_strike(strike, side, data[side])
      end
    end
  end
end

# After — 2 levels deep
option_chain.each do |strike, data|
  SIDES.each do |side|
    process_side(strike, side, data[side])
  end
end

private

def process_side(strike, side, option_data)
  return unless option_data
  return unless option_data[:oi] > MIN_OI
  process_strike(strike, side, option_data)
end
```

### Technique 3: Replace nested iteration with flat pipeline

```ruby
# Before — 3-level nesting
results = []
indices.each do |index|
  index[:strikes].each do |strike|
    if strike[:qualified]
      results << build_entry(index, strike)
    end
  end
end

# After — flat pipeline
results = indices.flat_map do |index|
  index[:strikes]
    .select { |s| s[:qualified] }
    .map { |s| build_entry(index, s) }
end
```

### Technique 4: Decompose conditional tree into decision table

```ruby
# Before — nested conditionals for regime/direction
if regime == 'TRENDING_UP'
  if adx > 25
    if rsi < 70
      :enter_long
    else
      :wait
    end
  else
    :wait
  end
elsif regime == 'TRENDING_DOWN'
  # ...
end

# After — table-driven decision
ENTRY_MATRIX = {
  ['TRENDING_UP',   :strong_adx, :rsi_ok] => :enter_long,
  ['TRENDING_DOWN', :strong_adx, :rsi_ok] => :enter_short,
}.freeze

def entry_signal(regime, adx, rsi)
  key = [regime, adx_band(adx), rsi_band(rsi)]
  ENTRY_MATRIX.fetch(key, :wait)
end
```

## Trading System Context

In this codebase, deep nesting commonly appears in:

- `Signal::Engine#run_for` — decompose into `fetch_indicators`, `evaluate_regime`,
  `validate_entry_conditions`, `build_signal`
- `Options::ChainAnalyzer#pick_strikes` — decompose into `filter_by_liquidity`,
  `score_strikes`, `select_best`
- `Entries::EntryGuard#try_enter` — the guard pipeline is the right pattern;
  each guard should be its own method

## Agent Instructions

1. Count nesting depth in each method.
2. For violations, identify the **deepest block** and propose an extracted
   method name and signature.
3. Apply guard clauses to eliminate outer `if` wrappers first.
4. Then extract inner loops/blocks to private methods.
5. Never mechanically flatten if the result obscures domain logic — the goal
   is readable code, not minimal indentation.
