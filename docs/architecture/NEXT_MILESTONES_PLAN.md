# Next Milestones Implementation Plan

**Starting Point:** Post-architecture-assessment (2026-06-27)  
**Priority Order:** 8.1 → 5.4 → 7.3 → 10.3 → 11.2

---

## Milestone 8.1: Learning Engine (Sprint 1-2)

### Sprint 1 (Week 1): Core Learning Infrastructure

| Day | Task | Files to Create/Modify |
|-----|------|------------------------|
| 1-2 | LearningEngine + TradeRecorder interfaces | `app/engines/learning_engine.rb`, `app/engines/learning/trade_recorder.rb` |
| 3-4 | MFECalculator / MAECalculator | `app/engines/learning/calculators/mfe_calculator.rb`, `mae_calculator.rb` |
| 5 | SlippageAnalyzer | `app/engines/learning/analyzers/slippage_analyzer.rb` |
| 6-7 | RegimePerformanceAnalyzer + tests | `app/engines/learning/analyzers/regime_performance_analyzer.rb` |

### Sprint 2 (Week 2): Analysis + Reporting

| Day | Task | Files to Create/Modify |
|-----|------|------------------------|
| 1-2 | TimeOfDayAnalyzer + DeltaRangeAnalyzer | `app/engines/learning/analyzers/time_of_day_analyzer.rb`, `delta_range_analyzer.rb` |
| 3 | ExpiryDayAnalyzer | `app/engines/learning/analyzers/expiry_day_analyzer.rb` |
| 4 | StrategyExpectancyCalculator | `app/engines/learning/calculators/strategy_expectancy_calculator.rb` |
| 5 | LearningReportGenerator | `app/engines/learning/learning_report_generator.rb` |
| 6 | Solid Queue jobs | `app/jobs/learning_engine_job.rb`, `weekly_learning_report_job.rb` |
| 7 | Integration + specs | `spec/engines/learning_engine_spec.rb` |

### Hooks Required
- After trade exit: `LearningEngineJob.perform_later(trade_id)` in `ExitEngine.finalize_exit!`
- Weekly: `rails solid_queue:load_recurring` adds `weekly_learning_report`

---

## Milestone 5.4: TradeScoringEngine (Sprint 3)

| Task | Files |
|------|-------|
| TradeScoringEngine with weight config | `app/engines/trade_scoring_engine.rb` |
| ScoreAggregator | `app/engines/aggregators/score_aggregator.rb` |
| ScoreThreshold + Breakdown | `app/engines/calculators/score_threshold.rb` |
| ScoreValidator (replaces some guards) | `app/engines/validators/score_validator.rb` |
| Migration: EntryGuardPipeline → soft gates | Modify `app/services/entries/entry_guard_pipeline.rb` |
| Config: `config/trade_scoring.yml` | New file |

---

## Milestone 7.3: Vector Memory (Sprint 4-5)

| Task | Files |
|------|-------|
| pgvector migration | `db/migrate/xxx_enable_pgvector.rb` |
| vector_embeddings table | `db/migrate/xxx_create_vector_embeddings.rb` |
| EmbeddingService (Ollama local) | `app/gateway/ai/embedding_service.rb` |
| TradeEmbedder | `app/engines/learning/trade_embedder.rb` |
| VectorStore + SimilarTradeFinder | `app/engines/learning/vector_store.rb` |
| AIContextEnricher | `app/gateway/ai/ai_context_enricher.rb` |
| Background job for embeddings | `app/jobs/generate_trade_embedding_job.rb` |

---

## Milestone 10.3: Historical Replay (Sprint 6-7)

| Task | Files |
|------|-------|
| HistoricalReplayEngine | `app/engines/replay/historical_replay_engine.rb` |
| ReplaySpeedController | `app/engines/replay/replay_speed_controller.rb` |
| WalkForwardTestRunner | `app/engines/replay/walk_forward_test_runner.rb` |
| MonteCarloSimulator | `app/engines/replay/monte_carlo_simulator.rb` |
| ParameterOptimization | `app/engines/replay/parameter_optimization.rb` |
| ReplayReportGenerator | `app/engines/replay/replay_report_generator.rb` |

---

## Milestone 11.2: Observability (Sprint 8)

| Task | Files |
|------|-------|
| prometheus-client Gemfile | Add to Gemfile |
| TradingMetrics | `app/metrics/trading_metrics.rb` |
| EngineMetrics | `app/metrics/engine_metrics.rb` |
| DataMetrics | `app/metrics/data_metrics.rb` |
| RiskMetrics | `app/metrics/risk_metrics.rb` |
| Grafana dashboards JSON | `grafana/dashboards/*.json` |
| Alerting rules | `config/prometheus/alerts.yml` |

---

## Quick Start: Learning Engine Sprint 1 Day 1

```bash
# 1. Create engine directory structure
mkdir -p app/engines/learning/calculators
mkdir -p app/engines/learning/analyzers
mkdir -p app/jobs

# 2. Create LearningEngine base
cat > app/engines/learning_engine.rb << 'EOF'
# frozen_string_literal: true

module Engines
  class LearningEngine
    def self.record(trade_id)
      new.record(trade_id)
    end

    def self.analyze(time_window = :weekly)
      new.analyze(time_window)
    end

    def record(trade_id)
      # Called after every trade closes
      trade = TradeTelemetry.find(trade_id)
      return Result.failure("Trade not found") unless trade

      # Capture entry features (already in trade)
      # Capture exit features (MFE, MAE, slippage, holding time)
      # Store in learning_records
      Result.success({ recorded: true })
    rescue => e
      Result.failure(e)
    end

    def analyze(time_window)
      # Dispatch to analyzers based on window
      # Aggregate results
      # Store in learning_records
      Result.success({ analyzed: true })
    rescue => e
      Result.failure(e)
    end
  end
end
EOF

# 3. Create TradeRecorder
cat > app/engines/learning/trade_recorder.rb << 'EOF'
# frozen_string_literal: true

module Engines
  module Learning
    class TradeRecorder
      def self.capture_entry(trade_telemetry)
        # Extract all engine outputs at entry time
        # Already captured in TradeTelemetry meta
      end

      def self.capture_exit(trade_telemetry)
        # Calculate MFE, MAE from tick data
        # Calculate slippage, holding time
        # Update trade_telemetry with exit features
      end
    end
  end
end
EOF

# 4. Run tests to verify
bundle exec rspec spec/engines/learning_engine_spec.rb
```

---

## Dependencies & Blockers

| Milestone | Blockers | Mitigation |
|-----------|----------|------------|
| 8.1 Learning | None - uses existing TradeTelemetry | Start immediately |
| 5.4 Scoring | Needs 8.1 for optimal weights | Can parallelize scaffold |
| 7.3 Vector | Needs pgvector extension | Add migration first |
| 10.3 Replay | Needs 5.4 + 8.1 complete | Design in parallel |
| 11.2 Observability | None | Can start anytime |

---

## Success Metrics

| Milestone | KPI |
|-----------|-----|
| 8.1 Learning | Weekly report generated; expectancy tracked per strategy |
| 5.4 Scoring | Single score replaces 30+ guard vetoes; threshold tuning works |
| 7.3 Vector | Similar trade retrieval < 100ms; enriches AI prompts |
| 10.3 Replay | Strategy validation in < 5 min for 1 year data |
| 11.2 Observability | Grafana dashboards live; alerts on fill rate/slippage |

---

## Next Action

**Start Milestone 8.1 Sprint 1 Day 1** — Create `LearningEngine` + `TradeRecorder` interfaces and `MFECalculator`.
