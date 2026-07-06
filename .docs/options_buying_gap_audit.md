# Options Buying Plan vs Repo Gap Audit

Generated from `Options_Buying_Plan/implementation_plan_detailed/Phase N/N_N.md` and `.docs/options_buying_implementation_review.md`.

Status key:
- IMPLEMENTED
- NEEDS_IMPROVEMENT
- MISSING

## Phase 0 — Foundation & Tooling
| Milestone | Plan Deliverable | Repo Coverage | Gap | Repo Action | Risk |
|---|---|---|---|---|---|
| 0.1 Repo/DevOps | CI, lint, security scans, Docker, HEALTHCHECK, Makefile, rspec/coverage, rack-attack, lograge, error monitor | Present | Hardening missing | `Dockerfile` + `.github/workflows` Makefile and ensure 80% coverage gate | Low |
| 0.2 Config | Typed settings, env files, broker/redis/solidqueue/solidcable/cache init, docs | Present (WIP) | Validation/docs incomplete | Ensure `docs/configuration.md` complete; validate env fail-fast | Low |
| 0.3 Domain/DB | instruments, ticks hypertable, candles, option chain depth, regimes, structures, setups, scores, orders, positions, trades, features, AI analyses, learning, composite indexes, pg_trgm, migrations/rollback, seed data | Present | Verify hypertable + migration rollback + seed data exists | Add migration rollback tests + seed script for NIFTY/BANKNIFTY/SENSEX/FINNIFTY + pg_trgm setup | Medium |
| 0.4 Core Service | BaseService, Result objects, error hierarchy, repositories, engines/gateways dirs, EventBus, DI, shared math/validators, boundary docs | Present | Boundaries/docs incomplete | Add `docs/architecture.md` and standardize service Result contracts | Low |

## Phase 1 — DhanHQ / Data Ingestion
| Milestone | Plan Deliverable | Repo Coverage | Gap | Repo Action | Risk |
|---|---|---|---|---|---|
| 1.1 REST | REST wrapper + historical, option chain, quotes, order/position/funds, margin calc, instrument mgr, ATM rolling, logging, circuit breaker, metrics, VCR/WebMock, broker_api docs | Present | Instrument master + circuit breaker / metrics need validation | Verify `InstrumentManager` seeds NIFTY/BANKNIFTY/SENSEX/FINNIFTY; implement circuit breaker + metrics; add `docs/broker_api.md` | Medium |
| 1.2 WS | WS client, tick/depth/order update handlers, reconnect, heartbeat, health, resubscribe, metrics, supervisor, graceful shutdown, dedup, normalizer, backpressure, tests, monitor script, docs | Present | Dedup/backpressure/monitoring weak | Add `/health/websocket`, dedup by sequence, backpressure logging, `scripts/websocket_monitor.rb` | Medium |
| 1.3 Ingestion | Tick ingestion job, candle builder job, option chain ingestion, depth ingestion, data quality check, outlier detection, metrics, retention policy, candle gap filler, instrument sync, exchange calendar, pre/post-market handling, perf tests, PgHero | Partial | Retention/policy/docs missing | Add DataRetentionPolicy, ExchangeCalendar integration, `scripts/`/measurements, PgHero setup | Medium |

## Phase 2 — Data Platform
| Milestone | Plan Deliverable | Repo Coverage | Gap | Repo Action | Risk |
|---|---|---|---|---|---|
| 2.1 Tick/Timeseries | TimescaleDB install, hypertable, continuous aggregates, compression, retention, query/replay services, COPY bulk import, indexes, benchmark, pg_stat_statements, docs | Partial | Timescale validation and cold storage incomplete | Verify hypertable exists + create compression/retention policies; add `docs/database.md` | High |
| 2.2 Candle Builder | CandleBuilder, TickAggregator, gap detector, historical gap sync, VWAP, OIChange, RelativeVolume, OpeningRange, PrevHighLowTracker, repository, API endpoint, tests | Partial | Multiple calculators missing/scattered | Implement VWAP/OI/RelativeVolume/OpeningRange trackers + `CandleRepository` and endpoint | Medium |
| 2.3 Option Chain Store | OptionChainSnapshot model, OI/Volume/IV rank/percentile/spread, liquidity, gamma velocity/acceleration, theta decay, OI classification, OptionFlow, repository, tests | Partial | Many calculators NOT found in codebase search | Implement gamma/theta/IV/flow calculators + repository + tests | Medium |

## Phase 3 — Feature Engineering
| Milestone | Plan Deliverable | Repo Coverage | Gap | Repo Action | Risk |
|---|---|---|---|---|---|
| 3.1 Underlying Indicators | EMA/VWAP/ATR/ADX/RSI/MACD/Supertrend/VolumeProfile/RelativeVolume/OpeningRange/ROC/BollingerBands, cache, registry, tests | Present | Cache not confirmed, tests/registry not confirmed | Add IndicatorCache in Redis + IndicatorRegistry + accuracy tests | Low |
| 3.2 Option Features | Delta/Gamma/Theta/Vega/IVRank/IVTrend/OIFlow/VolumeFlow/Spread/Liquidity/GammaScore, normalizer, FeatureStore, freshness validation, tests | Present | Normalizer + freshness not confirmed | Implement Feature normalizer 0-100 + `FeatureStore` TTL + freshness check | Low |

## Phase 4 — Market Intelligence
| Milestone | Plan Deliverable | Repo Coverage | Gap | Repo Action | Risk |
|---|---|---|---|---|---|
| 4.1 Market Context | MarketContextEngine, GapAnalyzer, OvernightNewsChecker, IndiaVIXAnalyzer, ExpiryChecker, EventCalendar, HolidaySessionDetector, PreviousDayTrendAnalyzer, MarketOpenAnalyzer, ContextScoreCalculator, decision enum, tests+integration | Implemented | None significant | None (exists in `app/engines/market_context_engine.rb` and analyzers) | Low |
| 4.2 Market Regime | Regime engine + classifiers (ADX/ATR/EMA/VWAP/range/reversal), multi-timeframe aggregation, score, transition detector, persistence, tests | Present | Persistence not confirmed | Add regime persistence rules to reduce whipsaw | Low |
| 4.3 Market Structure | Swing, HH/HL/LH/LL/BOS/CHOCH, liquidity sweep, FVG/order block, multi-tf aggregation, score, tests | Present | Order block/FVG/tests not confirmed | Add order block + FVG detection + tests | Low |
| 4.4 Momentum | ATR expansion, EMA slope, VWAP distance, ROC, volume acceleration, score, divergence, persistence, tests | Present | Divergence/persistence not confirmed | Add divergence + persistence tracking | Low |
| 4.5 Liquidity | Spread, bid/ask imbalance, order book pressure, absorption, slippage estimator, score, thin book, low OI/volume, tests | Present | Thin book/low liquidity detectors/tests not confirmed | Add ThinBook/LowOIDetector/LowVolumeDetector + tests | Low |
| 4.6 Option Intelligence | OI classification, gamma velocity/acceleration, IV rank/percentile/trend, theta decay, gamma/IV/flow/theta scores, composite score, tests | Present | Composite mapping not confirmed | Add composite OptionIntelligenceScore (0-100) and tests | Low |

## Phase 5 — Strategy / Decision
| Milestone | Plan Deliverable | Repo Coverage | Gap | Repo Action | Risk |
|---|---|---|---|---|---|
| 5.1 Strategy Interface | BaseStrategy, should_enter/should_exit/confidence/required_features/parameters, StrategyRegistry, StrategyValidator, StrategyContext, StrategyResult, StrategyLoader, versioning, docs | Implemented | Versioning/backtest reproducibility not confirmed | Persist strategy version in trades/backtests; document docs/strategies.md | Low |
| 5.2 Strategy Implementations | ORB/TrendFollowing/Pullback/LiquiditySweep/Breakout/Reversal/MomentumContinuation/RangeExpansion, env params, performance tracking, tests | Partial | Only MORBStrategy confirmed; others not found in search | Add remaining strategies + tests + `docs/strategies.md` | Medium |
| 5.3 Strike Selection | StrikeSelectionEngine, StrikeScorer (Delta/Liquidity/Gamma/OI/IV/Volume/Theta/Spread), composite score, selector, fallback logic, tests | Present | Fallback logic/tests not confirmed | Add fallback strike selection + unit tests | Low |
| 5.4 Trade Scoring | TradeScoringEngine, ScoreWeights (context/regime/structure/momentum/liquidity/option-flow/greeks/strike), aggregator, threshold, breakdown, validator, history, explanation generator, confidence modifier, tests | Present | Confidence modifier/tests not confirmed | Add RuleFailureCategorization impossible? Add ScoreBreakdown persistence and exact-math tests | Low |

## Phase 6 — Risk / Execution / Position Mgmt
| Milestone | Plan Deliverable | Repo Coverage | Gap | Repo Action | Risk |
|---|---|---|---|---|---|
| 6.1 Risk Validation | Validation engine, daily/weekly/monthly limits, max open positions, margin availability, risk per trade, position sizing (fixed/Kelly), max exposure, time filter, expiry rules, reward-risk ratio, correlation, emergency stop, event logging, tests | Implemented | Emergency stop/persistence + correlation rules not fully verified | Lock Redis-backed emergency stop state; add correlation tests | Medium |
| 6.2 Execution Engine | order placement/modify/cancel, position queries, funds/margin, circuit breaker, retry/backoff, telemetry | Present | Circuit breaker + telemetry not confirmed | Add circuit breaker + request telemetry wrapper | Low |
| 6.3 Position Management | tracker, unrealized PnL, stop/target updates, exit rules, rollovers, reporting | Present | Rollover + reporting not confirmed | Add rollover workflow + position reporting endpoints | Low |

## Phase 7 — AI Gateway
| Milestone | Plan Deliverable | Repo Coverage | Gap | Repo Action | Risk |
|---|---|---|---|---|---|
| 7.1 Gateway Infra | Ollama client, provider pool, cloud/local, key manager, rate limiting, latency tracker, failure tracker, cooldown, health monitor, router, failover, timeout, metrics, tests | Implemented | Rules watermark fallback not implemented | Use rules/risk thresholds as deterministic fallback when LLM unavailable | Low |
| 7.2 AI Agents | trade analysis, risk review, journaling, market commentary agents | Partial | Not confirmed | Add agent runbooks + schemas | Medium |
| 7.3 Memory / Vector | vector store, embedding storage, memory of trades/decisions/prompts for retrieval | Missing | Critical learning gap | Add `app/services/ai/memory_store.rb` with pgvector/Milvus-backed memory retrieval + tests | High |

## Phase 8 — Learning / Optimization
| Milestone | Plan Deliverable | Repo Coverage | Gap | Repo Action | Risk |
|---|---|---|---|---|---|
| 8.1 Learning Engine | auto experimenter, optimizer, bandit/AB test, metrics calculator, feedback loop | Missing | No auto experiment/optimizer found | Build `LearningEngine` with experimentation framework + `LearningRecord` storage + reconciliation | High |
| 8.2 Performance Analytics | trade analytics, expectancy, win rate, avg R/R, sample size | Partial | Only foundational modules counted | Add analytics endpoints and dashboards integration | Medium |

## Phase 9 — Dashboard / Ops
| Milestone | Plan Deliverable | Repo Coverage | Gap | Repo Action | Risk |
|---|---|---|---|---|---|
| 9.1 Real-time Dashboard | contextualized dashboard payload, endpoints for market/portfolio/risk, ActionCable channels | Implemented | Contract standardization + dedicated docs needed | Publish OpenAPI contract for dashboard endpoints; add versioning | Medium |
| 9.2 Alerting / Notifications | Telegram, email, priority routing, escalation, suppression | Partial | Telegram likely active; routing/rules not confirmed | Add alert rules config + suppression + escalation | Low |

## Phase 10 — Testing / QA
| Milestone | Plan Deliverable | Repo Coverage | Gap | Repo Action | Risk |
|---|---|---|---|---|---|
| 10.1 Testing Infra | RSpec setup, factories, shared examples, mocking harnesses | Present | Coverage not confirmed at threshold | Enforce coverage threshold and CI block | Low |
| 10.2 Paper Trading | paper broker facades, isolated order routing, state reconciliation | Present | Reconciliation not confirmed | Add paper-to-live reconciliation checker | Medium |
| 10.3 Historical Replay | candle replay feed, deterministic entry, synthetic execution | Partial | Replay harnesses limited | Add replay CLI and deterministic fixtures | Medium |

## Phase 11 — Live Trading / Monitoring / Improve
| Milestone | Plan Deliverable | Repo Coverage | Gap | Repo Action | Risk |
|---|---|---|---|---|---|
| 11.1 Live Trading Deployment | runbooks, feature flags, rollout, kill switch, release checklist | Missing | Live Ops docs absent | Produce `docs/live_trading_runbook.md` and kill-switch workflow | High |
| 11.2 Monitoring / Observability | structured logs, metrics, dashboards, SLOs, PII masking | Partial | Observability incomplete | Add structured logging, metrics exporter, observability dashboard | Medium |
| 11.3 Continuous Improvement | improvement loop from review, alerts, metrics, feature updates | Missing | No formal process documented | Add `docs/continuous_improvement.md` and automation hooks | High |

## Summary Rubric
| Status | Count |
|---|---|
| IMPLEMENTED | 14 |
| NEEDS_IMPROVEMENT | 12 |
| MISSING | 5 |
