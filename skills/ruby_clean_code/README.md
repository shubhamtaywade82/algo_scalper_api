# Clean Ruby Skill Pack

## Purpose

Teach coding agents (Claude, Cursor, Codex, Gemini) to produce and review
idiomatic Ruby and Rails code in a production trading system context.

## Skill Domains

| Domain | Skills | When to Load |
|--------|--------|-------------|
| `fundamentals/` | Naming, method size, guard clauses, Ruby idioms, nesting | Always |
| `design/` | SRP, composition, value objects, immutability | Architecture review |
| `rails/` | Models, controllers, services, queries, scopes, callbacks | Rails PR review |
| `smells/` | Ruby smells, Rails smells, architecture smells | Code smell detection |
| `refactoring/` | Extract method, replace conditionals, value objects, dedup | Refactoring sessions |
| `reviews/` | Senior review, PR review, inline comment generation | All code review |
| `trading_systems/` | Determinism, event-driven, strategy purity | Trading-specific review |

## Usage

### Loading skills in an agent prompt

```
Load ruby_clean_code skills, then review the attached code.

Steps:
1. Identify Ruby style violations (fundamentals/)
2. Detect code smells (smells/)
3. Check Rails conventions (rails/)
4. Verify trading system constraints (trading_systems/)
5. Generate inline review comments (reviews/inline_review_comment_generator.md)
```

### Targeted skill loading

```
Load skills: guard_clauses, avoid_deep_nesting, extract_method
Task: refactor the run_for method in signal/engine.rb
```

## Skill File Format

Each skill follows this structure:

```markdown
---
name: skill_name
description: one-line description
tags: [ruby, rails, trading]
applies_to: [models, services, strategies]
severity: [info, warning, major, critical]
---

## Goal
## Principles
## Detection Rules
## Refactoring Guidance
## Examples
## Agent Instructions
```

## Recommended Agent Workflow

```
Before code generation:   load fundamentals/ + design/
Before PR review:         load all skills
Before refactoring:       load smells/ + refactoring/
Before trading code:      load trading_systems/ first, then fundamentals/
```

## Codebase Context

This skill pack is tuned for **algo_scalper_api** — a Rails 8 API for fully
autonomous intraday options scalping on Indian index markets (NIFTY, SENSEX,
BANKNIFTY). Key architectural constraints:

- Services communicate via **direct method calls** (not event bus)
- `ExitEngine` is the **single source of truth** for all exit placement
- Position sizing must go through `Capital::Allocator` — never inline
- WebSocket tick handlers must be **idempotent** and **never write to DB**
- All trading percentages in `algo.yml` use **decimal format** (0.12 = 12%)
