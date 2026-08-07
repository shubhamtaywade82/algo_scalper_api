# Requirements — Options Buying Autonomous & Automated Delivery

This file is the canonical requirements register for completing naked-options-buying
delivery against `Options_Buying_Plan/implementation_plan_detailed` in the
`algo_scalper_api` repository.

## Phase 0 — Foundation & Tooling
Status: staged. Covers repo bootstrap, Ruby lock, RuboCop, Brakeman, bundler-audit,
GitHub Actions CI, Docker multi-stage build, compose, pre-commit gates, docs scaffold,
database_consistency checks, typed config, DhanHQ broker init, Redis pools,
Solid Queue wiring, job base class, migration rollback helpers.

## Phase 1 — DhanHQ Integration / Data Ingestion
Status: staged. Covers REST client, instrument manager, WebSocket manager, tick
normalization, option chain ingestion, data quality checks, backfill jobs.

## Phase 2 — Data Platform
Status: staged. Covers TimescaleDB extension, tick hypertable, continuous aggregates,
option chain snapshots, depth snapshots, retention policies, COPY import,
query/query availability in repo.

## Phase 3 — Feature Engineering
Status: staged. Covers underlying indicators, option features, technical analysis
layer, feature composition, caching source.

## Phase 4 — Market Intelligence
Status: staged. Covers market context engine, regime engine, structure engine,
momentum engine, liquidity engine, option intelligence engine, detectors, and
context/snapshot builders in `app/services/market*` and `app/services/smc/*`.

## Phase 5 — Strategy & Decision
Status: staged. Covers strategy interface, implementations, strike selection,
trade scoring, state machines, orchestrator/runner/adapter.

## Phase 6 — Risk, Execution & Position Management
Status: staged. Covers entry_guard_pipeline, risk rules (rule context/engine/factory),
exit execution, position state machines, live risk manager, paper gateway,
slippage model, fill validation, recovery paths.

## Phase 7 — AI Gateway
Status: staged-outside vector memory. Covers AI snapshot prompt builder, generative
market gate, HITL workflow. Memory/vector note still pending.

## Phase 8 — Learning & Optimization
Status: staged. Covers autonomous optimizer, backtest-to-config applier,
auto experiment runner, results store, metrics/strategy evaluator,
single-indicator and trailing optimizers.

## Phase 9 — Dashboard & Ops
Status: staged. Covers API controllers and ActionCable channels for dashboard/positions,
Telegram notification client, incident/alert flows, telemetry events.

## Phase 10 — Testing/QA
Status: staged (from file inventory). Covers model/service/controller/integration/smoke
tests plus backtest/replay rubesque harness.

## Phase 11 — Live Trading / Monitoring / Improvement
Status: to be verified after repo map. Covers live deployment posture,
product observability (SLOs/alerts), feedback loop from live PnL into config.

## Authoritative Sources
- Plan manifest: `Repository: /home/nemesis/project/trading-workspace/options_buying_plan`
- Repo root: `Repository: /home/nemesis/project/trading-workspace/algo_scalper_api`
- Audit cache: `File: /home/nemesis/project/trading-workspace/algo_scalper_api/.docs/options_buying_gap_audit.md`
- Completion plan: `File: /home/nemesis/project/trading-workspace/algo_scalper_api/.docs/options_buying_completion_plan.md`
- Review cache: `File: /home/nemesis/project/trading-workspace/algo_scalper_api/.docs/options_buying_implementation_review.md`
