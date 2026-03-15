---
name: small_methods
description: Enforce small, focused methods that do exactly one thing
tags: [ruby, methods, complexity, srp]
applies_to: [all]
severity: major
---

## Goal

Each method performs **one task** at one level of abstraction. The method name
completely describes what it does — the body is just the *how*.

## Principles

1. **Ideal size: 5–10 lines.** 15 is the absolute max before extraction becomes
   mandatory. In a trading system, complex decision methods may reach 20 lines
   if they are pure data transformations with no side effects.
2. **One level of abstraction per method.** A method that calls `calculate_adx`
   should not also index into `result[:value].to_f.round(2)` — that detail
   belongs one level down.
3. **No mixed abstraction levels.** Don't mix high-level orchestration
   (`try_enter`, `run_signal_cycle`) with low-level detail (`tracker.meta ||= {}`)
   in the same method.
4. **Extract until it hurts.** If you can name the extracted piece naturally,
   extract it.
5. **Private methods are free.** Use `private` sections generously.

## Detection Rules

Flag when a method:
- Exceeds 15 lines of meaningful code (blank lines and comments excluded)
- Contains more than one `rescue` block
- Contains nested `if/unless` inside a loop
- Has a comment section like `# Step 1:`, `# Phase 2:` — those are method boundaries
- Calls more than 4 different collaborators
- Has a name with `and`, `or`, `then`: `validate_and_save`, `fetch_or_compute`

## Refactoring Guidance

### Extract Method pattern

1. Find a cohesive block of lines (often marked by a comment).
2. Identify inputs (parameters) and outputs (return value).
3. Extract to a private method with an intention-revealing name.
4. Replace the original block with the method call.

### Decompose large signal/strategy methods

Large `run_for` or `execute` methods in trading services typically decompose into:

```
run_for
  └── fetch_market_data
  └── compute_indicators
  └── evaluate_regime
  └── generate_signal
  └── validate_signal
  └── emit_signal
```

Each sub-method is testable in isolation.

## Examples

### Bad

```ruby
def process(order)
  # validate
  raise 'invalid' unless order.instrument
  raise 'invalid' unless order.qty.positive?
  # calculate size
  risk_pct = 0.01
  capital = account.balance
  size = (capital * risk_pct / order.ltp).floor
  # place
  response = gateway.place_market(side: order.side, qty: size)
  # record
  tracker = PositionTracker.create!(
    order_no: response[:order_id],
    entry_price: order.ltp,
    qty: size
  )
  tracker
end
```

### Good

```ruby
def process(order)
  validate!(order)
  qty = calculate_position_size(order)
  response = place_order(order, qty)
  record_position(order, response, qty)
end

private

def validate!(order)
  raise ArgumentError, 'instrument required' unless order.instrument
  raise ArgumentError, 'qty must be positive' unless order.qty.positive?
end

def calculate_position_size(order)
  risk_budget = account.balance * RISK_PER_TRADE_PCT
  (risk_budget / order.ltp).floor
end

def place_order(order, qty)
  gateway.place_market(side: order.side, qty: qty)
end

def record_position(order, response, qty)
  PositionTracker.create!(
    order_no: response[:order_id],
    entry_price: order.ltp,
    qty: qty
  )
end
```

## Agent Instructions

When reviewing code:

1. Measure method length (count non-blank, non-comment lines).
2. Identify comment blocks that signal extraction points.
3. Check for mixed abstraction levels.
4. Propose extracted method names and signatures.
5. Flag but do not refactor methods that are pure algorithmic computations
   (e.g., a 20-line ATR calculation with no branching) — these may be
   intentionally long for performance or auditability.
