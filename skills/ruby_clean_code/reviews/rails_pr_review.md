---
name: rails_pr_review
description: Full Rails PR review covering migrations, models, controllers, services, jobs, and tests
tags: [rails, pr, review, checklist]
applies_to: [all]
severity: [info, warning, major, critical]
---

## Goal

Review a complete Rails PR as a senior Rails engineer — covering schema
changes, model behavior, service design, query safety, job reliability,
and test quality.

## PR Review Checklist

### Migrations (critical)

- [ ] Migration is reversible (has `down` or uses reversible block)?
- [ ] No destructive operation without explicit confirmation (`remove_column`,
  `drop_table`)?
- [ ] Index added for every foreign key and frequently queried column?
- [ ] Column defaults set at DB level, not just in Ruby?
- [ ] Migration file name describes what it does?
- [ ] No data migration mixed with schema migration?

```ruby
# Good migration
class AddExpiresAtToPositionTrackers < ActiveRecord::Migration[8.0]
  def change
    add_column :position_trackers, :expires_at, :datetime
    add_index  :position_trackers, :expires_at
  end
end
```

### Models

- [ ] Validations cover all required fields?
- [ ] Scope uses lambda syntax (not stale time)?
- [ ] No callbacks that call external services?
- [ ] No business logic that belongs in a service?
- [ ] `frozen_string_literal: true` present?
- [ ] New associations have appropriate `dependent:` option?

### Controllers

- [ ] Action is ≤ 10 lines?
- [ ] Strong parameters for all write operations?
- [ ] Authentication/authorization before action?
- [ ] Responds with appropriate HTTP status codes?
- [ ] No business logic in action body?

### Services

- [ ] Single public `call` method?
- [ ] Dependencies injected, not hardcoded?
- [ ] Returns consistent result object?
- [ ] Transactional where multiple records are mutated?
- [ ] Error paths return `ServiceResult.fail(reason)`, not nil?

### Jobs (Solid Queue)

- [ ] Job inherits from `ApplicationJob`?
- [ ] `retry_on` configured for transient errors?
- [ ] `discard_on` configured for permanent errors?
- [ ] Job is idempotent (safe to retry)?
- [ ] Heavy logic delegated to a service, not inline in `perform`?
- [ ] No synchronous external calls that could block the queue?

### Queries / Performance

- [ ] No N+1 queries in new code?
- [ ] New indexes added for query patterns introduced?
- [ ] `count` vs `size` vs `length` used correctly?
- [ ] Pagination for endpoints returning potentially large collections?

### Security

- [ ] No SQL injection risk (no string interpolation in `where`)?
- [ ] No mass assignment without explicit `permit`?
- [ ] Sensitive data not logged?

### Tests

- [ ] Happy path covered?
- [ ] Error paths covered?
- [ ] Edge cases: nil input, empty collection, boundary values?
- [ ] New factories/fixtures provided for new models?
- [ ] No `sleep` in tests?

### Trading-Specific

- [ ] New config values use decimal percentages?
- [ ] New services registered in `TradingSystem::Bootstrap` if they run in daemon?
- [ ] New recurring jobs added to `config/recurring.yml`?
- [ ] WebSocket handlers are idempotent?
- [ ] Capital sizing goes through `Capital::Allocator`?

## Review Output Format

```
## Summary
[1-3 sentences about what the PR does and overall quality]

## Critical Issues
[Must fix before merge]

## Major Issues
[Should fix before merge]

## Warnings
[Nice to fix, not blocking]

## Suggestions
[Optional improvements]

## Positives
[What's done well]
```
