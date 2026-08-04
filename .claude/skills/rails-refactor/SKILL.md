---
name: rails-refactor
description: >
  Safe, verified refactoring execution pipeline for Rails applications.
  Enforces behavior preservation (behavior_before == behavior_after), incremental micro-changes,
  RuboCop checks, and RSpec test suite verification.
---

# Rails Refactor Execution Pipeline

This skill guides agents through executing safe, behavior-preserving refactorings on Ruby on Rails codebases.

---

## Execution Workflow

### Step 1: Run Baseline Verification
Before touching any code, run the existing test suite for the component:
```bash
bundle exec rspec spec/services/orders/place_service_spec.rb
```
*Requirement*: All tests MUST pass 100% green before proceeding.

### Step 2: Establish Implementation Plan
Identify exact micro-steps (e.g. 1. Extract method `calculate_margin`, 2. Create gateway file `DhanGateway`, 3. Move API calls).

### Step 3: Atomic Micro-Refactor Loop
For each step:
1. Apply code edit.
2. Run target RSpec spec immediately.
3. Run RuboCop on modified files (`bundle exec rubocop <file>`).
4. If specs fail or RuboCop reports syntax errors, fix or revert immediately.

### Step 4: Full Suite Verification
Run full test suite for affected domain:
```bash
bundle exec rspec spec/
```

### Step 5: Generate Architectural Diff Summary
Output summary comparing before vs after metrics:
- LOC reduction
- Branch complexity reduction
- Resolved smells
- Passing test count
