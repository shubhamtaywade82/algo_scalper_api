# Options Buying — Completion Plan

Priority-ordered actions derived from `.docs/options_buying_gap_audit.md`.

## P0 — High Risk / Must Close Before Live
1. **7.3 AI Memory / Vector Store** — `docs/options_buying_gap_audit.md` lists as Missing.  
   Action: `app/services/ai/memory_store.rb` + backing vector store (pgvector by default). Risk: without retrieval memory, AI reviews are stateless and learning signal is lost.

2. **11.1 Live Trading Deployment & Runbook** — Missing.  
   Action: `docs/live_trading_runbook.md` with release checklist, feature flags, rollout sequence, kill-switch procedure, rollback steps. Risk: live incident response will be ad hoc.

3. **11.3 Continuous Improvement Loop** — Missing.  
   Action: `docs/continuous_improvement.md` defining review cadence, metric thresholds, alert-to-action path, and release-trigger rules. Risk: drift accumulates without a documented improvement loop.

4. **2.1 Timescale Hypertable + Retention + Compression** — Partial.  
   Action: `db/migrate/` + `docs/database.md`. Verify hypertable setup, add 7-day compression policy and 30-day raw retention. Risk: storage/cost growth and slow time-range queries.

5. **6.1 Emergency Stop Persistence & Correlation Rules** — Implemented but not fully verified.  
   Action: Lock Redis-backed emergency stop state recovery on boot; add correlation concentration tests in `spec/engines/risk_validation_engine_spec.rb`. Risk: state loss across restart or silent concentration breaching.

## P1 — Medium Risk / Hardening & Completeness
6. **1.1 Circuit Breaker + Metrics + Broker API Map**  
   Action: breaker state in `app/services/live/dhan_circuit.rb`, request latency/error counters, and `docs/broker_api.md` endpoint map.

7. **1.2 WebSocket Dedup / Backpressure / Health Endpoint**  
   Action: sequence-based dedup in `app/services/live/market_feed_hub.rb`, `/health/websocket` in `app/controllers/api/health_controller.rb`.

8. **1.3 Data Retention Policy + Exchange Calendar**  
   Action: retention job in `app/jobs/options_buying/data_retention_job.rb`; use `app/lib/market/calendar.rb` for session/holiday logic.

9. **2.2 Candle Calculator Suite + Endpoint Tests**  
   Action: `app/services/engines/calculators/...` for VWAP/OI/RelativeVolume/OpeningRange plus controller tests.

10. **2.3 Option Chain Analytics Calculators**  
    Action: gamma velocity/acceleration, theta decay estimator, IV rank/percentile/trend, OptionFlowScore, and repository tests.

11. **5.2 Missing Strategy Implementations**  
    Action: complete implementations in `app/strategies/` for remaining plugins + tests + `docs/strategies.md`.

12. **9.1 Dashboard API Contract**  
    Action: `docs/api/dashboard.md` or OpenAPI snippet covering endpoints and ActionCable payloads.

13. **10.3 Historical Replay Harness**  
    Action: replay CLI + deterministic fixtures for paper/QA runs.

14. **8.2 Performance Analytics Surface**  
    Action: lean analytics view built on existing `trade_analytic`/`trade_telemetry` models, routed through dashboard.

## P2 — Low Risk / Polish & Docs
15. **0.1 DevOps Hygiene**  
    Action: confirm 80% coverage CI gate, finalize `Makefile`.

16. **0.4 Architecture Boundary Docs**  
    Action: complete `docs/architecture.md`.

17. **0.3/10.2 Seed Data & Paper Reconciliation**  
    Action: instrument master seed script + paper-to-live reconciliation tolerance check.

18. **4.x Engine Hardening Items**  
    Action: regime persistence, order block/FVG detection, thin book/low liquidity detectors.

19. **5.4 Score Persistence + Breakdown Validation**  
    Action: persist `score_breakdown` and exact-math unit tests.

20. **6.2 Telemetry + 9.2 Alert Escalation**  
    Action: request telemetry wrapper around broker calls; add alert suppression/escalation rules.

## Current Status Summary
- Implemented: foundation/config, Dhan REST+WS ingestion base, data platform core, feature indicators, market intelligence engines, strategy interface/base, risk/execution guards, dashboard API+ActionCable, testing/paper infrastructure
- Needs improvement: Phase 2.1 Timescale hardening, Phase 8.2 performance analytics visibility, Phase 9.1 API contract, Phase 10.3 replay harness, Phase 5.2 additional strategies
- Missing: Phase 7.3 AI/vector memory store, Phase 8.1 learning/optimizer, Phase 11.1 live trading runbook/kill-switch, Phase 11.3 continuous improvement process

## Owners / Sequence Recommendation
- Live-readiness gate: items 1–5 in any order, but **do not enable live capital** before 1–4 are closed.
- Parallelize P1 across infra/data and strategy tracks.
- Treat P2 as polish after P0/P1 green.
