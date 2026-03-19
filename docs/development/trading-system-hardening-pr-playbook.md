# Trading System Hardening PR Playbook

## Purpose

This runbook defines the branch strategy and PR execution plan for production
hardening of the trading system.

Non-negotiable goal:

- Deterministic, low-latency, observable trading system
- Reject any change that violates this goal, even if it follows generic Rails
  conventions

## Hard Rules

- Never commit directly to `main`
- Never open multi-feature PRs
- Never mix refactor and feature behavior changes in one PR
- Every PR must be independently deployable and independently revertable
- All PRs target `develop` (never `main`)
- Validate in paper mode before merge

## Branch Topology

Base branches:

- `main` (production)
- `develop` (integration)

Feature branches (in merge order):

1. `feat/query-layer-foundation`
2. `feat/model-hardening`
3. `feat/exit-engine-deterministic`
4. `feat/risk-layer-enforcement`
5. `feat/performance-indexing`
6. `feat/observability-structured-logs`

## Two-Week Timeline

### Phase 1 (Day 1-3): Query Layer Foundation

Branch: `feat/query-layer-foundation`

Goals:

- Add canonical scopes for reused filters
- Introduce query objects for entry, exit, and risk
- Remove repeated status filters from services in scoped areas

Deliverables:

- `app/queries/positions/active_for_exit.rb`
- `app/queries/positions/risk_candidates.rb`
- `app/queries/derivatives/atm_options.rb`
- `app/queries/signals/valid_entries.rb`
- Scope updates in `PositionTracker` and `Derivative`

Acceptance:

- No repeated `where(status: ...)` in touched services
- Exit path uses query object as single source
- Query logic is intention-revealing and test-covered

### Phase 2 (Day 3-5): Model Hardening

Branch: `feat/model-hardening`

Goals:

- Make association optionality explicit
- Ensure bidirectional associations where needed
- Keep models focused on associations, validations, and small predicates

Acceptance:

- Every `belongs_to` has explicit `optional: true/false`
- `includes(:instrument, :derivative)` works in core flows
- No trading orchestration in models

### Phase 3 (Day 5-8): Exit Engine Stabilization

Branch: `feat/exit-engine-deterministic`

Goals:

- Centralize exit decision path
- Enforce idempotent exit execution
- Remove hidden/model-triggered execution paths

Acceptance:

- Same position cannot exit twice
- Exit decisions are deterministic for same inputs
- No callback-driven trading actions

### Phase 4 (Day 8-10): Risk Layer Enforcement

Branch: `feat/risk-layer-enforcement`

Goals:

- Enforce daily loss circuit breaker
- Enforce per-trade risk cap
- Integrate enforcement into entry/exit flow safely

Acceptance:

- New entries blocked after daily threshold breach
- Breach events are logged with reason and thresholds
- Risk checks are deterministic and test-covered

### Phase 5 (Day 10-12): Performance + Indexing

Branch: `feat/performance-indexing`

Goals:

- Add critical indexes for trading hot paths
- Eliminate avoidable sequential scans in hot queries
- Replace non-batch iteration where appropriate

Target indexes:

- `position_trackers(status)`
- `position_trackers(created_at)`
- `position_trackers(instrument_id)`
- `derivatives(expiry_date, strike, option_type)`
- `candles(candle_series_id, time)`

Acceptance:

- No hot-path query regressions
- Query plans improve for critical filters
- No DB calls in real-time tick loop

### Phase 6 (Day 12-14): Observability

Branch: `feat/observability-structured-logs`

Goals:

- Add structured logs for entry/exit/risk/order lifecycle
- Add failure and retry visibility
- Add metrics for trading quality and execution health

Acceptance:

- Decision logs include position, reason, and market context
- API/order responses are traceable by correlation id
- Minimal noise, high signal logs in production

## PR-by-PR Blueprint

### PR 1: Query Layer Foundation

Branch: `feat/query-layer-foundation`  
PR title: `refactor: add query layer for deterministic trade selection`

Scope:

- Add scopes and query objects
- Replace direct `.where` in selected entry/exit/risk service paths
- No behavior change intended

Validation checklist:

- Exit candidate list matches baseline behavior
- Entry candidate list matches baseline behavior
- Query objects are covered by focused specs

### PR 2: Model Hardening

Branch: `feat/model-hardening`  
PR title: `refactor: enforce explicit associations and model boundaries`

Scope:

- Explicit `optional:` flags
- Missing inverse/bidirectional associations
- Remove non-model responsibilities

Validation checklist:

- Eager loading works in core services
- No N+1 warnings in touched flows
- No callback-based execution side effects

### PR 3: Exit Engine Determinism (High Risk)

Branch: `feat/exit-engine-deterministic`  
PR title: `refactor: make exit execution deterministic and idempotent`

Scope:

- Route exit candidate selection via query object
- Add idempotency guard before exit placement
- Consolidate decision path

Validation checklist:

- No duplicate exits under re-run/retry
- SL/TP/timeout paths remain correct
- Paper trading shows expected behavior parity

### PR 4: Risk Layer Enforcement

Branch: `feat/risk-layer-enforcement`  
PR title: `feat: enforce daily and per-trade risk constraints`

Scope:

- Daily loss cap enforcement
- Per-trade risk enforcement
- Entry blocking on circuit-break conditions

Validation checklist:

- Entries stop after breach
- Breach state is observable and auditable
- Recovery/reset path is explicit and safe

### PR 5: Performance + Indexing

Branch: `feat/performance-indexing`  
PR title: `perf: add trading-critical indexes and query optimizations`

Scope:

- Migration with trading indexes
- Hot-path query cleanup
- Batch iteration improvements

Validation checklist:

- Migration is reversible and safe
- Query latency improves on key paths
- No functional behavior changes

### PR 6: Observability

Branch: `feat/observability-structured-logs`  
PR title: `feat: add structured logs and metrics for trade lifecycle`

Scope:

- Structured logging contract
- Entry/exit/risk/order decision events
- Core execution metrics

Validation checklist:

- Every critical decision emits structured logs
- Failure and retry paths are traceable
- Log format is consistent across services

## Standard PR Lifecycle

### 1) Branch creation

```bash
git checkout develop
git pull origin develop
git checkout -b <feature-branch>
```

### 2) Development

- Keep commits small and single-purpose
- Separate refactor commits from behavior-changing commits
- Prefer deletion over additive complexity

### 3) Local verification

Mandatory checks before push:

```bash
bundle exec rspec <focused-specs>
bundle exec rubocop <changed-paths>
```

Recommended:

```bash
bundle exec rspec
bin/brakeman --no-pager
```

Runtime validation (paper mode):

- Verify entries, exits, and risk responses for touched area
- Confirm no duplicate order placements
- Confirm no DB activity in tick loop for real-time changes

### 4) Push and open PR

```bash
git push -u origin <feature-branch>
```

PR target:

- Base branch: `develop`
- Merge strategy: squash merge

### 5) Review gates

Review dimensions:

1. Functional correctness
2. Determinism and idempotency
3. Query consistency (single-source filters)
4. Performance and latency impact
5. Observability completeness

### 6) Post-merge validation on `develop`

- Re-run focused paper-mode validation
- Monitor logs for regressions in touched flows
- Validate websocket lifecycle and order execution traces

### 7) Release

- Promote `develop` to `main` only after all six PRs pass validation

## Definition of Done per PR

- Scope limited to one layer and one intent
- Specs added/updated for changed behavior
- Lint passes for changed paths
- Paper-mode behavior validated
- Rollback path documented in PR notes
- No locked-infrastructure changes unless critical scenario applies

## Risk Controls and Rollback

Feature flag recommendation for high-risk paths:

```ruby
if Feature.enabled?(:deterministic_exit_engine)
  ExitEngine::DeterministicProcessor.call(position)
else
  ExitEngine::LegacyProcessor.call(position)
end
```

Rollback policy:

- Every PR must be revertable in isolation
- No hidden cross-branch dependencies
- If runtime behavior diverges from expected deterministic behavior, revert first
  and analyze second

## Structured Logging Contract (Minimum)

Example:

```json
{
  "event": "exit_triggered",
  "position_id": 123,
  "ltp": 152.0,
  "reason": "SL_HIT",
  "timestamp": "2026-03-19T10:15:30Z"
}
```

Required event families:

- Entry decision
- Exit trigger and execution
- Risk gate breach and enforcement
- Order API request/response
- WebSocket connectivity and subscription lifecycle

## Final Priority Order

Execute strictly in this order:

1. Query layer (scopes + query objects)
2. Exit engine determinism and idempotency
3. Risk enforcement
4. WebSocket/LTP cache integrity checks
5. Index and performance hardening
6. Observability coverage

If a proposed change conflicts with deterministic behavior, low latency, or
observability, reject it and redesign.
