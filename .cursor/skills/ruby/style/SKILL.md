---
name: ruby-style
description: Ruby Style Guide (rubystyle.guide) conventions. Use when writing, formatting, or reviewing Ruby code for layout, naming, flow of control, methods, classes, and idioms. Complements RuboCop.
---

# Ruby Style Guide

This skill applies the [Ruby Style Guide](https://rubystyle.guide/) — the community style guide that [RuboCop](https://github.com/rubocop/rubocop) is based on. Use when writing or reviewing Ruby for consistency and readability.

## Guiding principle

> "Programs must be written for people to read, and only incidentally for machines to execute."

Consistency within a project matters more than strict adherence; when in doubt, match surrounding code.

---

## Source code layout

- **Encoding:** UTF-8.
- **Indentation:** Two spaces (no hard tabs).
- **Line length:** Prefer 80 characters; teams may use up to 120.
- **No trailing whitespace.** End files with a newline.
- **No `;`** to terminate statements.
- **One expression per line** (except e.g. `puts 'a', 'b'`).
- **Spaces around operators** (e.g. `sum = 1 + 2`). No space after `!`, inside range literals (`1..3`), or after `{`/before `}` in interpolations.
- **Safe navigation:** Avoid long `&.` chains; prefer explicit checks or delegation.
- **Empty lines:** One between method definitions; one around `private`/`protected`; none around method/class/module bodies.
- **Multi-line method chains:** Use leading `.` or trailing `.` consistently (leading `.` preferred: continue on next line with `.method`).
- **Method args alignment:** Align multi-line arguments or use single indent; be consistent.

---

## Naming

- **Identifiers in English.** `snake_case` for symbols, methods, variables. `CapitalCase` for classes and modules (e.g. `SomeClass`, `SomeXML`). `SCREAMING_SNAKE_CASE` for other constants.
- **Files and directories:** `snake_case` (e.g. `hello_world.rb`). One class per file; filename mirrors class name.
- **Predicate methods:** end with `?` (e.g. `empty?`). Avoid prefixing with `is_`, `does_`, `can_`.
- **Dangerous methods:** end with `!` only when a "safe" counterpart exists (e.g. `update!` vs `update`).
- **Unused variables:** prefix with `_` (e.g. `_unused_var`, or `|_k, v|` in blocks).

---

## Flow of control

- **Prefer iterators over `for`.** Use `each` etc., not `for elem in arr`.
- **No `then`** for multi-line `if`/`unless`/`when`.
- **Prefer ternary** for simple branches: `result = condition ? a : b`. Avoid nested ternaries; use `if/else`.
- **Prefer `case` over `if/elsif`** when comparing the same value. Indent `when` as deep as `case` (outdented).
- **Use `!` instead of `not`.** Avoid double negation `!!` unless you need an explicit boolean.
- **Use `&&`/`||` in conditions.** Reserve `and`/`or` for control flow (e.g. `raise or return`) if at all.
- **Prefer modifier form** for single-line: `do_something if condition`. Avoid modifier at end of long blocks.
- **Prefer `unless` over `if !`.** Don't use `else` with `unless`; rewrite with positive case first.
- **No parentheses** around condition of `if`/`while`/`unless`.
- **Prefer `loop do` with `break`** over `while true` or `begin...end while`.
- **Avoid explicit `return`** where the last expression is the return value.
- **Avoid explicit `self`** except for writers (`self.foo =`), reserved-word method names, or overloaded operators.
- **Guard clauses:** Prefer early return/`next` over deep nesting. Use guard clauses to bail on invalid input.

---

## Exceptions

- **Prefer `raise` over `fail`.** Use two-arg form: `raise SomeException, 'message'`. Don't specify `RuntimeError` explicitly in two-arg `raise`.
- **Don't return from `ensure`.** Use implicit `begin` (rescue in method). Don't suppress exceptions; handle or re-raise. Don't use exceptions for flow of control.
- **Rescue specific exceptions** (e.g. `StandardError`, `IOError`), not bare `Exception`. Put more specific rescues first.

---

## Methods

- **Keep methods short** (e.g. under 10 LOC). Prefer keyword arguments over long option hashes or many positional args.
- **Optional/boolean args:** Put required params first; use keyword args for optional/boolean (e.g. `def foo(bar:, baz: false)`).
- **Omit parentheses** for `def` with no params; use them when there are params. Omit for method calls with no args and for "keyword" methods (e.g. `puts`, `raise`) per project convention.
- **Use `...` for argument forwarding** when delegating (Ruby 2.7+). Use `&` for block forwarding (Ruby 3.1+).

---

## Classes and modules

- **Consistent structure:** extend/include/prepend, inner classes, constants, attr macros, other macros, `def self.`, `initialize`, public methods, then `protected`/`private`.
- **One mixin per line:** `include Foo` and `include Bar`, not `include Foo, Bar`.
- **Prefer modules with `module_function`** for namespaces of class methods over classes with only `self.` methods.
- **Duck typing:** Prefer interfaces (duck typing) over inheritance. No class variables (`@@`); use class instance variables or dependency injection.
- **Access modifiers:** Use `private`/`protected`; indent them like method definitions with one blank line above and below.
- **Define `to_s`** for domain objects. Use `attr_reader`/`attr_accessor`; avoid `attr`. Prefer `Struct.new` or `Data.define` for simple value holders (don't extend them).
- **Liskov and SOLID:** Subtypes must be substitutable; keep classes SOLID.

---

## Comments and annotations

- **Prefer self-documenting code.** Comment only when explaining *why*. Use English. One space after `#`. Capitalize and punctuate full sentences.
- **Annotations:** Place above the relevant line. Format as `KEYWORD: note` (e.g. `TODO:`, `FIXME:`, `OPTIMIZE:`, `HACK:`, `REVIEW:`).

---

## Collections and strings

- **Use `[]` and `{}`** for literals. Prefer `%w[]`/`%i[]` for word/symbol arrays. Prefer `key:` over `:key =>` in hashes.
- **Use `Hash#key?`/`value?`** not `has_key?`/`has_value?`. Use `fetch` for required keys; use block form for expensive defaults.
- **Prefer `map`/`find`/`select`/`reduce`/`include?`/`size`** over `collect`/`detect`/`find_all`/`inject`/`member?`/`length` where it helps readability.
- **Use `any?`/`none?`/`one?`** instead of `count > 0` etc. Don't use `count` when `size`/`length` is enough (e.g. for Hash).
- **Strings:** Prefer interpolation: `"#{a} #{b}"`. Use single quotes when no interpolation/special chars. Use `<<` for building large strings. Use `\A` and `\z` for full-string regex (not `^`/`$`).

---

## Other

- **Use `require_relative`** for internal code; `require` for external libs. Omit `.rb` in `require`/`require_relative`.
- **Prefer `predicate?` and `Comparable#between?`** over manual comparisons where it clarifies intent.
- **Don't mutate params** unless that's the method's purpose. Avoid more than ~3 levels of block nesting.
- **Prefer `public_send`** over `send`; prefer `__send__` if the name might be overridden.

---

## Reference

- [Ruby Style Guide](https://rubystyle.guide/) — full guide
- [RuboCop](https://github.com/rubocop/rubocop) — linter and formatter based on this guide
- [Rails Style Guide](https://github.com/rubocop/rails-style-guide) · [RSpec Style Guide](https://github.com/rubocop/rspec-style-guide) — complementary guides
