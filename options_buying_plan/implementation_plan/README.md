# AlgoScalperApi — Implementation Plan Index

**Total Milestones:** 35 | **Total Tasks:** 312 | **Estimated Duration:** 24–32 weeks (1–2 devs)

---

## Directory Structure

```
implementation_plan/
├── phase_00_foundation/                    # Phase 0 — Foundation & Tooling (4 milestones)
├── phase_01_dhanhq_integration/            # Phase 1 — DhanHQ Integration (3 milestones)
├── phase_02_data_platform/                 # Phase 2 — Data Platform (3 milestones)
├── phase_03_feature_engineering/           # Phase 3 — Feature Engineering (2 milestones)
├── phase_04_market_intelligence/           # Phase 4 — Market Intelligence Engines (6 milestones)
├── phase_05_strategy_decision/             # Phase 5 — Strategy & Decision Layer (4 milestones)
├── phase_06_risk_execution/                # Phase 6 — Risk & Execution (3 milestones)
├── phase_07_ai_gateway/                    # Phase 7 — AI Gateway (3 milestones)
├── phase_08_learning_optimization/         # Phase 8 — Learning & Optimization (2 milestones)
├── phase_09_dashboard_operations/          # Phase 9 — Dashboard & Operations (2 milestones)
├── phase_10_testing_qa/                    # Phase 10 — Testing & Quality Assurance (3 milestones)
├── phase_11_live_trading/                  # Phase 11 — Live Trading & Operations (3 milestones)
└── README.md                               # This file
```

---

## Phase Summary

| Phase | Milestones | Tasks | Focus Area |
|-------|-----------|-------|------------|
| 0 — Foundation | 0.1–0.4 | 47 | Tooling, config, schema, services |
| 1 — DhanHQ Integration | 1.1–1.3 | 50 | REST, WebSocket, ingestion |
| 2 — Data Platform | 2.1–2.3 | 37 | TimescaleDB, candles, option chain |
| 3 — Feature Engineering | 3.1–3.2 | 32 | Indicators, Greeks features |
| 4 — Market Intelligence | 4.1–4.6 | 64 | 6 engines: context, regime, structure, momentum, liquidity, option |
| 5 — Strategy & Decisions | 5.1–5.4 | 38 | Strategies, strike selection, scoring |
| 6 — Risk & Execution | 6.1–6.3 | 45 | Risk, execution, position management |
| 7 — AI Gateway | 7.1–7.3 | 39 | Gateway, agents, vector memory |
| 8 — Learning | 8.1–8.2 | 26 | Learning engine, performance analytics |
| 9 — Dashboard | 9.1–9.2 | 25 | Real-time dashboard, alerts |
| 10 — Testing | 10.1–10.3 | 34 | Tests, paper trading, replay |
| 11 — Live Trading | 11.1–11.3 | 36 | Deployment, monitoring, improvement |
| **Total** | **35** | **312** | |

---

## Milestone Index

### Phase 0 — Foundation & Tooling

| Milestone | File | Tasks | Goal |
|-----------|------|-------|------|
| **0.1** | [milestone_0_1_repository_devops.md](phase_00_foundation/milestone_0_1_repository_devops.md) | 15 | Production-ready Rails environment with strict quality gates |
| **0.2** | [milestone_0_2_configuration_environment.md](phase_00_foundation/milestone_0_2_configuration_environment.md) | 12 | Environment-aware, type-safe configuration using dry-rb patterns |
| **0.3** | [milestone_0_3_domain_model_database.md](phase_00_foundation/milestone_0_3_domain_model_database.md) | 20 | Core domain entities for all engines |
| **0.4** | [milestone_0_4_core_service_architecture.md](phase_00_foundation/milestone_0_4_core_service_architecture.md) | 16 | Clean, testable service layer with dependency injection |

### Phase 1 — DhanHQ Integration

| Milestone | File | Tasks | Goal |
|-----------|------|-------|------|
| **1.1** | [milestone_1_1_rest_client_instrument_manager.md](phase_01_dhanhq_integration/milestone_1_1_rest_client_instrument_manager.md) | 18 | Reliable, resilient broker REST API wrapper |
| **1.2** | [milestone_1_2_websocket_manager.md](phase_01_dhanhq_integration/milestone_1_2_websocket_manager.md) | 17 | Fault-tolerant, auto-recovering market data streams |
| **1.3** | [milestone_1_3_data_ingestion_pipeline.md](phase_01_dhanhq_integration/milestone_1_3_data_ingestion_pipeline.md) | 14 | Raw market data → normalized domain objects → persistent storage |

### Phase 2 — Data Platform

| Milestone | File | Tasks | Goal |
|-----------|------|-------|------|
| **2.1** | [milestone_2_1_tick_store_timeseries.md](phase_02_data_platform/milestone_2_1_tick_store_timeseries.md) | 12 | High-performance tick storage with TimescaleDB |
| **2.2** | [milestone_2_2_candle_builder_historical.md](phase_02_data_platform/milestone_2_2_candle_builder_historical.md) | 12 | Reliable OHLC generation from ticks with gap handling |
| **2.3** | [milestone_2_3_option_chain_data_store.md](phase_02_data_platform/milestone_2_3_option_chain_data_store.md) | 13 | Rich option chain analytics with derived metrics |

### Phase 3 — Feature Engineering

| Milestone | File | Tasks | Goal |
|-----------|------|-------|------|
| **3.1** | [milestone_3_1_underlying_indicators.md](phase_03_feature_engineering/milestone_3_1_underlying_indicators.md) | 17 | All technical indicators needed by downstream engines |
| **3.2** | [milestone_3_2_option_features.md](phase_03_feature_engineering/milestone_3_2_option_features.md) | 15 | Greeks-derived and option-specific features |

### Phase 4 — Market Intelligence Engines

| Milestone | File | Tasks | Goal |
|-----------|------|-------|------|
| **4.1** | [milestone_4_1_market_context_engine.md](phase_04_market_intelligence/milestone_4_1_market_context_engine.md) | 13 | Macro filter that decides if trading should be allowed |
| **4.2** | [milestone_4_2_market_regime_engine.md](phase_04_market_intelligence/milestone_4_2_market_regime_engine.md) | 12 | Classify market into trending, ranging, expanding, compressing, reversing |
| **4.3** | [milestone_4_3_market_structure_engine.md](phase_04_market_intelligence/milestone_4_3_market_structure_engine.md) | 14 | Detect HH, HL, LH, LL, BOS, CHOCH, liquidity sweeps, FVG, order blocks |
| **4.4** | [milestone_4_4_momentum_engine.md](phase_04_market_intelligence/milestone_4_4_momentum_engine.md) | 10 | Determine if price is accelerating or dying |
| **4.5** | [milestone_4_5_liquidity_engine.md](phase_04_market_intelligence/milestone_4_5_liquidity_engine.md) | 11 | Reject illiquid markets and estimate slippage |
| **4.6** | [milestone_4_6_option_intelligence_engine.md](phase_04_market_intelligence/milestone_4_6_option_intelligence_engine.md) | 14 | Transform raw option chain into actionable intelligence |

### Phase 5 — Strategy & Decision Layer

| Milestone | File | Tasks | Goal |
|-----------|------|-------|------|
| **5.1** | [milestone_5_1_strategy_interface_base.md](phase_05_strategy_decision/milestone_5_1_strategy_interface_base.md) | 12 | Plugin architecture where strategies are interchangeable |
| **5.2** | [milestone_5_2_strategy_implementations.md](phase_05_strategy_decision/milestone_5_2_strategy_implementations.md) | 12 | Multiple deterministic strategies as plugins |
| **5.3** | [milestone_5_3_strike_selection_engine.md](phase_05_strategy_decision/milestone_5_3_strike_selection_engine.md) | 14 | Score every strike and pick the optimal one |
| **5.4** | [milestone_5_4_trade_scoring_engine.md](phase_05_strategy_decision/milestone_5_4_trade_scoring_engine.md) | 10 | Weighted composite score from all engines |

### Phase 6 — Risk & Execution

| Milestone | File | Tasks | Goal |
|-----------|------|-------|------|
| **6.1** | [milestone_6_1_risk_validation_engine.md](phase_06_risk_execution/milestone_6_1_risk_validation_engine.md) | 16 | Nothing reaches execution without passing risk rules |
| **6.2** | [milestone_6_2_execution_engine.md](phase_06_risk_execution/milestone_6_2_execution_engine.md) | 14 | Reliable order placement with full state tracking |
| **6.3** | [milestone_6_3_position_management_engine.md](phase_06_risk_execution/milestone_6_3_position_management_engine.md) | 15 | Live monitoring and adaptive trade management |

### Phase 7 — AI Gateway

| Milestone | File | Tasks | Goal |
|-----------|------|-------|------|
| **7.1** | [milestone_7_1_ai_gateway_infrastructure.md](phase_07_ai_gateway/milestone_7_1_ai_gateway_infrastructure.md) | 15 | Resilient, multi-provider AI routing layer |
| **7.2** | [milestone_7_2_ai_agents.md](phase_07_ai_gateway/milestone_7_2_ai_agents.md) | 14 | Specialized AI agents for interpretation, not execution |
| **7.3** | [milestone_7_3_ai_memory_vector_store.md](phase_07_ai_gateway/milestone_7_3_ai_memory_vector_store.md) | 10 | Historical trade retrieval for pattern matching |

### Phase 8 — Learning & Optimization

| Milestone | File | Tasks | Goal |
|-----------|------|-------|------|
| **8.1** | [milestone_8_1_learning_engine.md](phase_08_learning_optimization/milestone_8_1_learning_engine.md) | 14 | Continuous improvement from every trade |
| **8.2** | [milestone_8_2_performance_analytics.md](phase_08_learning_optimization/milestone_8_2_performance_analytics.md) | 12 | Deep metrics on strategy and execution quality |

### Phase 9 — Dashboard & Operations

| Milestone | File | Tasks | Goal |
|-----------|------|-------|------|
| **9.1** | [milestone_9_1_realtime_dashboard.md](phase_09_dashboard_operations/milestone_9_1_realtime_dashboard.md) | 13 | Operational visibility for live trading |
| **9.2** | [milestone_9_2_alerting_notifications.md](phase_09_dashboard_operations/milestone_9_2_alerting_notifications.md) | 12 | Multi-channel alerting for critical events |

### Phase 10 — Testing & Quality Assurance

| Milestone | File | Tasks | Goal |
|-----------|------|-------|------|
| **10.1** | [milestone_10_1_testing_infrastructure.md](phase_10_testing_qa/milestone_10_1_testing_infrastructure.md) | 14 | Comprehensive test coverage for all engines |
| **10.2** | [milestone_10_2_paper_trading.md](phase_10_testing_qa/milestone_10_2_paper_trading.md) | 11 | Full system validation without real capital |
| **10.3** | [milestone_10_3_historical_replay.md](phase_10_testing_qa/milestone_10_3_historical_replay.md) | 10 | Validate strategies on historical data before deployment |

### Phase 11 — Live Trading & Operations

| Milestone | File | Tasks | Goal |
|-----------|------|-------|------|
| **11.1** | [milestone_11_1_live_trading_deployment.md](phase_11_live_trading/milestone_11_1_live_trading_deployment.md) | 12 | Production deployment with safety mechanisms |
| **11.2** | [milestone_11_2_monitoring_observability.md](phase_11_live_trading/milestone_11_2_monitoring_observability.md) | 12 | Full system visibility in production |
| **11.3** | [milestone_11_3_continuous_improvement.md](phase_11_live_trading/milestone_11_3_continuous_improvement.md) | 12 | System that improves from every trading session |

---

## Critical Path

```
0.1 → 0.2 → 0.3 → 0.4 → 1.1 → 1.2 → 1.3 → 2.1 → 2.2 → 3.1 → 4.1 → 4.2 → 4.3 → 5.1 → 5.4 → 6.1 → 6.2 → 10.2 → 11.1
```

**Parallelizable Groups:**
- Phase 4 engines (4.1–4.6) can be developed in parallel after Phase 3
- Phase 7 (AI Gateway) can run parallel to Phases 5–6
- Phase 8 depends on Phase 6 generating trades

---

## Key Gating Criteria

| Gate | Milestone | Criteria |
|------|-----------|----------|
| **Dev Environment Ready** | 0.1 | `make setup` works, CI passes |
| **Data Pipeline Live** | 1.3 | 10k ticks/sec ingestion, < 50ms latency |
| **Engines Integrated** | 4.6 | All 6 engines produce scores, stored in DB |
| **Strategy Scoring Works** | 5.4 | TradeScoringEngine outputs > 80 for known good setups |
| **Risk Gates Active** | 6.1 | All 12 risk checkers pass/fail correctly |
| **Execution Verified** | 6.2 | Paper trading fill rate > 95%, slippage < 3 bps |
| **Paper Trading Green** | 10.2 | 10 days paper trading, Sharpe > 1.0, DD < 5% |
| **Replay Validated** | 10.3 | Walk-forward OOS expectancy > 0 |
| **Live Deployment** | 11.1 | DeploymentChecklist PASS, Runbook complete |

---

## Technology Stack

| Layer | Technology |
|-------|------------|
| Framework | Rails 8.1.3 (API mode) |
| Database | PostgreSQL 16 + TimescaleDB |
| Broker | DhanHQ v2 (REST + WebSocket) |
| Queue | Solid Queue |
| Cache | Solid Cache (Redis) |
| Cable | Solid Cable (Redis) |
| Testing | RSpec, FactoryBot, VCR, WebMock |
| Quality | RuboCop, Brakeman, Bundler-Audit, SimpleCov |
| Monitoring | Prometheus, Grafana, Loki |
| AI | Ollama (local + cloud), pgvector |
| Deployment | Docker, GitHub Actions |

---

## Usage

Each milestone file contains:
- **Goal** — What this milestone achieves
- **Tasks** — Detailed checkbox items with acceptance criteria
- **Notes** — Implementation guidance and gotchas

To track progress:
1. Open a milestone file
2. Check off tasks as completed
3. Verify acceptance criteria
4. Move to next milestone in critical path

---

## Related Documentation

- `docs/architecture.md` — System architecture (created in Milestone 0.4)
- `docs/configuration.md` — All configuration variables (Milestone 0.2)
- `docs/database_schema.md` — ERD and table definitions (Milestone 0.3)
- `docs/broker_api.md` — DhanHQ endpoint mapping (Milestone 1.1)
- `docs/websocket.md` — WebSocket event schemas (Milestone 1.2)
- `docs/strategies.md` — Strategy entry/exit rules (Milestone 5.2)
- `docs/testing.md` — Testing strategy (Milestone 10.1)
- `docs/paper_trading.md` — Paper trading results (Milestone 10.2)
- `docs/replay.md` — Replay methodology (Milestone 10.3)
- `docs/live_trading.md` — Live trading procedures (Milestone 11.1)
- `docs/monitoring.md` — Monitoring setup (Milestone 11.2)
- `docs/continuous_improvement.md` — Improvement process (Milestone 11.3)
- `docs/runbook.md` — Operations runbook (Milestone 11.1)

---

## Contributing

1. Pick a milestone from the critical path
2. Read the milestone file completely
3. Implement tasks in order
4. Run tests: `make test`
5. Run lint: `make lint`
6. Update milestone checkboxes
7. Commit with message: `feat: complete milestone X.Y - [description]`

---

*Generated from the 35-milestone, 312-task implementation roadmap for AlgoScalperApi*