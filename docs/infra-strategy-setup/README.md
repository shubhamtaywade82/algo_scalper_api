# Infra & Strategy Platform Upgrade — Documentation Suite

This directory contains the complete plan for upgrading `algo_scalper_api` from a single hardcoded
trading pipeline into a **single-user personal trading operating system**: the platform owns data,
indicators, market structure, risk, execution, and state; strategies become hot-swappable plugins
that consume a read-only `StrategyContext` and emit signal objects.

## Reading order

| # | Document | Purpose |
| --- | ---------- | --------- |
| 00 | [Overview](00_overview.md) | Vision, platform-vs-strategy split, layer map, non-goals, glossary |
| 01 | [Current State & Gap Analysis](01_current_state_and_gap_analysis.md) | Verified inventory of what exists / is dead / is missing |
| 02 | [Target Architecture](02_target_architecture.md) | End-state components, signal flow, process model, event architecture |
| 03 | [Data Layer](03_data_layer.md) | Durable candle persistence, multi-timeframe derivation, backfill |
| 04 | [Strategy Plugin System](04_strategy_plugin_system.md) | Plugin contract, StrategyContext, workspace, registry, versioning |
| 05 | [Runtime Manager](05_runtime_manager.md) | Per-strategy lifecycle, health, crash recovery, supervisor evolution |
| 06 | [Platform Services](06_platform_services.md) | Variables, deploy pipeline, scanner, live logs, replay, scheduler |
| 07 | [API & Frontend Contract](07_api_and_frontend_contract.md) | REST + ActionCable contract; wiring the existing dashboard views |
| 08 | [Migration Roadmap](08_migration_roadmap.md) | Seven phases, reuse-vs-build, verification gates, dependency graph |
| 09 | [Risks & Change Policy](09_risks_and_change_policy.md) | LOCKED-layer carve-outs, risk register, safety invariants |
| 10 | [Greeks & Indicator Streaming](10_greeks_and_indicator_streaming.md) | Deferred optional track (skip decisions recorded) |

## Source material

- `implementation_plan.md` — raw design transcript (DhanHQ Cloud feature inventory, gap analysis,
  plugin-architecture discussion). **Superseded by this suite**; where they conflict, this suite wins.
- `ChatGPT Image Jul 6, 2026, 01_01_16 PM.png` — "Complete E2E Flow" diagram (7 layers + platform services).
- `ChatGPT Image Jul 6, 2026, 01_01_11 PM.png` — "Upgraded Architecture (Single User)" diagram.

## Conventions

- **Decision IDs** — every architectural decision is recorded as `D-<doc>.<n>` (e.g. `D-04.2`) so the
  roadmap, PRs, and future discussions can cite them. Decisions are recorded in the doc that owns the area.
- **Status labels** — components are annotated:
  - `EXISTS` — implemented and in active use.
  - `PARTIAL` — some pieces exist; gaps remain.
  - `DEAD` — code exists but has no callers / references undefined classes; slated for delete-and-rebuild.
  - `NEW` — net-new build.
- **File paths** are repo-relative and were verified against the codebase at the time of writing
  (branch `feat/frontend-architecture-setup`, July 2026).

## Related existing docs (referenced, not duplicated)

- `docs/NEW_ANALYTICS_AND_STRATEGY_LAYER.md` — documents the old `Strategy::` scaffold; **superseded**
  by [04](04_strategy_plugin_system.md) (see banner in that file).
- `docs/config_architecture_roadmap.md` — AlgoConfig hardening roadmap; the variables store in
  [06](06_platform_services.md) reuses its layering idiom.
- `docs/ALPHA_MASTER_PLAN.md` — Alpha engine plan; orthogonal to this platform work.
- `docs/architecture/*` — existing architecture assessments and component maps.
