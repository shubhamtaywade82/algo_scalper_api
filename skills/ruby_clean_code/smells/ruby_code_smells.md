---
name: ruby_code_smells
description: Detect and remediate common Ruby code smells across all layers
tags: [ruby, smells, refactoring, quality]
applies_to: [all]
severity: [warning, major, critical]
---

## Goal

Identify structural code problems that indicate deeper design issues. Smells
are not bugs — they are symptoms that make the code fragile, hard to test,
or hard to change.

## Smell Catalogue

### 1. Long Method (major)

**Symptom:** Method exceeds 15 meaningful lines, contains comment blocks as
section headers.

**Refactor:** Extract Method — each comment header becomes a method name.

---

### 2. Long Parameter List (major)

**Symptom:** Method takes 4+ parameters, especially booleans.

```ruby
# Bad
def run(instrument, interval, lookback, test_mode, cache_enabled, verbose)

# Good
def run(config)  # or use keyword args with a config value object
def run(instrument:, options: OptimizationOptions.new)
```

---

### 3. Boolean Parameter (warning)

**Symptom:** `method(x, true)` — the caller has no idea what `true` means.

```ruby
# Bad
def optimize(instrument, true)  # what does true mean?

# Good — use keyword argument
def optimize(instrument, test_mode: false)
# Or split into two methods
def optimize(instrument)
def optimize_test(instrument)
```

---

### 4. Primitive Obsession (warning)

**Symptom:** Cluster of related primitives (`strike`, `expiry`, `side`) passed
together everywhere. Hash-as-object anti-pattern.

**Refactor:** Introduce Value Object (see `value_objects.md`).

---

### 5. Data Clumps (warning)

**Symptom:** Same group of variables appear together in multiple method
signatures: `(instrument, interval, lookback_days)` everywhere.

**Refactor:** Introduce a parameter object or Value Object.

---

### 6. Feature Envy (major)

**Symptom:** A method accesses data from another object more than from its
own object.

```ruby
# Bad — PositionCalculator is obsessed with PositionTracker's data
class PositionCalculator
  def pnl(tracker)
    (tracker.exit_price - tracker.entry_price) * tracker.qty * tracker.direction_multiplier
  end
end

# Good — put the method on the object it envies
class PositionTracker < ApplicationRecord
  def pnl
    (exit_price - entry_price) * qty * direction_multiplier
  end
end
```

---

### 7. Inappropriate Intimacy (major)

**Symptom:** Class accesses `private` or internal state of another class.
Services reaching into model's `meta` hash as if they own it.

**Refactor:** Add a public accessor method on the target class.

---

### 8. Shotgun Surgery (major)

**Symptom:** A single change requires edits in 5+ files. Common when the same
magic number or string appears in many places.

**Refactor:** Introduce a single-source constant, config key, or service.

---

### 9. Duplicate Code (major)

**Symptom:** Same logic appears in 2+ places with minor variations.

**Refactor:** Extract to a shared method, concern, or service. Parameterise
the variation.

---

### 10. Dead Code (warning)

**Symptom:** Methods, variables, or classes that are never called.

**Refactor:** Delete. Don't comment out.

---

### 11. Speculative Generality (warning)

**Symptom:** Abstractions built for hypothetical future requirements — empty
base classes, unused parameters, configurable options that are never changed.

**Refactor:** YAGNI — delete the unused abstraction.

---

### 12. Magic Numbers/Strings (warning)

**Symptom:** `0.12`, `25`, `'active'` appear inline without a named constant.

```ruby
# Bad
if adx > 25 && rsi < 70

# Good
if adx > ADX_TREND_THRESHOLD && rsi < RSI_OVERBOUGHT_THRESHOLD
```

---

### 13. Nil Proliferation (major)

**Symptom:** `nil` used as a meaningful value — passed as "no data", "not
applicable", or "failed". Creates `NoMethodError` bugs.

**Refactor:** Use Null Object pattern, `Result` object, or explicit `Optional`.

---

### 14. Overuse of Metaprogramming (critical)

**Symptom:** `define_method`, `method_missing`, `send` used where simple
polymorphism or composition would work.

**Refactor:** Explicit method definitions, or `case`/strategy pattern.

## Agent Instructions

For each smell detected:

```
file: path/to/file.rb
line: LINE_NUMBER
severity: warning|major|critical
smell: SMELL_NAME
comment: What the smell is and why it's problematic
suggestion: Specific refactoring step with example
```
