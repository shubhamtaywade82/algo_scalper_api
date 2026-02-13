---
name: ruby
description: Ruby skills bundle. Contains Ruby-oriented SOLID, TDD, clean code, Ruby Style Guide, Rails Style Guide, RSpec/Better Specs, and design-pattern guidance. Use when working with Ruby or Rails code.
---

# Ruby Skills

This directory holds **Ruby-specific** skills. All examples and references use Ruby (and RSpec where tests are shown).

## Available skills

- **solid** — SOLID principles, TDD, clean code, design patterns, architecture. Path: `ruby/solid/`
- **style** — [Ruby Style Guide](https://rubystyle.guide/) conventions (layout, naming, flow of control, methods, classes). Path: `ruby/style/`
- **rails** — [Rails Style Guide](https://rails.rubystyle.guide/) conventions (routing, controllers, models, Active Record, migrations, views, mailers, time). Path: `ruby/rails/`
- **rspec** — RSpec style and best practices from the [RSpec Style Guide](https://rspec.rubystyle.guide/) and [Better Specs](https://www.betterspecs.org/). Path: `ruby/rspec/`

Use **solid** when designing/refactoring Ruby; **style** for Ruby formatting; **rails** for Rails conventions; **rspec** when writing or reviewing specs.

---

## Using these skills for code review

When the user asks to **review code** or **fix issues** against Ruby/Rails/RSpec standards:

1. **Apply the right skills** based on what's being reviewed:
   - **Ruby code (any)** → apply **style** (Ruby Style Guide) and **solid** (SOLID, clean code, design).
   - **Rails code** (controllers, models, routes, migrations, views, mailers) → apply **rails** (Rails Style Guide) in addition to **style** and **solid**.
   - **RSpec specs** → apply **rspec** (RSpec Style Guide + Better Specs) for layout, structure, naming, matchers, doubles, and Rails spec conventions.

2. **Review workflow:**
   - Read the file(s) the user opened or specified.
   - Check against the relevant skill(s): layout, naming, structure, patterns, conventions.
   - List **concrete issues** with file:line or snippet and which guideline they violate (e.g. "Rails: use `find_each` instead of `.all.each`").
   - Group by category (style, rails, rspec, solid) if helpful.
   - Then **propose or apply fixes** per issue (or batch); prefer one logical change per edit.

3. **Fixing issues:**
   - Fix one concern at a time where possible (e.g. style first, then Rails, then RSpec) so the user can review incrementally.
   - For automated style/safety, suggest running **RuboCop** (and `rubocop-rails`, `rubocop-rspec`) and fixing reported offenses; the skills align with RuboCop's rules.

4. **Prompt ideas for the user:**
   - "Review this file using the Ruby and Rails skills and list issues."
   - "Check this spec against the RSpec skill and fix any violations."
   - "Review the app/services directory against solid, style, and rails skills; then fix the issues you find."
