# Infrastructure roadmap - market-data workstream

Phases 0-6 of [`UNIFIED_SYSTEM_PLAN.md`](UNIFIED_SYSTEM_PLAN.md) (signal routing, supervision,
governance) remain the master schedule. This roadmap layers the **market-data / analytics / risk**
gaps on top, with their own gates. Nothing here promotes a trading strategy; everything here makes
the infrastructure able to *measure and protect* whichever strategy earns its place.

## Already done (verified in code)

- Token authority: agent fetches `GET /api/dhan/token`, never logs in (agent PR #14, merged).
- Shared chain rate budget: byte-identical Lua on `dhan:rate_limit:option_chain` (both sides).
- Unified runtime: `deploy/unified` compose stack (PG roles, Redis, Rails web/jobs/trading/dashboard,
  agent container) with bring-up checklist and staged rollout.
- Plan + corrections appendix written from a real docker bring-up (2026-11-18).
- Contracts seed: 8 JSON Schemas + fixtures in [`contracts/`](../../contracts/README.md) (this PR).
- **G1 (shared chain truth) implemented end-to-end (this PR)**:
  - Rails: `Options::ChainContext` + `Options::ChainContextPublisher` publish
    `chain-context/1` to Redis `dhan:chain:context:<INDEX>` from the ChainWatch broadcast cycle
    (TTL 15 s, publish failures isolated from the chain watch loop) + specs.
  - Agent: `src/options/sharedChainContext.ts` (zod-validated, 10 s freshness) wired into the
    OI-resistance gate (`underlyingAgent.ts` `sharedChainContext` dep; shared-first, local fallback)
    + 13 tests; full agent suite 1658/1658 green.
  - Backend PCR, walls, ATM straddle, expected range and sentiment score now have one shared
    implementation (Rails) instead of a frontend-only dashboard calc.
  - Remaining from G1: payout-minimising max pain (G1b) and `json_schemer` CI wiring (G0).

## Workstream items

| ID | Item | Size | Gate |
|---|---|---|---|
| G7 | **Arm the analytics jobs**: add `IvSnapshotJob` + `PreMarketIvBaselineJob` to `config/recurring.yml` (optionally `VixGateJob` for periodic re-evaluation; boot + guard evaluation already cover VixGate). Today the IV-rank guards are no-ops by their own comment. | **S - do immediately** | `iv_snapshots` rows appear daily; `iv_history:*` accumulates; `iv_vol_gate_guard` / `selling_iv_rank_guard` become active; `iv-snapshot/1` rank non-null after 30+ samples |
| G1b | **True max pain**: payout-minimising strike (the dashboard's current "max pain" is just the max-call-OI strike) in `Options::ChainContext`, published with the context | S | Max pain recomputable from published OI; dashboard reads from the API |
| G0 | **Wire contract CI**: run `contracts/` fixtures through this repo's validator (`json_schemer`) in CI; the agent vendors `contracts/` and a drift job fails on any diff vs this repo's `main` | S | Both CIs fail on a deliberate schema break; fixtures pass on both stacks |
| G4 | **Canonical chain snapshots (S3)**: `dhan:chain:{sid}:{expiry}` writer/reader on both sides, fixture-validated normalisers, per-reader freshness | M | Dhan chain calls per hour measurably reduced at equal coverage; zero freshness regressions in the agent's gate |
| G5 | **Rate-budget extension (S2)**: agent joins `data_api`/`quote_api` Redis keys; cross-repo Lua contract test | S | Both implementations produce identical spacing against one Redis in CI |
| G2 | **Advisory VIX/IV consumption by the agent**: journal-first (VIX tercile + IV rank at entry), then Time Machine validation of any sizing modulation; IV endpoint serves `iv-snapshot/1` (VIX endpoint already exists) | M | Research labels appear in the agent journal with zero live-behaviour change; any live rule change passes its pre-registered replay first |
| G3 | **Position-level Greeks aggregation**: `greeks-snapshot/1` publisher in Rails (broker-first, BSM fallback, provenance-tagged); agent displays, decides nothing (yet) | M | Entry delta/theta/vega per agent position shown in dashboard; provenance tag visible |
| G6 | **Candle bridge (S17.2)**: export Rails `candles` to the agent's Time Machine dataset format | L (Phase 6) | One hypothesis replayed on both engines from identical data |

Suggested order: **G7 first (hours, not days)**, then G0 -> G1 -> G4 -> G5 (they compound: contracts
make snapshots testable, snapshots make analytics cheap), G2/G3 in parallel once G4 lands.

## Sequencing with the plan's phases

| Plan phase | Market-data items that belong in it |
|---|---|
| Phase 1 - shared foundation | G7 (independent, do now), G0, G4, G5 (+ plan S5 WS budget, S13 shared env, S14 supervision, S11 alerts, S15 snapshot, S1 hardening) |
| Phase 2 - visibility | G1, G3 (+ plan S7 ledger read-back, S12 dashboard pages) |
| Phase 3 - paper signal intake | none (plan's own scope; the `trade-intent/1` and `intent-outcome/1` schemas in `contracts/` are its starting point) |
| Phase 4 - governance & drills | margin/netting answer; capital split config |
| Phase 5 - sandbox/live promotion | gated by evidence, not calendar; G2's live rules only here, if ever |
| Phase 6 - consolidation | G6; paper venue unification decision |

## Definition of done (infrastructure, not profitability)

- One canonical chain per (underlying, expiry), fixture-validated on both stacks, halved chain spend.
- Every agent entry journals: VIX tercile, IV rank, entry delta/theta/vega, PCR, max-pain distance.
- IV and VIX gates on the Rails side are actually armed (jobs scheduled, history accumulating).
- Dashboards show both books' positions, exits-in-force, and all four give-back layers side by side.
- All Phase 4 drills pass and are documented in the runbook.
- A dead agent, a dead Rails, or a dead Redis never produces a wrong entry - only a stopped one.
