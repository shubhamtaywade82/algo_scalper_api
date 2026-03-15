---
name: intention_revealing_names
description: Ensure variables, methods, and classes clearly express intent without requiring comments
tags: [ruby, naming, readability]
applies_to: [all]
severity: warning
---

## Goal

Every name — variable, method, class, constant — must answer three questions:
*what it holds*, *what it does*, and *why it matters* in the domain. A reader
should never need to check the implementation to understand a call site.

## Principles

1. **Use domain language.** In a trading system, prefer `entry_price`,
   `position_size`, `signal_direction` over `val`, `n`, `data`.
2. **Predicates end in `?`.** `valid?`, `expired?`, `bullish?`, `stale?`.
3. **Mutating methods end in `!`.** `expire!`, `close!`, `transition!`.
4. **Avoid abbreviations** unless universal (`ltp` = last traded price in
   Indian markets is acceptable domain jargon; `p` for price is not).
5. **Booleans read as statements.** Prefer `include_today` over `flag`,
   `trading_enabled` over `te`.
6. **Collections are plural.** `instruments`, `signals`, `trackers`.
7. **No noise words.** `order_data` → `order`, `calc_result` → `result`.

## Detection Rules

Flag when:
- Method or variable name is a single letter (except block params `|e|`, `|k, v|`)
- Name contains `data`, `info`, `obj`, `tmp`, `val`, `res`, `ret`, `flag`
- Boolean variable doesn't read as a true/false statement
- Predicate method does not end in `?`
- Name requires a comment above it to explain what it holds

## Refactoring Guidance

1. Read the implementation — what does it *actually* do?
2. Extract the domain concept: is this a `premium_decay_rate`, a `strike_distance`, an `expiry_window`?
3. Rename everywhere (search + replace, update callers).
4. Delete any comment that was compensating for the unclear name.

## Examples

### Bad

```ruby
def p(u)
  u.a > 18
end

def calc(x, y)
  x * y * 0.18
end

tmp = orders.select { |o| o.status == 'active' }
flag = ltp > entry
d = Time.current - created_at
```

### Good

```ruby
def adult?(user)
  user.age > 18
end

def apply_gst(base_amount, rate)
  base_amount * rate * 0.18
end

active_orders = orders.select { |o| o.status == 'active' }
price_moved_up = ltp > entry_price
days_since_entry = Time.current - created_at
```

### Trading System Specific

```ruby
# Bad
def chk(t)
  t.m.dig('adx') > cfg[:thresh]
end

# Good
def trend_strong?(tracker)
  tracker.meta.dig('adx').to_f > adx_threshold
end
```

## Agent Instructions

When reviewing code:

1. Scan all `def`, `let`, assignment, and block parameter names.
2. Flag any name that matches the detection rules above.
3. Propose a replacement using domain language from the file's context
   (e.g., if the file is about signals, use signal/trend/regime vocabulary).
4. Output as inline comments in the format:

```
file: app/services/signal/engine.rb
line: 47
severity: warning
comment: `d` is unclear. In signal context this appears to be the ADX direction.
suggestion: Rename `d` to `adx_direction` or `trend_direction`.
```
