---
name: ruby_code_review
description: Perform a senior-level Ruby code review covering readability, design, safety, and performance
tags: [review, ruby, senior, checklist]
applies_to: [all]
severity: [info, warning, major, critical]
---

## Goal

Act as a senior Ruby engineer reviewing a PR or file. Produce actionable,
specific feedback covering all quality dimensions — not just style.

## Review Checklist

### 1. Correctness (critical)

- [ ] Does the code do what the PR description / tests claim?
- [ ] Are edge cases handled: nil, empty collection, zero, negative number?
- [ ] Are exceptions raised for truly exceptional conditions only?
- [ ] Are rescued exceptions specific (not bare `rescue Exception`)?
- [ ] Is thread safety preserved in shared state? (Critical in trading daemons)

### 2. Naming (warning)

- [ ] Do all names reveal intent?
- [ ] Are predicates named with `?`?
- [ ] Are mutating methods named with `!`?
- [ ] Are collections named in plural?
- [ ] No abbreviations, generic names, or misleading names?

### 3. Method Quality (major)

- [ ] Methods are ≤ 15 lines?
- [ ] Methods perform one task?
- [ ] No mixed abstraction levels?
- [ ] Guard clauses used instead of nested ifs?

### 4. Class Design (major)

- [ ] Class has a single responsibility?
- [ ] Class name matches its behaviour?
- [ ] No inappropriate intimacy between classes?
- [ ] Dependencies are injected, not hardcoded?
- [ ] No God objects?

### 5. Ruby Idioms (warning)

- [ ] Safe navigation `&.` used for optional chaining?
- [ ] `filter_map` instead of `select + map`?
- [ ] `fetch` with defaults instead of `|| default`?
- [ ] No redundant nil checks: `if x; x; else; y` → `x || y`?
- [ ] Frozen string literal comment present?

### 6. Performance (warning)

- [ ] No N+1 queries (check loops over associations)?
- [ ] `includes`/`eager_load` used where associations accessed?
- [ ] No repeated heavy computations (memoize with `||=`)?
- [ ] No collection literals recreated inside loops?
- [ ] `select { }.first` → `find { }`; `select { }.count` → `count { }`?

### 7. Security (critical)

- [ ] No raw string interpolation in SQL (`where("name = '#{name}'")`)?
- [ ] No `eval`, `send` with user input?
- [ ] No secrets or credentials in code?
- [ ] Mass assignment protected by `permit`?
- [ ] No command injection via `system`, backtick, `Open3.capture`?

### 8. Error Handling (major)

- [ ] Errors are logged with context (class, message, relevant IDs)?
- [ ] Services return result objects, not rescue-and-return-nil?
- [ ] No silent swallowing of errors in trading-critical paths?

### 9. Tests (major)

- [ ] New behaviour has test coverage?
- [ ] Tests describe behaviour, not implementation?
- [ ] No testing of private methods directly?
- [ ] Tests are isolated (no shared mutable state between examples)?

### 10. Domain Consistency (major — trading systems)

- [ ] Percentage values use decimal format (0.12 = 12%)?
- [ ] No order placement outside `Orders::Gateway`?
- [ ] No position sizing outside `Capital::Allocator`?
- [ ] No exit placement outside `ExitEngine`?
- [ ] Tick handlers are idempotent?
- [ ] No DB writes from WebSocket tick handlers?

## Output Format

For each issue found:

```
severity: info|warning|major|critical
file: path/to/file.rb
line: LINE
issue: Brief description of the problem
suggestion: Specific fix with code example if applicable
```

## Review Tone Guidelines

- Be specific — "line 42 has an N+1 because..." not "there might be N+1 issues"
- Be constructive — explain the *why*, not just the *what*
- Acknowledge good patterns — note what's done well
- Prioritise — critical > major > warning > info
- One fix suggestion per issue — don't overwhelm with alternatives
