---
name: ruby_idioms
description: Apply idiomatic Ruby patterns to produce expressive, concise, and Rubyist code
tags: [ruby, idioms, style, expressiveness]
applies_to: [all]
severity: warning
---

## Goal

Idiomatic Ruby code reads like a well-structured English sentence. Prefer
Ruby's built-in expressive constructs over verbose boilerplate.

## Core Idioms

### 1. Safe navigation operator (`&.`)

```ruby
# Bad
result = nil
result = obj.method if obj

# Good
result = obj&.method
```

### 2. `||=` and `&&=` for conditional assignment

```ruby
# Bad
@cache = @cache || {}
config = config && config[:key]

# Good
@cache ||= {}
config &&= config[:key]
```

### 3. `fetch` with defaults instead of `|| default`

```ruby
# Bad
timeout = config[:timeout] || 30

# Good — raises KeyError if missing (explicit contract)
timeout = config.fetch(:timeout, 30)
# or strict — intentional missing key is a bug:
timeout = config.fetch(:timeout)
```

### 4. Predicate methods with `?`

```ruby
# Bad
def is_valid
  status == 'active'
end

# Good
def valid?
  status == 'active'
end
```

### 5. `tap` for object construction with side effects

```ruby
# Bad
series = CandleSeries.new(symbol: sym, interval: interval)
series.load_from_raw(raw_data)
@cache[interval] = series

# Good
@cache[interval] = CandleSeries.new(symbol: sym, interval: interval).tap do |s|
  s.load_from_raw(raw_data)
end
```

### 6. `then`/`yield_self` for transformation pipelines

```ruby
# Good — when result flows through a transformation
raw_signal
  .then { |s| validate_signal(s) }
  .then { |s| enrich_with_regime(s) }
```

### 7. Hash `dig` for nested access

```ruby
# Bad
meta && meta[:trailing] && meta[:trailing][:peak]

# Good
meta&.dig(:trailing, :peak)
```

### 8. Pattern matching (Ruby 3+) for structured data

```ruby
case result
in { regime: 'TRENDING_UP', confidence: (75..) }
  enter_long
in { regime: 'RANGING' }
  stay_flat
end
```

### 9. Array methods over imperative loops

```ruby
# Bad
results = []
trackers.each do |t|
  results << t.pnl if t.active?
end

# Good
results = trackers.filter_map { |t| t.pnl if t.active? }
```

### 10. `Comparable` and `Enumerable` modules

```ruby
# Bad — manual min/max selection
best = nil
candidates.each { |c| best = c if best.nil? || c.score > best.score }

# Good
best = candidates.max_by(&:score)
```

## Detection Rules

Flag when:
- `if x; x; else; y; end` — use `x || y`
- `x = nil; x = val if cond` — use `x = val if cond` directly
- `arr.select { }.first` — use `arr.find { }`
- `arr.select { }.count` — use `arr.count { }`
- `arr.map { }.compact` — use `arr.filter_map { }`
- `x.nil? ? default : x` — use `x || default` or `x.presence || default`
- Manual `each` with accumulator instead of `map`/`reduce`/`filter_map`
- `is_` prefix on predicate (use `?` suffix instead)
- `respond_to?(:to_ary)` for array check — use `is_a?(Array)`

## Agent Instructions

When reviewing code:

1. Identify non-idiomatic constructs from the detection rules.
2. Suggest the idiomatic equivalent with a brief explanation of why.
3. Prioritize fixes that reduce line count or eliminate nil-guard boilerplate.
4. Do not force idioms that reduce clarity — a verbose form is acceptable when
   the idiomatic version would be harder to read at a glance.
